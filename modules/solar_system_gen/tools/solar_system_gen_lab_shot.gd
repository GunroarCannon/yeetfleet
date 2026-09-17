## Screenshots the solar_system_gen lab.
##     godot --path . --rendering-driver opengl3 --script modules/solar_system_gen/tools/solar_system_gen_lab_shot.gd -- out.png [frames] [w] [h]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "solar_system_gen_lab.png" if args.is_empty() else String(args[0])
	var warm := 60 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/solar_system_gen/solar_system_gen_lab.tscn") as PackedScene
	var lab := packed.instantiate()
	root.add_child(lab)
	await process_frame
	var extra := "" if args.size() < 5 else String(args[4])
	if extra == "near_belt":
		lab._on_spawn_near_belt_pressed()
	elif extra == "wide_belt":
		lab._on_spawn_wide_belt_pressed()
	elif extra == "close":
		lab._orbit_dist = 1400.0
	elif extra == "realistic":
		var idx: int = lab._distance_index_for(14.0)
		lab._mode_option.select(idx)
		lab._on_distance_preset_selected(idx)
	for i in warm:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
