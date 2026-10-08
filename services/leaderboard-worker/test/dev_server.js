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

import http from "node:http";
import { createHash } from "node:crypto";
import worker from "../src/index.js";
import { FakeD1 } from "./d1.js";

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
  FETCH: async () => new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result: { value: [] } })),
};

http.createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  const request = new Request(`http://127.0.0.1:${port}${req.url}`, {
    method: req.method,
    headers: req.headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : body,
  });
  const out = await worker.fetch(request, env);
  res.writeHead(out.status, Object.fromEntries(out.headers));
  res.end(Buffer.from(await out.arrayBuffer()));
}).listen(port, "127.0.0.1", () => console.log(`yeetfleet dev worker on http://127.0.0.1:${port}`));
