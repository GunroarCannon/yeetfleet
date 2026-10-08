// G2: sign-in with a server nonce, the Genesis Token check, session tokens.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeEnv, makeWallet, signIn, call, holdGenesis, DOMAIN } from "./helpers.js";
import { NONCE_TTL_MS, SESSION_TTL_SEC, cleanName } from "../src/index.js";
import { parse } from "../src/siws.js";
import { encode, decode, isPublicKey } from "../src/base58.js";

test("base58 round-trips keys, leading zeros included", () => {
  const bytes = new Uint8Array(32).fill(7);
  bytes[0] = 0;
  assert.deepEqual(decode(encode(bytes)), bytes);
  assert.ok(isPublicKey("GE7bEoKnVEkPQ7U7sQswPqq2AbZfNWEgMxcQiYjyHLdK"));
  assert.ok(!isPublicKey("not-a-key"));
  assert.ok(!isPublicKey("11111111111111111111111111111111111111111111111"));
});

test("SIWS parse reads the header, statement and fields", () => {
  const m = parse("a.io wants you to sign in with your Solana account:\nKEY\n\nHello there\n\nNonce: abc12345\nIssued At: 2026-10-08T12:00:00Z");
  assert.equal(m.domain, "a.io");
  assert.equal(m.address, "KEY");
  assert.equal(m.statement, "Hello there");
  assert.equal(m.nonce, "abc12345");
  assert.equal(m.issuedAt, "2026-10-08T12:00:00Z");
  assert.equal(parse("hello"), null);
});

test("challenge hands out the domain and a fresh nonce each time", async () => {
  const env = makeEnv();
  const a = await call(env, "POST", "/auth/challenge", {});
  const b = await call(env, "POST", "/auth/challenge", {});
  assert.equal(a.status, 200);
  assert.equal(a.body.domain, DOMAIN);
  assert.match(a.body.fields.nonce, /^[0-9a-f]{32}$/);
  assert.notEqual(a.body.fields.nonce, b.body.fields.nonce);
  assert.equal(Date.parse(a.body.fields.expirationTime) - Date.parse(a.body.fields.issuedAt), NONCE_TTL_MS);
});

test("a good sign-in opens a session; /me knows the pilot", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  const r = await signIn(env, w, { name: "  Ace\u0000 Pilot  " });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.pilot.public_key, w.pubkey);
  assert.equal(r.body.pilot.name, "Ace Pilot");
  assert.equal(r.body.pilot.seeker, false);
  const me = await call(env, "GET", "/me", undefined, r.body.token);
  assert.equal(me.status, 200);
  assert.equal(me.body.pilot.public_key, w.pubkey);
});

test("a nonce works once: a captured sign-in can't be replayed", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  let captured;
  const first = await signIn(env, w, { tamper: (f) => (captured = f) });
  assert.equal(first.status, 200);
  const again = await signIn(env, w, { tamper: () => captured });
  assert.equal(again.status, 401);
  assert.equal(again.body.error, "bad_nonce");
});

test("refused: made-up nonce, stale nonce, wrong domain, wrong signer, other address", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  const thief = await makeWallet();
  const cases = [
    [{ tamper: (f) => ({ ...f, nonce: "deadbeefdeadbeef" }) }, "bad_nonce"],
    [{ tamper: (f) => ({ ...f, domain: "evil.example" }) }, "wrong_domain"],
    [{ signer: thief }, "bad_signature"],
    [{ tamper: (f) => ({ ...f, address: thief.pubkey }) }, "wrong_address"],
  ];
  for (const [opts, code] of cases) {
    const r = await signIn(env, w, opts);
    assert.equal(r.status, 401, code);
    assert.equal(r.body.error, code);
  }
  // A nonce taken, then signed after it went stale.
  const ch = await call(env, "POST", "/auth/challenge", {});
  env.clock += NONCE_TTL_MS + 1000;
  const late = await signIn(env, w, { tamper: (f) => ({ ...f, ...ch.body.fields }) });
  assert.equal(late.status, 401);
  assert.ok(["expired", "bad_nonce"].includes(late.body.error));
});

test("garbage input is a 400, not a crash", async () => {
  const env = makeEnv();
  const r1 = await call(env, "POST", "/auth/verify", { public_key: "nope" });
  assert.equal(r1.status, 400);
  const r2 = await call(env, "POST", "/auth/verify", { public_key: "GE7bEoKnVEkPQ7U7sQswPqq2AbZfNWEgMxcQiYjyHLdK", signed_message: "%%%", signature: "%%%" });
  assert.equal(r2.status, 400);
  const r3 = await call(env, "GET", "/nowhere");
  assert.equal(r3.status, 404);
});

test("a Seeker Genesis Token makes the pilot a Seeker", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  holdGenesis(env, w.pubkey);
  const r = await signIn(env, w);
  assert.equal(r.status, 200);
  assert.equal(r.body.pilot.seeker, true);
});

test("a token from another group doesn't count", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  holdGenesis(env, w.pubkey, { group: "FakeGroup1111111111111111111111111111111111" });
  const r = await signIn(env, w);
  assert.equal(r.body.pilot.seeker, false);
});

test("RPC down: sign-in still works and keeps the last Genesis answer", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  holdGenesis(env, w.pubkey);
  assert.equal((await signIn(env, w)).body.pilot.seeker, true);
  env.rpc.down = true;
  const r = await signIn(env, w);
  assert.equal(r.status, 200);
  assert.equal(r.body.pilot.seeker, true);
  assert.equal(r.body.pilot.genesis_checked, false);
});

test("DEV_GENESIS_OWNERS counts as a Seeker on devnet only", async () => {
  const w = await makeWallet();
  const dev = makeEnv({ DEV_GENESIS_OWNERS: `x, ${w.pubkey}` });
  assert.equal((await signIn(dev, w)).body.pilot.seeker, true);
  const main = makeEnv({ DEV_GENESIS_OWNERS: w.pubkey, CLUSTER: "mainnet-beta" });
  assert.equal((await signIn(main, w)).body.pilot.seeker, false);
});

test("sessions expire, and forged or foreign tokens are refused", async () => {
  const env = makeEnv();
  const w = await makeWallet();
  const { token } = (await signIn(env, w)).body;
  const [payload, mac] = token.split(".");
  assert.equal((await call(env, "GET", "/me", undefined, `${payload}x.${mac}`)).status, 401);
  assert.equal((await call(env, "GET", "/me", undefined, "junk")).status, 401);
  assert.equal((await call(env, "GET", "/me")).status, 401);
  const other = makeEnv({ SESSION_SECRET: "another" });
  assert.equal((await call(other, "GET", "/me", undefined, token)).status, 401);
  env.clock += SESSION_TTL_SEC * 1000 + 1;
  assert.equal((await call(env, "GET", "/me", undefined, token)).status, 401);
});

test("no SESSION_SECRET: sign-in refuses rather than minting weak tokens", async () => {
  const env = makeEnv({ SESSION_SECRET: "" });
  const r = await signIn(env, await makeWallet());
  assert.equal(r.status, 500);
  assert.equal(r.body.error, "misconfigured");
});

test("names are trimmed, stripped of control characters and capped", () => {
  assert.equal(cleanName("  hi​\n "), "hi");
  assert.equal(cleanName("x".repeat(50)).length, 20);
  assert.equal(cleanName(42), "");
});
