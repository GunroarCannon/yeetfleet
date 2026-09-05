class_name FaceExpression

# Expression states as sparse genome-field deltas
const EXPRESSIONS: Dictionary = {
	&"neutral": {},
	&"happy": {
		"brow_angle": 0.10, "mouth_curve": 0.20, "mouth_width": 0.05,
		"lid_lower": -0.10, "cheek_prominence": 0.10
	},
	&"angry": {
		"brow_angle": -0.30, "lid_upper": 0.20, "mouth_curve": -0.35,
		"mouth_width": -0.10, "crest_spread": -0.25
	},
	&"sad": {
		"brow_angle": 0.15, "mouth_curve": 0.15, "lid_upper": 0.10,
		"lid_lower": 0.10, "eye_tilt": -0.10
	},
	&"surprised": {
		"lid_upper": -0.20, "mouth_height": 0.20, "brow_angle": 0.20,
		"eye_size": 0.10, "mouth_width": 0.10
	},
	&"suspicious": {
		"lid_upper": 0.15, "eye_tilt": 0.15, "mouth_curve": -0.10,
		"brow_angle": -0.10
	},
	&"talking_a": {
		"mouth_height": 0.15, "mouth_width": 0.05
	},
	&"talking_b": {
		"mouth_height": 0.25, "mouth_width": -0.05, "lip_thickness": 0.10
	},
	&"talking_c": {
		"mouth_height": 0.10, "mouth_width": 0.10, "mouth_curve": 0.10
	}
}

# Compensation chains for missing features
const _COMPENSATION := {
	"mouth": ["lid_upper", "lid_lower", "crest_spread", "jaw_length", "eye_glow"],
	"brow": ["lid_upper", "eye_tilt", "crest_curve", "eye_glow"],
	"eye": ["crest", "mouth_curve", "eye_glow"],
}

# Fallback for UMBRAL (no mouth, no brow, no crest)
const _UMBRAL_COMPENSATION := ["eye_glow", "eye_tilt"]


static func apply(g: FaceGenome, state: StringName) -> FaceGenome:
	if state == &"neutral" or not EXPRESSIONS.has(state):
		return g.duplicate()
	
	var delta: Dictionary = EXPRESSIONS[state]
	var result := g.duplicate()
	
	for field in delta:
		var d: float = delta[field]
		var current = result.get(field)
		if current is float:
			var new_val = current + d
			result.set(field, clampf(new_val, 0.0, 1.0))
		elif current is int:
			# Don't modify int fields from expressions
			pass
	
	# Apply compensation for missing features
	_redistribute(result, g)
	
	return result


static func _redistribute(g: FaceGenome, original: FaceGenome) -> void:
	var species: SpeciesDef = null
	# Try to load the species definition
	var path := "res://modules/alien_face_gen/data/species/" + String(g.species_id).to_lower() + ".tres"
	var s = load(path)
	if s is SpeciesDef:
		species = s
	
	# Check each compensation chain
	for missing_slot in _COMPENSATION:
		var slot_present := true
		match missing_slot:
			"mouth": slot_present = g.mouth_present
			"brow": slot_present = g.brow_present
			"eye": slot_present = g.eye_present
		
		if not slot_present:
			# Find the first present slot in the chain
			var chain: Array = _COMPENSATION[missing_slot]
			for fallback_field in chain:
				# Check if this field exists on the genome
				var current = g.get(fallback_field)
				if current != null:
					# Apply a small delta to the fallback
					if fallback_field == "eye_glow":
						g.eye_glow = clampf(g.eye_glow + 0.15, 0.0, 1.0)
					elif fallback_field == "eye_tilt":
						g.eye_tilt = clampf(g.eye_tilt + 0.10, 0.0, 1.0)
					elif fallback_field == "lid_upper":
						g.lid_upper = clampf(g.lid_upper + 0.10, 0.0, 1.0)
					elif fallback_field == "lid_lower":
						g.lid_lower = clampf(g.lid_lower + 0.10, 0.0, 1.0)
					elif fallback_field == "crest_spread":
						g.crest_spread = clampf(g.crest_spread + 0.10, 0.0, 1.0)
					elif fallback_field == "crest_curve":
						g.crest_curve = clampf(g.crest_curve + 0.10, 0.0, 1.0)
					elif fallback_field == "jaw_length":
						g.jaw_length = clampf(g.jaw_length + 0.10, 0.0, 1.0)
					break
	
	# UMBRAL special case: eye_glow is terminal fallback for everything
	if not g.mouth_present and not g.brow_present:
		# Check if crest is also absent
		if g.crest_type == FaceEnums.CrestType.NONE or g.crest_count <= 0:
			# Apply to eye_glow and eye_tilt
			g.eye_glow = clampf(g.eye_glow + 0.10, 0.0, 1.0)
			g.eye_tilt = clampf(g.eye_tilt + 0.05, 0.0, 1.0)


static func talking_cycle(g: FaceGenome, phase: int) -> FaceGenome:
	# Cycle through neutral → a → b → c → a …
	match phase % 4:
		1: return apply(g, &"talking_a")
		2: return apply(g, &"talking_b")
		3: return apply(g, &"talking_c")
		_: return g.duplicate()
