## Renders a turntable contact sheet of parts (or a preset ship) to PNG so
## geometry can be eyeballed without launching the editor.
##
##     godot --path . --script modules/ship_builder/tools/shot.gd -- <out.png> [ids...]
extends SceneTree

const CELL := 420


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "shot.png" if args.is_empty() else String(args[0])
	var library := PartLibrary.instance()
	library.load_all()

	var ids: Array[String] = []
	for i in range(1, args.size()):
		ids.append(String(args[i]))
	if ids.is_empty():
		for id: Variant in library.parts:
			ids.append(String(id))
		ids.sort()

	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.48, 0.6)
	e.ambient_light_energy = 0.55
	env.environment = e
	vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, -0.9, 0.0)
	key.light_energy = 1.2
	vp.add_child(key)

	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)

	var holder := Node3D.new()
	vp.add_child(holder)

	var cols := mini(ids.size(), 4)
	var rows := int(ceil(float(ids.size()) / float(cols)))
	var sheet := Image.create(cols * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.03))

	for i in ids.size():
		var part := library.get_part(ids[i])
		if part == null:
			continue
		for c in holder.get_children():
			holder.remove_child(c)
			c.free()
		var built := PartMeshFactory.build(part, false)
		var mi := MeshInstance3D.new()
		mi.mesh = built.mesh
		var design := library.default_design()
		mi.material_override = ShipMaterials.make_part_material(design, {})
		holder.add_child(mi)

		# 3/4 view from above-front-right, framed on the part.
		var box := built.aabb
		var r := maxf(box.size.length() * 0.5, 0.2)
		var dir := Vector3(0.75, 0.45, 0.95).normalized()
		if OS.get_environment("SHOT_DIR") == "back":
			dir = Vector3(-0.75, 0.35, -0.95).normalized()
		elif OS.get_environment("SHOT_DIR") == "top":
			dir = Vector3(0.15, 1.0, 0.25).normalized()
		cam.position = box.get_center() + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.15)
		cam.look_at(box.get_center(), Vector3.UP)

		await process_frame
		await process_frame
		var img := vp.get_texture().get_image()
		img.convert(sheet.get_format())
		sheet.blit_rect(
			img, Rect2i(0, 0, CELL, CELL),
			Vector2i((i % cols) * CELL, (i / cols) * CELL)
		)
		print("  %2d/%d  %s" % [i + 1, ids.size(), ids[i]])

	sheet.save_png(out_path)
	print("wrote " + out_path)
	quit(0)
