extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

func _initialize() -> void:
	var fails: Array[String] = []
	
	# 1. plugin.cfg parses and plugin.gd loads as a script with @tool
	var cfg_path := "res://addons/face_gen_gallery/plugin.cfg"
	var cfg := ConfigFile.new()
	var err := cfg.load(cfg_path)
	H.check(fails, err == OK, "Failed to load plugin.cfg: %d" % err)
	if err == OK:
		H.check(fails, cfg.has_section_key("plugin", "name"), "plugin.cfg missing [plugin] name")
		H.check(fails, cfg.get_value("plugin", "script", "") == "plugin.gd",
			"plugin.cfg script != plugin.gd")
	
	var plugin_script = load("res://addons/face_gen_gallery/plugin.gd")
	H.check(fails, plugin_script != null, "Failed to load plugin.gd")
	if plugin_script:
		# Check if it's a tool script
		H.check(fails, plugin_script.is_tool(), "plugin.gd is not @tool")
	
	# 2. gallery_dock.gd loads and can be instantiated headlessly
	var dock_script = load("res://addons/face_gen_gallery/gallery_dock.gd")
	H.check(fails, dock_script != null, "Failed to load gallery_dock.gd")
	if dock_script:
		H.check(fails, dock_script.is_tool(), "gallery_dock.gd is not @tool")
	
	# 3. The dock's _build_preview returns a non-null DrawList
	# We test by directly calling the renderer
	var g := GenomeGenerator.generate(_load_species(&"NORDIC"), 42)
	var lm := LandmarkSolver.solve(g, 0)
	var p := _make_test_palette()
	var style := Face2DRenderer.get_style(&"flat_vector")
	var dl := Face2DRenderer.render(g, lm, p, style, 0)
	H.check(fails, dl != null, "_build_preview returned null")
	H.check(fails, dl.cmds.size() > 0, "_build_preview returned empty DrawList")
	
	H.print_results(fails, 10)
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
