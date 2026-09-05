extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

const _EXPRESSIONS := [
	&"neutral", &"happy", &"angry", &"sad", &"surprised",
	&"suspicious", &"talking_a", &"talking_b", &"talking_c"
]

func _initialize() -> void:
	var fails: Array[String] = []
	var style := StyleFlatVector.new()
	var p := _make_test_palette()
	
	# 1. apply() never mutates the input
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var fp_before := g.fingerprint()
		for expr in _EXPRESSIONS:
			var result := FaceExpression.apply(g, expr)
			H.check(fails, g.fingerprint() == fp_before,
				"Species %s expression %s: apply() mutated input genome" % [sid, expr])
	
	# 2. Output genome fields stay within 0.0 – 1.0
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		for expr in _EXPRESSIONS:
			var result := FaceExpression.apply(g, expr)
			var d := result.to_dict()
			for key in d:
				var val = d[key]
				if val is float:
					H.check(fails, val >= -0.001 and val <= 1.001,
						"Species %s expr %s: field %s=%.3f out of range" % [sid, expr, key, val])
	
	# 3. For every species × every facial expression: the resulting DrawList
	# differs from neutral. talking_* only perturbs mouth height/width, so it is
	# skipped here (a beak or absent mouth has no geometry to move) and covered
	# for NORDIC below, whose lips do open.
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var neutral_dl := Face2DRenderer.render(g, lm, p, style, 0, &"neutral")
		for expr in _EXPRESSIONS:
			if expr in [&"neutral", &"talking_a", &"talking_b", &"talking_c"]:
				continue
			var expr_dl := Face2DRenderer.render(g, lm, p, style, 0, expr)
			H.check(fails, neutral_dl.cmds.size() != expr_dl.cmds.size() or
				_dl_differ(neutral_dl, expr_dl),
				"Species %s expr %s: DrawList identical to neutral" % [sid, expr])

	# 3b. talking still visibly opens a species with a proper mouth.
	var g_talk := GenomeGenerator.generate(_load_species(&"NORDIC"), 42)
	var lm_talk := LandmarkSolver.solve(g_talk, 0)
	var neutral_talk := Face2DRenderer.render(g_talk, lm_talk, p, style, 0, &"neutral")
	var talk_dl := Face2DRenderer.render(g_talk, lm_talk, p, style, 0, &"talking_a")
	H.check(fails, neutral_talk.cmds.size() != talk_dl.cmds.size() or _dl_differ(neutral_talk, talk_dl),
		"talking_a should change NORDIC's mouth geometry")
	
	# 4. For NORDIC + angry: mouth_curve decreased and brow_angle decreased
	var nordic := _load_species(&"NORDIC")
	var g_nord := GenomeGenerator.generate(nordic, 42)
	var angry_nord := FaceExpression.apply(g_nord, &"angry")
	H.check(fails, angry_nord.mouth_curve < g_nord.mouth_curve,
		"NORDIC angry: mouth_curve not decreased")
	H.check(fails, angry_nord.brow_angle < g_nord.brow_angle,
		"NORDIC angry: brow_angle not decreased")
	
	# 5. For LATTICE + angry: mouth_curve unchanged (no mouth) but lid_upper OR eye_glow changed
	var lattice := _load_species(&"LATTICE")
	var g_lat := GenomeGenerator.generate(lattice, 42)
	var angry_lat := FaceExpression.apply(g_lat, &"angry")
	H.check(fails, g_lat.mouth_present == false, "LATTICE should have no mouth")
	H.check(fails, angry_lat.mouth_curve == g_lat.mouth_curve or
		absf(angry_lat.mouth_curve - g_lat.mouth_curve) < 0.001,
		"LATTICE angry: mouth_curve changed despite no mouth")
	H.check(fails, angry_lat.lid_upper != g_lat.lid_upper or angry_lat.eye_glow != g_lat.eye_glow,
		"LATTICE angry: neither lid_upper nor eye_glow changed")
	
	# 6. out/verify_09_expr.svg: 4 species × 9 expressions
	var grid_lists: Array[DrawList] = []
	var grid_species := [&"NORDIC", &"VOID_GREY", &"MANTID", &"UMBRAL"]
	for sid in grid_species:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		for expr in _EXPRESSIONS:
			var dl := Face2DRenderer.render(g, lm, p, style, 0, expr)
			grid_lists.append(dl)
	
	var grid_path := "res://out/verify_09_expr.svg"
	var err := SvgExporter.grid(grid_lists, 9, 256, grid_path)
	H.check(fails, err == OK, "SvgExporter.grid() error: %d" % err)
	
	H.print_results(fails, 9)
	quit(0 if fails.size() == 0 else 1)


func _dl_differ(a: DrawList, b: DrawList) -> bool:
	if a.cmds.size() != b.cmds.size():
		return true
	for i in range(a.cmds.size()):
		if a.cmds[i]["type"] != b.cmds[i]["type"]:
			return true
		if a.cmds[i]["color"] != b.cmds[i]["color"]:
			return true
		if a.cmds[i]["slot"] != b.cmds[i]["slot"]:
			return true
		if a.cmds[i]["points"].size() != b.cmds[i]["points"].size():
			return true
		for j in range(a.cmds[i]["points"].size()):
			if a.cmds[i]["points"][j] != b.cmds[i]["points"][j]:
				return true
	return false


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
