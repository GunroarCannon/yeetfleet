# Menu polish, debug mode, level systems, tutorial hand (2026-09-29)

Playtest batch. What was picked, and what was turned down.

## Settings submenus
- **Picked:** each page is a `ScrollContainer` with slabs placed by hand in a
  plain `Control` (containers reset rotation, and the slabs are tilted). A
  submenu tweens the main page off left and itself in from the right with
  `TRANS_BACK`; the running tween is killed before a new one. `SlabButton.pass_drag`
  lets a drag through to the scroll (a >14 px drag cancels the tap).
- **Rejected:** AnimationPlayer (the pages are code-built and sized at runtime).
- CONTROLS offers only SLINGSHOT (DEFAULT) and SWIPE. SHIP FACES toggles both
  emote switches. DIFFICULTY maps to player damage taken + enemy hull.

## Debug mode
- `Session.debug_mode` (saved, defaults to `OS.is_debug_build()`, never baked into
  shipped defaults: `GameDefaults.SKIP_KEYS`). Off: no DEBUG chip, only F/V/C/Esc
  flight keys, `FlightHud.show_hint` drops non-player hints, incident banners
  go quiet (title only, one per minute).
- Player tips go through `FlightRoot.announce` → `show_hint(text, true)`: ka1,
  fades after 6 s, dashes stripped.

## Level systems
- **Picked:** `Session.space_setup`, a plain recipe (looks, sizes, yaw, rock
  density, rings, events). `LevelGen.space_setup(key, theme)` per level (own
  RNG stream, so existing level rolls are unchanged), `random_space()` for the
  sandbox. `SpaceScene` recolours duplicates of the saved planets and sets
  `Planet.palette_mix` low, since the Toybox palette otherwise pulled every
  world 70 % to the same green.
- **Rejected:** a generated system (`GENERATED_SYSTEM` location): the
  scenarios and spawner live in `SPACE`, and the hand-built layout is tuned.

## Missions
- Go-here goals: any order, 170 m catch radius, a gravity well
  (`ScenarioObjectives._pull`) on top of the existing aim bend.
- The guarded ship has ~3.5x the hull and a pinned gold target
  (`InteractionMarkers.pin`). Guard levels get wingmen 80 % of the time.
- `lose_reason` flows scenario → end card headline (WRECKED / ESCORT LOST /
  OUT OF TIME). NEXT on a win card uses `pending_level.next`, computed at
  launch by `Campaign.next_candidates`, and `go_next` in the result.

## Sling camera
- One move per pull: the aim direction and look-ahead lock the first time the
  pull passes `AIM_CAM_POWER`, then hold. Release resets: flight framing after
  a launch, the pre-touch view after a let-go.

## Tutorial
- Playable from the map (TUTORIAL → `Campaign.launch_tutorial`, a practice
  level with `tutorial: true`). A neon-tinted `assets/hand.png` acts each step
  out; the end card waits for the lesson to finish.

# Second batch: audio, store art, title faces, phone layouts

## Music and sounds
- **Picked:** `GameAudio` (common), a static façade that parks one host node
  under the tree root, so music survives menu → loading → flight. Two players
  crossfade; playlists are the folders under `assets/sounds/songs`
  (`main` = home, `submenus` + loose root songs = map/garage/settings,
  `gameplay` = flight, played through and moved on without repeats). Buses
  `Music` and `SFX`; SOUND and MUSIC in Settings turn one each, Master stays
  at 0 dB. SpaceAudio's Cockpit/Exterior buses and AddonVfx's pool send to SFX.
- **Rejected:** an autoload (the project keeps state on statics, `Session`
  style) and `AudioStreamInteractive` (the songs are unrelated tracks; a
  crossfade is all a screen change needs).
- `Sfx` now names only the new files (mixkit set + loose sounds); the old
  Sci-Fi Sound Library is unused. Ids with no new file (warp, alarm, engine
  loops) return nothing and SpaceAudio's synth covers them. The Exterior
  low-pass went from 950 Hz to 3200 Hz (every blast was a thud).

## Store art
- Banner/icon draw the overlay at real pixels (`content_scale_mode` off:
  the 1280x720 stretch was shrinking the title). Title spans the top; a
  planet and the sun are placed by screen point, the key light comes from
  the sun with high specular, a 2D lens flare sits over the 3D. BinbunVFX
  explosions are set off in beats so the capture catches them at different
  stages, on top of more sculpted blasts.

## Title faces
- `GraffitiTitle.cycle`: every 4.5 s a squash-and-pop to another face from
  From Street Art, Graffiti.ttf and `assets/fonts/graffiti/*`, never one of
  the last two shown (static history, so it carries across screen visits).

## Phone layouts
- On a phone `BuilderTheme.apply_density_scale` makes the canvas about
  960x432 (landscape) / 432x960 (portrait). `menu_shot.gd -- dir w h cw ch`
  and `scratch/cards_shot.gd` lay out at that canvas in a desktop-sized
  window. Home panels shrink to fit the column (EXIT included); the report
  pad never exceeds the screen and compacts its photo and name; end cards
  stack buttons in portrait and size the headline to the width.

## Debug shots
- Verification images live in `debug_shots/` (has `.gdignore`: never
  imported or exported). The Android preset also excludes `scratch/`,
  `tests/`, `launch/`, `out/` and `debug_shots/`.

## Menu backdrop blasts
- The live blasts play at `MenuStage.BOOM_SPEED` (0.3): the addon controller's
  `speed_scale` and `CartoonBlast.speed`, so they match the frozen fight.
