## One pooled [MultiMesh] emitter for a single [BurstPresets.Preset]. State lives
## in flat arrays rather than per-particle objects — no allocation once the pool
## is warm, and the whole live set is one draw call, the same trick [FlightRoot]
## already uses for its drift field and [SpaceScene] uses for its asteroid belt.
##
## When the pool is full, [method emit] recycles the oldest slot instead of
## dropping the new burst: a firefight thins out instead of popping particles out
## of existence, which reads as a budget rather than a bug.
class_name ParticleBurst
extends Node3D

var preset: BurstPresets.Preset = BurstPresets.Preset.SPARKS

var _capacity := 0
var _multimesh: MultiMesh
var _mesh_instance: MultiMeshInstance3D
var _config: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# Struct-of-arrays particle state, sized once in [method _ready] and never
# resized again.
var _position: PackedVector3Array = []
var _velocity: PackedVector3Array = []
var _life: PackedFloat32Array = []
var _life_total: PackedFloat32Array = []
var _spin: PackedFloat32Array = []
var _angle: PackedFloat32Array = []
var _size: PackedFloat32Array = []

## Round-robin write cursor. Landing on a dead slot reuses empty space; landing
## on a live one recycles it — the same line of code does both.
var _cursor := 0

## A dead slot is parked at this scale rather than exactly zero.
## [constant BaseMaterial3D.BILLBOARD_PARTICLES] derives its facing from the
## instance basis's column lengths; a literal zero-length basis is a divide by
## zero in that math, and on at least one driver the NaN it produces rasterizes
## as a full-screen quad instead of nothing. A near-zero scale keeps every dead
## slot genuinely invisible without that edge case.
const DEAD_SCALE := 0.0005


func _ready() -> void:
	top_level = true
	_config = BurstPresets.config(preset)
	_capacity = maxi(mini(int(_config.get("pool", 32)), BurstPresets.capacity()), 1)
	_rng.randomize()
	_build_multimesh()
	_position.resize(_capacity)
	_velocity.resize(_capacity)
	_life.resize(_capacity)
	_life_total.resize(_capacity)
	_spin.resize(_capacity)
	_angle.resize(_capacity)
	_size.resize(_capacity)
	set_process(true)


func capacity() -> int:
	return _capacity


func live_count() -> int:
	var n := 0
	for i in _capacity:
		if _life[i] > 0.0:
			n += 1
	return n


func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = quad
	_multimesh.instance_count = _capacity

	_mesh_instance = MultiMeshInstance3D.new()
	_mesh_instance.name = "Burst_" + BurstPresets.Preset.keys()[preset]
	_mesh_instance.multimesh = _multimesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 64.0

	var mat := ShaderMaterial.new()
	var shader := load("res://modules/common/juice/shaders/particle_circle.gdshader") as Shader
	if shader != null:
		mat.shader = shader
	# Particle-billboarded so the per-instance basis only has to carry rotation
	# and stretch; facing the camera is the material's job, not the state array's.
	#mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Use additive blending if the preset says so.
	var additive: bool = _config.get("additive", true)
	if additive:
		pass#mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	for i in _capacity:
		_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * DEAD_SCALE), Vector3.ZERO))


## Spawns this preset's particle count at [param xform]'s origin, travelling
## along random directions in [param xform]'s basis. [param scale] multiplies
## both speed and size, which is how [code]Juice.intensity[/code] reaches a
## burst without the preset table knowing anything about settings.
func emit(xform: Transform3D, scale := 1.0, _color := Color.TRANSPARENT) -> void:
	if _capacity <= 0 or scale <= 0.0:
		return
	var count: int = int(_config.get("count", 8))
	var life_range: Vector2 = _config.get("life", Vector2(0.3, 0.6))
	var size_range: Vector2 = _config.get("size", Vector2(0.05, 0.1))
	var speed_range: Vector2 = _config.get("speed", Vector2(1.0, 3.0))
	var spin_max: float = _config.get("spin", 0.0)
	for _i in count:
		var slot := _cursor
		_cursor = (_cursor + 1) % _capacity
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)
		).normalized()
		_position[slot] = xform.origin
		_velocity[slot] = xform.basis * dir * _rng.randf_range(speed_range.x, speed_range.y) * scale
		var total := _rng.randf_range(life_range.x, life_range.y)
		_life[slot] = total
		_life_total[slot] = total
		_spin[slot] = _rng.randf_range(-spin_max, spin_max)
		_angle[slot] = _rng.randf_range(0.0, TAU)
		_size[slot] = _rng.randf_range(size_range.x, size_range.y) * scale


func _process(delta: float) -> void:
	var gravity: float = _config.get("gravity", 0.0)
	var stretch: float = _config.get("stretch", 1.0)
	var color_from: Color = _config.get("color_from", Color.WHITE)
	var color_to: Color = _config.get("color_to", Color.WHITE)
	for i in _capacity:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * DEAD_SCALE), Vector3.ZERO))
			continue
		_velocity[i].y -= gravity * delta
		_position[i] += _velocity[i] * delta
		_angle[i] += _spin[i] * delta
		var frac: float = 1.0 - (_life[i] / _life_total[i])
		var speed := _velocity[i].length()
		var size_now := _size[i] * (1.0 - frac * 0.6)
		var basis := Basis(Vector3.FORWARD, _angle[i]).scaled(
			Vector3(size_now, size_now * (1.0 + speed * stretch * 0.05), 1.0)
		)
		_multimesh.set_instance_transform(i, Transform3D(basis, _position[i]))
		_multimesh.set_instance_color(i, color_from.lerp(color_to, frac))
