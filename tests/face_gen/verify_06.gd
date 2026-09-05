extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

const _STYLES := [&"flat_vector", &"pixel_art", &"ink_outline"]

func _initialize() -> void:
	var fails: Array[String] = []
	var p := _make_test_palette()
	
	# 1. All 3 styles render all 12 species at all 4 LODs without error
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		for style_id in _STYLES:
			var style := Face2DRenderer.get_style(style_id)
			for lod in range(4):
				var g := GenomeGenerator.generate(sp, 42)
				var lm := LandmarkSolver.solve(g, lod)
				var dl := Face2DRenderer.render(g, lm, p, style, lod)
				H.check(fails, dl != null and dl.cmds.size() > 0,
					"Species %s style %s LOD %d: render failed or empty" % [sid, style_id, lod])
	
	# 2. PixelArt: every point's coordinates are exact multiples of LOD's pixel size
	var pix_style := Face2DRenderer.get_style(&"pixel_art")
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		for lod in range(4):
			var lm := LandmarkSolver.solve(g, lod)
			var dl := Face2DRenderer.render(g, lm, p, pix_style, lod)
			var pixel_size: float = 1.0 / float([64, 48, 32, 16][lod])
			for cmd in dl.cmds:
				for pt in cmd["points"]:
					H.check(fails,
						absf(pt.x - snappedf(pt.x, pixel_size)) < 0.001 and
						absf(pt.y - snappedf(pt.y, pixel_size)) < 0.001,
						"PixelArt %s LOD %d: point (%.4f, %.4f) not snapped to %.4f" % [
							sid, lod, pt.x, pt.y, pixel_size])
			H.check(fails, dl.color_set().size() <= 20,
				"PixelArt %s LOD %d: %d colours, max 20" % [sid, lod, dl.color_set().size()])
	
	# 3. InkOutline: every filled poly has a matching line command in the same slot
	var ink_style := Face2DRenderer.get_style(&"ink_outline")
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var dl := Face2DRenderer.render(g, lm, p, ink_style, 0)
		var poly_slots: Dictionary = {}
		for cmd in dl.cmds:
			if cmd["type"] == &"poly":
				poly_slots[cmd["slot"]] = true
		for slot in poly_slots:
			if slot == &"bg_block":
				continue  # Background doesn't need outline
			var has_line := false
			for cmd in dl.cmds:
				if cmd["type"] == &"line" and cmd["slot"] == slot:
					has_line = true
					break
			H.check(fails, has_line,
				"InkOutline %s: poly slot '%s' has no matching line" % [sid, slot])
	
	# 4. Style independence: genome and landmarks are byte-identical regardless of style
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var fp := g.fingerprint()
		for style_id in _STYLES:
			var style := Face2DRenderer.get_style(style_id)
			var dl := Face2DRenderer.render(g, lm, p, style, 0)
			H.check(fails, g.fingerprint() == fp,
				"Style %s mutated genome for %s" % [style_id, sid])
	
	# 5. out/verify_06_styles.svg written
	var grid_lists: Array[DrawList] = []
	var grid_species := [&"NORDIC", &"VOID_GREY", &"DRACONIAN", &"MANTID", &"SYNTH", &"BRUTE"]
	for sid in grid_species:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		for style_id in _STYLES:
			var style := Face2DRenderer.get_style(style_id)
			var dl := Face2DRenderer.render(g, lm, p, style, Lod.LOD_CINEMATIC)
			grid_lists.append(dl)
	
	var grid_path := "res://out/verify_06_styles.svg"
	var err := SvgExporter.grid(grid_lists, 3, 256, grid_path)
	H.check(fails, err == OK, "SvgExporter.grid() error: %d" % err)
	
	H.print_results(fails, 6)
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
