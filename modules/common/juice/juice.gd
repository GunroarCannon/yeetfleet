## The one place the whole project calls for screen shake, flashes, hitstop,
## pooled particle/light/ring one-shots, UI motion helpers and haptics.
##
## Same idiom as [BuilderTheme] and [ShipMaterials]: a static facade with no
## instance to hold, so any script anywhere calls e.g. `Juice.shake(...)`
## without first finding or wiring a node. Unlike those two, several of its
## calls need per-frame state — a shake has to decay, a flash has to fade — so
## [Juice] lazily installs a [JuiceRuntime] under the scene tree's root the
## first time anything asks for that state, rather than depending on a
## `project.godot` autoload entry.
##
## That choice is deliberate: this project's `--script` tool runs
## (`smoke_test.gd`, `ui_shot.gd`, `flight_smoke.gd`, and this module's own
## `juice_smoke.gd`) are its standard of proof, and an autoload that behaved
## differently — or not at all — under `--script` would undermine them. There is
## always a [SceneTree] by the time any of this project's code runs, so the
## lazy install never has to fall back further than that.
##
## [b]Juice never writes another node's transform.[/b] [method shake_offset_3d]
## and [method shake_rotation_3d] are read, not applied — [FlightCamera] and
## [OrbitCamera] stay the only things that ever touch their own [Transform3D].
## See `juice-and-more.md`, ground rule 5.
class_name Juice
extends RefCounted

enum HapticKind { LIGHT, MEDIUM, HEAVY }

static var _runtime: JuiceRuntime = null


# --- Screen shake ----------------------------------------------------------

## Adds undirected trauma — an impact with no single origin, or several summed
## at once. [param strength] is 0..1; see [JuiceShake] for how trauma combines.
static func shake(strength: float, duration := 0.35, source := "") -> void:
	_ensure().shake_add(strength, duration, source)


## A directional impulse — recoil, a hit from a known direction — layered on top
## of trauma shake. See [JuiceShake].
static func kick(world_dir: Vector3, strength: float) -> void:
	_ensure().kick(world_dir, strength)


## Metres. Read by a camera rig each frame and added to its own transform —
## never written here. See the class doc comment.
static func shake_offset_3d() -> Vector3:
	return _ensure().shake_offset_3d()


## Radians (pitch, yaw, roll).
static func shake_rotation_3d() -> Vector3:
	return _ensure().shake_rotation_3d()


## Pixels, for HUD elements that shake with the frame.
static func shake_offset_2d() -> Vector2:
	return _ensure().shake_offset_2d()


# --- Screen effects ----------------------------------------------------------

static func flash(color: Color, strength := 0.5, decay := 0.25) -> void:
	_ensure().flash(color, strength, decay)


## A directional-feeling pulse at the screen edge — used for damage and refused
## actions, where a full flash would read as far too strong.
static func vignette(color: Color, strength: float, decay: float) -> void:
	_ensure().vignette(color, strength, decay)


## OFF by default in flight — see `juice-and-more.md` §6. Capped at 60 ms and
## skipped entirely under reduce_motion regardless of what is asked for.
static func hitstop(seconds := 0.05, scale := 0.15) -> void:
	_ensure().hitstop(seconds, scale)


## A real freeze-frame: time all but stops for [param seconds] of real time
## (capped at [constant JuiceRuntime.FREEZE_MAX]). [param depth] 1 = a dead
## stop, 0.5 = half speed. Skipped under reduce_motion. Shares
## [method hitstop_factor] with [method hitstop], so a scene that writes the
## time scale itself picks it up the same way.
static func freeze(seconds: float, depth := 1.0) -> void:
	_ensure().freeze(seconds, depth)


## The live hitstop slow-down, 1.0 when none is running. For a scene that
## writes [member Engine.time_scale] itself every frame: multiply this in, or
## the freeze-frame is cancelled the frame after it starts.
static func hitstop_factor() -> float:
	return _ensure().hitstop_factor


## Continuous, 0..1 — how close to top speed the caller is, not a one-shot.
static func speed_lines(fraction: float) -> void:
	_ensure().speed_lines(fraction)


# --- 3D one-shots --------------------------------------------------------

static func burst(
	preset: BurstPresets.Preset, xform: Transform3D, scale := 1.0, color := Color.TRANSPARENT
) -> void:
	if not AddonVfx.worth_spawning(xform.origin, 2500.0):
		return
	_ensure().burst(preset, xform, scale, color)


static func light_pop(position: Vector3, color: Color, energy: float, decay := 0.12) -> void:
	if not AddonVfx.worth_spawning(position, 2500.0):
		return
	_ensure().light_pop(position, color, energy, decay)


static func ring(xform: Transform3D, radius: float, color: Color, life := 0.4) -> void:
	if not AddonVfx.worth_spawning(xform.origin, 2500.0):
		return
	_ensure().ring(xform, radius, color, life)


# --- UI ------------------------------------------------------------------

static func pop(node: Control, amount := 0.12) -> void:
	JuiceTween.pop(node, amount)


static func nudge(node: Control, dir: Vector2) -> void:
	JuiceTween.nudge(node, dir)


static func pulse(node: CanvasItem, color: Color, times := 1) -> void:
	JuiceTween.pulse(node, color, times)


static func roll_number(label: Label, from: float, to: float, fmt: String) -> void:
	JuiceTween.roll_number(label, from, to, fmt)


## Mobile only; a no-op everywhere else and under reduce_motion.
static func haptic(kind: HapticKind) -> void:
	if JuiceSettings.reduce_motion or not OS.has_feature("mobile"):
		return
	match kind:
		HapticKind.LIGHT:
			Input.vibrate_handheld(20)
		HapticKind.MEDIUM:
			Input.vibrate_handheld(40)
		HapticKind.HEAVY:
			Input.vibrate_handheld(80)


# --- Settings ------------------------------------------------------------

static func intensity() -> float:
	return JuiceSettings.intensity


static func set_intensity(value: float) -> void:
	JuiceSettings.set_intensity(value)


static func reduce_motion() -> bool:
	return JuiceSettings.reduce_motion


static func set_reduce_motion(value: bool) -> void:
	JuiceSettings.set_reduce_motion(value)


# --- Runtime lifecycle -----------------------------------------------------

## Returns the installed [JuiceRuntime], installing it first if this is the
## first call since the scene tree started — or restarted, which a `--script`
## test fixture that tears down and rebuilds its own tree can trigger.
static func _ensure() -> JuiceRuntime:
	if _runtime == null or not is_instance_valid(_runtime) or not _runtime.is_inside_tree():
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			_runtime = JuiceRuntime.new()
			_runtime.name = "JuiceRuntime"
			(loop as SceneTree).root.add_child(_runtime)
		else:
			# No scene tree at all cannot happen in practice, but degrade to a
			# throwaway, unparented runtime instead of crashing every caller.
			return JuiceRuntime.new()
	return _runtime
