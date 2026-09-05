extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

func _initialize() -> void:
	var fails: Array[String] = []
	
	# 1. Determinism: same (species, seed) → same fingerprint
	var g1 := GenomeGenerator.generate(_get_species(&"NORDIC"), 12345)
	var g2 := GenomeGenerator.generate(_get_species(&"NORDIC"), 12345)
	H.check(fails, g1.fingerprint() == g2.fingerprint(), "Same seed must produce same fingerprint")
	
	# 2. Different seed → different fingerprint
	var g3 := GenomeGenerator.generate(_get_species(&"NORDIC"), 12346)
	H.check(fails, g1.fingerprint() != g3.fingerprint(), "Different seeds must produce different fingerprints")
	
	# 3. All 12 palettes load with 17 non-null colors; no duplicate skin_base
	var palette_dir := DirAccess.open("res://modules/alien_face_gen/data/palettes/")
	H.check(fails, palette_dir != null, "Cannot open palettes directory")
	if palette_dir:
		palette_dir.list_dir_begin()
		var skin_bases: Array[Color] = []
		var count := 0
		var fname := palette_dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var p: FacePalette = load("res://modules/alien_face_gen/data/palettes/" + fname)
				H.check(fails, p != null, "Failed to load palette: %s" % fname)
				if p:
					var colors := p.get_all_colors()
					H.check(fails, colors.size() == 17, "Palette %s has %d colors, expected 17" % [fname, colors.size()])
					for c in colors:
						H.check(fails, c != Color.TRANSPARENT or c == p.background or c == p.eye_glow, "Palette %s has null color" % fname)
					skin_bases.append(p.skin_base)
					count += 1
			fname = palette_dir.get_next()
		H.check(fails, count == 12, "Expected 12 palettes, found %d" % count)
		# Check no duplicate skin_base
		for i in range(skin_bases.size()):
			for j in range(i + 1, skin_bases.size()):
				H.check(fails, not H.approx(skin_bases[i].r, skin_bases[j].r) or
					not H.approx(skin_bases[i].g, skin_bases[j].g) or
					not H.approx(skin_bases[i].b, skin_bases[j].b),
					"Palettes %d and %d share identical skin_base" % [i, j])
	
	# 4. FORBIDDEN presence zeros fields
	var test_species := SpeciesDef.new()
	test_species.id = &"TEST"
	test_species.presence = {"nose": SpeciesDef.PRESENCE_FORBIDDEN}
	test_species.allowed_palettes = [&"void_grey"]
	test_species.ranges = {}
	test_species.enum_weights = {}
	var tg := GenomeGenerator.generate(test_species, 42)
	H.check(fails, tg.nose_present == false, "FORBIDDEN nose must set nose_present=false")
	H.check(fails, tg.nose_length == 0.0, "FORBIDDEN nose must zero nose_length")
	H.check(fails, tg.nose_width == 0.0, "FORBIDDEN nose must zero nose_width")
	H.check(fails, tg.nose_bridge == 0.0, "FORBIDDEN nose must zero nose_bridge")
	
	# 5. Stream isolation: changing eye ranges does not change nose fields
	var sp_a := _get_species(&"NORDIC")
	var sp_b := _get_species(&"NORDIC").duplicate()
	sp_b.ranges = sp_b.ranges.duplicate()
	sp_b.ranges["eye_size"] = Vector2(0.9, 1.0)
	var ga := GenomeGenerator.generate(sp_a, 9999)
	var gb := GenomeGenerator.generate(sp_b, 9999)
	H.check(fails, ga.nose_length == gb.nose_length, "Stream isolation: nose_length changed with eye range change")
	H.check(fails, ga.nose_width == gb.nose_width, "Stream isolation: nose_width changed with eye range change")
	H.check(fails, ga.nose_bridge == gb.nose_bridge, "Stream isolation: nose_bridge changed with eye range change")
	
	# 6. All continuous fields in 0..1 for 200 random seeds across 3 species
	var species_list := [&"NORDIC", &"VOID_GREY", &"DRACONIAN"]
	for sid in species_list:
		var sp := _get_species(sid)
		for i in range(200):
			var gen := GenomeGenerator.generate(sp, i * 7 + 13)
			var d := gen.to_dict()
			for key in d:
				var val = d[key]
				if val is float:
					H.check(fails, val >= -0.001 and val <= 1.001,
						"Field %s=%.3f out of range for %s seed %d" % [key, val, sid, i])
	
	H.print_results(fails, 1)
	quit(0 if fails.size() == 0 else 1)


func _get_species(id: StringName) -> SpeciesDef:
	var path := "res://modules/alien_face_gen/data/species/" + String(id).to_lower() + ".tres"
	var s = load(path)
	if s == null:
		# Fallback: create a minimal SpeciesDef
		var sd := SpeciesDef.new()
		sd.id = id
		sd.allowed_palettes = [&"void_grey"]
		sd.ranges = {}
		sd.enum_weights = {}
		sd.presence = {}
		return sd
	return s
