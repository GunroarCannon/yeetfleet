// The Worker on localhost over an in-memory D1, for the game's headless
// checks (modules/chain/tools/chain_server_check.gd) and for poking at it:
//
//   node services/leaderboard-worker/test/dev_server.js [port]
//
// Test-only differences from the deployed Worker, all here:
// - The addon's mock wallet doesn't do Ed25519; it "signs" with the SHA-256
//   hex of the text. That stand-in is accepted here, and only here.
// - The mock wallet's key counts as a Seeker (DEV_GENESIS_OWNERS) and the
//   mainnet RPC answers "no tokens", so nothing leaves the machine.
// - The mock wallet's payments ("MockSig…") never reach a chain: asked about
//   one, the RPC answers with a transfer that pays the order being verified.
//   With DEVNET_RPC_URL set, any other signature is looked up on that RPC
//   for real (scripts/devnet_pay_check.mjs uses that).

import http from "node:http";
import { createHash } from "node:crypto";
import worker from "../src/index.js";
import { FakeD1 } from "./d1.js";
import { transferTx } from "./helpers.js";

const port = Number(process.argv[2] ?? 8787);
const MOCK_KEY = "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB";

const realVerify = crypto.subtle.verify.bind(crypto.subtle);
crypto.subtle.verify = async (alg, key, sig, data) => {
  if ((alg?.name ?? alg) === "Ed25519") {
    const stand_in = new TextEncoder().encode(createHash("sha256").update(Buffer.from(data)).digest("hex"));
    if (Buffer.from(sig).equals(Buffer.from(stand_in))) return true;
  }
  return realVerify(alg, key, sig, data);
};

const env = {
  DB: new FakeD1(),
  CLUSTER: "devnet",
  SIWS_DOMAIN: "gunroarcannon.github.io",
  SIWS_STATEMENT: "Sign in to Yeetfleet as this pilot",
  GENESIS_GROUP: "GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te",
  DEV_GENESIS_OWNERS: process.env.DEV_GENESIS_OWNERS ?? MOCK_KEY,
  SESSION_SECRET: "dev-only-secret",
  MAINNET_RPC_URL: "http://rpc.invalid",
  SKR_MINT: "J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK",
  TREASURY: "2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1",
  DEVNET_RPC_URL: process.env.DEVNET_RPC_URL || "http://devnet.invalid",
  FETCH: fakeRpc,
};
/** The order /order/verify is asking about (for the mock wallet's payments). */
let verifying = "";

async function fakeRpc(url, init) {
  const { method, params } = JSON.parse(init.body);
  const answer = (result) => new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }));
  if (method === "getTransaction") {
    const sig = String(params[0]);
    if (sig.startsWith("MockSig")) {
      const o = await env.DB.prepare("SELECT * FROM orders WHERE id = ?").bind(verifying).first();
      return answer(o ? transferTx({ from: o.pubkey, amount: o.amount, memo: `yeetfleet:${o.id}` }) : null);
    }
    if (process.env.DEVNET_RPC_URL) return fetch(url, init);
    return answer(null);
  }
  return answer({ value: [] });
}

http.createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  if (req.url.startsWith("/order/verify") && body) {
    try {
      verifying = String(JSON.parse(body.toString()).order_id ?? "");
    } catch {}
  }
  const request = new Request(`http://127.0.0.1:${port}${req.url}`, {
    method: req.method,
    headers: req.headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : body,
  });
  const out = await worker.fetch(request, env);
  res.writeHead(out.status, Object.fromEntries(out.headers));
  res.end(Buffer.from(await out.arrayBuffer()));
}).listen(port, "127.0.0.1", () => console.log(`yeetfleet dev worker on http://127.0.0.1:${port}`));
