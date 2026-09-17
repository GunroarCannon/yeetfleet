## Renders and screenshots the visual event language (HUD bubbles and 3D world markers).
##
##     godot --path . --rendering-driver opengl3 --script modules/events/tools/events_shot.gd -- events.png [warm_frames] [w] [h]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "events.png" if args.is_empty() else String(args[0])
	var warm := 20 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))

	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	# 3D World setup
	var world := Node3D.new()
	world.name = "EventsPreviewWorld"
	root.add_child(world)

	# Environment / Lighting
	var env := WorldEnvironment.new()
	var sky_env := Environment.new()
	sky_env.background_mode = Environment.BG_COLOR
	sky_env.background_color = Color(0.015, 0.02, 0.04)
	sky_env.ambient_light_color = Color(0.35, 0.4, 0.5)
	sky_env.ambient_light_energy = 0.9
	env.environment = sky_env
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	world.add_child(sun)

	# Camera (add to world first before look_at)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.0, 22.0)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	# Materials for visual clarity
	var mat_ship := StandardMaterial3D.new()
	mat_ship.albedo_color = Color(0.25, 0.28, 0.35)
	mat_ship.metallic = 0.8
	mat_ship.roughness = 0.3

	var mat_cargo := StandardMaterial3D.new()
	mat_cargo.albedo_color = Color(0.0, 0.75, 0.9)
	mat_cargo.emission_enabled = true
	mat_cargo.emission = Color(0.0, 0.4, 0.6)

	var mat_crystal := StandardMaterial3D.new()
	mat_crystal.albedo_color = Color(1.0, 0.82, 0.1)
	mat_crystal.emission_enabled = true
	mat_crystal.emission = Color(0.8, 0.5, 0.0)

	var mat_raider := StandardMaterial3D.new()
	mat_raider.albedo_color = Color(0.55, 0.12, 0.12)
	mat_raider.metallic = 0.6

	# 1. Distress ship with 🚨 marker
	var ship_mesh := BoxMesh.new()
	ship_mesh.size = Vector3(3.5, 1.4, 6.0)
	ship_mesh.material = mat_ship
	var ship_inst := MeshInstance3D.new()
	ship_inst.mesh = ship_mesh
	ship_inst.position = Vector3(-8.0, 0.5, -4.0)
	world.add_child(ship_inst)

	var marker_distress := WorldMarker.new()
	marker_distress.symbol = "🚨"
	marker_distress.marker_color = Color(1.0, 0.2, 0.27)
	marker_distress.pulse = true
	marker_distress.target_node = ship_inst
	world.add_child(marker_distress)

	# 2. Cargo pod with 📦 marker
	var cargo_mesh := BoxMesh.new()
	cargo_mesh.size = Vector3(2.0, 2.0, 2.0)
	cargo_mesh.material = mat_cargo
	var cargo_inst := MeshInstance3D.new()
	cargo_inst.mesh = cargo_mesh
	cargo_inst.position = Vector3(-1.0, 0.5, 2.0)
	world.add_child(cargo_inst)

	var marker_cargo := WorldMarker.new()
	marker_cargo.symbol = "📦"
	marker_cargo.marker_color = Color(0.0, 0.9, 1.0)
	marker_cargo.target_node = cargo_inst
	world.add_child(marker_cargo)

	# 3. Rare crystal with ◆ marker
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = 1.0
	crystal_mesh.height = 2.0
	crystal_mesh.material = mat_crystal
	var crystal_inst := MeshInstance3D.new()
	crystal_inst.mesh = crystal_mesh
	crystal_inst.position = Vector3(7.5, 1.5, -5.0)
	world.add_child(crystal_inst)

	var marker_res := WorldMarker.new()
	marker_res.symbol = "◆"
	marker_res.marker_color = Color(1.0, 0.84, 0.0)
	marker_res.target_node = crystal_inst
	world.add_child(marker_res)

	# 4. Target raider with 🎯 marker
	var raider_mesh := PrismMesh.new()
	raider_mesh.size = Vector3(2.8, 1.4, 4.5)
	raider_mesh.material = mat_raider
	var raider_inst := MeshInstance3D.new()
	raider_inst.mesh = raider_mesh
	raider_inst.position = Vector3(-4.5, 3.0, -10.0)
	world.add_child(raider_inst)

	var marker_target := WorldMarker.new()
	marker_target.symbol = "🎯"
	marker_target.marker_color = Color(1.0, 0.13, 0.0)
	marker_target.target_node = raider_inst
	world.add_child(marker_target)

	# 2D HUD Canvas with EventBubble bloom centered at top
	var canvas := CanvasLayer.new()
	root.add_child(canvas)

	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center_box.offset_top = 45.0
	center_box.custom_minimum_size = Vector2(1280.0, 70.0)
	canvas.add_child(center_box)

	var bubble := EventBubble.create(
		"🚨",
		"DISTRESS SIGNAL",
		"Civilian transport under attack • 450m",
		Color(1.0, 0.2, 0.27)
	)
	center_box.add_child(bubble)

	# Warm up frames
	for i in warm:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
