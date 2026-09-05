## A short motion trail: a fading line strip drawn through where a ship has
## been, so the eye can read which way it is actually moving at a glance.
##
## Lives in world space ([member Node3D.top_level]), so the owner can be any
## moving node; the owner just feeds it world positions with [method add_point]
## every frame. Built from an [ImmediateMesh] line strip with per-vertex alpha
## fading tail→head — the same technique the planet pointer and gravity
## visualizer use, so it renders on GL Compatibility.
class_name Trail3D
extends Node3D

## Points kept before the oldest fall off.
const MAX_POINTS := 48
## Seconds a point lives before it has faded out completely.
const LIFETIME := 2.5
## Line width is a single pixel on GL Compatibility — enough, since the strip
## is unshaded colour against black and the eye reads direction long before it
## needs width.

var _points: Array = []  # [{pos: Vector3, age: float}]
var _mesh: ImmediateMesh
var _inst: MeshInstance3D
var _mat: StandardMaterial3D
var _tint := Color.WHITE
var _enabled := true


func _ready() -> void:
	top_level = true
	_mesh = ImmediateMesh.new()
	_inst = MeshInstance3D.new()
	_inst.name = "Trail"
	_inst.mesh = _mesh
	_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShipMaterials.line_material(Color.WHITE, true)
	# Per-vertex colour drives both the tint and the fade; albedo stays white.
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color.WHITE
	_inst.material_override = _mat
	add_child(_inst)
	set_color(_tint)


func set_color(color: Color) -> void:
	_tint = color


## Turn the trail on or off. Off also clears the strip so nothing lingers.
func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	if not on:
		_points.clear()
		if _mesh != null:
			_mesh.clear_surfaces()


func is_enabled() -> bool:
	return _enabled


func clear() -> void:
	_points.clear()
	if _mesh != null:
		_mesh.clear_surfaces()


## Feed a world-space position. Call every frame from the owner's update loop.
func add_point(world_pos: Vector3) -> void:
	if not _enabled:
		return
	_points.append({"pos": world_pos, "age": 0.0})
	if _points.size() > MAX_POINTS:
		_points.pop_front()


func _process(delta: float) -> void:
	if not _enabled or _mesh == null:
		return
	# Age every point; drop the ones that have faded past the end.
	if not _points.is_empty():
		var alive: Array = []
		for p in _points:
			p["age"] = float(p["age"]) + delta
			if float(p["age"]) < LIFETIME:
				alive.append(p)
		_points = alive

	if _points.size() < 2:
		_mesh.clear_surfaces()
		return

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _points:
		var t := 1.0 - clampf(float(p["age"]) / LIFETIME, 0.0, 1.0)
		_mesh.surface_set_color(Color(_tint.r, _tint.g, _tint.b, t))
		_mesh.surface_add_vertex(p["pos"] as Vector3)
	_mesh.surface_end()
