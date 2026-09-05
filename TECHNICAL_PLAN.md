# Project Nebula — Technical Plan

**Companion to:** `GAMEDOC.md`
**Version:** 2026-09-05
**Engine:** Godot 4.5, GL Compatibility renderer
**Targets:** PC and mobile

---

## Part 0 — Ground rules

### 0.1 The module isolation contract

You want to work on two modules at once without them colliding. That requires a
rule stronger than "put files in different folders." Every new module obeys all
four of these:

1. **One entry point.** A module exposes exactly one `class_name` façade. Nobody
   outside the module names any other class inside it.
2. **No upward node lookups.** No `get_parent()`, no `find_child("...")`, no
   walking the tree to find `FlightRoot`. Dependencies arrive through a
   `NebulaContext` handed in at construction.
3. **Signals out, calls in.** A module never calls another module. It emits.
   The scene root wires signals together — that wiring is the only place two
   modules meet, and it is a file you can read in one screen.
4. **Headless-testable.** Every module ships a `tools/<name>_smoke.gd` that runs
   under `--headless` with no scene, no window, no other module.

If a change to module A requires opening a file in module B, the contract has
been broken and that is the bug to fix first.

### 0.2 The shared context

```gdscript
# modules/core/scripts/nebula_context.gd
class_name NebulaContext extends RefCounted

var phys: PhysWorld          # modules/physics
var gravity: GravitySystem   # existing
var style: StyleProfile      # modules/style
var events: IncidentDirector # modules/events
var reputation: RepStore     # modules/reputation
var rng: RandomNumberGenerator  # ONE seeded source, see 0.3
```

Built once by whichever scene root is running. Fields may be `null` — every
module must run with a partially-filled context, because the physics lab has no
events and the style lab has no physics. **Null-check, do not assume.**

### 0.3 Determinism

The design promise is *predictable rules*. That is only verifiable if runs
reproduce. One seeded `RandomNumberGenerator` lives on the context and is
threaded to everything that rolls dice. `_rng.randomize()` is banned outside
tools. A seed is printed at session start and can be forced with
`--seed=<n>` so a bug report is a number, not a video.

---

## Part 1 — What actually exists today

An honest audit, because the plan is only useful relative to the real starting
point.

### Strong and reusable

| System | Where | State |
|---|---|---|
| **Ship builder** | `modules/ship_builder/` (~3,400 lines) | Complete. Parts from JSON, sockets, mirroring, undo, autosave, stat derivation, procedural low-poly mesh generation, custom PBR-ish shader. |
| **Flight model** | `modules/flight/scripts/flight_model.gd` (663) | Hand-integrated 6DOF, three assist modes, boost tied to a capacitor, quick-turn, control-mode presets. Well documented, well tuned. |
| **Gravity + orbits** | `modules/common/ai/gravity_system.gd` (363) | Genuinely good. Dominant-body softmax blending, derived relevance ranges, orbital elements, escape velocity, Hill spheres. This is the pinball table and it already works. |
| **AI** | `modules/common/ai/` (~2,600 lines) | 31 faction archetypes, group behaviours, formations, spawner, combat. Deep — it is missing *consequences*, not intelligence. |
| **Planets** | `modules/common/planets/` | Procedural surface/cloud/ring shaders, `PlanetData` resource with ~30 exported dials, an in-game editor. |
| **Juice** | `modules/common/juice/` | Shake, kick, flash, vignette, hitstop, particles, haptics, speed lines, with intensity + reduce-motion settings. |
| **Damage** | `modules/flight/scripts/damage_system.gd` (273) | Parts physically break off on impact and apply stat penalties. |

### Not built at all

Missions · economy · reputation storage · cargo · docking · pickups ·
in-world event signalling · style switching · ship-to-ship collision ·
save/load beyond ship designs · export presets · version control.

### The elephant

`modules/alien_face_gen/` is ~75 files and is registered as the project's only
autoload (`FaceGen`). It is a **separate product** sharing the repo, and
`PROGRESS.md` / `DECISIONS.md` document *only it* — neither mentions the space
game. See §3.4.

---

## Part 2 — The module plan

Build order follows your priority: **physics + bump-to-interact → style lab →
events → faction memory**, with one prerequisite in front.

```
modules/
  core/          M0  context, module registry, launcher      [prerequisite]
  physics/       M1  impulse bus, broadphase, profiles
  physics_lab/   M1  cartoony flight bench with live dials
  interact/      M2  bump-to-interact, pickups, tow
  style/         M3  global look toggle, roundness pipeline
  style_lab/     M3  ship + planet side by side with dials
  events/        M4  incident director, event bubbles, icon language
  reputation/    M5  faction memory, witnesses, grudges
```

---

### M0 — `modules/core/` (prerequisite, small)

**Why first:** four new modules cannot hang off `FlightRoot` as it stands. It
is 1,771 lines holding six static vars of global state and four hardcoded
`change_scene_to_file` paths. Six scenes need a real launcher.

```
modules/core/
  scripts/
    nebula_context.gd      # §0.2
    module_registry.gd     # id -> scene path, display name, icon
    session.gd             # seed, current mode (SANDBOX/CAREER), settings load
  core.tscn                # the launcher / module picker
  tools/core_smoke.gd
```

- `ModuleRegistry` replaces every hardcoded scene constant
  (`arena_root.gd:12-13`, `builder_root.gd:29`, `flight_root.gd:903,1599`).
- `project.godot`'s `main_run_args="--module=ship_builder"` is currently read by
  **nothing**. `Session` makes it real: `--module=<id>` selects the boot scene.
- Extract `FlightRoot`'s statics (`_planet_scale`, `_planet_spacing`,
  `_persist_location`, `_high_res_on`, `_trail_*`) into `Session`.

**Cost:** ~1–2 days. **Unblocks:** everything else in parallel.

---

### M1 — `modules/physics/` + `modules/physics_lab/`

The feel bet. Everything in the gamedoc depends on this being good.

#### Approach: custom impulse layer over the existing integrator

`FlightModel` keeps its hand-integration — it is tuned, testable, and cheap.
What it loses is collision. Collision moves into a shared layer where **every
actor can push every other actor**, which is exactly what today's code cannot do.

```
modules/physics/
  scripts/
    phys_body.gd        # a registry entry: mass, radius, velocity, angular, layer
    phys_world.gd       # the per-scene service; steps after all controllers
    broadphase.gd       # uniform spatial hash
    impulse_solver.gd   # pair resolution: linear + angular + separation
    phys_profile.gd     # Resource: every tunable constant
    ccd.gd              # swept sphere test for fast movers
  data/profiles/
    grounded.tres
    cartoony.tres
  tools/
    physics_smoke.gd    # headless, deterministic, no scene
```

#### `PhysBody`

```gdscript
class_name PhysBody extends RefCounted

var node: Node3D
var mass := 1.0             # tonnes; from ShipStats.mass, or rock volume
var radius := 1.0           # collision sphere; from the design's bounds
var velocity := Vector3.ZERO   # written by the controller, modified by the solver
var angular := Vector3.ZERO    # rad/s, body frame
var inv_inertia := 1.0      # 1 / (mass * radius^2 * INERTIA_K)
var restitution := 0.4
var layer := Layer.SHIP     # SHIP | ROCK | DEBRIS | PICKUP | STATIC
var mask := 0xFF
var kinematic := false      # planets, stations: infinite mass, never pushed
var faction_id := -1        # for blame attribution -> M5
var last_pusher := -1       # who last hit this, and when

signal impacted(other: PhysBody, impulse: float, point: Vector3, normal: Vector3)
```

#### Tick order (this is the whole design)

```
_physics_process(delta), priority ascending:

  0   FlightModel._integrate_rotation()      unchanged
  0   FlightModel._integrate_translation()   unchanged, minus _check_collision()
      └─ writes body.velocity, does NOT move the node
  0   AiShip behaviour                       unchanged
 100  PhysWorld.step(delta):
        1. broadphase.rebuild()              spatial hash, cell = 2 * max_radius
        2. for each candidate pair:
             swept sphere test (CCD when speed*delta > radius * CCD_RATIO)
        3. impulse_solver.resolve(a, b):
             j = -(1+e) * v_rel·n / (1/ma + 1/mb)
             a.velocity -= n * j / ma
             b.velocity += n * j / mb          <-- the line that did not exist
             off-centre component -> angular impulse on both
        4. positional correction (Baumgarte, with slop)
        5. emit impacted() on both
        6. integrate: node.global_position += velocity * delta
```

Step 3's second line is the entire difference between the current game and the
one in the gamedoc. Today only the player's velocity is ever changed by a
collision; nothing is ever knocked anywhere.

#### `PhysProfile` — the physics-lab dials

Every one of these is a live slider in the lab and a field in a `.tres`. The
two shipped profiles are `grounded` and `cartoony`; the lab writes a third.

| Dial | Range | What it does |
|---|---|---|
| `mass_influence` | 0–1 | How much `ShipStats.mass` differentiates response. 0 = every ship bounces alike (today), 1 = a hauler is a wrecking ball |
| `restitution_ship` / `_rock` / `_planet` | 0–1 | Bounciness per pair. Cartoony wants ~0.75; grounded ~0.35 |
| `knock_transfer` | 0–1 | Fraction of momentum handed to the thing you hit. The "asteroid goes flying" knob |
| `impulse_to_spin` | 0–1 | How much an off-centre hit becomes angular momentum. **The knob that makes recovery a skill** |
| `spin_damp_free` / `_assist` | s⁻¹ | How fast an induced tumble decays per mode |
| `boost_impulse` | m/s | Magnitude of the recovery boost (currently a thrust multiplier, must become an impulse) |
| `boost_cooldown` | s | Gates recovery so it is a decision, not a hold |
| `assist_lockout_on_impact` | s | **Critical.** How long assists and orbital assist stay disengaged after a hit, so the consequence is visible (see §3.1 #6) |
| `hitstop_scale` / `_max` | – | Routes impact magnitude into the existing `Juice.hitstop()` |
| `squash_amount` / `_recovery` | – | Cartoony visual deformation on impact (M3 consumes it) |
| `gravity_g` | – | Currently the hard constant `GravitySystem.GAME_G = 3.0` |
| `gravity_falloff` | 1.5–2.0 | Exponent. Below 2.0 gravity reaches further and slingshots get dramatic and cartoonish |
| `ccd_ratio` | 0.2–1.0 | Fraction of radius per frame above which the swept test engages |
| `max_pairs_per_step` | int | The mobile safety valve |

#### `modules/physics_lab/`

A dedicated scene, not a mode of the flight test. One ship, a handful of rocks,
one planet, a wall of sliders bound to a live `PhysProfile`, plus:

- **Repeat button** — re-runs the exact same impact with the current dials, so
  A/B comparison is honest.
- **Ghost trail** of the previous run overlaid on the current one.
- **Save profile as .tres** — the lab is how `cartoony.tres` gets authored.
- Preset scenarios: *glancing rock · head-on rock · rock into rock · ram a
  hauler · scatter a swarm · slingshot*.

#### `physics_smoke.gd` must assert

- Conservation of momentum across a pair collision, within 1e-4.
- Identical seed + identical inputs → identical positions after 600 steps.
- A 15,000 m/s body does not pass through a 10 m sphere (CCD).
- 300 bodies × 600 steps completes within the frame budget headlessly.

**Cost:** ~1.5–2 weeks including tuning. **This is the milestone that decides
whether the game is good.**

---

### M2 — `modules/interact/`

Bump-to-interact. Small, and it rides entirely on M1's `impacted` signal.

```
modules/interact/
  scripts/
    touchable.gd         # component attached to any Node3D with a PhysBody
    pickup.gd            # touch -> collect; radius scales with ship
    tow_link.gd          # touch a disabled ship -> soft spring constraint
    cargo_attach.gd      # touch a mission ship -> CARGO ATTACHED
    interact_registry.gd # the module façade
  tools/interact_smoke.gd
```

`Touchable` has one virtual: `on_touch(other: PhysBody, impulse: float)`. That
is the whole extension point. A crate, a mission ship, an explosive barrel and
a faction beacon are four subclasses, not four systems.

Emits `touched(what, by, impulse)` for M4/M5 to consume. Knows nothing about
missions or factions.

**Cost:** ~3–4 days on top of M1.

---

### M3 — `modules/style/` + `modules/style_lab/`

One global toggle: **Grounded ⟷ Friendly**.

```
modules/style/
  scripts/
    style_profile.gd     # Resource: every look dial
    style_manager.gd     # static: current profile, style_changed signal, apply()
    mesh_rounding.gd     # bevel + inflate + proportion pass over LowPoly output
    palette.gd           # one palette definition both looks derive from
  data/profiles/
    grounded.tres
    friendly.tres
  tools/style_smoke.gd

modules/style_lab/
  style_lab.tscn         # a ship and a planet, side by side, dials between them
  scripts/style_lab_root.gd
```

#### `StyleProfile` — the style-lab dials

| Dial | Effect | Live or reload |
|---|---|---|
| `roundness` 0–1 | Bevel width + normal smoothing in `LowPoly` | **reload** (mesh cache) |
| `chunkiness` 0–1 | Proportion scaling — fatter, stubbier parts | **reload** |
| `rock_potato` 0–1 | Subdivision + noise smoothing on asteroids | **reload** |
| `shading_bands` 0–5 | 0 = smooth gradient, 2–3 = friendly ramp | live |
| `outline_width` / `_color` | Ink outline on hulls and rocks | live |
| `spec_amount` / `rim_amount` | Kill specular and rim for the soft look | live |
| `palette_saturation` / `_lift` | Pastel-ise the whole palette at once | live |
| `planet_detail` / `planet_bands` | Noisy realistic ⟶ 3 flat colour bands | live |
| `star_count` / `star_size` | 900 small ⟶ a few big soft ones | live |
| `squash_enabled` | Consumes `PhysProfile.squash_amount` for impact deformation | live |

#### The reload problem, and the honest answer

`PartMeshFactory._cache` is keyed `"part_id|mirror"`
(`part_mesh_factory.gd:31,37`). A roundness change makes every cached mesh
stale. Two options, and we take the second:

1. Add roundness to the cache key → memory doubles per style, but no reload.
2. **`PartMeshFactory.clear_cache()` + rebuild + scene reload.** Simpler,
   already has the method, and the gamedoc explicitly permits a reload.

So: **shading dials apply live; geometry dials reload the scene.** The lab
shows which is which on each slider, and batches geometry changes behind an
Apply button so you are not reloading on every drag.

#### Unifying the three existing style statics

There are currently three unrelated global look toggles:
`ShipMaterials.high_contrast` (`ship_materials.gd:30`), `Planet.high_detail`
(`planet.gd:43`), `Theme.high_contrast` (`theme.gd:70`). `StyleManager`
subsumes all three so there is one switch, not four.

**Cost:** ~1 week for the shader/palette half, ~1 week for `mesh_rounding.gd`.

---

### M4 — `modules/events/`

The incident director and the visual language.

```
modules/events/
  scripts/
    incident.gd            # base: setup(context), tick(delta), is_done()
    incident_director.gd   # budget, spacing, spawn near-but-not-on the player
    event_bubble.gd        # the ~1.5s HUD bloom, then it never speaks again
    world_marker.gd        # the 🚨 🎯 📦 ◆ vocabulary as billboarded sprites
    incidents/
      distress_call.gd
      pirate_raid.gd
      cargo_request.gd
      derelict_tumble.gd
      meteor_strike.gd
      faction_skirmish.gd
      rare_drift.gd
  data/icons.json          # the §9 table, as data
  tools/events_smoke.gd
```

**Director rules**

- A budget, not a timer: at most *N* live incidents, at most one within *R*
  metres of the player, minimum *T* seconds between bubbles.
- Incidents spawn **just outside** perception and drift in, so the player
  discovers them rather than watching them pop.
- An incident has no accept step and no completion UI. It resolves itself if
  ignored — that is what makes ignoring it feel real.
- Every incident is a **physics arrangement**: bodies with velocities near each
  other. The director's real job is putting mass where the player will hit it.

Consumes M1 (`impacted`) and M2 (`touched`). Emits `incident_resolved(id, how,
who)` for M5.

**Cost:** ~1.5 weeks for the director plus 4–5 incident types.

---

### M5 — `modules/reputation/`

Faction memory. Session-scoped now, persistence-ready by construction.

```
modules/reputation/
  scripts/
    rep_store.gd           # ABSTRACT interface — the swap point
    session_rep_store.gd   # in-memory implementation (now)
    saved_rep_store.gd     # user:// implementation (later, no consumer changes)
    grudge.gd              # who, what, how bad, when, decay
    witness.gd             # line-of-sight + range check: did anyone SEE it?
    recognition.gd         # a patrol identifying your ship
  tools/reputation_smoke.gd
```

The persistence swap you asked for is one line in `NebulaContext`:

```gdscript
context.reputation = SessionRepStore.new()   # today
context.reputation = SavedRepStore.new()     # later — nothing else changes
```

Which means `RepStore`'s interface must be serialisable from day one: plain
dictionaries and ints, no node references, no `Callable`s stored in state.

**Witness is the design-critical part.** A grudge is only created if a faction
ship actually observed the act. Ram a hauler with nobody watching and nothing
happens — which is *itself* a game mechanic, and it is the difference between
"the universe remembers" and "the universe has a reputation number."

**No reputation bar in the UI.** The only expression is behaviour:
`IDENTIFIED: HOSTILE` and a patrol that turns toward you.

**Cost:** ~1 week.

---

### Cross-cutting: the plane-locked arcade scene

`modules/flight/arcade_plane.tscn` — the same `FlightModel`, the same
`PhysWorld`, with a constraint component that zeroes the off-plane velocity
component and maps pitch to plane-normal banking. **A constraint, not a second
physics implementation.** Roughly a day, once M1 exists.

---

## Part 3 — What is missing, what must change, what does not work

Ranked by how directly it blocks the gamedoc.

### 3.1 Blocking bugs and design conflicts in the physics

**1. Nothing can be pushed. Collision is one-directional.**
`flight_model.gd:461-517`. `_check_collision()` modifies only `self.velocity`.
Asteroids are `MultiMesh` instances with position/radius stored as immutable
metadata (`space_scene.gd:735,783`); there is no code path that moves a rock.
→ *The single most important line in the game does not exist.* Fixed by M1.

**2. There is no ship-to-ship collision at all.**
AI ships share `FlightModel`, so they collide with planets and rocks — never
with each other or with you. `ai_ship.gd:5` claims they "participate in the same
physics and collision systems"; that is true only for scenery. The pileup in
the gamedoc's headline example is currently impossible. Fixed by M1.

**3. Collisions cannot impart spin.**
`angular` (`flight_model.gd:_integrate_rotation`) is a *commanded* rate that is
lerped toward stick input and damped toward zero. `_check_collision()` never
touches it. "You spin, then you boost to recover" — the loop the gamedoc is
built on — cannot happen. Needs `impulse_to_spin` + real angular momentum. M1.

**4. Mass does not affect flight.**
`ShipStats.mass` exists and is summed, but `FlightModel.configure()` derives
only `top_speed`, `accel`, `turn_rate` from stats. Collision response uses fixed
restitution (`0.6` planets `flight_model.gd:479`, `0.25` rocks `:511`) and a
hardcoded minimum outward speed. **A scout and a cargo hauler bounce
identically.** Directly contradicts gamedoc §5. M1 (`mass_influence`).

**5. The hardcoded minimum bounce kills bump-to-interact.**
`flight_model.gd:481`: `var min_speed := maxf(30.0, impact_speed * 0.4)`. Every
contact, however gentle, ejects you at ≥30 m/s. You cannot nudge, tow, dock, or
touch a crate. Must become a profile dial with a floor of zero. M1/M2.

**6. The orbital assist silently deletes consequences.**
`flight_model.gd:533` `_apply_orbital_assist()` lerps velocity toward circular
orbit whenever the player is coasting near a body. A player knocked off course
gets quietly corrected — exactly the "assist that undoes the story" the gamedoc
bans (§14). Needs `assist_lockout_on_impact`. M1.

**7. Tunneling at speed. Two ways.**
   - No swept collision anywhere. At 520 m/s the ship moves 8.7 m per frame,
     against rocks of radius ~3–10 m. Clipping straight through is routine.
   - Worse under gravity: `flight_model.gd:387` caps fall speed at
     `top_speed * 30.0` ≈ 15,600 m/s → **260 m per frame**, versus a 1,400 m
     planet radius. A fast fall passes through a planet without registering.
   → Needs CCD (`ccd.gd`). M1.

**8. `break  # one rock per frame`** (`flight_model.gd:516`). Flying into a
cluster resolves one rock and ignores the rest. In a game about ricocheting
through debris this is the wrong behaviour by design. M1.

**9. Belt collision is hardcoded to one belt at the origin.**
`flight_model.gd:498`: `if dist_from_origin > 3000.0 or absf(pos.y) > 250.0`.
These constants do not scale with `FlightRoot._planet_scale` /
`_planet_spacing`, and a second belt anywhere else silently has no collision at
all. Replaced by the spatial hash. M1.

**10. O(n·m) collision that is about to become O(n²).**
Every ship checks all 260 rocks every frame. Add ship-vs-ship and debris and it
does not fit in the mobile budget. Uniform spatial hash, cell = 2× max radius.
M1.

### 3.2 Correctness and hygiene

**11. Private field reached across a module boundary.**
`flight_model.gd:466` reads `gravity._bodies[i]` directly. Add
`GravitySystem.body_at(i)` before four more modules depend on the private array.

**12. Unconditional per-second `print` in the hot path.**
`flight_model.gd:606` prints `[ORBIT] …` every second, for every ship with a
`FlightModel` — including AI. Move behind a debug flag on `Session`.

**13. Collision radii are magic numbers unrelated to ship size.**
`body.radius + 5.0` (`:470`) and `rock_radius + 3.0` (`:506`). A capital ship
and a scout collide at the same standoff. Radius must come from the design's
bounds. M1.

**14. Three orthonormalise passes per frame per ship.**
`_integrate_rotation`, `_update_visual_roll` and `_update_quick_turn` each read,
mutate and write `global_transform` in sequence. Correct today, but a real
angular-momentum model must own the basis in exactly one place. M1.

**15. Hitstop is not wired to impacts.** `Juice.hitstop()` exists
(`juice.gd:75`) and is never called from a collision. The cartoony profile wants
it on every hit, scaled by impulse. M1.

**16. Non-reproducible AI.** `ai_ship.gd:79` calls `_rng.randomize()`. Breaks
§0.3. Thread the context RNG.

**17. `--module=` is fiction.** `project.godot` sets
`main_run_args="--module=ship_builder"`, and nothing anywhere reads it — the
only `get_cmdline_user_args()` calls are in screenshot tools. Scene switching is
four hardcoded string constants. M0.

**18. Stray build artefacts.** Three Godot crash leftovers in the repo:
`modules/flight/flight_test.tscn16733913567.tmp` and two siblings. Delete.

**19. A stray CJK fragment** in `ai_factions.gd:51` (`"高aggression, 智能 target
selection"`). Cosmetic, but a marker that the file was machine-edited without
review — worth a read-through of that file.

### 3.3 Architectural blockers for parallel work

**20. `FlightRoot` is a 1,771-line god object** holding six static globals and
every scene-switch path. Four new modules cannot attach to it without
conflicting. `flight_hud.gd` (928) and `space_scene.gd` (880) are next in line.
M0 extracts the globals into `Session`; the HUD split can wait until M4 needs
event bubbles in it.

**21. No version control.** The repo is not a git repository. You have asked to
work on two modules simultaneously; without branches that is a merge you do by
hand, and without history a bad physics-tuning session is unrecoverable. **This
is the highest-value 30 seconds in the whole plan** — `git init`, commit the
current state, then start M0.

**22. No tests outside the face generator.** `tests/` contains only
`face_gen/verify_00..12`. Everything else is a smoke tool that needs a window.
The physics work *cannot* be done safely without deterministic headless tests —
"predictable rules" is a testable claim, and it should be tested.

**23. No export presets.** No `export_presets.cfg` exists, so neither PC nor
mobile has ever been built. `window/handheld/orientation=6` and
`stretch/mode="canvas_items"` show mobile intent, untested. Build both targets
*now*, while the project is small enough that a failure is diagnosable.

### 3.4 Documentation and scope

**24. The docs describe a different project.** `PROGRESS.md` and `DECISIONS.md`
document only the alien face generator — 12 phases, none about the space game.
`AI_USE_CASES.md`, `juice-and-more.md` and `freebuff_changes.md` (35k, 29k,
28k) are working notes, not specs. `GAMEDOC.md` and this file are now the
sources of truth; the others should be moved to `docs/archive/` with a one-line
header saying what they were.

**25. `GAMEPLAY_IDEAS.md` conflicts with the gamedoc.** Ideas 2, 4, 7, 9, 13,
15, 16 are all menu-and-contract shaped ("accept the contract at a station").
Under §8 they must be re-expressed as physical objects or deferred to Career.
Re-tag the file rather than delete it — the ideas are fine, the delivery is not.

**26. `FaceGen` is an autoload for a module the space game never calls.** It
costs boot time and a global. Either make it lazy, or move
`modules/alien_face_gen/` to its own repository. It is a good module; it is not
this game.

### 3.5 Missing systems (greenfield, no code exists)

| System | Needed by | Module |
|---|---|---|
| Cargo as a physical object | §8 cargo runs | M2 |
| Pickups / touch-to-collect | §7 | M2 |
| Tow constraint | §8 rescue | M2 |
| In-world icon vocabulary | §9 | M4 |
| Event bubbles | §10 | M4 |
| Incident director | §10 | M4 |
| Witness / recognition | §11 | M5 |
| Grudges | §11 | M5 |
| Faction physical signatures (magnetic, explosive, heavy) | §11 | M1 profiles + M5 |
| Economy, stations, contracts | Career mode | deferred |
| Save/load beyond ship designs | Career mode | deferred |

---

## Part 4 — Budgets and risks

### Performance ceiling (set by mobile)

| Budget | Target |
|---|---|
| Active `PhysBody` count | ≤ 300 (≈40 ships, ≈200 rocks in range, ≈60 debris/pickups) |
| Broadphase pairs per step | ≤ 1,500, hard-capped by `max_pairs_per_step` |
| Physics step | ≤ 4 ms on a mid-range phone |
| Draw calls | unchanged — rocks stay `MultiMesh`; only *near* rocks get a `PhysBody` |

The key trick: **rocks are promoted to physics bodies only inside a radius
around the player**, and demoted back into the `MultiMesh` when they leave. A
rock knocked out of the sphere keeps its velocity as baked metadata.

### The three real risks

1. **The feel does not land.** Mitigated by building `physics_lab` alongside
   `physics`, never after it — the dials are the deliverable, not a bonus.
2. **The chaos becomes noise.** Gamedoc §2 is the acceptance test: after ten
   minutes a player must be able to predict a collision outcome. If they cannot,
   turn down `impulse_to_spin` and `knock_transfer` before adding anything.
3. **Module isolation erodes.** The first `get_parent()` that sneaks in is the
   one that ends parallel work. §0.1 is not a style preference.

### Recommended order

```
NOW      git init + commit + delete the three .tmp files      (30 min)
M0       modules/core: context, registry, launcher            (1-2 days)
M1       modules/physics + physics_lab                        (1.5-2 weeks)  <- the bet
M2       modules/interact                                     (3-4 days)
   ---- from here M3 and M4 can run in parallel ----
M3       modules/style + style_lab                            (2 weeks)
M4       modules/events                                       (1.5 weeks)
M5       modules/reputation                                   (1 week)
later    plane-locked arcade scene, Career shell, persistence
```

M3 and M4 touch disjoint files and can genuinely be worked simultaneously —
which is the reason M0 exists at all.
