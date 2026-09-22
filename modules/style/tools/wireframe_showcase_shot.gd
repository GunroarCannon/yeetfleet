## wireframe_showcase_shot.gd — renders and screenshots the Vector Arcade Wireframe mode
## matching retro vector arcade monitors (Geometry Wars 3, Asteroids, Tempest).
extends SceneTree

const VectorGridScript = preload("res://modules/style/scripts/vector_grid.gd")
const WireframeUtilScript = preload("res://modules/style/scripts/wireframe_util.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "wireframe_mode_showcase.png" if args.is_empty() else String(args[0])
	var warm := 35 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)

	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	# Configure StyleManager to Vector Arcade (vector_neon profile & wireframe mode)
	var mgr := StyleManager.instance()
	mgr.set_wireframe(true)
	var neon_prof := mgr.find_profile("vector_neon")
	if neon_prof != null:
		mgr.set_profile(neon_prof)

	# Build 3D world
	var world := Node3D.new()
	world.name = "WireframeWorld"
	root.add_child(world)

	# Dark void environment with authentic CRT vector phosphor bloom
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.002, 0.002, 0.005, 1.0)
	e.ambient_light_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_node.environment = e
	world.add_child(env_node)

	# Camera with cinematic vector framing (elevated 3/4 arcade perspective)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 9.6)
	cam.fov = 58.0
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, -0.3, 0.0), Vector3.UP)
	cam.current = true

	# 1. Warped neon background grid with 3 gravity vortex wells & CRT curvature
	var grid: Node3D = VectorGridScript.create(320.0)
	grid.position = Vector3(0.0, 0.0, -42.0)
	world.add_child(grid)

	# 2. Player Ship in center (neon gold vector lines)
	var lib := PartLibrary.instance()
	lib.load_all()
	var design: ShipDesign = null
	for p in lib.presets:
		var pid := String(p.get("id", ""))
		if pid == "wedge_fighter" or pid == "balanced_fighter":
			design = lib.build_preset_design(pid)
			break
	if design == null and not lib.presets.is_empty():
		design = lib.build_preset_design(String(lib.presets[0].get("id", "")))

	var ship_view: Variant = null
	if design != null:
		design.refresh_palette()
		ship_view = ShipAssembler.assemble(design, lib, 0.0, false, false)
		ship_view.restyle(true)
		ship_view.root.position = Vector3(0.0, -0.3, 0.0)
		ship_view.root.rotation_degrees = Vector3(-8.0, 20.0, 0.0)
		ship_view.root.scale = Vector3.ONE * 0.95
		world.add_child(ship_view.root)
		
		# Convert all ship part meshes to authentic crisp vector wireframe lines (using MIX blend so overlapping parts do not blow out)
		var ship_mat := StandardMaterial3D.new()
		ship_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ship_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ship_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		ship_mat.albedo_color = Color(1.0, 0.88, 0.18) * 1.15
		ship_mat.no_depth_test = false

		var stack: Array[Node] = [ship_view.root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and n.mesh != null:
				var wm: ArrayMesh = WireframeUtilScript.to_wireframe_mesh(n.mesh, true)
				if wm != null:
					n.mesh = wm
					n.material_override = ship_mat
			for c in n.get_children():
				stack.append(c)

	# 2B. Twin Converging Neon Laser Bolts firing forward from ship's wing guns
	var laser_mat := StandardMaterial3D.new()
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	laser_mat.albedo_color = Color(1.0, 0.96, 0.35) * 2.2
	laser_mat.no_depth_test = false

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 1.0, 1.0) * 2.5
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var ship_xf: Transform3D = ship_view.root.transform if (ship_view != null and ship_view.root != null) else Transform3D()
	var aim_target: Vector3 = ship_xf * Vector3(0.0, 0.0, -22.0)
	var muzzle_left: Vector3 = ship_xf * Vector3(-1.8, -0.05, -0.4)
	var muzzle_right: Vector3 = ship_xf * Vector3(1.8, -0.05, -0.4)

	for m_pos: Vector3 in [muzzle_left, muzzle_right]:
		var l_dir: Vector3 = (aim_target - m_pos).normalized()
		var beam_len := 10.0
		# 3D crossed-ribbon tracer mesh for sleek high-visibility vector laser bolt
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rad := 0.14
		var p_start := m_pos + l_dir * 0.4
		var p_end := m_pos + l_dir * (0.4 + beam_len)
		var perp1 := l_dir.cross(ship_xf.basis.y.normalized()).normalized() * rad
		var perp2 := l_dir.cross(perp1).normalized() * rad
		# Ribbon 1 (double-sided)
		st.add_vertex(p_start - perp1); st.add_vertex(p_start + perp1); st.add_vertex(p_end + perp1 * 0.6)
		st.add_vertex(p_start - perp1); st.add_vertex(p_end + perp1 * 0.6); st.add_vertex(p_end - perp1 * 0.6)
		st.add_vertex(p_start + perp1); st.add_vertex(p_start - perp1); st.add_vertex(p_end - perp1 * 0.6)
		st.add_vertex(p_start + perp1); st.add_vertex(p_end - perp1 * 0.6); st.add_vertex(p_end + perp1 * 0.6)
		# Ribbon 2 (double-sided)
		st.add_vertex(p_start - perp2); st.add_vertex(p_start + perp2); st.add_vertex(p_end + perp2 * 0.6)
		st.add_vertex(p_start - perp2); st.add_vertex(p_end + perp2 * 0.6); st.add_vertex(p_end - perp2 * 0.6)
		st.add_vertex(p_start + perp2); st.add_vertex(p_start - perp2); st.add_vertex(p_end - perp2 * 0.6)
		st.add_vertex(p_start + perp2); st.add_vertex(p_end - perp2 * 0.6); st.add_vertex(p_end + perp2 * 0.6)
		var l_inst := MeshInstance3D.new()
		l_inst.mesh = st.commit()
		l_inst.material_override = laser_mat
		world.add_child(l_inst)

		# Glowing white core head sphere at tip of laser bolt
		var head_sphere := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		head_sphere.mesh = sm
		head_sphere.material_override = core_mat
		head_sphere.position = p_end
		world.add_child(head_sphere)

		# Muzzle flash ring
		var f_mesh := ImmediateMesh.new()
		f_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var f_segs := 16
		var f_r := 0.28
		for s in f_segs:
			var a1 := TAU * float(s) / float(f_segs)
			var a2 := TAU * float(s + 1) / float(f_segs)
			var v1: Vector3 = ship_xf.basis * Vector3(cos(a1) * f_r, sin(a1) * f_r, 0.0)
			var v2: Vector3 = ship_xf.basis * Vector3(cos(a2) * f_r, sin(a2) * f_r, 0.0)
			f_mesh.surface_add_vertex(m_pos + v1)
			f_mesh.surface_add_vertex(m_pos + v2)
		f_mesh.surface_end()
		var f_inst := MeshInstance3D.new()
		f_inst.mesh = f_mesh
		f_inst.material_override = laser_mat
		world.add_child(f_inst)

	# 3. Geometric Nested Polyhedra Gems (matching Geometry Wars reference photo)
	# 3A. Green Nested Icosahedron Gem (top-left) with inner rotating core
	var poly_green := MeshInstance3D.new()
	poly_green.mesh = WireframeUtilScript.create_nested_polyhedron(1.55, 0.80)
	poly_green.material_override = WireframeUtilScript.create_vector_material(Color(0.12, 1.0, 0.35), 1.5)
	poly_green.position = Vector3(-6.8, 3.2, -4.5)
	poly_green.rotation_degrees = Vector3(22.0, 35.0, 12.0)
	world.add_child(poly_green)

	# 3B. Fiery Orange Nested Star Gem (mid-left) with inner star
	var poly_orange := MeshInstance3D.new()
	poly_orange.mesh = WireframeUtilScript.create_nested_star_gem(1.40, 0.72)
	poly_orange.material_override = WireframeUtilScript.create_vector_material(Color(1.0, 0.45, 0.05), 1.5)
	poly_orange.position = Vector3(-6.8, -0.2, -4.0)
	poly_orange.rotation_degrees = Vector3(-18.0, 48.0, -10.0)
	world.add_child(poly_orange)

	# 3C. Pure White Glowing Gyro (between ship and orange gem)
	var poly_white := MeshInstance3D.new()
	poly_white.mesh = WireframeUtilScript.create_dodecahedron(0.95)
	poly_white.material_override = WireframeUtilScript.create_vector_material(Color(1.0, 1.0, 1.0), 1.8)
	poly_white.position = Vector3(-3.8, 0.8, -3.2)
	poly_white.rotation_degrees = Vector3(15.0, 25.0, 45.0)
	world.add_child(poly_white)

	# 3D. Cyan Nested Dodecahedron Gem (bottom-center)
	var poly_cyan := MeshInstance3D.new()
	poly_cyan.mesh = WireframeUtilScript.create_nested_polyhedron(1.75, 0.88)
	poly_cyan.material_override = WireframeUtilScript.create_vector_material(Color(0.0, 0.95, 1.0), 1.5)
	poly_cyan.position = Vector3(-1.0, -3.2, -4.2)
	poly_cyan.rotation_degrees = Vector3(32.0, -20.0, 15.0)
	world.add_child(poly_cyan)

	# 3E. Magenta Nested Star Gem (mid-right)
	var poly_magenta := MeshInstance3D.new()
	poly_magenta.mesh = WireframeUtilScript.create_nested_star_gem(1.55, 0.78)
	poly_magenta.material_override = WireframeUtilScript.create_vector_material(Color(1.0, 0.10, 0.70), 1.5)
	poly_magenta.position = Vector3(6.8, 0.4, -4.8)
	poly_magenta.rotation_degrees = Vector3(-25.0, -35.0, 10.0)
	world.add_child(poly_magenta)

	# 4. Enemies & Vector Swarms (Geometry Wars retro arcade action)
	# 4A. Cluster of Yellow Rosette Gears (lower-right)
	for i in 4:
		var gear := MeshInstance3D.new()
		gear.mesh = WireframeUtilScript.create_vector_gear(0.78, 0.46, 14)
		gear.material_override = WireframeUtilScript.create_vector_material(Color(1.0, 0.82, 0.12), 1.5)
		var offset := Vector3(3.2 + float(i % 2) * 0.95, -2.2 + float(i / 2) * 0.85, -3.8 - float(i) * 0.2)
		gear.position = offset
		gear.rotation_degrees = Vector3(0.0, 0.0, float(i) * 28.0)
		world.add_child(gear)

	# 4B. Curving Swarm of Cyan Vector Crosses (upper-right arch, matching reference photo)
	var cyan_mat := WireframeUtilScript.create_vector_material(Color(0.0, 0.95, 1.0), 1.5)
	for i in 14:
		var cross := MeshInstance3D.new()
		cross.mesh = WireframeUtilScript.create_vector_cross(0.38)
		cross.material_override = cyan_mat
		var t_step := float(i) / 14.0
		var cx := 2.6 + sin(t_step * PI * 0.85) * 2.2
		var cy := 3.8 - t_step * 3.4
		var cz := -4.2 + t_step * 0.8
		cross.position = Vector3(cx, cy, cz)
		cross.rotation_degrees = Vector3(0.0, 0.0, float(i) * 15.0)
		world.add_child(cross)

	# 4C. Pink/Magenta Sparks Stream (center-down stream)
	var pink_mat := WireframeUtilScript.create_vector_material(Color(1.0, 0.15, 0.75), 1.5)
	for i in 6:
		var p_spark := MeshInstance3D.new()
		p_spark.mesh = WireframeUtilScript.create_vector_cross(0.32)
		p_spark.material_override = pink_mat
		var py := 3.2 - float(i) * 0.72
		var px := -0.2 + sin(float(i) * 0.9) * 0.25
		p_spark.position = Vector3(px, py, -3.6)
		p_spark.rotation_degrees = Vector3(0.0, 0.0, 45.0 + float(i) * 20.0)
		world.add_child(p_spark)

	# 4D. Vector Arrowhead Dart Flyers (orange and lime curving fighters)
	var dart1 := MeshInstance3D.new()
	dart1.mesh = WireframeUtilScript.create_vector_dart(0.85)
	dart1.material_override = WireframeUtilScript.create_vector_material(Color(1.0, 0.50, 0.05), 1.6)
	dart1.position = Vector3(6.2, -2.2, -4.0)
	dart1.rotation_degrees = Vector3(-15.0, -115.0, 20.0)
	world.add_child(dart1)

	var dart2 := MeshInstance3D.new()
	dart2.mesh = WireframeUtilScript.create_vector_dart(0.70)
	dart2.material_override = WireframeUtilScript.create_vector_material(Color(0.20, 1.0, 0.40), 1.6)
	dart2.position = Vector3(-4.5, 3.8, -4.5)
	dart2.rotation_degrees = Vector3(10.0, 65.0, -15.0)
	world.add_child(dart2)

	# 4E. Floating Vector Diamonds & Triangles
	var green_mat := WireframeUtilScript.create_vector_material(Color(0.20, 1.0, 0.40), 1.4)
	for i in 5:
		var dia := MeshInstance3D.new()
		dia.mesh = WireframeUtilScript.create_vector_diamond(0.42)
		dia.material_override = green_mat
		dia.position = Vector3(-8.5 - float(i) * 0.4, 1.0 + float(i) * 0.5, -4.5)
		dia.rotation_degrees = Vector3(float(i) * 25.0, float(i) * 35.0, 0.0)
		world.add_child(dia)

	# 4F. Vector Explosion Particle Sparkles (upper right burst)
	var spark_mat := WireframeUtilScript.create_vector_material(Color(1.0, 0.90, 0.30), 1.8)
	for i in 12:
		var sp := MeshInstance3D.new()
		sp.mesh = WireframeUtilScript.create_vector_diamond(0.22)
		sp.material_override = spark_mat
		var sp_ang := float(i) * (TAU / 12.0)
		var sp_r := randf_range(0.6, 1.5)
		sp.position = Vector3(4.8 + cos(sp_ang) * sp_r, 3.2 + sin(sp_ang) * sp_r, -4.5)
		world.add_child(sp)

	# Warm frames to let the viewport, shader, and bloom stabilize
	for _frame in warm:
		await process_frame

	var img := root.get_texture().get_image()
	if img != null:
		var err := img.save_png(out_path)
		if err == OK:
			print("Saved wireframe showcase screenshot to ", out_path)
		else:
			push_error("Failed to save screenshot: " + str(err))
	mgr.set_wireframe(false)
	StyleSettings.set_wireframe_mode(false)
	quit(0)
