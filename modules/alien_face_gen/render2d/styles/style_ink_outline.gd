class_name StyleInkOutline extends StyleBase2D

# Stroke width by LOD: [3,2,1,1] px
const _STROKE_WIDTHS := [3.0, 2.0, 1.0, 1.0]


func style_id() -> StringName:
	return &"ink_outline"


func silhouette_defining_slots() -> Array[StringName]:
	return [&"head_shell", &"crest", &"ear_l", &"ear_r"]


func background(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	dl.poly(PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)
	]), p.background, 0, &"bg_block")


func draw_feature(slot: StringName, dl: DrawList, g: FaceGenome, lm: FaceLandmarks,
		p: FacePalette, lod: int) -> void:
	# Draw the flat fill first (delegating to FlatVector)
	var flat := StyleFlatVector.new()
	var before := dl.cmds.size()
	flat.draw_feature(slot, dl, g, lm, p, lod)
	
	# Then add a matching outline stroke for every poly command
	var stroke_w: float = _STROKE_WIDTHS[clampi(lod, 0, 3)] * 0.001
	var outline_col := p.outline
	if outline_col.a <= 0.0:
		outline_col = Color(0, 0, 0, 1)  # Default black outline
	
	for i in range(before, dl.cmds.size()):
		var cmd := dl.cmds[i]
		if cmd["type"] == &"poly" and cmd["points"].size() >= 3:
			var pts = cmd["points"].duplicate()
			pts.append(pts[0])  # Close the loop
			# Label the stroke with the poly's own slot, not the outer slot it was
			# drawn under: FlatVector draws e.g. a pupil poly while handling the
			# eye_sclera slot, so consumers must be able to find an outline for it.
			dl.line(pts, outline_col, stroke_w, cmd["z"] + 1, cmd["slot"])


func post(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	# Add hatching for skin_shade at LOD 0 only
	if lod > Lod.LOD_CINEMATIC:
		return
	
	# Find skin_shade polys and add cross-hatching
	for cmd in dl.cmds:
		if cmd["type"] == &"poly" and cmd["slot"] == &"head_shade":
			var bounds := Rect2()
			for pt in cmd["points"]:
				bounds = bounds.expand(pt)
			# Draw horizontal hatch lines
			var hatch_col := Color(p.skin_deep.r, p.skin_deep.g, p.skin_deep.b, 0.3)
			var step := 0.015
			var y := bounds.position.y + step
			while y < bounds.position.y + bounds.size.y:
				dl.line(PackedVector2Array([
					Vector2(bounds.position.x, y),
					Vector2(bounds.position.x + bounds.size.x, y)
				]), hatch_col, 0.0005, cmd["z"] + 2, &"hatch")
				y += step
