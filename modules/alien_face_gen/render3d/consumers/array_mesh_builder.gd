class_name ArrayMeshBuilder


static func build(md: MeshData, style: StyleBase3D, p: FacePalette, g: FaceGenome) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	
	if md.verts.size() == 0:
		return mesh
	
	# Group vertices by surface
	if md.surfaces.is_empty():
		# No surfaces defined: build as one surface
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(md.verts.size()):
			st.set_normal(md.normals[i])
			st.set_color(md.colors[i])
			st.set_uv(md.uvs[i])
			st.add_vertex(md.verts[i])
		st.commit(mesh)
		return mesh
	
	# Build each surface separately
	for surface_info in md.surfaces:
		var start: int = surface_info["start"]
		var count: int = surface_info["count"]
		var hint: StringName = surface_info["material_hint"]
		
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		
		for i in range(start, mini(start + count, md.indices.size())):
			var vi := md.indices[i]
			st.set_normal(md.normals[vi])
			st.set_color(md.colors[vi])
			st.set_uv(md.uvs[vi])
			st.add_vertex(md.verts[vi])
		
		# Set material
		var mat := style.material_for(hint, p, g)
		if mat:
			st.set_material(mat)
		
		st.commit(mesh)
	
	return mesh
