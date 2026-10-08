// Yeetfleet's leaderboard Worker (Cloudflare Workers + D1).
//
// Auth (G2): the game asks for a challenge, has the wallet sign it in one
// Sign-In-With-Solana prompt, and trades the signed message for a session
// token. Sign-in also checks the Seeker Genesis Token: ranked play is keyed
// by it (one Seeker, one ranked pilot).
//
//   POST /auth/challenge                 → {domain, statement, fields}
//   POST /auth/verify  {public_key, signed_message, signature, name?}
//                                        → {token, expires_at, pilot}
//   GET  /me           (Bearer token)    → {pilot}
//
// Environment: DB (D1), SIWS_DOMAIN, SIWS_STATEMENT, GENESIS_GROUP, CLUSTER,
// secrets SESSION_SECRET and MAINNET_RPC_URL (a Helius URL; the public RPC
// otherwise). DEV_GENESIS_OWNERS (comma-separated keys counted as Seekers)
// is honoured off mainnet only, for testing ranked play on devnet.

import { isPublicKey } from "./base58.js";
import { parse, verify, fromBase64 } from "./siws.js";
import * as session from "./session.js";
import { genesisMint } from "./genesis.js";

export const NONCE_TTL_MS = 5 * 60 * 1000;
export const SESSION_TTL_SEC = 24 * 60 * 60;
export const NAME_MAX = 20;
const PUBLIC_MAINNET_RPC = "https://api.mainnet-beta.solana.com";

export default {
  /** @param {Request} request */
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.code, message: e.message }, e.status);
      console.error(e);
      return json({ error: "server_error", message: "Something broke on the server" }, 500);
    }
  },
};

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function route(request, env) {
  const url = new URL(request.url);
  const key = `${request.method} ${url.pathname.replace(/\/+$/, "") || "/"}`;
  switch (key) {
    case "GET /":
    case "GET /health":
      return json({ ok: true, cluster: env.CLUSTER ?? "devnet" });
    case "POST /auth/challenge":
      return json(await challenge(env));
    case "POST /auth/verify":
      return json(await signIn(env, await body(request)));
    case "GET /me":
      return json({ pilot: await pilotOf(env, (await requirePilot(request, env)).pk) });
  }
  throw new HttpError(404, "not_found", `No route ${key}`);
}

// --- Auth ---

/** A fresh one-time nonce, and the SIWS fields for the game to pass to the wallet. */
async function challenge(env) {
  const t = now(env);
  const nonce = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
  // Old nonces go as new ones come: the table stays small without a cron.
  await env.DB.prepare("DELETE FROM nonces WHERE issued_at < ?").bind(t - NONCE_TTL_MS * 4).run();
  await env.DB.prepare("INSERT INTO nonces (nonce, issued_at) VALUES (?, ?)").bind(nonce, t).run();
  return {
    domain: env.SIWS_DOMAIN,
    statement: env.SIWS_STATEMENT ?? "",
    fields: {
      nonce,
      issuedAt: new Date(t).toISOString(),
      expirationTime: new Date(t + NONCE_TTL_MS).toISOString(),
    },
  };
}

/** Check a signed SIWS message and open a session. */
async function signIn(env, b) {
  if (!env.SESSION_SECRET) throw new HttpError(500, "misconfigured", "SESSION_SECRET is not set");
  const pk = b.public_key;
  if (!isPublicKey(pk)) throw new HttpError(400, "bad_request", "public_key is not a Solana address");
  const msgBytes = fromBase64(String(b.signed_message ?? ""));
  const sig = fromBase64(String(b.signature ?? ""));
  if (!msgBytes || !sig) throw new HttpError(400, "bad_request", "signed_message and signature must be base64");
  const msg = parse(new TextDecoder().decode(msgBytes));
  if (!msg) throw new HttpError(400, "bad_message", "Not a Sign-In-With-Solana message");
  if (msg.domain !== env.SIWS_DOMAIN) throw new HttpError(401, "wrong_domain", `Signed for ${msg.domain}`);
  if (msg.address !== pk) throw new HttpError(401, "wrong_address", "Signed by another account");
  if (!(await verify(pk, msgBytes, sig))) throw new HttpError(401, "bad_signature", "The signature doesn't match");
  const t = now(env);
  if (msg.expirationTime && Date.parse(msg.expirationTime) < t) throw new HttpError(401, "expired", "The sign-in expired");
  // One use per nonce, and only while fresh: a captured sign-in can't be replayed.
  const used = await env.DB.prepare("UPDATE nonces SET used = 1 WHERE nonce = ? AND used = 0 AND issued_at >= ?")
    .bind(msg.nonce ?? "", t - NONCE_TTL_MS).run();
  if (!used.meta?.changes) throw new HttpError(401, "bad_nonce", "Unknown, used or expired nonce");

  const before = await env.DB.prepare("SELECT * FROM pilots WHERE pubkey = ?").bind(pk).first();
  let gm = before?.genesis_mint ?? null;
  let checked = true;
  try {
    gm = await findGenesis(env, pk);
  } catch (e) {
    // The RPC is down: keep what we knew. Sign-in itself still works.
    console.warn("genesis check failed", e.message);
    checked = false;
  }
  const name = cleanName(b.name) || before?.name || "";
  await env.DB.prepare(
    `INSERT INTO pilots (pubkey, name, genesis_mint, created_at, last_seen) VALUES (?1, ?2, ?3, ?4, ?4)
     ON CONFLICT (pubkey) DO UPDATE SET name = ?2, genesis_mint = ?3, last_seen = ?4`)
    .bind(pk, name, gm, t).run();
  const token = await session.issue({ pk, gm }, env.SESSION_SECRET, SESSION_TTL_SEC, t);
  return {
    token,
    expires_at: new Date(t + SESSION_TTL_SEC * 1000).toISOString(),
    expires_in: SESSION_TTL_SEC,
    pilot: { ...(await pilotOf(env, pk)), genesis_checked: checked },
  };
}

async function findGenesis(env, owner) {
  const dev = (env.CLUSTER !== "mainnet-beta" ? env.DEV_GENESIS_OWNERS ?? "" : "").split(",").map((s) => s.trim());
  if (dev.includes(owner)) return `dev:${owner}`;
  return genesisMint(owner, {
    rpcUrl: env.MAINNET_RPC_URL || PUBLIC_MAINNET_RPC,
    group: env.GENESIS_GROUP,
    fetchFn: env.FETCH ?? fetch,
  });
}

/** The session's pilot, or a 401. */
export async function requirePilot(request, env) {
  const auth = request.headers.get("authorization") ?? "";
  const p = await session.read(auth.replace(/^Bearer\s+/i, ""), env.SESSION_SECRET, now(env));
  if (!p) throw new HttpError(401, "no_session", "Sign in first");
  return p;
}

async function pilotOf(env, pk) {
  const row = await env.DB.prepare("SELECT * FROM pilots WHERE pubkey = ?").bind(pk).first();
  if (!row) throw new HttpError(404, "no_pilot", "Unknown pilot");
  return { public_key: row.pubkey, name: row.name, seeker: row.genesis_mint !== null };
}

/** Printable, trimmed, at most NAME_MAX characters. */
export function cleanName(name) {
  if (typeof name !== "string") return "";
  return [...name.replace(/[\p{C}]/gu, "").trim()].slice(0, NAME_MAX).join("");
}

// --- Plumbing ---

function now(env) {
  return env.NOW ? env.NOW() : Date.now();
}

async function body(request) {
  try {
    const b = await request.json();
    if (b && typeof b === "object") return b;
  } catch {}
  throw new HttpError(400, "bad_request", "Send a JSON object");
}

export function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
