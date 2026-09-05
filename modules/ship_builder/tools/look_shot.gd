## Renders preset ships large, using the same environment as the builder scene,
## so material and lighting tweaks can be judged without launching the editor.
##     godot --path . --rendering-driver opengl3 --script .../look_shot.gd -- out.png [preset ids...]
extends SceneTree

const CELL := Vector2i(640, 480)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "look.png" if args.is_empty() else String(args[0])
	var ids: Array[String] = []
	for i in range(1, args.size()):
		ids.append(String(args[i]))
	if ids.is_empty():
		ids = ["lance_interceptor", "mule_freighter"]

	var library := PartLibrary.instance()
	library.load_all()

	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var scene := load("res://modules/ship_builder/ship_builder.tscn") as PackedScene
	var state := scene.get_state()
	# Pull the authored lights + environment out of the builder scene so this tool
	# never drifts from what the player actually sees.
	var probe := scene.instantiate()
	var world: Node3D = probe.get_node("Layout/Body/Center/ViewportFrame/Stage/World")
	for child in world.get_children():
		if child is DirectionalLight3D or child is WorldEnvironment:
			world.remove_child(child)
			child.owner = null
			vp.add_child(child)
	probe.free()

	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)
	var holder := Node3D.new()
	vp.add_child(holder)

	var sheet := Image.create(CELL.x * ids.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in ids.size():
		var design := library.build_preset_design(ids[i])
		if design == null:
			continue
		var view := ShipAssembler.assemble(design, library, 0.0, false, false)
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		holder.add_child(view.root)
		var box := view.aabb
		var r := maxf(box.size.length() * 0.5, 0.3)
		var dir := Vector3(0.8, 0.35, 0.9).normalized()
		var eye := box.get_center() + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05)
		cam.look_at_from_position(eye, box.get_center(), Vector3.UP)
		for f in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(sheet.get_format())
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	sheet.save_png(out_path)
	print("wrote " + out_path)
	quit(0)
