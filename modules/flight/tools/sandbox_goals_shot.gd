## Screenshots the sandbox's goals panel on a desktop and a phone canvas, with
## a goal half done and one just finished. Windowed:
##     godot --path . --audio-driver Dummy --script modules/flight/tools/sandbox_goals_shot.gd -- out_dir [width] [height]
## Writes `<out_dir>/goals_<w>x<h>.png`.
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
	Session.prefs["tutorial_done"] = true
	JuiceSettings.tutorial_on = false
	Campaign.launch_sandbox()
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	JuiceSettings.player_invulnerable = true
	for i in 200:
		await process_frame
	# The first-flight tutorial would hide the panel: skip it.
	if f.tutorial != null and is_instance_valid(f.tutorial):
		f.tutorial.stop(true)
	for i in 30:
		await process_frame
	var goals: SandboxGoals = f.sandbox.goals
	# One goal part way, one done.
	var st := goals.state()
	var partial := true
	for g: Dictionary in st:
		var id := String(g["id"])
		if id in ["wreck", "orbs", "yeet"] and partial:
			goals.note({"wreck": "kill", "orbs": "powerup", "yeet": "launch"}[id], 1.0)
			partial = false
	f.sandbox.note("kill", 1.0)
	for i in 30:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/goals_%dx%d.png" % [ProjectSettings.globalize_path(out_dir), size.x, size.y])
	print("wrote goals_%dx%d.png" % [size.x, size.y])
	quit(0)
