// The music version of the cut: the game's own songs (assets/sounds/songs)
// under the finished video, a new song where the video changes mood, with
// crossfades; the music ducks a little under the game's sounds, and the whole
// mix is levelled for YouTube (-14 LUFS). The picture is copied, not encoded.
//
//   node launch/video/music.mjs <seg/times.txt> <in.mp4> <out.mp4>
//
// times.txt (assemble.sh writes it): "<segment> <start s> <length s>" a line.
// MUSIC_DB (env): the bed's mean level before the mix, dB (default -29).
import { spawn, spawnSync } from "node:child_process";
import { readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const SONGS = "assets/sounds/songs/";
// Each song comes in at a segment's cut. from: where in the song the cut lands
// (s); pre: how early it starts fading in under the old one; fadeIn; fadeOut:
// how long the old song takes to go, from when this one starts.
const PLAN = [
  // The hook: cyber_power's build under PULL BACK / LET GO, its drop (21.4 s)
  // on the YEET! burst (1.75 s into the hook).
  { seg: "hook", song: "gameplay/cyber_power.ogg", from: 21.4 - 1.75, pre: 0, fadeIn: 0.25 },
  // The home screen and the wallet: the game's own theme (its main playlist).
  { seg: "home", song: "main/Inspring Piano.ogg", from: 1.0, pre: 0.8, fadeIn: 2.0, fadeOut: 2.4 },
  // A ranked run: 90s_racer_techno's drop (21.0 s) on the cut.
  { seg: "ranked", song: "gameplay/90s_racer_techno.ogg", from: 21.0, pre: 1.0, fadeIn: 0.9, fadeOut: 1.2 },
  // SKR, the shop, under the hood: the store's song (the submenus playlist).
  { seg: "skr", song: "submenus/space_fleet_rejects_looping.ogg", from: 0.8, pre: 0.8, fadeIn: 1.6, fadeOut: 2.2 },
  // Seeker-native and the end card: the theme again, from where it lifts (32 s).
  { seg: "seeker", song: "main/Inspring Piano.ogg", from: 32.0, pre: 1.0, fadeIn: 1.2, fadeOut: 2.0 },
];
const END_FADE = 3.0;
const BED_DB = Number(process.env.MUSIC_DB ?? -29);

const [timesPath, input, out] = process.argv.slice(2);
if (!timesPath || !out) {
  console.error("usage: node launch/video/music.mjs <seg/times.txt> <in.mp4> <out.mp4>");
  process.exit(2);
}
const segs = {};
let total = 0;
for (const line of (await readFile(timesPath, "utf8")).split(/\r?\n/).filter(Boolean)) {
  const [name, start, len] = line.trim().split(/\s+/);
  segs[name] = Number(start);
  total = Math.max(total, Number(start) + Number(len));
}

// The mean level of [len] s of a song from [from], dB.
function meanDb(file, from, len) {
  const r = spawnSync("ffmpeg", ["-hide_banner", "-ss", String(from), "-t", String(len), "-i", file, "-af", "volumedetect", "-f", "null", "-"], { encoding: "utf8" });
  const m = /mean_volume: (-?[\d.]+) dB/.exec(r.stderr);
  return m ? Number(m[1]) : -20;
}

const inputs = ["-i", input], chains = [];
PLAN.forEach((p, i) => {
  if (segs[p.seg] === undefined) throw new Error(`no segment "${p.seg}" in ${timesPath}`);
  const next = PLAN[i + 1];
  const at = segs[p.seg] - p.pre;
  // Until the next song has faded in over it (or to the end).
  const until = next ? segs[next.seg] - next.pre + next.fadeOut : total;
  const len = until - at;
  const file = resolve(ROOT, SONGS + p.song);
  const start = p.from - p.pre;
  const gain = BED_DB - meanDb(file, Math.max(0, start), len);
  const fo = next ? next.fadeOut : END_FADE;
  const k = i + 1;
  inputs.push("-ss", String(Math.max(0, start)), "-t", String(len), "-i", file);
  chains.push(`[${k}:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=${gain.toFixed(2)}dB,` +
    `afade=t=in:st=0:d=${p.fadeIn}:curve=qsin,afade=t=out:st=${(len - fo).toFixed(3)}:d=${fo}:curve=qsin,` +
    `adelay=${Math.round(at * 1000)}:all=1[m${k}]`);
  console.log(`[music] ${p.seg.padEnd(7)} ${at.toFixed(2).padStart(7)}s +${len.toFixed(1)}s  ${p.song} from ${start.toFixed(1)}s, ${gain.toFixed(1)} dB`);
});
const n = PLAN.length;
const graph = `${chains.join(";")};` +
  `${Array.from({ length: n }, (_, k) => `[m${k + 1}]`).join("")}amix=inputs=${n}:normalize=0:dropout_transition=0,apad,atrim=0:${total}[bed];` +
  `[0:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,asplit[main][key];` +
  `[bed][key]sidechaincompress=threshold=0.04:ratio=3:attack=15:release=450[duck];` +
  `[main][duck]amix=inputs=2:normalize=0:duration=first[a]`;
const run = async (args) => {
  const ff = spawn("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "inherit" });
  const code = await new Promise((r) => ff.on("close", r));
  if (code) process.exit(code);
};
// Two passes: the mix, then its loudness measured and set to -14 LUFS, with a
// limiter on the peaks (one-pass loudnorm lands short on a mix this uneven).
const mix = join(tmpdir(), `yeetfleet_mix_${process.pid}.wav`);
await run([...inputs, "-filter_complex", graph, "-map", "[a]", "-c:a", "pcm_f32le", mix]);
const lufs = Number(/I:\s+(-?[\d.]+) LUFS/.exec(spawnSync("ffmpeg", ["-hide_banner", "-i", mix, "-af", "ebur128", "-f", "null", "-"], { encoding: "utf8" }).stderr.split("Summary")[1])[1]);
await run(["-i", input, "-i", mix, "-filter_complex", `[1:a]volume=${(-14 - lufs).toFixed(2)}dB,alimiter=limit=0.84:level=false,aresample=48000[a]`,
  "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]);
await rm(mix, { force: true });
console.log(`[music] -> ${out} (mix was ${lufs} LUFS, set to -14)`);
