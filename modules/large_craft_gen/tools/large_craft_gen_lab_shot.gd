## Screenshots the large_craft_gen lab.
##     godot --path . --rendering-driver opengl3 --script modules/large_craft_gen/tools/large_craft_gen_lab_shot.gd -- out.png [frames] [w] [h]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "large_craft_gen_lab.png" if args.is_empty() else String(args[0])
	var warm := 60 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/large_craft_gen/large_craft_gen_lab.tscn") as PackedScene
	var lab := packed.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	if args.size() >= 5:
		var arch_idx := int(args[4])
		lab.generator.archetype = arch_idx as LargeCraftGenerator.Archetype
		lab.generator.generate()
		lab._sync_archetype_option()
		lab._frame_camera_to_craft()
	for i in warm:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
