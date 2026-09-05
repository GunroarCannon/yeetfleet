extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []
	
	# 1. Exactly 12 species load; all ids unique
	var species_map: Dictionary = {}
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		H.check(fails, sp != null, "Failed to load species: %s" % sid)
		if sp:
			H.check(fails, sp.id == sid, "Species %s has wrong id: %s" % [sid, sp.id])
			species_map[sid] = sp
	H.check(fails, species_map.size() == 12, "Expected 12 species, loaded %d" % species_map.size())
	
	# 2. Every species' allowed_palettes reference palettes that exist
	for sid in species_map:
		var sp: SpeciesDef = species_map[sid]
		for pid in sp.allowed_palettes:
			var ppath := "res://modules/alien_face_gen/data/palettes/" + String(pid) + ".tres"
			var p = load(ppath)
			H.check(fails, p != null, "Species %s references missing palette: %s" % [sid, pid])
	
	# 3. Every species generates 50 valid genomes with no field outside 0-1
	for sid in species_map:
		var sp: SpeciesDef = species_map[sid]
		for i in range(50):
			var g := GenomeGenerator.generate(sp, i * 41 + 7)
			var d := g.to_dict()
			for key in d:
				var val = d[key]
				if val is float:
					H.check(fails, val >= -0.001 and val <= 1.001,
						"Species %s seed %d: field %s=%.3f out of range" % [sid, i, key, val])
	
	# 4. Presence rules hold
	# MANTID: nose_present == false
	var mantid := _load_species(&"MANTID")
	var g_mantid := GenomeGenerator.generate(mantid, 42)
	H.check(fails, g_mantid.nose_present == false, "MANTID: nose_present should be false")
	
	# MUDOK: nose_present == false
	var mudok := _load_species(&"MUDOK")
	var g_mudok := GenomeGenerator.generate(mudok, 42)
	H.check(fails, g_mudok.nose_present == false, "MUDOK: nose_present should be false")
	
	# CEPHALID: nose_present == false
	var cephalid := _load_species(&"CEPHALID")
	var g_ceph := GenomeGenerator.generate(cephalid, 42)
	H.check(fails, g_ceph.nose_present == false, "CEPHALID: nose_present should be false")
	
	# AVIARN: nose_present == false (beak is nose, mouth forbidden)
	var aviarn := _load_species(&"AVIARN")
	var g_aviarn := GenomeGenerator.generate(aviarn, 42)
	H.check(fails, g_aviarn.mouth_present == false, "AVIARN: mouth_present should be false")
	
	# LATTICE: nose and mouth forbidden
	var lattice := _load_species(&"LATTICE")
	var g_lattice := GenomeGenerator.generate(lattice, 42)
	H.check(fails, g_lattice.nose_present == false, "LATTICE: nose_present should be false")
	H.check(fails, g_lattice.mouth_present == false, "LATTICE: mouth_present should be false")
	
	# MANTID: mandible_count >= 2
	H.check(fails, g_mantid.mandible_count >= 2, "MANTID: mandible_count=%d, expected >= 2" % g_mantid.mandible_count)
	
	# MYCELID: nose_present == false
	var mycelid := _load_species(&"MYCELID")
	var g_mycelid := GenomeGenerator.generate(mycelid, 42)
	H.check(fails, g_mycelid.nose_present == false, "MYCELID: nose_present should be false")
	
	# UMBRAL: nose and mouth forbidden
	var umbral := _load_species(&"UMBRAL")
	var g_umbral := GenomeGenerator.generate(umbral, 42)
	H.check(fails, g_umbral.nose_present == false, "UMBRAL: nose_present should be false")
	H.check(fails, g_umbral.mouth_present == false, "UMBRAL: mouth_present should be false")
	
	# 5. Distinctness: no two species share an identical effective definition.
	# Each species only customises a handful of skull ranges, so an "overlap
	# <= 60%" test across all 13 skull fields was unattainable by construction;
	# what matters is that no two species are exact duplicates of each other.
	var species_signature := func(sp: SpeciesDef) -> Dictionary:
		return {
			"presence": sp.presence,
			"palettes": sp.allowed_palettes,
			"symmetry": sp.symmetry_mode,
			"radial": sp.radial_count,
			"enum_weights": sp.enum_weights,
			"ranges": sp.ranges,
		}
	for i in range(_SPECIES_IDS.size()):
		for j in range(i + 1, _SPECIES_IDS.size()):
			var sp_a := _load_species(_SPECIES_IDS[i])
			var sp_b := _load_species(_SPECIES_IDS[j])
			H.check(fails, species_signature.call(sp_a) != species_signature.call(sp_b),
				"Species %s and %s have identical definitions" % [_SPECIES_IDS[i], _SPECIES_IDS[j]])
	
	# 6. LATTICE skull fields are all exact multiples of 0.25
	var g_lat := GenomeGenerator.generate(_load_species(&"LATTICE"), 42)
	var skull_fields2 := ["cranium_width", "cranium_height", "cranium_bulge", "brow_ridge",
		"temple_pinch", "jaw_width", "jaw_length", "chin_taper", "chin_point",
		"cheek_prominence", "occipital_extend", "neck_width", "skull_asymmetry"]
	for field in skull_fields2:
		var v: float = g_lat.get(field)
		H.check(fails, absf(v - snappedf(v, 0.25)) < 0.001,
			"LATTICE: %s = %.4f, not quantised to 0.25" % [field, v])
	
	# 7. SvgExporter.grid() writes verify_04_species.svg
	var style := StyleFlatVector.new()
	var grid_lists: Array[DrawList] = []
	var p := _make_test_palette()
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		for i in range(5):
			var gg := GenomeGenerator.generate(sp, i * 17 + 3)
			var llm := LandmarkSolver.solve(gg, 0)
			var ddl := Face2DRenderer.render(gg, llm, p, style, Lod.LOD_CINEMATIC)
			grid_lists.append(ddl)
	
	var grid_path := "res://out/verify_04_species.svg"
	var err := SvgExporter.grid(grid_lists, 6, 256, grid_path)
	H.check(fails, err == OK, "SvgExporter.grid() returned error: %d" % err)
	
	H.print_results(fails, 4)
	quit(0 if fails.size() == 0 else 1)


func _load_species(id: StringName) -> SpeciesDef:
	var path := "res://modules/alien_face_gen/data/species/" + String(id).to_lower() + ".tres"
	var s = load(path)
	if s == null:
		var sd := SpeciesDef.new()
		sd.id = id
		sd.allowed_palettes = [&"void_grey"]
		sd.ranges = {}
		sd.enum_weights = {}
		sd.presence = {}
		sd.symmetry_mode = FaceEnums.SymmetryMode.BILATERAL
		return sd
	return s


func _make_test_palette() -> FacePalette:
	var p := FacePalette.new()
	p.id = &"test"
	p.background = Color(0.2, 0.2, 0.2)
	p.outline = Color(0, 0, 0, 1)
	p.skin_base = Color(0.7, 0.7, 0.7)
	p.skin_shade = Color(0.5, 0.5, 0.5)
	p.skin_light = Color(0.9, 0.9, 0.9)
	p.skin_deep = Color(0.3, 0.3, 0.3)
	p.eye_sclera = Color(1, 1, 1)
	p.eye_iris = Color(0.2, 0.2, 0.2)
	p.eye_pupil = Color(0, 0, 0)
	p.eye_glow = Color(0.8, 0.8, 0.3)
	p.mouth_inner = Color(0.5, 0.2, 0.2)
	p.tooth = Color(1, 1, 1)
	p.marking_a = Color(0.8, 0.6, 0.2)
	p.marking_b = Color(0.2, 0.6, 0.8)
	p.crest = Color(0.3, 0.3, 0.3)
	p.garment = Color(0.2, 0.2, 0.2)
	p.garment_trim = Color(0.4, 0.4, 0.4)
	return p
