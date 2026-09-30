## The power-ups / shields / callouts / marks / slingshot-aim batch in the
## real flight scene, on the shipped Juice defaults at ×1 time:
##
## - no always-on design shield: the shield bar is empty until the power-up;
## - a dropped orb is taken by flying into it; the shield bubble soaks every
##   hit, does not stack (a second one refills), and pops when broken;
## - boost raises attack power and speed, then gives them back;
## - the EMP ripple freezes the ships it reaches (no firing, drifting still);
## - an enemy veil soaks hits before the hull;
## - "?" when the player shoots a ship that wasn't hostile, rate-limited;
## - a lost part and a pick-up give a callout from the player's ship;
## - scaled debris keeps its size (a physics body can't carry scale);
## - slingshot: a tap auto-aims while resting, a launch fires on its own at
##   what it heads for, and the aiming camera follows the aim;
## - the tutorial steps advance on what the player does.
##
##     godot --path . --headless --fixed-fps 60 --audio-driver Dummy --script modules/flight/tools/powerup_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []
var _marks: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(what)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _secs(seconds: float) -> void:
	await _ticks(int(seconds * Engine.physics_ticks_per_second))


func _on_marked(_ship: AiShip, mark: String) -> void:
	_marks.append(mark)


func _initialize() -> void:
	JuiceSettings._loaded = true
	JuiceSettings.kill_cam = false
	JuiceSettings.reduce_motion = false
	JuiceSettings.yeet_combat = false
	print("── power-ups, shields, callouts, marks, sling aim ─────────")
	_root = (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	await _ticks(10)
	if not is_equal_approx(_root.time_scale(), 1.0):
		_root.set_time_scale(1.0)
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	var sp := _root.ensure_ai_spawner()
	sp.teardown()
	sp.auto_fleet = false
	sp.set_process(false)
	sp.ship_marked.connect(_on_marked)
	_root.model.halt()
	await _ticks(5)
	await _shield()
	await _boost()
	await _emp()
	await _veil_and_marks()
	await _callouts()
	_debris_scale()
	await _sling()
	await _tutorial()
	_finish()


# --- Player shield ---------------------------------------------------------------

func _shield() -> void:
	_root.respawn()
	await _ticks(3)
	_root._grace_until_ms = 0
	_check(_root.player_max_shield == 0.0, "no design shield: the shield bar is empty at spawn")
	var pu := _root.power_ups
	var ahead := -_root.model.global_transform.basis.z
	pu.drop(PowerUps.Kind.SHIELD, _root.model.global_position + ahead * 30.0)
	_check(pu.orb_count() == 1, "an orb floats where it was dropped")
	await _secs(2.0)
	_check(pu.orb_count() == 0 and pu.shield_active(), "the orb drifts in, is taken, and raises the shield")
	_check(_root.player_max_shield > 0.0 and _root.player_shield == _root.player_max_shield, "the shield bar fills")
	_check(pu._bubble != null and is_instance_valid(pu._bubble), "the bubble shows round the ship")
	var hp := _root.player_hp
	_root.take_damage(_root.player_max_shield * 0.3 * JuiceSettings.player_toughness / JuiceSettings.player_damage_taken_mult)
	_check(is_equal_approx(_root.player_hp, hp), "the bubble soaks the whole hit")
	var left := _root.player_shield
	pu.grant(PowerUps.Kind.SHIELD)
	_check(_root.player_shield > left and _root.player_shield == _root.player_max_shield \
		and is_equal_approx(pu.shield_left, JuiceSettings.powerup_shield_time), "a second shield refills, never stacks")
	_root.take_damage(_root.player_max_shield * 5.0 * JuiceSettings.player_toughness)
	_check(not pu.shield_active() and _root.player_max_shield == 0.0, "a hit past its strength pops it; no shield left")
	_root.revive_player()
	await _ticks(2)


# --- Boost -----------------------------------------------------------------------

func _boost() -> void:
	var pu := _root.power_ups
	var top := _root.model.top_speed
	JuiceSettings.powerup_boost_time = 0.5
	pu.grant(PowerUps.Kind.BOOST)
	_check(is_equal_approx(AiShip.player_power_boost, JuiceSettings.powerup_boost_power), "boost raises the player's attack")
	_check(_root.model.top_speed > top * 1.1, "boost raises top speed")
	# 0.5 s of boost, plus the pickup's 0.3 s freeze frame, plus a margin.
	await _secs(1.0)
	_check(is_equal_approx(AiShip.player_power_boost, 1.0) and is_equal_approx(_root.model.top_speed, top), "boost runs out and gives both back")
	JuiceSettings.powerup_boost_time = 8.0


# --- EMP --------------------------------------------------------------------------

func _emp() -> void:
	var ships := await _spawn(2, 200.0)
	var far := await _spawn(1, JuiceSettings.powerup_emp_radius + 600.0)
	_root.power_ups.grant(PowerUps.Kind.EMP)
	await _secs(1.2)
	var near_frozen := ships.all(func(s: AiShip) -> bool: return s.is_frozen())
	_check(near_frozen, "the EMP ripple freezes ships it reaches")
	_check(not far[0].is_frozen(), "ships beyond its reach carry on")
	_check(not ships[0].fire_gate(), "a frozen ship cannot fire")
	for s in ships + far:
		s.take_damage(s.hp + 1.0)
	await _ticks(2)


# --- Enemy veil and marks --------------------------------------------------------

func _veil_and_marks() -> void:
	var ships := await _spawn(1, 120.0)
	var s := ships[0]
	s.give_shield(100.0)
	var hp := s.hp
	s.take_damage(60.0)
	_check(is_equal_approx(s.hp, hp) and is_equal_approx(s.shield_hp, 40.0), "an enemy veil soaks hits before the hull")
	s.take_damage(60.0)
	_check(s.shield_hp == 0.0 and s.hp < hp and s._veil == null, "past the veil the hull takes the rest; the veil pops")
	# "?" from being shot by someone it didn't count as an enemy.
	_marks.clear()
	s._next_mark_ms = 0
	AiShip._next_any_mark_ms = 0
	s._hit_player_ms = -1000000
	_in_front(s, 110.0)
	var was := s.attitude_to_player()
	s.take_damage(1.0, true)
	if was != AiShip.Attitude.HOSTILE:
		_check(_marks.has("?"), "a ship that wasn't hostile pops \"?\" when the player shoots it")
	s.take_damage(1.0, true)
	_check(_marks.count("?") <= 1, "marks are rate-limited (no \"?\" per hit)")
	s.take_damage(s.hp + 1.0)
	await _ticks(2)


# --- Callouts ---------------------------------------------------------------------

func _callouts() -> void:
	var co: PlayerCallouts = _root._hud._callouts
	_root.damage.break_random_part(0.5)
	await _ticks(2)
	_check(co.shown_count() >= 1, "a lost part gives a callout from the player's ship")
	_root.player_callout("TEST")
	_root.player_callout("TEST")
	_check(co.shown_count() <= PlayerCallouts.MAX_SHOWN, "callouts never pile up past the cap")
	_root.revive_player()
	await _ticks(2)


# --- Debris scale ------------------------------------------------------------------

func _debris_scale() -> void:
	var part := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	part.add_child(mi)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * 4.0), _root.model.global_position + Vector3(0, 60, 0))
	var rb := DebrisRegistry.wrap_rigidbody(part, xf, _root, Vector3.ZERO, Vector3.ZERO)
	var s := part.global_transform.basis.get_scale()
	_check(s.is_equal_approx(Vector3.ONE * 4.0), "a scaled hull's debris keeps its size")
	rb.queue_free()


# --- Slingshot ----------------------------------------------------------------------

func _sling() -> void:
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.model.halt()
	await _ticks(5)
	var pilot := _root.pilot() as SlingshotPilot
	var ships := await _spawn(1, 150.0)
	var cam := _root.camera_node()
	_in_front(ships[0], 150.0)
	_root.locked_target = null
	# A tap well away from the ship and from the enemy.
	var s := pilot.ship_screen_pos()
	var tap := Vector2(20.0, 20.0) if s.distance_to(Vector2(20, 20)) > 200.0 else Vector2(cam.get_viewport().get_visible_rect().size.x - 20.0, 20.0)
	pilot._on_tap(tap)
	await _ticks(2)
	_check(_root.locked_target == ships[0], "a tap while resting auto-aims at the ship on screen")
	_check(_root._button_firing, "…and fires")
	# Aiming: the camera holds its frame (it no longer swings round behind
	# the ship) and turns to look along the aim, following the thumb; it
	# resets on release.
	var rest := -cam.global_transform.basis.z
	var edge := minf(cam.get_viewport().get_visible_rect().size.x, cam.get_viewport().get_visible_rect().size.y)
	pilot._begin_aim()
	var a := pilot._aim_anchor
	pilot._update_aim(a + Vector2(0.0, edge * 0.01))
	pilot._update_camera()
	_check(pilot._flight_dir() == Vector3.ZERO and _root.camera_rig.look_ahead == Vector3.ZERO, "a barely-started pull leaves the camera still")
	pilot._update_aim(a + Vector2(-edge * 0.15, edge * 0.1))
	pilot._update_camera()
	var ahead := _root.camera_rig.look_ahead
	_check(pilot._flight_dir() == Vector3.ZERO and ahead.length() > 1.0 and ahead.normalized().dot(pilot.aim_dir) > 0.5,
		"aiming, the camera stays put and looks along the aim")
	pilot._update_aim(a + Vector2(edge * 0.2, edge * 0.05))
	pilot._update_camera()
	var ahead2 := _root.camera_rig.look_ahead
	_check(pilot._flight_dir() == Vector3.ZERO and ahead2.normalized().dot(pilot.aim_dir) > 0.5 and not ahead2.is_equal_approx(ahead),
		"…and the look follows the thumb")
	pilot.aim_power = 0.0
	pilot._on_released(a)
	_check(pilot._flight_dir().is_equal_approx(rest), "let go without a launch, it goes back to where it was")
	# Launched at the ship: the guns fire on their own.
	_root.locked_target = null
	var to := (ships[0].global_position - _root.model.global_position).normalized()
	pilot.run.launch(to, 0.6)
	await _ticks(6)
	_check(_root.locked_target == ships[0] and _root._button_firing, "launched, it auto-fires at what it heads for")
	ships[0].take_damage(ships[0].hp + 1.0)
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _ticks(2)


# --- Tutorial -------------------------------------------------------------------------

func _tutorial() -> void:
	var was_done: Variant = Session.prefs.get("tutorial_done", null)
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.start_tutorial()
	var tut := _root.tutorial
	# A drone to guard, then to wreck.
	var drones := await _spawn(1, 150.0)
	_check(tut.current_event() == "story", "the tutorial opens on a story card")
	# NEXT on each card, then look round and zoom, before the launch.
	for i in 2:
		tut.note("story")
		_tick_tutorial(tut)
	_check(tut.current_event() == "look", "the slingshot tutorial teaches looking round first")
	_check(tut.guards_enemies(), "ships cannot be hurt before the wreck step")
	tut.note("look", FlightTutorial.LOOK_NEED * 0.4)
	tut._process(0.016)
	_check(tut.current_event() == "look", "looking round has to add up before it ticks")
	tut.note("look", FlightTutorial.LOOK_NEED)
	_tick_tutorial(tut)
	_check(tut.current_event() == "zoom", "…then zooming")
	tut.note("zoom", FlightTutorial.ZOOM_NEED)
	_tick_tutorial(tut)
	_check(tut.current_event() == "launch", "…then the launch")
	tut.note("kill")
	tut._process(0.016)
	_check(tut.current_event() == "launch", "a step only advances on its own action")
	tut.note("launch")
	_tick_tutorial(tut)
	_check(tut.current_event() == "tap_fire", "doing it ticks it off and moves on")
	tut.note("tap_fire")
	_tick_tutorial(tut)
	tut.note("story")
	_tick_tutorial(tut)
	_check(tut.current_event() == "kill" and not tut.guards_enemies(), "at the wreck step ships can be hurt again")
	await _ticks(3)
	var pinned: Dictionary = _root._interaction_markers._pinned
	_check(pinned.has(drones[0]) and (pinned[drones[0]] as Color).is_equal_approx(InteractionMarkers.COLORS[AiShip.Attitude.HOSTILE]),
		"at the wreck step the drone wears the red target")
	for d in drones:
		if is_instance_valid(d):
			d.queue_free()
	tut.queue_free()
	if was_done == null:
		Session.prefs.erase("tutorial_done")
	else:
		Session.prefs["tutorial_done"] = was_done
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)


## Run the tutorial's clock past a step's NICE! beat.
func _tick_tutorial(tut: FlightTutorial) -> void:
	for i in int(FlightTutorial.TICK_TIME / 0.1) + 2:
		tut._process(0.1)


## Park [param s] [param dist] m straight in front of the camera: the saved
## session may have the player drifting (gravity chaos), and marks and
## auto-aim only count ships on screen.
func _in_front(s: AiShip, dist: float) -> void:
	var cam := _root.camera_node()
	var xf := Transform3D(Basis(), cam.global_position - cam.global_transform.basis.z * dist)
	s.global_transform = xf
	s.model.global_transform = xf
	s.model.halt()
	s.model.reset_physics_interpolation()


func _spawn(count: int, dist: float) -> Array[AiShip]:
	var sp := _root.ensure_ai_spawner()
	var before: Array = []
	for s in sp.ships():
		if is_instance_valid(s):
			before.append(s)
	sp.spawn_near_player(count)
	await _ticks(2)
	var model := _root.model
	var fwd := -model.global_transform.basis.z
	var right := model.global_transform.basis.x
	var out: Array[AiShip] = []
	var i := 0
	for s in sp.ships():
		if not is_instance_valid(s) or not s._alive or s in before:
			continue
		var pos := model.global_position + fwd * dist + right * (float(i) - float(count - 1) * 0.5) * 40.0
		var xf := Transform3D(Basis.looking_at(-fwd, model.global_transform.basis.y), pos)
		s.global_transform = xf
		s.model.global_transform = xf
		s.model.halt()
		s.model.reset_physics_interpolation()
		out.append(s)
		i += 1
	await _ticks(1)
	return out


func _finish() -> void:
	JuiceSettings.load_from_disk()
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
	else:
		print("── FAIL: %s" % ", ".join(_failures))
	quit(0 if _failures.is_empty() else 1)
