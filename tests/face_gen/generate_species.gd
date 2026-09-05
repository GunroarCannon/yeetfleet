# Run with: godot --headless --path . --script res://tests/face_gen/generate_species.gd
extends SceneTree

func _initialize() -> void:
	_create_species()
	quit(0)


func _create_species() -> void:
	# 1. VOID_GREY
	_save_species(_make_species(
		&"VOID_GREY", "Void Grey",
		{
			"cranium_width": Vector2(0.75, 0.95), "cranium_height": Vector2(0.7, 0.85),
			"jaw_width": Vector2(0.1, 0.25), "chin_taper": Vector2(0.8, 1.0),
			"eye_size": Vector2(0.75, 0.95), "eye_tilt": Vector2(0.6, 0.8)
		},
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN, "mandible": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.ALMOND: 1.0}, "pupil_shape": {FaceEnums.PupilShape.NONE: 1.0},
			"nose_type": {FaceEnums.NoseType.NONE: 1.0}, "mouth_type": {FaceEnums.MouthType.THIN: 1.0}},
		[&"void_grey", &"ash_husk"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.80, 0.75, 0.40]  # depth: crown, eye, chin
	))
	
	# 2. DRACONIAN
	_save_species(_make_species(
		&"DRACONIAN", "Draconian",
		{
			"brow_ridge": Vector2(0.7, 1.0), "jaw_length": Vector2(0.6, 0.85),
			"occipital_extend": Vector2(0.5, 0.8)
		},
		{},
		{"eye_shape": {FaceEnums.EyeShape.SLIT_V: 1.0}, "pupil_shape": {FaceEnums.PupilShape.SLIT_V: 1.0},
			"nose_type": {FaceEnums.NoseType.SNOUT: 1.0}, "mouth_type": {FaceEnums.MouthType.TUSKED: 1.0},
			"crest_type": {FaceEnums.CrestType.HORN: 0.5, FaceEnums.CrestType.SPINE: 0.5}},
		[&"desert_scale", &"plated_brute"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 3. MANTID
	_save_species(_make_species(
		&"MANTID", "Mantid",
		{
			"cranium_width": Vector2(0.3, 0.5), "chin_point": Vector2(0.8, 1.0),
			"temple_pinch": Vector2(0.1, 0.3), "eye_size": Vector2(0.8, 1.0),
			"eye_glow": Vector2(0.3, 0.6)
		},
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN, "mandible": SpeciesDef.PRESENCE_REQUIRED},
		{"eye_shape": {FaceEnums.EyeShape.COMPOUND: 1.0}, "pupil_shape": {FaceEnums.PupilShape.NONE: 1.0},
			"nose_type": {FaceEnums.NoseType.NONE: 1.0}, "mouth_type": {FaceEnums.MouthType.MANDIBLE: 1.0},
			"crest_type": {FaceEnums.CrestType.ANTENNA: 1.0}, "skin_texture": {FaceEnums.SkinTexture.CHITIN: 1.0}},
		[&"chitin_cold", &"deep_bio"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.45, 0.60, 0.35]
	))
	
	# 4. MUDOK
	_save_species(_make_species(
		&"MUDOK", "Mudok",
		{
			"cranium_height": Vector2(0.7, 0.9), "cranium_bulge": Vector2(0.6, 0.8),
			"jaw_width": Vector2(0.5, 0.7), "eye_spacing": Vector2(0.8, 1.0),
			"eye_glow": Vector2(0.2, 0.4)
		},
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.ROUND: 1.0}, "nose_type": {FaceEnums.NoseType.NONE: 1.0},
			"mouth_type": {FaceEnums.MouthType.STITCHED: 1.0},
			"crest_type": {FaceEnums.CrestType.TENDRIL: 1.0}, "skin_texture": {FaceEnums.SkinTexture.MEMBRANE: 1.0}},
		[&"amphib_moss", &"deep_bio"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 5. CEPHALID
	_save_species(_make_species(
		&"CEPHALID", "Cephalid",
		{
			"cranium_bulge": Vector2(0.85, 1.0), "jaw_length": Vector2(0.1, 0.25)
		},
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.HEX: 1.0}, "nose_type": {FaceEnums.NoseType.NONE: 1.0},
			"mouth_type": {FaceEnums.MouthType.BEAK: 1.0},
			"crest_type": {FaceEnums.CrestType.TENDRIL: 1.0},
			"marking_type": {FaceEnums.MarkingType.GRADIENT_BAND: 1.0}},
		[&"deep_bio", &"crystal_prism"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.45, 0.60, 0.35]
	))
	
	# 6. AVIARN
	_save_species(_make_species(
		&"AVIARN", "Aviarn",
		{
			"cranium_width": Vector2(0.35, 0.5), "occipital_extend": Vector2(0.6, 0.8),
			"eye_spacing": Vector2(0.85, 1.0), "lid_lower": Vector2(0.4, 0.6)
		},
		{"mouth": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.ROUND: 1.0}, "nose_type": {FaceEnums.NoseType.BEAK: 1.0},
			"mouth_type": {FaceEnums.MouthType.NONE: 1.0},
			"crest_type": {FaceEnums.CrestType.PLUME: 1.0}, "skin_texture": {FaceEnums.SkinTexture.FUR: 1.0}},
		[&"crystal_prism", &"fungal_bloom"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 7. LATTICE
	_save_species(_make_species(
		&"LATTICE", "Lattice",
		{},  # All skull params quantised to 0.25
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN, "mouth": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.TRIANGLE: 0.5, FaceEnums.EyeShape.HEX: 0.5},
			"nose_type": {FaceEnums.NoseType.NONE: 1.0}, "mouth_type": {FaceEnums.MouthType.NONE: 1.0},
			"crest_type": {FaceEnums.CrestType.SPINE: 1.0},
			"skin_texture": {FaceEnums.SkinTexture.CRYSTAL: 1.0},
			"marking_type": {FaceEnums.MarkingType.GLYPH: 1.0}},
		[&"crystal_prism", &"synth_alloy"], FaceEnums.SymmetryMode.RADIAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 8. SYNTH
	_save_species(_make_species(
		&"SYNTH", "Synth",
		{
			"jaw_width": Vector2(0.5, 0.7), "plate_seams": Vector2(0.8, 1.0),
			"skull_asymmetry": Vector2(0.49, 0.51)
		},
		{},
		{"eye_shape": {FaceEnums.EyeShape.HEX: 1.0}, "pupil_shape": {FaceEnums.PupilShape.NONE: 1.0},
			"eye_glow": Vector2(0.6, 0.9), "nose_type": {FaceEnums.NoseType.PLATE: 1.0},
			"mouth_type": {FaceEnums.MouthType.VENT: 1.0},
			"crest_type": {FaceEnums.CrestType.NONE: 1.0},
			"skin_texture": {FaceEnums.SkinTexture.PLATE: 1.0},
			"marking_type": {FaceEnums.MarkingType.CIRCUIT: 1.0}},
		[&"synth_alloy", &"void_grey"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 9. BRUTE
	_save_species(_make_species(
		&"BRUTE", "Brute",
		{
			"cranium_width": Vector2(0.8, 1.0), "jaw_width": Vector2(0.85, 1.0),
			"jaw_length": Vector2(0.6, 0.8), "brow_ridge": Vector2(0.8, 1.0),
			"eye_size": Vector2(0.2, 0.35)
		},
		{},
		{"nose_type": {FaceEnums.NoseType.PLATE: 0.5, FaceEnums.NoseType.NONE: 0.5},
			"mouth_type": {FaceEnums.MouthType.TUSKED: 0.5, FaceEnums.MouthType.MANDIBLE: 0.5},
			"crest_type": {FaceEnums.CrestType.FRILL: 0.5, FaceEnums.CrestType.NONE: 0.5},
			"skin_texture": {FaceEnums.SkinTexture.PLATE: 1.0},
			"marking_type": {FaceEnums.MarkingType.SCAR_TISSUE: 1.0}},
		[&"plated_brute", &"desert_scale"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.75, 0.95, 0.90]
	))
	
	# 10. NORDIC
	_save_species(_make_species(
		&"NORDIC", "Nordic",
		{
			"cranium_width": Vector2(0.35, 0.65), "cranium_height": Vector2(0.35, 0.65),
			"jaw_width": Vector2(0.35, 0.65), "brow_ridge": Vector2(0.35, 0.65)
		},
		{},
		{"eye_shape": {FaceEnums.EyeShape.ALMOND: 0.5, FaceEnums.EyeShape.ROUND: 0.5},
			"pupil_shape": {FaceEnums.PupilShape.ROUND: 1.0},
			"nose_type": {FaceEnums.NoseType.HUMAN: 1.0},
			"mouth_type": {FaceEnums.MouthType.LIPS: 1.0},
			"crest_type": {FaceEnums.CrestType.HAIR: 1.0},
			"marking_type": {FaceEnums.MarkingType.NONE: 0.7, FaceEnums.MarkingType.WARPAINT: 0.3}},
		[&"terran_warm", &"pop_flat"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 11. MYCELID
	_save_species(_make_species(
		&"MYCELID", "Mycelid",
		{
			"cranium_bulge": Vector2(0.7, 0.95), "temple_pinch": Vector2(0.6, 0.8)
		},
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.VOID: 1.0}, "eye_glow": Vector2(0.3, 0.5),
			"nose_type": {FaceEnums.NoseType.NONE: 1.0},
			"mouth_type": {FaceEnums.MouthType.SUCKER: 1.0},
			"crest_type": {FaceEnums.CrestType.FRILL: 1.0},
			"skin_texture": {FaceEnums.SkinTexture.BARK: 1.0},
			"marking_type": {FaceEnums.MarkingType.SPOT: 0.5, FaceEnums.MarkingType.GLYPH: 0.5}},
		[&"fungal_bloom", &"amphib_moss"], FaceEnums.SymmetryMode.ASYMMETRIC, 2,
		[0.55, 0.85, 0.70]
	))
	
	# 12. UMBRAL
	_save_species(_make_species(
		&"UMBRAL", "Umbral",
		{},  # Silhouette only
		{"nose": SpeciesDef.PRESENCE_FORBIDDEN, "mouth": SpeciesDef.PRESENCE_FORBIDDEN},
		{"eye_shape": {FaceEnums.EyeShape.VOID: 1.0}, "eye_glow": Vector2(0.9, 1.0),
			"nose_type": {FaceEnums.NoseType.NONE: 1.0},
			"mouth_type": {FaceEnums.MouthType.NONE: 1.0},
			"crest_type": {FaceEnums.CrestType.TENDRIL: 1.0},
			"skin_texture": {FaceEnums.SkinTexture.MEMBRANE: 1.0}},
		[&"deep_bio", &"crystal_prism"], FaceEnums.SymmetryMode.BILATERAL, 2,
		[0.30, 0.30, 0.30]
	))
	
	print("All 12 species created.")


func _make_species(id: StringName, display_name: String, ranges: Dictionary,
		presence: Dictionary, enum_weights: Dictionary, palettes: Array,
		symmetry: int, radial: int, depth_vals: Array) -> SpeciesDef:
	var sp := SpeciesDef.new()
	sp.id = id
	sp.display_name = display_name
	sp.ranges = ranges
	sp.presence = presence
	sp.enum_weights = enum_weights
	sp.allowed_palettes = palettes
	sp.symmetry_mode = symmetry
	sp.radial_count = radial
	sp.default_style_2d = &"flat_vector"
	sp.default_style_3d = &"faceted"
	sp.silhouette_tag = id
	
	# Create depth profile curve
	var curve := Curve.new()
	curve.clear_points()
	curve.add_point(Vector2(0.0, depth_vals[0]))  # Crown
	curve.add_point(Vector2(0.5, depth_vals[1]))  # Eye line
	curve.add_point(Vector2(1.0, depth_vals[2]))  # Chin
	sp.depth_profile = curve
	
	return sp


func _save_species(sp: SpeciesDef) -> void:
	var path := "res://modules/alien_face_gen/data/species/" + String(sp.id).to_lower() + ".tres"
	var err := ResourceSaver.save(sp, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		printerr("Failed to save %s: %d" % [path, err])
	else:
		print("Saved: %s" % path)
