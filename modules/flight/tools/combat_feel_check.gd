## Headless check for the bullet-hell / fairness batch: enemy firing styles
## (fans of slow orbs), real enemy shots that land on the player's hull, the
## off-screen mercy, the chase carry, the spray-paint target markers, flying
## as another ship, and the bug hunt finding a planted aim bug.
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/combat_feel_check.gd
##
## Settings are changed in memory only (no setters), so the player's saved
## juice.cfg is untouched.
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	# The shipped defaults, not the player's saved dials: this measures the
	# feel the game ships with, whatever someone has tuned on this machine.
	JuiceSettings._loaded = true
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	# Normal speed, whatever time warp the last session saved.
	_root.set_time_scale(1.0)
	# The classic controls, whatever movement profile the last session saved
	# (a slingshot pilot holds the throttle and the guns). In memory only.
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	_root.get_node("Ui/Coach").visible = false
	print("── combat feel check ─────────────────────────────────────")
	var sp := _root.ensure_ai_spawner()
	sp.auto_fleet = false
	sp.kill_all()
	await _frames(3)
	JuiceSettings.player_invulnerable = false
	JuiceSettings._set_bool("ai_fire_patterns", true)
	JuiceSettings._set_bool("ai_real_projectiles", true)
	JuiceSettings._set_bool("cheat_offscreen_mercy", true)
	JuiceSettings._load_float("ai_fire_variety", 1.0)

	await _check_fan_of_orbs(sp)
	await _check_offscreen_mercy(sp)
	await _check_chase_assist(sp)
	await _check_markers(sp)
	await _check_fly_as(sp)
	await _check_bug_hunt(sp)
	await _check_straight_tracers()
	await _check_shot_pool_and_cap(sp)
	await _check_enemy_fire_leaves_camera(sp)
	await _check_respawn()
	await _check_pilot_damage(sp)
	_check_marker_sizes()
	_finish()


## A canted gun's tracer is drawn along its flight, not down its barrel: one
## muzzle is turned 30° off the nose, the guns converge on the sight, and every
## tracer's long axis must match its path (the player sits still, so a shot's
## path is just its velocity).
func _check_straight_tracers() -> void:
	_root.leave_control()
	var sys := _root.systems
	_root.model.halt()
	sys._clear_shots()
	sys.set_weapon_index(_weapon_index("twin_autocannon"))
	sys.energy = sys._capacity()
	var muzzles: Array = sys._get_effective_muzzles()
	var saved: Array = []
	for m: Dictionary in muzzles:
		saved.append(m["xform"])
		m["xform"] = Transform3D((m["xform"] as Transform3D).basis.rotated(Vector3.UP, deg_to_rad(30.0)), (m["xform"] as Transform3D).origin)
	_root.set_firing(true)
	await _seconds(0.25)
	_root.set_firing(false)
	var worst := 0.0
	var n := 0
	for shot: Dictionary in sys._shots:
		var node := shot["node"] as Node3D
		var v: Vector3 = shot.get("velocity", Vector3.ZERO)
		if bool(shot.get("beam", false)) or node == null or v.length() < 1.0:
			continue
		worst = maxf(worst, rad_to_deg((-node.global_transform.basis.z).angle_to(v)))
		n += 1
	for i in muzzles.size():
		(muzzles[i] as Dictionary)["xform"] = saved[i]
	print("  canted guns: %d tracers, worst angle between drawn axis and path %.2f°" % [n, worst])
	_report("tracers fly straight along their path, even from a canted gun", n > 0 and worst < 1.0)


## Spent tracers go back into the pool and come out again, and the whole-game
## enemy shot cap holds.
func _check_shot_pool_and_cap(sp: AiSpawner) -> void:
	var sys := _root.systems
	JuiceSettings._set_bool("shot_pooling", true)
	sys.set_weapon_index(_weapon_index("twin_autocannon"))
	sys.energy = sys._capacity()
	_root.set_firing(true)
	await _seconds(0.5)
	_root.set_firing(false)
	await _seconds(3.0)
	var pooled := sys._tracer_pool.size()
	var nodes_before := sys._shot_root.get_child_count()
	_root.set_firing(true)
	await _seconds(0.5)
	_root.set_firing(false)
	var nodes_after := sys._shot_root.get_child_count()
	print("  pool: %d spent tracers kept; shot nodes %d -> %d on the next burst" % [pooled, nodes_before, nodes_after])
	_report("spent tracers are kept for reuse", pooled > 0)
	_report("  and reused: a second burst builds no new nodes", nodes_after <= nodes_before)
	var cap_was := JuiceSettings.max_enemy_shots
	JuiceSettings._load_float("max_enemy_shots", 20.0)
	# Behind the player, clear of its own shots still in the air.
	var a := _parked_enemy(sp, 350.0, true)
	var b := _parked_enemy(sp, 350.0, true)
	# Side by side, so neither is in the other's line of fire.
	var side := _root.model.global_transform.basis.x * 220.0
	b.model.global_position += side
	b.global_position = b.model.global_position
	await _frames(2)
	var peak := 0
	for ship: AiShip in [a, b]:
		ship.reroll_fire_pattern("stream")
		ship.systems.target_ref = _root.model
		ship.systems.set_firing(true)
	for i in 90:
		await process_frame
		if not (is_instance_valid(a) and is_instance_valid(b)):
			break
		peak = maxi(peak, a.systems._shots.size() + b.systems._shots.size())
	print("  enemy shots in the air with a cap of 20: peak %d" % peak)
	_report("the whole-game enemy shot cap holds", peak > 0 and peak <= 20 + 2 * 5)
	JuiceSettings._load_float("max_enemy_shots", cap_was)
	for ship: Variant in [a, b]:
		if is_instance_valid(ship):
			(ship as AiShip).teardown()
	await _frames(2)


## Enemy guns no longer kick or shake the player's camera; the player's own do.
func _check_enemy_fire_leaves_camera(sp: AiSpawner) -> void:
	var shake: JuiceShake = Juice._ensure().shake
	var ship := _parked_enemy(sp, 300.0)
	await _frames(2)
	# Firing across the view, past the player: its own hits would shake it.
	var side := _root.model.global_transform.basis.x
	ship.model.global_transform = Transform3D(Basis.looking_at(side, Vector3.UP), ship.model.global_position)
	JuiceSettings.player_invulnerable = true
	ship.reroll_fire_pattern("stream")
	ship.systems.target_ref = null
	shake.reset()
	var peak := 0.0
	ship.systems.set_firing(true)
	for i in 30:
		await process_frame
		peak = maxf(peak, shake.trauma + shake._kick.length())
	ship.systems.set_firing(false)
	print("  camera shake while an enemy fires past: %.3f" % peak)
	_report("an enemy's guns do not shake or kick the player's camera", peak < 0.01)
	shake.reset()
	_root.set_firing(true)
	var own := 0.0
	for i in 10:
		await process_frame
		own = maxf(own, shake.trauma + shake._kick.length())
	_root.set_firing(false)
	_report("  the player's own guns still do", own > 0.01)
	JuiceSettings.player_invulnerable = false
	ship.teardown()
	await _frames(2)


## Death and respawn: the popup goes away, the pilot is alive, the view is the
## one they had, and a grace keeps them from dying again on arrival.
func _check_respawn() -> void:
	_root.leave_control()
	JuiceSettings.player_invulnerable = false
	var cam := _root.camera_rig
	cam.set_mode(FlightCamera.Mode.CHASE)
	var view_before := cam.mode
	_root.take_damage(_root.player_max_hp * 10.0)
	# The death beat: 1.4 s of game time at quarter speed.
	await _seconds(6.0)
	var hud: FlightHud = _root._hud
	_report("death shows the popup", hud._game_over_modal.visible and _root._player_dead)
	hud._on_respawn_pressed()
	await _frames(3)
	_report("the popup's respawn button closes it and revives the pilot", not hud._game_over_modal.visible and not _root._player_dead)
	_report("  back in the view they had before dying", cam.mode == view_before)
	var hp := _root.player_hp
	_root.take_damage(50.0)
	_report("  and nothing hurts them during the respawn grace", is_equal_approx(_root.player_hp, hp) and _root.in_respawn_grace())
	# A quick R during the death slow-mo must not leave the popup to appear later.
	_root._grace_until_ms = 0
	_root.take_damage(_root.player_max_hp * 10.0)
	await _seconds(0.3)
	_root.respawn_player_ship()
	await _seconds(1.6)
	_report("  respawning during the slow-mo: the popup never shows up", not hud._game_over_modal.visible)
	_root._grace_until_ms = 0
	_root.player_hp = _root.player_max_hp


## A ship the player flies takes hits by the player's rules, not an enemy's.
func _check_pilot_damage(sp: AiSpawner) -> void:
	var mine := _root.fly_as(1.0)
	await _frames(3)
	var foe := _parked_enemy(sp, 400.0)
	await _frames(2)
	var hp0 := mine.hp
	mine.take_damage(100.0, false, foe.systems)
	var took := hp0 - mine.hp
	print("  flown ship: %.0f hp, a 100-damage enemy hit took %.1f" % [hp0, took])
	_report("a flown ship has at least the player's hull", hp0 >= _root.player_max_hp * 0.6)
	_report("  and takes an enemy hit at the player's rate", took > 0.0 and took < 100.0 * JuiceSettings.enemy_shot_damage_scale * 1.5)
	foe.team_id = 9
	_root.set_player_team(9)
	var hp1 := mine.hp
	mine.take_damage(100.0, false, foe.systems)
	_report("  and no friendly fire", is_equal_approx(mine.hp, hp1))
	_root.set_player_team(0)
	_root.leave_control()
	foe.teardown()
	await _frames(2)


## Targets are bigger up close and smaller far away, within the dials.
func _check_marker_sizes() -> void:
	var near := InteractionMarkers.distance_scale(50.0)
	var mid := InteractionMarkers.distance_scale(900.0)
	var far := InteractionMarkers.distance_scale(8000.0)
	print("  marker size ×%.2f near, ×%.2f at 900 m, ×%.2f far" % [near, mid, far])
	_report("graffiti targets shrink with distance between their min and max",
		is_equal_approx(near, JuiceSettings.marker_max_scale) and is_equal_approx(far, JuiceSettings.marker_min_scale) \
		and mid < near and mid > far)


func _weapon_index(id: String) -> int:
	for i in SystemsSim.WEAPONS.size():
		if String(SystemsSim.WEAPONS[i]["id"]) == id:
			return i
	return 0


## A ship parked 160 m ahead of the player, facing it, AI paused.
func _parked_enemy(sp: AiSpawner, dist: float, behind := false) -> AiShip:
	var m := _root.model
	m.halt()
	var fwd := -m.global_transform.basis.z
	var pos := m.global_position + fwd * (-dist if behind else dist)
	var ship := sp.spawn_pilot_vessel(Transform3D(Basis.looking_at(m.global_position - pos, Vector3.UP), pos), 1.0)
	ship.global_position = pos
	ship.model.global_transform = Transform3D(Basis.looking_at(m.global_position - pos, Vector3.UP), pos)
	ship.is_pilot_vessel = false
	ship._ai_paused = true
	return ship


func _check_fan_of_orbs(sp: AiSpawner) -> void:
	var ship := _parked_enemy(sp, 400.0)
	await _frames(3)
	ship.systems.set_weapon_index(0)
	ship.reroll_fire_pattern("fan")
	ship.systems.target_ref = _root.model
	var hp0 := _root.player_hp
	ship.systems.set_firing(true)
	# One volley: every gun starts ready, so the first firing frame is it.
	await _frames(2)
	var shots := ship.systems._shots
	var orbs := 0
	var max_speed := 0.0
	for s: Dictionary in shots:
		if float(s.get("radius", 0.0)) > 0.0:
			orbs += 1
		max_speed = maxf(max_speed, (s["velocity"] as Vector3).length())
	print("  fan: first volley %d shots, %d orbs, fastest %.0f m/s (pulse laser is 1100)" % [shots.size(), orbs, max_speed])
	_report("a fan style fires several orbs per trigger", orbs >= 5)
	_report("  from at most two guns, however many the hull has", orbs <= 5 * 2)
	_report("its orbs are slow enough to dodge", max_speed > 0.0 and max_speed < 700.0)
	await _seconds(3.0)
	ship.systems.set_firing(false)
	print("  player hull %.0f -> %.0f, attitude %d" % [hp0, _root.player_hp, ship.attitude_to_player()])
	_report("real enemy orbs land on the player's hull", _root.player_hp < hp0)
	_report("the shooter is marked hostile", ship.attitude_to_player() == AiShip.Attitude.HOSTILE)
	_root.player_hp = _root.player_max_hp
	ship.teardown()
	await _frames(2)


func _check_offscreen_mercy(sp: AiSpawner) -> void:
	var ahead := _parked_enemy(sp, 200.0)
	var behind := _parked_enemy(sp, 200.0, true)
	await _frames(3)
	_root.player_hp = _root.player_max_hp
	JuiceSettings._load_float("offscreen_shots", 2.0)
	JuiceSettings._load_float("offscreen_window", 30.0)
	print("  camera sees the ship ahead: %s, behind: %s" % [ahead.in_player_view(), behind.in_player_view()])
	for s: AiShip in [ahead, behind]:
		s._combat_target = _root.model
		s._offview_tokens = 2.0
	var ahead_ok := true
	for i in 6:
		ahead_ok = ahead_ok and ahead.fire_gate()
	_report("an on-screen ship may fire whenever it likes", ahead_ok)
	var allowed := 0
	for i in 6:
		if behind.fire_gate():
			allowed += 1
	_report("an off-screen ship fires at the player twice, then holds (%d of 6)" % allowed, allowed == 2)
	behind._tick_offview(14.0)
	_report("  still holding before 15 s out of view", not behind.fire_gate())
	behind._tick_offview(1.5)
	_report("  one more shot after 15 s out of view", behind.fire_gate() and not behind.fire_gate())
	ahead._offview_tokens = 0.0
	ahead._tick_offview(60.0)
	_report("  the clock only runs out of view", ahead._offview_tokens < 0.01)
	behind._combat_target = ahead
	_report("  a ship shooting another ship is never held", behind.fire_gate())
	behind._combat_target = _root.model
	# Real guns: a held-down trigger from behind the camera for a second.
	behind._offview_tokens = 2.0
	behind.systems.set_weapon_index(0)
	behind.reroll_fire_pattern("stream")
	behind.systems.target_ref = _root.model
	var fired0 := behind.systems.shots_fired
	behind.systems.set_firing(true)
	await _seconds(1.0)
	behind.systems.set_firing(false)
	var fired := behind.systems.shots_fired - fired0
	var guns := behind.systems._get_effective_muzzles().size()
	print("  off-screen stream for 1 s: %d shots from %d guns" % [fired, guns])
	_report("  its guns hold fire too (two firing frames at most)", fired >= 1 and fired <= 2 * guns)
	JuiceSettings._set_bool("cheat_offscreen_mercy", false)
	_report("mercy off: an off-screen ship fires freely", behind.fire_gate() and behind.fire_gate() and behind.fire_gate())
	JuiceSettings._set_bool("cheat_offscreen_mercy", true)
	# The dice fallback has no gun to hold, so it asks at the hit.
	JuiceSettings._set_bool("ai_real_projectiles", false)
	behind._offview_tokens = 1.0
	var on := _root.take_enemy_fire(1.0, ahead.global_position, ahead.systems)
	var off1 := _root.take_enemy_fire(1.0, behind.global_position, behind.systems)
	var off2 := _root.take_enemy_fire(1.0, behind.global_position, behind.systems)
	_report("dice fallback: on-screen hits count, off-screen only on allowance", on and off1 and not off2)
	JuiceSettings._set_bool("ai_real_projectiles", true)
	_root.player_hp = _root.player_max_hp
	ahead.teardown()
	behind.teardown()
	await _frames(2)


func _check_chase_assist(sp: AiSpawner) -> void:
	var ship := _parked_enemy(sp, 220.0)
	JuiceSettings.enemies_passive = true
	ship._ai_paused = false
	JuiceSettings._set_bool("cheat_chase_assist", true)
	# Merely coming for the player (interacted, not engaged) is not a chase.
	var fwd0 := -_root.model.global_transform.basis.z
	ship.mark_interacted()
	_root.model.command.throttle = 1.0
	for i in 30:
		_root.model.velocity = fwd0 * 160.0
		await physics_frame
	_report("a ship the player has not gone after is not carried", ship.model.frame_velocity.length() < 2.0)
	ship.mark_engaged()
	var fwd := -_root.model.global_transform.basis.z
	var carried := 0.0
	for i in 60:
		ship.mark_engaged()
		_root.model.command.throttle = 1.0
		_root.model.velocity = fwd * 160.0
		# Held 220 m dead ahead: left to itself the AI wanders out of the
		# assist's range and cone within the second this takes.
		var at := _root.model.global_position + fwd * 220.0
		ship.model.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), at)
		ship.model.velocity = Vector3.ZERO
		await physics_frame
		carried = maxf(carried, ship.model.frame_velocity.dot(fwd))
	print("  chase carry along the player's line: %.0f m/s" % carried)
	_report("a chased ship is carried along at the player's speed", carried > 40.0)
	_report("the carry does not turn the ship (it is not its velocity)", ship.model.frame_velocity != ship.model.velocity)
	JuiceSettings._set_bool("cheat_chase_assist", false)
	for i in 120:
		await physics_frame
	_report("chase assist off: the carry fades to nothing", ship.model.frame_velocity.length() < 2.0)
	JuiceSettings._set_bool("cheat_chase_assist", true)
	JuiceSettings.enemies_passive = false
	_root.model.halt()
	ship.teardown()
	await _frames(2)


func _check_markers(sp: AiSpawner) -> void:
	var ship := _parked_enemy(sp, 400.0)
	await _frames(2)
	var mk := _root._interaction_markers
	_report("no marker before any interaction", not mk.snapshot().has(ship))
	ship.note_hit_player()
	# Straight after the marker is added, before its tween has run a frame.
	mk._process(0.0)
	var s0: Dictionary = mk.snapshot().get(ship, {})
	print("  marker on appear: alpha %.2f scale %.2f" % [float(s0.get("alpha", -1.0)), float(s0.get("scale", -1.0))])
	_report("the marker starts at twice its size, transparent", not s0.is_empty() and float(s0["alpha"]) < 0.05 and float(s0["scale"]) > 1.95)
	await _seconds(0.6)
	var s1: Dictionary = mk.snapshot().get(ship, {})
	var col: Color = s1.get("color", Color.BLACK)
	print("  marker settled: alpha %.2f scale %.2f colour %s" % [float(s1.get("alpha", -1.0)), float(s1.get("scale", -1.0)), col.to_html(false)])
	_report("it tweens to full alpha at its own size", absf(float(s1.get("alpha", 0.0)) - 1.0) < 0.02 and absf(float(s1.get("scale", 0.0)) - 1.0) < 0.05)
	_report("a ship that shot the player is marked red", col.r > 0.8 and col.g < 0.4)
	ship.team_id = 7
	ship.aggressive_to = [3]
	_root.set_player_team(7)
	ship._hit_player_ms = -1000000
	await _seconds(0.6)
	col = mk.snapshot().get(ship, {}).get("color", Color.BLACK)
	_report("a teammate's marker turns green", col.g > 0.7 and col.r < 0.5)
	_root.set_player_team(0)
	ship.teardown()
	await _seconds(0.5)
	_report("a dead ship's marker fades away", not mk.snapshot().has(ship))


func _check_fly_as(sp: AiSpawner) -> void:
	var tiny := _root.fly_as(0.35, 4, "stream")
	await _frames(3)
	_report("fly as tiny: the player flies it", _root.controlled_ai == tiny and tiny != null)
	_report("  with the picked gun and style", tiny.systems.get_active_weapon()["id"] == "twin_autocannon" \
		and String(tiny.fire_pattern.get("name", "")) == "stream")
	var big := _root.fly_as(12.0)
	await _frames(3)
	_report("fly as capital: the tiny one is handed back and freed", not is_instance_valid(tiny) or tiny.is_queued_for_deletion())
	_report("  and the capital hull is flown", _root.controlled_ai == big and is_equal_approx(big.scale_multiplier, 12.0))
	var hunter := _parked_enemy(sp, 300.0)
	hunter._ai_paused = false
	await _frames(3)
	_report("the AI hunts the ship being flown", hunter.player_ref == big.model)
	_root.leave_control()
	await _frames(3)
	_report("leaving control frees it and returns to the own ship", _root.controlled_ai == null and not is_instance_valid(big))
	hunter.teardown()
	await _frames(2)


func _check_bug_hunt(_sp: AiSpawner) -> void:
	JuiceSettings.player_invulnerable = true
	var hunt := _root.bug_hunt
	hunt.run_time = 1.6
	_root.set_weapon_index(1)  # sustained laser: a held beam
	var s0 := _root.active_systems()
	print("  (before hunt: cap=%.0f energy=%.0f muzzles=%d sustain=%s running=%s ctrl=%s)" % [s0._capacity(), s0.energy,
		s0._get_effective_muzzles().size(), s0.sustain_fire, s0.running, _root.controlled_ai])
	# Plant the old bugs.
	JuiceSettings._set_bool("beam_camera_aim", true)
	JuiceSettings._set_bool("shot_stable_frame", false)
	JuiceSettings._load_float("muzzle_convergence_deg", 12.0)
	JuiceSettings._set_bool("offaxis_guns_hold", false)
	hunt.hunt_ids = ["beam_camera_aim", "shot_stable_frame", "muzzle_convergence_deg", "offaxis_guns_hold", "player_spread_mult"]
	hunt.start_hunt()
	var t := 0.0
	while hunt.is_busy() and t < 40.0:
		await _seconds(0.25)
		t += 0.25
	var sys := _root.active_systems()
	print("  (player rig: dead=%s firing=%s shots=%d energy=%.0f weapon=%s)" % [_root._player_dead, sys.firing,
		sys.shots_fired, sys.energy, sys.get_active_weapon()["id"]])
	var v := hunt.verdict()
	for run: Dictionary in hunt.runs:
		var m: Dictionary = run["metrics"]
		print("    %-44s %4d samples  mean %.2f°  p95 %.2f°" % [run["label"], int(m.get("shot_dev_n", 0)),
			float(m.get("shot_dev_mean", -1.0)), float(m.get("shot_dev_p95", -1.0))])
	print("  %s" % v["text"])
	var ranked: Array = v["ranked"]
	_report("the hunt recorded the beam", float(v["baseline"]) >= 0.0)
	_report("its top suspect is one of the planted bugs", not ranked.is_empty() \
		and ["beam_camera_aim", "shot_stable_frame", "muzzle_convergence_deg", "offaxis_guns_hold"].has(String(ranked[0]["id"])) \
		and float(ranked[0]["delta"]) < 0.0)
	# Fixed settings: the beam should now hold the line.
	JuiceSettings._set_bool("beam_camera_aim", false)
	JuiceSettings._set_bool("shot_stable_frame", true)
	JuiceSettings._load_float("muzzle_convergence_deg", 180.0)
	JuiceSettings._set_bool("offaxis_guns_hold", true)
	hunt.start_run("fixed")
	while hunt.is_busy():
		await _seconds(0.25)
	var fixed: Dictionary = hunt.runs[hunt.runs.size() - 1]["metrics"]
	print("  fixed settings: beam mean %.2f°, p95 %.2f°" % [float(fixed.get("shot_dev_mean", -1.0)), float(fixed.get("shot_dev_p95", -1.0))])
	_report("with the fixes the beam stays on the gunsight line", float(fixed.get("shot_dev_mean", 99.0)) < float(v["baseline"]) \
		and float(fixed.get("shot_dev_mean", 99.0)) < 1.0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame


func _report(label: String, ok: bool) -> void:
	print("  %-58s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		quit(1)
