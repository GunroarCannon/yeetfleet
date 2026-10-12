// Fails if the game's win fanfare (GameAudio "win") is anywhere in a cut. The
// gameplay takes record the game's own sounds, and the YEET! win card plays
// its fanfare when a level is won; the video shouldn't have it. Run by
// assemble.sh on the no-music version.
//
//   node launch/video/nowin_check.mjs <video.mp4>
//
// Normalised cross-correlation of three 1.5 s pieces of the fanfare against
// the cut's audio at 2 kHz. A real hit scores 0.3-0.9, the rest of the soundtrack
// stays under 0.05. No dependencies: Node 22+, ffmpeg on PATH.
import { spawnSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const FANFARE = resolve(ROOT, "assets/sounds/mixit-sounds/mixkit-medieval-show-fanfare-announcement-226.ogg");
const RATE = 2000;
const THRESHOLD = 0.15;

function decode(file) {
  const r = spawnSync("ffmpeg", ["-v", "error", "-i", file, "-ac", "1", "-ar", String(RATE), "-f", "f32le", "-"],
    { maxBuffer: 1 << 28 });
  if (r.status !== 0) throw new Error(`ffmpeg failed on ${file}: ${r.stderr}`);
  const b = r.stdout;
  return new Float32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength - (b.byteLength % 4)));
}

const input = process.argv[2];
if (!input) {
  console.error("usage: node launch/video/nowin_check.mjs <video.mp4>");
  process.exit(2);
}
const x = decode(input);
const fan = decode(FANFARE);
const M = Math.round(1.5 * RATE);
// Running window energy.
const e = new Float64Array(x.length + 1);
for (let i = 0; i < x.length; i++) e[i + 1] = e[i] + x[i] * x[i];

let worst = { score: 0, at: 0, piece: 0 };
for (let piece = 0; piece < 3; piece++) {
  const pat = fan.slice(piece * M, piece * M + M);
  if (pat.length < M) continue;
  let mean = 0;
  for (const v of pat) mean += v;
  mean /= M;
  let pe = 0;
  for (let i = 0; i < M; i++) { pat[i] -= mean; pe += pat[i] * pat[i]; }
  if (pe < 1e-6) continue;
  for (let i = 0; i + M <= x.length; i++) {
    const we = e[i + M] - e[i];
    if (we < 1e-4) continue;
    let d = 0;
    for (let k = 0; k < M; k++) d += x[i + k] * pat[k];
    const score = d / Math.sqrt(we * pe);
    if (score > worst.score) worst = { score, at: i / RATE, piece };
  }
}
console.log(`[nowin] best match ${worst.score.toFixed(3)} at ${worst.at.toFixed(2)} s (piece ${worst.piece}, threshold ${THRESHOLD})`);
if (worst.score >= THRESHOLD) {
  console.error(`[nowin] FAIL: the win fanfare is in the cut around ${worst.at.toFixed(1)} s. Cut that gameplay take in earlier (PLAY_IN / HOOK_IN / RANKED_IN) or shorter.`);
  process.exit(1);
}
console.log("[nowin] ok: no win fanfare");
