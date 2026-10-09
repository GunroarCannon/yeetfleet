// Shared test kit: a Worker env on the fake D1, a fake RPC, real Ed25519
// wallets, and the SIWS text a wallet would sign.

import worker from "../src/index.js";
import { encode } from "../src/base58.js";
import { FakeD1 } from "./d1.js";

export const DOMAIN = "gunroarcannon.github.io";
export const GROUP = "GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te";
export const MINT = "J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK";
export const TREASURY = "2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1";

/** A Worker env with a clock the test moves and an RPC the test scripts. */
export function makeEnv(extra = {}) {
  const env = {
    DB: new FakeD1(),
    SIWS_DOMAIN: DOMAIN,
    SIWS_STATEMENT: "Sign in to Yeetfleet as this pilot",
    GENESIS_GROUP: GROUP,
    CLUSTER: "devnet",
    SKR_MINT: MINT,
    TREASURY,
    SESSION_SECRET: "test-secret",
    MAINNET_RPC_URL: "https://rpc.test",
    clock: Date.parse("2026-10-08T12:00:00Z"),
    rpc: new FakeRpc(),
    ...extra,
  };
  env.NOW = () => env.clock;
  env.FETCH = (url, init) => env.rpc.handle(url, init);
  return env;
}

/** Answers JSON-RPC from scripted handlers: rpc.on("method", (params) => result). */
export class FakeRpc {
  constructor() {
    this.handlers = {};
    this.calls = [];
    this.down = false;
  }

  on(method, fn) {
    this.handlers[method] = fn;
  }

  async handle(_url, init) {
    if (this.down) throw new Error("connection refused");
    const { method, params } = JSON.parse(init.body);
    this.calls.push(method);
    const fn = this.handlers[method];
    const result = fn ? fn(params) : { value: [] };
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), { headers: { "content-type": "application/json" } });
  }
}

/** A request to the Worker. */
export async function call(env, method, path, body, token) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await worker.fetch(new Request(`https://w.test${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }), env);
  return { status: res.status, body: await res.json() };
}

/** A real Ed25519 wallet: its base58 key and a signer. */
export async function makeWallet() {
  const kp = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
  return {
    pubkey: encode(raw),
    sign: async (bytes) => new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, kp.privateKey, bytes)),
  };
}

/** The SIWS text a wallet signs (same layout as the addon's mock). */
export function siwsText({ domain, address, statement, nonce, issuedAt, expirationTime }) {
  let t = `${domain} wants you to sign in with your Solana account:\n${address}`;
  if (statement) t += `\n\n${statement}`;
  const lines = [];
  if (nonce) lines.push(`Nonce: ${nonce}`);
  if (issuedAt) lines.push(`Issued At: ${issuedAt}`);
  if (expirationTime) lines.push(`Expiration Time: ${expirationTime}`);
  if (lines.length) t += `\n\n${lines.join("\n")}`;
  return t;
}

export const b64 = (bytes) => btoa(String.fromCharCode(...bytes));

/** Challenge → wallet signs → verify, as the game does. Overrides tamper with a step. */
export async function signIn(env, wallet, { tamper = (f) => f, name, signer } = {}) {
  const ch = await call(env, "POST", "/auth/challenge", {});
  const f = tamper({ domain: ch.body.domain, address: wallet.pubkey, statement: ch.body.statement, ...ch.body.fields });
  const bytes = new TextEncoder().encode(siwsText(f));
  const sig = await (signer ?? wallet).sign(bytes);
  return call(env, "POST", "/auth/verify", { public_key: wallet.pubkey, signed_message: b64(bytes), signature: b64(sig), name });
}

/** Script the RPC so [owner] holds a Genesis Token (or a look-alike). */
export function holdGenesis(env, owner, { mint = "GenesisMint111111111111111111111111111111111", group = GROUP } = {}) {
  env.rpc.on("getTokenAccountsByOwner", (p) => ({
    value: p[0] === owner ? [{ account: { data: { parsed: { info: { mint, tokenAmount: { amount: "1", decimals: 0 } } } } } }] : [],
  }));
  env.rpc.on("getMultipleAccounts", (p) => ({
    value: p[0].map((m) => ({
      owner: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
      data: { parsed: { info: { extensions: [{ extension: "tokenGroupMember", state: { group, mint: m, memberNumber: 7 } }] } } },
    })),
  }));
  return mint;
}

/**
 * A landed SKR transfer as getTransaction (jsonParsed) shows it: [from] pays
 * [amount] base units of [mint] to [to], with [memo] (in an inner
 * instruction when [innerMemo]). [err] makes it a failed one.
 */
export function transferTx({ from, to = TREASURY, amount, mint = MINT, memo, err = null, innerMemo = false }) {
  const memoIx = { program: "spl-memo", programId: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", parsed: memo };
  const bal = (owner, amt, idx) => ({ accountIndex: idx, mint, owner, uiTokenAmount: { amount: String(amt), decimals: 6 } });
  return {
    slot: 1234,
    meta: {
      err,
      preTokenBalances: [bal(from, 1000000000n, 1), bal(to, 5000000n, 2)],
      postTokenBalances: [bal(from, 1000000000n - BigInt(amount), 1), bal(to, 5000000n + BigInt(amount), 2)],
      innerInstructions: innerMemo ? [{ index: 0, instructions: [memoIx] }] : [],
    },
    transaction: {
      signatures: ["sig"],
      message: {
        accountKeys: [{ pubkey: from, signer: true }],
        instructions: [
          { program: "spl-token", programId: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", parsed: { type: "transferChecked" } },
          ...(innerMemo ? [] : [memoIx]),
        ],
      },
    },
  };
}
