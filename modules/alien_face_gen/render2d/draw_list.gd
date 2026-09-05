class_name DrawList extends RefCounted

# Each cmd: {type:StringName, points:PackedVector2Array, color:Color, width:float, z:int, slot:StringName}
var cmds: Array[Dictionary] = []


func poly(points: PackedVector2Array, color: Color, z: int, slot: StringName) -> void:
	cmds.append({"type": &"poly", "points": points, "color": color, "width": 0.0, "z": z, "slot": slot})


func line(points: PackedVector2Array, color: Color, width: float, z: int, slot: StringName) -> void:
	cmds.append({"type": &"line", "points": points, "color": color, "width": width, "z": z, "slot": slot})


func circle(center: Vector2, r: float, color: Color, z: int, slot: StringName) -> void:
	var samples := Lod.curve_samples(0)
	var pts := PackedVector2Array()
	for i in range(samples):
		var angle := TAU * i / samples
		pts.append(Vector2(center.x + cos(angle) * r, center.y + sin(angle) * r))
	cmds.append({"type": &"poly", "points": pts, "color": color, "width": 0.0, "z": z, "slot": slot})


func ellipse(center: Vector2, rx: float, ry: float, rot: float, color: Color, z: int, slot: StringName) -> void:
	var samples := Lod.curve_samples(0)
	var pts := PackedVector2Array()
	for i in range(samples):
		var angle := TAU * i / samples
		var px := cos(angle) * rx
		var py := sin(angle) * ry
		# Apply rotation
		var rx2 := px * cos(rot) - py * sin(rot)
		var ry2 := px * sin(rot) + py * cos(rot)
		pts.append(Vector2(center.x + rx2, center.y + ry2))
	cmds.append({"type": &"poly", "points": pts, "color": color, "width": 0.0, "z": z, "slot": slot})


func sort_z() -> void:
	# Stable sort by z
	var indexed: Array = []
	for i in range(cmds.size()):
		indexed.append({"idx": i, "z": cmds[i]["z"]})
	indexed.sort_custom(func(a, b): return a["z"] < b["z"])
	var sorted_cmds: Array[Dictionary] = []
	for entry in indexed:
		sorted_cmds.append(cmds[entry["idx"]])
	cmds = sorted_cmds


func color_set() -> Array[Color]:
	var seen: Dictionary = {}
	var result: Array[Color] = []
	for c in cmds:
		var col: Color = c["color"]
		var key := "%f_%f_%f_%f" % [col.r, col.g, col.b, col.a]
		if not seen.has(key):
			seen[key] = true
			result.append(col)
	return result


func bounds() -> Rect2:
	if cmds.is_empty():
		return Rect2()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cmds:
		for p in c["points"]:
			min_v = Vector2(minf(min_v.x, p.x), minf(min_v.y, p.y))
			max_v = Vector2(maxf(max_v.x, p.x), maxf(max_v.y, p.y))
	if min_v.x == INF:
		return Rect2()
	return Rect2(min_v, max_v - min_v)
