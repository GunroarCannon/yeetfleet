## Headless check for the one-thumb movement profiles: swipe (heading, dash,
## cruise, tap fire at the priority target, hold boost/warp, course correction,
## ramming) and slingshot (launch opposite the pull, camera pull-out, bounce
## toward the next body, run end and camera return, catch, tap to shoot, orbit
## ends the run), plus AI ships fighting by slingshot. Also: camera gestures
## (a drag off the ship swings the view, from the ship flies; pinch, twist),
## the swipe profile's pulled-out camera and 3D arrows, the slingshot camera
## ignoring the hull's spin, the FPS profile (stick = move and speed, drag =
## look), and the player's shots never flying slow. Input goes in as real
## InputEventScreenTouch/Drag through FlightRoot._unhandled_input.
##
##     godot --path . --headless --audio-driver Dummy --fixed-fps 60 --script modules/flight/tools/move_profile_check.gd
##
## Run at --fixed-fps 60 and 144. Settings are changed in memory only.
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []
var _ended_in_orbit := false
## The camera's basis when the last swipe was released (what it maps through).
var _cam_at_release := Basis()


func _initialize() -> void:
	JuiceSettings._loaded = true
	# Enemy shield veils soak hits; these checks measure hull damage.
	JuiceSettings.enemy_shields = false
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	# The HUD checks below are about the desktop widgets: take the desktop
	# layout whatever the saved pref says (it is put back in _finish).
	_was_mobile = bool(Session.prefs.get("mobile_layout", false))
	_root._hud.set_mobile_layout(false)
	_root.set_time_scale(1.0)
	_root.get_node("Ui/Coach").visible = false
	print("── movement profile check ────────────────────────────────")
	var sp := _root.ensure_ai_spawner()
	sp.auto_fleet = false
	sp.kill_all()
	JuiceSettings.player_invulnerable = true
	if _root.gravity != null:
		_root.gravity.mode = GravitySystem.GravityMode.OFF
	await _frames(3)

	await _check_swipe_heading_and_dash()
	await _check_swipe_tap_priority(sp)
	await _check_swipe_hold()
	await _check_swipe_course_correction(sp)
	await _check_swipe_ram(sp)
	await _check_sling_launch_and_end()
	await _check_sling_bounce_seek(sp)
	await _check_sling_catch()
	await _check_sling_steady_aim()
	await _check_sling_tap_fire(sp)
	_check_sling_orbit_ends_run()
	await _check_ai_sling(sp)
	await _check_hud_hides_controls()
	await _check_swipe_camera_gestures()
	await _check_sling_steady_camera()
	await _check_fps_profile()
	await _check_player_shots_fast()
	await _check_magnet_and_reach(sp)
	await _check_markers_and_telegraph(sp)
	await _check_sling_aim_styles(sp)
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	_report("classic profile hands the ship back", not _root.model.external_drive and _root.pilot() == null)
	_finish()


# --- Swipe ---

func _check_swipe_heading_and_dash() -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SWIPE)
	_root.model.halt()
	await _frames(3)
	var pilot := _root.pilot() as SwipePilot
	var centre := _swipe_start()
	await _swipe(centre, centre + Vector2(short() * 0.45, 0.0), 4)
	var cam_right := _cam_at_release.x
	await _seconds(0.6)
	var v := _root.model.velocity
	var ang := rad_to_deg(v.angle_to(cam_right))
	var cruise := _root.model.top_speed * JuiceSettings.swipe_speed_mult * JuiceSettings.swipe_cruise
	print("  swipe right: path %.1f° off camera-right, speed %.0f (cruise %.0f)" % [ang, v.length(), cruise])
	_report("swipe: the ship flies the swiped way (view plane)", ang < 10.0)
	_report("swipe: a long quick swipe dashes above cruise", v.length() > cruise * 1.3)
	await _seconds(3.5)
	var settled := _root.model.velocity.length()
	print("  after 4 s: %.0f m/s" % settled)
	_report("swipe: the dash bleeds off to the cruise floor", absf(settled - cruise) < cruise * 0.15)
	var nose_off := rad_to_deg((-_root.model.global_transform.basis.z).angle_to(_root.model.velocity))
	# The random hull may be a barge that can't come round 90° in 4 s: then
	# it only has to have turned most of what it can.
	var can_turn := rad_to_deg(_root.model.turn_rate) * 4.1
	print("  nose %.1f° off the path (turn rate %.2f rad/s, can turn %.0f°)" % [nose_off, _root.model.turn_rate, can_turn])
	_report("swipe: the nose follows the path", nose_off < maxf(25.0, 90.0 - can_turn * 0.8))


func _check_swipe_tap_priority(sp: AiSpawner) -> void:
	_root.model.halt()
	var fwd := -_root.model.global_transform.basis.z
	var side := _root.model.global_transform.basis.x
	var weak := _parked(sp, _root.model.global_position + fwd * 420.0 + side * 60.0)
	var strong := _parked(sp, _root.model.global_position + fwd * 330.0 - side * 50.0)
	var friend := _parked(sp, _root.model.global_position + fwd * 250.0)
	weak.hp = weak.max_hp * 0.3
	weak._hit_player_ms = Time.get_ticks_msec()
	friend.team_id = 7
	_root.model.set_meta("team", 7)
	_root.set_meta("team", 7)
	friend.player_ref = _root.model
	await _frames(2)
	var pilot := _root.pilot() as SwipePilot
	pilot.heading = fwd
	var sys := _root.active_systems()
	sys.energy = sys._capacity()
	var shots0 := sys._shots.size()
	_root.locked_target = null
	await _tap(_view_centre())
	await _seconds(0.3)
	var picked := _root.locked_target
	print("  tap: picked %s (weak hostile %s, wary %s, friendly %s); shots %d -> %d" % [
		_name(picked), _name(weak), _name(strong), _name(friend), shots0, sys._shots.size()])
	_report("swipe tap: fires at the weak hostile, not the wary or friendly", picked == weak)
	_report("swipe tap: a volley goes out", sys._shots.size() > shots0 or sys.firing)
	# Game time, not wall time: a kill here freezes/slows the game (kill cam).
	for i in 4 * Engine.physics_ticks_per_second:
		if not sys.firing:
			break
		await physics_frame
	_report("swipe tap: the volley stops by itself", not sys.firing)
	_root.remove_meta("team")
	_root.model.remove_meta("team")
	for s: AiShip in [weak, strong, friend]:
		s.queue_free()
	_root.locked_target = null
	await _frames(2)


func _check_swipe_hold() -> void:
	var c := _view_centre()
	_touch(c, true)
	await _seconds(0.5)
	var boosting := _root._button_boost
	await _seconds(1.2)
	var warping := _root.model.warp_active
	_touch(c, false)
	await _frames(2)
	print("  hold: boost %s at 0.5 s, warp %s at 1.7 s; after release boost %s warp %s" % [
		boosting, warping, _root._button_boost, _root.model.warp_active])
	_report("swipe hold: boosts", boosting)
	_report("swipe long hold: warps", warping)
	_report("swipe release: boost and warp end", not _root._button_boost and not _root.model.warp_active)
	_root.model.halt()
	await _seconds(0.5)


func _check_swipe_course_correction(sp: AiSpawner) -> void:
	_root.model.halt()
	var pilot := _root.pilot() as SwipePilot
	var c := _swipe_start()
	await _swipe(c, c + Vector2(0.0, -short() * 0.3), 4)
	await _frames(2)
	# A hostile 15° off the swiped heading (fixed in the world once swiped).
	var axis := pilot.heading.cross(Vector3.UP if absf(pilot.heading.y) < 0.9 else Vector3.RIGHT).normalized()
	var off := pilot.heading.rotated(axis, deg_to_rad(15.0))
	var t := _parked(sp, _root.model.global_position + off * 500.0)
	t._hit_player_ms = Time.get_ticks_msec()
	await _seconds(0.8)
	var v := _root.model.velocity.normalized()
	var to_t := (t.global_position - _root.model.global_position).normalized()
	print("  course correction: path %.1f° from swipe, %.1f° from target (target %.1f° off the swipe)" % [
		rad_to_deg(v.angle_to(pilot.heading)), rad_to_deg(v.angle_to(to_t)), rad_to_deg(pilot.heading.angle_to(to_t))])
	_report("swipe: course correction bends onto the target", pilot.assist_target == t and v.angle_to(to_t) < pilot.heading.angle_to(to_t))
	t.queue_free()
	await _frames(2)


func _check_swipe_ram(sp: AiSpawner) -> void:
	_root.model.halt()
	await _frames(2)
	var c := _swipe_start()
	await _swipe(c, c + Vector2(0.0, -short() * 0.45), 3)
	# Straight down the swiped heading, whatever this run's hull flies like.
	var pilot := _root.pilot() as SwipePilot
	var t := _parked(sp, _root.model.global_position + pilot.heading * 300.0)
	t._hit_player_ms = Time.get_ticks_msec()
	var hp0 := t.hp
	var closest := INF
	var hit := false
	for i in int(3.5 * Engine.physics_ticks_per_second):
		await physics_frame
		if not is_instance_valid(t) or not t._alive or t.hp < hp0:
			hit = true
			break
		closest = minf(closest, _root.model.global_position.distance_to(t.global_position))
	print("  ram: target hp %.0f -> %s (closest %.0f m)" % [hp0, ("%.0f" % t.hp) if is_instance_valid(t) and t._alive else "destroyed", closest])
	_report("swipe: swiping into a ship rams it for damage", hit)
	if is_instance_valid(t):
		t.queue_free()
	await _frames(2)


# --- Slingshot ---

func _check_sling_launch_and_end() -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.model.halt()
	await _seconds(0.3)
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	var s := pilot.ship_screen_pos()
	_report("sling: ship is on screen and ready", s != Vector2.INF and run.state == SlingRun.State.READY)
	var cam_b := _root.camera_node().global_transform.basis.orthonormalized()
	# Pulled straight down on the shipped dome aim: round the half-sphere
	# toward the camera, so it throws forward along the line of sight through
	# the ship, not up the view.
	var ray := _root.camera_node().project_ray_normal(s)
	var want := SlingshotPilot.dome_dir(Vector2(0.0, 1.0), cam_b, JuiceSettings.sling_aim_depth, ray)
	var max_time := JuiceSettings.sling_max_time
	var magnet := JuiceSettings.magnet_strength
	JuiceSettings.magnet_strength = 0.0
	JuiceSettings.sling_max_time = 1.6
	# Pull down: launch goes up the view and into the screen.
	_touch(s, true)
	await _frames(2)
	_drag(s + Vector2(0.0, short() * 0.3))
	await _frames(3)
	var aiming := run.state == SlingRun.State.AIMING
	_touch(s + Vector2(0.0, short() * 0.3), false)
	await _frames(2)
	var v := _root.model.velocity
	var ang := rad_to_deg(v.angle_to(want))
	var into := v.normalized().dot(-cam_b.z)
	print("  launch: %.0f m/s, %.1f° off the 3D aim, %.2f into the screen (pulled down)" % [v.length(), ang, into])
	_report("sling: pulling back from the ship aims", aiming)
	_report("sling: release launches along the aim (pulling back throws it forward)", run.state == SlingRun.State.FLYING and ang < 15.0)
	_report("sling: the launch is 3D (into the screen, not flat on it)", into > 0.5)
	_report("sling: the hull spins free in flight", _root.model.free_spin)
	await _seconds(0.5)
	_report("sling: the camera pulls out", _root.camera_rig._held_zoom > 0.2)
	# Past the 1.6 s limit with room for hitstop (it slows game time).
	await _seconds(2.4)
	var ended := run.state != SlingRun.State.FLYING
	await _seconds(2.5)
	print("  run: ended %s, now %s at %.1f m/s, camera held zoom %.2f" % [
		ended, SlingRun.State.keys()[run.state], _root.model.velocity.length(), _root.camera_rig._held_zoom])
	_report("sling: the run ends (time out) and the ship brakes", ended and run.state == SlingRun.State.READY and _root.model.velocity.length() < 3.0)
	_report("sling: the camera eases back in", _root.camera_rig._held_zoom < 0.15)
	JuiceSettings.sling_max_time = max_time
	JuiceSettings.magnet_strength = magnet


func _check_sling_bounce_seek(sp: AiSpawner) -> void:
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	_root.model.halt()
	var cam := _root.camera_node()
	var up := cam.global_transform.basis.y
	var right := cam.global_transform.basis.x
	var pos := _root.model.global_position
	var wall := _parked(sp, pos + up * 260.0)
	var next := _parked(sp, pos + up * 120.0 + right * 500.0)
	next._hit_player_ms = Time.get_ticks_msec()
	await _frames(3)
	var seek_was := JuiceSettings.sling_bounce_seek
	JuiceSettings.sling_bounce_seek = 0.9
	# Auto-fire would shoot the wall down before the ship reaches it.
	var auto_was := JuiceSettings.sling_auto_shoot
	JuiceSettings.sling_auto_shoot = 0.0
	run.launch(up, 0.8)
	var bounced := false
	var v_after := Vector3.ZERO
	for i in 3 * Engine.physics_ticks_per_second:
		await physics_frame
		if run.bounces > 0:
			bounced = true
			v_after = _root.model.velocity
			break
	var to_next := Vector3.ZERO
	if is_instance_valid(next):
		to_next = (next.global_position - _root.model.global_position).normalized()
	var ang := rad_to_deg(v_after.angle_to(to_next)) if bounced else 180.0
	print("  bounce: %s, then %.1f° from the next ship (pure reflection would be ~%.0f°)" % [
		bounced, ang, rad_to_deg((-up).angle_to(to_next))])
	_report("sling: the ship bounces off what it hits", bounced)
	JuiceSettings.sling_auto_shoot = auto_was
	_report("sling: the bounce heads for the next body", bounced and ang < 40.0)
	JuiceSettings.sling_bounce_seek = seek_was
	run.catch_ship()
	for s: AiShip in [wall, next]:
		if is_instance_valid(s):
			s.queue_free()
	await _seconds(1.0)


func _check_sling_catch() -> void:
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	_root.model.halt()
	await _seconds(0.3)
	run.launch(_root.camera_node().global_transform.basis.x, 0.5)
	await _seconds(0.3)
	var s := pilot.ship_screen_pos()
	_touch(s, true)
	await _frames(2)
	var caught := run.state == SlingRun.State.RECALLING
	await _seconds(1.2)
	var re_aim := run.state == SlingRun.State.AIMING
	_touch(s, false)
	await _frames(2)
	print("  catch: braking %s, aiming again while held %s" % [caught, re_aim])
	_report("sling: touching the flying ship catches it", caught)
	_report("sling: the same finger aims the next launch", re_aim)
	run.set_aiming(false)
	await _seconds(0.3)


## A still thumb holds a still aim: the camera swings round behind the ship
## along the pull, but the pull is read in the view from touch-down and from
## where the ship is drawn, so the aim must not wander ("goes wild"). The band
## starts on the hull, and in flight the camera keeps the launch line.
func _check_sling_steady_aim() -> void:
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	_root.model.halt()
	var magnet := JuiceSettings.magnet_strength
	JuiceSettings.magnet_strength = 0.0
	await _seconds(0.5)
	var s := pilot.ship_screen_pos()
	var finger := s + Vector2(short() * 0.22, short() * 0.18)
	_touch(s, true)
	await _frames(2)
	_drag(finger)
	await _frames(3)
	var first := pilot.aim_dir
	var worst := 0.0
	var band_off := 0.0
	var ring_off := 0.0
	# Hold still while the view swings.
	for i in 60:
		await process_frame
		worst = maxf(worst, rad_to_deg(first.angle_to(pilot.aim_dir)))
		band_off = maxf(band_off, pilot.finger.distance_to(finger))
		var at := _root.camera_node().unproject_position(_root.model.get_global_transform_interpolated().origin)
		ring_off = maxf(ring_off, pilot.ship_screen_pos().distance_to(at))
	var cam_turned := rad_to_deg((-_root.camera_node().global_basis.z).angle_to(first))
	print("  steady aim: aim wandered %.2f° over a second, band %.1f px off the thumb, ring %.1f px off the hull, camera %.0f° off the aim" % [worst, band_off, ring_off, cam_turned])
	_report("sling: a still thumb keeps a still aim while the view swings", worst < 3.0)
	_report("sling: the band ends under the thumb, the ring sits on the drawn hull", band_off < 1.0 and ring_off < 1.0)
	_touch(finger, false)
	await _seconds(0.4)
	var held := pilot._flight_dir()
	_report("sling: in flight the camera holds the launch line", run.state != SlingRun.State.FLYING
		or (held != Vector3.ZERO and rad_to_deg(held.angle_to(pilot._launch_dir)) < 1.0))
	run.catch_ship()
	JuiceSettings.magnet_strength = magnet
	await _seconds(1.0)


func _check_sling_tap_fire(sp: AiSpawner) -> void:
	var pilot := _root.pilot() as SlingshotPilot
	var run := pilot.run
	_root.model.halt()
	var sys := _root.active_systems()
	sys.energy = sys._capacity()
	var cam := _root.camera_node()
	run.launch(cam.global_transform.basis.x, 0.4)
	await _seconds(0.2)
	var shots0 := sys._shots.size()
	var tap := _view_centre() + Vector2(-short() * 0.3, -short() * 0.25)
	# The tap's ray, from the camera at the moment of the tap.
	var want := (cam.project_position(tap, 500.0) - cam.global_position).normalized()
	var eye := cam.global_position
	await _tap(tap)
	await physics_frame
	await physics_frame
	var aimed := sys.aim_override != Vector3.INF
	var firing := sys.firing
	var aim_dir := (sys.aim_override - eye).normalized() if aimed else Vector3.ZERO
	await _seconds(0.2)
	print("  sling tap: aim set %s, firing %s, shots %d -> %d, aim %.1f° off the tap ray" % [
		aimed, firing, shots0, sys._shots.size(), rad_to_deg(aim_dir.angle_to(want)) if aim_dir != Vector3.ZERO else 180.0])
	_report("sling: a tap in flight shoots toward the tap", aimed and firing and aim_dir.angle_to(want) < deg_to_rad(10.0))
	await _seconds(0.5)
	_report("sling: the aim goes back to the nose after", sys.aim_override == Vector3.INF)
	run.catch_ship()
	await _seconds(1.0)


func _check_sling_orbit_ends_run() -> void:
	var run := (_root.pilot() as SlingshotPilot).run
	run.launch(_root.camera_node().global_transform.basis.x, 0.3)
	run.ended.connect(func(in_orbit: bool) -> void: _ended_in_orbit = in_orbit, CONNECT_ONE_SHOT)
	_root.model.orbit_changed.emit("Test planet", true)
	_report("sling: going into orbit ends the run, ship left orbiting", _ended_in_orbit \
		and run.state == SlingRun.State.READY and not _root.model.external_drive and _root.model.velocity.length() > 1.0)
	_root.model.halt()


# --- AI slingshot ---

func _check_ai_sling(sp: AiSpawner) -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	_root.model.halt()
	JuiceSettings.ai_slingshot = true
	JuiceSettings.ai_sling_share = 1.0
	var fwd := -_root.model.global_transform.basis.z
	var ship := _parked(sp, _root.model.global_position + fwd * 500.0)
	ship._ai_paused = false
	ship._hit_player_ms = Time.get_ticks_msec()
	ship._sling_cooldown = 0.1
	var launched := false
	for i in 4 * Engine.physics_ticks_per_second:
		await physics_frame
		if not is_instance_valid(ship):
			break
		if ship._sling != null and ship._sling.state == SlingRun.State.FLYING:
			launched = true
			break
	var closing := 0.0
	if launched:
		closing = ship.model.velocity.dot((_root.model.global_position - ship.global_position).normalized())
	print("  AI sling: launched %s, closing on the player at %.0f m/s" % [launched, closing])
	_report("AI slingshot: a picked ship launches itself at its target", launched and closing > 50.0)
	JuiceSettings.ai_slingshot = false
	await _frames(3)
	_report("AI slingshot off: the ship flies normally again", not is_instance_valid(ship) or (ship._sling == null and not ship.model.external_drive))
	if is_instance_valid(ship):
		ship.queue_free()
	await _frames(2)


func _check_hud_hides_controls() -> void:
	var hud: FlightHud = _root._hud
	_root.set_move_profile(FlightRoot.MoveProfile.SWIPE)
	await _frames(2)
	var hidden := not hud._stick.visible and not hud._fire_button.visible and not hud._throttle.visible
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _frames(2)
	var shown := hud._stick.visible and hud._fire_button.visible
	_report("HUD: swipe hides the stick and buttons, classic brings them back", hidden and shown)


# --- Camera gestures, FPS, shot speed ---

func _check_swipe_camera_gestures() -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SWIPE)
	_root.model.halt()
	await _seconds(0.5)
	var pilot := _root.pilot() as SwipePilot
	var rig := _root.camera_rig
	_report("swipe: the camera sits further out by default", is_equal_approx(rig.profile_distance, 1.0 + JuiceSettings.swipe_cam_zoom))
	var view := _root.get_viewport().get_visible_rect().size
	var s := pilot.ship_screen_pos()
	# A corner well clear of the ship.
	var off := Vector2(view.x * 0.12, view.y * 0.15)
	if s.distance_to(off) < pilot.grab_radius() * 1.5:
		off = Vector2(view.x * 0.88, view.y * 0.15)
	var heading := pilot.heading
	await _swipe(off, off + Vector2(short() * 0.3, 0.0), 4)
	await _seconds(0.5)
	print("  drag off the ship: user yaw %.0f° (eased %.0f°), heading moved %.1f°" % [
		rig.user_yaw, rig._user_yaw, rad_to_deg(pilot.heading.angle_to(heading))])
	_report("drag off the ship: the ship keeps its heading", pilot.heading.is_equal_approx(heading))
	_report("drag off the ship: the camera swings round it", absf(rig.user_yaw) > 20.0 and absf(rig._user_yaw) > 15.0)
	var in_view := Rect2(Vector2.ZERO, view).has_point(pilot.ship_screen_pos())
	_report("drag off the ship: the ship stays in frame (it is the pivot)", in_view)
	# From the ship: flies, and leaves the swing alone. The arrow shows mid-swipe.
	var yaw := rig.user_yaw
	s = pilot.ship_screen_pos()
	_touch(s, true)
	await _frames(2)
	_drag(s + Vector2(0.0, -short() * 0.3))
	await _frames(3)
	var arrow_up := pilot._arrows.size() > 0 and pilot._arrows[0].visible
	_touch(s + Vector2(0.0, -short() * 0.3), false)
	await _seconds(0.2)
	_report("swipe from the ship: flies, camera swing untouched", not pilot.heading.is_equal_approx(heading) and rig.user_yaw == yaw)
	_report("swipe: a 3D chevron arrow shows where the swipe goes", arrow_up)
	# Two fingers: spread = zoom in, twist = swing; neither is a swipe.
	heading = pilot.heading
	var c := view * 0.5
	var d0 := rig.user_distance
	_touch_i(0, c - Vector2(40.0, 0.0), true)
	_touch_i(1, c + Vector2(40.0, 0.0), true)
	for i in 4:
		await process_frame
		var r := 40.0 + 30.0 * float(i + 1)
		_drag_i(0, c - Vector2(r, 0.0))
		_drag_i(1, c + Vector2(r, 0.0))
	var d1 := rig.user_distance
	var y0 := rig.user_yaw
	for i in 4:
		await process_frame
		var a := deg_to_rad(10.0 * float(i + 1))
		_drag_i(0, c - Vector2(160.0, 0.0).rotated(a))
		_drag_i(1, c + Vector2(160.0, 0.0).rotated(a))
	_touch_i(1, c + Vector2(160.0, 0.0), false)
	_touch_i(0, c - Vector2(160.0, 0.0), false)
	await physics_frame
	print("  pinch: distance %.2f -> %.2f; twist: yaw %.0f° -> %.0f°" % [d0, d1, y0, rig.user_yaw])
	_report("pinch: spreading two fingers zooms in", d1 < d0 * 0.6)
	_report("twist: turning two fingers swings the camera", absf(wrapf(rig.user_yaw - y0, -180.0, 180.0)) > 20.0)
	_report("two fingers never fly the ship", pilot.heading.is_equal_approx(heading))
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _frames(2)
	_report("leaving the profile resets the camera", rig.user_yaw == 0.0 and rig.user_distance == 1.0 and rig.profile_distance == 1.0)


func _check_sling_steady_camera() -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.model.halt()
	await _seconds(0.3)
	var pilot := _root.pilot() as SlingshotPilot
	var s := pilot.ship_screen_pos()
	_touch(s, true)
	await _frames(2)
	_drag(s + Vector2(0.0, short() * 0.3))
	await _frames(3)
	var aim_arrow := pilot._arrows.size() > 0 and pilot._arrows[0].visible
	_touch(s + Vector2(0.0, short() * 0.3), false)
	# Past the camera's own ease onto the launch line, then half a second of
	# game time (ticks, so it is the same flight at any frame rate).
	await _seconds(0.6)
	var cam := _root.camera_rig
	var hull_turn := 0.0
	var cam_turn := 0.0
	var hq := _root.model.global_transform.basis.get_rotation_quaternion()
	var cq := cam.global_transform.basis.get_rotation_quaternion()
	for i in int(Engine.physics_ticks_per_second * 0.5):
		await physics_frame
		var hq2 := _root.model.global_transform.basis.get_rotation_quaternion()
		var cq2 := cam.global_transform.basis.get_rotation_quaternion()
		hull_turn += rad_to_deg(hq.angle_to(hq2))
		cam_turn += rad_to_deg(cq.angle_to(cq2))
		hq = hq2
		cq = cq2
	print("  sling flight: hull turned %.0f°, camera %.0f°" % [hull_turn, cam_turn])
	_report("sling: a 3D chevron arrow shows the launch while aiming", aim_arrow)
	_report("sling: the camera doesn't turn with the hull's spin", hull_turn > 60.0 and cam_turn < hull_turn * 0.25)
	pilot.run.catch_ship()
	await _seconds(1.0)


func _check_fps_profile() -> void:
	var hud: FlightHud = _root._hud
	_root.set_move_profile(FlightRoot.MoveProfile.FPS)
	_root.model.halt()
	await _seconds(0.3)
	var pilot := _root.pilot() as FpsPilot
	_report("FPS: stick and fire stay, the throttle goes", hud._stick.visible and hud._fire_button.visible and not hud._throttle.visible)
	var top := _root.model.top_speed * JuiceSettings.fps_speed_mult
	_root.set_stick(Vector2(0.0, -0.5))
	await _seconds(1.5)
	var v := _root.model.velocity
	print("  half stick: %.0f m/s (half of %.0f), %.1f° off the look" % [v.length(), top, rad_to_deg(v.angle_to(pilot.look_dir))])
	_report("FPS: half stick flies forward at half speed", absf(v.length() - top * 0.5) < top * 0.1 and v.angle_to(pilot.look_dir) < deg_to_rad(10.0))
	_root.set_stick(Vector2(0.0, -1.0))
	await _seconds(1.5)
	_report("FPS: a full stick boosts", _root.model.command.boost and _root.model.velocity.length() > top * 1.05)
	_root.set_stick(Vector2.ZERO)
	await _seconds(1.5)
	_report("FPS: letting go of the stick stops the ship", _root.model.velocity.length() < top * 0.1)
	var before := pilot.look_dir
	var c := _root.get_viewport().get_visible_rect().size * 0.5
	_touch(c, true)
	for i in 5:
		await process_frame
		_drag_rel(c + Vector2(short() * 0.05 * float(i + 1), 0.0), Vector2(short() * 0.05, 0.0))
	_touch(c + Vector2(short() * 0.25, 0.0), false)
	var turned := rad_to_deg(before.angle_to(pilot.look_dir))
	# Time for the slowest-turning random hull to come round.
	await _seconds(2.0)
	var nose := rad_to_deg((-_root.model.global_transform.basis.z).angle_to(pilot.look_dir))
	# A barge that can't turn the whole look in 2 s only has to have turned most of what it can.
	var can_turn := rad_to_deg(_root.model.turn_rate) * 2.0
	var cam_fwd := -_root.camera_node().global_transform.basis.z
	var cam_off := rad_to_deg(cam_fwd.angle_to(pilot.look_dir))
	print("  look drag: turned %.0f°, nose %.1f° off it, camera %.1f° off it (hull can turn %.0f°)" % [turned, nose, cam_off, can_turn])
	_report("FPS: dragging the screen turns the look", turned > 30.0)
	_report("FPS: the nose and camera follow the look", nose < maxf(12.0, turned - can_turn * 0.8) and cam_off < 25.0)
	_root.set_stick(Vector2(0.6, 0.0))
	await _seconds(1.5)
	var right := _root.camera_node().global_transform.basis.x
	_report("FPS: a sideways stick strafes", _root.model.velocity.angle_to(right) < deg_to_rad(20.0))
	_root.set_stick(Vector2.ZERO)
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _frames(2)
	_report("FPS: classic gets the throttle back", hud._throttle.visible)


func _check_player_shots_fast() -> void:
	_root.model.halt()
	# The pulse laser: a travelling shot (a beam has no speed to slow).
	var ship := _root.fly_as(1.0, 0, "orbs")
	await _seconds(0.2)
	if ship == null or ship.systems == null:
		_report("fly as a slow-shot style: shots at full speed", false)
		return
	ship.model.halt()
	var sys := ship.systems
	var weapon_speed := float(sys.get_active_weapon().get("speed", 900.0))
	_root.set_firing(true)
	await _seconds(0.8)
	_root.set_firing(false)
	var slowest := INF
	for shot: Dictionary in sys._shots:
		slowest = minf(slowest, (shot["velocity"] as Vector3).length())
	print("  fly as orbs: slowest shot %.0f m/s (weapon %.0f, style ×%.2f, floor %.0f)" % [
		slowest, weapon_speed, float(ship.fire_pattern.get("speed_mult", 1.0)), JuiceSettings.player_min_shot_speed])
	_report("fly as a slow-shot style: player flag set", sys.player_flown)
	_report("fly as a slow-shot style: shots at full speed", slowest != INF and slowest >= minf(weapon_speed, JuiceSettings.player_min_shot_speed) * 0.95)
	_root.leave_control()
	# (The flown-as ship is torn down with it; read the flag before it goes.)
	_report("handing it back clears the flag", not is_instance_valid(sys) or not sys.player_flown)
	await _frames(2)


# --- Helpers ---

# --- Launch magnet, attack reach, grab area, markers, telegraph ---

func _check_magnet_and_reach(sp: AiSpawner) -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.model.halt()
	await _seconds(0.4)
	var pilot := _root.pilot() as SlingshotPilot
	var s := pilot.ship_screen_pos()
	var edge := short()
	print("  grab area: %.0f px (short edge %.0f)" % [pilot.grab_radius(), edge])
	_report("grab area: small (a drag just off the ship looks around)",
		pilot.grab_radius() <= edge * MovePilot.GRAB_MAX_EDGE * JuiceSettings.grab_radius_scale + 0.5
		and not pilot.near_ship(s + Vector2(edge * 0.14, 0.0)) and pilot.near_ship(s))

	# The magnet: a hostile 30° off the launch line bends the flight onto it.
	var cam_b := _root.camera_node().global_transform.basis.orthonormalized()
	var dir := MovePilot.depth_dir(Vector2(0.0, -1.0), cam_b, JuiceSettings.sling_aim_depth)
	var axis := dir.cross(cam_b.x).normalized()
	var t := _parked(sp, _root.model.global_position + dir.rotated(axis, deg_to_rad(30.0)) * 450.0)
	t._hit_player_ms = Time.get_ticks_msec()
	await _frames(2)
	var hp0 := t.hp
	_touch(s, true)
	await _frames(2)
	_drag(s + Vector2(0.0, edge * 0.3))
	await _frames(3)
	_touch(s + Vector2(0.0, edge * 0.3), false)
	var picked := false
	var ahead_ok := false
	var closest := INF
	for i in int(2.5 * Engine.physics_ticks_per_second):
		await physics_frame
		if not is_instance_valid(t) or not t._alive or t.hp < hp0:
			closest = 0.0
			break
		picked = picked or pilot.magnet_target == t
		var rig := _root.camera_rig
		ahead_ok = ahead_ok or (rig.look_ahead.length() > 1.0 and rig.look_ahead.dot(_root.model.velocity) > 0.0)
		closest = minf(closest, _root.model.global_position.distance_to(t.global_position))
	print("  magnet: picked %s, closest %.0f m (the line passed %.0f m off)" % [picked, closest, 450.0 * sin(deg_to_rad(30.0))])
	_report("magnet: the launch bends onto a ship off the line", picked and closest < 60.0)
	_report("sling camera: looks ahead along the flight", ahead_ok)
	if is_instance_valid(t):
		t.queue_free()
	await _seconds(3.5)
	# Settled at rest: back out at the resting distance, never onto the hull.
	var rest_d := _root.camera_rig.profile_distance
	print("  sling camera at rest: × %.2f (rest dial × %.2f, nearest × %.2f)" % [rest_d, JuiceSettings.sling_rest_distance, JuiceSettings.sling_cam_min])
	_report("sling camera: sits out at the rest distance once the ship has slowed",
		rest_d >= 1.0 and rest_d <= JuiceSettings.sling_rest_distance + 0.01)


	# Ram reach: flying past a ship, a little wider than touching, rams it.
	var magnet := JuiceSettings.magnet_strength
	JuiceSettings.magnet_strength = 0.0
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	_root.model.halt()
	await _frames(3)
	var m := _root.model
	var fwd := -m.global_transform.basis.z
	var side := m.global_transform.basis.x
	var mine := m.phys_body().radius
	var t2 := _parked(sp, m.global_position + fwd * 120.0)
	await _frames(2)
	var gap := mine * (1.0 + (JuiceSettings.player_ram_reach - 1.0) * 0.5) + t2.model.phys_body().radius
	t2.global_position = m.global_position + fwd * 120.0 + side * gap
	t2.model.global_position = t2.global_position
	t2._hit_player_ms = Time.get_ticks_msec()
	var hp2 := t2.hp
	var touch := mine + t2.model.phys_body().radius
	m.set_velocity(fwd * 120.0)
	var rammed := false
	var touched := false
	for i in int(2.0 * Engine.physics_ticks_per_second):
		m.velocity = fwd * 120.0
		await physics_frame
		if not is_instance_valid(t2) or not t2._alive or t2.hp < hp2:
			rammed = true
			break
		touched = touched or m.global_position.distance_to(t2.global_position) <= touch
	print("  ram reach: passed %.1f m off (touching %.1f), rammed %s, touched %s" % [gap, touch, rammed, touched])
	_report("ram reach: passing just wide of a ship still rams it", rammed and not touched)
	if is_instance_valid(t2):
		t2.queue_free()
	m.halt()
	JuiceSettings.magnet_strength = magnet
	await _frames(2)

	# Shot reach: a shot passing wide of a ship's hull still hits it.
	var t3 := _parked(sp, m.global_position + fwd * 300.0)
	await _frames(2)
	var hp3 := t3.hp
	var r3 := t3.model.phys_body().radius
	var off := t3.global_position + side * r3 * (JuiceSettings.player_shot_hit_scale * 0.8)
	var sys := _root.active_systems()
	var grazed: bool = sys._player_shot_graze({"weapon": sys.get_active_weapon()}, off - fwd * 50.0, off + fwd * 50.0)
	print("  shot reach: passed %.1f m from a %.1f m ship: hit %s, hp %.0f -> %.0f" % [
		r3 * JuiceSettings.player_shot_hit_scale * 0.8, r3, grazed, hp3, t3.hp])
	_report("shot reach: the player's shot hits a ship it passes near", grazed and t3.hp < hp3)
	t3.queue_free()

	# Losing a wing: the player's ship doesn't spiral (the AI would).
	# (Yaw and roll only: that is the pull a lost wing adds.)
	m.asymmetric_drag = Vector3(0.0, 0.4, 0.85)
	m.set_velocity(fwd * 100.0)
	var spin := 0.0
	for i in Engine.physics_ticks_per_second:
		m.command.pitch = 0.0
		m.command.yaw = 0.0
		m.command.roll = 0.0
		await physics_frame
		spin = maxf(spin, Vector2(m.angular.y, m.angular.z).length())
	m.asymmetric_drag = Vector3.ZERO
	m.halt()
	print("  lost wing: player yaw/roll spin %.2f rad/s" % spin)
	_report("lost wing: the player isn't thrown into a spiral", spin < 0.05)
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	await _check_aim_look()
	await _frames(2)


func _check_markers_and_telegraph(sp: AiSpawner) -> void:
	var m := _root.model
	var cam := _root.camera_node()
	var t := _parked(sp, m.global_position - cam.global_transform.basis.z * 400.0)
	# At war with the player, never touched by them.
	t._hit_player_ms = Time.get_ticks_msec()
	await _frames(6)
	var marks := _root._interaction_markers.snapshot()
	print("  markers: hostile on screen, never engaged: marked %s (interacted %s)" % [marks.has(t), t.interacted_recently()])
	_report("markers: a shoot-on-sight ship on screen is marked at once", marks.has(t) and not t.interacted_recently())
	var hud: FlightHud = _root._hud
	var was_mobile: bool = hud._mobile_layout
	hud.set_mobile_layout(true)
	await _frames(3)
	_report("markers: still drawn in the phone layout", _root._interaction_markers.is_visible_in_tree())
	hud.set_mobile_layout(was_mobile)

	# Telegraph: a volley at the player waits for the wind-up, glowing.
	var wind := JuiceSettings.enemy_telegraph
	var dt := 1.0 / 60.0
	var first_fire := -1.0
	var glowed := false
	for i in int((wind + 0.3) / dt):
		if t._telegraph_gate(dt, m, true):
			first_fire = i * dt
			break
		glowed = glowed or (t._telegraph != null and t._telegraph.visible)
	print("  telegraph: first shot after %.2f s (wind-up %.2f), glowed %s" % [first_fire, wind, glowed])
	_report("telegraph: an enemy glows before it opens fire on you", glowed and first_fire >= wind - dt * 1.5)
	_report("telegraph: then it fires", first_fire >= 0.0)
	t.queue_free()
	await _frames(2)


## The aim styles ([member JuiceSettings.sling_aim_style]): the dome throws a
## pull back forward (not up), a pull up down and a pull right leftward and
## into the screen; smart locks onto a ship the classic cone misses, turns
## the aim onto its lead and adds the power to reach it.
func _check_sling_aim_styles(sp: AiSpawner) -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.model.halt()
	await _seconds(0.6)
	var pilot := _root.pilot() as SlingshotPilot
	var style := JuiceSettings.sling_aim_style
	var magnet := JuiceSettings.magnet_strength
	var edge := short()
	var s := pilot.ship_screen_pos()
	var cam_b := _root.camera_node().global_transform.basis.orthonormalized()
	var ray := _root.camera_node().project_ray_normal(s)
	var dirs := {}
	for pull: Vector2 in [Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(1.0, 0.0)]:
		dirs[pull] = SlingshotPilot.dome_dir(pull, cam_b, JuiceSettings.sling_aim_depth, ray)
	var back: Vector3 = dirs[Vector2(0.0, 1.0)]
	var up_pull: Vector3 = dirs[Vector2(0.0, -1.0)]
	var right_pull: Vector3 = dirs[Vector2(1.0, 0.0)]
	print("  dome: pull back → %.2f into / %.2f up; pull up → %.2f up; pull right → %.2f right, %.2f into" % [
		back.dot(-cam_b.z), back.dot(cam_b.y), up_pull.dot(cam_b.y), right_pull.dot(cam_b.x), right_pull.dot(-cam_b.z)])
	_report("dome aim: pulling back throws the ship forward, not up",
		back.angle_to(ray) < deg_to_rad(1.0) and back.dot(-cam_b.z) > 0.8)
	_report("dome aim: pulling up throws it down, pulling right throws it left and into the screen",
		up_pull.dot(cam_b.y) < -0.7 and right_pull.dot(cam_b.x) < -0.7 and right_pull.dot(-cam_b.z) > 0.1)

	# A hostile 20° off the dome's line: outside the classic 12° snap, inside smart's.
	JuiceSettings.magnet_strength = 0.85
	var axis := back.cross(cam_b.x).normalized()
	var t := _parked(sp, _root.model.global_position + back.rotated(axis, deg_to_rad(20.0)) * 1200.0)
	await _frames(3)
	var pull := Vector2(0.0, edge * 0.1)
	var raw := clampf(pull.length() / (edge * 0.38), 0.0, 1.0)
	var got := {}
	for st in [1.0, 2.0]:
		JuiceSettings.sling_aim_style = st
		_touch(s, true)
		await _frames(2)
		_drag(s + pull)
		await _frames(3)
		var to := (t.global_position - _root.model.global_position).normalized()
		got[st] = [pilot.aim_target == t, pilot.aim_power, rad_to_deg(pilot.aim_dir.angle_to(to))]
		# Back onto the ship and let go: no launch.
		_drag(s)
		await _frames(2)
		_touch(s, false)
		await _frames(3)
	print("  smart aim: dome locked %s (%.2f power, %.0f° off); smart locked %s (%.2f power from %.2f, %.0f° off)" % [
		got[1.0][0], got[1.0][1], got[1.0][2], got[2.0][0], got[2.0][1], raw, got[2.0][2]])
	_report("smart aim: locks onto a ship the plain snap misses and turns onto it",
		not got[1.0][0] and got[2.0][0] and got[2.0][2] < 6.0)
	_report("smart aim: adds the power to reach it", got[2.0][1] > raw + 0.1)
	_report("smart aim: a pull let go on the ship doesn't launch", pilot.run.state != SlingRun.State.FLYING)
	if is_instance_valid(t):
		t.queue_free()
	JuiceSettings.sling_aim_style = style
	JuiceSettings.magnet_strength = magnet


func _parked(sp: AiSpawner, pos: Vector3) -> AiShip:
	var m := _root.model
	var ship := sp.spawn_pilot_vessel(Transform3D(Basis.looking_at(m.global_position - pos, Vector3.UP), pos), 1.0)
	ship.global_position = pos
	ship.model.global_transform = Transform3D(Basis.looking_at(m.global_position - pos, Vector3.UP), pos)
	ship.model.halt()
	ship.is_pilot_vessel = false
	ship._ai_paused = true
	ship.player_ref = m
	return ship


func _name(n: Node) -> String:
	return "none" if n == null else String(n.name)


func short() -> float:
	var s := _root.get_viewport().get_visible_rect().size
	return minf(s.x, s.y)


func _view_centre() -> Vector2:
	return _root.get_viewport().get_visible_rect().size * 0.5


## Where a flying swipe starts: on the ship (a swipe from anywhere else swings
## the camera, see [member JuiceSettings.swipe_from_ship]).
func _swipe_start() -> Vector2:
	var p := _root.pilot()
	var s := p.ship_screen_pos() if p != null else Vector2.INF
	return s if s != Vector2.INF else _view_centre()


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


func _touch_i(index: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = down
	_root._unhandled_input(e)


func _drag_i(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	_root._unhandled_input(e)


func _drag_rel(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	_root._unhandled_input(e)


func _swipe(from: Vector2, to: Vector2, steps: int) -> void:
	_touch(from, true)
	for i in steps:
		await process_frame
		_drag(from.lerp(to, float(i + 1) / float(steps)))
	_cam_at_release = _root.camera_node().global_transform.basis
	_touch(to, false)
	await physics_frame


func _tap(pos: Vector2) -> void:
	_touch(pos, true)
	await process_frame
	_touch(pos, false)
	await physics_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Game seconds, counted in physics ticks: under --fixed-fps a wall-clock wait
## is a different amount of game time at every frame rate.
func _seconds(s: float) -> void:
	for i in int(ceilf(s * Engine.physics_ticks_per_second)):
		await physics_frame


func _report(label: String, ok: bool) -> void:
	print("  %-62s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


var _was_mobile := false


func _finish() -> void:
	JuiceSettings.ai_slingshot = false
	Session.prefs["mobile_layout"] = _was_mobile
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		quit(1)


## Pulling: the view holds its frame and turns to look along the aim; a
## second finger looks around without ending the pull, and from then on the
## camera is left alone until the pull ends.
func _check_aim_look() -> void:
	# "Opposite on screen" is the classic aim; the dome wraps a pull down round
	# toward the camera (see _check_sling_aim_styles).
	var style := JuiceSettings.sling_aim_style
	JuiceSettings.sling_aim_style = 0.0
	await _check_aim_look_classic()
	JuiceSettings.sling_aim_style = style


func _check_aim_look_classic() -> void:
	_root.model.halt()
	await _seconds(1.0)
	var pilot := _root.pilot() as SlingshotPilot
	var rig := _root.camera_rig
	var s := pilot.ship_screen_pos()
	var edge := short()
	var cam := _root.camera_node()
	# Measured in the camera as it was at touch-down (the aim's own frame).
	var cam_xf := cam.global_transform
	_touch(s, true)
	await _frames(2)
	var pull := Vector2(edge * 0.12, edge * 0.25)
	_drag(s + pull)
	await _frames(4)
	var live_xf := cam.global_transform
	cam.global_transform = cam_xf
	var p0 := cam.unproject_position(_root.model.global_position)
	var p1 := cam.unproject_position(_root.model.global_position + pilot.aim_dir * 5.0)
	cam.global_transform = live_xf
	var off := rad_to_deg(absf((p1 - p0).angle_to(-pull)))
	print("  pull vs launch on screen: %.1f° apart (snapped onto a ship: %s)" % [off, pilot.aim_target != null])
	_report("pulling: the launch looks opposite the pull on screen", pilot.aim_target != null or off < 6.0)
	var aiming := pilot.run.state == SlingRun.State.AIMING
	var held: Variant = rig.follow_dir.call() if rig.follow_dir.is_valid() else Vector3.ZERO
	var looks := rig.look_ahead.length() > 1.0 and pilot.aim_dir != Vector3.ZERO 			and rig.look_ahead.normalized().dot(pilot.aim_dir) > 0.5
	_report("pulling: the frame holds still (no swing round behind the ship)", aiming and held == Vector3.ZERO)
	_report("pulling: the view looks along the aim", looks)
	var yaw0 := rig.user_yaw
	var look_ahead0 := rig.look_ahead
	_touch_i(1, s + Vector2(-edge * 0.4, 0.0), true)
	for k in 6:
		var e := InputEventScreenDrag.new()
		e.index = 1
		e.position = s + Vector2(-edge * 0.4 + k * 12.0, 0.0)
		e.relative = Vector2(12.0, 0.0)
		_root._unhandled_input(e)
		await _frames(1)
	_drag(s + Vector2(-edge * 0.12, edge * 0.28))
	await _frames(4)
	_report("pulling: a second finger looks around and the pull carries on",
		pilot.run.state == SlingRun.State.AIMING and absf(rig.user_yaw - yaw0) > 1.0)
	_report("pulling: after looking, the camera leaves the view alone", rig.look_ahead.is_equal_approx(look_ahead0))
	_touch_i(1, s, false)
	_touch(s + Vector2(-edge * 0.12, edge * 0.28), false)
	await _seconds(0.5)
	_report("pulling: letting go still launches", pilot.run.state == SlingRun.State.FLYING)
	# Back to the plain profile, at rest, for the checks after this one (a
	# flying sling auto-fires at whatever they put ahead).
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	_root.model.halt()
	rig.reset_user_view()
	await _seconds(0.5)
