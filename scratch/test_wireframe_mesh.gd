extends SceneTree

func _initialize() -> void:
	var size := Vector2i(640, 360)
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	var world := Node3D.new()
	root.add_child(world)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 5.0)
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
	cam.current = true

	# Test 1: Generate an icosahedron or box as PRIMITIVE_LINES
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 2.0
	var box_arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = box_arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = box_arrays[Mesh.ARRAY_INDEX]

	var line_indices := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var i0 := indices[i]
		var i1 := indices[i + 1]
		var i2 := indices[i + 2]
		line_indices.append_array([i0, i1, i1, i2, i2, i0])

	var line_arrays := []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = verts
	line_arrays[Mesh.ARRAY_INDEX] = line_indices

	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 1.0, 0.35, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var inst := MeshInstance3D.new()
	inst.mesh = line_mesh
	inst.material_override = mat
	inst.rotation_degrees = Vector3(30.0, 45.0, 0.0)
	world.add_child(inst)

	for _i in 10:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png("scratch/test_wireframe.png")
	print("Saved test wireframe lines!")
	quit()
