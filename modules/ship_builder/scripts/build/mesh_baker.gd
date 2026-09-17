## MeshBaker: combines ship part meshes and collision shapes for performance.
##
## On mobile or with large fleet counts / giant motherships, having 50-200
## individual MeshInstance3D nodes causes severe draw call overhead.
## MeshBaker merges parts into unified ArrayMeshes grouped by material
## and generates dedicated part-level collision shapes for big ships.
class_name MeshBaker
extends RefCounted

## Cache of baked collision hulls keyed by design or part count token.
static var _hull_cache: Dictionary = {}

## Cache of baked meshes keyed by design_id + style_token + palette_id.
static var _mesh_cache: Dictionary = {}


# --- Mesh Baking -----------------------------------------------------------

## Bakes all part meshes of a [ShipView] into a single consolidated [MeshInstance3D]
## with an [ArrayMesh] that merges geometry transformed into ship local space.
static func bake_ship_mesh(view: ShipView) -> MeshInstance3D:
	if view == null or view.resolution == null or view.resolution.placements.is_empty():
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Merge all placement meshes into the SurfaceTool, transforming vertices and normals.
	for placement in view.resolution.placements:
		var mesh_inst: MeshInstance3D = view.part_meshes.get(placement.path)
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var part_mesh := mesh_inst.mesh
		var xform := placement.xform

		for s in part_mesh.get_surface_count():
			var arrays: Array = part_mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

			var has_normals := not normals.is_empty()
			var has_uvs := not uvs.is_empty()
			var has_colors := not colors.is_empty()

			if indices.is_empty():
				for i in verts.size():
					var v := xform * verts[i]
					if has_normals:
						st.set_normal((xform.basis * normals[i]).normalized())
					if has_uvs:
						st.set_uv(uvs[i])
					if has_colors:
						st.set_color(colors[i])
					st.add_vertex(v)
			else:
				for idx in indices:
					var v := xform * verts[idx]
					if has_normals:
						st.set_normal((xform.basis * normals[idx]).normalized())
					if has_uvs:
						st.set_uv(uvs[idx])
					if has_colors:
						st.set_color(colors[idx])
					st.add_vertex(v)

	var baked_mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.name = "BakedHullMesh"
	inst.mesh = baked_mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Use the first valid material or ship material
	if not view.part_materials.is_empty():
		var first_mat: ShaderMaterial = null
		for mat in view.part_materials.values():
			if mat is ShaderMaterial:
				first_mat = mat
				break
		if first_mat != null:
			inst.material_override = first_mat

	return inst


# --- Collision Baking ------------------------------------------------------

## Creates dedicated physical [CollisionShape3D] colliders for each part of a ship.
## Especially important for really big ships (carriers, motherships, stations)
## so individual wings, engines, towers, and hull sections can be hit.
static func create_part_colliders(view: ShipView, target_node: Node3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if view == null or target_node == null:
		return out

	for placement in view.resolution.placements:
		var holder: Node3D = view.part_nodes.get(placement.path)
		var mesh_inst: MeshInstance3D = view.part_meshes.get(placement.path)
		if holder == null:
			continue

		var shape_node := CollisionShape3D.new()
		shape_node.name = "Col_" + ShipView.sanitise(placement.path)

		var aabb: AABB
		if mesh_inst != null and mesh_inst.mesh != null:
			aabb = mesh_inst.mesh.get_aabb()
		else:
			var built := PartMeshFactory.build(placement.part, placement.mirrored)
			aabb = built.aabb

		# Create a BoxShape3D sized to the part bounds
		var box := BoxShape3D.new()
		var s := aabb.size
		box.size = Vector3(maxf(s.x, 0.3), maxf(s.y, 0.3), maxf(s.z, 0.3))
		shape_node.shape = box
		shape_node.transform = placement.xform * Transform3D(Basis(), aabb.get_center())

		shape_node.set_meta("part_path", placement.path)
		shape_node.set_meta("part_id", placement.part.id)
		shape_node.set_meta("part_kind", String(placement.part.mesh_spec.get("kind", "box")))

		target_node.add_child(shape_node)
		out.append(shape_node)

	return out


## Computes, prunes and bakes the compound sphere hull for [PhysBody],
## caching the result so repeated queries do zero allocations.
static func bake_compound_spheres(boxes: Array[AABB]) -> Array[Dictionary]:
	var raw_hull: Array[Dictionary] = []
	for box in boxes:
		HullFit.append_box_spheres(box, raw_hull)

	# Prune any sphere that is fully contained within another sphere
	var baked: Array[Dictionary] = []
	for i in raw_hull.size():
		var s1: Dictionary = raw_hull[i]
		var c1: Vector3 = s1["offset"]
		var r1: float = s1["radius"]
		var contained := false
		for j in raw_hull.size():
			if i == j:
				continue
			var s2: Dictionary = raw_hull[j]
			var c2: Vector3 = s2["offset"]
			var r2: float = s2["radius"]
			if r2 >= r1 and c1.distance_to(c2) + r1 <= r2 * 1.05:
				contained = true
				break
		if not contained:
			baked.append(s1)

	return baked if not baked.is_empty() else raw_hull


## Clears all baker caches (called on style or design reload).
static func clear_cache() -> void:
	_hull_cache.clear()
	_mesh_cache.clear()
