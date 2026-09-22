# Session Changes Summary — Project Nebula

## Files Created

### `modules/common/ai/ai_behaviour.gd`
Lightweight behaviour state machine for AI ships. States: IDLE, CRUISE, PATROL, INVESTIGATE, FLEE, FORMATION, ORBIT, PURSUIT, HOLD. Integrates group context — boid flocking, formation offset, threat response, wolfpack pursuit, and orbit steering are blended with individual state decisions based on the ship's faction archetype. Outputs throttle/yaw/pitch/roll/boost each frame.

### `modules/common/ai/ai_ship.gd`
Full AI-controlled ship node. Assembles a **completely random ship** from random chassis + random parts per socket + random faction paint. Uses the same `FlightModel` + `SystemsSim` component stack as the player. Features:
- Plumes, tracers, projectiles (same shaders as the player)
- Fires at the player when within 500m
- Has HP from the design's hull stat
- On death: full juice stack (sparks, embers, debris, light pop, ring, shake, flash, hitstop)
- Collides with planets/asteroids via `FlightModel._check_collision()`
- Syncs throttle/boost to `SystemsSim` in `_physics_process`
- Gravity-aware: experiences gravitational pull from all registered bodies

### `modules/common/ai/ai_spawner.gd`
Fleet manager with **group spawning**. Spawns 12 ships on desktop, 4 on mobile. Ships spawn in groups sharing the same faction archetype. Group member arrays are rebuilt each frame so boid/formation algorithms have live positions. Respawns destroyed/distant groups every 2 seconds. Prunes ships beyond 3500m.

### `modules/common/ai/ai_group_behaviour.gd` (435 lines)
Pure algorithmic functions, no state. Includes:
- **Boid flocking** (Reynolds 1987): separation, alignment, cohesion with Perlin noise
- **Formation flying**: V, line, sphere, scatter, trail, zipper shapes
- **Wolfpack pursuit**: encircle, pincer, feint patterns
- **Orbit behaviour**: circle a target at fixed radius
- **Swarm cellular automata**: local rules → emergent patterns
- **Threat response**: group investigate, flee, attack, defend
- **Leapfrog**: alternating advance/cover for military tactics
- **Force blending**: weighted average of multiple steering forces

### `modules/common/ai/ai_factions.gd` (545 lines)
30 faction archetypes from pirates to eldritch swarms. Each defines: group size, detection range, aggression, formation shape, combat pattern, speed, and behavioural tags. Weighted random selection. Adding a new faction = one enum + one `_apply_defaults` case.

### `modules/common/ai/gravity_system.gd` (279 lines)
Newtonian gravity for all objects. Features:
- `register_body()` for planets, stations, asteroids, gates — any mass
- `compute_gravity()` — sum of all body forces on an object
- `orbit_velocity()`, `escape_velocity()` — for orbital mechanics
- `circular_orbit_velocity()` — tangent velocity for stable orbits
- `orbit_elements()` — periapsis, apoapsis, eccentricity, period
- `hill_sphere()`, `roche_limit()` — gravitational boundaries
- `is_in_orbit()` — detect stable orbits
- Three modes: OFF, NORMAL (1×), HIGH (2× for testing)
- Starts OFF by default — player enables with G key

### `AI_USE_CASES.md`
30 documented use cases with algorithm references, parameter values, and tuning guide. Covers pirates, police, swarms, military, traders, aliens, cults, anomalies, escorts, and more.

### `GAMEPLAY_IDEAS.md`
20 detailed gameplay ideas for making the Elite-like space game deep and fun through procedural content. Covers economy, bounties, salvage, smuggling, racing, mining, derelicts, faction standing, capital ships, dynamic stories, and more.

### `freebuff_changes.md`
This file — comprehensive session summary.

---

## Files Modified

### `modules/flight/scripts/flight_root.gd`
- **AI spawner**: Created in `_build_location()` when in SPACE mode, torn down on `toggle_location()`
- **Gravity system**: `_build_gravity()` registers all planets (Tarn IV, Ashara, Glacius), moon, and station. Gravity passed to FlightModel in `_ready()` and to AI spawner via `_find_gravity()`
- **G key toggle**: Cycles OFF → NORMAL → HIGH → OFF with HUD display
- **X key warp**: Toggles 8× debug speed
- **C key**: Quick-turn (barrel roll)
- **Joystick snap-back fix**: `_read_keyboard` now calls `set_stick()` every frame, even when zero — previously releasing arrow keys left yaw/pitch stuck at last value
- **Debris fix**: `_on_part_broken` now tracks the actual part node the damage system moved (instead of creating a box), adds transparency fade and triple particle bursts (SPARKS + DEBRIS + EMBERS)
- **Location toggle**: Rebuilds gravity system when switching between SPACE and TEST_VOLUME

### `modules/flight/scripts/flight_model.gd`
- **Gravity**: `var gravity: GravitySystem` member. Applied in `_integrate_translation()` after thrust — NOT clamped by speed ceiling (gravity can accelerate beyond normal top speed). Hard clamp at 10× top speed.
- **Quick-turn**: `trigger_quick_turn()` starts a 360° barrel roll over 0.45s. `_update_quick_turn()` applies rotation each physics frame. Screen shake on activation.
- **Warp speed**: `warp_active` bool toggles 8× thrust and 8× speed ceiling (debug tool)

### `modules/flight/scripts/space_scene.gd`
- **Planets moved further apart**: Tarn IV 12,800m, Ashara 13,500m, Glacius 9,700m (was 5,000/4,900/3,800)
- **Asteroid tumbling**: Each rock has a per-instance `_rotation_speed` (0.05–0.25 rad/s). `_process()` updates instance transforms each frame.
- **Near-field rocks**: 12 small rocks (1–3.5m radius) placed 30–180m from origin — the speed cue at cruise. Also tumbling, faster (0.1–0.4 rad/s).

### `modules/ship_builder/scripts/editor/systems_sim.gd`
- **Engine halos**: Replaced `StandardMaterial3D` (flat additive quad) with `ShaderMaterial` using `particle_circle.gdshader` — soft glowing orbs instead of hard-edged rectangles

### `modules/common/juice/shaders/particle_circle.gdshader`
- Added `beam_color` uniform so meshes without vertex colors (engine halos) can pass their color to the shader

### `modules/flight/scripts/damage_system.gd`
- Added `debris_node: Node3D` to `BrokenPart` — the actual part node the damage system moved to world space is now passed through to `_on_part_broken`

### `modules/common/ai/ai_behaviour.gd`
- Rewritten to integrate group context: accepts group members, archetype data, threat position
- New states: FORMATION, ORBIT, PURSUIT, HOLD
- Blends individual state machine with group forces based on archetype

---

## Controls Reference

| Key | Action |
|-----|--------|
| W/S | Throttle up/down (lever, holds position) |
| Arrow keys | Pitch and yaw (snap back on release) |
| Q/E | Roll left/right |
| Z | Cycle flight assist mode (assist → damping → manual) |
| V | Cycle camera (chase → cockpit → orbit) |
| R | Respawn at start point |
| C | Quick-turn (360° barrel roll) |
| X | Toggle warp speed (8× debug) |
| G | Toggle gravity (OFF → NORMAL → HIGH) |
| Shift+G | Cycle gravity range multiplier (×0.5 → ×1 → ×2 → ×4 → ×8) |
| Shift+D | Dump scene tree to console (debug) |
| F5 | Restart scene |
| F1/? | Help walkthrough |
| Escape | Return to hangar |
| Left/Right mouse | Look drag + hold to accelerate |
| Scroll wheel | Camera zoom |

---

## Architecture Notes

- **Modular**: All AI code in `modules/common/ai/` — 5 new files, zero restructured
- **Data-driven**: AI ships use random parts from the same `PartLibrary` as the player
- **Performance-budgeted**: 12/4 ship cap (desktop/mobile), same ratio as particle budgets
- **Component-based**: AI ships use `FlightModel` + `SystemsSim` — identical stack to the player
- **Juice-integrated**: AI destruction fires the full particle/light/ring/shake/flash stack
- **Gravity-general**: Any object with a `GravitySystem` reference experiences Newtonian gravity. Stations, asteroids, gates — all can be given mass.
- **Group algorithms compose**: `AiGroupBehaviour` provides pure functions. `AiBehaviour` blends them based on archetype. `AiSpawner` manages group lifecycle. No coupling between layers.
- **30 faction archetypes**: Pirates, police, swarms, military, traders, aliens, cults, anomalies — each with unique movement and combat patterns

---

## Session 2 Changes

### Parse Error Fixes
- `ai_spawner.gd`: Added missing `_spawn_initial_fleet()` method
- `ai_behaviour.gd`: Added missing `var gravity_ref: GravitySystem = null` declaration
- `ai_behaviour.gd`: Fixed `hill_sphere()` call — was on `near_body` (GravityBody) instead of `gravity_ref` (GravitySystem)
- `ai_ship.gd`: Now sets `behaviour.gravity_ref` in `set_gravity()` and comment in `initialise()`
- `space_scene.gd`: Fixed leading whitespace on `_belt_multimeshes.append(inst)`

### `modules/common/ai/gravity_visualizer.gd` (NEW)
Real-time gravity visualization toggled with H key. Shows:
- **Force-line arrows**: Direction and magnitude of gravitational pull from each body, colour-coded by intensity
- **Orbit prediction**: Keplerian propagation of the ship's predicted orbit path
- **Hill spheres**: Transparent outlines showing gravitational influence zones
- Uses `ImmediateMesh` — one draw call per layer, rebuilt each frame, trivial cost

### Control Mode Presets (F11 key)
Three flight control modes, cycling with F11:
- **Arcade**: 1.3× speed, 1.6× accel, 1.5× turn — forgiving and responsive
- **Sim**: 1.0× all — the design's stats as-is
- **Realistic**: 0.7× speed, 0.6× accel, 0.65× turn — sluggish and demanding

Applied as multipliers on top of the design's own stats in `FlightModel.configure()`.

### Firing Visual Improvements
- **SPARKS burst**: 14→20 particles, bigger (0.05–0.16), brighter (overdriven white-to-orange), faster stretch
- **Muzzle FX**: Added EMBERS burst alongside SPARKS for richer flash
- **Light pop**: Increased from 2.5→4.0 intensity, 0.1→0.15 duration
- **Shot shake/kick**: Increased from 0.05→0.08 and 0.35→0.45
- **Tracer shader**: Wider glow halo, brighter white-hot core, better visibility at distance
- **Particle circle shader**: Brighter core with separate edge falloff, better for engine halos

### Updated Controls Reference
| Key | Action |
|-----|--------|
| H | Toggle gravity visualizer |
| F11 | Cycle control mode (Arcade/Sim/Realistic) |

---

## Session 3 Fixes

### Black Circle Fix
- **Root cause**: GravityVisualizer created ImmediateMesh instances at setup time with `no_depth_test = true` and `render_priority = 100`. On the GL Compatibility renderer, an ImmediateMesh with this material configuration renders a black quad even when the parent node is `visible = false`.
- **Fix**: Delayed mesh creation until the visualizer is first toggled on (`_built` flag). Meshes only exist when the visualizer is active — zero cost when inactive.

### Low-Poly Cartoony Planets
- **Problem**: Planets used sphere_resolution 96/64/48 with detail_strength 0.2-0.35, making them look like smooth low-res spheres instead of matching the low-poly art style.
- **Fix**: Updated both .tres data files AND fallback functions:
  - Tarn IV: 96→24 resolution, terrain_height 0.055→0.12, detail_strength 0.20→0.06, saturated colors
  - Moon: 48→16 resolution, terrain_height 0.045→0.10, detail_strength 0.30→0.04
  - Ashara (fallback): 64→20 resolution, terrain_height 0.06→0.14, detail_strength 0.35→0.04, brighter volcanic colors
  - Glacius (fallback): 48→16 resolution, terrain_height 0.04→0.08, detail_strength 0.22→0.03, brighter ice colors
- Lower resolution = visible facets = matches the ship part and asteroid art style
- Less detail noise = cleaner surfaces that read as stylized, not low-res
- More saturated colors = cartoony palette that pops against the dark void

### Orbit Detection Debug Text
- FlightModel now checks every physics frame if the ship is in a stable orbit around any planet
- Uses `GravitySystem.is_in_orbit()` — checks if velocity is within 20% of circular orbital velocity
- Emits `orbit_changed(body_name, in_orbit)` signal on state transitions
- FlightRoot shows HUD hint: "ORBIT — stable around Tarn IV" / "Orbit lost around Tarn IV"
- Detection runs against all registered bodies, picks the nearest planet
- Ignores non-planet bodies (stations, gates) for orbit detection

### Gravity Strength Controls
- 5 preset strength levels: ×0.5, ×1.0, ×2.0, ×5.0, ×10.0
- Number keys 1-5 set specific strength instantly
- TAB cycles through all strengths sequentially
- G key now shows current strength alongside mode (e.g. "Gravity: NORMAL ×2.0")
- Gravity strength multiplier applied in `FlightModel._integrate_translation()` on top of the mode multiplier
- AI ships share the same gravity system, so strength changes affect them too

### Updated Controls Reference
| Key | Action |
|-----|--------|
| 1-5 | Set gravity strength (×0.5 to ×10.0) |
| TAB | Cycle gravity strength |

### Options Menu (☰ hamburger)
- **Gravity mode**: Radio items for OFF / Normal / High — shows current selection with checkmark
- **Gravity strength**: Radio items for ×0.5 / ×1.0 / ×2.0 / ×5.0 / ×10.0 — shows current selection
- **Gravity visualizer**: Check item for H key toggle — shows ON/OFF state
- **Control mode**: Radio items for Arcade / Sim / Realistic — shows current selection
- All menu items sync with keyboard shortcuts and vice versa
- Menu rebuilds on each open to reflect current state

---

## Session 4 Fixes

### Black Circle Fix (attempt 3)
- GravityVisualizer meshes were still being created even when parent was hidden
- Now completely lazy: node and all ImmediateMesh children only created on first H key toggle, removed from tree on second toggle
- Zero nodes exist between toggles

### Debug Toggle Panel (D key)
- Checkbox panel on right edge of screen, toggled with D key
- 10 toggles: Plumes, Halos, Tracers, Stars, Nebula, Planet, Asteroids, Drift, Reticle, Markers
- Each toggle hides/shows the corresponding rendering layer in FlightRoot
- Use this to isolate which element causes the black circle if it persists

### Gravity Fix — Actually Works Now
- **Root cause**: `GAME_G = 0.0005` with mass 500,000 produced only 0.01 m/s² at 5000m — 1000× too weak
- **Fix**: `GAME_G = 0.5` (1000× increase) and masses scaled up:
  - Tarn IV: 500,000 → 50,000,000 (1.0 m/s² at 5000m, 6.25 m/s² at 2000m)
  - Ashara: 80,000 → 10,000,000
  - Glacius: 15,000 → 3,000,000
  - Moon: 2,000 → 500,000
  - Station: 50 → 50,000
- Orbital velocity at 3000m from Tarn IV: ~91 m/s (feels right for gameplay)
- Orbital period at 3000m: ~13 minutes

### Performance — Game Hang Fix
- **Asteroid collision**: Added belt volume check (distance from origin > 3000m or height > 250m skips all 260 rock checks)
- **AI member pool**: Pre-allocated Member array pool instead of `new()` every frame — zero allocation in hot path
- **Cached references**: Player position and gravity system cached in spawner `_ready()` instead of tree walks every frame
- **Group member arrays**: Reuse same Array objects (clear + refill) instead of creating new ones each frame

### Debug Panel Expanded (D key)
Now has 16 toggles covering every visual element:
- Plumes, Halos, Tracers (engine/weapon)
- Stars, Nebula, Planet, Atmo, Station, SkyDome, Sun (environment)
- Asteroids, Drift (reference objects)
- Reticle, Markers (HUD)
- ShipGeo (ship geometry itself)

**To find the black circle**: turn off toggles one at a time. If turning off "ShipGeo" fixes it, the circle is part of the ship's3D model. If "Atmo" fixes it, it's the planet atmosphere. If nothing fixes it, it's a GL Compatibility renderer artifact.

### Gravity Now Starts ON
- Changed default from OFF to NORMAL in SPACE mode
- Player no longer needs to press G to enable gravity — it's on from the start
- G key still cycles OFF → NORMAL → HIGH → OFF

### W/S Throttle Fix
- Both W and S now actively change throttle (W increases, S decreases)
- When neither key is held, throttle holds position (lever behaviour)
- Clearer variable names: `throttle_up` / `throttle_down` instead of combined `throttle_key`

### Gravity Range Multiplier
- New `range_multiplier` on GravitySystem — scales how far gravity reaches
- 5 levels: ×0.5, ×1.0, ×2.0, ×4.0, ×8.0
- Implemented by dividing distance by range_multiplier before force calculation
- Keys: Shift+G cycles range
- Menu: Radio items under gravity settings
- At ×8.0, gravity influence extends ~8× further than default

---

## Gravity Implementation Summary

### Architecture
The gravity system is a standalone `GravitySystem` class (RefCounted, no nodes) that lives in `FlightRoot` and is passed to the `FlightModel` as a reference. It follows the project philosophy: no autoloads, no hidden state, explicitly wired.

### Physics Model
Newtonian inverse-square law: `a = G × M / r²`
- Ship mass cancels out — gravity accelerates all objects equally
- `GAME_G = 0.5` (game-tuned constant, not real G)
- Planet masses: Tarn IV=50M, Ashara=10M, Glacius=3M, Moon=500K, Station=50K
- At 5000m from Tarn IV: ~1.0 m/s² (noticeable pull)
- At 2000m: ~6.25 m/s² (strong pull)
- Orbital velocity at 3000m: ~91 m/s

### Force Application
Applied in `FlightModel._integrate_translation()` AFTER thrust, BEFORE position update:
```
velocity += gravity.compute_gravity(position) * gravity_strength * delta
```
- NOT clamped by speed ceiling — ships can exceed normal top speed via gravity
- Hard clamp at 10× top speed to prevent numerical explosions
- `gravity_strength` multiplier (×0.5 to ×10.0) layered on top of mode multiplier

### Modes
- OFF: no gravity at all
- NORMAL: 1× strength
- HIGH: 2× strength

### Range Multiplier
`effective_dist = dist / range_multiplier` — scales the gravitational reach:
- ×1.0: default — gravity noticeable within ~5000m of a planet
- ×2.0: gravity noticeable within ~10000m
- ×8.0: gravity noticeable within ~40000m
- Does NOT change force at close range, only extends the effective distance

### Orbit Detection
`FlightModel._check_orbit()` runs every physics frame:
- Finds nearest planet body
- Calls `GravitySystem.is_in_orbit()` — checks if velocity is within 20% of circular orbital velocity
- Emits `orbit_changed(body_name, in_orbit)` signal on state transitions
- FlightRoot shows HUD hint: "ORBIT — stable around Tarn IV"

### Orbital Mechanics
- `orbit_velocity(body, r) = sqrt(G × M / r)` — speed for circular orbit
- `escape_velocity(body, r) = v_orbit × sqrt(2)`
- `orbit_elements()` — computes periapsis, apoapsis, eccentricity, period
- `circular_orbit_velocity()` — tangent velocity vector for stable orbit
- `hill_sphere()` — gravitational dominance radius
- `roche_limit()` — tidal disruption boundary

### Visualisation
GravityVisualizer (lazy, H key toggle):
- Force-line arrows: direction + magnitude from each body
- Orbit prediction: Keplerian propagation of current trajectory
- Hill spheres: wireframe outlines of gravitational influence
- Only created when first toggled on, removed from tree when toggled off

### Controls
| Control | Action |
|---------|--------|
| G | Cycle gravity mode (OFF/NORMAL/HIGH) |
| Shift+G | Cycle gravity range (×0.5 to ×8.0) |
| 1-5 | Set gravity strength |
| TAB | Cycle gravity strength |
| H | Toggle gravity visualizer |
| Menu | Full gravity settings submenu |

### Moon Orbits Tarn IV
- Moon now orbits Tarn IV with proper Newtonian orbital velocity
- `v_orbit = sqrt(G × M / r)` calculated from planet mass and orbital radius
- Orbital radius: 3500m, angular velocity: ~0.024 rad/s, period: ~4.3 minutes
- Moon position updated each frame in SpaceScene._process
- Moon gravity body position synced in FlightRoot._process
- Moon landmark position updated for HUD markers

### Planet Collisions Fixed
- `_check_collision()` now iterates over ALL registered gravity bodies
- No more hardcoded positions — any body registered with the gravity system gets collision
- Moon, station, all planets — all collide properly
- Ship bounces off surfaces and takes damage at high speed

### Gravity Strengthened 4×
- `GAME_G` increased from 0.5 to 2.0
- Same planet masses, but now:
  - At 3000m from Tarn IV: ~11 m/s² (very noticeable pull)
  - Orbital velocity at 3000m: ~183 m/s (within ship's speed range)
  - Orbital velocity at 5000m: ~141 m/s
- Ships at normal cruise speed (150 m/s) will now visibly curve toward planets
- Orbit achievable by reducing throttle and matching orbital velocity

### Persistent Orbit Debug Log
- Prints to console every ~1 second with body, distance, speed, v_orbit, and orbit status
- Example: `[ORBIT] Tarn IV dist=3000m speed=180 m/s v_orbit=183 m/s (2% off) IN ORBIT`

### Debug Toggle Fixes
- "Planet" toggle now hides ALL planet-related nodes recursively
- "Atmo" toggle finds atmosphere nodes across all planet pivots

---

## Black Sphere — All Possible Causes

If D-key toggles don't remove it, the cause is NOT a scene node. Possible causes:

1. **GL Compatibility depth buffer bug**: A mesh with `depth_draw_never` + `blend_add` may render in front of everything on some drivers. The atmosphere shader and particle circle shader both use these modes.

2. **Near clipping plane artifact**: Camera near = 0.2m. Objects closer than this get clipped, and on some drivers the clipped geometry renders as a black disc at the near plane.

3. **Reticle arc rendering**: `_draw_arc(centre, r * 1.5, 0, TAU, 32, Color(col, 0.35))` draws a full circle around the crosshair. If the accent color is very dark, this reads as a dark ring.

4. **Drift marker**: Green/orange circle showing actual velocity direction. At low divergence (flying straight) alpha drops to 0.25 — barely visible but could appear as a faint dark circle.

5. **Engine halo shader fallback**: particle_circle.gdshader — if shader fails to compile, QuadMesh renders with default material as a dark square/circle.

6. **Ship part shader failure**: ship_part.gdshader — if it fails, the whole ship renders as black geometry.

7. **Planet surface shader failure**: planet_surface.gdshader — if it fails, planet renders as solid black sphere. Since planet is huge (r=1400m), it could fill much of the screen.

8. **Atmosphere shader failure**: limb_glow.gdshader — if it fails, the atmosphere shell (larger than planet) renders as opaque black sphere blocking everything behind it.

### Fixes Applied This Session
- Fixed parse error: `Engine.get_process_frames_count()` → timer-based orbit log
- Collision bounce: increased restitution from 0.3 to 0.6, added minimum bounce velocity so ship never sticks to surfaces
- Player start: moved 4000m from Tarn IV (was 12,600m) so gravity is immediately noticeable
- Orbit log: prints every 1 second with body, distance, speed, v_orbit, and orbit status

### Gravity Tuned for Orbit Gameplay
- Planet masses reduced 5× (Tarn IV: 50M → 10M, Ashara: 10M → 2M, Glacius: 3M → 500K, Moon: 200K → 50K)
- At 4000m from Tarn IV: ~1.25 m/s² (gentle curve, noticeable but not overwhelming)
- At 2000m: ~5.0 m/s² (strong pull, orbit at ~183 m/s)
- Gravity weakens with distance — ships barely notice beyond 6000m
- This is Newtonian physics: F = G*M/r². Close = strong, far = weak. No artificial "pull down".

### "!!! ALL !!!" Debug Toggle
- New toggle in D-key panel hides ALL SpaceScene children at once
- If sphere disappears when this is off, it is a SpaceScene node

### Engine Halo Material Reverted (Black Sphere Fix)
- Engine halos were changed from `StandardMaterial3D` to `ShaderMaterial` using `particle_circle.gdshader`
- If that shader fails to compile on GL Compatibility, the QuadMesh renders with a fallback material as a solid dark shape
- **Fix**: Reverted halo material back to `ShipMaterials.glow_material()` (StandardMaterial3D with additive blend)
- The particle_circle shader is still used for ParticleBurst particles (sparks, embers) — those work fine because they use vertex colors, not the beam_color uniform
- If it remains, it is a rendering artifact outside the scene tree

### Black Sphere — Complete Cause List
1. GL Compatibility depth buffer bug (depth_draw_never + blend_add renders in front)
2. Near clipping plane artifact (objects < 0.2m from camera)
3. Reticle arc (full circle drawn at 35% alpha around crosshair)
4. Drift marker (velocity direction circle, low alpha when flying straight)
5. Engine halo shader fallback (particle_circle.gdshader compile failure)
6. Ship part shader failure (ship_part.gdshader → whole ship renders black)
7. Planet surface shader failure (planet_surface.gdshader → solid black sphere)
8. Atmosphere shader failure (limb_glow.gdshader → opaque black shell)
9. Star/nebula material issue (additive materials rendering on top of everything)

---

## Latest Changes (Black Sphere Debug + Rear Camera Fix)

### Rear Camera Menu Handler
- Added `MENU_REAR_VIEW` handler in `flight_hud._on_menu()` — the menu item was created but never connected
- Press B or use the ☰ menu to toggle rear view

### "Everything" Debug Toggle Now Nuclear
- Previously only hid children of SpaceScene
- Now hides ALL Node3D and SubViewport children of FlightRoot — including ship, camera rig, drift field, rear viewport
- If the sphere persists with this toggle OFF, it is definitively a **rendering artifact** outside the scene tree (GL Compatibility shader/driver issue)

### Atmosphere Debug Toggle Fixed
- The `atmo` toggle was searching at the wrong level in the scene tree — it looked for Atmosphere nodes as direct children of Planet pivots, but they are grandchildren (inside Planet nodes)
- Now correctly finds Atmosphere MeshInstance3D inside each Planet node
- This toggle should now properly hide the atmosphere glow shells

### Black Sphere — How to Definitively Diagnose
1. Press D to open debug panel
2. Turn off "!!! ALL !!!" — this now hides EVERYTHING (ship, planets, sky, asteroids, drift, camera rig, rear viewport)
3. If sphere disappears → it's a scene node. Turn toggles back on one by one to find it
4. If sphere remains → it's a **GL Compatibility rendering artifact** (shader compilation failure, depth buffer bug, or driver issue)
5. Check Godot Output panel for shader compile errors (red text about limb_glow, planet_surface, or ship_part shaders)

---

## Gravity System Rewrite — Dominant Body Selection

### Problem
Ships "nose dive" into planets instead of orbiting. The old system summed every body's pull, which meant moons orbited the sun instead of their planet. Orbit detection required an `is_planet` flag and nearest-by-distance logic.

### Solution: Dominant Body + Weighted Blend
Instead of summing all gravity vectors, the system now:
1. **Computes acceleration** from each body at the query point (`a = G * M / r²`)
2. **Sorts by acceleration** descending — the body pulling hardest wins
3. **Takes top N** (default 2) and applies **softmax weights** for smooth blending
4. **Orbit math** always runs against the single dominant body

This is computed, not categorized. A procedurally-generated asteroid slots in automatically with zero setup.

### Key Changes

**`gravity_system.gd`** — Complete rewrite:
- `find_dominant_bodies(pos, n=2)` — returns top N bodies with softmax weights
- `find_dominant_body(pos)` — convenience for single dominant body
- `relevant_range(body)` — derived from mass: `sqrt(G * M / epsilon)` where epsilon = 0.008 m/s²
- `compute_gravity()` now uses weighted blend of top 2 bodies instead of summing all
- `is_planet` removed from physics logic (kept as optional UI hint)
- `hill_sphere()` now returns `relevant_range` (derived from mass, not category)

**`flight_model.gd`** — Orbit check uses dominant body:
- `_check_orbit()` calls `gravity.find_dominant_body(pos)` instead of iterating all bodies and filtering by `is_planet`
- Moon orbits are detected correctly because the moon produces more local acceleration than the distant sun

**`flight_root.gd`** — Ship spawns in orbit:
- On spawn, ship receives tangential velocity (60% of circular orbit velocity)
- This prevents the "nose dive" effect — ship is already orbiting when it appears
- Uses `gravity.find_dominant_body()` to compute the correct orbital velocity for the nearest body

**`ai_behaviour.gd`** — Uses dominant body for gravity-aware throttle:
- Replaced `nearest_body()` with `find_dominant_body()` for throttle reduction near planets

**`gravity_visualizer.gd`** — Orbit prediction uses dominant body:
- Replaced `nearest_body()` with `find_dominant_body()` for orbit path visualization

### Physics: Why Ships No Longer Nose-Dive
The old behavior: ship spawns at rest → gravity pulls it straight toward planet → assist ON makes nose follow velocity → ship points at planet → crash.

New behavior: ship spawns with tangential velocity → gravity curves the trajectory into an ellipse → ship orbits the dominant body. With assist ON, the ship still follows its nose, but the orbit is stable enough that the player can learn to reduce throttle and enter a proper orbit.

### How Dominant Body Selection Works

```
for each body:
    a = GAME_G * body.mass / max(dist, MIN_ORBIT_RADIUS)^2
sort by a descending
top_n = bodies[0..1]
weights = softmax(top_n.accelerations, temperature=3.0)
force = sum(weight_i * direction_i * accel_i)
```

At the moon's position, Earth's gravity is ~9.8 m/s² but the Sun's pull is only ~0.006 m/s². The dominant body selection naturally picks Earth, no category needed.

At SOI boundaries (where two bodies have similar acceleration), the softmax blend provides smooth transitions — no popping or hard switches.

### Backward Compatibility
- `register_body()` signature unchanged (is_planet is now optional, defaults to false)
- `nearest_body()` still exists for backward compatibility
- `orbit_velocity()`, `escape_velocity()`, `orbit_elements()` all work unchanged
- AI ships share the same gravity system and benefit from the same dominant-body logic

---

## New Atmosphere Shader + Black Sphere Fix

### Problem
A persistent dark sphere appeared in front of the camera that no debug toggle could remove. The `limb_glow.gdshader` uses `depth_draw_never` + `blend_add` + `cull_front` — this combination causes rendering order issues on some GL Compatibility drivers, producing a solid dark shape instead of a transparent limb glow.

### Fix: New Safe Atmosphere Shader
Created `modules/common/juice/shaders/atmosphere_safe.gdshader` — identical visual output but uses default depth drawing instead of `depth_draw_never`. The sphere should no longer appear.

### How to Switch
- **Default**: Safe shader (`atmosphere_safe.gdshader`) — no artifacts
- **Debug toggle**: "SafeAtmo" in D-key panel — turn OFF to revert to original `limb_glow.gdshader`
- **Runtime swap**: `Planet.swap_all_atmosphere_shaders(use_safe)` — swaps shader on all existing planets instantly

### Parse Error Fixed
`_check_orbit()` function definition was jammed onto the same line as the preceding doc comment (missing newline), causing a parse error. Fixed by adding the missing newline.

---

## Session 4 Fixes

### Parse Error: `_check_orbit()` Not Found
The `trigger_quick_turn()` function's doc comment was jammed onto the same line as the preceding `global_transform` assignment (`...global_transform.origin)## Start a 180°...`). This cascading parse error made `_check_orbit()` unresolvable at the call site (line 346). Fixed by inserting the missing newline between the assignment and the doc comment.

### WorldEnvironment.visible Error
The "!!! ALL !!!" debug toggle tried to call `.visible` on a `WorldEnvironment` node, which extends `Node` (not `Node3D`) and has no `.visible` property. Fixed by skipping the Environment node in the hide loop and handling it separately via `Environment.background_color`.

### SubViewport.visible Error
The "everything" toggle set `.visible` on `SubViewport` children of FlightRoot, but SubViewport extends Viewport/Node (not Node3D) — no `.visible` property. Fixed by checking `child is SubViewport` separately and toggling `render_target_update_mode` instead.

### New Safe Atmosphere Shader (Revised)
The previous `atmosphere_safe.gdshader` used `cull_front` which still produced a dark artifact on some GL Compatibility drivers. Revised to use `cull_back` (standard rendering direction) with `blend_add` + `depth_draw_opaque`. The rim glow is calculated from the view angle — center is transparent, edges glow — without relying on `cull_front`.

### Debug: Scene Tree Dump (Shift+D)
New `Shift+D` key dumps the full scene tree hierarchy to the Godot console, showing every node's class, name, parent, and relevant properties (mesh type, material, visibility, camera settings, SubViewport settings). This is the primary tool for identifying mystery rendering artifacts like the persistent black sphere.

### Debug: Green Background on "All Off"
When "!!! ALL !!!" is toggled, the environment background turns bright green (RGB 0, 0.8, 0.15) so any remaining dark artifacts are clearly visible against a contrasting background.

---

## Session 5 Fixes

### Rear View Toggle Fix
The `toggle_rear_view()` function used `_rear_viewport.visible = _rear_view_on` — SubViewport has no `.visible` property. Fixed to toggle `render_target_update_mode` between UPDATE_ALWAYS and UPDATE_DISABLED.

### Menu Pause System
- **"Pause game"** checkbox in the ☰ menu pauses/unpauses the scene tree
- **"Resume when menu closes"** checkbox (ON by default) — unpauses automatically when the menu popup closes
- Uncheck "Resume when menu closes" to keep paused while browsing options
- The HUD uses `process_mode = PROCESS_MODE_ALWAYS` so the menu remains interactive while paused

### AI Ship Spawn from Menu
- **"Spawn 1/3/6 AI ships"** — spawns ships near the player with random faction archetypes
- **"Kill all AI ships"** — tears down all live AI ships instantly
- Menu shows live ship count next to spawn options
- `AiSpawner.spawn_near_player(count)` — public API for spawning ships near the player

### Controls Reference Updated
| Key | Action |
|-----|--------|
| Shift+G | Cycle gravity range multiplier |
| Shift+D | Dump scene tree to console (debug) |

---

## Session 6 Fixes

### Moon Orbit: Real Newtonian Gravity (Not Fake)
**Problem**: The moon used a hard-coded `cos/sin` animation to orbit Tarn IV. Gravity had zero effect on it — turning off gravity did nothing.

**Fix**: Replaced with real Newtonian integration:
- Moon gets initial tangential velocity: `v = sqrt(G * M / r)`
- Each frame: `velocity += gravity * delta; position += velocity * delta`
- When gravity is OFF, moon drifts at constant velocity (no force applied)
- Moon's gravity body position updates each frame so the player feels its pull at its real location

### Player Spawn: Stable Orbit, Not Crash Course
**Problem**: Ship spawned facing the station with 60% orbital velocity. Flight assist pulled the ship toward its nose (the station) — INTO the planet. And 60% velocity was too slow, causing the orbit periapsis to dip below the surface.

**Fix**:
- Ship spawns at full circular orbit velocity: `v = sqrt(G*M/r)` = ~71 m/s at 4000m
- Ship faces along the orbit direction (tangential), not toward the station
- Flight assist now keeps the ship in orbit instead of pulling it toward the planet
- Orbit is slightly elliptical for interesting flight

### Why Orbits Now Work
Correct tangential velocity + correct facing direction + real gravity = stable orbit. The ship follows a Keplerian ellipse around Tarn IV. Boosting increases speed (wider orbit), cutting throttle decreases speed (tighter orbit).

---

## Session 7 — Sci-Fi sound library, addon hit FX, toon toggle, lab comparison

Everything added this session is behind a single switch, so each layer can be
flipped against the original look without a code change.

### New files

**`modules/common/juice/fx_settings.gd`** — `FxSettings`, three persisted
toggles in `user://fx.cfg`: `library_sounds`, `addon_vfx`, `sprite_hits`.

**`modules/common/juice/sfx.gd`** — `Sfx`. The bundled Sci-Fi Sound Library as
named streams (`laser`, `kinetic`, `railgun`, `plasma`, `missile`, `hit`,
`engine_loop_small/medium/large`, `warp`, `menu_select`, `alarm`, `jingle_*`,
`robot_talk`, `alien_language`, `ambience_*`). Cached, optional at load (a
stripped build still boots), variants resolved through `random_stream`.

**`modules/common/juice/addon_vfx.gd`** — `AddonVfx`. Instantiates BinbunVFX
hit / impact / big-impact / air / ground / nuke / zap / ball scenes as one-shots
(freed on `finished` with a lifetime backstop), plus the animated
`assets/hit-effects` sprite flash. Owns a small pooled `AudioStreamPlayer3D` so
the destruction lab gets sound without the flight module.

**`modules/style/scripts/toon_override.gd`** — `ToonOverride`. One switch that
forces every element into the project's toon path (hulls, rocks, stations,
planets); exposes the UltimateToonSource `stylized.gdshader` for anything
wanting a conventional toon material.

**`modules/common/juice/tools/fx_smoke.gd`** — headless check for all three
layers, including "the addon's `main` animation is actually reachable".

### Sound: library replaces the synth where a match exists

`SpaceAudio`'s bank is now filled from `Sfx` first (weapons, engine loop,
alarms, menu, singularity drone) and falls back to the procedural synth for
everything the library has no asset for — explosions, impacts, collisions — and
for all of it when the toggle is off. `refresh_bank()` re-picks the bank so the
switch is audible immediately. New `play_hit()` and `play_ui_select()`.

### Muzzle particles now spawn at the gun

`SystemsSim._spawn_shot` used to push the *muzzle transform* clear of the hull
before calling `_muzzle_fx`, so every muzzle flash and spark burst appeared out
ahead of the nose. Only the projectile's spawn point is offset now; the flash
stays on the barrel tip.

### Player ship no longer renders black

With the default `cartoony` profile (`shading_bands = 3`), `ship_part.gdshader`
cut the self-lit floor to 16% of albedo and the toon `light()` branch could
return zero diffuse on a facet facing away from every light — the shadow side of
the hull was darker than the void behind it. The floor is now 45%, the toon band
has a 16% minimum, and a `toon_override` uniform joins the profile dial as a
second way into the stepped path.

### Palette now reaches planets

`Planet.apply_palette()` blends the authored colours onto the active palette's
planet roles from a snapshot taken on first call, so switching palettes twice
does not compound. Anchored at `PALETTE_MIX = 0.7` so a system's worlds still
read as individuals. `StyleManager._push_to_planets` walks it down to every
live planet alongside the toon flag; with no palette active it is a no-op, which
keeps the default look untouched. `Planet._process` also gained the null guard
it needed for the add_child-before-configure window.

### Destruction lab: pick, spawn, compare

A `🧪 COMPARE EFFECTS` panel drives one catalog of every effect (Juice blasts
and waves, the addon scenes, the sprite flash, the camera-origin strikes). Pick
one and `Spawn Selected at Target (C)`, or `Compare Row (V)` to lay every
position-centred effect out in a line — spaced by a slider, across the camera's
right vector — and watch them side by side. Strikes that originate at the
camera are excluded from the row. A `🎚 LAYERS (A/B)` section carries the four
toggles. Shockwave ring, spherical blast wave, EMP wave and the ripple rings are
all still there and in the catalog.

### Brackeys particle controls

Enabled as an editor plugin in `project.godot` (preview/scrub particles in the
3D view without touching the inspector).

### Vendored BinbunVFX addon actually loads now

The addon shipped with `res://assets/BinbunVFX_Vol2/...` internal paths (it was
authored for that folder), stale UIDs, and its `AnimationPlayer` libraries in
Godot 3's `libraries/ = SubResource(...)` form — which Godot 4 parses as an
empty library, so the scenes loaded, looked fine, and never played. All 16
scene files had their paths repointed to `res://addons/...`, 23 had their
libraries rewritten to the Godot 4 `libraries = { &"": ... }` form, and the 184
stale `uid=` attributes on `ext_resource` lines were dropped.

### Verified

`fx_smoke`, `juice_smoke`, `planet_smoke`, `core_smoke`, `destruction_lab_smoke`,
`events_smoke`, `flight_smoke`, `flight_bridge_smoke`, `profile_cycle_check`,
`control_mode_check`, `aggro_indicator_check`, `chaos_check`, `high_res_check`,
`mother_check`, `scale_check`, `ship_hull_check`, `interact_smoke`,
`large_craft_gen_smoke`, `physics_smoke`, `physics_lab_smoke`, `smoke_test`,
`solar_system_gen_*`, `palette_smoke`, `style_smoke`, `style_lab_smoke` all pass.

Pre-existing failures left alone (none touch the files edited here): `orbit_check`
and `sat_check` (the ×4 / fast-orbit time-scale path in `flight_model`),
`features_check` (drift-field thickness and mote stretch), and `arena_check`
(calls a `set_throttle` that `ArenaRoot` does not have).