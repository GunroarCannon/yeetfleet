# Demo video kit

The Yeetfleet hackathon video, 1920×1080 / 60 fps for YouTube, built from
the real game and code. The gameplay is recorded with Godot's Movie Maker
(every frame lands at exactly 1/60 s, however slowly it renders) at a
phone's landscape shape (20:9, the mobile HUD and the phone's UI scale),
shown inside a phone on a graffiti wall. The animated parts are
`scenes.html` (GSAP, the game's fonts and palette), rendered frame by frame
in headless Chrome. Every slab, caption, chip, card and tick makes a sound:
the game's own (`assets/sounds`), mixed in at the moment it moves. Two
versions come out: **`yeetfleet_demo.mp4`** with no music, for your own, and
**`yeetfleet_demo_music.mp4`** with the game's songs under it.

| Step | Command (from the repo root) | Writes |
|---|---|---|
| Gameplay takes | `bash launch/video/render_takes.sh` | `takes/*.mp4` (intro = the CRITBOX splash into the home screen; fight, boss, swarm; map, garage) |
| Animated parts | `bash launch/video/render_scenes.sh` | `out/scenes/*` (pictures and `*.sfx.wav`) |
| Only their sounds | `bash launch/video/render_scenes.sh --sfx` | `out/scenes/*.sfx.wav`, in seconds |
| The cut | `bash launch/video/assemble.sh` | `out/yeetfleet_demo.mp4`, `out/yeetfleet_demo_music.mp4` |

Preview a scene in a browser: serve the repo root (`npx http-server .` or
any static server) and open `/launch/video/scenes.html?scene=skr`. The
scenes are `hook title play home daily ranked skr arch seeker end`, the
phone slots `slot_wallet slot_daily slot_board slot_shop slot_settings`.

## The cut (about 1:22)

Fast: every part is short, captions change every 2-3 s, the phone clips are
sped up to fit.

| At | Length | Part |
|---|---|---|
| 0:00.0 | 1.4 s | the CRITBOX splash (the game's own) |
| 0:01.4 | 4.2 s | hook over the boss fight: PULL BACK. / LET GO. / YEET! |
| 0:05.6 | 2.6 s | title card |
| 0:08.2 | 7.5 s | gameplay (a skirmish), how it plays |
| 0:15.7 | 2.2 s | the home screen: ONE TAP: CONNECT WALLET |
| 0:17.9 | 9 s | **slot: wallet** |
| 0:26.9 | 1.9 s | DAILY SORTIE card |
| 0:28.8 | 10 s | **slot: daily** |
| 0:38.8 | 6 s | a ranked run (gameplay: an assault on a capital ship) |
| 0:44.8 | 5 s | **slot: board** |
| 0:49.8 | 7.2 s | how an SKR payment works |
| 0:57.0 | 10 s | **slot: shop** |
| 1:07.0 | 7.4 s | under the hood (architecture) |
| 1:14.4 | 3 s | Seeker-native |
| 1:17.4 | 4.2 s | end card, @therealgunroar |

Each part is also its own file in `out/seg/` for an editor.

**No win fanfare.** The takes record the game's own sounds, and the YEET! win
card plays the game's fanfare (8 s). The in-points keep every take well
before its win, and `nowin_check.mjs` (run by `assemble.sh`) listens for the
fanfare in the finished cut and stops with the time it found it. If it
trips, cut that take in earlier or shorter (`PLAY_IN`, `HOOK_IN`,
`RANKED_IN`).

## Sound effects

`scenes.html` logs a cue wherever something moves (`sfx(kind, at)`, called
from `slamIn`, `slamOut`, `chip`, `title` and the scenes); `render.mjs
--cues` reads them and `sfx.mjs` mixes them. Which sounds a kind uses, how
loud and at what pitch is the `KINDS` table in `sfx.mjs`:

| Kind | Sounds like |
|---|---|
| `slam` (a caption) | the popup open, a small thud |
| `slam_big` (a heading) | a swoosh in, the impact, a thud |
| `out` | the popup close |
| `chip`, `pop`, `letter` | the menu click, pitched up a step for each in a run |
| `halo` | the power-up |
| `burst` (YEET!) | the shatter and the impact |
| `card` | the tech hit and the popup open |
| `tick` | the major-triad tone, rising |
| `coin`, `whoosh`, `stamp`, `draw` | the coin jingle, the swoosh, the impact and the upgrade, a quick high swoosh |

## The music version

`music.mjs` (run by `assemble.sh`) puts the game's songs under the cut, a
new song where the mood changes, with crossfades. The music dips a little
under the game's sounds, and the mix is set to -14 LUFS for YouTube. The plan
(the `PLAN` table) is:

| From | Song | Why |
|---|---|---|
| the hook | `gameplay/cyber_power` | its drop lands on YEET! |
| the home screen, wallet, Daily Sortie | `main/Inspring Piano` | the game's theme, what the home screen plays |
| the ranked run, the board | `gameplay/90s_racer_techno` | its drop lands on the cut |
| SKR, the shop, under the hood | `submenus/space_fleet_rejects_looping` | the store's song |
| Seeker-native, the end card | `main/Inspring Piano` from 32 s | the theme again, where it lifts |

`MUSIC_DB=-26 bash launch/video/assemble.sh` raises the music (default -29),
or run just `node launch/video/music.mjs out/seg/times.txt
out/yeetfleet_demo.mp4 out/yeetfleet_demo_music.mp4`, which takes seconds.

## Your phone clips

The parts that need a real wallet are slots in the cut, showing a
placeholder until their clip is in:

| Slot file | In the cut | Film about | What to film (`docs/demo-script.md`) |
|---|---|---|---|
| `clips/wallet.mp4` | 9 s | 15-25 s | CONNECT WALLET → Phantom: connect + sign in (one prompt) → the chip (key, SKR, GENESIS) → the Pilot ID card |
| `clips/daily.mp4` | 10 s | 20-30 s | DAILY SORTIE: the level, countdown, streak, RANKED / OPEN boards → RANKED RUN → sign "arm the sling" (the fingerprint) |
| `clips/board.mp4` | 5 s | 6-10 s | back on the board after a ranked run: points and RANK |
| `clips/shop.mp4` | 10 s | 20-30 s | +1 RANKED RUN · 25 SKR → Phantom → "checking the payment on chain" → granted; the STORE's SKR tab, 24 KARAT worn; TIP a rival |

Record with scrcpy (`scrcpy --record clips/wallet.mp4`, the phone held
sideways) **with the game's MUSIC turned down to 0** (its sounds on). The
music version brings its own songs, and the phone's music would play under
them. Drop the file in `launch/video/clips/`, and run `assemble.sh` again. Any length or shape works: the clip is fitted into the phone's
screen and **sped up to the slot's length** (up to 8x, `MAX_SPEED=3 bash
launch/video/assemble.sh` for a gentler limit), so a 25 s flow plays as 10 s
with nothing cut off; a clip shorter than its slot holds on its last frame.
It keeps its sound (pitch kept when sped up). Take the whole flow at your
own pace: the speed-up is what makes it fast. The captions over each slot are timed in `scenes.html` (`SLOTS`);
change a line or its timing there, then `render_scenes.sh slot_<name>`.

**Phantom is a stamp.** Phantom is portrait, so in a landscape recording its
sheet is a thin strip with black either side. `assemble.sh` finds the moments
the strip is up (the left of the recording goes black, `stamp_enable`) and,
only then, pastes that sheet over the phone big and tilted as a paper stamp.
Nothing to do when you re-record. When you change a clip, check the slot's
captions still land on the right moment: the times to watch are printed as
`(phantom stamp: between(t,…))` when the slot is made.

**Lettering.** YEET and YEETFLEET are set in From Street Art
(`vendor/FromStreetArt.ttf`; its licence doc is beside it in `out/`),
wherever they appear: the title, the YEET! burst, the slabs. Everything else
is the game's own faces.

**Voice-over.** `VOICEOVER.md` is the script, timed to the cut;
`vo_mix.sh` lays a recording of it over the music cut.

Gameplay in-points (where each take is cut in) are the `*_IN` variables at
the bottom of `assemble.sh`, e.g. `HOOK_IN=4.5 bash launch/video/assemble.sh`.

## Notes

- Movie Maker on a screen smaller than 2400×1080: `render_takes.sh` writes
  a temporary `override.cfg` (window size, borderless, MJPEG quality) and
  removes it on exit. A framed window is clamped to the screen and the HUD
  comes out cropped; borderless isn't.
- The takes run on a scratch save and never touch the player's own; a bot
  thumb flies the slingshot (`launch/tools/demo_reel.gd`), invulnerable,
  with no coach, hints or callouts on screen.
- Renders and takes are big binaries: `takes/`, `out/` and `clips/` are
  git-ignored.

## Voice-over

`VOICEOVER_AI.md` is the script for an AI voice, one timed line per file;
`vo_lines.tsv` holds the same lines and start times. `vo_place.sh <folder>`
puts each file at its second (trimming silence, tempo-fitting a long line)
into `out/vo_track.wav`, and `vo_mix.sh` lays that over the music cut.
