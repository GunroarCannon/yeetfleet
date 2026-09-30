# Front end, campaign, sling camera and launch kit — 2026-09-29

## Menu and campaign (new modules `menu`, `campaign`)

- **Pattern:** screens are code-built Controls under one `MenuRoot` façade,
  swapped behind a wipe; the campaign is a static façade (`Campaign`) over a
  versioned JSON save with a migrate step. Flight hand-off is through
  `Session.pending_level / pending_ship / level_result` only.
- **Rejected:** a scene per screen (`change_scene` between them) — it would
  rebuild the 3D home stage on every hop, and the stage is the expensive part.
- Levels are seeded (`"yeetfleet/v{GRAMMAR_VERSION}/key".hash()`), so every
  player gets the same level on the same road; bumping `GRAMMAR_VERSION` is
  the only way to change them.

## Pause and leaving a level

- **Pattern:** `SceneTree.paused` with the level overlay on
  `PROCESS_MODE_ALWAYS`. MAP, the HUD's menu button, Back and Escape all pause;
  the pause card carries the level's brief (`LevelGen.KIND_BRIEF`).
- **Rejected:** `Engine.time_scale = 0` (the game's freezes already use time
  scale for juice; a pause on the same dial fights them).
- Only a **win** shows the pay-out card on the map; a bail-out is a try that
  pays nothing and shows nothing.
- The home screen never quits directly: EXIT, Back and the window's close
  button ask QUIT? (`set_auto_accept_quit(false)` while the menu is up).

## Slingshot aim and camera

- **Pattern:** the pull is measured from the ship's screen position **at
  touch-down** and read in the camera basis **from touch-down**; the band,
  pouch and rings are drawn from where the ship is **drawn now**
  (`get_global_transform_interpolated`). The camera swings behind the ship
  along the aim while pulling, then holds the launch line in flight.
- **Rejected:** measuring from the live ship. `move_profile_check`'s new
  steady-aim test measured the aim wandering 35° under a still thumb at 60 fps
  as the view swung. The grab ring floating off the ship at speed was the
  physics-tick position vs the interpolated one.
- New dials (not changed defaults): `sling_aim_cam_look`, `sling_cam_hold_launch`.

## Objectives

- Rings count in any order, through the hoop either way or near its middle.
  Objectives pull like the launch magnet (`ScenarioObjectives._attract`) and
  the sling aim snaps to them (`FlightScenarios.objective_points`).
- The way-pointer is one 3D arrowhead parented to the camera
  (`GoalPointer3D`), so it never lags a frame; rejected the chevron trail off
  the ship, which read like the movement arrow.
- The level intro counts down on the wall clock: counting drawn frames let a
  kill cam in the first seconds lock the controls for good.

## Effects cost

- Under Compatibility, big explosions draw only the `CartoonBlast`; the
  Binbun particle scene on top drew nothing and cost a hitch per kill. Rings
  share one unit torus mesh. Every blast look is drawn once under the loading
  card (`CartoonBlast.prewarm`), and the card stays up over the scene swap so
  the first frames aren't a grey window.

## Launch kit (`launch/`)

- Banner, icon and screenshots are made by scripts that build the real game
  scenes (`banner_gen.gd`, `store_shots.gd`), seeded, so the art follows the
  look and any banner can be re-rolled or got back by seed.

## Known, pre-existing

`move_profile_check` (FPS: nose follows the look), `powerup_check` at 60 and
`combat_feel_check` fail on the last commit too (checked in a worktree of
`0171eed` under Godot 4.7); this batch fails a subset of them.
