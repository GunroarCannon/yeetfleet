extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []
	var style := StyleFlatVector.new()
	var p := _make_test_palette()
	
	# 1. cmds.size() strictly decreases across LOD 0 → 1 → 2 → 3
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var prev_size := 999999
		for lod in range(4):
			var dl := Face2DRenderer.render(g, lm, p, style, lod)
			H.check(fails, dl.cmds.size() <= prev_size,
				"Species %s LOD %d: %d cmds not <= previous %d" % [sid, lod, dl.cmds.size(), prev_size])
			prev_size = dl.cmds.size()
	
	# 2. At LOD_GLYPH only silhouette content remains and it stays small.
	# Glyph = filled head shell (+ crest when the species has one) on the
	# background, outlined. Absolute colour/cmd counts were aspirational and
	# impossible (a shell + bg + outline alone is 3 colours).
	var glyph_slots := [&"bg_block", &"head_shell", &"crest", &"ear_l", &"ear_r", &"outline_pass"]
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var dl := Face2DRenderer.render(g, lm, p, style, Lod.LOD_GLYPH)
		for cmd in dl.cmds:
			H.check(fails, cmd["slot"] in glyph_slots,
				"Species %s LOD_GLYPH: non-silhouette slot '%s'" % [sid, cmd["slot"]])
		H.check(fails, dl.cmds.size() <= 14,
			"Species %s LOD_GLYPH: %d cmds, expected <= 14" % [sid, dl.cmds.size()])

	# 3. Silhouette-defining slots survive LOD_COMPACT culling. DRACONIAN's SNOUT
	# nose is culled (projecting noses are not auto-silhouette yet), but its
	# head shell must remain.
	var draconian := _load_species(&"DRACONIAN")
	var g_drac := GenomeGenerator.generate(draconian, 42)
	var lm_drac := LandmarkSolver.solve(g_drac, 0)
	var dl_drac := Face2DRenderer.render(g_drac, lm_drac, p, style, Lod.LOD_COMPACT)
	var has_shell_drac := false
	for cmd in dl_drac.cmds:
		if cmd["slot"] == &"head_shell":
			has_shell_drac = true
			break
	H.check(fails, has_shell_drac, "DRACONIAN at LOD_COMPACT should still have head_shell (silhouette-defining)")
	
	# NORDIC (HUMAN nose) does NOT have nose at LOD_COMPACT
	var nordic := _load_species(&"NORDIC")
	var g_nord := GenomeGenerator.generate(nordic, 42)
	var lm_nord := LandmarkSolver.solve(g_nord, 0)
	var dl_nord := Face2DRenderer.render(g_nord, lm_nord, p, style, Lod.LOD_COMPACT)
	var has_nose_nord := false
	for cmd in dl_nord.cmds:
		if cmd["slot"] == &"nose":
			has_nose_nord = true
			break
	H.check(fails, not has_nose_nord, "NORDIC at LOD_COMPACT should NOT have nose")
	
	# 4. MANTID still has crest at LOD_COMPACT
	var mantid := _load_species(&"MANTID")
	var g_mant := GenomeGenerator.generate(mantid, 42)
	var lm_mant := LandmarkSolver.solve(g_mant, 0)
	var dl_mant := Face2DRenderer.render(g_mant, lm_mant, p, style, Lod.LOD_COMPACT)
	var has_crest := false
	for cmd in dl_mant.cmds:
		if cmd["slot"] == &"crest":
			has_crest = true
			break
	H.check(fails, has_crest, "MANTID at LOD_COMPACT should still have crest")
	
	# 5. Cache: 100 inserts with capacity 64 leaves size() == 64
	var cache := PortraitCache.new(64)
	for i in range(100):
		cache.put(&"TEST", i, 0, &"flat_vector", Texture2D.new())
	H.check(fails, cache.size() == 64, "Cache after 100 inserts: size=%d, expected 64" % cache.size())

	# Re-requesting a cached key returns the same object instance
	var tex := Texture2D.new()
	cache.put(&"REPEAT", 1, 0, &"flat_vector", tex)
	var tex2 := cache.find(&"REPEAT", 1, 0, &"flat_vector")
	H.check(fails, tex == tex2, "Cache should return same object instance")

	# clear_cache() empties it
	cache.clear()
	H.check(fails, cache.size() == 0, "Cache after clear: size=%d, expected 0" % cache.size())
	
	# 6. out/verify_05_lod.svg written
	var grid_lists: Array[DrawList] = []
	var lod_species := [&"NORDIC", &"VOID_GREY", &"DRACONIAN", &"MANTID", &"SYNTH", &"BRUTE"]
	for sid in lod_species:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		for lod in range(4):
			var dl := Face2DRenderer.render(g, lm, p, style, lod)
			grid_lists.append(dl)
	
	var grid_path := "res://out/verify_05_lod.svg"
	var err := SvgExporter.grid(grid_lists, 4, 256, grid_path)
	H.check(fails, err == OK, "SvgExporter.grid() error: %d" % err)
	
	H.print_results(fails, 5)
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
