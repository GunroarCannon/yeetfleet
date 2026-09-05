class_name LandmarkSolver

# φ-derived baseline proportions (normalised space, origin at head centre)
# head_height / head_width = 1.618
const _PHI := 1.6180339887
const _INV_PHI := 1.0 / _PHI
const _INV_PHI2 := 1.0 / (_PHI * _PHI)

# Baseline points before genome deformation
const _BASE_CROWN := Vector2(0.0, -0.5)
const _BASE_HAIRLINE := Vector2(0.0, -0.382)  # crown + 1/φ²
const _BASE_BROW_L := Vector2(-0.3, -0.191)
const _BASE_BROW_C := Vector2(0.0, -0.191)
const _BASE_BROW_R := Vector2(0.3, -0.191)
const _BASE_TEMPLE_L := Vector2(-0.4, -0.1)
const _BASE_TEMPLE_R := Vector2(0.4, -0.1)
const _BASE_EYE_C_L := Vector2(-0.2, 0.0)
const _BASE_EYE_C_R := Vector2(0.2, 0.0)
const _BASE_CHEEK_L := Vector2(-0.35, 0.1)
const _BASE_CHEEK_R := Vector2(0.35, 0.1)
const _BASE_NOSE_ROOT := Vector2(0.0, 0.05)
const _BASE_NOSE_TIP := Vector2(0.0, 0.15)
const _BASE_NOSE_BASE := Vector2(0.0, 0.191)
const _BASE_MOUTH_L := Vector2(-0.15, 0.309)
const _BASE_MOUTH_C := Vector2(0.0, 0.309)
const _BASE_MOUTH_R := Vector2(0.15, 0.309)
const _BASE_JAW_L := Vector2(-0.3, 0.36)
const _BASE_JAW_R := Vector2(0.3, 0.36)
const _BASE_CHIN := Vector2(0.0, 0.5)
const _BASE_EAR_L := Vector2(-0.45, 0.0)
const _BASE_EAR_R := Vector2(0.45, 0.0)
const _BASE_NECK_L := Vector2(-0.15, 0.55)
const _BASE_NECK_R := Vector2(0.15, 0.55)

const _OUTLINE_COUNT := 24


static func solve(g: FaceGenome, lod: int) -> FaceLandmarks:
	var lm := FaceLandmarks.new()
	
	# Step 1: Start from baseline
	var scale_x = lerp(0.7, 1.3, g.cranium_width)
	var scale_y = lerp(0.8, 1.25, g.cranium_height)
	
	# Apply skull deformations to all points
	lm.crown = _deform_point(_BASE_CROWN, scale_x, scale_y, g)
	lm.hairline = _deform_point(_BASE_HAIRLINE, scale_x, scale_y, g)
	lm.brow_l = _deform_point(_BASE_BROW_L, scale_x, scale_y, g)
	lm.brow_c = _deform_point(_BASE_BROW_C, scale_x, scale_y, g)
	lm.brow_r = _deform_point(_BASE_BROW_R, scale_x, scale_y, g)
	lm.temple_l = _deform_point(_BASE_TEMPLE_L, scale_x, scale_y, g)
	lm.temple_r = _deform_point(_BASE_TEMPLE_R, scale_x, scale_y, g)
	lm.eye_c_l = _deform_point(_BASE_EYE_C_L, scale_x, scale_y, g)
	lm.eye_c_r = _deform_point(_BASE_EYE_C_R, scale_x, scale_y, g)
	lm.cheek_l = _deform_point(_BASE_CHEEK_L, scale_x, scale_y, g)
	lm.cheek_r = _deform_point(_BASE_CHEEK_R, scale_x, scale_y, g)
	lm.nose_root = _deform_point(_BASE_NOSE_ROOT, scale_x, scale_y, g)
	lm.nose_tip = _deform_point(_BASE_NOSE_TIP, scale_x, scale_y, g)
	lm.nose_base = _deform_point(_BASE_NOSE_BASE, scale_x, scale_y, g)
	lm.mouth_l = _deform_point(_BASE_MOUTH_L, scale_x, scale_y, g)
	lm.mouth_c = _deform_point(_BASE_MOUTH_C, scale_x, scale_y, g)
	lm.mouth_r = _deform_point(_BASE_MOUTH_R, scale_x, scale_y, g)
	lm.jaw_l = _deform_point(_BASE_JAW_L, scale_x, scale_y, g)
	lm.jaw_r = _deform_point(_BASE_JAW_R, scale_x, scale_y, g)
	lm.chin = _deform_point(_BASE_CHIN, scale_x, scale_y, g)
	lm.ear_l = _deform_point(_BASE_EAR_L, scale_x, scale_y, g)
	lm.ear_r = _deform_point(_BASE_EAR_R, scale_x, scale_y, g)
	lm.neck_l = _deform_point(_BASE_NECK_L, scale_x, scale_y, g)
	lm.neck_r = _deform_point(_BASE_NECK_R, scale_x, scale_y, g)
	
	# Step 2: Apply specific skull field deformations
	# chin.y offset by jaw_length
	lm.chin.y += (g.jaw_length - 0.5) * 0.15
	
	# temple_pinch: pull temples inward
	var pinch := (g.temple_pinch - 0.5) * 0.15
	lm.temple_l.x += pinch
	lm.temple_r.x -= pinch
	
	# brow_ridge: push brow down-forward
	var ridge := (g.brow_ridge - 0.5) * 0.12
	lm.brow_l.y += ridge
	lm.brow_c.y += ridge
	lm.brow_r.y += ridge
	
	# chin_taper: narrow the chin
	var taper = lerp(0.7, 1.0, g.chin_taper)
	lm.jaw_l.x *= taper
	lm.jaw_r.x *= taper
	
	# chin_point: pull chin down
	lm.chin.y += (g.chin_point - 0.5) * 0.08
	
	# cheek_prominence: push cheeks outward
	var cheek := (g.cheek_prominence - 0.5) * 0.1
	lm.cheek_l.x -= cheek
	lm.cheek_r.x += cheek
	
	# jaw_width and jaw_length
	var jaw_w = lerp(0.8, 1.2, g.jaw_width)
	lm.jaw_l.x *= jaw_w
	lm.jaw_r.x *= jaw_w
	lm.jaw_l.y += (g.jaw_length - 0.5) * 0.1
	lm.jaw_r.y += (g.jaw_length - 0.5) * 0.1
	
	# occipital_extend: push crown backward (up in 2D)
	lm.crown.y -= (g.occipital_extend - 0.5) * 0.08
	
	# neck_width
	var neck_w = lerp(0.8, 1.2, g.neck_width)
	lm.neck_l.x *= neck_w
	lm.neck_r.x *= neck_w
	
	# Step 3: Apply skull_asymmetry
	lm.mirror_axis_x = (g.skull_asymmetry - 0.5) * 0.06
	var asym_scale := 1.0 + (g.skull_asymmetry - 0.5) * 0.1
	# Scale right half
	for field_name in ["brow_r", "temple_r", "eye_c_r", "cheek_r", "jaw_r", "ear_r", "neck_r", "mouth_r"]:
		var pt: Vector2 = lm.get_point(field_name)
		pt.x = lm.mirror_axis_x + (pt.x - lm.mirror_axis_x) * asym_scale
		lm.set(field_name, pt)
	
	# Step 4: Place eyes based on symmetry mode
	_place_eyes(lm, g)
	
	# Step 5: Build outline ring (24 points)
	lm.outline = _build_outline(lm, g, lod)
	
	return lm


static func _deform_point(base: Vector2, sx: float, sy: float, g: FaceGenome) -> Vector2:
	return Vector2(base.x * sx, base.y * sy)


static func _place_eyes(lm: FaceLandmarks, g: FaceGenome) -> void:
	var spacing = lerp(0.6, 1.0, g.eye_spacing) * 0.4
	var eye_y = (g.eye_line_height - 0.5) * 0.1
	
	match g.symmetry_mode:
		FaceEnums.SymmetryMode.BILATERAL:
			lm.eye_c_l = Vector2(lm.mirror_axis_x - spacing, eye_y)
			lm.eye_c_r = Vector2(lm.mirror_axis_x + spacing, eye_y)
		FaceEnums.SymmetryMode.RADIAL:
			lm.eye_c_l = Vector2(lm.mirror_axis_x - spacing, eye_y)
			lm.eye_c_r = Vector2(lm.mirror_axis_x + spacing, eye_y)
			# Place extra eyes in a circle
			lm._extra_eyes.clear()
			var extra_count := g.radial_count - 2
			var radius = spacing * 0.8
			for i in range(extra_count):
				var angle := TAU * (i + 1) / (extra_count + 2) - PI / 2.0
				lm._extra_eyes.append(Vector2(
					lm.mirror_axis_x + cos(angle) * radius,
					eye_y + sin(angle) * radius
				))
		FaceEnums.SymmetryMode.ASYMMETRIC:
			var jitter := g.asymmetry_amount * 0.08
			var rng := RandomNumberGenerator.new()
			rng.seed = g.seed + 1000
			lm.eye_c_l = Vector2(lm.mirror_axis_x - spacing + rng.randf_range(-jitter, jitter),
				eye_y + rng.randf_range(-jitter, jitter))
			lm.eye_c_r = Vector2(lm.mirror_axis_x + spacing + rng.randf_range(-jitter, jitter),
				eye_y + rng.randf_range(-jitter, jitter))
			# Extra asymmetric eyes
			lm._extra_eyes.clear()
			var extra_count2 := g.eye_count - 2
			for i in range(maxi(0, extra_count2)):
				lm._extra_eyes.append(Vector2(
					lm.mirror_axis_x + rng.randf_range(-0.3, 0.3),
					eye_y + rng.randf_range(-0.2, 0.2)
				))


static func _build_outline(lm: FaceLandmarks, g: FaceGenome, lod: int) -> PackedVector2Array:
	# Build the outline path: crown → temple_r → cheek_r → jaw_r → chin → jaw_l → cheek_l → temple_l → crown
	var path_points: Array[Vector2] = [
		lm.crown,
		lm.temple_r,
		lm.cheek_r,
		lm.jaw_r,
		lm.chin,
		lm.jaw_l,
		lm.cheek_l,
		lm.temple_l,
		lm.crown  # close the loop
	]
	
	# Sample the path with enough resolution then resample to exactly 24 points
	var total_length := 0.0
	var seg_lengths: Array[float] = []
	for i in range(path_points.size() - 1):
		var seg_len := path_points[i].distance_to(path_points[i + 1])
		seg_lengths.append(seg_len)
		total_length += seg_len
	
	var outline := PackedVector2Array()
	if total_length < 0.001:
		# Degenerate case: generate a circle
		for i in range(_OUTLINE_COUNT):
			var angle := TAU * i / _OUTLINE_COUNT
			outline.append(Vector2(cos(angle) * 0.3, sin(angle) * 0.3))
		return outline
	
	# Walk the path and place 24 evenly spaced points
	for i in range(_OUTLINE_COUNT):
		var target_dist := total_length * i / _OUTLINE_COUNT
		var accumulated := 0.0
		for seg in range(seg_lengths.size()):
			if accumulated + seg_lengths[seg] >= target_dist or seg == seg_lengths.size() - 1:
				var seg_frac := 0.0
				if seg_lengths[seg] > 0.0001:
					seg_frac = (target_dist - accumulated) / seg_lengths[seg]
				else:
					seg_frac = 0.0
				var p := path_points[seg].lerp(path_points[seg + 1], clampf(seg_frac, 0.0, 1.0))
				outline.append(p)
				break
			accumulated += seg_lengths[seg]
	
	assert(outline.size() == _OUTLINE_COUNT, "Outline must have exactly 24 points, got %d" % outline.size())
	return outline
