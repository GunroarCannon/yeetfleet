## Visualises gravitational forces and orbital mechanics in real time.
##
## Draws force-line arrows from each gravitating body, shows the player's
## predicted orbit, and optionally outlines Hill spheres. Toggled with H key
## or via [method toggle].
##
## Mesh instances are only added to the scene tree when the visualizer is
## toggled ON and removed when toggled OFF, preventing any rendering
## artifacts from empty ImmediateMeshes on the GL Compatibility renderer.
class_name GravityVisualizer
extends Node3D


var show_force_lines := true
var show_orbit := true
var show_hill_spheres := false

var _gravity: GravitySystem
var _ship: FlightModel
var _force_mesh: MeshInstance3D = null
var _orbit_mesh: MeshInstance3D = null
var _hill_mesh: MeshInstance3D = null
var _force_im: ImmediateMesh = null
var _orbit_im: ImmediateMesh = null
var _hill_im: ImmediateMesh = null
var _visible := false


func setup(gravity_system: GravitySystem, ship: FlightModel) -> void:
	_gravity = gravity_system
	_ship = ship


func toggle() -> void:
	_visible = not _visible
	if _visible:
		_create_meshes()
	else:
		_destroy_meshes()


func is_showing() -> bool:
	return _visible


func _create_meshes() -> void:
	_destroy_meshes()

	_force_im = ImmediateMesh.new()
	_force_mesh = MeshInstance3D.new()
	_force_mesh.name = "ForceLines"
	_force_mesh.mesh = _force_im
	var force_mat := StandardMaterial3D.new()
	force_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	force_mat.no_depth_test = true
	# Per-vertex colours are what the draw code sets (amber shafts, fading
	# heads); without this flag StandardMaterial3D discards them and every line
	# renders the material's flat albedo.
	force_mat.vertex_color_use_as_albedo = true
	force_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.9)
	force_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	force_mat.render_priority = 100
	_force_mesh.material_override = force_mat
	_force_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_force_mesh)

	_orbit_im = ImmediateMesh.new()
	_orbit_mesh = MeshInstance3D.new()
	_orbit_mesh.name = "OrbitPath"
	_orbit_mesh.mesh = _orbit_im
	var orbit_mat := StandardMaterial3D.new()
	orbit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orbit_mat.no_depth_test = true
	orbit_mat.vertex_color_use_as_albedo = true
	orbit_mat.albedo_color = Color(0.3, 0.8, 1.0, 0.85)
	orbit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orbit_mat.render_priority = 101
	_orbit_mesh.material_override = orbit_mat
	_orbit_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orbit_mesh)

	_hill_im = ImmediateMesh.new()
	_hill_mesh = MeshInstance3D.new()
	_hill_mesh.name = "HillSpheres"
	_hill_mesh.mesh = _hill_im
	var hill_mat := StandardMaterial3D.new()
	hill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hill_mat.no_depth_test = true
	hill_mat.vertex_color_use_as_albedo = true
	hill_mat.albedo_color = Color(0.4, 1.0, 0.6, 0.3)
	hill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hill_mat.render_priority = 99
	_hill_mesh.material_override = hill_mat
	_hill_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hill_mesh)


func _destroy_meshes() -> void:
	for m in [_force_mesh, _orbit_mesh, _hill_mesh]:
		if m != null and is_instance_valid(m):
			m.queue_free()
	_force_mesh = null
	_orbit_mesh = null
	_hill_mesh = null
	_force_im = null
	_orbit_im = null
	_hill_im = null


func _process(_delta: float) -> void:
	if not _visible or _gravity == null or _ship == null:
		return
	_draw_force_lines()
	_draw_orbit_overlay()
	_draw_hill_spheres()


func _draw_force_lines() -> void:
	if _force_im == null:
		return
	_force_im.clear_surfaces()
	if not show_force_lines:
		return

	var ship_pos := _ship.global_position
	_force_im.surface_begin(Mesh.PRIMITIVE_LINES)

	for i in _gravity.body_count():
		var body := _gravity._bodies[i] if i < _gravity._bodies.size() else null
		if body == null:
			continue

		var to_body := body.position - ship_pos
		var dist := maxf(to_body.length(), 10.0)
		var force_dir := to_body.normalized()
		var force_mag := GravitySystem.GAME_G * body.mass / (dist * dist)
		if _gravity.mode == GravitySystem.GravityMode.HIGH:
			force_mag *= 2.0

		var arrow_len := clampf(log(force_mag * 1000.0 + 1.0) * 120.0, 20.0, 800.0)
		var arrow_end := ship_pos + force_dir * arrow_len

		var intensity := clampf(1.0 - dist / 5000.0, 0.1, 1.0)
		var col := Color(1.0, 0.6 * intensity, 0.2 * intensity, 0.95 * intensity)

		# Shaft.
		_force_im.surface_set_color(col)
		_force_im.surface_add_vertex(ship_pos)
		_force_im.surface_set_color(col * 0.5)
		_force_im.surface_add_vertex(arrow_end)

		# Arrowhead.
		var perp_a := force_dir.cross(Vector3.UP).normalized()
		if perp_a.length_squared() < 0.001:
			perp_a = force_dir.cross(Vector3.FORWARD).normalized()
		var head_size := arrow_len * 0.12
		_force_im.surface_set_color(col * 0.5)
		_force_im.surface_add_vertex(arrow_end)
		_force_im.surface_set_color(col * 0.3)
		_force_im.surface_add_vertex(arrow_end - force_dir * head_size + perp_a * head_size * 0.5)
		_force_im.surface_set_color(col * 0.5)
		_force_im.surface_add_vertex(arrow_end)
		_force_im.surface_set_color(col * 0.3)
		_force_im.surface_add_vertex(arrow_end - force_dir * head_size - perp_a * head_size * 0.5)

	_force_im.surface_end()


func _draw_orbit_overlay() -> void:
	if _orbit_im == null:
		return
	_orbit_im.clear_surfaces()
	if not show_orbit:
		return

	var ship_pos := _ship.global_position
	var ship_vel := _ship.velocity
	var dominant := _gravity.find_dominant_body(ship_pos)
	if dominant == null:
		return

	var dist := ship_pos.distance_to(dominant.position)
	var orbit_plane_normal := (ship_pos - dominant.position).cross(ship_vel).normalized()
	if orbit_plane_normal.length_squared() < 0.001:
		orbit_plane_normal = Vector3.UP
	var radial := (ship_pos - dominant.position).normalized()
	var tangent := orbit_plane_normal.cross(radial).normalized()

	_orbit_im.surface_begin(Mesh.PRIMITIVE_LINES)

	# --- Predicted orbit -------------------------------------------------
	var elems := _gravity.orbit_elements(dominant, ship_pos, ship_vel)
	if elems.is_empty():
		# Unbound (hyperbolic / parabolic): there is no closed ellipse to draw.
		# Show the escape direction in red so "you are leaving" reads instead of
		# the visualiser silently drawing nothing.
		var end := ship_pos + ship_vel.normalized() * 1400.0
		var red := Color(1.0, 0.25, 0.2, 0.95)
		_orbit_im.surface_set_color(red)
		_orbit_im.surface_add_vertex(ship_pos)
		_orbit_im.surface_set_color(red * 0.45)
		_orbit_im.surface_add_vertex(end)
	else:
		var a: float = elems.get("semi_major_axis", 1000.0)
		var e: float = elems.get("eccentricity", 0.0)
		var periapsis: float = elems.get("periapsis", a * (1.0 - e))
		# Rotate the ellipse so its periapsis lines up with the ship's current
		# true anomaly — otherwise a non-circular orbit is drawn pointing the
		# wrong way around the body.
		var cos_nu := 0.0
		if e > 0.0001:
			cos_nu = (a * (1.0 - e * e) / dist - 1.0) / e
		var sin_nu := signf(ship_vel.dot(radial)) * sqrt(maxf(1.0 - cos_nu * cos_nu, 0.0))
		var nu := atan2(sin_nu, cos_nu)
		var peri_dir := (radial * cos(nu) - tangent * sin(nu)).normalized()
		var perp_dir := orbit_plane_normal.cross(peri_dir).normalized()

		var segments := 64
		var prev_point := Vector3.ZERO
		var base_col := Color(0.35, 1.0, 0.55, 0.95)  # closed: a bound orbit
		for i in segments + 1:
			var true_anomaly := TAU * float(i) / float(segments)
			var rr := periapsis * (1.0 + e) / (1.0 + e * cos(true_anomaly))
			var point := dominant.position + (peri_dir * cos(true_anomaly) + perp_dir * sin(true_anomaly)) * rr
			if i > 0:
				var t := float(i) / float(segments)
				var col := base_col.lerp(base_col * 0.45, t)
				_orbit_im.surface_set_color(col)
				_orbit_im.surface_add_vertex(prev_point)
				_orbit_im.surface_set_color(col * 0.7)
				_orbit_im.surface_add_vertex(point)
			prev_point = point

	# --- Circular reference ring -----------------------------------------
	# The orbit the ship would hold right now if its speed matched the local
	# circular-orbit velocity. Red = falling in, green = matching, amber = too
	# fast and climbing out.
	var v_circ := _gravity.orbit_velocity(dominant, dist)
	var ratio := ship_vel.length() / v_circ if v_circ > 0.0 else 0.0
	var ref_col := Color(0.35, 1.0, 0.55, 0.9) if absf(ratio - 1.0) < 0.1 else (
		Color(1.0, 0.55, 0.2, 0.95) if ratio > 1.0 else Color(1.0, 0.3, 0.25, 0.95)
	)
	var segs := 48
	var prev := dominant.position + radial * dist
	for j in segs + 1:
		var ang := TAU * float(j) / float(segs)
		var point := dominant.position + (radial * cos(ang) + tangent * sin(ang)) * dist
		_orbit_im.surface_set_color(ref_col)
		_orbit_im.surface_add_vertex(prev)
		_orbit_im.surface_set_color(ref_col)
		_orbit_im.surface_add_vertex(point)
		prev = point

	_orbit_im.surface_end()


func _draw_hill_spheres() -> void:
	if _hill_im == null:
		return
	_hill_im.clear_surfaces()
	if not show_hill_spheres:
		return

	for i in _gravity.body_count():
		var body := _gravity._bodies[i] if i < _gravity._bodies.size() else null
		if body == null:
			continue
		var hill_r := _gravity.hill_sphere(body)
		_draw_wire_sphere(body.position, hill_r, 24, Color(0.4, 1.0, 0.6, 0.12))


func _draw_wire_sphere(centre: Vector3, radius: float, segments: int, color: Color) -> void:
	_hill_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		var u := Vector3.ZERO
		var v := Vector3.ZERO
		match axis:
			0: u = Vector3.RIGHT; v = Vector3.UP
			1: u = Vector3.RIGHT; v = Vector3.FORWARD
			2: u = Vector3.UP; v = Vector3.FORWARD
		var prev := centre + u * radius
		for j in segments + 1:
			var angle := TAU * float(j) / float(segments)
			var point := centre + (u * cos(angle) + v * sin(angle)) * radius
			_hill_im.surface_set_color(color)
			_hill_im.surface_add_vertex(prev)
			_hill_im.surface_set_color(color)
			_hill_im.surface_add_vertex(point)
			prev = point
	_hill_im.surface_end()
