class_name Face2DRenderer

# Canonical z-order for all slots
const Z_ORDER: Array[StringName] = [
	&"bg_block", &"collar", &"neck", &"head_shell", &"head_shade", &"cheek",
	&"ear_l", &"ear_r", &"brow_l", &"brow_r", &"eye_socket",
	&"eye_sclera", &"eye_iris", &"eye_pupil", &"nose", &"mouth",
	&"mandible", &"marking", &"crest", &"headgear", &"ocular_gear", &"outline_pass"
]

# Style registry
const STYLES_2D: Dictionary = {}


static func get_style(style_id: StringName) -> StyleBase2D:
	match style_id:
		&"flat_vector": return StyleFlatVector.new()
		&"pixel_art": return StylePixelArt.new()
		&"ink_outline": return StyleInkOutline.new()
		_: return StyleFlatVector.new()


static func render(g: FaceGenome, lm: FaceLandmarks, p: FacePalette,
		style: StyleBase2D, lod: int, expression: StringName = &"neutral") -> DrawList:
	var dl := DrawList.new()
	var culled := Lod.culled_slots(lod)
	var silhouette := style.silhouette_defining_slots()
	
	# Apply expression to genome (creates a copy)
	var eg = FaceExpression.apply(g, expression)
	
	# Re-solve landmarks with the expressed genome
	var el := LandmarkSolver.solve(eg, lod)
	
	# Background first
	style.background(dl, eg, p, lod)
	
	# Draw features in canonical z-order
	for slot in Z_ORDER:
		# Skip culled slots unless silhouette-defining
		if slot in culled and slot not in silhouette:
			continue
		style.draw_feature(slot, dl, eg, el, p, lod)
	
	# Post-processing
	style.post(dl, eg, p, lod)
	
	# Sort by z
	dl.sort_z()
	
	return dl
