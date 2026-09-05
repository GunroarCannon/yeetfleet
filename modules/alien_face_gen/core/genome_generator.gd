class_name GenomeGenerator

const DEFAULT_RANGE := Vector2(0.25, 0.75)

const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"

static var _cache: Dictionary = {}  # species_id -> SpeciesDef

# LATTICE post-process: quantise skull fields to 0.25
static var _POST_PROCESS = {
	&"LATTICE": func(g: FaceGenome) -> void:
		var skull_fields := [
			"cranium_width", "cranium_height", "cranium_bulge", "brow_ridge",
			"temple_pinch", "jaw_width", "jaw_length", "chin_taper", "chin_point",
			"cheek_prominence", "occipital_extend", "neck_width", "skull_asymmetry"
		]
		for field in skull_fields:
			var v: float = g.get(field)
			g.set(field, snappedf(v, 0.25))
}


static func generate(species: SpeciesDef, seed_value: int) -> FaceGenome:
	var rng := FaceRNG.new(species.id, seed_value)
	var g := FaceGenome.new()
	g.species_id = species.id
	g.seed = seed_value
	
	# Set symmetry mode and radial count from species
	g.symmetry_mode = species.symmetry_mode
	g.radial_count = species.radial_count
	
	# Roll continuous skull fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.SKULL, [
		"age", "dimorph_axis",
		"cranium_width", "cranium_height", "cranium_bulge", "brow_ridge",
		"temple_pinch", "jaw_width", "jaw_length", "chin_taper", "chin_point",
		"cheek_prominence", "occipital_extend", "neck_width", "skull_asymmetry"
	], species)
	
	# Roll continuous eye fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.EYES, [
		"eye_size", "eye_spacing", "eye_line_height", "eye_tilt",
		"pupil_size", "iris_ratio", "lid_upper", "lid_lower", "eye_glow"
	], species)
	
	# Roll eye integer fields
	var eye_r := rng.stream(FaceRNG.Stream.EYES)
	g.eye_count = _roll_int_field(eye_r, "eye_count", species, 2, 1, 8)
	g.eye_rows = _roll_int_field(eye_r, "eye_rows", species, 1, 1, 3)
	
	# Roll eye enums
	g.eye_shape = _roll_enum_field(eye_r, "eye_shape", species, EyeShapeWeights, FaceEnums.EyeShape.size())
	g.pupil_shape = _roll_enum_field(eye_r, "pupil_shape", species, PupilShapeWeights, FaceEnums.PupilShape.size())
	
	# Roll continuous nose fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.NOSE, [
		"nose_length", "nose_width", "nose_bridge", "nostril_flare"
	], species)
	var nose_r := rng.stream(FaceRNG.Stream.NOSE)
	g.nose_type = _roll_enum_field(nose_r, "nose_type", species, NoseTypeWeights, FaceEnums.NoseType.size())
	
	# Roll continuous mouth fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.MOUTH, [
		"mouth_width", "mouth_height", "mouth_curve", "lip_thickness",
		"teeth_amount", "mandible_length", "tongue_amount"
	], species)
	var mouth_r := rng.stream(FaceRNG.Stream.MOUTH)
	g.mouth_type = _roll_enum_field(mouth_r, "mouth_type", species, MouthTypeWeights, FaceEnums.MouthType.size())
	g.mandible_count = _roll_int_field(mouth_r, "mandible_count", species, 0, 0, 4)
	
	# Roll brow/ear fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.BROW_EAR, [
		"brow_thickness", "brow_angle", "ear_size", "ear_angle", "ear_height"
	], species)
	var brow_r := rng.stream(FaceRNG.Stream.BROW_EAR)
	g.ear_type = _roll_enum_field(brow_r, "ear_type", species, EarTypeWeights, FaceEnums.EarType.size())
	
	# Roll crest fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.CREST, [
		"crest_length", "crest_spread", "crest_curve", "crest_thickness"
	], species)
	var crest_r := rng.stream(FaceRNG.Stream.CREST)
	g.crest_type = _roll_enum_field(crest_r, "crest_type", species, CrestTypeWeights, FaceEnums.CrestType.size())
	g.crest_count = _roll_int_field(crest_r, "crest_count", species, 0, 0, 12)
	
	# Roll surface fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.SURFACE, [
		"marking_coverage", "marking_symmetry", "plate_seams", "wrinkle_amount"
	], species)
	var surface_r := rng.stream(FaceRNG.Stream.SURFACE)
	g.skin_texture = _roll_enum_field(surface_r, "skin_texture", species, SkinTextureWeights, FaceEnums.SkinTexture.size())
	g.marking_type = _roll_enum_field(surface_r, "marking_type", species, MarkingTypeWeights, FaceEnums.MarkingType.size())
	g.marking_count = _roll_int_field(surface_r, "marking_count", species, 0, 0, 8)
	g.scar_count = _roll_int_field(surface_r, "scar_count", species, 0, 0, 5)
	
	# Roll gear fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.GEAR, [
		"collar_height", "gear_bulk"
	], species)
	var gear_r := rng.stream(FaceRNG.Stream.GEAR)
	g.collar_type = _roll_enum_field(gear_r, "collar_type", species, CollarTypeWeights, FaceEnums.CollarType.size())
	g.headgear_type = _roll_enum_field(gear_r, "headgear_type", species, HeadgearTypeWeights, FaceEnums.HeadgearType.size())
	g.ocular_gear = _roll_enum_field(gear_r, "ocular_gear", species, OcularGearWeights, FaceEnums.OcularGear.size())
	
	# Roll colour fields
	_roll_continuous_group(g, rng, FaceRNG.Stream.COLOR, [
		"hue_shift", "sat_scale", "val_scale", "marking_hue", "emissive_amount"
	], species)
	
	# Roll global fields
	var global_r := rng.stream(FaceRNG.Stream.GLOBAL)
	g.condition = _roll_enum_field(global_r, "condition", species, ConditionWeights, FaceEnums.Condition.size())
	g.asymmetry_amount = _roll_continuous_in_range(global_r, species, "asymmetry_amount")
	
	# Resolve palette
	if species.allowed_palettes.size() > 0:
		var idx := global_r.randi_range(0, species.allowed_palettes.size() - 1)
		g.palette_id = species.allowed_palettes[idx]
	
	# Resolve presence rules
	_resolve_presence(g, species, rng)
	
	# Apply post-process hooks
	if _POST_PROCESS.has(species.id):
		_POST_PROCESS[species.id].call(g)
	
	return g


static func _roll_continuous_group(g: FaceGenome, rng: FaceRNG, stream: int, fields: Array, species: SpeciesDef) -> void:
	var r := rng.stream(stream)
	for field_name in fields:
		g.set(field_name, _roll_continuous_in_range(r, species, field_name))


static func _roll_continuous_in_range(r: RandomNumberGenerator, species: SpeciesDef, field_name: String) -> float:
	var range: Vector2 = species.ranges.get(field_name, DEFAULT_RANGE)
	return r.randf_range(range.x, range.y)


static func _roll_int_field(r: RandomNumberGenerator, field_name: String, species: SpeciesDef, default_val: int, min_val: int, max_val: int) -> int:
	var range: Vector2 = species.ranges.get(field_name, Vector2(default_val, default_val))
	var lo := maxi(min_val, int(range.x))
	var hi := maxi(lo, mini(max_val, int(range.y)))
	return r.randi_range(lo, hi)


static func _roll_enum_field(r: RandomNumberGenerator, field_name: String, species: SpeciesDef, default_weights: Dictionary, count: int) -> int:
	var weights: Dictionary = species.enum_weights.get(field_name, default_weights)
	if weights.is_empty():
		return r.randi_range(0, count - 1)
	var total := 0.0
	for v in weights.values():
		total += v
	if total <= 0.0:
		return r.randi_range(0, count - 1)
	var roll := r.randf() * total
	var cumulative := 0.0
	for v in weights:
		cumulative += weights[v]
		if roll <= cumulative:
			return int(v)
	return count - 1


static func _resolve_presence(g: FaceGenome, species: SpeciesDef, rng: FaceRNG) -> void:
	var global_r := rng.stream(FaceRNG.Stream.GLOBAL)
	
	# Eyes
	_resolve_feature_presence(g, species, global_r, "eye", [
		"eye_count", "eye_rows", "eye_size", "eye_spacing", "eye_line_height",
		"eye_tilt", "eye_shape", "pupil_shape", "pupil_size", "iris_ratio",
		"lid_upper", "lid_lower", "eye_glow"
	])
	g.eye_present = g.eye_count > 0 and species.presence.get("eye", FaceRNG.Stream.SKULL) != SpeciesDef.PRESENCE_FORBIDDEN
	
	# Nose
	_resolve_feature_presence(g, species, global_r, "nose", [
		"nose_type", "nose_length", "nose_width", "nose_bridge", "nostril_flare"
	])
	
	# Mouth
	_resolve_feature_presence(g, species, global_r, "mouth", [
		"mouth_type", "mouth_width", "mouth_height", "mouth_curve", "lip_thickness",
		"teeth_amount", "mandible_count", "mandible_length", "tongue_amount"
	])
	
	# Brow
	_resolve_feature_presence(g, species, global_r, "brow", [
		"brow_thickness", "brow_angle"
	])
	
	# Crest
	_resolve_feature_presence(g, species, global_r, "crest", [
		"crest_type", "crest_count", "crest_length", "crest_spread",
		"crest_curve", "crest_thickness"
	])
	
	# Ear
	_resolve_feature_presence(g, species, global_r, "ear", [
		"ear_type", "ear_size", "ear_angle", "ear_height"
	])


static func _resolve_feature_presence(g: FaceGenome, species: SpeciesDef, r: RandomNumberGenerator, slot: String, fields: Array) -> void:
	var rule = species.presence.get(slot, 1.0)  # default: present
	if rule == SpeciesDef.PRESENCE_FORBIDDEN:
		g.set(slot + "_present" if slot != "eye" else "eye_present", false)
		for field in fields:
			var current = g.get(field)
			if current is float:
				g.set(field, 0.0)
			elif current is int:
				g.set(field, 0)
			elif current is bool:
				g.set(field, false)
	elif rule == SpeciesDef.PRESENCE_REQUIRED:
		g.set(slot + "_present" if slot != "eye" else "eye_present", true)
	elif rule is float:
		var present = r.randf() < rule
		g.set(slot + "_present" if slot != "eye" else "eye_present", present)
		if not present:
			for field in fields:
				var current = g.get(field)
				if current is float:
					g.set(field, 0.0)
				elif current is int:
					g.set(field, 0)
				elif current is bool:
					g.set(field, false)
	else:
		g.set(slot + "_present" if slot != "eye" else "eye_present", true)


# Default enum weights (uniform distribution)
const EyeShapeWeights := {}
const PupilShapeWeights := {}
const NoseTypeWeights := {}
const MouthTypeWeights := {}
const EarTypeWeights := {}
const CrestTypeWeights := {}
const SkinTextureWeights := {}
const MarkingTypeWeights := {}
const CollarTypeWeights := {}
const HeadgearTypeWeights := {}
const OcularGearWeights := {}
const ConditionWeights := {}
