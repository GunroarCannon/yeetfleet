## Screenshots a sandbox flight as a player sees it (debug mode off): the
## desktop HUD, the phone HUD, and the ship parked near the main planet (the
## planet call-out). Windowed (needs a real renderer):
##     godot --path . --audio-driver Dummy --script modules/flight/tools/sandbox_shot.gd -- out_dir [width] [height]
## Writes `<out_dir>/sandbox_<tag>.png`. The mobile-layout pref is put back.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "." if args.is_empty() else String(args[0])
	var size := Vector2i(1600, 740)
	if args.size() >= 3:
		size = Vector2i(int(args[1]), int(args[2]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	Session.debug_mode = false
	Campaign.launch_sandbox()
	var was_mobile := bool(Session.prefs.get("mobile_layout", false))
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	JuiceSettings.player_invulnerable = true
	for i in 260:
		await process_frame
	_save(out_dir, "desktop")
	f._hud.set_mobile_layout(true)
	for i in 40:
		await process_frame
	_save(out_dir, "phone")
	# Parked a little way off the main world, looking at it.
	var lm: Array[Dictionary] = f.landmarks()
	if not lm.is_empty():
		var p: Vector3 = lm[0]["position"]
		var r := float(lm[0]["radius"])
		# Off to one side of where the camera looks, so the world sits in view.
		var cam_fwd := -f.camera_node().global_transform.basis.z
		var at := p - cam_fwd * r * 2.6 + f.camera_node().global_transform.basis.x * r * 0.9
		f.model.global_transform = Transform3D(Basis.looking_at(cam_fwd, Vector3.UP), at)
		f.model.velocity = Vector3.ZERO
		f.model.reset_physics_interpolation()
		for i in 90:
			f.model.velocity = Vector3.ZERO
			await process_frame
		_save(out_dir, "planet")
	# A hostile dreadnought, guns going.
	JuiceSettings.player_invulnerable = true
	var gen := f.spawn_large_craft(LargeCraftGenerator.Archetype.DREADNOUGHT, Vector3.ZERO, FlightRoot.CraftSize.DEFAULT)
	if gen != null:
		var mega := f.mega_of(gen)
		mega._gun_clock = 0.0
		for i in 150:
			f.model.velocity = Vector3.ZERO
			await process_frame
		_save(out_dir, "warship")
	Session.prefs["mobile_layout"] = was_mobile
	JuiceSettings.load_from_disk()
	quit(0)


func _save(out_dir: String, tag: String) -> void:
	var path := out_dir.path_join("sandbox_%s.png" % tag)
	root.get_texture().get_image().save_png(path)
	print("wrote ", path)
