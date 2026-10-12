// Render a scene of scenes.html to a video, frame-exact: Chrome (headless,
// the one already installed) draws window.seek(t) for every frame and each
// PNG is piped into ffmpeg. The page background is transparent, so overlay
// scenes keep their alpha (out.alpha: a colour and a mask video); full-frame
// scenes go straight to H.264 (out.mp4).
//
//   node launch/video/render.mjs <scene> [out.mp4 | out.alpha] [--fps 60]
//   node launch/video/render.mjs <scene> out.png --at 2.5,4,6   (stills: out_2.5.png …)
//   node launch/video/render.mjs <scene> out.json --cues        (its sound cues, for sfx.mjs)
//
// No dependencies: Node 22+ (global WebSocket), ffmpeg on PATH. Pages are
// served from the repo root on localhost, so the game's own fonts load.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, extname, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const args = process.argv.slice(2);
const scene = args[0];
if (!scene) {
  console.error("usage: node launch/video/render.mjs <scene> [out] [--fps 60]");
  process.exit(2);
}
const fpsAt = args.indexOf("--fps");
const FPS = fpsAt >= 0 ? Number(args[fpsAt + 1]) : 60;
const out = args[1] && !args[1].startsWith("--") ? args[1] : join(ROOT, "launch/video/out/scenes", `${scene}.mp4`);
const W = 1920, H = 1080;
const CHROME = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
].find(existsSync);

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".otf": "font/otf",
  ".ttf": "font/ttf", ".png": "image/png", ".svg": "image/svg+xml", ".jpg": "image/jpeg", ".json": "application/json" };

const server = createServer(async (req, res) => {
  try {
    const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
    const file = resolve(ROOT, "." + path);
    if (!file.startsWith(ROOT)) throw new Error("outside");
    const body = await readFile(file);
    res.writeHead(200, { "content-type": TYPES[extname(file).toLowerCase()] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const PORT = server.address().port;

const DEBUG_PORT = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn(CHROME, [
  "--headless=new", `--remote-debugging-port=${DEBUG_PORT}`, `--window-size=${W},${H}`,
  "--hide-scrollbars", "--force-device-scale-factor=1", "--no-first-run", "--mute-audio",
  `--user-data-dir=${join(tmpdir(), "yeetfleet-render-" + DEBUG_PORT)}`, "about:blank",
], { stdio: "ignore" });

async function json(path, method = "GET") {
  for (let i = 0; i < 100; i++) {
    try {
      return await (await fetch(`http://127.0.0.1:${DEBUG_PORT}${path}`, { method })).json();
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  throw new Error("Chrome didn't start");
}

let ws, nextId = 1;
const pending = new Map();
function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((ok, fail) => pending.set(id, { ok, fail }));
}
async function evaluate(expr) {
  const r = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
  return r.result.value;
}

try {
  await json("/json/version");
  const target = (await json("/json/list")).find((t) => t.type === "page");
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      m.error ? p.fail(new Error(m.error.message)) : p.ok(m.result);
    }
  });
  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });
  await send("Page.navigate", { url: `http://127.0.0.1:${PORT}/launch/video/scenes.html?render&scene=${scene}` });
  for (let i = 0; i < 200 && !(await evaluate("window.READY === true").catch(() => false)); i++) {
    await new Promise((r) => setTimeout(r, 100));
  }
  const dur = await evaluate("window.DURATION");
  // --cues: the scene's sound cues (sfx.mjs mixes them), no frames.
  if (args.includes("--cues")) {
    await mkdir(dirname(out), { recursive: true });
    await writeFile(out, JSON.stringify({ scene, duration: dur, cues: await evaluate("window.CUES") }, null, 1));
    console.log(`[render] ${out}`);
    process.exit(0);
  }
  const atAt = args.indexOf("--at");
  if (atAt >= 0) {
    await mkdir(dirname(out), { recursive: true });
    for (const t of args[atAt + 1].split(",")) {
      await evaluate(`window.seek(${Number(t)})`);
      const shot = await send("Page.captureScreenshot", { format: "png" });
      const file = out.replace(/\.png$/, `_${t}.png`);
      await writeFile(file, Buffer.from(shot.data, "base64"));
      console.log(`[render] ${file}`);
    }
    process.exit(0);
  }
  const frames = Math.round(dur * FPS);
  await mkdir(dirname(out), { recursive: true });
  // <name>.alpha: two small H.264 files, the colour and the alpha as a grey
  // mask (ffmpeg's alphamerge puts them back together). Transparent 1080p60
  // in one file (QuickTime Animation, PNG) runs to gigabytes.
  const x264 = (crf) => ["-c:v", "libx264", "-preset", "medium", "-crf", String(crf)];
  const outArgs = out.endsWith(".alpha")
    ? ["-filter_complex", "[0:v]split[c][m];[c]format=yuv420p[cv];[m]alphaextract,format=gray[mv]",
       "-map", "[cv]", ...x264(14), out.replace(/\.alpha$/, ".color.mp4"),
       "-map", "[mv]", ...x264(8), out.replace(/\.alpha$/, ".mask.mp4")]
    : [...x264(14), "-pix_fmt", "yuv420p", out];
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-", ...outArgs],
    { stdio: ["pipe", "inherit", "inherit"] });
  const t0 = Date.now();
  for (let f = 0; f < frames; f++) {
    await evaluate(`window.seek(${f / FPS})`);
    const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false, optimizeForSpeed: true });
    const buf = Buffer.from(shot.data, "base64");
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (f % 120 === 0) process.stdout.write(`\r[render] ${scene} ${f}/${frames}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  console.log(`\r[render] ${scene}: ${frames} frames, ${dur}s, in ${((Date.now() - t0) / 1000).toFixed(0)}s -> ${out}`);
} finally {
  ws?.close();
  chrome.kill();
  server.close();
}
