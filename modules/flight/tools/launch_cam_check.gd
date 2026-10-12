## Headless check: a sling launch thrown along the line the camera already
## looks down (camera behind the ship) must not turn the view. Records the
## camera's heading every frame from the touch-down to a second after the
## launch and fails when it swings.
##
##     godot --path . --headless --audio-driver Dummy --fixed-fps 60 --script modules/flight/tools/launch_cam_check.gd
##
## Run at --fixed-fps 60 and 144. Settings are changed in memory only.
extends SceneTree

const MAX_SWING_DEG := 6.0

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	JuiceSettings._loaded = true
	JuiceSettings.enemy_shields = false
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	_root.set_time_scale(1.0)
	_root.get_node("Ui/Coach").visible = false
	var sp := _root.ensure_ai_spawner()
	sp.auto_fleet = false
	sp.kill_all()
	JuiceSettings.player_invulnerable = true
	if _root.gravity != null:
		_root.gravity.mode = GravitySystem.GravityMode.OFF
	print("── launch camera check ───────────────────────────────────")
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	await _launch_case("pulled straight down (thrown along the view)", Vector2(0.0, 1.0))
	await _launch_case("pulled down a little left", Vector2(-0.25, 1.0))
	# The player has swung the camera round already and throws along what they
	# look at: the frame must hold, not turn onto the flight (it used to, and
	# the view ended up looking from the ship's front).
	await _launch_case("view swung 90°, thrown along the view", Vector2(0.0, 1.0), 90.0)
	await _launch_case("view swung 180° (ship's front), thrown along the view", Vector2(0.0, 1.0), 180.0)
	await _face_view_case()
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		quit(1)


func _launch_case(label: String, pull_dir: Vector2, swing_deg := 0.0) -> void:
	_root.model.halt()
	_root.camera_rig.user_yaw = swing_deg
	await _seconds(3.0)
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	var cam := _root.camera_node()
	var s := pilot.ship_screen_pos()
	var magnet := JuiceSettings.magnet_strength
	JuiceSettings.magnet_strength = 0.0
	var start_fwd := -cam.global_transform.basis.z
	var worst := 0.0
	var worst_roll := 0.0
	var start_up := cam.global_transform.basis.y
	var trace := PackedStringArray()
	var finger := s + pull_dir.normalized() * _short() * 0.3
	_touch(s, true)
	await process_frame
	_drag(finger)
	var launched := false
	for i in 60 + 90:
		await process_frame
		if i == 20:
			_touch(finger, false)
			launched = true
		var b := cam.global_transform.basis
		var turn := rad_to_deg((-b.z).angle_to(start_fwd))
		var roll := rad_to_deg(b.y.angle_to(start_up))
		worst = maxf(worst, turn)
		worst_roll = maxf(worst_roll, roll)
		if i % 10 == 0:
			var rig := _root.camera_rig
			var ref_fwd := -Basis(rig._ref_quat).z
			var ld := pilot._launch_dir
			trace.append("%d:%.1f(ref %.1f, vh %.1f, beh %.2f, launch %.1f, la %.0f, mf %.0f, cal %.2f)" % [i, turn, rad_to_deg(ref_fwd.angle_to(start_fwd)), rad_to_deg(rig.view_heading().angle_to(start_fwd)), rig._behind,
				rad_to_deg(ld.angle_to(start_fwd)) if ld != Vector3.ZERO else -1.0, rig._look_ahead.length(), rig._motion_focus.length(), rig._calm()])
	print("  %s: camera turned at most %.1f° (view roll %.1f°), launched %s" % [label, worst, worst_roll, launched])
	print("    turn by frame: %s" % " ".join(trace))
	_report("camera does not rotate on launch: " + label, launched and worst < MAX_SWING_DEG)
	run.catch_ship()
	JuiceSettings.magnet_strength = magnet
	await _seconds(1.0)


## Camera swung to the ship's front: the resting ship turns to face where the
## camera looks, and does nothing of the sort with the dial off.
func _face_view_case() -> void:
	var rig := _root.camera_rig
	var pilot := _root.pilot() as SlingshotPilot
	_root.model.halt()
	await _seconds(1.0)
	rig.user_yaw = 0.0
	await _seconds(2.0)
	# Nose along the view, then the camera swung to its front.
	_root.model.global_transform.basis = Basis.looking_at(rig.view_heading(), Vector3.UP)
	await _seconds(0.5)
	var nose := -_root.active_ship_node().global_transform.basis.z
	JuiceSettings.cam_face_view = false
	rig.user_yaw = 180.0
	await _seconds(3.0)
	var off_dial := rad_to_deg((-_root.active_ship_node().global_transform.basis.z).angle_to(rig.view_heading()))
	_report("dial off: the nose stays put (%.0f° off the view)" % off_dial, off_dial > 120.0)
	JuiceSettings.cam_face_view = true
	await _seconds(6.0)
	var on := rad_to_deg((-_root.active_ship_node().global_transform.basis.z).angle_to(rig.view_heading()))
	_report("camera at the ship's front: the nose turns to the view (%.0f° off)" % on, on < 25.0)
	JuiceSettings.cam_face_view = true
	rig.user_yaw = 0.0
	await _seconds(2.0)
	if nose == Vector3.ZERO or pilot == null:
		_report("setup", false)


func _short() -> float:
	var s := _root.get_viewport().get_visible_rect().size
	return minf(s.x, s.y)


func _touch(pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = down
	_root._unhandled_input(e)


func _drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	_root._unhandled_input(e)


func _seconds(s: float) -> void:
	for i in int(ceilf(s * Engine.physics_ticks_per_second)):
		await physics_frame


func _report(label: String, ok: bool) -> void:
	print("  %-62s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)
