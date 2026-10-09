# Project Nebula — working notes for Claude Code

Godot 4.5 (GL Compatibility), GDScript. Modules under `modules/`, each with a
`class_name` façade, `scripts/`, optional `tools/` (headless smokes) and
`data/`. Execution order and the feel contract live in `TECHNICAL_PLAN.md`;
`GAMEDOC.md` is the design bible.

## GodotPrompter

Before implementing any Godot system, check for and invoke the matching
`godot-prompter:*` skill (`godot-grill` when a new system's requirements are
unclear; the domain skill — `input-handling`, `camera-system`, `save-load`,
`responsive-ui`, … — for a known change). Report the pattern you picked, the
alternative you rejected and why, before building. Subagents writing Godot
code must do the same. Decision records live in `docs/decisions/`.

## The rules that matter (a condensed, always-true core)

- **Match the surrounding code exactly.** Tabs for indentation, `##` doc
  comments above classes/functions/significant vars, `:=` inference,
  snake_case with `_` private prefix, typed returns (`-> void`), section
  banners like `# --- Translation ---`. GDScript is whitespace-sensitive: one
  wrong indent is a parse error.
- **The Godot exe is NOT on PATH.** The project is on Godot 4.7: use
  `"C:\Users\hmmm\Godot_v4.7-stable_win64_console.exe"`
  (export it as `GD`). Rescan the class cache after adding any `class_name`
  (`"$GD" --headless --editor --quit --path .`).
- **Headless verification, always.** Module smokes:
  - physics: `"$GD" --path . --headless --script modules/physics/tools/physics_smoke.gd`
  - flight↔physics bridge: `... --script modules/flight/tools/flight_bridge_smoke.gd`
  - flight scene orbit: `... --script modules/flight/tools/orbit_check.gd`
  - chase-camera feel (zoom ease, knockback, shudder): `... --fixed-fps 144 --script
    modules/flight/tools/camera_feel_check.gd` — run at 60 too; tick/frame
    mismatch bugs only show above 60 fps. Add `-- --no-interp` to run with
    physics interpolation off. Also checks emotes ride along at speed, a
    twitchy-thumb weave against the old rigid follow, and that every view in
    `FlightCamera.CYCLE` keeps the ship in frame.
  - sling launch along the view must not turn the camera: `... --fixed-fps 60
    --script modules/flight/tools/launch_cam_check.gd` — run at 144 too.
  - profile cycle / rock promote / control modes: the matching `*_check.gd`.
  - scenarios (sides spawn, wingmen fight, locked guns kill, stop restores
    free roam): `... --script modules/flight/tools/scenario_check.gd`.
  - level dressing & sounds (every sector ends on a boss, neutral giants and
    backdrop megastructures, grazes don't pop popcorn ships, tutorial guards
    ships till the wreck step, fly-by / big-engine / low-health / big-blast
    sounds): `... --script modules/flight/tools/level_feel_check.gd`. Which
    sound file does which job lives in `Sfx.FILES` (flight) and `GameAudio.UI`
    (menus); keep the two in step when a sound is reassigned.
  - bullet-hell / fairness (enemy fire styles, real enemy shots, off-screen
    mercy, chase carry, graffiti markers, fly-as, the bug hunt finding a
    planted aim bug): `... --script modules/flight/tools/combat_feel_check.gd`.
  - **Bug hunt rule:** when something misbehaves "sometimes", don't guess —
    register the suspects on `BugHunt` (flight root's `bug_hunt`, 🐞 chip),
    feed a metric with `BugHunt.record()`, and let a hunt flip each suspect
    against a baseline. Runs append to `user://bug_hunt_runs.csv`.
  - movement profiles (swipe, slingshot incl. 3D aim and the classic/dome/smart aim styles, FPS, AI slingshot, HUD hiding, camera
    gestures, steady/look-ahead sling camera, 3D arrows, player shots never slow, grab area,
    launch magnet, ram/shot reach, lost wing, hostile markers, enemy telegraph): `... --fixed-fps 60
    --script modules/flight/tools/move_profile_check.gd` — run at 144 too. Its waits count
    physics ticks, not wall time (under `--fixed-fps` they differ per rate).
  - power-ups / shield bubble & enemy veils / EMP freeze / callouts / "!" "?" marks /
    sling tap auto-aim, auto-fire and aim camera / tutorial: `... --fixed-fps 60 --script
    modules/flight/tools/powerup_check.gd` — run at 144 too.
  - Solana wallet façade (`Chain` on the addon's mock: SIWS, session kept, SKR to the
    treasury confirmed before it counts, tips, cancel / no wallet):
    `... --script modules/chain/tools/chain_check.gd`. Addresses: `docs/solana-wallets.md`.
  - the Pilot ID chip (tap signs in / cancels / opens the card, failures in plain words,
    fits beside STORE, Back closes its card): `... --script modules/menu/tools/pilot_chip_check.gd`.
  - Chain against the real leaderboard Worker code on localhost (server nonce signed, session +
    Genesis, kept across launches, offline still signs in unranked):
    `... --script modules/chain/tools/chain_server_check.gd` (needs `node` 22.5+). The Worker's own
    tests: `cd services/leaderboard-worker && npm test` (no dependencies).
  - Daily Sortie (level stable per date, its own key, points, offline practice, then one ranked
    run per Genesis pilot sent and ranked against the local Worker, the open board, the screen):
    `... --script modules/daily/tools/daily_check.gd` (the Worker part needs `node`).
  - SKR shop UI (the STORE's SKR tab, buying and wearing a livery, +1 RANKED RUN, a tip
    from the board) against the local Worker: `... --script modules/menu/tools/skr_shop_check.gd`.
    A real dSKR payment on devnet, verified by the Worker's code (spends 50 dSKR, needs the
    Solana CLI): `cd services/leaderboard-worker && node scripts/devnet_pay_check.mjs`
    (`WORKER_URL=<live url>` checks the deployed one). Headless checks pin `Chain.api_url = ""`
    or a local dev server: they never touch the live Worker.
  - shipped game defaults (layering, no headless bake, reset):
    `... --script modules/core/tools/game_defaults_check.gd`.
  - UI at any window size (portrait phones, small landscape): `modules/flight/tools/portrait_ui_shot.gd
    -- out_dir 540 960` (windowed).
  - what logs the most: `... --script modules/flight/tools/log_census_check.gd [-- <seconds>]`
    (start-up and a fight, ranked by lines; fails above 2 lines/s while fighting).
    In game: the Log census debug chip ([LogCensus], a Godot 4.5 `Logger`).
  - Feel checks (`camera_feel_check`, `combat_feel_check`, `killcam_check`)
    run on the **shipped** Juice defaults (`JuiceSettings._loaded = true`
    before the scene loads) and at ×1 time — the player's saved dials and a
    saved time warp (restored a frame late) made them fail on this machine.
    New feel checks should do the same.
  - menus at a phone's canvas (after its DPI scale): `modules/menu/tools/menu_shot.gd
    -- res://debug_shots/phone_land 1200 540 960 432` (and `324 720 432 960` for
    portrait), windowed. Screenshots go in `debug_shots/` (never imported or exported).
  - store art studio (builds, randomises, saves): `modules/art_studio/tools/art_studio_shot.gd`
    (windowed, `--resolution 1600x900`); level-card pictures: `modules/menu/tools/picset_bake.gd`
    (windowed, then rescan).
  - planet looks side by side: `flight_shot.gd -- out.png 90 960 540 planet <style 0-2>`.
  - the player's guns on screen: `modules/flight/tools/fire_shot.gd` and the
    mobile HUD looks: `mobile_hud_shot.gd` (both windowed, see headers).
  - faces / confetti: `... --script modules/whimsy/tools/whimsy_smoke.gd`; the
    look itself: `modules/whimsy/tools/whimsy_shot.gd` (windowed, see its header).
  - Always add `--audio-driver Dummy` to test launches — they should be silent.
- **Module isolation.** One `class_name` per module; a module talks to another
  only through that façade's public API (signals out / calls in). No `get_parent()`
  reach-across for new code. `Session` (core) holds statics that survive scene
  reloads.
- **Memory gotchas** (see the auto-memory `godot-headless-smoke-gotchas`):
  the class-cache rescan does not compile script bodies — parse errors surface
  when a script is loaded; nodes added under `SceneTree.root` are not in the
  tree until the loop runs (`await process_frame` ×2); GDScript lambdas capture
  outer locals by value — use bound methods + instance fields to hand data back;
  a model with `_physics_process` is auto-stepped during any `await`, so settle
  moving ships at rest first.

## Editing files correctly (positive + negative examples)

Use `Edit` with a **small, exact** `old_string` copied verbatim from the file —
never retype code you think you remember. Then make the new text differ only in
what must change. Prefer many small edits over one huge replacement; only
`Write` a whole file when you have just read the whole file and are rebuilding
most of it.

- Positive: replace one method's body:
  ```text
  old: "\tvar step := thrust * ASSIST_AUTHORITY * delta"
  new: "\tvar step := thrust * assist_authority * delta"
  ```
  (Note the leading tab character — GDScript indentation.)
- Positive: when a block spans several lines, include enough unique context
  (the `func` header or a neighbouring comment) so the match is unique, and keep
  unrelated lines identical.
- Negative — never do this: guess at the text. The read line numbers are NOT
  part of the file; do not include `123:`. If `Edit` says "String to replace not
  found", `Read` the file and copy the exact bytes (tabs, trailing spaces,
  the `✕`-style characters) — do not retry a slightly-different guess.
- Negative: don't paste a giant `old_string` spanning dozens of lines; if a big
  block is genuinely being rewritten and `Edit` keeps failing, rewrite the file
  with `Write` instead (you must have read it first).
- The Edit tool is preferred over `sed`/`perl` for source changes — it surfaces
  mismatches instead of silently doing the wrong thing.

Windows note: paths in tools are `/c/Users/...`-style for the Bash tool, and
`C:\Users\...`-style when the absolute Windows path is needed. In GDScript
resources are always `res://...`.
