## Screenshots the real mobile HUD ([MobileHud]) in the flight test bed, one
## PNG per profile, at a phone's landscape aspect.
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy --script modules/flight/tools/mobile_hud_shot.gd -- out_dir [width] [height]
##
## Windowed (needs a real renderer). Writes `<out_dir>/mobile_hud_<profile>.png`.
## The active profile and the mobile-layout pref are put back afterwards.
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
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	for i in 30:
		await process_frame
	f.get_node("Ui/Coach").visible = false
	JuiceSettings.player_invulnerable = true
	f.player_hp = f.player_max_hp * 0.62
	f.player_shield = f.player_max_shield * 0.45
	f.set_throttle(0.7)
	var was_active := MobileHudProfiles.active
	f._hud.set_mobile_layout(true)
	for id: String in MobileHudProfiles.profile_ids():
		MobileHudProfiles.active = id
		MobileHudProfiles.revision += 1
		for i in 45:
			await process_frame
		var path := out_dir.path_join("mobile_hud_%s.png" % id)
		root.get_texture().get_image().save_png(path)
		print("wrote ", path)
	# The juice and the schemes, on the comic look: a hull hit mid-burst, boost,
	# then each touch scheme and the mirrored layout. Set in memory only (no
	# setter), so the player's saved choices are untouched.
	MobileHudProfiles.active = "comic"
	var was_scheme := MobileHudProfiles.scheme
	var was_swap := MobileHudProfiles.swap_sides
	MobileHudProfiles.revision += 1
	for i in 20:
		await process_frame
	f.player_hp -= f.player_max_hp * 0.18
	for i in 7:
		await process_frame
	_save(out_dir, "hit")
	f.set_boosting(true)
	for i in 30:
		await process_frame
	_save(out_dir, "boost")
	f.set_boosting(false)
	for shot: Array in [["simple", false], ["pro", false], ["pro", true]]:
		MobileHudProfiles.scheme = String(shot[0])
		MobileHudProfiles.swap_sides = bool(shot[1])
		MobileHudProfiles.revision += 1
		for i in 30:
			await process_frame
		_save(out_dir, "scheme_%s%s" % [shot[0], "_swapped" if shot[1] else ""])
	MobileHudProfiles.scheme = was_scheme
	MobileHudProfiles.swap_sides = was_swap
	MobileHudProfiles.active = was_active
	Session.prefs["mobile_layout"] = false
	JuiceSettings.load_from_disk()
	quit(0)


func _save(out_dir: String, tag: String) -> void:
	var path := out_dir.path_join("mobile_hud_%s.png" % tag)
	root.get_texture().get_image().save_png(path)
	print("wrote ", path)
