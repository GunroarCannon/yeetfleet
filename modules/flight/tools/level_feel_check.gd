## Headless check for the level dressing and the sounds that ride on it: a
## sector's last level is a boss fight (a huge warship, marked, calling in
## guards, with neutral giants and a megastructure for scenery), a graze no
## longer pops a popcorn ship, the tutorial keeps ships unhurtable until the
## wreck step, and the new sounds fire (the boss's big blast, a fly-by, the
## low-health alarm).
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/level_feel_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	# In memory only (no setter), so the player's saved settings stay as-is.
	JuiceSettings.player_invulnerable = true
	JuiceSettings.enemy_shields = false
	FxSettings.ensure_loaded()
	FxSettings.library_sounds = true
	print("── level feel check ──────────────────────────────────────")
	_levels()
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	_root.get_node("Ui/Coach").visible = false
	# The scene loads the saved dials: switch the veils off again after it.
	JuiceSettings.enemy_shields = false
	await _boss()
	await _graze()
	await _sounds()
	await _tutorial_guard()
	_finish()


## The campaign: every sector ends on its boss, and fights get their dressing.
func _levels() -> void:
	var bosses := true
	var dressed := 0
	for route in [[0], [0, 2], [0, 2, 4], [0, 1]]:
		var sec := LevelGen.sector(route)
		var last: Dictionary = sec["levels"][LevelGen.LEVELS_PER_SECTOR - 1]
		bosses = bosses and String(last["kind"]) == "boss"
		for lvl: Dictionary in sec["levels"]:
			var o: Dictionary = lvl["overrides"]
			# No big scenery anywhere: nothing may out-size a boss, and a big ship
			# on screen elsewhere should be part of the job.
			if int(o.get("bystanders", 0)) > 0 or int(o.get("backdrop", 0)) > 0:
				dressed += 1
	_report("every sector's last level is a boss fight", bosses)
	_report("no big ships unless the level needs them", dressed == 0)
	var first := LevelGen.level([0], 0)
	_report("enemies start at full strength", float(first["overrides"]["enemy_hp"]) >= 1.0)


func _boss() -> void:
	var sc := _root.scenarios
	var cfg := FlightScenarios.preset("boss")
	cfg["bystanders"] = 2
	sc.start(cfg)
	await _frames(5)
	var boss := sc.boss
	_report("the boss spawns, big and tough", boss != null and boss.scale_multiplier >= 6.0 and boss.max_hp >= 2000.0)
	_report("the boss is on the enemy side", boss != null and boss.team_id == FlightScenarios.ENEMY_TEAM)
	_report("the status line shows the boss", sc.status_line().contains("BOSS"))
	var neutral := 0
	for s in _root._ai_spawner.ships():
		if is_instance_valid(s) and s.team_id == 0 and s.scale_multiplier >= 5.0:
			neutral += 1
	_report("a boss level shows no neutral giants, even when asked", neutral == 0)
	_report("a boss level shows no megastructure, even when asked", _root.large_craft().is_empty())
	var before := sc._enemies.size()
	sc._boss_clock = float(cfg["boss_reinforce"]) - 0.05
	await _seconds(0.3)
	_report("the boss calls in guards", sc._enemies.size() > before)
	if boss != null:
		boss.shield_hp = 0.0
		boss.take_damage(boss.hp + 10.0, true)
	# Straight away: a dozen guns firing recycle the voices within frames.
	_report("wrecking the boss makes the big blast", _heard([&"explosion_big", &"explosion_far"]))
	sc.stop()
	await _frames(5)
	_report("stop clears the scenery", _root.large_craft().is_empty())
	# Scenery still works on levels that are not a boss fight.
	var sk := FlightScenarios.preset("skirmish")
	sk["bystanders"] = 2
	sk["backdrop"] = 1
	sc.start(sk)
	await _frames(5)
	var giants := 0
	for s in _root._ai_spawner.ships():
		if is_instance_valid(s) and s.team_id == 0 and s.scale_multiplier >= 5.0:
			giants += 1
	_report("neutral giants drift through a skirmish", giants == 2)
	_report("a megastructure sits in a skirmish's distance", _root.large_craft().size() == 1)
	sc.stop()
	await _frames(5)


## A graze (reach ram) no longer pops a popcorn ship; a hard ram still does.
func _graze() -> void:
	var sp := _root._ai_spawner
	sp.teardown()
	sp.auto_fleet = false
	var before := sp.ships().duplicate()
	sp.spawn_group_with(AiFactions.create(AiFactions.Archetype.BASIC_SWARM), 1, 2)
	await _frames(3)
	var ship: AiShip = null
	for s in sp.ships():
		if not (s in before) and is_instance_valid(s) and s._alive and s.archetype != null and s.archetype.popcorn:
			ship = s
	_report("a popcorn ship to ram", ship != null)
	if ship == null:
		return
	ship.shield_hp = 0.0
	var me := _root.model.phys_body()
	var n := Vector3.FORWARD
	ship.model.take_reach_ram(me, ship.model.global_position, n, 20.0)
	_report("a graze leaves a popcorn ship alive", ship._alive)
	print("  after graze: hull %.0f, shield %.0f, invulnerable %s, pilot %s, yeeting %s" % [
		ship.hp, ship.shield_hp, ship.invulnerable, ship.pilot_host, ship.model.get("yeeting")])
	ship.model._apply_collision_damage(me, 0.0, ship.model.global_position, 45.0)
	if ship._alive:
		print("  after hard ram: hull %.0f, shield %.0f" % [ship.hp, ship.shield_hp])
	_report("a hard ram still pops it", not ship._alive)


func _sounds() -> void:
	var audio := _root.audio
	var prox := _root.get_node("ProximityAudio")
	var me := _root.model
	# A pass: closing in, then pulling away, fast. The ram above left the
	# player drifting; stopped, the pass is all the other ship's speed.
	me.halt()
	var id := 12345
	var p0 := me.global_position + Vector3(20.0, 0.0, -30.0)
	prox._last_flyby = -100.0
	prox._track(audio, id, p0, Vector3(0, 0, 90), 3.0, false, me, 10.0, 0.1)
	prox._track(audio, id, me.global_position + Vector3(20.0, 0.0, -10.0), Vector3(0, 0, 90), 3.0, false, me, 10.1, 0.1)
	prox._track(audio, id, me.global_position + Vector3(20.0, 0.0, 12.0), Vector3(0, 0, 90), 3.0, false, me, 10.2, 0.1)
	_report("a close fast pass plays the fly-by", _heard([&"flyby"]))
	var big := 777
	prox._track(audio, big, me.global_position + Vector3(900, 0, 0), Vector3.ZERO, 200.0, true, me, 20.0, 0.1)
	prox._track(audio, big, me.global_position + Vector3(901, 0, 0), Vector3(12, 0, 0), 200.0, true, me, 20.1, 0.1)
	_report("a big ship getting under way starts its engines", _heard([&"big_engine"]))
	_root.player_hp = _root.player_max_hp * 0.15
	await _seconds(0.3)
	_report("low hull sounds the alarm", audio._low_health and audio._alarm_player.playing)
	_root.player_hp = _root.player_max_hp
	await _frames(3)
	_report("…and stops once patched up", not audio._low_health)


func _tutorial_guard() -> void:
	var sp := _root._ai_spawner
	sp.spawn_group_with(AiFactions.create(AiFactions.Archetype.WOLF_PIRATE), 1, 2)
	await _frames(3)
	var was_done: Variant = Session.prefs.get("tutorial_done", null)
	_root.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_root.start_tutorial()
	await _frames(3)
	var ship: AiShip = null
	for s in sp.ships():
		if is_instance_valid(s) and s._alive:
			ship = s
	var hp := ship.hp if ship != null else 0.0
	if ship != null:
		ship.take_damage(50.0, true)
	_report("tutorial: ships shrug off shots before the wreck step", ship != null and ship.hp == hp)
	_report("tutorial: orbs are held (never fade)", _root.power_ups.hold)
	_root.tutorial.stop(true)
	await _frames(3)
	_report("tutorial over: ships can be hurt again", ship != null and not ship.invulnerable)
	if was_done == null:
		Session.prefs.erase("tutorial_done")
	else:
		Session.prefs["tutorial_done"] = was_done
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)


## Whether any of [param ids]' sounds is playing in [SpaceAudio]'s pools.
func _heard(ids: Array) -> bool:
	var audio := _root.audio
	var want: Array[AudioStream] = []
	for id: StringName in ids:
		want.append_array(Sfx.streams(id))
	for p in audio._spatial_pool:
		if p.playing and p.stream in want:
			return true
	for p in audio._pilot_pool:
		if p.playing and p.stream in want:
			return true
	return false


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
