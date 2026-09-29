## The chain / combo / yeet batch in the real flight scene, on the shipped
## Juice defaults at ×1 time:
##
## - kills close together count a combo (x2 …) that pops a world shout and
##   drops when the window runs out;
## - the yeet clash rule: ramming into a ship faster than it comes in hurts
##   only the ship; a ship ramming into a slower player hurts both;
## - hostile ships in view yeet (wind up, then dash) at the player, never more
##   than [member JuiceSettings.yeet_max_ships] at once;
## - the swipe camera stays inside its distance window however it's pinched
##   or bumped, and looks further ahead when the ship dashes;
## - a live chain pulls the swipe heading toward the next enemy.
##
##     godot --path . --headless --fixed-fps 60 --audio-driver Dummy --script modules/flight/tools/yeet_combo_check.gd
##
## Run at 144 too.
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []
var _dropped := 0


func _check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(what)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _secs(seconds: float) -> void:
	await _ticks(int(seconds * Engine.physics_ticks_per_second))


func _on_dropped(_count: int) -> void:
	_dropped += 1


func _initialize() -> void:
	JuiceSettings._loaded = true
	# Enemy shield veils soak hits; these checks measure hull damage.
	JuiceSettings.enemy_shields = false
	JuiceSettings.kill_cam = false
	JuiceSettings.reduce_motion = false
	print("── chains, combos, yeet combat, swipe camera ──────────────")
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
	await _ticks(5)
	await _combo()
	await _clash()
	await _yeet()
	_root.revive_player()
	_root.model.halt()
	await _swipe_camera()
	await _chain_magnet()
	_finish()


# --- Combo ----------------------------------------------------------------------

func _combo() -> void:
	var chain := ComboChain.new()
	chain.dropped.connect(_on_dropped)
	JuiceSettings.chain_window = 0.3
	chain.note_kill(Vector3.ZERO)
	chain.note_kill(Vector3.ZERO)
	_check(chain.count == 2 and chain.is_live(), "two kills inside the window make a x2 chain")
	# The window is real time; under --fixed-fps game time runs faster, so
	# wait it out on the wall clock.
	OS.delay_msec(450)
	_check(not chain.is_live() and _dropped == 1, "the chain drops when the window runs out")
	JuiceSettings.chain_window = 2.5

	var ships := await _spawn(2, 300.0)
	_root.combo.reset()
	for s in ships:
		s.take_damage(s.hp + 10.0, true)
	await _ticks(2)
	_check(_root.combo.count == 2, "two player kills in a row count x2 on the flight root")
	var words: Array = _root._hud._hit_words._words
	_check(words.any(func(w: Dictionary) -> bool: return String(w["word"]) == "x2!"),
		"and a x2! pops where the kill happened")


# --- Clash rule ------------------------------------------------------------------

func _clash() -> void:
	var model := _root.model
	JuiceSettings.yeet_combat = true
	JuiceSettings.player_invulnerable = false
	# The player rams in fast; the ship sits still.
	var ai := (await _spawn(1, 40.0))[0] as AiShip
	var r := await _ram(ai, 140.0, 0.0)
	print("  player 140 m/s into a still ship: player -%.1f, ship -%.1f" % [r.x, r.y])
	_check(r.y > 0.0, "ramming a ship faster than it comes in damages it")
	_check(r.x <= 0.01, "and the player takes nothing")
	# The ship rams in; the player is slower.
	ai = (await _spawn(1, 40.0))[0] as AiShip
	r = await _ram(ai, 0.0, 140.0)
	print("  ship 140 m/s into a still player: player -%.1f, ship -%.1f" % [r.x, r.y])
	_check(r.x > 0.0, "a ship ramming a slower player hurts the player")
	_check(r.y > 0.0, "and hurts the ship too")
	JuiceSettings.player_invulnerable = true
	model.external_drive = false
	# The clash may have cost the ship its hull: whole again for what follows.
	_root.revive_player()
	await _ticks(5)


## Close [param ai] and the player at the given speeds until they touch;
## returns (player hull lost, ship hull lost).
func _ram(ai: AiShip, player_speed: float, ship_speed: float) -> Vector2:
	var model := _root.model
	_root._grace_until_ms = 0
	_root.player_shield = 0.0
	var hp0 := _root.player_hp
	var ai_hp0 := ai.hp
	var to := (ai.global_position - model.global_position).normalized()
	model.external_drive = true
	ai.model.external_drive = true
	var closest := INF
	for i in 90:
		model.set_velocity(to * player_speed)
		ai.model.set_velocity(-to * ship_speed)
		await physics_frame
		if is_instance_valid(ai) and ai._alive:
			closest = minf(closest, ai.global_position.distance_to(model.global_position))
		if not ai._alive or ai.hp < ai_hp0 or _root.player_hp < hp0:
			break
	print("    closest %.1f m, hulls %.1f + %.1f m, ai phys %s" % [closest,
		model.phys_body().radius if model.phys_body() != null else -1.0,
		ai.model.phys_body().radius if is_instance_valid(ai) and ai.model.phys_body() != null else -1.0,
		is_instance_valid(ai) and ai.model.phys_body() != null])
	await _ticks(2)
	model.external_drive = false
	model.set_velocity(Vector3.ZERO)
	var lost := Vector2(hp0 - _root.player_hp, ai_hp0 - (ai.hp if ai._alive else 0.0))
	if is_instance_valid(ai) and ai._alive:
		ai.teardown()
	return lost


# --- Yeet -------------------------------------------------------------------------

func _yeet() -> void:
	JuiceSettings.yeet_combat = true
	JuiceSettings.yeet_interval = 0.6
	JuiceSettings.yeet_windup = 0.2
	# Only armed ships can be hostile (civilians and gunless hulls never yeet).
	var ships: Array[AiShip] = []
	for tries in 4:
		for s in await _spawn(4, 350.0):
			if s.can_attack() and ships.size() < 4:
				ships.append(s)
			else:
				s.teardown()
		if ships.size() >= 3:
			break
	print("    %d armed ships in view" % ships.size())
	for s in ships:
		s.note_hit_player()
	var sp := _root.ensure_ai_spawner()
	sp.set_process(true)
	var saw_windup := false
	var saw_dash := false
	var dash_ok := false
	var most := 0
	for i in 240:
		await physics_frame
		most = maxi(most, YeetDash.live_count())
		for s in ships:
			if not is_instance_valid(s) or s._yeet == null:
				continue
			if s._yeet.state == YeetDash.State.WINDUP:
				saw_windup = true
			elif s._yeet.state == YeetDash.State.DASH and not saw_dash:
				saw_dash = true
				var v := s.model.velocity
				var to := (_root.model.global_position - s.global_position).normalized()
				var want := s.model.top_speed * JuiceSettings.yeet_speed
				print("  dash: %.0f m/s (at least %.0f), %.0f° off the player" % [v.length(), want, rad_to_deg(v.angle_to(to))])
				dash_ok = v.length() > want * 0.9 and v.angle_to(to) < deg_to_rad(40.0)
	_check(saw_windup, "a hostile ship in view winds up a yeet")
	_check(saw_dash and dash_ok, "then dashes at the player at yeet speed")
	_check(most <= int(JuiceSettings.yeet_max_ships), "never more than %d yeeting at once (saw %d)" % [int(JuiceSettings.yeet_max_ships), most])
	sp.set_process(false)
	JuiceSettings.yeet_combat = false
	for s in ships:
		if is_instance_valid(s) and s._alive:
			s.teardown()
	await _ticks(3)


# --- Swipe camera ----------------------------------------------------------------

func _swipe_camera() -> void:
	# The rams above can leave the ship flung; start the profile from rest.
	_root.model.halt()
	_root.set_move_profile(FlightRoot.MoveProfile.SWIPE)
	var rig := _root.camera_rig
	var pilot := _root._pilot as SwipePilot
	await _secs(1.5)
	var base := _cam_dist()
	var ahead_cruise := rig.look_ahead.length()
	rig.pinch_by(0.02)
	for i in 6:
		rig.bump_zoom(1.0)
		await _secs(0.25)
	await _secs(1.0)
	var out := _cam_dist() / base
	var s0 := 1.0 + JuiceSettings.swipe_cam_zoom
	var max_ratio := JuiceSettings.swipe_cam_max / s0
	print("  pinched right out and bumped: ×%.2f of the base distance (limit ×%.2f)" % [out, max_ratio])
	_check(out <= max_ratio * 1.12, "the swipe camera never pulls out past its limit")
	rig.pinch_by(100.0)
	await _secs(3.0)
	var inn := _cam_dist() / base
	var min_ratio := JuiceSettings.swipe_cam_min / s0
	print("  pinched right in: ×%.2f of the base distance (limit ×%.2f)" % [inn, min_ratio])
	_check(inn >= min_ratio * 0.85, "nor comes in past its limit")
	rig.pinch_by(rig.user_distance)
	await _secs(1.5)
	ahead_cruise = rig.look_ahead.length()
	# A long quick swipe dashes: the view looks further ahead.
	var vs := _root.get_viewport().get_visible_rect().size
	pilot._on_swipe(vs * 0.5, vs * 0.5 + Vector2(0.0, -vs.y * 0.45), 0.08)
	await _secs(0.35)
	var ahead_dash := rig.look_ahead.length()
	print("  look-ahead: cruising %.0f m, dashing %.0f m" % [ahead_cruise, ahead_dash])
	_check(ahead_cruise > 0.0 and ahead_dash > ahead_cruise * 1.3, "moving looks ahead, and dashing looks further")


func _cam_dist() -> float:
	return _root.camera_rig.global_position.distance_to(_root.model.get_global_transform_interpolated().origin)


# --- Chain magnet ------------------------------------------------------------------

func _chain_magnet() -> void:
	var pilot := _root._pilot as SwipePilot
	var model := _root.model
	await _secs(1.5)
	var h := pilot.heading
	# A hostile well off to the side: outside the launch magnet and the
	# course correction, inside the chain's wider look.
	var ship := (await _spawn(1, 10.0))[0] as AiShip
	var axis := h.cross(Vector3.UP if absf(h.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var pos := model.global_position + h.rotated(axis, deg_to_rad(75.0)) * 450.0
	ship.model.global_position = pos
	ship.global_position = pos
	ship.model.halt()
	ship.note_hit_player()
	_root.combo.reset()
	var a0 := pilot.heading.angle_to(ship.global_position - model.global_position)
	await _secs(0.5)
	var a_off := pilot.heading.angle_to(ship.global_position - model.global_position)
	_root.combo.note_kill(model.global_position)
	await _secs(0.5)
	var a_on := pilot.heading.angle_to(ship.global_position - model.global_position)
	print("  heading to the next enemy: %.0f° → %.0f° with no chain, → %.0f° with a live chain" % [
		rad_to_deg(a0), rad_to_deg(a_off), rad_to_deg(a_on)])
	_check(a_off > deg_to_rad(55.0), "without a chain the heading stays put")
	_check(a_on < a_off - deg_to_rad(20.0), "a live chain pulls it toward the next enemy")
	_check(pilot.chain_target == ship, "and picks that enemy")


# --- Helpers ------------------------------------------------------------------------

## [param count] AI ships spread in front of the player at [param dist].
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
