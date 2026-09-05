## The node [Juice] lazily installs under the scene tree's root. Owns everything
## that has to tick every frame or hold pooled children: the shake model,
## hitstop, the screen-flash overlay, and the fixed-size [FxLight]/[FxRing]/
## [ParticleBurst] pools every one-shot draws from.
class_name JuiceRuntime
extends Node

var shake := JuiceShake.new()

var speed_lines_fraction := 0.0

var _hitstop_timer := 0.0

var _screen_flash: ScreenFlash = null
var _light_pool: FxLight = null
var _ring_pool: FxRing = null
var _burst_pools: Dictionary = {}   # BurstPresets.Preset -> ParticleBurst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	JuiceSettings.load_from_disk()
	set_process(true)


func _process(delta: float) -> void:
	shake.update(delta)
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0:
			Engine.time_scale = 1.0


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
	_hitstop_timer = minf(seconds, 0.06)
	Engine.time_scale = clampf(scale, 0.01, 1.0)


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
