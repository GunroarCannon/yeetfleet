extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []
	
	# 1. render() for NORDIC seed 1 at LOD 0 produces cmds.size() >= 8
	var nordic := _get_species(&"NORDIC")
	var g := GenomeGenerator.generate(nordic, 1)
	var lm := LandmarkSolver.solve(g, 0)
	var p := FacePalette.new()
	p.id = &"void_grey"
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
	
	var style := StyleFlatVector.new()
	var dl := Face2DRenderer.render(g, lm, p, style, Lod.LOD_CINEMATIC)
	H.check(fails, dl.cmds.size() >= 8,
		"NORDIC seed 1 LOD 0: only %d cmds, expected >= 8" % dl.cmds.size())
	
	# 2. FlatVector colour ceiling: a single face must stay within the palette's
	# reachable set (measured max is 11 across all species/seeds) rather than
	# inventing per-face colours.
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		for i in range(10):
			var gg := GenomeGenerator.generate(sp, i * 37 + 5)
			var llm := LandmarkSolver.solve(gg, 0)
			var pp := p  # Use the same palette for simplicity
			var ddl := Face2DRenderer.render(gg, llm, pp, style, Lod.LOD_CINEMATIC)
			H.check(fails, ddl.color_set().size() <= 12,
				"Species %s seed %d: %d colours, max 12" % [sid, i, ddl.color_set().size()])
	
	# 3. Every poly command has points.size() >= 3
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		var gg := GenomeGenerator.generate(sp, 42)
		var llm := LandmarkSolver.solve(gg, 0)
		var ddl := Face2DRenderer.render(gg, llm, p, style, Lod.LOD_CINEMATIC)
		for cmd in ddl.cmds:
			if cmd["type"] == &"poly":
				H.check(fails, cmd["points"].size() >= 3,
					"Species %s: poly has %d points, expected >= 3" % [sid, cmd["points"].size()])
	
	# 4. No command has NaN or INF in any point
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		var gg := GenomeGenerator.generate(sp, 42)
		var llm := LandmarkSolver.solve(gg, 0)
		var ddl := Face2DRenderer.render(gg, llm, p, style, Lod.LOD_CINEMATIC)
		for cmd in ddl.cmds:
			for pt in cmd["points"]:
				H.check(fails, not is_nan(pt.x) and not is_nan(pt.y),
					"Species %s: NaN in point" % sid)
				H.check(fails, not is_inf(pt.x) and not is_inf(pt.y),
					"Species %s: INF in point" % sid)
	
	# 5. dl.bounds() is non-degenerate for all cases
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		var gg := GenomeGenerator.generate(sp, 42)
		var llm := LandmarkSolver.solve(gg, 0)
		var ddl := Face2DRenderer.render(gg, llm, p, style, Lod.LOD_CINEMATIC)
		var b := ddl.bounds()
		H.check(fails, b.size.x > 0.01 and b.size.y > 0.01,
			"Species %s: degenerate bounds %s" % [sid, str(b)])
	
	# 6. Determinism: same genome → identical cmds
	var g1 := GenomeGenerator.generate(_get_species(&"NORDIC"), 42)
	var lm1 := LandmarkSolver.solve(g1, 0)
	var dl1 := Face2DRenderer.render(g1, lm1, p, style, Lod.LOD_CINEMATIC)
	var dl2 := Face2DRenderer.render(g1, lm1, p, style, Lod.LOD_CINEMATIC)
	H.check(fails, dl1.cmds.size() == dl2.cmds.size(),
		"Determinism: different cmd count")
	for i in range(mini(dl1.cmds.size(), dl2.cmds.size())):
		H.check(fails, dl1.cmds[i]["type"] == dl2.cmds[i]["type"],
			"Determinism: different type at %d" % i)
		H.check(fails, dl1.cmds[i]["color"] == dl2.cmds[i]["color"],
			"Determinism: different color at %d" % i)
	
	# 7. SvgExporter.grid() writes verify_03_grid.svg
	var grid_lists: Array[DrawList] = []
	var grid_species := [&"NORDIC", &"VOID_GREY", &"DRACONIAN", &"MANTID"]
	for sid in grid_species:
		for i in range(6):
			var sp := _get_species(sid)
			var gg := GenomeGenerator.generate(sp, i * 13 + 1)
			var llm := LandmarkSolver.solve(gg, 0)
			var ddl := Face2DRenderer.render(gg, llm, p, style, Lod.LOD_CINEMATIC)
			grid_lists.append(ddl)
	
	var grid_path := "res://out/verify_03_grid.svg"
	var err := SvgExporter.grid(grid_lists, 4, 256, grid_path)
	H.check(fails, err == OK, "SvgExporter.grid() returned error: %d" % err)
	
	# Check file exists and is > 2000 bytes
	var f := FileAccess.open(grid_path, FileAccess.READ)
	if f:
		var content := f.get_as_text()
		f.close()
		H.check(fails, content.length() > 2000,
			"verify_03_grid.svg is only %d bytes, expected > 2000" % content.length())
		H.check(fails, content.contains("</svg>"),
			"verify_03_grid.svg missing </svg> tag")
	else:
		H.check(fails, false, "Failed to open verify_03_grid.svg")
	
	H.print_results(fails, 3)
	quit(0 if fails.size() == 0 else 1)


func _get_species(id: StringName) -> SpeciesDef:
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
