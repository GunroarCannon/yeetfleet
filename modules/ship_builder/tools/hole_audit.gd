## Renders every part twice -- back-faces culled, then not culled -- and reports
## how many pixels differ. A part with holes shows its interior through the gap,
## so the two renders diverge; a watertight part renders identically.
##
##     godot --path . --rendering-driver opengl3 --script .../hole_audit.gd
extends SceneTree

const CELL := 300


func _initialize() -> void:
	var library := PartLibrary.instance()
	library.load_all()
	var ids: Array[String] = []
	for id: Variant in library.parts:
		ids.append(String(id))
	ids.sort()

	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)

	# Flat unshaded so any difference is geometric, not a lighting artifact.
	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.albedo_color = Color.WHITE
	solid.cull_mode = BaseMaterial3D.CULL_BACK
	var both := StandardMaterial3D.new()
	both.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	both.albedo_color = Color.WHITE
	both.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Six viewing directions, so a hole facing any way is caught.
	var dirs := [
		Vector3(0.75, 0.45, 0.95), Vector3(-0.75, 0.45, -0.95),
		Vector3(0.0, 1.0, 0.05), Vector3(0.0, -1.0, 0.05),
		Vector3(1.0, 0.05, 0.0), Vector3(0.0, 0.05, 1.0),
	]
	var worst: Array[Dictionary] = []
	for id: String in ids:
		var part := library.get_part(id)
		var built := PartMeshFactory.build(part, false)
		mi.mesh = built.mesh
		var box := built.aabb
		var r := maxf(box.size.length() * 0.5, 0.15)
		var total_missing := 0
		var total_solid := 0
		for d: Vector3 in dirs:
			cam.position = box.get_center() + d.normalized() * (r / tan(deg_to_rad(22.5)) * 1.1)
			cam.look_at(box.get_center(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD)
			mi.material_override = solid
			await process_frame
			await process_frame
			var a := vp.get_texture().get_image()
			mi.material_override = both
			await process_frame
			await process_frame
			var b := vp.get_texture().get_image()
			for y in range(0, CELL, 2):
				for x in range(0, CELL, 2):
					var lit_a := a.get_pixel(x, y).r > 0.5
					var lit_b := b.get_pixel(x, y).r > 0.5
					if lit_b:
						total_solid += 1
					if lit_b and not lit_a:
						total_missing += 1
		if total_missing > 0:
			worst.append({
				"id": id,
				"pct": 100.0 * float(total_missing) / float(maxi(total_solid, 1)),
				"px": total_missing,
			})
	worst.sort_custom(func(x, y): return float(x["pct"]) > float(y["pct"]))
	print("── Holes (silhouette pixels showing no front face) ───────")
	for w in worst:
		print("  %-24s %5.1f%%  (%d px)" % [w["id"], w["pct"], w["px"]])
	print("  %d of %d parts have holes" % [worst.size(), ids.size()])
	quit(0)
