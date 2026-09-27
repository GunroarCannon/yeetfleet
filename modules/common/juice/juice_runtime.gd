## The node [Juice] lazily installs under the scene tree's root. Owns everything
## that has to tick every frame or hold pooled children: the shake model,
## hitstop, the screen-flash overlay, and the fixed-size [FxLight]/[FxRing]/
## [ParticleBurst] pools every one-shot draws from.
class_name JuiceRuntime
extends Node

var shake := JuiceShake.new()

var speed_lines_fraction := 0.0

## Current hitstop slow-down (1.0 = none). A scene that sets
## [member Engine.time_scale] itself every frame (FlightRoot's time warp) must
## multiply this in, or it cancels the freeze-frame on the very next frame.
## That turned every hitstop into a one-frame hiccup that read as the ship
## jerking.
var hitstop_factor := 1.0
## Real-time end of the current hitstop, in [method Time.get_ticks_msec].
## Real time rather than delta, because delta itself is slowed by the hitstop.
var _hitstop_end_ms := 0
var _base_time_scale := 1.0

var _screen_flash: ScreenFlash = null
var _light_pool: FxLight = null
var _ring_pool: FxRing = null
var _burst_pools: Dictionary = {}   # BurstPresets.Preset -> ParticleBurst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pools here are placed per render frame; interpolating them would only
	# drag them a physics tick behind where they were put.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	JuiceSettings.ensure_loaded()
	set_process(true)


func _process(delta: float) -> void:
	shake.update(delta)
	if hitstop_factor < 1.0 and Time.get_ticks_msec() >= _hitstop_end_ms:
		hitstop_factor = 1.0
		Engine.time_scale = _base_time_scale


# --- Shake -------------------------------------------------------------------

func shake_add(strength: float, _duration: float, _source: String) -> void:
	if JuiceSettings.reduce_motion:
		return
	shake.add_trauma(clampf(strength, 0.0, 1.0) * JuiceSettings.intensity)


func kick(world_dir: Vector3, strength: float) -> void:
	if JuiceSettings.reduce_motion:
		return
	shake.add_kick(world_dir, strength * JuiceSettings.intensity)


func shake_offset_3d() -> Vector3:
	return Vector3.ZERO if JuiceSettings.reduce_motion else shake.offset_3d()


func shake_rotation_3d() -> Vector3:
	return Vector3.ZERO if JuiceSettings.reduce_motion else shake.rotation_3d()


func shake_offset_2d() -> Vector2:
	return Vector2.ZERO if JuiceSettings.reduce_motion else shake.offset_2d()


# --- Screen effects ------------------------------------------------------

func flash(color: Color, strength: float, decay: float) -> void:
	if JuiceSettings.reduce_motion:
		return
	_ensure_flash().flash(color, strength * JuiceSettings.intensity, decay)


func vignette(color: Color, strength: float, decay: float) -> void:
	if JuiceSettings.reduce_motion:
		return
	_ensure_flash().vignette(color, strength * JuiceSettings.intensity, decay)


## Off by default in flight, capped short, and skipped entirely under
## reduce_motion — see `juice-and-more.md` §6 on hitstop fighting a
## `_physics_process`-based flight model.
func hitstop(seconds: float, scale: float) -> void:
	if JuiceSettings.reduce_motion or seconds <= 0.0:
		return
	_slow(minf(seconds, 0.06), clampf(scale, 0.01, 1.0))


## A real freeze-frame (see [method Juice.freeze]): unlike [method hitstop],
## which is a short slow-down capped at 60 ms, this all but stops time for up
## to [constant FREEZE_MAX] real seconds. [param depth] 1 = a dead stop.
func freeze(seconds: float, depth: float) -> void:
	if JuiceSettings.reduce_motion or seconds <= 0.0 or depth <= 0.0:
		return
	_slow(minf(seconds, FREEZE_MAX), lerpf(1.0, FREEZE_FLOOR, clampf(depth, 0.0, 1.0)))


## Longest freeze [method freeze] will run, in real seconds.
const FREEZE_MAX := 0.6
## The slowest a freeze goes. Never exactly zero: a zero time scale hands every
## `_process` a zero delta, and a divide by delta anywhere would blow up.
const FREEZE_FLOOR := 0.002


func _slow(seconds: float, factor: float) -> void:
	if hitstop_factor >= 1.0:
		_base_time_scale = Engine.time_scale
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	_hitstop_end_ms = maxi(_hitstop_end_ms, end_ms)
	hitstop_factor = minf(hitstop_factor, factor)
	Engine.time_scale = _base_time_scale * hitstop_factor


func speed_lines(fraction: float) -> void:
	speed_lines_fraction = 0.0 if JuiceSettings.reduce_motion else clampf(fraction, 0.0, 1.0)
	if _screen_flash != null:
		_screen_flash.set_speed_lines(speed_lines_fraction)


# --- 3D one-shots --------------------------------------------------------

func burst(preset: int, xform: Transform3D, scale: float, color: Color) -> void:
	if JuiceSettings.reduce_motion:
		return
	_ensure_burst(preset).emit(xform, scale * JuiceSettings.intensity, color)


func light_pop(position: Vector3, color: Color, energy: float, decay: float) -> void:
	_ensure_light_pool().pop(position, color, energy * JuiceSettings.intensity, decay)


func ring(xform: Transform3D, radius: float, color: Color, life: float) -> void:
	if JuiceSettings.reduce_motion:
		return
	_ensure_ring_pool().spawn(xform, radius, color, life)


# --- Lazy pools ------------------------------------------------------------
#
# Built on first use rather than in [method _ready]: a `--script` run that only
# exercises shake and settings — most of them — never pays for a CanvasLayer, a
# light pool, or six MultiMeshes it will never touch.

func _ensure_flash() -> ScreenFlash:
	if _screen_flash == null:
		_screen_flash = ScreenFlash.new()
		add_child(_screen_flash)
	return _screen_flash


func _ensure_light_pool() -> FxLight:
	if _light_pool == null:
		_light_pool = FxLight.new()
		add_child(_light_pool)
	return _light_pool


func _ensure_ring_pool() -> FxRing:
	if _ring_pool == null:
		_ring_pool = FxRing.new()
		add_child(_ring_pool)
	return _ring_pool


func _ensure_burst(preset: int) -> ParticleBurst:
	if not _burst_pools.has(preset):
		var burst_node := ParticleBurst.new()
		burst_node.preset = preset
		add_child(burst_node)
		_burst_pools[preset] = burst_node
	return _burst_pools[preset]
