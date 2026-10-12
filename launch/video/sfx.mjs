// Mix a scene's sound cues (render.mjs --cues) into a WAV, with the game's
// own sounds (assets/sounds, the files Sfx and GameAudio play): a slab slams
// in, a caption pops, chips click, the title's letters tick up in pitch, cards
// land, ticks chime. The kinds are the ones scenes.html logs with sfx().
//
//   node launch/video/sfx.mjs <scene.cues.json> <out.wav>
//
// No dependencies: Node 22+, ffmpeg on PATH.
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const S = "assets/sounds/", M = S + "mixit-sounds/";
// Sound -> file and where its hit starts (s): some files open on silence.
const FILES = {
  impact: [S + "Impact_1.ogg", 0.78],
  open: [S + "JDSherbert - Sci Fi UI SFX Pack - Popup Open - 1.mp3", 0],
  close: [S + "JDSherbert - Sci Fi UI SFX Pack - Popup Close - 1.mp3", 0.08],
  tap: [M + "mixkit-forceful-impact-item-3174.ogg", 0.04],
  swoosh: [M + "mixkit-long-sweeping-air-swoosh-167.mp3", 0],
  coin: [M + "mixkit-game-experience-level-increased-2062.mp3", 0],
  upgrade: [M + "mixkit-sci-fi-construction-complete-811.ogg", 0.08],
  shatter: [M + "mixkit-shatter-shot-explosion-1693.mp3", 0],
  hit: [M + "mixkit-break-tech-impact-2952.ogg", 0.25],
  power: [S + "Power Up Gained.mp3", 0],
  tone: [S + "Tone1C_MajorTriadUp.ogg", 0],
};
// Cue kind -> layers: sound, seconds kept, dB, pitch, offset from the cue (s),
// skip into the file past its hit start (s), pitch added per step of a run.
const KINDS = {
  slam: [{ s: "open", len: 0.7, db: -9, p: 1.05 }, { s: "tap", len: 0.4, db: -15, p: 1.3, dt: 0.06 }],
  slam_big: [{ s: "swoosh", len: 0.45, db: -17, p: 1.2, dt: -0.22, skip: 0.35 },
    { s: "impact", len: 1.2, db: -3, dt: 0.05 }, { s: "tap", len: 0.4, db: -11, p: 1.1, dt: 0.05 }],
  out: [{ s: "close", len: 0.5, db: -13, p: 1.15 }],
  chip: [{ s: "tap", len: 0.3, db: -16, p: 1.6 }],
  pop: [{ s: "tap", len: 0.3, db: -12, p: 1.25, step: 0.1 }, { s: "open", len: 0.4, db: -19, p: 1.3, step: 0.05 }],
  letter: [{ s: "tap", len: 0.25, db: -14, p: 1.0, step: 0.09 }],
  halo: [{ s: "power", len: 1.4, db: -13 }],
  burst: [{ s: "shatter", len: 1.6, db: -9 }, { s: "impact", len: 1.5, db: -1 }],
  card: [{ s: "hit", len: 0.6, db: -15, p: 1.1, step: 0.05 }, { s: "open", len: 0.5, db: -17 }],
  tick: [{ s: "tone", len: 0.3, db: -3, step: 0.06 }],
  coin: [{ s: "coin", len: 1.6, db: -13 }],
  whoosh: [{ s: "swoosh", len: 1.0, db: -15, p: 1.1, skip: 0.2 }],
  stamp: [{ s: "impact", len: 1.2, db: -1 }, { s: "upgrade", len: 2.2, db: -11 }],
  draw: [{ s: "swoosh", len: 0.6, db: -21, p: 1.5, step: 0.08, skip: 0.3 }],
};

const [cuesPath, out] = process.argv.slice(2);
if (!cuesPath || !out) {
  console.error("usage: node launch/video/sfx.mjs <scene.cues.json> <out.wav>");
  process.exit(2);
}
const { scene, duration, cues } = JSON.parse(await readFile(cuesPath, "utf8"));

const inputs = [], chains = [];
cues.forEach((c, n) => {
  const layers = KINDS[c.kind];
  if (!layers) throw new Error(`${scene}: no sound for cue kind "${c.kind}"`);
  // A small, fixed wobble per cue so a run of the same sound isn't a machine gun.
  const wob = 1 + (((n * 7919) % 41) / 40 - 0.5) * 0.04;
  for (const l of layers) {
    const [file, start] = FILES[l.s];
    const p = ((l.p ?? 1) + (l.step ?? 0) * c.i) * wob;
    const at = Math.max(0, c.at + (l.dt ?? 0));
    const k = inputs.length / 6;
    inputs.push("-ss", String(start + (l.skip ?? 0)), "-t", String(l.len), "-i", resolve(ROOT, file));
    const kept = l.len / p;
    chains.push(`[${k}:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,` +
      `asetrate=${Math.round(48000 * p)},aresample=48000,afade=t=out:st=${Math.max(0, kept - 0.1).toFixed(3)}:d=0.1,` +
      `volume=${l.db}dB,adelay=${Math.round(at * 1000)}:all=1[a${k}]`);
  }
});
const n = chains.length;
const graph = n
  ? `${chains.join(";")};${Array.from({ length: n }, (_, k) => `[a${k}]`).join("")}amix=inputs=${n}:normalize=0:dropout_transition=0,alimiter=limit=0.8:level=false,` +
    `apad,atrim=0:${duration}[out]`
  : `anullsrc=r=48000:cl=stereo,atrim=0:${duration}[out]`;
const ff = spawn("ffmpeg", ["-v", "error", "-y", ...inputs, "-filter_complex", graph, "-map", "[out]",
  "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", out], { stdio: "inherit" });
const code = await new Promise((r) => ff.on("close", r));
if (code) process.exit(code);
console.log(`[sfx] ${scene}: ${cues.length} cues, ${n} sounds -> ${out}`);
