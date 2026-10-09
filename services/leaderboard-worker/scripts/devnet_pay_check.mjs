// A real SKR payment on devnet, checked by the Worker's own code: sign in as
// a fresh pilot, take an order, pay it with dSKR from a CLI keypair through
// `spl-token transfer --with-memo`, and have /order/verify find it on chain.
// Then the same payment is tried on a second order (refused).
//
//   node scripts/devnet_pay_check.mjs [payer-keypair.json]
//   WORKER_URL=https://… node scripts/devnet_pay_check.mjs   (the deployed one)
//
// Needs the Solana CLI (spl-token) on PATH and a payer holding devnet SOL
// and dSKR (docs/solana-wallets.md says how to mint more). Spends 50 dSKR.

import { spawn, execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { makeWallet, siwsText, b64 } from "../test/helpers.js";

const PORT = 8797;
const BASE = process.env.WORKER_URL || `http://127.0.0.1:${PORT}`;
const PAYER = process.argv[2] ?? join(homedir(), ".config", "solana", "id.json");
const ITEM = "paint:skr_gold";

let fails = 0;
const expect = (ok, what) => {
  console.log(`${ok ? "  ok  " : "  FAIL"}  ${what}`);
  if (!ok) fails++;
};

async function api(method, path, body, token) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json() };
}

const server = process.env.WORKER_URL ? null : spawn(process.execPath, [new URL("../test/dev_server.js", import.meta.url).pathname.replace(/^\/(\w:)/, "$1"), String(PORT)], {
  env: { ...process.env, DEVNET_RPC_URL: "https://api.devnet.solana.com" },
  stdio: "inherit",
});
try {
  for (let i = 0; i < 40; i++) {
    try {
      if ((await fetch(BASE + "/health")).ok) break;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  const wallet = await makeWallet();
  const ch = await api("POST", "/auth/challenge", {});
  const bytes = new TextEncoder().encode(siwsText({ domain: ch.body.domain, address: wallet.pubkey, statement: ch.body.statement, ...ch.body.fields }));
  const v = await api("POST", "/auth/verify", { public_key: wallet.pubkey, signed_message: b64(bytes), signature: b64(await wallet.sign(bytes)) });
  expect(v.status === 200, "signed in as a fresh pilot");
  const token = v.body.token;

  const o = (await api("POST", "/order/new", { item: ITEM }, token)).body;
  expect(!!o.order_id, `order ${o.order_id}: ${o.price} dSKR to ${o.to}`);
  // The public devnet RPC drops requests now and then: try a few times. (A
  // try that did land would pay twice, which costs test tokens only.)
  let sig = "";
  for (let i = 0; i < 5 && !sig; i++) {
    try {
      const out = execFileSync("spl-token", [
        "transfer", o.mint, String(o.price), o.to, "--with-memo", o.memo,
        "--fund-recipient", "--allow-unfunded-recipient",
        "--owner", PAYER, "--fee-payer", PAYER, "--url", "devnet", "--output", "json",
      ], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
      sig = JSON.parse(out).signature;
    } catch (e) {
      console.log(`  (transfer try ${i + 1} failed: ${String(e.stderr ?? e.message).trim()})`);
      await new Promise((res) => setTimeout(res, 3000));
    }
  }
  expect(!!sig, `paid on devnet: ${sig}`);

  let r;
  for (let i = 0; i < 30; i++) {
    r = await api("POST", "/order/verify", { order_id: o.order_id, signature: sig }, token);
    if (r.body.error !== "tx_not_found") break;
    await new Promise((res) => setTimeout(res, 2000));
  }
  expect(r.status === 200 && r.body.owned?.includes(ITEM), `the Worker found it on chain and granted ${ITEM} (${JSON.stringify(r.body)})`);

  const o2 = (await api("POST", "/order/new", { item: "paint:skr_seeker" }, token)).body;
  const again = await api("POST", "/order/verify", { order_id: o2.order_id, signature: sig }, token);
  expect(again.body.error === "wrong_memo", `the same payment can't pay another order (${again.body.error})`);
} finally {
  server?.kill();
}
console.log(`devnet_pay_check: ${fails === 0 ? "PASS" : `FAIL (${fails})`}`);
process.exit(fails === 0 ? 0 : 1);
