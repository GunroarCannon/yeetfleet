## Screenshots of the flight scene under a few random sandbox systems
## ([method LevelGen.random_space]). Windowed:
##     godot --path . --audio-driver Dummy --resolution 960x540 --script scratch/space_shot.gd -- <out_dir> [seed...]
extends SceneTree

var _out := "res://debug_shots/space"
var _seeds: Array[int] = [1, 2, 3]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	if args.size() >= 2:
		_seeds.clear()
		for i in range(1, args.size()):
			_seeds.append(int(args[i]))
	_run.call_deferred()


func _run() -> void:
	for sd in _seeds:
		Session.space_setup = LevelGen.random_space(sd)
		Session.space_setup["events"] = []
		print("[space_shot] seed %d: %s" % [sd, Session.space_setup])
		var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate()
		root.add_child(f)
		current_scene = f
		await _wait(4.0)
		# Look back toward the main planet.
		var fr := f as FlightRoot
		if fr.camera_rig != null and fr.space != null:
			fr.camera_rig.set_mode(FlightCamera.Mode.FREE)
			var cam := fr.camera_node()
			cam.look_at(fr.space.planet_centre)
		await _wait(0.5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("space_%d.png" % sd))
		print("[space_shot] saved ", sd)
		f.queue_free()
		await _wait(0.5)
	quit()


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
