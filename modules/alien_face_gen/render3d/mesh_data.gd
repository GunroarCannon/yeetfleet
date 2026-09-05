class_name MeshData extends RefCounted

var verts: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var uvs: PackedVector2Array = PackedVector2Array()
var colors: PackedColorArray = PackedColorArray()
var indices: PackedInt32Array = PackedInt32Array()
var surfaces: Array = []  # [{name:StringName, start:int, count:int, material_hint:StringName}]


func tri_count() -> int:
	return indices.size() / 3


func validate() -> String:
	if indices.size() % 3 != 0:
		return "indices.size()=%d not divisible by 3" % indices.size()
	if verts.size() == 0:
		return "no vertices"
	if normals.size() != verts.size():
		return "normals.size()=%d != verts.size()=%d" % [normals.size(), verts.size()]
	if uvs.size() != verts.size():
		return "uvs.size()=%d != verts.size()=%d" % [uvs.size(), verts.size()]
	if colors.size() != verts.size():
		return "colors.size()=%d != verts.size()=%d" % [colors.size(), verts.size()]
	for i in range(indices.size()):
		if indices[i] < 0 or indices[i] >= verts.size():
			return "index %d out of range (verts.size()=%d)" % [indices[i], verts.size()]
	for i in range(verts.size()):
		if is_nan(verts[i].x) or is_nan(verts[i].y) or is_nan(verts[i].z):
			return "NaN in verts[%d]" % i
		if is_inf(verts[i].x) or is_inf(verts[i].y) or is_inf(verts[i].z):
			return "INF in verts[%d]" % i
	return ""


func merge(other: MeshData) -> void:
	var offset := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	uvs.append_array(other.uvs)
	colors.append_array(other.colors)
	for idx in other.indices:
		indices.append(idx + offset)
	for s in other.surfaces:
		surfaces.append({
			"name": s["name"],
			"start": s["start"] + offset,
			"count": s["count"],
			"material_hint": s["material_hint"]
		})
