// G3: the Daily Sortie — tickets, one ranked run per Genesis Token, the
// score and time checks, boards and streaks.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeEnv, makeWallet, signIn, call, holdGenesis } from "./helpers.js";
import { TICKET_TTL_MS } from "../src/daily.js";

const DAY = 86400000;

/** A signed-in pilot: {wallet, token}. [seeker] gives it a Genesis Token. */
async function pilot(env, { seeker = false, name = "" } = {}) {
  const wallet = await makeWallet();
  if (seeker) holdGenesis(env, wallet.pubkey, { mint: `Gen${wallet.pubkey.slice(3)}` });
  const r = await signIn(env, wallet, { name });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { wallet, token: r.body.token };
}

/** Start a run, let [sec] pass, finish it. */
async function play(env, p, { ranked = false, won = true, points = 1500, time = 60, sec = 90, kills = 4 } = {}) {
  const s = await call(env, "POST", "/run/start", { ranked }, p.token);
  if (s.status !== 200) return s;
  env.clock += sec * 1000;
  return call(env, "POST", "/run/finish", { run_id: s.body.run_id, won, points, time, kills }, p.token);
}

test("/daily names today and when it ends; signed in it adds the pilot's numbers", async () => {
  const env = makeEnv();
  const anon = await call(env, "GET", "/daily");
  assert.equal(anon.body.day, "2026-10-08");
  assert.equal(anon.body.ends_in_sec, 12 * 3600);
  assert.equal(anon.body.me, undefined);
  const p = await pilot(env, { seeker: true });
  const me = await call(env, "GET", "/daily", undefined, p.token);
  assert.deepEqual(me.body.me, { streak: 0, ranked_left: 1, best: { ranked: null, open: null } });
});

test("a Seeker gets one ranked run a day; others get none, practice is unlimited", async () => {
  const env = makeEnv();
  const seeker = await pilot(env, { seeker: true });
  const plain = await pilot(env);
  assert.equal((await play(env, seeker, { ranked: true })).status, 200);
  const again = await call(env, "POST", "/run/start", { ranked: true }, seeker.token);
  assert.equal(again.status, 403);
  assert.equal(again.body.error, "no_attempts");
  const no = await call(env, "POST", "/run/start", { ranked: true }, plain.token);
  assert.equal(no.body.error, "not_seeker");
  for (let i = 0; i < 3; i++) assert.equal((await play(env, plain)).status, 200);
  // A new day, a new ranked run (and a new sign-in: sessions last a day).
  env.clock += DAY;
  seeker.token = (await signIn(env, seeker.wallet)).body.token;
  assert.equal((await play(env, seeker, { ranked: true })).status, 200);
});

test("a ranked ticket started and abandoned still uses the attempt", async () => {
  const env = makeEnv();
  const p = await pilot(env, { seeker: true });
  assert.equal((await call(env, "POST", "/run/start", { ranked: true }, p.token)).status, 200);
  assert.equal((await call(env, "POST", "/run/start", { ranked: true }, p.token)).body.error, "no_attempts");
});

test("bought attempts add ranked runs for that token and day", async () => {
  const env = makeEnv();
  const p = await pilot(env, { seeker: true });
  await play(env, p, { ranked: true });
  await env.DB.prepare("INSERT INTO extra_attempts (genesis_mint, day, count) VALUES (?, ?, 2)")
    .bind(`Gen${p.wallet.pubkey.slice(3)}`, "2026-10-08").run();
  assert.equal((await call(env, "GET", "/daily", undefined, p.token)).body.me.ranked_left, 2);
});

test("a run finishes once, by its own pilot, before its ticket runs out", async () => {
  const env = makeEnv();
  const a = await pilot(env);
  const b = await pilot(env);
  const s = await call(env, "POST", "/run/start", {}, a.token);
  env.clock += 90000;
  const fin = { run_id: s.body.run_id, won: true, points: 1500, time: 60, kills: 1 };
  assert.equal((await call(env, "POST", "/run/finish", fin, b.token)).body.error, "no_run");
  assert.equal((await call(env, "POST", "/run/finish", fin, a.token)).status, 200);
  assert.equal((await call(env, "POST", "/run/finish", fin, a.token)).body.error, "run_finished");
  const late = await call(env, "POST", "/run/start", {}, a.token);
  env.clock += TICKET_TTL_MS + 1000;
  assert.equal((await call(env, "POST", "/run/finish", { ...fin, run_id: late.body.run_id }, a.token)).body.error, "ticket_expired");
});

test("scores and times outside the rules are refused", async () => {
  const env = makeEnv();
  const p = await pilot(env);
  const cases = [
    [{ won: true, points: 2001 }, "bad_score"],
    [{ won: true, points: 999 }, "bad_score"],
    [{ won: false, points: 950 }, "bad_score"],
    [{ won: true, points: 1500, time: 600, sec: 60 }, "bad_time"],
    [{ won: true, points: 1500, time: 1, sec: 60 }, "bad_time"],
    [{ won: true, points: 1500.5 }, "bad_request"],
  ];
  for (const [run, code] of cases) {
    const r = await play(env, p, run);
    assert.equal(r.body.error, code, JSON.stringify(run));
  }
});

test("the wrong day is refused (a phone clock across midnight)", async () => {
  const env = makeEnv();
  const p = await pilot(env);
  const r = await call(env, "POST", "/run/start", { day: "2026-10-07" }, p.token);
  assert.equal(r.status, 409);
  assert.equal(r.body.error, "wrong_day");
});

test("boards rank each pilot's best run, ranked and open apart", async () => {
  const env = makeEnv();
  const ace = await pilot(env, { seeker: true, name: "Ace" });
  const bee = await pilot(env, { seeker: true, name: "Bee" });
  const cat = await pilot(env, { name: "Cat" });
  await play(env, ace, { ranked: true, points: 1700 });
  await play(env, bee, { ranked: true, points: 1900 });
  await play(env, cat, { points: 1999 });
  await play(env, cat, { points: 1200 });
  const ranked = await call(env, "GET", "/leaderboard?board=ranked", undefined, ace.token);
  assert.deepEqual(ranked.body.rows.map((r) => [r.rank, r.name, r.points]), [[1, "Bee", 1900], [2, "Ace", 1700]]);
  assert.deepEqual(ranked.body.me, { points: 1700, rank: 2 });
  const open = await call(env, "GET", "/leaderboard?board=open");
  assert.deepEqual(open.body.rows.map((r) => [r.name, r.points]), [["Cat", 1999]]);
  assert.equal(open.body.me, null);
});

test("finishing reports the best, the rank and the streak", async () => {
  const env = makeEnv();
  const p = await pilot(env, { seeker: true });
  const r = await play(env, p, { ranked: true, points: 1400 });
  assert.deepEqual({ ...r.body }, { board: "ranked", points: 1400, best: 1400, rank: 1, streak: 1 });
});

test("streaks count days in a row, and survive until today is over", async () => {
  const env = makeEnv();
  const p = await pilot(env);
  for (let d = 0; d < 3; d++) {
    await play(env, p);
    env.clock += DAY;
    // Sessions last a day: sign in again each day, as a player would.
    p.token = (await signIn(env, p.wallet)).body.token;
  }
  // Day 4, not played yet: the streak of 3 still stands.
  assert.equal((await call(env, "GET", "/daily", undefined, p.token)).body.me.streak, 3);
  env.clock += DAY;
  p.token = (await signIn(env, p.wallet)).body.token;
  // A day missed: back to 0.
  assert.equal((await call(env, "GET", "/daily", undefined, p.token)).body.me.streak, 0);
});

test("run routes need a session", async () => {
  const env = makeEnv();
  assert.equal((await call(env, "POST", "/run/start", {})).status, 401);
  assert.equal((await call(env, "POST", "/run/finish", {})).status, 401);
});
