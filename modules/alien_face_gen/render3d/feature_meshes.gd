class_name FeatureMeshes

# Features seat on the actual round head surface (ShellLattice.surface_point) and
# are oriented by the local surface normal, so they stay attached as the head curves.
# Vertex colours bake per-feature albedo * a soft light; materials are unshaded.

static func _surf(x: float, y: float, lm: FaceLandmarks, g: FaceGenome) -> Vector3:
	return ShellLattice.surface_point(x, y, lm, g)


static func _norm(x: float, y: float, lm: FaceLandmarks) -> Vector3:
	return ShellLattice.surface_normal(x, y, lm)


static func _emit(md: MeshData, a: Vector3, b: Vector3, c: Vector3, albedo: Color) -> void:
	ShellLattice._emit_tri(md, a, b, c, albedo)


## Orthonormal frame {right, up} for a given outward normal.
static func _frame(n: Vector3) -> Array:
	var up := Vector3(0, 1, 0)
	if absf(n.dot(up)) > 0.95:
		up = Vector3(0, 0, 1)
	var right := n.cross(up).normalized()
	var up2 := right.cross(n)
	return [right, up2]


## Flat ellipse disc lying in the tangent plane, slightly proud of the surface.
static func _disc(md: MeshData, c: Vector3, n: Vector3, rx: float, ry: float, z_lift: float, albedo: Color) -> void:
	var f := _frame(n)
	var right: Vector3 = f[0]
	var up2: Vector3 = f[1]
	var base := c + n * z_lift
	var segs := 14
	var ring: Array[Vector3] = []
	for k in range(segs):
		var a := TAU * k / segs
		ring.append(base + right * (cos(a) * rx) + up2 * (sin(a) * ry))
	for k in range(segs):
		var nxt := (k + 1) % segs
		_emit(md, base, ring[nxt], ring[k], albedo)


## Shallow rounded bump (half ellipsoid cap) bulging out along the normal.
static func _dome(md: MeshData, c: Vector3, n: Vector3, rx: float, ry: float, height: float, albedo: Color) -> void:
	var f := _frame(n)
	var right: Vector3 = f[0]
	var up2: Vector3 = f[1]
	var apex := c + n * height
	var segs := 12
	var mid: Array[Vector3] = []
	var rim: Array[Vector3] = []
	for k in range(segs):
		var a := TAU * k / segs
		var dx := cos(a) * rx
		var dy := sin(a) * ry
		mid.append(c + right * (dx * 0.66) + up2 * (dy * 0.66) + n * height * 0.55)
		rim.append(c + right * dx + up2 * dy + n * -0.004)
	for k in range(segs):
		var nxt := (k + 1) % segs
		_emit(md, apex, mid[nxt], mid[k], albedo)
		_emit(md, mid[k], mid[nxt], rim[nxt], albedo)
		_emit(md, mid[k], rim[nxt], rim[k], albedo)


static func build_eyes(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if not g.eye_present or g.eye_count == 0:
		return MeshData.new()
	var md := MeshData.new()
	_build_single_eye(md, lm, lm.eye_c_l, g, palette)
	_build_single_eye(md, lm, lm.eye_c_r, g, palette)
	for extra in lm.extra_eyes():
		_build_single_eye(md, lm, extra, g, palette)
	md.surfaces.append({
		"name": &"eyes", "start": 0, "count": md.indices.size(), "material_hint": &"eyes"
	})
	return md


static func _build_single_eye(md: MeshData, lm: FaceLandmarks, pos: Vector2, g: FaceGenome, palette: FacePalette) -> void:
	var w := ShellLattice.half_width(pos.y, lm)
	var ex := clampf(pos.x, -w * 0.8, w * 0.8)
	var seat := _surf(ex, pos.y, lm, g)
	var n := _norm(ex, pos.y, lm)

	# Eye whites: an almond-shaped lens.
	var eye_r := g.eye_size * 0.055 + 0.018
	var rx := eye_r
	var ry := eye_r * (0.8 - g.eye_tilt * 0.0)  # a touch wider than tall
	_dome(md, seat, n, rx, ry, eye_r * 0.55, palette.eye_sclera)

	# Iris + pupil on the front of the lens.
	var iris_pos := seat + n * eye_r * 0.34
	_disc(md, iris_pos, n, rx * 0.62, ry * 0.62, 0.0, palette.eye_iris)
	var pupil_col := palette.eye_pupil
	if g.eye_glow > 0.6:
		pupil_col = palette.eye_glow
	_disc(md, iris_pos + n * 0.004, n, rx * 0.26, ry * 0.3, 0.0, pupil_col)


static func build_nose(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if not g.nose_present or g.nose_type == FaceEnums.NoseType.NONE:
		return MeshData.new()
	var md := MeshData.new()

	var tip_y := lm.nose_tip.y
	var root_y := lm.nose_root.y
	var nw := ShellLattice.half_width(tip_y, lm) * 0.18  # nose half width
	var len := g.nose_length * 0.05 + 0.014
	var centre := _surf(0.0, (root_y + tip_y) * 0.5, lm, g)
	var cn := _norm(0.0, tip_y, lm)

	# Bridge: a low rounded keel down the centre.
	_dome(md, centre, cn, nw * 0.5, g.nose_length * 0.03 + 0.012, len * 0.6, palette.skin_shade)

	# Tip ball, proud of the face.
	var tip := _surf(0.0, tip_y, lm, g)
	var tn := _norm(0.0, tip_y, lm)
	_dome(md, tip, tn, nw, nw * 0.8, len, palette.skin_base)

	# Nostril dots either side of the tip.
	var nw2 := ShellLattice.half_width(tip_y, lm) * 0.16
	for side in [-1.0, 1.0]:
		var nostril := _surf(side * nw2, tip_y - 0.008, lm, g)
		_disc(md, nostril, _norm(side * nw2, tip_y - 0.008, lm), nw2 * 0.28, nw2 * 0.2, 0.002, palette.skin_deep)

	md.surfaces.append({
		"name": &"nose", "start": 0, "count": md.indices.size(), "material_hint": &"shell"
	})
	return md


static func build_mouth(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if not g.mouth_present or g.mouth_type == FaceEnums.MouthType.NONE:
		return MeshData.new()
	var md := MeshData.new()

	var half_w := g.mouth_width * 0.05 + 0.015
	var yc := lm.mouth_c.y
	var c := _surf(0.0, yc, lm, g)
	var n := _norm(0.0, yc, lm)
	var f := _frame(n)
	var right: Vector3 = f[0]
	var up2: Vector3 = f[1]

	# Dark open mouth, widest at the centre and curving up at the corners.
	var mh := g.mouth_height * 0.02 + 0.006
	var segs := 12
	var rim: Array[Vector3] = []
	for k in range(segs):
		var t := k / float(segs - 1)
		var a := lerpf(-PI, 0.0, t)
		var x := cos(a) * half_w
		var yl := sin(a) * mh
		rim.append(c + right * x + up2 * yl + n * 0.006)
	for k in range(segs - 1):
		_emit(md, rim[k], rim[k + 1], rim[k] + n * -0.002, palette.mouth_inner)
		_emit(md, rim[k + 1], rim[k + 1] + n * -0.002, rim[k] + n * -0.002, palette.mouth_inner)

	# Upper and lower lips: thin proud bands framing the opening.
	var upper := c + up2 * (mh * 1.1)
	var lower := c - up2 * (mh * 1.1)
	_disc(md, upper, n, half_w * 0.95, mh * 0.55, 0.004, palette.skin_base)
	_disc(md, lower, n, half_w * 0.9, mh * 0.5, 0.004, palette.skin_shade)

	md.surfaces.append({
		"name": &"mouth", "start": 0, "count": md.indices.size(), "material_hint": &"shell"
	})
	return md


static func build_mandibles(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if not g.mouth_present or g.mouth_type != FaceEnums.MouthType.MANDIBLE or g.mandible_count <= 0:
		return MeshData.new()
	var md := MeshData.new()
	var len := g.mandible_length * 0.05 + 0.015
	for i in range(g.mandible_count):
		var t := (i + 1) / float(g.mandible_count + 1)
		var x := lerpf(lm.mouth_l.x, lm.mouth_r.x, t)
		var base := _surf(x, lm.mouth_c.y, lm, g)
		var tip := base + Vector3(0, len, 0)  # down toward the jaw
		var w2 := 0.006
		_emit(md, base + Vector3(-w2, 0, 0), base + Vector3(w2, 0, 0), tip, palette.skin_deep)
		_emit(md, base + Vector3(0, 0, -w2), base + Vector3(0, 0, w2), tip, palette.skin_deep)
	md.surfaces.append({
		"name": &"mandible", "start": 0, "count": md.indices.size(), "material_hint": &"shell"
	})
	return md


static func build_crest(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if g.crest_type == FaceEnums.CrestType.NONE or g.crest_count <= 0:
		return MeshData.new()
	var md := MeshData.new()
	var len := g.crest_length * 0.08 + 0.02
	var count := mini(g.crest_count, 6)
	# Walk across the crown — crests rise UP (−y).
	for i in range(count):
		var t := (i + 1) / float(count + 1)
		var x := lerpf(-0.2, 0.2, t)
		var yb := lm.crown.y + 0.05
		var base := _surf(x, yb, lm, g)
		var tip := base + Vector3(0, -len, 0)
		var w2 := g.crest_thickness * 0.008 + 0.003
		_emit(md, base + Vector3(-w2, 0, 0), base + Vector3(w2, 0, 0), tip, palette.crest)
		_emit(md, base + Vector3(0, 0, -w2), base + Vector3(0, 0, w2), tip, palette.crest)
	md.surfaces.append({
		"name": &"crest", "start": 0, "count": md.indices.size(), "material_hint": &"crest"
	})
	return md


static func build_ears(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if g.ear_type == FaceEnums.EarType.NONE:
		return MeshData.new()
	var md := MeshData.new()
	var len := g.ear_size * 0.05 + 0.015
	for side in [-1.0, 1.0]:
		var ear_lm := lm.ear_l if side < 0 else lm.ear_r
		var w := ShellLattice.half_width(ear_lm.y, lm)
		var x = side * w * 0.97
		var seat := _surf(x, ear_lm.y, lm, g)
		var n := _norm(x, ear_lm.y, lm)
		# Simple fin sticking out from the side of the head.
		var tip := seat + n * len * 1.3
		var up := 0.006
		_emit(md, seat + Vector3(0, -up, 0), seat + Vector3(0, up, 0), tip, palette.skin_base)
		_emit(md, seat + Vector3(0, up, 0), seat + n * up + Vector3(0, up, 0), tip, palette.skin_deep)
	md.surfaces.append({
		"name": &"ears", "start": 0, "count": md.indices.size(), "material_hint": &"shell"
	})
	return md


static func build_headgear(lm: FaceLandmarks, g: FaceGenome, palette: FacePalette) -> MeshData:
	if g.headgear_type == FaceEnums.HeadgearType.NONE:
		return MeshData.new()
	var md := MeshData.new()
	var crown := _surf(0.0, lm.crown.y, lm, g)
	var tl := _surf(lm.temple_l.x * 0.55, lm.crown.y, lm, g)
	var tr := _surf(lm.temple_r.x * 0.55, lm.crown.y, lm, g)
	var apex := crown + Vector3(0, -0.08, 0)
	_emit(md, apex, tr, tl, palette.garment)
	md.surfaces.append({
		"name": &"headgear", "start": 0, "count": md.indices.size(), "material_hint": &"garment"
	})
	return md
