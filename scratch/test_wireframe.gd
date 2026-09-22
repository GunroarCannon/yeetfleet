extends SceneTree

func _init():
	print("Testing wireframe primitive generation...")
	var sphere := SphereMesh.new()
	sphere.radial_segments = 16
	sphere.rings = 8
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	var arrays := arr_mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var line_indices := PackedInt32Array()
	line_indices.resize(indices.size() * 2)
	var out_idx := 0
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		line_indices[out_idx] = a
		line_indices[out_idx + 1] = b
		line_indices[out_idx + 2] = b
		line_indices[out_idx + 3] = c
		line_indices[out_idx + 4] = c
		line_indices[out_idx + 5] = a
		out_idx += 6
	arrays[Mesh.ARRAY_INDEX] = line_indices
	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	print("Success! Created line mesh with ", line_mesh.surface_get_array_len(0), " vertices and ", line_indices.size(), " line indices.")
	quit()
