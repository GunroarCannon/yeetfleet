## Screenshots the live builder scene.
##     godot --path . --rendering-driver opengl3 --script .../ui_shot.gd -- out.png [frames] [w] [h]
##
## The width and height are the point of the tool as much as the picture is: the
## builder has to hold together from a phone to a desktop, and the only honest way
## to check that is to render it at both.
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "ui.png" if args.is_empty() else String(args[0])
	var warm := 30 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/ship_builder/ship_builder.tscn") as PackedScene
	var b := packed.instantiate()
	root.add_child(b)
	for i in warm:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
