## reputation_shot.gd — visual screenshot for modules/reputation/
##
## Renders a top-down view showing:
##   - Player ship (blue) at centre
##   - Faction ships with heat values + recognition status labels
##   - Transponder range ring
##
## Run:
##   "$GD" --path . --rendering-driver opengl3 --script modules/reputation/tools/reputation_shot.gd -- reputation.png
##
## Output: reputation.png in the project root.
extends SceneTree

func _initialize() -> void:
	var args     := OS.get_cmdline_user_args()
	var out_path := "reputation.png" if args.is_empty() else String(args[0])
	var warm     := 20 if args.size() < 2 else int(args[1])
	var size     := Vector2i(1280, 720)

	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	var world := Node3D.new()
	world.name = "ReputationPreviewWorld"
	root.add_child(world)

	# --- Environment --------------------------------------------------
	var env := WorldEnvironment.new()
	var e   := Environment.new()
	e.background_mode  = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.08)
	e.ambient_light_color  = Color(0.4, 0.4, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 45, 0)
	sun.light_energy = 1.2
	world.add_child(sun)

	# --- Camera (top-down) --------------------------------------------
	var cam := Camera3D.new()
	cam.position = Vector3(0, 30, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.fov = 55.0
	world.add_child(cam)
	cam.current = true

	# --- Build a SessionRepStore with history -------------------------
	var store := SessionRepStore.new()
	store.record_act("player", "empire",  RepStore.ACTS.ATTACK, 6)
	store.record_act("player", "traders", RepStore.ACTS.STEAL,  2)
	store.record_act("player", "pirates", RepStore.ACTS.RESCUE, 4)

	# --- Ships in scenario --------------------------------------------
	var ships := [
		{
			"label":      "EMPIRE PATROL",
			"faction_id": "empire",
			"pos":        Vector3(-7, 0, -5),
			"color":      Color(0.6, 0.7, 1.0),
		},
		{
			"label":      "TRADERS GUILD",
			"faction_id": "traders",
			"pos":        Vector3(7, 0, -3),
			"color":      Color(0.8, 0.9, 0.5),
		},
		{
			"label":      "PIRATES",
			"faction_id": "pirates",
			"pos":        Vector3(0, 0, 7),
			"color":      Color(1.0, 0.4, 0.3),
		},
		{
			"label":      "FAR PATROL (out of range)",
			"faction_id": "empire",
			"pos":        Vector3(15, 0, 0),
			"color":      Color(0.45, 0.45, 0.45),
		},
	]

	# Player.
	_add_cube(world, Vector3.ZERO, Color(0.3, 0.5, 1.0), 1.0)
	_add_label3d(world, Vector3(0, 0, 0) + Vector3(0, 1.8, 0), "PLAYER", Color.WHITE, 0.08)

	# Transponder range ring (½ scene units = 12.5 units for 500m).
	_add_ring(world, Vector3.ZERO, 12.5)

	# Faction ships.
	for s in ships:
		var pos     : Vector3 = s["pos"]
		var faction : String  = s["faction_id"]
		var dist    := pos.length()
		# 1 unit ≈ 40m in this view → transponder range 500m ≈ 12.5 units.
		var dist_m  := dist * 40.0
		var heat    := store.get_heat("player", faction)
		var result  := Recognition.evaluate("player", faction, store, dist_m)

		_add_cube(world, pos, s["color"], 0.7)
		_add_label3d(world, pos + Vector3(0, 2.0, 0), s["label"], s["color"], 0.055)
		_add_label3d(world, pos + Vector3(0, 2.8, 0), "Heat: %d" % heat, Color(1.0, 0.7, 0.3), 0.055)

		var rlabel := Recognition.label_for(result)
		if rlabel.is_empty():
			rlabel = "—"
		var rcol := Color(0.5, 1.0, 0.5)
		match result:
			Recognition.RecognitionResult.KOS:
				rcol = Color(1.0, 0.1, 0.1)
			Recognition.RecognitionResult.HOSTILE:
				rcol = Color(1.0, 0.5, 0.1)
			Recognition.RecognitionResult.IDENTIFIED:
				rcol = Color(0.9, 0.9, 0.3)
		_add_label3d(world, pos + Vector3(0, 3.5, 0), rlabel, rcol, 0.07)

	# Warm up.
	for _i in warm:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)


func _add_cube(parent: Node, pos: Vector3, col: Color, size: float) -> void:
	var mi  := MeshInstance3D.new()
	var m   := BoxMesh.new()
	m.size  = Vector3(size, size * 0.4, size)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic     = 0.3
	mat.roughness    = 0.6
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_label3d(parent: Node, pos: Vector3, text: String, col: Color, px: float) -> void:
	var lbl         := Label3D.new()
	lbl.text        = text
	lbl.pixel_size  = px
	lbl.font_size   = 28
	lbl.modulate    = col
	lbl.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position    = pos
	parent.add_child(lbl)


func _add_ring(parent: Node, centre: Vector3, radius: float) -> void:
	var mi      := MeshInstance3D.new()
	var m       := CylinderMesh.new()
	m.top_radius    = radius
	m.bottom_radius = radius
	m.height        = 0.05
	m.rings         = 1
	m.radial_segments = 64
	mi.mesh     = m
	var mat     := StandardMaterial3D.new()
	mat.albedo_color   = Color(0.3, 0.5, 1.0, 0.35)
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test  = true
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	_add_label3d(parent, centre + Vector3(radius + 1.2, 0, 0),
		"TRANSPONDER\nRANGE", Color(0.4, 0.6, 1.0, 0.8), 0.045)
