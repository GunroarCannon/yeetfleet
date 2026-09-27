## Headless check that scenarios actually play out: sides spawn where they
## should, wingmen and enemies fight each other, the player's locked guns
## kill targets, and stopping hands the scene back to free roam.
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/scenario_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	# In memory only (no setter), so the player's saved settings stay as-is.
	JuiceSettings.player_invulnerable = true
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	_root.get_node("Ui/Coach").visible = false
	print("── scenario check ────────────────────────────────────────")
	var sc := _root.scenarios
	_report("scenario runner exists", sc != null)
	if sc == null:
		_finish()
		return

	# Skirmish: 3 enemies ahead, 2 wingmen beside the player.
	sc.start(FlightScenarios.preset("skirmish"))
	await _frames(5)
	var sp := _root._ai_spawner
	var foes := _team(sp, FlightScenarios.ENEMY_TEAM)
	var friends := _team(sp, FlightScenarios.PLAYER_TEAM)
	print("  skirmish: %d enemies, %d wingmen, status '%s'" % [foes.size(), friends.size(), sc.status_line()])
	_report("skirmish spawns 3 enemies and 2 wingmen", foes.size() == 3 and friends.size() == 2)
	var fwd := -_root.model.global_transform.basis.z
	var ahead := true
	for s in foes:
		ahead = ahead and (s.global_position - _root.model.global_position).dot(fwd) > 300.0
	_report("enemies start ahead of the player", ahead)
	_report("the ambient traffic is gone", sp.ships().size() == 5)
	var hp0 := 0.0
	for s in foes:
		hp0 += s.hp
	await _seconds(20.0)
	var hp1 := 0.0
	var dead := 0
	for s in foes:
		if is_instance_valid(s) and s._alive:
			hp1 += s.hp
		else:
			dead += 1
	print("  after 20 s: enemy hull %.0f -> %.0f, %d down, roster %d" % [hp0, hp1, dead, sp.ships().size()])
	_report("wingmen damage the enemy on their own", hp1 < hp0 * 0.9 or dead > 0)
	_report("no random traffic refills the roster", sp.ships().size() <= 5)

	# Target practice: lock and fire until the sitting ducks are gone.
	sc.start(FlightScenarios.preset("practice"))
	await _frames(5)
	var start_n := _team(sp, FlightScenarios.ENEMY_TEAM).size()
	_root.set_weapon_index(0)
	var t := 0.0
	while t < 40.0 and sc.state == FlightScenarios.State.RUNNING:
		if _root.locked_target == null or not is_instance_valid(_root.locked_target):
			_root.toggle_lock()
		_root.facing_target = true
		_root.set_firing(true)
		await _seconds(0.25)
		t += 0.25
	_root.set_firing(false)
	print("  practice: %d targets, %d kills in %.0f s, state %d, energy %.0f" % [
		start_n, sc.kills, t, sc.state, _root.systems.energy])
	_report("the player's locked guns clear target practice", sc.state == FlightScenarios.State.WON)

	sc.stop()
	await _frames(5)
	_report("stop brings the ambient fleet back", sp.auto_fleet and sp.ships().size() > 0)
	_report("stop takes the player off the team", int(_root.model.get_meta("team", 0)) == 0)
	_finish()


func _team(sp: AiSpawner, team: int) -> Array[AiShip]:
	var out: Array[AiShip] = []
	for s in sp.ships():
		if is_instance_valid(s) and s._alive and s.team_id == team:
			out.append(s)
	return out


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
