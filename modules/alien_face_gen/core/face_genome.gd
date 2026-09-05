class_name FaceGenome extends Resource

# Identity
@export var species_id: StringName = &""
@export var seed: int = 0
@export var age: float = 0.5
@export var dimorph_axis: float = 0.5
@export var condition: int = FaceEnums.Condition.HEALTHY

# Skull (13)
@export var cranium_width: float = 0.5
@export var cranium_height: float = 0.5
@export var cranium_bulge: float = 0.5
@export var brow_ridge: float = 0.5
@export var temple_pinch: float = 0.5
@export var jaw_width: float = 0.5
@export var jaw_length: float = 0.5
@export var chin_taper: float = 0.5
@export var chin_point: float = 0.5
@export var cheek_prominence: float = 0.5
@export var occipital_extend: float = 0.5
@export var neck_width: float = 0.5
@export var skull_asymmetry: float = 0.5

# Eyes (14)
@export var eye_present: bool = true
@export var eye_count: int = 2
@export var eye_rows: int = 1
@export var eye_size: float = 0.5
@export var eye_spacing: float = 0.5
@export var eye_line_height: float = 0.5
@export var eye_tilt: float = 0.5
@export var eye_shape: int = FaceEnums.EyeShape.ROUND
@export var pupil_shape: int = FaceEnums.PupilShape.ROUND
@export var pupil_size: float = 0.5
@export var iris_ratio: float = 0.5
@export var lid_upper: float = 0.5
@export var lid_lower: float = 0.5
@export var eye_glow: float = 0.5

# Nose (6)
@export var nose_present: bool = true
@export var nose_type: int = FaceEnums.NoseType.HUMAN
@export var nose_length: float = 0.5
@export var nose_width: float = 0.5
@export var nose_bridge: float = 0.5
@export var nostril_flare: float = 0.5

# Mouth (10)
@export var mouth_present: bool = true
@export var mouth_type: int = FaceEnums.MouthType.LIPS
@export var mouth_width: float = 0.5
@export var mouth_height: float = 0.5
@export var mouth_curve: float = 0.5
@export var lip_thickness: float = 0.5
@export var teeth_amount: float = 0.5
@export var mandible_count: int = 0
@export var mandible_length: float = 0.5
@export var tongue_amount: float = 0.5

# Brow / Ear (7)
@export var brow_present: bool = true
@export var brow_thickness: float = 0.5
@export var brow_angle: float = 0.5
@export var ear_present: bool = true
@export var ear_type: int = FaceEnums.EarType.NONE
@export var ear_size: float = 0.5
@export var ear_angle: float = 0.5
@export var ear_height: float = 0.5

# Crest (6)
@export var crest_present: bool = true
@export var crest_type: int = FaceEnums.CrestType.NONE
@export var crest_count: int = 0
@export var crest_length: float = 0.5
@export var crest_spread: float = 0.5
@export var crest_curve: float = 0.5
@export var crest_thickness: float = 0.5

# Surface (8)
@export var skin_texture: int = FaceEnums.SkinTexture.SMOOTH
@export var marking_type: int = FaceEnums.MarkingType.NONE
@export var marking_count: int = 0
@export var marking_coverage: float = 0.5
@export var marking_symmetry: float = 0.5
@export var plate_seams: float = 0.5
@export var wrinkle_amount: float = 0.5
@export var scar_count: int = 0

# Gear (5)
@export var collar_type: int = FaceEnums.CollarType.NONE
@export var collar_height: float = 0.5
@export var headgear_type: int = FaceEnums.HeadgearType.NONE
@export var ocular_gear: int = FaceEnums.OcularGear.NONE
@export var gear_bulk: float = 0.5

# Colour (6)
@export var palette_id: StringName = &""
@export var hue_shift: float = 0.5
@export var sat_scale: float = 0.5
@export var val_scale: float = 0.5
@export var marking_hue: float = 0.5
@export var emissive_amount: float = 0.5

# Global (3)
@export var symmetry_mode: int = FaceEnums.SymmetryMode.BILATERAL
@export var radial_count: int = 3
@export var asymmetry_amount: float = 0.5


func to_dict() -> Dictionary:
	var d := {}
	d["age"] = age
	d["asymmetry_amount"] = asymmetry_amount
	d["brow_angle"] = brow_angle
	d["brow_present"] = brow_present
	d["brow_thickness"] = brow_thickness
	d["chin_point"] = chin_point
	d["chin_taper"] = chin_taper
	d["cheek_prominence"] = cheek_prominence
	d["collar_height"] = collar_height
	d["collar_type"] = collar_type
	d["condition"] = condition
	d["cranium_bulge"] = cranium_bulge
	d["cranium_height"] = cranium_height
	d["cranium_width"] = cranium_width
	d["crest_count"] = crest_count
	d["crest_curve"] = crest_curve
	d["crest_length"] = crest_length
	d["crest_present"] = crest_present
	d["crest_spread"] = crest_spread
	d["crest_thickness"] = crest_thickness
	d["crest_type"] = crest_type
	d["dimorph_axis"] = dimorph_axis
	d["ear_angle"] = ear_angle
	d["ear_height"] = ear_height
	d["ear_present"] = ear_present
	d["ear_size"] = ear_size
	d["ear_type"] = ear_type
	d["emissive_amount"] = emissive_amount
	d["eye_count"] = eye_count
	d["eye_glow"] = eye_glow
	d["eye_line_height"] = eye_line_height
	d["eye_present"] = eye_present
	d["eye_rows"] = eye_rows
	d["eye_shape"] = eye_shape
	d["eye_size"] = eye_size
	d["eye_spacing"] = eye_spacing
	d["eye_tilt"] = eye_tilt
	d["gear_bulk"] = gear_bulk
	d["headgear_type"] = headgear_type
	d["hue_shift"] = hue_shift
	d["iris_ratio"] = iris_ratio
	d["jaw_length"] = jaw_length
	d["jaw_width"] = jaw_width
	d["lid_lower"] = lid_lower
	d["lid_upper"] = lid_upper
	d["lip_thickness"] = lip_thickness
	d["mandible_count"] = mandible_count
	d["mandible_length"] = mandible_length
	d["marking_count"] = marking_count
	d["marking_coverage"] = marking_coverage
	d["marking_hue"] = marking_hue
	d["marking_symmetry"] = marking_symmetry
	d["marking_type"] = marking_type
	d["mouth_curve"] = mouth_curve
	d["mouth_height"] = mouth_height
	d["mouth_present"] = mouth_present
	d["mouth_type"] = mouth_type
	d["mouth_width"] = mouth_width
	d["neck_width"] = neck_width
	d["nostril_flare"] = nostril_flare
	d["nose_bridge"] = nose_bridge
	d["nose_length"] = nose_length
	d["nose_present"] = nose_present
	d["nose_type"] = nose_type
	d["nose_width"] = nose_width
	d["occipital_extend"] = occipital_extend
	d["ocular_gear"] = ocular_gear
	d["palette_id"] = String(palette_id)
	d["plate_seams"] = plate_seams
	d["pupil_shape"] = pupil_shape
	d["pupil_size"] = pupil_size
	d["radial_count"] = radial_count
	d["scar_count"] = scar_count
	d["seed"] = seed
	d["skin_texture"] = skin_texture
	d["skull_asymmetry"] = skull_asymmetry
	d["species_id"] = String(species_id)
	d["sat_scale"] = sat_scale
	d["symmetry_mode"] = symmetry_mode
	d["temple_pinch"] = temple_pinch
	d["teeth_amount"] = teeth_amount
	d["tongue_amount"] = tongue_amount
	d["val_scale"] = val_scale
	d["wrinkle_amount"] = wrinkle_amount
	return d


func fingerprint() -> String:
	return str(to_dict()).sha256_text()
