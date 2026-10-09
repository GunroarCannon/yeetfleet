// SKR purchases (G4): an order, a plain SPL transfer to the treasury with
// the order's memo, then a check on chain before anything is granted.
//
//   GET  /shop          (token optional) → {cluster, mint, treasury, decimals, catalog, owned?}
//   POST /order/new     {item}           → {order_id, item, price, amount, memo, to, mint, decimals}
//   POST /order/verify  {order_id, signature} → {item, granted, owned, ranked_left?}
//
// What /order/verify checks (the pitch says the same): the transaction
// landed without an error; it carries this order's memo; the treasury's SKR
// (the configured mint) went up by at least the order's amount in it; the
// signature hasn't paid for anything before. The order belongs to the
// signed-in pilot. Who paid isn't checked: paying for a friend is fine.
//
// Tips aren't here: they go wallet to wallet and the server never holds them.

import { HttpError } from "./errors.js";
import { rpc } from "./genesis.js";
import { dayOf, rankedLeft } from "./daily.js";

export const DECIMALS = 6;
export const MEMO_PREFIX = "yeetfleet:";
const MEMO_PROGRAMS = new Set([
  "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
  "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo",
]);
// Keyless RPCs tried in turn after the configured one. Solana's own public
// devnet RPC refuses Cloudflare's addresses (HTTP 403), so it goes last.
// Mainnet should have MAINNET_RPC_URL (Helius) set.
const PUBLIC_RPCS = {
  devnet: [
    "https://solana-devnet.api.onfinality.io/public",
    "https://devnet.rpcpool.com",
    "https://solana-devnet.gateway.tatum.io",
    "https://api.devnet.solana.com",
  ],
  "mainnet-beta": ["https://api.mainnet-beta.solana.com"],
};

/**
 * What SKR buys, in whole SKR. "attempt" needs a Seeker Genesis Token and is
 * spent (one more ranked run today); the rest are owned for good.
 */
export const CATALOG = {
  extra_attempt: { price: 25, kind: "attempt" },
  "paint:skr_solana": { price: 50, kind: "paint" },
  "paint:skr_seeker": { price: 50, kind: "paint" },
  "paint:skr_gold": { price: 50, kind: "paint" },
  "trail:mint": { price: 100, kind: "trail" },
  "trail:violet": { price: 100, kind: "trail" },
  "trail:gold": { price: 100, kind: "trail" },
};

/** Not for sale: every Seeker Genesis holder owns it (the Genesis Pilot hull). */
export const GENESIS_LIVERY = "paint:skr_genesis";

/** GET /shop */
export async function shop(env, pilot) {
  const out = {
    cluster: cluster(env),
    mint: env.SKR_MINT,
    treasury: env.TREASURY,
    decimals: DECIMALS,
    catalog: Object.entries(CATALOG).map(([item, c]) => ({ item, price: c.price, kind: c.kind })),
  };
  if (pilot) out.owned = await owned(env, pilot);
  return out;
}

/** POST /order/new {item} */
export async function newOrder(env, now, pilot, b) {
  config(env);
  const item = String(b.item ?? "");
  const c = CATALOG[item];
  if (!c) throw new HttpError(400, "no_item", `Nothing called '${item}' for sale`);
  if (c.kind === "attempt" && !pilot.gm) throw new HttpError(403, "not_seeker", "Extra ranked runs need a Seeker Genesis Token");
  if (c.kind !== "attempt" && (await owned(env, pilot)).includes(item)) throw new HttpError(409, "owned", "Already yours");
  const id = [...crypto.getRandomValues(new Uint8Array(12))].map((x) => x.toString(16).padStart(2, "0")).join("");
  const amount = (BigInt(c.price) * 10n ** BigInt(DECIMALS)).toString();
  await env.DB.prepare(
    "INSERT INTO orders (id, pubkey, genesis_mint, item, amount, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(id, pilot.pk, pilot.gm ?? null, item, amount, now).run();
  return {
    order_id: id,
    item,
    price: c.price,
    amount,
    memo: MEMO_PREFIX + id,
    to: env.TREASURY,
    mint: env.SKR_MINT,
    decimals: DECIMALS,
  };
}

/** POST /order/verify {order_id, signature} */
export async function verifyOrder(env, now, pilot, b) {
  config(env);
  const order = await env.DB.prepare("SELECT * FROM orders WHERE id = ?").bind(String(b.order_id ?? "")).first();
  if (!order || order.pubkey !== pilot.pk) throw new HttpError(404, "no_order", "No such order");
  const sig = String(b.signature ?? "");
  if (!sig || sig.length > 100) throw new HttpError(400, "bad_request", "signature is required");
  if (order.paid_sig !== null) {
    // Asking again with the same payment is fine (a lost reply); another isn't.
    if (order.paid_sig !== sig) throw new HttpError(409, "order_paid", "That order is already paid");
    return granted(env, now, pilot, order.item);
  }

  const tx = await getTransaction(env, sig);
  if (!tx) throw new HttpError(404, "tx_not_found", "Not on chain yet. Ask again in a few seconds");
  if (tx.meta?.err) throw new HttpError(422, "tx_failed", "That transaction failed on chain");
  if (!memos(tx).includes(MEMO_PREFIX + order.id)) throw new HttpError(422, "wrong_memo", "That payment isn't for this order");
  const got = received(tx, env.TREASURY, env.SKR_MINT);
  if (got < BigInt(order.amount)) throw new HttpError(422, "underpaid", "The treasury didn't get the full price");

  try {
    const done = await env.DB.prepare("UPDATE orders SET paid_sig = ?, paid_at = ? WHERE id = ? AND paid_sig IS NULL")
      .bind(sig, now, order.id).run();
    if (!done.meta?.changes) throw new HttpError(409, "order_paid", "That order is already paid");
  } catch (e) {
    if (e instanceof HttpError) throw e;
    // The UNIQUE index on paid_sig: this payment already bought something.
    throw new HttpError(409, "sig_used", "That payment was already used");
  }
  const c = CATALOG[order.item];
  if (c.kind === "attempt") {
    await env.DB.prepare(
      `INSERT INTO extra_attempts (genesis_mint, day, count) VALUES (?, ?, 1)
       ON CONFLICT (genesis_mint, day) DO UPDATE SET count = count + 1`)
      .bind(order.genesis_mint, dayOf(now)).run();
  } else {
    await env.DB.prepare("INSERT OR IGNORE INTO owned (pubkey, item, order_id, granted_at) VALUES (?, ?, ?, ?)")
      .bind(pilot.pk, order.item, order.id, now).run();
  }
  return granted(env, now, pilot, order.item);
}

async function granted(env, now, pilot, item) {
  const out = { item, granted: true, owned: await owned(env, pilot) };
  if (pilot.gm) out.ranked_left = await rankedLeft(env, pilot.gm, dayOf(now));
  return out;
}

/** What [pilot] owns: bought cosmetics, and the Genesis livery with a Genesis Token. */
async function owned(env, pilot) {
  const { results } = await env.DB.prepare("SELECT item FROM owned WHERE pubkey = ? ORDER BY granted_at").bind(pilot.pk).all();
  const out = results.map((r) => r.item);
  if (pilot.gm) out.unshift(GENESIS_LIVERY);
  return out;
}

// --- Reading a transaction ---

/** Every memo in [tx], top-level and inner instructions. */
export function memos(tx) {
  const ixs = [...(tx.transaction?.message?.instructions ?? [])];
  for (const inner of tx.meta?.innerInstructions ?? []) ixs.push(...(inner.instructions ?? []));
  return ixs
    .filter((ix) => MEMO_PROGRAMS.has(ix.programId) || ix.program === "spl-memo")
    .map((ix) => (typeof ix.parsed === "string" ? ix.parsed : ""));
}

/** How much of [mint] (base units) accounts owned by [owner] gained in [tx]. */
export function received(tx, owner, mint) {
  const sum = (list) => (list ?? [])
    .filter((t) => t.owner === owner && t.mint === mint)
    .reduce((s, t) => s + BigInt(t.uiTokenAmount?.amount ?? "0"), 0n);
  return sum(tx.meta?.postTokenBalances) - sum(tx.meta?.preTokenBalances);
}

// --- Config ---

function cluster(env) {
  return env.CLUSTER === "mainnet-beta" ? "mainnet-beta" : "devnet";
}

function rpcUrls(env) {
  const own = cluster(env) === "mainnet-beta" ? env.MAINNET_RPC_URL : env.DEVNET_RPC_URL;
  return [...(own ? [own] : []), ...PUBLIC_RPCS[cluster(env)]];
}

/** The transaction from the first RPC that answers (null: not landed yet). */
async function getTransaction(env, sig) {
  const params = [sig, { encoding: "jsonParsed", commitment: "confirmed", maxSupportedTransactionVersion: 0 }];
  let last = null;
  for (const url of rpcUrls(env)) {
    try {
      return await rpc(url, "getTransaction", params, env.FETCH ?? fetch);
    } catch (e) {
      last = e;
    }
  }
  throw new HttpError(502, "rpc_error", `Couldn't ask Solana: ${last?.message}`);
}

function config(env) {
  if (!env.SKR_MINT || !env.TREASURY) throw new HttpError(500, "misconfigured", "SKR_MINT and TREASURY must be set");
}
