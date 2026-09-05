extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []
	
	# 1. outline.size() == 24 for all 12 species × 20 seeds
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		for i in range(20):
			var g := GenomeGenerator.generate(sp, i * 31 + 7)
			var lm := LandmarkSolver.solve(g, 0)
			H.check(fails, lm.outline.size() == 24,
				"Species %s seed %d: outline has %d points, expected 24" % [sid, i, lm.outline.size()])
	
	# 2. Outline is simple (non-self-intersecting): triangulation returns non-empty
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		for i in range(20):
			var g := GenomeGenerator.generate(sp, i * 31 + 7)
			var lm := LandmarkSolver.solve(g, 0)
			if lm.outline.size() >= 3:
				var tri := Geometry2D.triangulate_polygon(lm.outline)
				H.check(fails, tri.size() > 0,
					"Species %s seed %d: outline is self-intersecting (triangulation empty)" % [sid, i])
	
	# 3. Vertical ordering: crown.y < brow_c.y < eye_line < nose_base.y < mouth_c.y < chin.y
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		for i in range(20):
			var g := GenomeGenerator.generate(sp, i * 31 + 7)
			var lm := LandmarkSolver.solve(g, 0)
			H.check(fails, lm.crown.y < lm.brow_c.y,
				"Species %s seed %d: crown.y >= brow_c.y" % [sid, i])
			H.check(fails, lm.brow_c.y < lm.nose_base.y,
				"Species %s seed %d: brow_c.y >= nose_base.y" % [sid, i])
			H.check(fails, lm.nose_base.y < lm.mouth_c.y,
				"Species %s seed %d: nose_base.y >= mouth_c.y" % [sid, i])
			H.check(fails, lm.mouth_c.y < lm.chin.y,
				"Species %s seed %d: mouth_c.y >= chin.y" % [sid, i])
	
	# 4. bounds() is non-degenerate
	for sid in _SPECIES_IDS:
		var sp := _get_species(sid)
		for i in range(20):
			var g := GenomeGenerator.generate(sp, i * 31 + 7)
			var lm := LandmarkSolver.solve(g, 0)
			var b := lm.bounds()
			H.check(fails, b.size.x > 0.05 and b.size.y > 0.05,
				"Species %s seed %d: degenerate bounds %s" % [sid, i, str(b)])
	
	# 5. BILATERAL with skull_asymmetry == 0.5: eyes symmetric about mirror_axis
	var nordic_sp := _get_species(&"NORDIC")
	for i in range(20):
		var g := GenomeGenerator.generate(nordic_sp, i * 31 + 7)
		g.skull_asymmetry = 0.5
		var lm := LandmarkSolver.solve(g, 0)
		H.check(fails, absf(lm.eye_c_l.x + lm.eye_c_r.x) < 0.001,
			"NORDIC seed %d asymmetric skull: eye_l.x + eye_r.x = %.4f, expected ~0" % [i, lm.eye_c_l.x + lm.eye_c_r.x])
	
	# 6. RADIAL species: extra_eyes().size() + 2 == radial_count
	var lattice_sp := _get_species(&"LATTICE")
	if lattice_sp:
		for i in range(10):
			var g := GenomeGenerator.generate(lattice_sp, i * 41 + 3)
			g.symmetry_mode = FaceEnums.SymmetryMode.RADIAL
			g.radial_count = 5
			var lm := LandmarkSolver.solve(g, 0)
			H.check(fails, lm.extra_eyes().size() + 2 == 5,
				"LATTICE seed %d radial: extra_eyes=%d, expected 3" % [i, lm.extra_eyes().size()])
	
	# 7. Determinism: same genome → identical point arrays
	var g1 := GenomeGenerator.generate(_get_species(&"NORDIC"), 42)
	var lm1 := LandmarkSolver.solve(g1, 0)
	var lm2 := LandmarkSolver.solve(g1, 0)
	H.check(fails, lm1.crown == lm2.crown, "Determinism: crown differs")
	H.check(fails, lm1.chin == lm2.chin, "Determinism: chin differs")
	H.check(fails, lm1.eye_c_l == lm2.eye_c_l, "Determinism: eye_c_l differs")
	H.check(fails, lm1.outline == lm2.outline, "Determinism: outline differs")
	
	H.print_results(fails, 2)
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
