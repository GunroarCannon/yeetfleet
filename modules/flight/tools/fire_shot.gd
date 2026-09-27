## Screenshots the player's guns in action: a target parked ahead and a
## little off the nose, each of a few weapons fired for a moment.
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy --script modules/flight/tools/fire_shot.gd -- out_dir [tag]
##
## Windowed. Writes `<out_dir>/fire_<tag>_<weapon index>.png`. Enemy fire and
## player damage are switched off in memory only.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "." if args.is_empty() else String(args[0])
	var tag := String(args[1]) if args.size() > 1 else "shot"
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	JuiceSettings.enemies_passive = true
	JuiceSettings.player_invulnerable = true
	var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(f)
	for i in 20:
		await process_frame
	f.get_node("Ui/Coach").visible = false
	f.scenarios.start(FlightScenarios.preset("practice"))
	for i in 10:
		await process_frame
	f.toggle_lock()
	for wi: int in [0, 1, 4]:
		f.set_weapon_index(wi)
		f.set_firing(true)
		for i in 36:
			await process_frame
		var path := out_dir.path_join("fire_%s_%d.png" % [tag, wi])
		root.get_texture().get_image().save_png(path)
		print("wrote ", path)
		f.set_firing(false)
		for i in 20:
			await process_frame
	quit(0)
