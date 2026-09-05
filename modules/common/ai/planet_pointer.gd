## Points the ship at the nearest planet or moon — a line to the surface plus a
## target ring, so "which way is the nearest body" is a glance instead of a
## scan. The debug cousin of [GravityVisualizer], sharing its construction
## pattern (Node3D + ImmediateMesh, meshes only in the tree while on, to avoid
## empty-ImmediateMesh artifacts on the GL Compatibility renderer).
class_name PlanetPointer
extends Node3D


var _gravity: GravitySystem
var _ship: FlightModel
var _mesh: MeshInstance3D = null
var _im: ImmediateMesh = null
var _visible := false


func setup(gravity_system: GravitySystem, ship: FlightModel) -> void:
	_gravity = gravity_system
	_ship = ship


func toggle() -> void:
	_visible = not _visible
	if _visible:
		_create_mesh()
	else:
		_destroy_mesh()


func is_showing() -> bool:
	return _visible


func _create_mesh() -> void:
	_destroy_mesh()
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.name = "PlanetPointer"
	_mesh.mesh = _im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 102
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The pointer lines span kilometres — never let frustum culling hide them.
	_mesh.extra_cull_margin = 60000.0
	add_child(_mesh)


func _destroy_mesh() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.queue_free()
	_mesh = null
	_im = null


func _process(_delta: float) -> void:
	if not _visible or _gravity == null or _ship == null or _im == null:
		return
	_im.clear_surfaces()

	var ship_pos := _ship.global_position
	var body := _gravity.nearest_body(ship_pos)
	if body == null:
		return

	# --- Faint lines to every other body, so the field of planets reads at a
	# glance even when the nearest one is behind the ship ----------------------
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var dim := Color(0.4, 0.8, 1.0, 0.25)
	for i in _gravity.body_count():
		var other := _gravity._bodies[i] if i < _gravity._bodies.size() else null
		if other == null or other == body:
			continue
		var to_other := other.position - ship_pos
		var d_other := maxf(to_other.length(), 0.01)
		var s_other := ship_pos + to_other / d_other * minf(d_other - other.radius, d_other)
		_im.surface_set_color(dim)
		_im.surface_add_vertex(ship_pos)
		_im.surface_set_color(dim * 0.5)
		_im.surface_add_vertex(s_other)

	# --- Bright pointer to the nearest body -----------------------------------
	var to_body := body.position - ship_pos
	var dist := maxf(to_body.length(), 0.01)
	var dir := to_body / dist
	# Line from the ship all the way to the body's surface (the nearest side).
	var surface := body.position - dir * body.radius
	var col := Color(0.2, 0.95, 1.0, 1.0)
	_im.surface_set_color(col)
	_im.surface_add_vertex(ship_pos)
	_im.surface_set_color(col * 0.85)
	_im.surface_add_vertex(surface)

	# Target ring at the surface, facing the ship.
	var ring_r := maxf(body.radius * 0.16, 60.0)
	var up := dir.cross(Vector3.RIGHT)
	if up.length_squared() < 0.001:
		up = dir.cross(Vector3.UP)
	up = up.normalized()
	var side := dir.cross(up).normalized()
	var ring_col := Color(0.5, 1.0, 0.7, 0.95)
	var segs := 40
	var prev := surface + up * ring_r
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var point := surface + (up * cos(a) + side * sin(a)) * ring_r
		_im.surface_set_color(ring_col)
		_im.surface_add_vertex(prev)
		_im.surface_set_color(ring_col)
		_im.surface_add_vertex(point)
		prev = point

	# A small crosshair at the ship end of the line so the pointer is obvious
	# even before you trace it to the planet.
	var cross := 14.0
	var x1 := up * cross
	var x2 := side * cross
	for v in [x1, -x1, x2, -x2]:
		_im.surface_set_color(col)
		_im.surface_add_vertex(ship_pos - v * 0.5)
		_im.surface_set_color(col * 0.9)
		_im.surface_add_vertex(ship_pos + v * 0.5)
	_im.surface_end()
