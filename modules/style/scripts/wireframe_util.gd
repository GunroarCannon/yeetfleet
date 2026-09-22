## wireframe_util.gd — Generates authentic vector arcade wireframe meshes and materials
## matching retro vector monitors (Asteroids, Tempest, Geometry Wars).
class_name WireframeUtil
extends RefCounted

static var _mat_cache: Dictionary = {}

## Returns an unshaded, additive-blended material that produces glowing neon vector lines
static func create_vector_material(color: Color, glow: float = 1.5) -> StandardMaterial3D:
	var key := "%s_%.2f" % [color.to_html(), glow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color * glow
	mat.no_depth_test = false
	_mat_cache[key] = mat
	return mat


## Converts any triangle mesh to a PRIMITIVE_LINES ArrayMesh with deduplicated edges
static func to_wireframe_mesh(source: Mesh, deduplicate: bool = true) -> ArrayMesh:
	if source == null:
		return null
	var wire_mesh := ArrayMesh.new()
	for s in source.get_surface_count():
		var arr := source.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var old_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var raw_indices: Variant = arr[Mesh.ARRAY_INDEX]
		var old_indices: PackedInt32Array = raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
		if old_verts.is_empty():
			continue

		var line_indices := PackedInt32Array()
		if not deduplicate or old_indices.is_empty():
			if not old_indices.is_empty():
				for t in range(0, old_indices.size(), 3):
					var i0 := old_indices[t]
					var i1 := old_indices[t + 1]
					var i2 := old_indices[t + 2]
					line_indices.append_array([i0, i1, i1, i2, i2, i0])
			else:
				for t in range(0, old_verts.size(), 3):
					line_indices.append_array([t, t + 1, t + 1, t + 2, t + 2, t])
		else:
			var edge_set := {}
			for t in range(0, old_indices.size(), 3):
				var idxs := [old_indices[t], old_indices[t + 1], old_indices[t + 2]]
				for e in 3:
					var a: int = idxs[e]
					var b: int = idxs[(e + 1) % 3]
					var min_i: int = mini(a, b)
					var max_i: int = maxi(a, b)
					var edge_key := (int(min_i) << 32) | int(max_i)
					if not edge_set.has(edge_key):
						edge_set[edge_key] = true
						line_indices.append(min_i)
						line_indices.append(max_i)

		var new_arr := []
		new_arr.resize(Mesh.ARRAY_MAX)
		new_arr[Mesh.ARRAY_VERTEX] = old_verts
		new_arr[Mesh.ARRAY_INDEX] = line_indices
		wire_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, new_arr)
	return wire_mesh


## Generates a mathematical icosahedron vector mesh (Geometry Wars green/orange diamonds)
static func create_icosahedron(radius: float = 1.0) -> ArrayMesh:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var raw_verts := [
		Vector3(-1.0,  phi, 0.0), Vector3( 1.0,  phi, 0.0),
		Vector3(-1.0, -phi, 0.0), Vector3( 1.0, -phi, 0.0),
		Vector3(0.0, -1.0,  phi), Vector3(0.0,  1.0,  phi),
		Vector3(0.0, -1.0, -phi), Vector3(0.0,  1.0, -phi),
		Vector3( phi, 0.0, -1.0), Vector3( phi, 0.0,  1.0),
		Vector3(-phi, 0.0, -1.0), Vector3(-phi, 0.0,  1.0)
	]
	var verts := PackedVector3Array()
	for v in raw_verts:
		verts.append((v as Vector3).normalized() * radius)

	var edges: Array[Vector2i] = [
		Vector2i(0, 11), Vector2i(0, 5), Vector2i(0, 1), Vector2i(0, 7), Vector2i(0, 10),
		Vector2i(1, 5), Vector2i(5, 11), Vector2i(11, 10), Vector2i(10, 7), Vector2i(7, 1),
		Vector2i(3, 9), Vector2i(3, 4), Vector2i(3, 2), Vector2i(3, 6), Vector2i(3, 8),
		Vector2i(4, 9), Vector2i(2, 4), Vector2i(6, 2), Vector2i(8, 6), Vector2i(9, 8),
		Vector2i(4, 5), Vector2i(5, 9), Vector2i(9, 1), Vector2i(1, 8), Vector2i(8, 7),
		Vector2i(7, 6), Vector2i(6, 10), Vector2i(10, 2), Vector2i(2, 11), Vector2i(11, 4)
	]

	var line_indices := PackedInt32Array()
	for e in edges:
		line_indices.append(e.x)
		line_indices.append(e.y)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = line_indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a mathematical dodecahedron vector mesh (Geometry Wars cyan polyhedra)
static func create_dodecahedron(radius: float = 1.0) -> ArrayMesh:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var inv_phi := 1.0 / phi
	var raw_verts := [
		Vector3( 1,  1,  1), Vector3( 1,  1, -1), Vector3( 1, -1,  1), Vector3( 1, -1, -1),
		Vector3(-1,  1,  1), Vector3(-1,  1, -1), Vector3(-1, -1,  1), Vector3(-1, -1, -1),
		Vector3(0,  inv_phi,  phi), Vector3(0,  inv_phi, -phi),
		Vector3(0, -inv_phi,  phi), Vector3(0, -inv_phi, -phi),
		Vector3( inv_phi,  phi, 0), Vector3( inv_phi, -phi, 0),
		Vector3(-inv_phi,  phi, 0), Vector3(-inv_phi, -phi, 0),
		Vector3( phi, 0,  inv_phi), Vector3( phi, 0, -inv_phi),
		Vector3(-phi, 0,  inv_phi), Vector3(-phi, 0, -inv_phi)
	]
	var verts := PackedVector3Array()
	for v in raw_verts:
		verts.append((v as Vector3).normalized() * radius)

	# Find edges by distance: in a regular dodecahedron, neighbors have equal shortest distance
	var target_dist_sq := 4.0 / (3.0 * phi * phi)
	var line_indices := PackedInt32Array()
	for i in range(verts.size()):
		for j in range(i + 1, verts.size()):
			var d_sq := (verts[i] / radius).distance_squared_to(verts[j] / radius)
			if absf(d_sq - target_dist_sq) < 0.12:
				line_indices.append(i)
				line_indices.append(j)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = line_indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a glowing concentric wireframe planet (latitude rings & longitude great circles)
static func create_wireframe_planet(radius: float = 8.0, lat_rings: int = 12, lon_circles: int = 16) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var segs := 48

	# Latitude rings
	for r in range(1, lat_rings):
		var theta := PI * float(r) / float(lat_rings)
		var y := cos(theta) * radius
		var r_lat := sin(theta) * radius
		var start_idx := verts.size()
		for s in segs:
			var phi := TAU * float(s) / float(segs)
			verts.append(Vector3(cos(phi) * r_lat, y, sin(phi) * r_lat))
			var next_s := (s + 1) % segs
			indices.append(start_idx + s)
			indices.append(start_idx + next_s)

	# Longitude great circles
	for l in lon_circles:
		var phi := PI * float(l) / float(lon_circles)
		var cos_p := cos(phi)
		var sin_p := sin(phi)
		var start_idx := verts.size()
		for s in segs:
			var theta := TAU * float(s) / float(segs)
			var yr := sin(theta) * radius
			var xr := cos(theta) * radius
			verts.append(Vector3(xr * cos_p, yr, xr * sin_p))
			var next_s := (s + 1) % segs
			indices.append(start_idx + s)
			indices.append(start_idx + next_s)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a Geometry Wars spinning gear / rosette enemy
static func create_vector_gear(outer_r: float = 1.0, inner_r: float = 0.55, teeth: int = 12) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var total_pts := teeth * 4

	for i in total_pts:
		var angle := TAU * float(i) / float(total_pts)
		var is_tooth := (i % 4 == 1 or i % 4 == 2)
		var r := outer_r if is_tooth else inner_r
		verts.append(Vector3(cos(angle) * r, sin(angle) * r, 0.0))
		indices.append(i)
		indices.append((i + 1) % total_pts)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a multifaceted nested polyhedron gem (like the green & cyan gems in Geometry Wars)
static func create_nested_polyhedron(outer_r: float = 1.6, inner_r: float = 0.85) -> ArrayMesh:
	var outer_m := create_icosahedron(outer_r)
	var inner_m := create_dodecahedron(inner_r)
	var o_arr := outer_m.surface_get_arrays(0)
	var i_arr := inner_m.surface_get_arrays(0)

	var verts: PackedVector3Array = o_arr[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = o_arr[Mesh.ARRAY_INDEX]

	var i_verts: PackedVector3Array = i_arr[Mesh.ARRAY_VERTEX]
	var i_indices: PackedInt32Array = i_arr[Mesh.ARRAY_INDEX]
	var offset: int = verts.size()

	# Rotate inner mesh slightly for geometric dynamism
	var rot := Basis(Vector3(0.577, 0.577, 0.577).normalized(), 0.65)
	for iv in i_verts:
		verts.append(rot * iv)
	for idx in i_indices:
		indices.append(idx + offset)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates an icosahedron with an inner concentric star-core (like the orange gem)
static func create_nested_star_gem(radius: float = 1.5, core_r: float = 0.75) -> ArrayMesh:
	var outer_m := create_icosahedron(radius)
	var o_arr := outer_m.surface_get_arrays(0)
	var verts: PackedVector3Array = o_arr[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = o_arr[Mesh.ARRAY_INDEX]

	var phi := (1.0 + sqrt(5.0)) * 0.5
	var star_points := [
		Vector3(0, 1, 0) * core_r, Vector3(0, -1, 0) * core_r,
		Vector3(1, 0, 0) * core_r, Vector3(-1, 0, 0) * core_r,
		Vector3(0, 0, 1) * core_r, Vector3(0, 0, -1) * core_r,
	]
	var offset: int = verts.size()
	for p in star_points:
		verts.append(p)
	# Connect octahedral star points
	var star_edges := [
		Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5),
		Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5),
		Vector2i(2, 4), Vector2i(4, 3), Vector2i(3, 5), Vector2i(5, 2)
	]
	for e in star_edges:
		indices.append(e.x + offset)
		indices.append(e.y + offset)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a classic Geometry Wars vector arrowhead dart enemy/fighter
static func create_vector_dart(size: float = 1.0) -> ArrayMesh:
	var s := size
	var raw_verts := [
		Vector3(0.0, 0.0, -s * 1.2),        # 0: nose tip
		Vector3(-s * 0.75, 0.0, s * 0.8),   # 1: left wingtip
		Vector3( s * 0.75, 0.0, s * 0.8),   # 2: right wingtip
		Vector3(0.0, 0.0, s * 0.35),        # 3: inner rear notch
		Vector3(0.0, s * 0.45, s * 0.1),    # 4: cockpit dorsal fin
		Vector3(-s * 0.35, 0.0, s * 0.1),   # 5: left inner rib
		Vector3( s * 0.35, 0.0, s * 0.1),   # 6: right inner rib
	]
	var verts := PackedVector3Array()
	for v in raw_verts:
		verts.append(v)
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 3), Vector2i(3, 2), Vector2i(2, 0), # outer hull
		Vector2i(0, 4), Vector2i(4, 3),                                 # spine/cockpit
		Vector2i(4, 1), Vector2i(4, 2),                                 # dorsal ribs
		Vector2i(5, 6), Vector2i(0, 3)                                  # inner chevron
	]
	var indices := PackedInt32Array()
	for e in edges:
		indices.append(e.x)
		indices.append(e.y)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a 3D vector asterisk / cross marker
static func create_vector_cross(size: float = 0.45) -> ArrayMesh:
	var s := size
	var verts := PackedVector3Array([
		Vector3(-s, 0, 0), Vector3(s, 0, 0),
		Vector3(0, -s, 0), Vector3(0, s, 0),
		Vector3(-s * 0.7, -s * 0.7, 0), Vector3(s * 0.7, s * 0.7, 0),
		Vector3(-s * 0.7,  s * 0.7, 0), Vector3(s * 0.7, -s * 0.7, 0),
	])
	var indices := PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Generates a hollow vector diamond
static func create_vector_diamond(size: float = 0.5) -> ArrayMesh:
	var s := size
	var verts := PackedVector3Array([
		Vector3(0, s, 0), Vector3(s * 0.7, 0, 0),
		Vector3(0, -s, 0), Vector3(-s * 0.7, 0, 0),
		Vector3(0, 0, s * 0.3), Vector3(0, 0, -s * 0.3)
	])
	var indices := PackedInt32Array([
		0, 1, 1, 2, 2, 3, 3, 0,
		0, 4, 1, 4, 2, 4, 3, 4,
		0, 5, 1, 5, 2, 5, 3, 5
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m
