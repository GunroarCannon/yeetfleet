class_name StyleFlatVector extends StyleBase2D

const _Z := {
	&"bg_block": 0, &"collar": 10, &"neck": 15, &"head_shell": 20, &"head_shade": 25,
	&"cheek": 30, &"ear_l": 35, &"ear_r": 36, &"brow_l": 40, &"brow_r": 41,
	&"eye_socket": 45, &"eye_sclera": 50, &"eye_iris": 55, &"eye_pupil": 60,
	&"nose": 65, &"mouth": 70, &"mandible": 75, &"marking": 80,
	&"crest": 85, &"headgear": 90, &"ocular_gear": 95, &"outline_pass": 100
}


func style_id() -> StringName:
	return &"flat_vector"


func silhouette_defining_slots() -> Array[StringName]:
	return [&"head_shell", &"crest", &"ear_l", &"ear_r"]


func background(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	# Full-frame rect in background colour
	dl.poly(PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)
	]), p.background, _Z[&"bg_block"], &"bg_block")


func draw_feature(slot: StringName, dl: DrawList, g: FaceGenome, lm: FaceLandmarks,
		p: FacePalette, lod: int) -> void:
	match slot:
		&"neck":
			_draw_neck(dl, lm, g, p, lod)
		&"head_shell":
			_draw_head_shell(dl, lm, p, lod)
		&"head_shade":
			if lod <= Lod.LOD_STANDARD:
				_draw_head_shade(dl, lm, p, lod)
		&"cheek":
			_draw_cheek(dl, lm, g, p, lod)
		&"ear_l":
			_draw_ear(dl, lm, g, p, lod, true)
		&"ear_r":
			_draw_ear(dl, lm, g, p, lod, false)
		&"brow_l":
			if g.brow_present:
				_draw_brow(dl, lm, g, p, lod, true)
		&"brow_r":
			if g.brow_present:
				_draw_brow(dl, lm, g, p, lod, false)
		&"eye_socket":
			pass  # FlatVector doesn't draw separate sockets
		&"eye_sclera":
			_draw_eye(dl, lm, g, p, lod, true)
		&"eye_iris":
			pass  # Drawn as part of eye
		&"eye_pupil":
			pass  # Drawn as part of eye
		&"nose":
			_draw_nose(dl, lm, g, p, lod)
		&"mouth":
			_draw_mouth(dl, lm, g, p, lod)
		&"mandible":
			_draw_mandibles(dl, lm, g, p, lod)
		&"marking":
			_draw_markings(dl, lm, g, p, lod)
		&"crest":
			_draw_crest(dl, lm, g, p, lod)
		&"headgear":
			_draw_headgear(dl, lm, g, p, lod)
		&"ocular_gear":
			_draw_ocular_gear(dl, lm, g, p, lod)
		&"outline_pass":
			_draw_outline(dl, lm, p, lod)


func post(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	pass


func _draw_neck(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	var pts := PackedVector2Array([
		lm.neck_l,
		Vector2(lm.neck_l.x, 0.6),
		Vector2(lm.neck_r.x, 0.6),
		lm.neck_r
	])
	dl.poly(pts, p.skin_base, _Z[&"neck"], &"neck")


func _draw_head_shell(dl: DrawList, lm: FaceLandmarks, p: FacePalette, lod: int) -> void:
	if lm.outline.size() >= 3:
		dl.poly(lm.outline, p.skin_base, _Z[&"head_shell"], &"head_shell")


func _draw_head_shade(dl: DrawList, lm: FaceLandmarks, p: FacePalette, lod: int) -> void:
	# Lower-left third of the head for shading
	var shade_pts := PackedVector2Array()
	for pt in lm.outline:
		if pt.y > 0.0 or pt.x < -0.1:
			shade_pts.append(pt)
	if shade_pts.size() >= 3:
		dl.poly(shade_pts, p.skin_shade, _Z[&"head_shade"], &"head_shade")


func _draw_cheek(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	var size := 0.04 + g.cheek_prominence * 0.06
	dl.circle(lm.cheek_l, size, p.skin_light, _Z[&"cheek"], &"cheek")
	dl.circle(lm.cheek_r, size, p.skin_light, _Z[&"cheek"], &"cheek")


func _draw_ear(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int, is_left: bool) -> void:
	if g.ear_type == FaceEnums.EarType.NONE:
		return
	var ear_pt := lm.ear_l if is_left else lm.ear_r
	var size := g.ear_size * 0.08 + 0.02
	var z_key := &"ear_l" if is_left else &"ear_r"
	
	match g.ear_type:
		FaceEnums.EarType.LOBE:
			dl.circle(ear_pt, size, p.skin_deep, _Z[z_key], z_key)
		FaceEnums.EarType.POINT:
			var tip := ear_pt + Vector2(-0.03 if is_left else 0.03, -size * 1.5)
			dl.poly(PackedVector2Array([
				ear_pt + Vector2(0, -size * 0.5), tip, ear_pt + Vector2(0, size * 0.5)
			]), p.skin_base, _Z[z_key], z_key)
		FaceEnums.EarType.FIN:
			dl.ellipse(ear_pt, size * 1.5, size * 0.5, 0.3 if is_left else -0.3,
				p.skin_base, _Z[z_key], z_key)
		FaceEnums.EarType.FRILL:
			var tip := ear_pt + Vector2(-0.04 if is_left else 0.04, -size * 1.2)
			dl.poly(PackedVector2Array([
				ear_pt + Vector2(0, -size), tip, ear_pt + Vector2(0, size)
			]), p.crest, _Z[z_key], z_key)
		FaceEnums.EarType.HOLE:
			dl.circle(ear_pt, size * 0.4, p.skin_deep, _Z[z_key], z_key)
		FaceEnums.EarType.ANTENNA_EAR:
			var tip := ear_pt + Vector2(0, -size * 2.5)
			dl.line(PackedVector2Array([ear_pt, tip]), p.skin_base, 0.003, _Z[z_key], z_key)
			dl.circle(tip, size * 0.3, p.eye_glow, _Z[z_key], z_key)


func _draw_brow(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int, is_left: bool) -> void:
	var brow_pt := lm.brow_l if is_left else lm.brow_r
	var thickness := g.brow_thickness * 0.02 + 0.005
	var angle := (g.brow_angle - 0.5) * 0.8
	
	var dir := Vector2(-1, angle) if is_left else Vector2(1, -angle)
	var start := brow_pt - dir * 0.04
	var end_pt := brow_pt + dir * 0.04
	
	# Draw as a thin polygon (thick line)
	var perp := Vector2(-dir.y, dir.x).normalized() * thickness
	var pts := PackedVector2Array([
		start + perp, end_pt + perp, end_pt - perp, start - perp
	])
	dl.poly(pts, p.skin_deep, _Z[&"brow_l" if is_left else &"brow_r"],
		&"brow_l" if is_left else &"brow_r")


func _draw_eye(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int, _is_left: bool) -> void:
	if not g.eye_present or g.eye_count == 0:
		return
	
	# Draw the primary eyes
	_draw_single_eye(dl, lm.eye_c_l, g, p, lod)
	_draw_single_eye(dl, lm.eye_c_r, g, p, lod)
	
	# Draw extra eyes
	for extra_pos in lm.extra_eyes():
		_draw_single_eye(dl, extra_pos, g, p, lod)


func _draw_single_eye(dl: DrawList, pos: Vector2, g: FaceGenome, p: FacePalette, lod: int) -> void:
	var size := g.eye_size * 0.06 + 0.02
	
	# Eye shape determines the sclera
	match g.eye_shape:
		FaceEnums.EyeShape.ROUND:
			dl.circle(pos, size, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			_draw_pupil(dl, pos, size, g, p, lod)
		FaceEnums.EyeShape.ALMOND:
			var pts := PackedVector2Array()
			for i in range(Lod.curve_samples(lod)):
				var t := TAU * i / Lod.curve_samples(lod)
				var rx := size * 1.4
				var ry := size * 0.7
				pts.append(Vector2(pos.x + cos(t) * rx, pos.y + sin(t) * ry))
			dl.poly(pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			_draw_pupil(dl, pos, size * 0.7, g, p, lod)
		FaceEnums.EyeShape.SLIT_V:
			var pts := PackedVector2Array([
				pos + Vector2(0, -size), pos + Vector2(size * 0.2, 0),
				pos + Vector2(0, size), pos + Vector2(-size * 0.2, 0)
			])
			dl.poly(pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			if g.pupil_shape != FaceEnums.PupilShape.NONE:
				dl.circle(pos, size * 0.15, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.EyeShape.SLIT_H:
			var pts := PackedVector2Array([
				pos + Vector2(-size, 0), pos + Vector2(0, -size * 0.2),
				pos + Vector2(size, 0), pos + Vector2(0, size * 0.2)
			])
			dl.poly(pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			if g.pupil_shape != FaceEnums.PupilShape.NONE:
				dl.circle(pos, size * 0.15, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.EyeShape.COMPOUND:
			# Multiple small circles in a larger oval
			var outer_pts := PackedVector2Array()
			for i in range(Lod.curve_samples(lod)):
				var t := TAU * i / Lod.curve_samples(lod)
				outer_pts.append(Vector2(pos.x + cos(t) * size * 1.2, pos.y + sin(t) * size))
			dl.poly(outer_pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			for j in range(3):
				var offset := Vector2((j - 1) * size * 0.4, 0)
				dl.circle(pos + offset, size * 0.25, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.EyeShape.TRIANGLE:
			var pts := PackedVector2Array([
				pos + Vector2(0, -size), pos + Vector2(size, size * 0.6),
				pos + Vector2(-size, size * 0.6)
			])
			dl.poly(pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			_draw_pupil(dl, pos, size * 0.4, g, p, lod)
		FaceEnums.EyeShape.HEX:
			var pts := PackedVector2Array()
			for i in range(6):
				var t := TAU * i / 6
				pts.append(Vector2(pos.x + cos(t) * size, pos.y + sin(t) * size))
			dl.poly(pts, p.eye_sclera, _Z[&"eye_sclera"], &"eye_sclera")
			_draw_pupil(dl, pos, size * 0.4, g, p, lod)
		FaceEnums.EyeShape.VOID:
			# Dark void - uses pupil colour for sclera
			dl.circle(pos, size, p.eye_pupil, _Z[&"eye_sclera"], &"eye_sclera")
			if g.eye_glow > 0.3:
				dl.circle(pos, size * 0.6, p.eye_glow, _Z[&"eye_pupil"], &"eye_pupil")
	
	# Eye glow
	if g.eye_glow > 0.5:
		dl.circle(pos, size * 1.1, Color(p.eye_glow.r, p.eye_glow.g, p.eye_glow.b, 0.3),
			_Z[&"eye_sclera"] - 1, &"eye_sclera")


func _draw_pupil(dl: DrawList, pos: Vector2, pupil_r: float, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if g.pupil_shape == FaceEnums.PupilShape.NONE:
		return
	
	match g.pupil_shape:
		FaceEnums.PupilShape.ROUND:
			dl.circle(pos, pupil_r, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.SLIT_V:
			var pts := PackedVector2Array([
				pos + Vector2(0, -pupil_r * 1.2),
				pos + Vector2(pupil_r * 0.2, 0),
				pos + Vector2(0, pupil_r * 1.2),
				pos + Vector2(-pupil_r * 0.2, 0)
			])
			dl.poly(pts, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.SLIT_H:
			var pts := PackedVector2Array([
				pos + Vector2(-pupil_r * 1.2, 0),
				pos + Vector2(0, -pupil_r * 0.2),
				pos + Vector2(pupil_r * 1.2, 0),
				pos + Vector2(0, pupil_r * 0.2)
			])
			dl.poly(pts, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.GOAT:
			dl.circle(pos, pupil_r, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
			dl.line(PackedVector2Array([
				pos + Vector2(0, -pupil_r * 1.3), pos + Vector2(0, pupil_r * 1.3)
			]), p.eye_iris, 0.002, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.MULTI:
			for j in range(3):
				var offset := Vector2((j - 1) * pupil_r * 0.5, 0)
				dl.circle(pos + offset, pupil_r * 0.3, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.STAR:
			var pts := PackedVector2Array()
			for i in range(5):
				var angle := TAU * i / 5 - PI / 2
				pts.append(pos + Vector2(cos(angle) * pupil_r, sin(angle) * pupil_r))
				var mid_angle := angle + TAU / 10
				pts.append(pos + Vector2(cos(mid_angle) * pupil_r * 0.4, sin(mid_angle) * pupil_r * 0.4))
			dl.poly(pts, p.eye_pupil, _Z[&"eye_pupil"], &"eye_pupil")
		FaceEnums.PupilShape.NONE:
			pass


func _draw_nose(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if not g.nose_present or g.nose_type == FaceEnums.NoseType.NONE:
		return
	
	var bridge_w := g.nose_width * 0.03 + 0.005
	var length := g.nose_length * 0.06 + 0.02
	
	match g.nose_type:
		FaceEnums.NoseType.NUB:
			dl.circle(lm.nose_tip, 0.015 + g.nose_width * 0.01, p.skin_shade,
				_Z[&"nose"], &"nose")
		FaceEnums.NoseType.HUMAN:
			# Bridge line + tip
			var pts := PackedVector2Array([
				lm.nose_root + Vector2(-bridge_w, 0),
				lm.nose_root + Vector2(bridge_w, 0),
				lm.nose_tip + Vector2(bridge_w * 1.5, 0),
				lm.nose_tip + Vector2(0, 0.01),
				lm.nose_tip + Vector2(-bridge_w * 1.5, 0)
			])
			dl.poly(pts, p.skin_shade, _Z[&"nose"], &"nose")
			# Nostrils
			if g.nostril_flare > 0.3:
				dl.circle(lm.nose_tip + Vector2(-0.01, 0.005), 0.004, p.skin_deep,
					_Z[&"nose"] + 1, &"nose")
				dl.circle(lm.nose_tip + Vector2(0.01, 0.005), 0.004, p.skin_deep,
					_Z[&"nose"] + 1, &"nose")
		FaceEnums.NoseType.SNOUT:
			var pts := PackedVector2Array([
				lm.nose_root + Vector2(-bridge_w * 2, 0),
				lm.nose_root + Vector2(bridge_w * 2, 0),
				lm.nose_tip + Vector2(bridge_w * 3, 0),
				lm.nose_tip + Vector2(0, 0.015),
				lm.nose_tip + Vector2(-bridge_w * 3, 0)
			])
			dl.poly(pts, p.skin_shade, _Z[&"nose"], &"nose")
		FaceEnums.NoseType.BEAK:
			var tip := lm.nose_tip + Vector2(0, length * 0.5)
			var pts := PackedVector2Array([
				lm.nose_root + Vector2(-bridge_w, 0),
				tip,
				lm.nose_root + Vector2(bridge_w, 0)
			])
			dl.poly(pts, p.skin_deep, _Z[&"nose"], &"nose")
		FaceEnums.NoseType.SLIT:
			dl.line(PackedVector2Array([lm.nose_root, lm.nose_tip]),
				p.skin_deep, 0.003, _Z[&"nose"], &"nose")
		FaceEnums.NoseType.TRUNK:
			var pts := PackedVector2Array([
				lm.nose_root + Vector2(-bridge_w * 1.5, 0),
				lm.nose_root + Vector2(bridge_w * 1.5, 0),
				lm.nose_tip + Vector2(bridge_w, length * 0.3),
				lm.nose_tip + Vector2(-bridge_w, length * 0.3)
			])
			dl.poly(pts, p.skin_shade, _Z[&"nose"], &"nose")
		FaceEnums.NoseType.PLATE:
			var pts := PackedVector2Array([
				lm.nose_root + Vector2(-bridge_w * 3, 0),
				lm.nose_root + Vector2(bridge_w * 3, 0),
				lm.nose_base + Vector2(bridge_w * 2, 0),
				lm.nose_base + Vector2(-bridge_w * 2, 0)
			])
			dl.poly(pts, p.skin_deep, _Z[&"nose"], &"nose")


func _draw_mouth(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if not g.mouth_present or g.mouth_type == FaceEnums.MouthType.NONE:
		return
	
	var w := g.mouth_width * 0.06 + 0.02
	var h := g.mouth_height * 0.02 + 0.005
	var curve := (g.mouth_curve - 0.5) * 0.03
	
	match g.mouth_type:
		FaceEnums.MouthType.LIPS:
			var pts := PackedVector2Array([
				lm.mouth_l,
				Vector2(lm.mouth_c.x, lm.mouth_c.y - h + curve),
				lm.mouth_r,
				Vector2(lm.mouth_c.x, lm.mouth_c.y + h + curve)
			])
			dl.poly(pts, p.mouth_inner, _Z[&"mouth"], &"mouth")
			if g.lip_thickness > 0.3 and lod <= Lod.LOD_STANDARD:
				dl.line(PackedVector2Array([lm.mouth_l, lm.mouth_r]),
					p.skin_deep, 0.002, _Z[&"mouth"] + 1, &"mouth")
		FaceEnums.MouthType.THIN:
			dl.line(PackedVector2Array([
				lm.mouth_l, Vector2(lm.mouth_c.x, lm.mouth_c.y + curve), lm.mouth_r
			]), p.skin_deep, 0.002, _Z[&"mouth"], &"mouth")
		FaceEnums.MouthType.BEAK:
			var pts := PackedVector2Array([
				lm.mouth_l, Vector2(lm.mouth_c.x, lm.mouth_c.y + h),
				lm.mouth_r, Vector2(lm.mouth_c.x, lm.mouth_c.y - h * 0.3)
			])
			dl.poly(pts, p.tooth, _Z[&"mouth"], &"mouth")
		FaceEnums.MouthType.MANDIBLE:
			pass  # Drawn separately
		FaceEnums.MouthType.VENT:
			dl.ellipse(lm.mouth_c, w * 0.5, h, 0, p.skin_deep, _Z[&"mouth"], &"mouth")
		FaceEnums.MouthType.SUCKER:
			dl.circle(lm.mouth_c, w * 0.4, p.mouth_inner, _Z[&"mouth"], &"mouth")
			dl.circle(lm.mouth_c, w * 0.2, p.skin_deep, _Z[&"mouth"] + 1, &"mouth")
		FaceEnums.MouthType.STITCHED:
			dl.line(PackedVector2Array([lm.mouth_l, lm.mouth_r]),
				p.skin_deep, 0.003, _Z[&"mouth"], &"mouth")
			# Stitch marks
			for i in range(5):
				var t := (i + 1) / 6.0
				var x := lerpf(lm.mouth_l.x, lm.mouth_r.x, t)
				dl.line(PackedVector2Array([
					Vector2(x, lm.mouth_c.y - h * 2), Vector2(x, lm.mouth_c.y + h * 2)
				]), p.skin_deep, 0.001, _Z[&"mouth"] + 1, &"mouth")
		FaceEnums.MouthType.TUSKED:
			# Two upward-pointing tusks
			for side in [-1, 1]:
				var base := lm.mouth_c + Vector2(side * w * 0.3, 0)
				var tip := base + Vector2(side * w * 0.1, -h * 3)
				dl.poly(PackedVector2Array([
					base + Vector2(-w * 0.05, 0), tip, base + Vector2(w * 0.05, 0)
				]), p.tooth, _Z[&"mouth"] + 1, &"mouth")
			dl.line(PackedVector2Array([lm.mouth_l, lm.mouth_r]),
				p.skin_deep, 0.002, _Z[&"mouth"], &"mouth")


func _draw_mandibles(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if not g.mouth_present or g.mouth_type != FaceEnums.MouthType.MANDIBLE:
		return
	if g.mandible_count <= 0:
		return
	
	var count := g.mandible_count
	var len := g.mandible_length * 0.06 + 0.02
	
	for i in range(count):
		var t := (i + 1) / float(count + 1)
		var x := lerpf(lm.mouth_l.x, lm.mouth_r.x, t)
		var base := Vector2(x, lm.mouth_c.y)
		# Chevron shape pointing down
		var tip := base + Vector2(0, len)
		var left := base + Vector2(-0.01, len * 0.3)
		var right := base + Vector2(0.01, len * 0.3)
		dl.poly(PackedVector2Array([left, tip, right]),
			p.skin_deep, _Z[&"mandible"], &"mandible")


func _draw_markings(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if g.marking_type == FaceEnums.MarkingType.NONE or g.marking_count <= 0:
		return
	
	var count := mini(g.marking_count, 1) if lod >= Lod.LOD_COMPACT else g.marking_count
	var rng := RandomNumberGenerator.new()
	rng.seed = g.seed + 2000
	
	var col := p.marking_a if g.marking_hue < 0.5 else p.marking_b
	
	match g.marking_type:
		FaceEnums.MarkingType.STRIPE:
			for i in range(count):
				var y := lm.crown.y + (lm.chin.y - lm.crown.y) * (i + 1) / float(count + 1)
				var pts := PackedVector2Array([
					Vector2(-0.3, y - 0.005), Vector2(0.3, y - 0.005),
					Vector2(0.3, y + 0.005), Vector2(-0.3, y + 0.005)
				])
				dl.poly(pts, col, _Z[&"marking"], &"marking")
		FaceEnums.MarkingType.SPOT:
			for i in range(count):
				var angle := rng.randf() * TAU
				var dist := rng.randf() * 0.15
				var center := Vector2(cos(angle) * dist, sin(angle) * dist + 0.1)
				dl.circle(center, 0.015 + rng.randf() * 0.01, col,
					_Z[&"marking"], &"marking")
		FaceEnums.MarkingType.WARPAINT:
			# Two diagonal lines from eyes to chin
			dl.line(PackedVector2Array([
				lm.eye_c_l + Vector2(0, 0.01), lm.chin + Vector2(-0.03, 0)
			]), col, 0.003, _Z[&"marking"], &"marking")
			dl.line(PackedVector2Array([
				lm.eye_c_r + Vector2(0, 0.01), lm.chin + Vector2(0.03, 0)
			]), col, 0.003, _Z[&"marking"], &"marking")
		FaceEnums.MarkingType.CIRCUIT:
			# Geometric lines
			for i in range(count):
				var start := Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3))
				var end_pt := start + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
				dl.line(PackedVector2Array([start, end_pt]), col, 0.001,
					_Z[&"marking"], &"marking")
		FaceEnums.MarkingType.SCAR_TISSUE:
			for i in range(count):
				var start := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.2))
				var end_pt := start + Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
				dl.line(PackedVector2Array([start, end_pt]), p.skin_deep, 0.002,
					_Z[&"marking"], &"marking")
		FaceEnums.MarkingType.GLYPH:
			for i in range(count):
				var center := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.2))
				var pts := PackedVector2Array()
				var sides := rng.randi_range(3, 6)
				for j in range(sides):
					var a := TAU * j / sides
					pts.append(center + Vector2(cos(a) * 0.02, sin(a) * 0.02))
				dl.poly(pts, col, _Z[&"marking"], &"marking")
		FaceEnums.MarkingType.GRADIENT_BAND:
			# Horizontal band across middle
			var y := 0.05
			var band_h := g.marking_coverage * 0.08 + 0.02
			var pts := PackedVector2Array([
				Vector2(-0.4, y - band_h), Vector2(0.4, y - band_h),
				Vector2(0.4, y + band_h), Vector2(-0.4, y + band_h)
			])
			dl.poly(pts, Color(col.r, col.g, col.b, 0.5), _Z[&"marking"], &"marking")


func _draw_crest(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if g.crest_type == FaceEnums.CrestType.NONE or g.crest_count <= 0:
		return
	
	var count := g.crest_count
	if lod >= Lod.LOD_COMPACT:
		count = 1
	
	var len := g.crest_length * 0.08 + 0.02
	var spread := g.crest_spread * 0.3 + 0.1
	
	for i in range(count):
		var t := (i + 1) / float(count + 1)
		var angle = lerp(-spread, spread, t) + PI / 2  # Upward from crown
		var base = lm.crown + Vector2(lerp(-0.1, 0.1, t), 0)
		var tip = base + Vector2(cos(angle) * len * 0.3, -sin(angle) * len)
		
		match g.crest_type:
			FaceEnums.CrestType.HAIR:
				dl.line(PackedVector2Array([base, tip]), p.crest, 0.003 + g.crest_thickness * 0.002,
					_Z[&"crest"], &"crest")
			FaceEnums.CrestType.HORN:
				dl.poly(PackedVector2Array([
					base + Vector2(-0.008, 0), tip, base + Vector2(0.008, 0)
				]), p.crest, _Z[&"crest"], &"crest")
			FaceEnums.CrestType.ANTENNA:
				dl.line(PackedVector2Array([base, tip]), p.crest, 0.002,
					_Z[&"crest"], &"crest")
				dl.circle(tip, 0.008, p.eye_glow, _Z[&"crest"] + 1, &"crest")
			FaceEnums.CrestType.FRILL:
				var mid := base.lerp(tip, 0.5) + Vector2(0.02 * (1 if t > 0.5 else -1), 0)
				dl.poly(PackedVector2Array([base, mid, tip]),
					p.crest, _Z[&"crest"], &"crest")
			FaceEnums.CrestType.SPINE:
				dl.poly(PackedVector2Array([
					base + Vector2(-0.005, 0), tip, base + Vector2(0.005, 0)
				]), p.crest, _Z[&"crest"], &"crest")
			FaceEnums.CrestType.TENDRIL:
				var mid := base.lerp(tip, 0.5)
				mid.x += sin(t * PI) * 0.03
				dl.line(PackedVector2Array([base, mid, tip]), p.crest, 0.002,
					_Z[&"crest"], &"crest")
			FaceEnums.CrestType.FIN:
				var fin_pts := PackedVector2Array([
					base, tip, base + Vector2(0, len * 0.5)
				])
				dl.poly(fin_pts, p.crest, _Z[&"crest"], &"crest")
			FaceEnums.CrestType.PLUME:
				dl.ellipse(tip, len * 0.3, len * 0.15, angle, p.crest,
					_Z[&"crest"], &"crest")


func _draw_headgear(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if g.headgear_type == FaceEnums.HeadgearType.NONE:
		return
	
	var band_y := lm.crown.y + 0.05
	
	match g.headgear_type:
		FaceEnums.HeadgearType.CAP:
			var pts := PackedVector2Array([
				lm.temple_l + Vector2(0, -0.02), lm.crown + Vector2(0, -0.05),
				lm.temple_r + Vector2(0, -0.02), lm.temple_r + Vector2(0, 0.01),
				lm.temple_l + Vector2(0, 0.01)
			])
			dl.poly(pts, p.garment, _Z[&"headgear"], &"headgear")
		FaceEnums.HeadgearType.HELM:
			var pts := PackedVector2Array([
				lm.temple_l + Vector2(-0.02, 0), lm.crown + Vector2(0, -0.06),
				lm.temple_r + Vector2(0.02, 0), lm.temple_r + Vector2(0, 0.03),
				lm.temple_l + Vector2(0, 0.03)
			])
			dl.poly(pts, p.garment, _Z[&"headgear"], &"headgear")
			dl.line(PackedVector2Array([lm.temple_l + Vector2(0, 0.03), lm.temple_r + Vector2(0, 0.03)]),
				p.garment_trim, 0.003, _Z[&"headgear"] + 1, &"headgear")
		FaceEnums.HeadgearType.BAND:
			dl.line(PackedVector2Array([
				lm.temple_l + Vector2(0, 0.01), lm.crown + Vector2(0, band_y),
				lm.temple_r + Vector2(0, 0.01)
			]), p.garment, 0.004, _Z[&"headgear"], &"headgear")
		FaceEnums.HeadgearType.CROWN:
			var pts := PackedVector2Array()
			var crown_w := 0.15
			for i in range(5):
				var x := lm.crown.x + (i - 2) * crown_w / 4
				var y := lm.crown.y - 0.04 if i % 2 == 0 else lm.crown.y
				pts.append(Vector2(x, y))
			pts.append(Vector2(lm.crown.x + crown_w / 2, lm.crown.y + 0.01))
			pts.append(Vector2(lm.crown.x - crown_w / 2, lm.crown.y + 0.01))
			dl.poly(pts, p.garment_trim, _Z[&"headgear"], &"headgear")
		FaceEnums.HeadgearType.BREATHER:
			dl.circle(lm.mouth_c, 0.04, p.garment, _Z[&"headgear"], &"headgear")
			dl.circle(lm.mouth_c, 0.025, p.garment_trim, _Z[&"headgear"] + 1, &"headgear")
		FaceEnums.HeadgearType.WRAP:
			dl.line(PackedVector2Array([
				lm.temple_l, lm.crown, lm.temple_r
			]), p.garment, 0.005, _Z[&"headgear"], &"headgear")


func _draw_ocular_gear(dl: DrawList, lm: FaceLandmarks, g: FaceGenome, p: FacePalette, lod: int) -> void:
	if g.ocular_gear == FaceEnums.OcularGear.NONE:
		return
	
	match g.ocular_gear:
		FaceEnums.OcularGear.VISOR:
			var pts := PackedVector2Array([
				lm.eye_c_l + Vector2(-0.03, -0.02),
				lm.eye_c_r + Vector2(0.03, -0.02),
				lm.eye_c_r + Vector2(0.03, 0.02),
				lm.eye_c_l + Vector2(-0.03, 0.02)
			])
			dl.poly(pts, p.garment_trim, _Z[&"ocular_gear"], &"ocular_gear")
		FaceEnums.OcularGear.GOGGLES:
			dl.circle(lm.eye_c_l, 0.03, p.garment_trim, _Z[&"ocular_gear"], &"ocular_gear")
			dl.circle(lm.eye_c_r, 0.03, p.garment_trim, _Z[&"ocular_gear"], &"ocular_gear")
			dl.line(PackedVector2Array([lm.eye_c_l, lm.eye_c_r]),
				p.garment, 0.002, _Z[&"ocular_gear"] + 1, &"ocular_gear")
		FaceEnums.OcularGear.MONO_LENS:
			dl.circle(lm.eye_c_r, 0.035, p.garment_trim, _Z[&"ocular_gear"], &"ocular_gear")
			dl.line(PackedVector2Array([
				lm.eye_c_r + Vector2(0.035, 0), lm.eye_c_r + Vector2(0.1, 0)
			]), p.garment, 0.001, _Z[&"ocular_gear"] + 1, &"ocular_gear")
		FaceEnums.OcularGear.IMPLANT:
			dl.circle(lm.eye_c_r, 0.015, p.garment_trim, _Z[&"ocular_gear"], &"ocular_gear")
			dl.line(PackedVector2Array([
				lm.eye_c_r, lm.eye_c_r + Vector2(0.05, -0.05)
			]), p.garment_trim, 0.001, _Z[&"ocular_gear"] + 1, &"ocular_gear")


func _draw_outline(dl: DrawList, lm: FaceLandmarks, p: FacePalette, lod: int) -> void:
	if p.outline.a <= 0.0:
		return
	if lm.outline.size() >= 3:
		var pts := lm.outline.duplicate()
		pts.append(pts[0])  # Close the loop
		dl.line(pts, p.outline, 0.002, _Z[&"outline_pass"], &"outline_pass")
