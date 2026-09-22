extends SceneTree

func _initialize() -> void:
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	
	var packed := load("res://modules/destruction_lab/destruction_lab.tscn") as PackedScene
	var lab = packed.instantiate() as DestructionLabRoot
	root.add_child(lab)
	
	await process_frame
	await process_frame
	
	# Open Explosion Studio modal
	lab.toggle_explosion_studio()
	
	# Trigger an explosion for visual preview
	lab._test_detonate_current_slot()
	
	for i in 40:
		await process_frame
		
	var img := root.get_texture().get_image()
	var out_path := "C:/Users/hmmm/.gemini/antigravity-cli/brain/a02a8ed2-469a-4067-9500-88459d681481/explosion_studio_showcase.png"
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
