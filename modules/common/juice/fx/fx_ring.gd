## A small pool of expanding, fading additive quads: weapon-impact shockwaves in
## flight, and the "part landed here" confirmation in the builder. The pool
## recycles round-robin, same as [FxLight] and [ParticleBurst].
class_name FxRing
extends Node3D

const COUNT := 12

var _rings: Array[MeshInstance3D] = []
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
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	for i in COUNT:
		var mi := MeshInstance3D.new()
		mi.name = "FxRing%d" % i
		mi.mesh = mesh
		mi.material_override = ShipMaterials.glow_material(Color.WHITE, true)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rings.append(mi)
	set_process(true)


func spawn(xform: Transform3D, radius: float, color: Color, life: float) -> void:
	var slot := _cursor
	_cursor = (_cursor + 1) % COUNT
	var mi := _rings[slot]
	mi.global_transform = xform
	mi.scale = Vector3.ONE * 0.05
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
		var scale_now := lerpf(0.05, _radius[i] * 2.0, frac)
		_rings[i].scale = Vector3(scale_now, scale_now, scale_now)
		var mat := _rings[i].material_override as StandardMaterial3D
		if mat != null:
			var c := _color[i]
			mat.albedo_color = Color(c.r, c.g, c.b, c.a * (1.0 - frac))
