class_name ObjExporter


static func save(md: MeshData, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	
	f.store_string("# Alien Face Generator - OBJ Export\n")
	f.store_string("# Vertices: %d, Triangles: %d\n\n" % [md.verts.size(), md.tri_count()])
	
	# Vertices
	for i in range(md.verts.size()):
		f.store_string("v %.6f %.6f %.6f\n" % [md.verts[i].x, md.verts[i].y, md.verts[i].z])
	
	f.store_string("\n")
	
	# Normals
	for i in range(md.normals.size()):
		f.store_string("vn %.6f %.6f %.6f\n" % [md.normals[i].x, md.normals[i].y, md.normals[i].z])
	
	f.store_string("\n")
	
	# UVs
	for i in range(md.uvs.size()):
		f.store_string("vt %.6f %.6f\n" % [md.uvs[i].x, md.uvs[i].y])
	
	f.store_string("\n")
	
	# Faces (1-indexed in OBJ format)
	for i in range(0, md.indices.size(), 3):
		var a := md.indices[i] + 1
		var b := md.indices[i + 1] + 1
		var c := md.indices[i + 2] + 1
		f.store_string("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % [a, a, a, b, b, b, c, c, c])
	
	f.close()
	return OK
