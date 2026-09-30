## Screenshots of the tutorial's hand for each slingshot step. Windowed:
##     godot --path . --audio-driver Dummy --resolution 960x540 --script scratch/tutorial_shot.gd -- <out_dir>
extends SceneTree

var _out := "res://debug_shots/tutorial"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	_run.call_deferred()


func _run() -> void:
	var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(f)
	current_scene = f
	await _wait(3.0)
	f.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	f.start_tutorial()
	var tut := f.tutorial
	for ev in ["launch", "tap_fire", "kill", "powerup"]:
		await _wait(0.9)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("tut_%s.png" % ev))
		print("[tut_shot] ", ev)
		tut.note(ev)
		await _wait(1.2)
	quit()


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
