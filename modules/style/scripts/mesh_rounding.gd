## MeshRounding: applies roundness, chunkiness, and rock_potato to meshes.
##
## This module modifies LowPoly output to implement the geometry dials
## from StyleProfile. Since these dials affect the actual mesh topology,
## they require a mesh cache rebuild and scene reload (see
## TECHNICAL_PLAN.md §3.3).
##
## Called by PartMeshFactory during mesh generation, and directly by
## space_scene.gd for asteroid rocks (is_asteroid = true).
##
## Input:  base_mesh (ArrayMesh from LowPoly.commit())
## Output: a new ArrayMesh with adjusted vertex positions and normals
##
## LowPoly gives every triangle its own unshared vertices with a true face
## normal (see lowpoly.gd's class doc) -- there is no shared-vertex topology to
## bevel or subdivide here. Each dial below is a deliberately honest
## simplification that reads right on this topology without becoming a real
## mesh-processing pipeline:
##
## - roundness: NOT a bevel. Vertices at (near enough) the same position are
##   grouped and their face normals averaged, then blended toward that average
##   by `roundness`. Shading softens across hard edges exactly like a bevel
##   would read from a normal distance, with zero new geometry.
## - chunkiness: non-uniform scale that shrinks the model's longest axis and
##   grows the other two in compensation, so a slender hull reads visibly
##   fatter/stubbier while keeping roughly the same volume.
## - rock_potato: hash-noise displacement of each vertex along its *smoothed*
##   normal (no subdivision -- there is nothing to subdivide into). Only ever
##   applied when [member is_asteroid] is set, since a lumpy hull is not the
##   ask.
@tool
class_name MeshRounding extends RefCounted

var roundness := 0.0
var chunkiness := 0.0
var rock_potato := 0.0
var is_asteroid := false  # Set true when processing asteroid meshes


func apply(base_mesh: Mesh) -> Mesh:
	var wants_potato := rock_potato > 0.0 and is_asteroid
	if roundness <= 0.0 and chunkiness <= 0.0 and not wants_potato:
		return base_mesh
	if not (base_mesh is ArrayMesh) or base_mesh.get_surface_count() == 0:
		return base_mesh

	var arrays: Array = base_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty():
		return base_mesh

	var smooth := normals
	if roundness > 0.0 or wants_potato:
		smooth = _smoothed_normals(verts, normals)

	if chunkiness > 0.0:
		verts = _apply_chunkiness(verts)

	if roundness > 0.0:
		var blended := PackedVector3Array()
		blended.resize(normals.size())
		for i in normals.size():
			blended[i] = normals[i].lerp(smooth[i], roundness * 0.85).normalized()
		normals = blended

	if wants_potato:
		verts = _apply_potato(verts, smooth)
		# Displacement moves the surface out from under the old face normals, so
		# they are recomputed from the new (still per-triangle, unshared) verts.
		normals = _face_normals(verts)

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.resource_name = base_mesh.resource_name
	return out


## Average the normal across every vertex that lands on (near enough) the same
## position, weighted equally per triangle-corner. A rounded-position hash
## stands in for a real weld: the meshes here run a few hundred verts, not
## thousands, so an O(n) bucket pass is plenty.
func _smoothed_normals(verts: PackedVector3Array, normals: PackedVector3Array) -> PackedVector3Array:
	var buckets := {}
	for i in verts.size():
		var key := _pos_key(verts[i])
		buckets[key] = buckets.get(key, Vector3.ZERO) + normals[i]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var sum: Vector3 = buckets[_pos_key(verts[i])]
		out[i] = sum.normalized() if sum.length_squared() > 0.0 else normals[i]
	return out


func _pos_key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 256.0), roundi(v.y * 256.0), roundi(v.z * 256.0))


## Non-uniform scale toward a cube: squashes the longest axis and grows the
## other two in proportion to how much they already span, so a slender hull
## reads visibly fatter/stubbier without flattening into a different shape.
func _apply_chunkiness(verts: PackedVector3Array) -> PackedVector3Array:
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	var center := box.position + box.size * 0.5
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return verts
	var shrink := chunkiness * 0.30
	var scale := Vector3(
		1.0 - shrink * (size.x / longest),
		1.0 - shrink * (size.y / longest),
		1.0 - shrink * (size.z / longest)
	)
	# Compensate by the cube root of the volume factor, not by 1/scale.x -- that
	# would exactly cancel the longest axis's own shrink (they share the same
	# factor) and leave it unchanged while only the other two grew.
	var vol_factor := scale.x * scale.y * scale.z
	if vol_factor > 0.0001:
		scale /= pow(vol_factor, 1.0 / 3.0)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var v := verts[i] - center
		out[i] = center + Vector3(v.x * scale.x, v.y * scale.y, v.z * scale.z)
	return out


## Bump-noise displacement along the welded normal. No subdivision -- at
## asteroid triangle counts, pushing existing verts along their smoothed
## normal already breaks the silhouette into lumps, which is what "potato"
## actually asks for; adding geometry would be a much bigger change for a look
## this dial already achieves.
func _apply_potato(verts: PackedVector3Array, smooth_normals: PackedVector3Array) -> PackedVector3Array:
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	var radius := box.size.length() * 0.5
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var n := _hash_noise(verts[i]) - 0.5
		out[i] = verts[i] + smooth_normals[i] * n * rock_potato * radius * 0.35
	return out


func _hash_noise(p: Vector3) -> float:
	var s := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
	return s - floor(s)


func _face_normals(verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	var i := 0
	while i + 2 < verts.size():
		var n := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
		n = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
		out[i] = n
		out[i + 1] = n
		out[i + 2] = n
		i += 3
	return out
