// The Daily Sortie (G3): one level per UTC day, the same for every pilot.
// Ranked runs need a Seeker Genesis Token and are one per token per day
// (plus attempts bought with SKR, G4); practice runs are unlimited and go on
// the open board.
//
// What is checked, and what isn't (the pitch says the same): a run needs a
// ticket from this server; it can be finished once, within TICKET_TTL_MS;
// its claimed time must fit inside the time the ticket was open; its points
// must fit the scoring rule's range (a win 1000–2000, a loss under 1000).
// The run itself is played on the phone and isn't replayed here.

import { HttpError } from "./errors.js";

export const TICKET_TTL_MS = 45 * 60 * 1000;
export const MIN_RUN_SEC = 3;
/** A win scores WIN_BASE plus up to WIN_BASE more for how well it went; a loss scores under LOSS_MAX. */
export const WIN_BASE = 1000;
export const LOSS_MAX = 900;
/** Seconds of clock difference forgiven between the phone and the server. */
const SLACK_SEC = 5;
const BOARD_SIZE = 50;

/** YYYY-MM-DD of [ms] in UTC. */
export function dayOf(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function prevDay(day) {
  return dayOf(Date.parse(`${day}T00:00:00Z`) - 86400000);
}

/** GET /daily: today, and with a session the pilot's streak and ranked attempts left. */
export async function today(env, now, pilot) {
  const day = dayOf(now);
  const out = { day, ends_in_sec: Math.ceil((Date.parse(`${day}T00:00:00Z`) + 86400000 - now) / 1000) };
  if (pilot) {
    out.me = {
      streak: await streak(env, pilot.pk, day),
      ranked_left: pilot.gm ? await rankedLeft(env, pilot.gm, day) : 0,
      best: {
        ranked: await bestOf(env, pilot.pk, day, 1),
        open: await bestOf(env, pilot.pk, day, 0),
      },
    };
  }
  return out;
}

/** POST /run/start {day, ranked}: a ticket for one run. */
export async function start(env, now, pilot, b) {
  const day = dayOf(now);
  if (b.day !== undefined && b.day !== day) throw new HttpError(409, "wrong_day", `Today is ${day}`);
  const ranked = b.ranked === true;
  if (ranked) {
    if (!pilot.gm) throw new HttpError(403, "not_seeker", "Ranked runs need a Seeker Genesis Token");
    if ((await rankedLeft(env, pilot.gm, day)) <= 0) throw new HttpError(403, "no_attempts", "No ranked runs left today");
  }
  const id = [...crypto.getRandomValues(new Uint8Array(16))].map((x) => x.toString(16).padStart(2, "0")).join("");
  await env.DB.prepare("INSERT INTO runs (id, pubkey, genesis_mint, day, ranked, started_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(id, pilot.pk, ranked ? pilot.gm : null, day, ranked ? 1 : 0, now).run();
  return { run_id: id, day, ranked, expires_in_sec: TICKET_TTL_MS / 1000 };
}

/** POST /run/finish {run_id, won, points, time, kills}: close the run, once. */
export async function finish(env, now, pilot, b) {
  const run = await env.DB.prepare("SELECT * FROM runs WHERE id = ?").bind(String(b.run_id ?? "")).first();
  if (!run || run.pubkey !== pilot.pk) throw new HttpError(404, "no_run", "No such run");
  if (run.finished_at !== null) throw new HttpError(409, "run_finished", "That run is already in");
  if (now - run.started_at > TICKET_TTL_MS) throw new HttpError(410, "ticket_expired", "That run's ticket ran out");
  const won = b.won === true;
  const points = Number(b.points);
  const time = Number(b.time);
  const kills = Number(b.kills ?? 0);
  if (!Number.isInteger(points) || !Number.isFinite(time) || !Number.isInteger(kills) || kills < 0) {
    throw new HttpError(400, "bad_request", "points and kills must be whole numbers, time a number");
  }
  const lo = won ? WIN_BASE : 0;
  const hi = won ? WIN_BASE * 2 : LOSS_MAX;
  if (points < lo || points > hi) throw new HttpError(422, "bad_score", `A ${won ? "win" : "loss"} scores ${lo}–${hi}`);
  const open = (now - run.started_at) / 1000;
  if (time < (won ? MIN_RUN_SEC : 0) || time > open + SLACK_SEC) throw new HttpError(422, "bad_time", "That time doesn't fit the ticket");
  const done = await env.DB.prepare(
    "UPDATE runs SET finished_at = ?, points = ?, won = ?, time_sec = ?, kills = ? WHERE id = ? AND finished_at IS NULL")
    .bind(now, points, won ? 1 : 0, time, kills, run.id).run();
  if (!done.meta?.changes) throw new HttpError(409, "run_finished", "That run is already in");
  const board = run.ranked ? "ranked" : "open";
  const best = await bestOf(env, pilot.pk, run.day, run.ranked);
  return {
    board,
    points,
    best,
    rank: await rankOf(env, run.day, run.ranked, best),
    streak: await streak(env, pilot.pk, dayOf(now)),
  };
}

/** GET /leaderboard?day=&board=ranked|open: the top pilots by their best run, and the caller's place. */
export async function board(env, now, pilot, params) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(params.get("day") ?? "") ? params.get("day") : dayOf(now);
  const ranked = params.get("board") === "open" ? 0 : 1;
  const { results } = await env.DB.prepare(
    `SELECT r.pubkey, MAX(r.points) AS points, p.name, p.genesis_mint IS NOT NULL AS seeker
     FROM runs r LEFT JOIN pilots p ON p.pubkey = r.pubkey
     WHERE r.day = ? AND r.ranked = ? AND r.finished_at IS NOT NULL
     GROUP BY r.pubkey ORDER BY points DESC, MIN(r.finished_at) ASC LIMIT ?`)
    .bind(day, ranked, BOARD_SIZE).all();
  const rows = results.map((r, i) => ({ rank: i + 1, pubkey: r.pubkey, name: r.name ?? "", points: r.points, seeker: !!r.seeker }));
  let me = null;
  if (pilot) {
    const best = await bestOf(env, pilot.pk, day, ranked);
    if (best !== null) me = { points: best, rank: await rankOf(env, day, ranked, best) };
  }
  return { day, board: ranked ? "ranked" : "open", rows, me };
}

// --- Counting ---

export async function rankedLeft(env, gm, day) {
  const used = await env.DB.prepare("SELECT COUNT(*) AS n FROM runs WHERE genesis_mint = ? AND day = ? AND ranked = 1")
    .bind(gm, day).first("n");
  const extra = (await env.DB.prepare("SELECT count FROM extra_attempts WHERE genesis_mint = ? AND day = ?")
    .bind(gm, day).first("count")) ?? 0;
  return Math.max(0, 1 + extra - used);
}

async function bestOf(env, pk, day, ranked) {
  return env.DB.prepare("SELECT MAX(points) AS p FROM runs WHERE pubkey = ? AND day = ? AND ranked = ? AND finished_at IS NOT NULL")
    .bind(pk, day, ranked).first("p");
}

/** 1 + how many pilots' best beats [points]. */
async function rankOf(env, day, ranked, points) {
  const above = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM (SELECT MAX(points) AS b FROM runs
     WHERE day = ? AND ranked = ? AND finished_at IS NOT NULL GROUP BY pubkey) WHERE b > ?`)
    .bind(day, ranked, points).first("n");
  return above + 1;
}

/** Days in a row with a finished run, ending today (or yesterday: today isn't over). */
export async function streak(env, pk, day) {
  const { results } = await env.DB.prepare(
    "SELECT DISTINCT day FROM runs WHERE pubkey = ? AND finished_at IS NOT NULL AND day <= ? ORDER BY day DESC LIMIT 400")
    .bind(pk, day).all();
  const days = new Set(results.map((r) => r.day));
  let d = days.has(day) ? day : prevDay(day);
  let n = 0;
  while (days.has(d)) {
    n++;
    d = prevDay(d);
  }
  return n;
}
