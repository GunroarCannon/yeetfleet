extends SceneTree

func _init() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ray_count := 16
	var max_radius := 2400.0
	for i in ray_count:
		var angle := TAU * float(i) / float(ray_count)
		var dir := Vector2(cos(angle), sin(angle))
		var perp := Vector2(-dir.y, dir.x)
		var length := max_radius * (0.6 + 0.4 * sin(float(i) * 3.7))
		var w := length * 0.08
		var v0 := Vector3.ZERO
		var v_mid := Vector3(dir.x * length * 0.3, dir.y * length * 0.3, 0.0)
		var v_left := v_mid + Vector3(perp.x * w, perp.y * w, 0.0)
		var v_right := v_mid - Vector3(perp.x * w, perp.y * w, 0.0)
		var v_tip := Vector3(dir.x * length, dir.y * length, 0.0)
		var core_col := Color(1.0, 0.9, 0.6, 0.45)
		var edge_col := Color(1.0, 0.5, 0.1, 0.0)
		# Inner quad
		st.set_color(core_col); st.add_vertex(v0)
		st.set_color(edge_col); st.add_vertex(v_left)
		st.set_color(core_col); st.add_vertex(v_mid)
		st.set_color(core_col); st.add_vertex(v0)
		st.set_color(core_col); st.add_vertex(v_mid)
		st.set_color(edge_col); st.add_vertex(v_right)
		# Outer triangle to tip
		st.set_color(core_col); st.add_vertex(v_mid)
		st.set_color(edge_col); st.add_vertex(v_left)
		st.set_color(edge_col); st.add_vertex(v_tip)
		st.set_color(core_col); st.add_vertex(v_mid)
		st.set_color(edge_col); st.add_vertex(v_tip)
		st.set_color(edge_col); st.add_vertex(v_right)
	var mesh := st.commit()
	print("Sun rays mesh committed successfully, vertex count: ", mesh.get_faces().size())
	quit()
