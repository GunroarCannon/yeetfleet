## A small pool of expanding, fading additive quads: weapon-impact shockwaves in
## flight, and the "part landed here" confirmation in the builder. The pool
## recycles round-robin, same as [FxLight] and [ParticleBurst].
class_name FxRing
extends Node3D

## Halved from 24 — 12 simultaneous shockwave rings is the observed ceiling in
## the heaviest firefights. Fewer slots = fewer MeshInstance3D draw calls.
const COUNT := 12

var _rings: Array[MeshInstance3D] = []
## Cached material refs so _process never casts material_override each frame.
var _mats: Array[StandardMaterial3D] = []
var _remaining: PackedFloat32Array = []
var _life_total: PackedFloat32Array = []
var _radius: PackedFloat32Array = []
var _color: Array[Color] = []
var _cursor := 0


func _ready() -> void:
	top_level = true
	_remaining.resize(COUNT)
	_life_total.resize(COUNT)
	_radius.resize(COUNT)
	_color.resize(COUNT)
	# Shared TorusMesh — every ring is the same geometry scaled at runtime.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 24         # was 36 — saves ~33% of torus vertices per instance
	tm.ring_segments = 8  # was 12
	for i in COUNT:
		var mi := MeshInstance3D.new()
		mi.name = "FxRing%d" % i
		mi.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.WHITE
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.disable_receive_shadows = true
		mi.material_override = mat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rings.append(mi)
		_mats.append(mat)
	set_process(true)


func spawn(xform: Transform3D, radius: float, color: Color, life: float) -> void:
	var slot := _cursor
	_cursor = (_cursor + 1) % COUNT
	var mi: MeshInstance3D = _rings[slot]
	if mi.is_inside_tree():
		mi.global_transform = xform
	else:
		mi.transform = xform
	mi.scale = Vector3(0.05, 0.02, 0.05)
	mi.visible = true
	_color[slot] = color
	_radius[slot] = maxf(radius, 0.01)
	_life_total[slot] = maxf(life, 0.01)
	_remaining[slot] = life


func _process(delta: float) -> void:
	for i in COUNT:
		if _remaining[i] <= 0.0:
			continue
		_remaining[i] -= delta
		if _remaining[i] <= 0.0:
			_rings[i].visible = false
			continue
		var frac := 1.0 - (_remaining[i] / _life_total[i])
		var ease_t := 1.0 - pow(1.0 - frac, 3.0)
		var scale_now := lerpf(0.05, _radius[i] * 2.0, ease_t)
		var thickness_y := clampf(scale_now * 0.012, 0.02, 0.18)
		_rings[i].scale = Vector3(scale_now, thickness_y, scale_now)
		var c := _color[i]
		var alpha := pow(1.0 - frac, 1.6)
		# Use cached ref — no cast, no property lookup in the hot path.
		_mats[i].albedo_color = Color(c.r, c.g, c.b, c.a * alpha)
		_mats[i].emission = c
		_mats[i].emission_energy_multiplier = 4.5 * alpha

