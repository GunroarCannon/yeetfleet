class_name FaceLandmarks extends RefCounted

# Named landmark points (Vector2, normalised space)
var crown: Vector2 = Vector2.ZERO
var hairline: Vector2 = Vector2.ZERO
var brow_l: Vector2 = Vector2.ZERO
var brow_c: Vector2 = Vector2.ZERO
var brow_r: Vector2 = Vector2.ZERO
var temple_l: Vector2 = Vector2.ZERO
var temple_r: Vector2 = Vector2.ZERO
var eye_c_l: Vector2 = Vector2.ZERO
var eye_c_r: Vector2 = Vector2.ZERO
var cheek_l: Vector2 = Vector2.ZERO
var cheek_r: Vector2 = Vector2.ZERO
var nose_root: Vector2 = Vector2.ZERO
var nose_tip: Vector2 = Vector2.ZERO
var nose_base: Vector2 = Vector2.ZERO
var mouth_l: Vector2 = Vector2.ZERO
var mouth_c: Vector2 = Vector2.ZERO
var mouth_r: Vector2 = Vector2.ZERO
var jaw_l: Vector2 = Vector2.ZERO
var jaw_r: Vector2 = Vector2.ZERO
var chin: Vector2 = Vector2.ZERO
var ear_l: Vector2 = Vector2.ZERO
var ear_r: Vector2 = Vector2.ZERO
var neck_l: Vector2 = Vector2.ZERO
var neck_r: Vector2 = Vector2.ZERO

# Outline ring: exactly 24 points, clockwise from crown
var outline: PackedVector2Array = PackedVector2Array()

# Extra eyes (for eye_count > 2)
var _extra_eyes: Array[Vector2] = []

# Mirror axis (usually 0.0, offset by skull_asymmetry)
var mirror_axis_x: float = 0.0


func get_point(name: StringName) -> Vector2:
	match name:
		&"crown": return crown
		&"hairline": return hairline
		&"brow_l": return brow_l
		&"brow_c": return brow_c
		&"brow_r": return brow_r
		&"temple_l": return temple_l
		&"temple_r": return temple_r
		&"eye_c_l": return eye_c_l
		&"eye_c_r": return eye_c_r
		&"cheek_l": return cheek_l
		&"cheek_r": return cheek_r
		&"nose_root": return nose_root
		&"nose_tip": return nose_tip
		&"nose_base": return nose_base
		&"mouth_l": return mouth_l
		&"mouth_c": return mouth_c
		&"mouth_r": return mouth_r
		&"jaw_l": return jaw_l
		&"jaw_r": return jaw_r
		&"chin": return chin
		&"ear_l": return ear_l
		&"ear_r": return ear_r
		&"neck_l": return neck_l
		&"neck_r": return neck_r
	return Vector2.ZERO


func extra_eyes() -> Array[Vector2]:
	return _extra_eyes


func bounds() -> Rect2:
	var points: Array[Vector2] = [crown, chin, jaw_l, jaw_r, cheek_l, cheek_r,
		temple_l, temple_r, ear_l, ear_r]
	points.append_array(_extra_eyes)
	if outline.size() > 0:
		for p in outline:
			points.append(p)
	if points.is_empty():
		return Rect2()
	var min_v := points[0]
	var max_v := points[0]
	for p in points:
		min_v = Vector2(minf(min_v.x, p.x), minf(min_v.y, p.y))
		max_v = Vector2(maxf(max_v.x, p.x), maxf(max_v.y, p.y))
	return Rect2(min_v, max_v - min_v)
