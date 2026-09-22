extends SceneTree

func _initialize() -> void:
	var size := Vector2i(640, 360)
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	var world := Node3D.new()
	root.add_child(world)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 10.0)
	world.add_child(cam)
	cam.current = true

	var qm := QuadMesh.new()
	qm.size = Vector2(100.0, 100.0)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scratch/test_uv.gdshader")
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, -10.0)
	world.add_child(mi)

	for _i in 5:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png("scratch/uv_test.png")
	print("Saved scratch/uv_test.png")
	quit()
