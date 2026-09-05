# Juice, and more

Plan for three things that are really one thing: a shared **juice layer** the whole
project can call, a **creation UI** that is pictures instead of paragraphs, and a
**flight view** that looks like the reference shots. Nothing here is implemented
yet — this file is the agreed shape of the work.

Reference images this plan is written against:

| Ref | What we are taking from it |
| --- | --- |
| 3 (No Man's Sky) | Coloured nebula wash filling the whole frame, ringed planet close enough to be scenery, long parallel tracer beams with soft bloom, asteroid field for scale, hot blue engine flares |
| 4 (Starfield) | Planet limb with an atmosphere arc, sun flare in frame, tumbling debris, an explosion with a white core and orange embers, dark hulls whose engines light their own plating |
| 5 (mobile space HUD) | Round icon buttons in the corners, arc gauges instead of bars, no word longer than four characters on screen, the middle of the screen empty |
| 6 (Battlevoid) | One tiny `MENU` pill and letterbox bars — art first, chrome reduced to a hairline frame |

---

## 0. Ground rules

These are constraints, not preferences, and every decision below is downstream of
them.

1. **`gl_compatibility` renderer** (`project.godot`). No reflection probes, no
   SSAO, no SDFGI. Glow support needs verifying before anything depends on it;
   `GPUParticles3D` is not trusted on old mobile GL, so particles are CPU-side
   `MultiMesh` (§1.4) in the style the project already uses for the drift field
   and the asteroid belt.
2. **One layout for a small landscape phone and a desktop.** Target the worst
   case: a **960×432** logical viewport. Anything permanently on screen has to
   earn its pixels there. `BuilderTheme.apply_density_scale` already makes one UI
   unit mean one dp, and `TOUCH_MIN = 44` still governs every tappable thing.
3. **Progressive disclosure stays the rule** (see the existing `DesignBar` and
   `ViewBar` doc comments). Juice does not get to reintroduce chrome.
4. **Verify by rendering, not by reasoning.** Every phase below ends with a
   command, and the screenshot phases are checked at both sizes.
5. **Juice never owns another node's transform.** `FlightCamera` and
   `OrbitCamera` are carefully written; the juice layer publishes offsets and
   they *ask* for them. This is the most important architectural rule in the
   plan — it is what keeps shake from fighting the chase camera's smoothing.

---

## 1. Part A — the juice layer

New top-level module, because juice belongs to neither existing module:

```
modules/common/juice/
  juice.gd              # class_name Juice          — static facade, the whole public API
  juice_runtime.gd      # class_name JuiceRuntime   — the node that ticks shake/flash/hitstop
  juice_settings.gd     # class_name JuiceSettings  — intensity, reduce_motion, persistence
  juice_shake.gd        # class_name JuiceShake     — trauma model, noise sampling
  juice_tween.gd        # class_name JuiceTween     — pop/punch/slide/pulse/roll helpers
  particles/
    particle_burst.gd   # class_name ParticleBurst  — pooled CPU MultiMesh emitter
    burst_presets.gd    # class_name BurstPresets   — sparks, debris, embers, vapour, streaks
  fx/
    screen_flash.gd     # class_name ScreenFlash    — full-screen flash + vignette CanvasLayer
    fx_light.gd         # class_name FxLight        — pooled OmniLight3D pops
    fx_ring.gd          # class_name FxRing         — expanding shock ring / weld ring quad
  shaders/
    plume.gdshader          # engine exhaust: additive core, heat wobble, boost stretch
    speed_lines.gdshader    # canvas: radial streaks + vignette that scale with speed
    flash_overlay.gdshader  # canvas: colour flash, damage vignette, boost frame flare
    limb_glow.gdshader      # planet atmosphere arc (ref 4)
    tracer.gdshader         # beam core with soft falloff and a travelling bright head
  tools/
    juice_smoke.gd      # headless correctness check for the layer itself
```

### 1.1 How it is reached

`Juice` is a static facade — the same shape as `BuilderTheme` and `ShipMaterials`,
which this codebase already reads as "the one place that owns X". It lazily
installs a `JuiceRuntime` node under the scene-tree root the first time anything
asks for per-frame state, so:

- game scenes get it for free with no `project.godot` autoload entry;
- `--script` tool runs (`smoke_test.gd`, `ui_shot.gd`, `flight_smoke.gd`) cannot
  crash on a missing autoload;
- headless runs work, because the runtime degrades to no-ops with no viewport.

*Alternative considered:* a real autoload. Rejected because the tool scripts are
this project's standard of proof, and an autoload that behaves differently under
`--script` would undermine them. If the lazy install ever proves awkward, adding
an `[autoload]` entry later is a two-line change.

### 1.2 Public API (sketch)

```gdscript
# --- Screen shake ---------------------------------------------------------
Juice.shake(strength: float, duration := 0.35, source := "")   # 0..1 trauma
Juice.kick(world_dir: Vector3, strength: float)                # directional impulse (recoil)
Juice.shake_offset_3d() -> Vector3                             # metres, read by camera rigs
Juice.shake_rotation_3d() -> Vector3                           # radians, pitch/yaw/roll
Juice.shake_offset_2d() -> Vector2                             # pixels, read by the HUD

# --- Screen effects ------------------------------------------------------
Juice.flash(color: Color, strength := 0.5, decay := 0.25)
Juice.vignette(color: Color, strength: float, decay: float)     # damage / error pulse
Juice.hitstop(seconds := 0.05, scale := 0.15)                   # OFF by default in flight
Juice.speed_lines(fraction: float)                              # 0..1, continuous

# --- 3D one-shots --------------------------------------------------------
Juice.burst(preset: int, xform: Transform3D, scale := 1.0, color := Color.TRANSPARENT)
Juice.light_pop(position: Vector3, color: Color, energy: float, decay := 0.12)
Juice.ring(xform: Transform3D, radius: float, color: Color, life := 0.4)

# --- UI ------------------------------------------------------------------
Juice.pop(node: Control, amount := 0.12)         # scale punch, settles with overshoot
Juice.nudge(node: Control, dir: Vector2)         # slide-in / rejection shove
Juice.pulse(node: Control, color: Color, times := 1)
Juice.roll_number(label: Label, from: float, to: float, fmt: String)
Juice.haptic(kind: int)                          # mobile only, no-op elsewhere

# --- Settings ------------------------------------------------------------
Juice.intensity         # 0..1.5, user slider, default 1.0
Juice.reduce_motion     # true kills shake/hitstop/streaks, keeps colour + scale cues
```

Every entry point multiplies by `intensity` and is short-circuited by
`reduce_motion`, in one place, so accessibility cannot be forgotten at a call
site. Both persist to `user://juice.cfg` and appear in both ☰ menus next to the
existing **High contrast** item.

### 1.3 Shake model

Trauma-based rather than "play a shake animation":

- Sources add trauma; total is `clamp(sum, 0, 1)`, so twelve guns firing at once
  do not produce twelve times the shake.
- Displacement is `trauma²` × amplitude, sampled from two out-of-phase noise
  channels. The squaring is what makes small hits feel small and big hits feel
  big.
- Exponential decay (`TRAUMA_DECAY ≈ 1.8/s`), so shake always returns to exactly
  zero — the smoke test asserts this.
- Separate translation and rotation amplitudes, **rotation-dominant**: translating
  a chase camera at 240 m/s reads as a glitch, rotating it reads as an impact.
- **Aim correctness.** Shake rotates the camera, which would drag the crosshair
  off the guns. So `FlightHud` stops drawing the reticle at screen centre and
  instead projects a point along the ship's own forward axis
  (`unproject_position(ship.origin - ship.basis.z * 600)`). The sight then stays
  glued to where the guns actually point while the frame shakes around it. This
  is a bug fix that shake would otherwise introduce.

### 1.4 The particle thing

`ParticleBurst` — one node, one `MultiMesh`, one draw call, no per-frame
allocation:

- State held struct-of-arrays in `PackedFloat32Array` / `PackedVector3Array`:
  position, velocity, life, spin, size, colour index. Capacity fixed at
  construction.
- One pool per preset, requested through `Juice.burst()`. When a pool is full the
  oldest particle is recycled rather than the burst dropped, so a firefight
  degrades in density instead of popping out of existence.
- Budget: **512** live particles on desktop, **192** when `OS.has_feature("mobile")`.
- `top_level = true` and a generous `extra_cull_margin`, for the same reason the
  drift field already sets one.

Presets in `BurstPresets`:

| Preset | Look | Used by |
| --- | --- | --- |
| `SPARKS` | Tiny additive streaks, white→amber ramp, 0.25–0.5 s | gun muzzles, impacts, the weld when a part lands |
| `DEBRIS` | Tumbling low-poly chunks in the ship's own palette, 1.5–3 s | hits, part deletion, destruction (ref 4) |
| `EMBERS` | Slow drifting glow motes, 2–4 s | after an explosion (ref 4) |
| `VAPOUR` | Dark expanding puffs, alpha-blended | thruster ignition, damage smoke trail |
| `STREAKS` | Motes stretched along the velocity vector | the speed cue, replacing the drift field |
| `RING_SPARK` | Sparks emitted on a socket ring | builder: a part snapping home |

`STREAKS` supersedes `FlightRoot._build_drift_field()`: same MultiMesh trick, but
each instance is scaled along the ship's velocity, so speed is legible from the
streak length and not only from parallax. The menu toggle stays.

### 1.5 Flash, lights, rings

- `ScreenFlash` is a `CanvasLayer` at layer 100 holding one `ColorRect` running
  `flash_overlay.gdshader`: additive colour flash, damage vignette, boost frame
  flare and the low-capacitor pulse are all uniforms, so it stays one draw.
- `FxLight` pools four `OmniLight3D`s. Four is the whole budget — muzzle flash,
  impact, explosion, engine — because under `gl_compatibility` every extra light
  is real per-pixel cost, and ref 4 needs exactly one thing from lights: a ship
  lit by its own engines and by what just hit it.
- `FxRing` is a single additive quad that expands and fades: shockwaves in flight,
  and the "part landed here" confirmation in the builder.

### 1.6 Cost budget

Juice must cost under **1.5 ms/frame** at phone size with everything firing,
enforced by the perf harness in Phase 7. If it does not fit, the order of
sacrifice is: bloom → extra lights → particle capacity → shake.

---

## 2. Part B — creation UI: fewer buttons, more picture

### 2.1 The problem, counted

Persistent controls in the builder today: ☰, name field, undo, redo, Parts
toggle, Stats toggle, search field, category dropdown, size dropdown, three
drag-mode buttons, View menu, four inspector tabs, the whole stat list, and one
button per catalogue part. On a 960×432 phone the two side panels alone
(300 + 320 dp) claim **more than the entire width**, and every part is a two-line
block of text.

### 2.2 The target: six persistent controls

Full-bleed viewport, ref 6's hairline framing, nothing between the player and the
ship except:

```
┌──────────────────────────────────────────────────────────┐
│ (☰)                    Kestrel II                   (↶) │   ← round, 44 dp
│   ╭ arc  arc  arc  arc ╮                                 │   ← drawn gauges, not buttons
│                                                          │
│                     ‹ the ship ›                         │
│                                                          │
│                                                (◎)       │   ← mode dial
│  ▢ ▢ ▢ ▢ ▢ ▢ ▢  ← part filmstrip →             (▶)      │   ← FLY
└──────────────────────────────────────────────────────────┘
```

1. **☰** (top-left, round) — rename, hull, example ships, save/open, JSON,
   contrast, **juice intensity + reduce motion**, help, walkthrough. Content
   unchanged; `DesignBar` already put it there.
2. **↶ Undo** (top-right, round). Redo *only appears once an undo has happened* —
   the rest of the time it is dead weight.
3. **Part filmstrip** (bottom, horizontally scrolling) — the palette, as pictures.
4. **◎ Mode dial** — one round button cycling LOOK / POSE / MOVE with a distinct
   glyph and colour per mode; long-press opens a three-way radial. Replaces the
   segmented row *and* the View menu, whose items (mounts, mount labels, fit,
   camera angles) move to the radial's outer ring.
5. **▶ FLY** (bottom-right, accent) — the primary verb, currently buried in ☰.
6. **Stat arcs** — a readout that is also a button: tap raises the full sheet.

The design name is a small dim label top-centre, ref 6's pill treatment. Search,
category and size filters exist **only while the filmstrip drawer is open**, as
one icon-triggered row. The four inspector tabs become a bottom sheet raised by
tapping a part, not a permanent column.

### 2.3 Part chips instead of part cards

The biggest "prioritise visuals" move: render each part's real mesh to a
thumbnail once, and cache it.

- New `modules/ship_builder/scripts/ui/part_thumbs.gd` (`class_name PartThumbs`):
  an off-screen 96×96 `SubViewport`, three-quarter camera, the same
  `ShipMaterials` part shader and stage lighting, geometry from
  `PartMeshFactory.build(part)`, output an `ImageTexture` keyed by part id.
  Generated lazily a few per frame so first paint is never blocked, cached in
  memory and optionally to `user://thumbs/` for warm starts.
- `PartCard` becomes `PartChip`: a 72×72 square — thumbnail, a 2 px category
  colour hairline, a single-glyph size dot in the corner, and **no body text**.
  The name and stat headline appear on the held or selected chip only; the full
  stat block stays in the tooltip and the sheet, which is also what keeps it
  available to a screen reader.
- Incompatible chips desaturate and dim instead of printing a rejection line. The
  reason moves to the tooltip and to a one-line toast on tap.

That turns the palette from a wall of prose into a rack of ship parts, which is
the thing a builder is actually choosing between.

### 2.4 Stat arcs

Four arcs in ref 5's radial vocabulary, replacing the always-open stat list:
**SPEED · TURN · HULL · POWER**, plus a thin mass ring that fills toward the
chassis limit and turns amber then red. Each arc draws its value with
`gauge_color()` and a ghost needle for the *preview* value that
`BuilderRoot.preview_changed` already emits. The existing `StatPanel` is reused
verbatim inside the tap-to-open sheet — no logic is thrown away, only its
permanent slot on screen.

### 2.5 Where the builder gets juicy

| Moment | Juice |
| --- | --- |
| Part placed | 3D scale pop (0.85 → 1.0, overshoot) on the new part, `RING_SPARK` + `FxRing` on the socket, one `FxLight` pop in the part's colour, small shake (0.08), haptic tick, and the chip pops in the filmstrip |
| Placement rejected | Chip shoves 6 px and returns, red `vignette` pulse, no shake (a rejection should not feel like an impact), toast |
| Part deleted | Part scales to 0.9 and fades, `DEBRIS` burst outward, dust ring, shake 0.12 |
| Socket focused | Marker ring pulses at ~1.6 Hz, unfocused sockets dim — cue by motion, not by colour alone |
| Stat change | Arc needle overshoots then settles, number rolls via `Juice.roll_number`, the changed arc flashes `delta_color()` once |
| Drag ghost | Existing `ghost.gdshader` gains a travelling scan line and brightens near a valid socket, so "this will snap here" needs no text |
| Hull swap / preset load | Ship assembles with a 0.25 s staggered pop outward from the root — the one deliberately showy animation, because it is the moment the player sees what they picked |
| Sheet / menu open | Scale-fade from 0.96 in the panel's own colour, 120 ms |
| Toast | Slides up with a small bounce instead of appearing |
| FLY pressed | Screen flash, plume ignition, then the scene change — the transition sells the button |

---

## 3. Part C — making flight look like the references

### 3.1 Give it a place to be

`flight_test.tscn` is deliberately empty black, and `SpaceScene` — star dome,
starfield, nebula band, planet, moon, station and a 260-rock asteroid belt, all
already written and lit — **is not instantiated anywhere**. Wiring it in is the
cheapest possible step toward refs 3 and 4.

- `FlightRoot` gains a location switch: `SpaceScene` by default, with the bare
  volume kept behind the ☰ menu as **Test volume**. That mode exists for a real
  reason (a flight-model change has to be measurable against nothing) and is not
  being deleted.
- `FlightCamera.space` is already declared and calls `recentre()`; only the
  assignment is missing.
- `landmarks()` returns the scene's landmarks, which the HUD already knows how to
  draw. `flight_smoke.gd`'s expectations get updated in the same commit.
- The streak field defaults **off** when `SpaceScene` is present — the belt is the
  speed cue there — and on in the test volume.

### 3.2 Environment

- **Nebula wash (ref 3).** Extend `SpaceScene._make_nebula_band` into two crossed
  gradient bands with vertex-colour ramps, teal→green and violet→blue, filling
  roughly a third of the frame instead of being a thin stripe. The sky stays dome
  *geometry* rather than a Sky shader — that choice already exists here and it
  survives on the compatibility renderer.
- **Planet limb (ref 4).** `limb_glow.gdshader` on a slightly larger inverted
  sphere around the planet: a view-dependent additive arc, brightest at the
  terminator. This single shader is most of what makes ref 4 read as space.
- **Sun and flare.** A bright disc plus two or three additive billboard petals
  along the screen-space axis to the sun, faded by its distance from view centre.
- **Bloom.** First verify `Environment.glow_enabled` under `gl_compatibility`. If
  it works: subtle, `glow_intensity ≈ 0.6`, HDR threshold above 1.0 so only
  emissives bloom. If it does not: fall back to a `BackBufferCopy` + bright-pass
  blur canvas shader, off by default on mobile. Either way the additive halos on
  plumes and tracers carry the look on their own — bloom is a bonus, never a
  dependency.
- Tonemap stays ACES, with `tonemap_white` dropped to about 2.6 so bright
  emissives clip to white the way they do in both references.

### 3.3 Engines — ref 3's blue flares, ref 4's warm dots

Replace `SystemsSim`'s two nested cones with a three-layer plume driven by
`plume.gdshader`:

1. a hot inner core, near-white at the throat, length ∝ throttle;
2. a coloured outer cone using `exhaust_color` from `func_data`, alpha falloff,
   UV wobble for heat shimmer;
3. an additive billboard halo at the nozzle — the layer that actually reads as
   "bright" when there is no bloom.

Plus: an `FxLight` at the largest nozzle tinted `exhaust_color`, which is the
ref-4 detail (the ship lit by its own engines); a `VAPOUR` puff on ignition from
zero; a `SPARKS` trickle under boost; and boost shifting colour toward white while
stretching length about 1.6× over a 0.12 s spool, so the throttle has a
sound-shaped visual.

### 3.4 Weapons — ref 3's long beams

- Tracers get `tracer.gdshader`: a bright travelling head, a soft body, a fading
  tail, additive. Length scales with `shot_speed`, so a slug reads as a bolt and a
  beam reads as a lance. Each shot also leaves a dim additive smear quad for one
  frame, which is what makes several guns read as ref 3's parallel beams.
- Muzzle: `SPARKS` burst, `FxLight` pop, a three-frame flash quad, `Juice.kick`
  backward along the barrel, and about 0.05 shake per shot — summed and clamped,
  so a twenty-gun broadside is emphatic rather than unusable.
- Impact (once there is something to hit): flash, `DEBRIS` + `SPARKS`, `FxRing`,
  shake 0.25, and an optional 40 ms hitstop.

### 3.5 Speed and motion

- `STREAKS` particles, stretched along velocity.
- FOV curve from 72° to 82° across the speed range, plus 6° more on boost, eased.
- The chase camera pulls further back and slightly lower at speed: the existing
  `CHASE_SPEED_STRETCH` grows, with an extra boost-only term.
- `speed_lines.gdshader` radial streaks and vignette, ramping in only above about
  70 % of top speed, hard off under `reduce_motion`.
- A near-field pass on the belt: a handful of small rocks placed *close* to the
  flight path, because the scale in ref 3 comes from having a 1.4 km planet and a
  3 m rock in the same frame.

### 3.6 Camera tilt and side effects

All inside `FlightCamera`, all reading `Juice` for shake, so the rig keeps sole
ownership of its transform:

| Effect | Detail |
| --- | --- |
| Bank into turn | Roll the view up to **7°** against sustained yaw, eased over 0.3 s. The biggest juice win in flight, and nearly free |
| Pitch lag | The camera trails about 3° behind hard pitch, then springs back |
| Boost dolly | Pull back 15 % and add FOV; snap forward on release |
| Impact kick | `Juice.kick()` rotates the rig away from the hit direction |
| Idle drift | ±0.15° sub-Hz noise, so a stationary ship is not a still photograph |
| Cockpit | Existing `COCKPIT_SWAY` gains a small translational bob and a `flash_overlay` frame flare on boost |

### 3.7 Destruction — last phase, and the reason it exists

Ref 4 is an explosion. To have one, and to be able to verify the juice stack at
all, the test bed gets one **practice drone**: a small assembled hull, no AI
beyond station-keeping, a hit box, hit points. Killing it plays the whole stack —
white flash core, `FxRing` shockwave, `DEBRIS` + `EMBERS` + `SPARKS`, an `FxLight`
pop, shake 0.6, 60 ms hitstop, haptic. Explicitly scoped as an FX target, not the
beginning of a combat system.

---

## 4. Part D — flight HUD, ref 5 style

### 4.1 Fewer, rounder

Today: ☰, a full-width target line, a view chip, an assist chip, a speed label, a
hint label, throttle, stick, FIRE, BOOST, plus the drawn reticle, drift marker and
power bars. Target:

| Corner | Control |
| --- | --- |
| Top-left | **☰** round — view, assist, respawn, hangar, streaks, contrast, **juice**, help |
| Top-right | Two round state buttons: **view** (glyph per mode) and **assist** (ring lit green or amber, no word) |
| Bottom-left | Throttle, redrawn as ref 5's curved tape: lever fill plus the actual-speed tick |
| Bottom-right | Stick, with the capacitor arc drawn *around* it, so power sits where the thumb is already looking |
| Inboard | **FIRE** and **BOOST** as round buttons, not labelled rectangles |

Dropped from the permanent layout: the target line (name and speed collapse to a
compact readout beside the reticle), the words "ASSIST"/"MANUAL" and "Chase", the
two straight power bars (now arcs), and the standing hint label — hints become
transient toasts.

### 4.2 HUD juice

- Reticle pulses on each shot, contracts toward the gun convergence point, and
  flares red on a blocked shot.
- Capacitor arc fills with overshoot; it pulses red and vignettes when a shot is
  refused for power, so the existing `fire_blocked` reason is a feeling first and
  a sentence second.
- Heat arc shimmers as it approaches the ceiling.
- Boost: frame flare, streak ramp, and the throttle tape glows.
- Assist toggle flashes the whole HUD in its state colour once, about 120 ms — one
  unmistakable signal for a change that alters how the ship flies.
- Every round button: 0.06 s press-scale plus haptic.
- Damage (once the drone shoots back, or on asteroid contact): a directional edge
  vignette showing where the hit came from.

---

## 5. Phases, in order, each with its proof

`GD` is the 4.5 binary at
`C:\Users\hmmm\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Godot_v4.5-stable_win64.exe`.
Every phase that adds a `class_name` starts with a class-cache rescan:
`"$GD" --path . --headless --editor --quit`.

| # | Phase | Files | Proof |
| --- | --- | --- | --- |
| 0 | **Juice core.** `Juice`, `JuiceRuntime`, `JuiceShake`, `JuiceSettings`, `JuiceTween`. No visual change anywhere | `modules/common/juice/*` | `juice_smoke.gd`: trauma clamps at 1, decays to exactly 0, `reduce_motion` zeroes every output, settings round-trip through `user://juice.cfg`, tween helpers complete and free themselves |
| 1 | **Primitives.** `ParticleBurst`, `BurstPresets`, `ScreenFlash`, `FxLight`, `FxRing`, and the shaders | `juice/particles`, `juice/fx`, `juice/shaders` | `juice_smoke.gd` grows: pools never exceed capacity, recycle instead of dropping, allocate nothing after warmup, leave no orphan nodes after 500 bursts |
| 2 | **Flight has a place.** Instantiate `SpaceScene`; test volume behind the menu; streaks replace motes; nebula, limb glow, sun flare, bloom decision | `flight_root.gd`, `space_scene.gd`, `flight_camera.gd` | `flight_smoke.gd` with updated expectations, plus a new `flight_shot.gd` at 1280×720 and 960×432, compared against refs 3 and 4 |
| 3 | **Engines and guns.** Plume rebuild, tracer shader, muzzle FX, impact FX | `systems_sim.gd`, shaders | `flight_shot.gd` with a scripted throttle-up and a burst of fire in frame; `smoke_test.gd` still green, since the builder shares `SystemsSim` |
| 4 | **Camera and HUD.** Bank, pitch lag, boost dolly, shake consumption, the reticle-on-gun-axis fix; HUD reduced to §4.1 and juiced | `flight_camera.gd`, `flight_hud.gd`, `throttle_lever.gd`, `virtual_stick.gd` | `flight_smoke.gd` (every control still wired) plus shots at both sizes; on-screen controls ≤ 7 |
| 5 | **Builder restructure.** Full-bleed viewport, filmstrip + `PartThumbs` + `PartChip`, stat arcs, mode dial, FLY, sheets | `ship_builder.tscn`, `part_palette.gd`, `part_card.gd`→`part_chip.gd`, `design_bar.gd`, `view_bar.gd`, new `stat_arcs.gd`, `part_thumbs.gd` | `smoke_test.gd`, plus `ui_shot.gd` at 1280×720 **and 960×432**; persistent controls = 6; thumbnails present and not blank |
| 6 | **Builder juice.** Every row of §2.5 | builder UI, `ship_view.gd` | `ui_shot.gd` mid-animation; `smoke_test.gd` green |
| 7 | **Destruction, tuning, perf.** Practice drone, explosion stack, one tuning pass over every constant, `reduce_motion` audit, frame-time harness | `flight_root.gd`, new `drone.gd`, `juice.gd` constants | `juice_perf.gd`: frame time at 960×432 with everything firing stays inside a 60 fps budget; every effect visibly off under `reduce_motion` |

Phases 0–1 are invisible and safe. Phase 2 has by far the best ratio of "looks
like the reference" to work done. Phases 5–6 are the biggest diff. Phase 7 is
where the numbers get taste applied.

---

## 6. Risks, and the fallback for each

| Risk | Fallback |
| --- | --- |
| `Environment` glow unsupported or ugly under `gl_compatibility` | Additive halo billboards on every emitter carry the look; canvas bright-pass bloom is opt-in and off on mobile |
| `GPUParticles3D` unreliable on old mobile GL | Never used — CPU `MultiMesh` from the start |
| Shake drags the crosshair off the guns | The reticle projects the ship's gun axis instead of drawing at screen centre (§1.3) |
| `hitstop` fights `_physics_process`-based flight | Off by default in flight, capped at 60 ms, kills only, one setting to disable |
| Phone frame budget | 1.5 ms cap with a named order of sacrifice (§1.6); mobile particle capacity is a third of desktop |
| `flight_smoke.gd` / `smoke_test.gd` break as the scenes change | Their expectations are updated in the same commit as the change; a phase is not done while a smoke test is red |
| Thumbnail generation stalls first paint | Lazy, a few per frame, placeholder glyph until ready, optional `user://thumbs/` cache |
| Juice buries the ship | `intensity` defaults to 1.0 but is a real slider, and Phase 7 tunes from screenshots rather than from argument |
| New `class_name`s break every parse | The class-cache rescan is the first command of every phase |

---

## 7. Out of scope

Named so they cannot creep in: combat AI, a damage model beyond the practice
drone, sound (juice is half sound, and it needs its own plan — this one leaves
hooks at every call site), station docking, multiple star systems, and any
settings screen beyond the two items added to the existing ☰ menus.
