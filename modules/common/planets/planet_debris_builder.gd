class_name PlanetDebrisBuilder
extends RefCounted

## Utility to generate realistic, diverse 3D planetary fragments (pyramids, irregular polyhedra,
## thick tectonic slabs) textured with the parent planet's procedural surface shader and molten mantle
## fracture walls, plus irregular 3D asteroid boulders and glowing core fragments.
## All pieces have physical collisions with player ships, AI ships, and other debris.

const SURFACE_SHADER_PATH := "res://modules/common/planets/shaders/planet_surface.gdshader"

## Spawns a complete set of physical planetary debris from an obliterated planet:
## - 3D pyramids and tapered crust-to-mantle wedges
## - Irregular 3D polyhedral monoliths and faceted prisms
## - Deep curved tectonic slabs with jagged fracture walls
## - Rocky mantle asteroids and superheated molten core boulders with realistic velocities
## - Dynamic dissipating core plasma flash (no static yellow core left behind)
## All pieces are registered with PhysWorld (if present) and Godot physics.
static func shatter_planet(
	planet: Planet,
	epicentre: Vector3,
	parent_node: Node,
	eject_force: float = 350.0,
	fineness: float = 1.0,
	phys_world: PhysWorld = null
) -> Dictionary:
	var results := {
		"crust_plates": [] as Array[RigidBody3D],
		"asteroids": [] as Array[RigidBody3D],
		"core": null,
	}
	if planet == null or not is_instance_valid(planet):
		return results
	if parent_node == null or not is_instance_valid(parent_node):
		return results

	# Read fineness from Session if not explicitly provided or invalid
	if fineness <= 0.0:
		fineness = Session.planet_break_fineness if Session.planet_break_fineness > 0.0 else 1.0

	# Auto-detect PhysWorld if not passed
	if phys_world == null:
		var cur: Node = parent_node
		while cur != null:
			if cur.get("phys_world") != null and cur.phys_world is PhysWorld:
				phys_world = cur.phys_world
				break
			cur = cur.get_parent()

	var p_pos := planet.global_position
	var p_data := planet.data
	var radius := p_data.planet_radius if p_data != null else 1000.0
	var surface_shader: Shader = load(SURFACE_SHADER_PATH) as Shader
	var mantle_mat := _make_mantle_material()

	# Scaling based on break fineness
	var safe_fineness := clampf(fineness, 0.35, 3.5)
	var count_mult := safe_fineness
	var geo_scale := 1.0 / sqrt(safe_fineness)

	var piece_count := clampi(roundi(randf_range(22, 32) * count_mult), 8, 64)
	var asteroid_count := clampi(roundi(randf_range(16, 26) * count_mult), 6, 54)
	var molten_core_count := clampi(roundi(randf_range(8, 14) * sqrt(safe_fineness)), 4, 20)

	var golden_ratio := (1.0 + sqrt(5.0)) / 2.0

	# 1. Spawn diverse 3D crust & mantle pieces (pyramids, irregular polyhedra, deep slabs)
	for i in piece_count:
		# Fibonacci sphere distribution for even coverage across planet surface
		var theta := TAU * float(i) / golden_ratio
		var phi := acos(1.0 - 2.0 * (float(i) + 0.5) / float(piece_count))
		var center_dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)).normalized()

		var angular_span := randf_range(0.24, 0.44) * geo_scale
		var depth := radius * randf_range(0.22, 0.58) * clampf(geo_scale, 0.7, 1.4)

		# Choose shape archetype:
		# 40% Pyramids / Tapered wedges
		# 35% Irregular chunky polyhedra / monoliths
		# 25% Deep curved tectonic slabs
		var shape_roll := randf()
		var piece: RigidBody3D = null

		if shape_roll < 0.40:
			# Pyramid / Tapered Wedge (3-sided or 4-sided)
			var is_quad := randf() < 0.5
			piece = _build_pyramid_piece(planet, p_pos, center_dir, radius, angular_span, depth, surface_shader, mantle_mat, is_quad)
		elif shape_roll < 0.75:
			# Irregular 3D Polyhedron / Chunky prism
			var pts_count := 4 if randf() < 0.65 else 5
			piece = _build_polyhedron_piece(planet, p_pos, center_dir, radius, angular_span, depth * 0.75, surface_shader, mantle_mat, pts_count)
		else:
			# Deep curved tectonic slab
			var thickness := radius * randf_range(0.12, 0.25) * geo_scale
			piece = _build_deep_slab_piece(planet, p_pos, center_dir, radius, angular_span, thickness, surface_shader, mantle_mat)

		if piece != null:
			parent_node.add_child(piece)

			# Ejection velocity away from blast epicentre + lateral swirl
			var blast_dir := (piece.position - epicentre).normalized()
			if blast_dir.length_squared() < 0.01:
				blast_dir = center_dir
			var swirl_axis := blast_dir.cross(Vector3.UP if absf(blast_dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
			var disp_dir := (blast_dir + swirl_axis.rotated(blast_dir, randf() * TAU) * randf_range(0.15, 0.40)).normalized()

			# Massive chunks move with lower speed but heavy momentum
			var speed := randf_range(eject_force * 0.35, eject_force * 1.1)
			var vel := disp_dir * speed
			var spin := Vector3(randf_range(-2.8, 2.8), randf_range(-2.8, 2.8), randf_range(-2.8, 2.8))
			var mass := maxf(radius * angular_span * 40.0 * geo_scale, 80.0)
			var bound_r := radius * angular_span * 0.7

			_register_physics(piece, vel, spin, mass, bound_r, phys_world, PhysBody.Layer.ROCK)
			_attach_cleanup_tween(piece, 120.0)
			results["crust_plates"].append(piece)

	# 2. Spawn Rocky Mantle Asteroids
	for j in asteroid_count:
		var phi_a := acos(randf_range(-1.0, 1.0))
		var theta_a := randf_range(0.0, TAU)
		var dir_a := Vector3(sin(phi_a) * cos(theta_a), sin(phi_a) * sin(theta_a), cos(phi_a)).normalized()
		var a_size := randf_range(radius * 0.05, radius * 0.20) * geo_scale
		var spawn_pos := p_pos + dir_a * randf_range(radius * 0.3, radius * 0.95)

		var ast := _build_asteroid_boulder(spawn_pos, a_size, false)
		parent_node.add_child(ast)

		var a_blast := (spawn_pos - epicentre).normalized()
		if a_blast.length_squared() < 0.01:
			a_blast = dir_a
		var swirl := a_blast.cross(Vector3.UP if absf(a_blast.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var a_dir := (a_blast + swirl.rotated(a_blast, randf() * TAU) * randf_range(0.1, 0.35)).normalized()

		# Smaller asteroids fly faster
		var a_speed := randf_range(eject_force * 0.7, eject_force * 1.9)
		var a_vel := a_dir * a_speed
		var a_spin := Vector3(randf_range(-3.5, 3.5), randf_range(-3.5, 3.5), randf_range(-3.5, 3.5))
		var a_mass := a_size * 25.0

		_register_physics(ast, a_vel, a_spin, a_mass, a_size * 0.5, phys_world, PhysBody.Layer.ROCK)
		_attach_cleanup_tween(ast, 120.0)
		results["asteroids"].append(ast)

	# 3. Molten Core Breakup (Core shatters into high-speed glowing core asteroids — NO static yellow ball left behind!)
	for k in molten_core_count:
		var core_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var core_size := randf_range(radius * 0.04, radius * 0.16) * geo_scale
		var core_spawn := p_pos + core_dir * randf_range(0.0, radius * 0.25)

		var core_ast := _build_asteroid_boulder(core_spawn, core_size, true)
		parent_node.add_child(core_ast)

		var c_blast := (core_spawn - epicentre).normalized()
		if c_blast.length_squared() < 0.01:
			c_blast = core_dir
		var c_speed := randf_range(eject_force * 1.3, eject_force * 2.6)
		var c_vel := c_blast * c_speed
		var c_spin := Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		var c_mass := core_size * 35.0

		_register_physics(core_ast, c_vel, c_spin, c_mass, core_size * 0.5, phys_world, PhysBody.Layer.ROCK)
		_attach_cleanup_tween(core_ast, 120.0)
		results["asteroids"].append(core_ast)

	# 4. Expanding temporary core energy flash (expands and fades out smoothly, leaving nothing static behind)
	var flash := MeshInstance3D.new()
	var flash_sphere := SphereMesh.new()
	flash_sphere.radius = radius * 0.25
	flash_sphere.height = radius * 0.5
	flash.mesh = flash_sphere

	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.65, 0.15, 0.95)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.material_override = flash_mat
	flash.top_level = true
	# In the tree before global_position is touched — see the same fix in
	# [method SystemsSim._spawn_planet_crater_blast].
	parent_node.add_child(flash)
	flash.global_position = p_pos

	var tw_flash := flash.create_tween()
	tw_flash.parallel().tween_property(flash, "scale", Vector3.ONE * 5.5, 2.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw_flash.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 2.2)
	tw_flash.tween_callback(flash.queue_free)
	results["core"] = null

	return results


## Builds a 3D pyramid / tapered wedge piece (crust polygon base tapering to a deep interior apex).
static func _build_pyramid_piece(
	planet: Planet,
	p_pos: Vector3,
	center_dir: Vector3,
	radius: float,
	angular_span: float,
	depth: float,
	surface_shader: Shader,
	mantle_mat: Material,
	is_quad: bool = false
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "PyramidDebris"
	rb.top_level = true
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4

	var n := center_dir.normalized()
	var up_guess := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t := n.cross(up_guess).normalized()
	var b := n.cross(t).normalized()

	var num_pts := 4 if is_quad else 3
	var world_base_pts: Array[Vector3] = []
	for k in num_pts:
		var base_angle := TAU * float(k) / float(num_pts) + (PI * 0.25 if is_quad else 0.0)
		var angle := base_angle + randf_range(-0.25, 0.25)
		var dist := angular_span * 0.5 * randf_range(0.75, 1.25)
		var u := cos(angle) * dist
		var v := sin(angle) * dist
		var pt_dir := (n + t * u + b * v).normalized()
		var r := radius * randf_range(0.995, 1.008)
		world_base_pts.append(p_pos + pt_dir * r)

	# Apex reaching deep into planetary interior
	var apex_dir := (n + t * randf_range(-0.15, 0.15) + b * randf_range(-0.15, 0.15)).normalized()
	var world_apex := p_pos + apex_dir * maxf(radius - depth, radius * 0.1)

	# Center of mass / position of the piece
	var p_sum := world_apex
	for pt in world_base_pts:
		p_sum += pt
	var piece_center_pos := p_sum / float(num_pts + 1)
	rb.position = piece_center_pos

	var local_base: Array[Vector3] = []
	var col_points := PackedVector3Array()
	for pt in world_base_pts:
		var loc := pt - piece_center_pos
		local_base.append(loc)
		col_points.append(loc)
	var local_apex := world_apex - piece_center_pos
	col_points.append(local_apex)

	# Surface 0: Outer crust (procedural planet surface shader)
	var st_crust := SurfaceTool.new()
	st_crust.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crust_col := Color(0.58, 0.0, 0.0)
	if not is_quad:
		_add_triangle(st_crust, local_base[0], local_base[1], local_base[2], crust_col, true, n)
	else:
		_add_triangle(st_crust, local_base[0], local_base[1], local_base[2], crust_col, true, n)
		_add_triangle(st_crust, local_base[0], local_base[2], local_base[3], crust_col, true, n)
	var mesh: ArrayMesh = st_crust.commit()

	# Surface 1: Fracture side walls (molten mantle rock)
	var st_mantle := SurfaceTool.new()
	st_mantle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mantle_col := Color(0.20, 0.0, 0.0)
	for k in num_pts:
		var next_k := (k + 1) % num_pts
		var mid_edge := (local_base[k] + local_base[next_k]) * 0.5
		var out_dir := (mid_edge - local_apex).normalized()
		_add_triangle(st_mantle, local_base[k], local_base[next_k], local_apex, mantle_col, true, out_dir)
	st_mantle.commit(mesh)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var crust_mat := _create_crust_material(planet, surface_shader, piece_center_pos - p_pos)
	mi.set_surface_override_material(0, crust_mat)
	mi.set_surface_override_material(1, mantle_mat)
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var poly := ConvexPolygonShape3D.new()
	poly.points = col_points
	cs.shape = poly
	rb.add_child(cs)
	rb.set_meta("col_points", col_points)

	return rb


## Builds an irregular 3D chunky polyhedron piece (faceted monolith / sheared prism).
static func _build_polyhedron_piece(
	planet: Planet,
	p_pos: Vector3,
	center_dir: Vector3,
	radius: float,
	angular_span: float,
	depth: float,
	surface_shader: Shader,
	mantle_mat: Material,
	num_pts: int = 4
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "PolyhedronDebris"
	rb.top_level = true
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4

	var n := center_dir.normalized()
	var up_guess := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t := n.cross(up_guess).normalized()
	var b := n.cross(t).normalized()

	var world_outer: Array[Vector3] = []
	var world_inner: Array[Vector3] = []
	for k in num_pts:
		var base_angle := TAU * float(k) / float(num_pts)
		var angle := base_angle + randf_range(-0.20, 0.20)
		var dist_out := angular_span * 0.5 * randf_range(0.8, 1.2)
		var u_out := cos(angle) * dist_out
		var v_out := sin(angle) * dist_out
		var dir_out := (n + t * u_out + b * v_out).normalized()
		world_outer.append(p_pos + dir_out * (radius * randf_range(0.995, 1.008)))

		var dist_in := dist_out * randf_range(0.55, 0.85)
		var u_in := cos(angle + randf_range(-0.15, 0.15)) * dist_in
		var v_in := sin(angle + randf_range(-0.15, 0.15)) * dist_in
		var dir_in := (n + t * u_in + b * v_in).normalized()
		world_inner.append(p_pos + dir_in * (radius - depth * randf_range(0.85, 1.15)))

	var p_sum := Vector3.ZERO
	for pt in world_outer: p_sum += pt
	for pt in world_inner: p_sum += pt
	var piece_center_pos := p_sum / float(num_pts * 2)
	rb.position = piece_center_pos

	var local_outer: Array[Vector3] = []
	var local_inner: Array[Vector3] = []
	var col_points := PackedVector3Array()
	for pt in world_outer:
		var loc := pt - piece_center_pos
		local_outer.append(loc)
		col_points.append(loc)
	for pt in world_inner:
		var loc := pt - piece_center_pos
		local_inner.append(loc)
		col_points.append(loc)

	# Surface 0: Outer crust
	var st_crust := SurfaceTool.new()
	st_crust.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crust_col := Color(0.58, 0.0, 0.0)
	for k in range(1, num_pts - 1):
		_add_triangle(st_crust, local_outer[0], local_outer[k], local_outer[k + 1], crust_col, true, n)
	var mesh: ArrayMesh = st_crust.commit()

	# Surface 1: Side fracture walls + bottom face
	var st_mantle := SurfaceTool.new()
	st_mantle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mantle_col := Color(0.20, 0.0, 0.0)
	# Side walls
	for k in num_pts:
		var next_k := (k + 1) % num_pts
		var o0 := local_outer[k]; var o1 := local_outer[next_k]
		var in0 := local_inner[k]; var in1 := local_inner[next_k]
		var mid := (o0 + o1 + in0 + in1) * 0.25
		_add_triangle(st_mantle, o0, o1, in0, mantle_col, true, mid)
		_add_triangle(st_mantle, o1, in1, in0, mantle_col, true, mid)
	# Bottom face
	for k in range(1, num_pts - 1):
		_add_triangle(st_mantle, local_inner[0], local_inner[k + 1], local_inner[k], mantle_col, true, -n)
	st_mantle.commit(mesh)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var crust_mat := _create_crust_material(planet, surface_shader, piece_center_pos - p_pos)
	mi.set_surface_override_material(0, crust_mat)
	mi.set_surface_override_material(1, mantle_mat)
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var poly := ConvexPolygonShape3D.new()
	poly.points = col_points
	cs.shape = poly
	rb.add_child(cs)
	rb.set_meta("col_points", col_points)

	return rb


## Builds a deep curved tectonic crust slab with substantial thickness and organic edges.
static func _build_deep_slab_piece(
	planet: Planet,
	p_pos: Vector3,
	center_dir: Vector3,
	radius: float,
	angular_span: float,
	thickness: float,
	surface_shader: Shader,
	mantle_mat: Material
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "TectonicSlabDebris"
	rb.top_level = true
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4

	var n := center_dir.normalized()
	var up_guess := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t := n.cross(up_guess).normalized()
	var b := n.cross(t).normalized()

	var steps := 3
	var outer_verts: Array[Vector3] = []
	var inner_verts: Array[Vector3] = []
	var col_points := PackedVector3Array()

	var plate_center_pos := p_pos + n * (radius - thickness * 0.5)
	rb.position = plate_center_pos

	for j in (steps + 1):
		var v_frac := (float(j) / float(steps)) - 0.5
		for i in (steps + 1):
			var u_frac := (float(i) / float(steps)) - 0.5
			var jitter_u := u_frac + (randf_range(-0.06, 0.06) if (i == 0 or i == steps) else 0.0)
			var jitter_v := v_frac + (randf_range(-0.06, 0.06) if (j == 0 or j == steps) else 0.0)

			var pt_dir := (n + t * (jitter_u * angular_span) + b * (jitter_v * angular_span)).normalized()
			var r_outer := radius * randf_range(0.995, 1.005)
			var r_inner := (radius - thickness) * randf_range(0.975, 1.025)

			var world_outer := p_pos + pt_dir * r_outer
			var world_inner := p_pos + pt_dir * r_inner

			var local_outer := world_outer - plate_center_pos
			var local_inner := world_inner - plate_center_pos
			outer_verts.append(local_outer)
			inner_verts.append(local_inner)
			col_points.append(local_outer)
			col_points.append(local_inner)

	# Surface 0: Outer curved crust
	var st_crust := SurfaceTool.new()
	st_crust.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crust_col := Color(0.58, 0.0, 0.0)
	for j in steps:
		for i in steps:
			var i0 := j * (steps + 1) + i
			var i1 := i0 + 1
			var i2 := (j + 1) * (steps + 1) + i
			var i3 := i2 + 1
			_add_triangle(st_crust, outer_verts[i0], outer_verts[i1], outer_verts[i2], crust_col, true, n)
			_add_triangle(st_crust, outer_verts[i1], outer_verts[i3], outer_verts[i2], crust_col, true, n)
	var mesh: ArrayMesh = st_crust.commit()

	# Surface 1: Fracture walls + inner mantle
	var st_mantle := SurfaceTool.new()
	st_mantle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mantle_col := Color(0.20, 0.0, 0.0)

	# Inner face
	for j in steps:
		for i in steps:
			var i0 := j * (steps + 1) + i
			var i1 := i0 + 1
			var i2 := (j + 1) * (steps + 1) + i
			var i3 := i2 + 1
			_add_triangle(st_mantle, inner_verts[i2], inner_verts[i1], inner_verts[i0], mantle_col, true, -n)
			_add_triangle(st_mantle, inner_verts[i2], inner_verts[i3], inner_verts[i1], mantle_col, true, -n)

	# Fracture boundary walls
	# Top edge (j = 0)
	for i in steps:
		_add_triangle(st_mantle, outer_verts[i], inner_verts[i], outer_verts[i + 1], mantle_col, true, -b)
		_add_triangle(st_mantle, outer_verts[i + 1], inner_verts[i], inner_verts[i + 1], mantle_col, true, -b)
	# Bottom edge (j = steps)
	var row_off := steps * (steps + 1)
	for i in steps:
		_add_triangle(st_mantle, outer_verts[row_off + i], outer_verts[row_off + i + 1], inner_verts[row_off + i], mantle_col, true, b)
		_add_triangle(st_mantle, outer_verts[row_off + i + 1], inner_verts[row_off + i + 1], inner_verts[row_off + i], mantle_col, true, b)
	# Left edge (i = 0)
	for j in steps:
		var o0 := j * (steps + 1); var o1 := (j + 1) * (steps + 1)
		var in0 := j * (steps + 1); var in1 := (j + 1) * (steps + 1)
		_add_triangle(st_mantle, outer_verts[o0], outer_verts[o1], inner_verts[in0], mantle_col, true, -t)
		_add_triangle(st_mantle, outer_verts[o1], inner_verts[in1], inner_verts[in0], mantle_col, true, -t)
	# Right edge (i = steps)
	for j in steps:
		var o0 := j * (steps + 1) + steps; var o1 := (j + 1) * (steps + 1) + steps
		var in0 := j * (steps + 1) + steps; var in1 := (j + 1) * (steps + 1) + steps
		_add_triangle(st_mantle, outer_verts[o0], inner_verts[in0], outer_verts[o1], mantle_col, true, t)
		_add_triangle(st_mantle, outer_verts[o1], inner_verts[in0], inner_verts[in1], mantle_col, true, t)
	st_mantle.commit(mesh)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var crust_mat := _create_crust_material(planet, surface_shader, plate_center_pos - p_pos)
	mi.set_surface_override_material(0, crust_mat)
	mi.set_surface_override_material(1, mantle_mat)
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var poly := ConvexPolygonShape3D.new()
	poly.points = col_points
	cs.shape = poly
	rb.add_child(cs)
	rb.set_meta("col_points", col_points)

	return rb


## Builds an irregular, faceted 3D asteroid boulder (rocky mantle asteroid or superheated molten core boulder).
static func _build_asteroid_boulder(
	pos: Vector3,
	size: float,
	is_molten: bool = false
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "MoltenCoreBoulder" if is_molten else "MantleAsteroid"
	rb.top_level = true
	rb.position = pos
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var S := 10 # radial slices
	var R := 7  # rings
	var c1 := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var c2 := -c1 + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)).normalized()
	var stretch := Vector3(randf_range(0.75, 1.25), randf_range(0.8, 1.2), randf_range(0.7, 1.3))

	var verts: Array[Array] = []
	for r in range(R + 1):
		var row: Array[Vector3] = []
		var lat := PI * (float(r) / float(R) - 0.5)
		for s in range(S):
			var lon := TAU * float(s) / float(S)
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			
			var j := sin(lat * 3.0 + lon * 2.0) * 0.14 + cos(lat * 5.0 - lon * 3.0) * 0.08 + randf_range(-0.06, 0.06)
			if d.dot(c1) > 0.60:
				j -= (d.dot(c1) - 0.60) * 0.35
			if d.dot(c2) > 0.65:
				j -= (d.dot(c2) - 0.65) * 0.30
			var rad := size * 0.5 * (1.0 + j)
			var v := (d * stretch).normalized() * rad
			row.append(v)
		verts.append(row)

	var ast_color := Color(0.9, 0.4, 0.1) if is_molten else Color(0.3, 0.25, 0.2)
	for r in range(R):
		for s in range(S):
			var next_s := (s + 1) % S
			var v00: Vector3 = verts[r][s]
			var v01: Vector3 = verts[r][next_s]
			var v10: Vector3 = verts[r + 1][s]
			var v11: Vector3 = verts[r + 1][next_s]

			if r > 0:
				_add_triangle(st, v00, v01, v10, ast_color, true, (v00 + v01 + v10) / 3.0)
			if r < R - 1:
				_add_triangle(st, v01, v11, v10, ast_color, true, (v01 + v11 + v10) / 3.0)

	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _make_molten_core_material() if is_molten else _make_asteroid_rock_material()
	mi.material_override = mat
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var ss := SphereShape3D.new()
	ss.radius = size * 0.48
	cs.shape = ss
	rb.add_child(cs)

	return rb


## Registers the body with both Godot physics and the custom PhysWorld (if present).
static func _register_physics(
	rb: RigidBody3D,
	velocity: Vector3,
	spin: Vector3,
	mass: float,
	bound_radius: float,
	phys_world: PhysWorld,
	layer: int = PhysBody.Layer.ROCK
) -> PhysBody:
	rb.mass = mass
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	rb.can_sleep = true
	rb.add_to_group("rigid_bodies")
	# A random fraction gets an early exit once off-screen for a while, rather
	# than every piece riding out its full cleanup tween below regardless of
	# whether anyone can see it — see [DebrisRegistry].
	DebrisRegistry.maybe_cull_when_unseen(rb)
	rb.body_entered.connect(func(_other: Node) -> void:
		if is_instance_valid(rb) and rb.is_inside_tree():
			Juice.burst(BurstPresets.Preset.SPARKS, rb.global_transform, 1.4, Color(1.0, 0.75, 0.3))
			Juice.burst(BurstPresets.Preset.DEBRIS, rb.global_transform, 1.0)
	)

	if phys_world != null:
		var pb := PhysBody.new(mass, bound_radius)
		pb.node = rb
		pb.velocity = velocity
		pb.angular = spin
		pb.layer = layer
		pb.kinematic = false
		pb.restitution = 0.5

		# Compound collision hull covering 3D geometry
		if rb.has_meta("col_points"):
			var pts: PackedVector3Array = rb.get_meta("col_points")
			if pts.size() > 0:
				var aabb := AABB(pts[0], Vector3.ZERO)
				for p in pts:
					aabb = aabb.expand(p)
				var spheres := HullFit.spheres_for_box(aabb)
				if not spheres.is_empty():
					pb.set_hull(spheres)

		# Rich impact feedback when colliding with ships, AI, or other debris in PhysWorld
		pb.impacted.connect(func(_other: PhysBody, _impulse: float, point: Vector3, _normal: Vector3, closing: float) -> void:
			if is_instance_valid(rb) and rb.is_inside_tree() and closing > 4.0:
				Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), point), 1.6, Color(1.0, 0.8, 0.4))
				Juice.burst(BurstPresets.Preset.DEBRIS, Transform3D(Basis(), point), 1.3)
				Juice.light_pop(point, Color(1.0, 0.6, 0.2), 30.0, 0.2)
				if closing > 12.0:
					Juice.shake(clampf(closing * 0.015, 0.1, 0.5))
		)

		phys_world.add(pb)

		# Cleanly unregister when freed
		rb.tree_exiting.connect(func() -> void:
			if is_instance_valid(phys_world):
				phys_world.remove(pb)
		)

		# Freeze Godot RigidBody so PhysWorld manages integration smoothly
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		return pb
	else:
		# Fallback to Godot's built-in rigid body dynamics
		rb.freeze = false
		rb.linear_velocity = velocity
		rb.angular_velocity = spin
		return null


## Creates the procedural crust ShaderMaterial with planet parameters and spatial offset.
static func _create_crust_material(planet: Planet, surface_shader: Shader, center_offset: Vector3) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = surface_shader
	if planet != null and planet.data != null:
		mat.set_shader_parameter("primary_color", planet.data.primary_color)
		mat.set_shader_parameter("secondary_color", planet.data.secondary_color)
		mat.set_shader_parameter("water_color", planet.data.water_color)
		mat.set_shader_parameter("ice_amount", planet.data.ice_amount)
		mat.set_shader_parameter("planet_type", 0.0 if planet.data.is_gas_giant() else 1.0)
		mat.set_shader_parameter("swirl_speed", planet.data.swirl_speed)
		mat.set_shader_parameter("swirl_scale", planet.data.swirl_scale)
		mat.set_shader_parameter("band_count", planet.data.band_count)
		mat.set_shader_parameter("detail_strength", planet.data.detail_strength)
		mat.set_shader_parameter("sea_level", planet.data.sea_level)
		mat.set_shader_parameter("relief", 1.0)
		mat.set_shader_parameter("sun_direction", planet.sun_direction.normalized())
	mat.set_shader_parameter("sphere_center_offset", center_offset)
	return mat


## Fracture walls material: dark basalt with glowing magma fissures.
static func _make_mantle_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.15, 0.13)
	m.roughness = 0.88
	m.emission_enabled = Session.planet_debris_glow
	m.emission = Color(1.0, 0.40, 0.08)
	m.emission_energy_multiplier = randf_range(1.6, 2.8) if Session.planet_debris_glow else 0.0
	return m


## Molten core boulder material: intense blazing core magma.
static func _make_molten_core_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.15, 0.08)
	m.roughness = 0.82
	m.emission_enabled = Session.planet_debris_glow
	m.emission = Color(1.0, 0.45, 0.05)
	m.emission_energy_multiplier = randf_range(3.5, 6.0) if Session.planet_debris_glow else 0.0
	return m


## Rocky mantle asteroid material: cold silicate/basalt stone with procedural Voronoi craters and ridges.
static func _make_asteroid_rock_material() -> Material:
	var rock_t := randf()
	var base_col := Color(
		lerpf(0.18, 0.32, rock_t),
		lerpf(0.15, 0.26, rock_t * 0.85),
		lerpf(0.12, 0.20, rock_t * 0.7)
	)
	var shader := load("res://modules/common/planets/shaders/asteroid_detail.gdshader") as Shader
	if shader != null:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("rock_color", base_col)
		sm.set_shader_parameter("crater_color", base_col * 0.45)
		sm.set_shader_parameter("roughness", randf_range(0.82, 0.95))
		sm.set_shader_parameter("micro_scale", randf_range(0.35, 0.65))
		sm.set_shader_parameter("crater_scale", randf_range(0.06, 0.12))
		sm.set_shader_parameter("normal_strength", 0.8)
		var has_glow: bool = (randf() < 0.45 and Session.planet_debris_glow)
		sm.set_shader_parameter("emission_enabled", has_glow)
		sm.set_shader_parameter("emission_color", Color(1.0, 0.30, 0.05))
		sm.set_shader_parameter("emission_energy", randf_range(1.2, 2.5) if has_glow else 0.0)
		return sm

	var m := StandardMaterial3D.new()
	m.albedo_color = base_col
	m.roughness = randf_range(0.82, 0.95)
	if randf() < 0.45 and Session.planet_debris_glow:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.30, 0.05)
		m.emission_energy_multiplier = randf_range(0.8, 1.8)
	else:
		m.emission_enabled = false
		m.emission_energy_multiplier = 0.0
	return m


## Dynamically toggles radiant emission on all living planet debris in the scene.
static func set_debris_glow_enabled(enabled: bool, root_node: Node = null) -> void:
	Session.planet_debris_glow = enabled
	if root_node == null or not is_instance_valid(root_node):
		return
	_update_glow_recursive(root_node, enabled)


static func _update_glow_recursive(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			var shm := mi.material_override as ShaderMaterial
			shm.set_shader_parameter("emission_enabled", enabled)
			shm.set_shader_parameter("emission_energy", (3.0 if enabled else 0.0))
		elif mi.material_override is StandardMaterial3D:
			var sm := mi.material_override as StandardMaterial3D
			sm.emission_enabled = enabled
			sm.emission_energy_multiplier = (3.5 if enabled else 0.0)
		for s in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(s)
			if mat is ShaderMaterial:
				var shm := mat as ShaderMaterial
				shm.set_shader_parameter("emission_enabled", enabled)
				shm.set_shader_parameter("emission_energy", (3.0 if enabled else 0.0))
			elif mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				sm.emission_enabled = enabled
				sm.emission_energy_multiplier = (3.5 if enabled else 0.0)
	for child in node.get_children():
		_update_glow_recursive(child, enabled)


## Emits a single triangle to a SurfaceTool with optional outward winding check.
static func _add_triangle(
	st: SurfaceTool,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	color: Color = Color.WHITE,
	flip_if_needed: bool = false,
	outward_ref: Vector3 = Vector3.ZERO
) -> void:
	var norm := (v1 - v0).cross(v2 - v0).normalized()
	if flip_if_needed and outward_ref.length_squared() > 1e-6:
		if norm.dot(outward_ref) < 0.0:
			var tmp := v1
			v1 = v2
			v2 = tmp
			norm = -norm

	st.set_normal(norm)
	st.set_color(color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(v0)

	st.set_normal(norm)
	st.set_color(color)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(v1)

	st.set_normal(norm)
	st.set_color(color)
	st.set_uv(Vector2(0.5, 1))
	st.add_vertex(v2)


## Self-cleanup with smooth fadeout before queue_free.
static func _attach_cleanup_tween(rb: RigidBody3D, lifespan: float = 120.0) -> void:
	var tw := rb.create_tween()
	tw.tween_interval(maxf(lifespan - 6.0, 1.0))
	# Smooth fade out over last 6 seconds
	tw.tween_property(rb, "scale", Vector3.ZERO, 6.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(rb.queue_free)
