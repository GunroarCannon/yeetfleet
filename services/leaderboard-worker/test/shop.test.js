// G4: SKR orders — an order, a transfer with its memo, a check on chain,
// then the grant (an extra ranked run, or a cosmetic kept for good).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeEnv, makeWallet, signIn, call, holdGenesis, transferTx, arm, MINT, TREASURY } from "./helpers.js";
import { memos, received } from "../src/shop.js";

async function pilot(env, { seeker = false } = {}) {
  const wallet = await makeWallet();
  if (seeker) holdGenesis(env, wallet.pubkey, { mint: `Gen${wallet.pubkey.slice(3)}` });
  const r = await signIn(env, wallet);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { wallet, token: r.body.token };
}

/** Script getTransaction: signature → transaction (missing: not landed yet). */
function chain(env) {
  const txs = {};
  env.rpc.on("getTransaction", (p) => txs[p[0]] ?? null);
  return txs;
}

async function order(env, p, item) {
  const o = await call(env, "POST", "/order/new", { item }, p.token);
  assert.equal(o.status, 200, JSON.stringify(o.body));
  return o.body;
}

const verify = (env, p, order_id, signature) => call(env, "POST", "/order/verify", { order_id, signature }, p.token);

test("/shop lists the catalog, the mint and the treasury; signed in, what's owned", async () => {
  const env = makeEnv();
  const anon = await call(env, "GET", "/shop");
  assert.equal(anon.body.mint, MINT);
  assert.equal(anon.body.treasury, TREASURY);
  assert.equal(anon.body.catalog.find((c) => c.item === "extra_attempt").price, 25);
  assert.equal(anon.body.owned, undefined);
  const p = await pilot(env);
  assert.deepEqual((await call(env, "GET", "/shop", undefined, p.token)).body.owned, []);
});

test("a Genesis holder owns the Genesis livery; nobody can buy it", async () => {
  const env = makeEnv();
  const seeker = await pilot(env, { seeker: true });
  const plain = await pilot(env);
  assert.deepEqual((await call(env, "GET", "/shop", undefined, seeker.token)).body.owned, ["paint:skr_genesis"]);
  assert.deepEqual((await call(env, "GET", "/shop", undefined, plain.token)).body.owned, []);
  assert.equal((await call(env, "POST", "/order/new", { item: "paint:skr_genesis" }, plain.token)).body.error, "no_item");
});

test("an order names the amount, the memo and where to pay", async () => {
  const env = makeEnv();
  const p = await pilot(env);
  const o = await order(env, p, "paint:skr_gold");
  assert.equal(o.amount, "50000000");
  assert.equal(o.to, TREASURY);
  assert.equal(o.mint, MINT);
  assert.equal(o.memo, `yeetfleet:${o.order_id}`);
  assert.equal((await call(env, "POST", "/order/new", { item: "rocket" }, p.token)).body.error, "no_item");
  assert.equal((await call(env, "POST", "/order/new", { item: "extra_attempt" }, p.token)).body.error, "not_seeker");
  assert.equal((await call(env, "POST", "/order/new", { item: "paint:skr_gold" })).status, 401);
});

test("a paid cosmetic is owned for good, and can't be bought twice", async () => {
  const env = makeEnv();
  const txs = chain(env);
  const p = await pilot(env);
  const o = await order(env, p, "trail:mint");
  txs.S1 = transferTx({ from: p.wallet.pubkey, amount: o.amount, memo: o.memo });
  const v = await verify(env, p, o.order_id, "S1");
  assert.equal(v.status, 200, JSON.stringify(v.body));
  assert.deepEqual(v.body.owned, ["trail:mint"]);
  // A lost reply: asking again with the same payment answers the same.
  assert.equal((await verify(env, p, o.order_id, "S1")).status, 200);
  assert.equal((await call(env, "POST", "/order/new", { item: "trail:mint" }, p.token)).body.error, "owned");
  assert.deepEqual((await call(env, "GET", "/shop", undefined, p.token)).body.owned, ["trail:mint"]);
});

test("an extra attempt adds a ranked run today", async () => {
  const env = makeEnv();
  const txs = chain(env);
  const p = await pilot(env, { seeker: true });
  const t = await call(env, "POST", "/run/start", { ranked: true }, p.token);
  assert.equal((await arm(env, p.wallet, t.body, p.token)).status, 200);
  assert.equal((await call(env, "GET", "/daily", undefined, p.token)).body.me.ranked_left, 0);
  const o = await order(env, p, "extra_attempt");
  txs.S2 = transferTx({ from: p.wallet.pubkey, amount: o.amount, memo: o.memo, innerMemo: true });
  const v = await verify(env, p, o.order_id, "S2");
  assert.equal(v.status, 200, JSON.stringify(v.body));
  assert.equal(v.body.ranked_left, 1);
  assert.equal((await call(env, "POST", "/run/start", { ranked: true }, p.token)).status, 200);
});

test("payments that don't match the order grant nothing", async () => {
  const env = makeEnv();
  const txs = chain(env);
  const p = await pilot(env);
  const o = await order(env, p, "paint:skr_solana");
  const other = await makeWallet();
  const from = p.wallet.pubkey;
  txs.short = transferTx({ from, amount: 49000000n, memo: o.memo });
  txs.memo = transferTx({ from, amount: o.amount, memo: "yeetfleet:someone-else" });
  txs.mint = transferTx({ from, amount: o.amount, memo: o.memo, mint: "So11111111111111111111111111111111111111112" });
  txs.dest = transferTx({ from, amount: o.amount, memo: o.memo, to: other.pubkey });
  txs.failed = transferTx({ from, amount: o.amount, memo: o.memo, err: { InstructionError: [0, "Custom"] } });
  const cases = [["short", "underpaid"], ["memo", "wrong_memo"], ["mint", "underpaid"], ["dest", "underpaid"],
    ["failed", "tx_failed"], ["nowhere", "tx_not_found"]];
  for (const [sig, code] of cases) {
    assert.equal((await verify(env, p, o.order_id, sig)).body.error, code, sig);
  }
  assert.deepEqual((await call(env, "GET", "/shop", undefined, p.token)).body.owned, []);
});

test("one payment buys one thing; orders are the pilot's own", async () => {
  const env = makeEnv();
  const txs = chain(env);
  const a = await pilot(env);
  const b = await pilot(env);
  const o1 = await order(env, a, "paint:skr_gold");
  txs.S = transferTx({ from: a.wallet.pubkey, amount: o1.amount, memo: o1.memo });
  assert.equal((await verify(env, b, o1.order_id, "S")).body.error, "no_order");
  assert.equal((await verify(env, a, o1.order_id, "S")).status, 200);
  // The same signature for a second order: its memo is the first order's.
  const o2 = await order(env, a, "paint:skr_seeker");
  assert.equal((await verify(env, a, o2.order_id, "S")).body.error, "wrong_memo");
  // A paid order can't take another payment.
  txs.T = transferTx({ from: a.wallet.pubkey, amount: o1.amount, memo: o1.memo });
  assert.equal((await verify(env, a, o1.order_id, "T")).body.error, "order_paid");
});

test("a payment's signature can't be reused across orders", async () => {
  const env = makeEnv();
  const txs = chain(env);
  const p = await pilot(env);
  const o1 = await order(env, p, "paint:skr_gold");
  const o2 = await order(env, p, "paint:skr_seeker");
  // One transaction with both memos and enough for both: still one purchase.
  const tx = transferTx({ from: p.wallet.pubkey, amount: 100000000n, memo: o1.memo });
  tx.transaction.message.instructions.push({ program: "spl-memo", programId: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", parsed: o2.memo });
  txs.both = tx;
  assert.equal((await verify(env, p, o1.order_id, "both")).status, 200);
  assert.equal((await verify(env, p, o2.order_id, "both")).body.error, "sig_used");
});

test("the RPC being down is a 502, not a grant", async () => {
  const env = makeEnv();
  const p = await pilot(env);
  const o = await order(env, p, "trail:gold");
  env.rpc.down = true;
  const r = await verify(env, p, o.order_id, "S");
  assert.equal(r.status, 502);
  assert.equal(r.body.error, "rpc_error");
});

test("reading a transaction: memos and what the treasury gained", () => {
  const tx = transferTx({ from: "A", amount: 25000000n, memo: "yeetfleet:x" });
  assert.deepEqual(memos(tx), ["yeetfleet:x"]);
  assert.equal(received(tx, TREASURY, MINT), 25000000n);
  assert.equal(received(tx, "A", MINT), -25000000n);
});
