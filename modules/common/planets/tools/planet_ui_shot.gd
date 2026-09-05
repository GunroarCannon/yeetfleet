## Screenshots the live planet editor scene.
##     godot --path . --rendering-driver opengl3 --script <this> -- out.png [frames] [w] [h]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "planet_ui.png" if args.is_empty() else String(args[0])
	var warm := 40 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/common/planets/planet_editor.tscn") as PackedScene
	var b := packed.instantiate()
	root.add_child(b)
	for i in warm:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
