class_name StylePixelArt extends StyleBase2D

# Internal pixel resolution by LOD
const _INTERNAL_RES := [64, 48, 32, 16]

# 20-colour ramp: 17 palette slots + 3 interpolated steps
const _RAMP_STEPS := 20


func style_id() -> StringName:
	return &"pixel_art"


func silhouette_defining_slots() -> Array[StringName]:
	return [&"head_shell", &"crest", &"ear_l", &"ear_r"]


func background(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	# Full-frame rect in background colour
	dl.poly(PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)
	]), p.background, 0, &"bg_block")


func draw_feature(slot: StringName, dl: DrawList, g: FaceGenome, lm: FaceLandmarks,
		p: FacePalette, lod: int) -> void:
	# Delegate to FlatVector then snap all points to the pixel grid
	var flat := StyleFlatVector.new()
	flat.draw_feature(slot, dl, g, lm, p, lod)
	
	# Snap all recently-added commands to the pixel grid
	var pixel_size = 1.0 / _INTERNAL_RES[clampi(lod, 0, 3)]
	var start_idx := maxi(0, dl.cmds.size() - 20)  # Approximate
	for i in range(start_idx, dl.cmds.size()):
		var cmd := dl.cmds[i]
		if cmd["slot"] == slot:
			var snapped_pts := PackedVector2Array()
			for pt in cmd["points"]:
				snapped_pts.append(Vector2(
					 snappedf(pt.x, pixel_size),
					 snappedf(pt.y, pixel_size)
				))
			cmd["points"] = snapped_pts
			# Quantise colour to 20-entry ramp
			cmd["color"] = _quantise_color(cmd["color"], p)
			dl.cmds[i] = cmd


func post(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	pass


func _quantise_color(c: Color, p: FacePalette) -> Color:
	# Build the 20-colour ramp from palette
	var ramp: Array[Color] = p.get_all_colors()
	
	# Add 3 interpolated steps between skin_base, skin_shade, skin_light
	ramp.append(p.skin_base.lerp(p.skin_shade, 0.33))
	ramp.append(p.skin_base.lerp(p.skin_shade, 0.66))
	ramp.append(p.skin_base.lerp(p.skin_light, 0.5))
	
	# Find nearest colour in the ramp
	var best_dist := INF
	var best_col := c
	for rc in ramp:
		var dr := c.r - rc.r
		var dg := c.g - rc.g
		var db := c.b - rc.b
		var dist := dr * dr + dg * dg + db * db
		if dist < best_dist:
			best_dist = dist
			best_col = rc
	return Color(best_col.r, best_col.g, best_col.b, c.a)
