# 2026-09-29 — Power-ups, shield veils, callouts, marks, sling aim, tutorial

Playtest batch. Check: `modules/flight/tools/powerup_check.gd` (run at 60 and 144).

## What changed

- **Slingshot tap auto-aims** (`JuiceSettings.sling_tap_auto_aim`): a tap off the ship shoots
  at a ship near the tap, else the best on-screen target (`TargetPriority`). It now works
  while resting between launches too, and the nose turns onto the target.
- **Auto-fire while launched** (`sling_auto_fire`, on by default, toggle in the debug column
  under ⚡ Performance): the guns fire at the magnet's pick, or at the best enemy ahead of
  the flight.
- **Sling aim camera**: while the pull is under way (power > 0.12) the steady camera's
  `follow_dir` is the aim, so the view swings round behind the ship and looks where it
  will fly. The aim is still read in the frame frozen at the start of the pull, so the
  swing never moves the aim under the thumb.
- **Kill cam** holds on the blast point instead of following the dead ship's node,
  which drifts on after the parts scatter.
- **Invisible debris**: `DebrisRegistry.wrap_rigidbody` put the part's scale on the
  RigidBody3D, and physics resets that scale. The parts of big (3–6.5×) AI hulls
  shrank to specks. The scale now goes on the part inside the body.
- **Persona-style callouts** (`PlayerCallouts`, `FlightRoot.player_callout`) replace the
  "⚠ X lost!" hint and the DETACHED! number. They also announce power-ups and the shield.
- **Comic marks**: `AiShip.marked` → `AiSpawner.ship_marked` → `HitWords.mark`. "!" on
  first sight of an enemy (and half the time when going down), "?" when hit by someone
  it didn't count as an enemy. Only in view, 8 s per ship, 0.7 s between any two.
- **Power-ups** (`PowerUps`, under FlightRoot): kills drop orbs. EMP freezes ships the
  ripple reaches (`AiShip.emp_freeze`). Boost raises attack × and speed ×. Shield is a
  bubble (`ShieldBubble`) that soaks 100% and never stacks.
- **Shields**: the design's always-on shield is off (`design_shields`). The shield bar
  is hidden until there is a shield. 25% of enemies wear a veil (`enemy_shields`).
  Per-hit shield ripples moved to `PerformanceSettings.shield_ripples` (off).
- **Tutorial** (`FlightTutorial`): profile-aware steps that wait for the real action,
  then kill → power-up. The power-up step always floats an orb ahead of the ship.
  Runs once (`Session.prefs.tutorial_done`, never baked); 🎓 in the debug column
  restarts it.
- **Settings are the game's defaults**: `GameDefaults.note_saved` mirrors every
  settings save into `res://data/game_defaults/` on an editor run (`auto_bake`,
  checkbox in the debug column). Tool scripts (`--script`) never bake. The folder
  was empty: nothing tuned had ever shipped.
- Phone HUD: the speed gauge takes the right edge, and the menu (pause) is always
  the outer button.

## Patterns picked

- Power-ups: a small node with a fixed enum and timed buffs (the ability-system
  skill's EffectHolder, trimmed). **Rejected**: an `Ability` Resource per power-up.
  There are only three hardcoded kinds, and every dial has to live in JuiceSettings
  like the rest of the game.
- Callouts and marks are drawn 2D overlays (like HitWords), re-projected each
  frame. **Rejected**: Label3D in the world. It gets no comic font outline
  control and scales with distance.

## Notes

- The saved session has `gravity_chaos: true`. With it on, orbit_check fails
  (orbits don't hold) and yeet/combat checks are flaky; they pass on re-run.

- The exit-time segfault in headless runs (`exit 139` after PASS) predates this
  batch. A clean HEAD worktree does the same.
- Checks that measure hull damage turn `enemy_shields` off. Sling bounce tests
  turn `sling_auto_fire` off, because auto-fire can kill the wall before the
  bounce.
