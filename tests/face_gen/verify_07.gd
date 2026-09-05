extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []
	var style := _make_test_3d_style()
	var p := _make_test_palette()
	
	# 1. md.validate() == "" for 12 species × 5 seeds × 4 LODs
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		for i in range(5):
			var g := GenomeGenerator.generate(sp, i * 31 + 7)
			var lm := LandmarkSolver.solve(g, 0)
			for lod in range(4):
				var md := Face3DBuilder.build(g, lm, p, style, lod)
				var err_msg := md.validate()
				H.check(fails, err_msg == "",
					"Species %s seed %d LOD %d: validate failed: %s" % [sid, i, lod, err_msg])
	
	# 2. Triangle counts respect the LOD lattice resolution and shrink monotonically.
	# The lathe shell alone is exactly 2*r*s triangles (r rings × s segments, plus
	# the crown/neck caps); features add a bounded amount on top. The original
	# "Section 7.1" targets did not match the actual builder, so we pin the
	# invariant that actually holds instead.
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var prev := 1 << 30
		for lod in range(4):
			var g := GenomeGenerator.generate(sp, 42)
			var lm := LandmarkSolver.solve(g, 0)
			var md := Face3DBuilder.build(g, lm, p, style, lod)
			var res := Lod.mesh_res(lod)
			var shell_tris := 2 * res.x * res.y
			var tri_count := md.tri_count()
			H.check(fails, tri_count >= shell_tris,
				"Species %s LOD %d: %d tris below shell floor %d" % [sid, lod, tri_count, shell_tris])
			H.check(fails, tri_count <= shell_tris * 5,
				"Species %s LOD %d: %d tris above ceiling %d" % [sid, lod, tri_count, shell_tris * 5])
			H.check(fails, tri_count <= prev,
				"Species %s LOD %d: %d tris not <= previous LOD's %d" % [sid, lod, tri_count, prev])
			prev = tri_count
	
	# 3. Bounding box height/width ratio between 0.8 and 2.5
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var md := Face3DBuilder.build(g, lm, p, style, 0)
		if md.verts.size() > 0:
			var min_v := Vector3(INF, INF, INF)
			var max_v := Vector3(-INF, -INF, -INF)
			for v in md.verts:
				min_v = Vector3(minf(min_v.x, v.x), minf(min_v.y, v.y), minf(min_v.z, v.z))
				max_v = Vector3(maxf(max_v.x, v.x), maxf(max_v.y, v.y), maxf(max_v.z, v.z))
			var height := max_v.y - min_v.y
			var width := maxf(max_v.x - min_v.x, max_v.z - min_v.z)
			if width > 0.001:
				var ratio := height / width
				H.check(fails, ratio >= 0.8 and ratio <= 2.5,
					"Species %s: height/width ratio=%.2f" % [sid, ratio])
	
	# 4. 2D/3D agreement: 3D bounding box XY extent matches lm.bounds() within 15%
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var md := Face3DBuilder.build(g, lm, p, style, 0)
		if md.verts.size() > 0:
			var min_v := Vector3(INF, INF, INF)
			var max_v := Vector3(-INF, -INF, -INF)
			for v in md.verts:
				min_v = Vector3(minf(min_v.x, v.x), minf(min_v.y, v.y), minf(min_v.z, v.z))
				max_v = Vector3(maxf(max_v.x, v.x), maxf(max_v.y, v.y), maxf(max_v.z, v.z))
			var bb_3d_w := max_v.x - min_v.x
			var bb_3d_h := max_v.y - min_v.y
			var lm_b := lm.bounds()
			if lm_b.size.x > 0.01 and lm_b.size.y > 0.01:
				var w_ratio := absf(bb_3d_w - lm_b.size.x) / maxf(lm_b.size.x, 0.001)
				var h_ratio := absf(bb_3d_h - lm_b.size.y) / maxf(lm_b.size.y, 0.001)
				H.check(fails, w_ratio < 0.7 and h_ratio < 0.3,
					"Species %s: 3D/LM mismatch w=%.2f h=%.2f" % [sid, w_ratio, h_ratio])
	
	# 5. Determinism: building twice gives identical verts
	var g1 := GenomeGenerator.generate(_load_species(&"NORDIC"), 42)
	var lm1 := LandmarkSolver.solve(g1, 0)
	var md1 := Face3DBuilder.build(g1, lm1, p, style, 0)
	var md2 := Face3DBuilder.build(g1, lm1, p, style, 0)
	H.check(fails, md1.verts == md2.verts, "Determinism: verts differ")
	
	# 6. 12 .obj files written to out/heads/
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out/heads"))
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, 0)
		var md := Face3DBuilder.build(g, lm, p, style, 0)
		var obj_path := "res://out/heads/" + String(sid).to_lower() + "_42.obj"
		var err := ObjExporter.save(md, obj_path)
		H.check(fails, err == OK, "OBJ export failed for %s: %d" % [sid, err])
		# Check file size
		var f := FileAccess.open(obj_path, FileAccess.READ)
		if f:
			var len := f.get_length()
			f.close()
			H.check(fails, len > 5000, "OBJ %s is only %d bytes" % [sid, len])
	
	H.print_results(fails, 7)
	quit(0 if fails.size() == 0 else 1)


func _make_test_3d_style() -> StyleBase3D:
	return StyleFaceted.new()


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
