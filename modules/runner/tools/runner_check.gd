## The endless run end to end: runner.tscn boots straight into a run, the
## ship is pulled down the track and speeds up, the HUD shows the speed as a
## meter, a boost ring threaded gives speed, a rock hit is felt and recycled,
## a fighter wave comes, the ship going down ends the run (best kept) and a
## new one starts after the respawn, and stop hands the scene back.
##
##     godot --path . --headless --audio-driver Dummy --script modules/runner/tools/runner_check.gd
extends SceneTree

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(what)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	JuiceSettings._loaded = true
	JuiceSettings.yeet_combat = false
	JuiceSettings.kill_cam = false
	# Only the steps that test damage let it through.
	JuiceSettings.player_invulnerable = true
	print("── endless run ──────────────────────────────────────────")
	var scene := (load("res://modules/runner/runner.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(scene)
	await _ticks(20)
	if not is_equal_approx(scene.time_scale(), 1.0):
		scene.set_time_scale(1.0)
	scene.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	var run := scene.get_node_or_null("EndlessRunner") as EndlessRunner
	_check(run != null and run.is_running(), "runner.tscn boots straight into a run")
	if run == null:
		_finish()
		return
	scene._hud.set_mobile_layout(true)
	await _ticks(5)
	var mob := scene._hud.get_node_or_null("MobileHud") as MobileHud
	_check(mob != null and mob.speed_meter_max > 0.0, "the mobile HUD shows speed as a meter")

	var model := scene.model
	model.command.throttle = 0.0
	var fv := model.frame_velocity
	_check(fv.dot(run._dir) > run._top() * 0.8, "the ship is pulled down the track")
	var s0 := run.speed
	await _ticks(180)
	print("  3 s in: %.0f m, pull %.0f → %.0f m/s" % [run.distance, s0, run.speed])
	_check(run.distance > 150.0, "it covers ground (> 150 m in 3 s)")
	_check(run.speed > s0, "and speeds up")

	# A ring laid just ahead, on the ship's line.
	var ring: Dictionary = run._rings[0]
	var s := (model.global_position - run._origin).dot(run._dir)
	var off := model.global_position - run._origin - run._dir * s
	ring["s"] = s + 40.0
	ring["pos"] = run._origin + run._dir * (s + 40.0) + off
	run._boost = 0.0
	await _ticks(40)
	_check(run._boost > 0.0, "threading a boost ring gives speed")

	# A rock parked on the ship.
	JuiceSettings.player_invulnerable = false
	scene._grace_until_ms = 0
	var hp0 := scene.player_hp + scene.player_shield
	var rock: Dictionary = run._rocks[0]
	s = (model.global_position - run._origin).dot(run._dir)
	rock["s"] = s + 5.0
	rock["pos"] = model.global_position + run._dir * 5.0
	rock["radius"] = 12.0
	await _ticks(3)
	JuiceSettings.player_invulnerable = true
	_check(scene.player_hp + scene.player_shield < hp0, "a rock hit hurts")
	_check(float(rock["s"]) > s + 1000.0, "and the rock is recycled ahead")

	# Far enough for the first wave.
	var t := 0
	while run._wave_ships.is_empty() and t < 900:
		await physics_frame
		t += 1
	_check(not run._wave_ships.is_empty(), "a fighter wave comes down the track")

	# Down goes the ship.
	var went := run.distance
	scene._grace_until_ms = 0
	JuiceSettings.player_invulnerable = false
	# The hull scales with the design: hit it until it goes.
	for i in 6:
		if not scene.is_player_dead():
			scene.take_damage((scene.player_max_hp + scene.player_max_shield) * 10.0 + 1000.0)
	JuiceSettings.player_invulnerable = true
	await _ticks(3)
	_check(run.state == EndlessRunner.State.OVER, "the ship going down ends the run")
	_check(EndlessRunner.best >= went, "and the best run is kept")
	scene.respawn_player_ship()
	await _ticks(int(EndlessRunner.RESTART_DELAY * 60.0) + 30)
	_check(run.is_running() and run.distance < went, "a new run starts after the respawn")

	run.stop()
	await _ticks(3)
	_check(scene.model.frame_velocity == Vector3.ZERO, "stop lets go of the ship")
	_check(mob.speed_meter_max == 0.0, "and the speed number comes back")
	_finish()


func _finish() -> void:
	JuiceSettings.load_from_disk()
	Session.prefs["mobile_layout"] = false
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
	else:
		print("── FAIL: %s" % ", ".join(_failures))
	quit(0 if _failures.is_empty() else 1)
