## Headless check for the sandbox and the megastructure warships:
## - a sandbox flight is a real system: outer worlds round the edge, named
##   megastructure landmarks, and the player flying for the player's team;
## - incidents do something: a raid brings real pirates and a hauler, a
##   skirmish two real sides, a meteor shower real rocks, a distress call a
##   real ship to reach (and reaching it pays);
## - a hostile dreadnought shoots (and its bolts land), launches fighters,
##   loses health as parts are shot off and breaks up; the ship can't fly
##   through a megastructure's hull.
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/sandbox_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	print("── sandbox check ─────────────────────────────────────────")
	Session.debug_mode = false
	Campaign.launch_sandbox()
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 20:
		await process_frame
	_root.get_node("Ui/Coach").visible = false
	JuiceSettings.player_invulnerable = true

	# --- A real system ---
	_report("the sandbox has its life", _root.sandbox != null)
	_report("outer worlds round the edge (5+ worlds)", _worlds() >= 5)
	_report("the player flies for the player's team", int(_root.model.get_meta("team", 0)) == FlightScenarios.PLAYER_TEAM)
	await _seconds(2.5)
	var named := 0
	for lm: Dictionary in _root.landmarks():
		if String(lm["name"]) in ["FREEPORT", "THE COLOSSUS"]:
			named += 1
	_report("megastructure landmarks stand in the system, named", named >= 1 and _root.large_craft().size() >= 1)
	_report("random incidents run in the sandbox", _root.incident_director.auto_spawn)

	# --- Incidents ---
	var sp := _root.ensure_ai_spawner()
	_root.incident_director.auto_spawn = false
	_root.incident_director.clear_all()
	var before := sp.ships().size()
	_root.incident_director.trigger_incident("pirate_raid", _root.model.global_position + Vector3(0, 0, -900))
	await _seconds(0.3)
	var job := _last_job()
	_report("a raid brings real pirates and a hauler", job.size() > 0 and (job["foes"] as Array).size() >= 2 and job["ward"] != null)
	var listed := 0
	for f: AiShip in job.get("foes", []):
		if f in sp.ships():
			listed += 1
	_report("the raid's ships are in the roster", listed >= 2 and before >= 0)
	var hostile := 0
	for f: AiShip in job.get("foes", []):
		if f.attitude_to_player() == AiShip.Attitude.HOSTILE:
			hostile += 1
	_report("raiders are hostile to the player", hostile >= 2)
	var score0 := _root.score
	for f: AiShip in job.get("foes", []):
		f.take_damage(f.max_hp * 10.0, true)
	await _seconds(0.5)
	_report("breaking the raid pays", _root.score > score0 and bool(job["done"]))

	_root.incident_director.trigger_incident("faction_skirmish", _root.model.global_position + Vector3(900, 0, 0))
	await _seconds(0.3)
	job = _last_job()
	_report("a skirmish brings two real sides", (job["foes"] as Array).size() >= 2 and (job["friends"] as Array).size() >= 2)
	var a0: AiShip = (job["friends"] as Array)[0]
	_report("the skirmish isn't aimed at the player", a0.attitude_to_player() != AiShip.Attitude.HOSTILE)

	_root.incident_director.trigger_incident("meteor_strike", _root.model.global_position + Vector3(0, 0, -900))
	await _seconds(7.5)
	job = _job_of("meteor_strike")
	var flying := 0
	for r: Dictionary in job.get("rocks", []):
		if r["node"] != null and is_instance_valid(r["node"]):
			flying += 1
	_report("a meteor shower throws real rocks", flying >= 6)

	_root.incident_director.trigger_incident("distress_call", _root.model.global_position + Vector3(0, 0, -600))
	await _seconds(0.3)
	job = _job_of("distress_call")
	var find: AiShip = job.get("find")
	_report("a distress call puts a real ship out there", find != null and is_instance_valid(find))
	if find != null:
		score0 = _root.score
		_root.model.global_position = find.global_position + Vector3(0, 0, 60)
		_root.model.velocity = Vector3.ZERO
		await _seconds(0.5)
		_report("reaching it pays", _root.score > score0 and bool(job["done"]))

	# --- A hostile dreadnought ---
	_root.incident_director.clear_all()
	JuiceSettings.player_invulnerable = false
	_root.revive_player()
	_root._grace_until_ms = 0
	var gen := _root.spawn_large_craft(LargeCraftGenerator.Archetype.DREADNOUGHT, Vector3.ZERO, FlightRoot.CraftSize.SMALL)
	var mega := _root.mega_of(gen)
	_report("a debug dreadnought comes armed and hostile", mega != null and mega.hostile)
	if mega != null:
		var hp0 := _root.player_hp
		var fighters0 := sp.ships().size()
		mega._launch_clock = 0.5
		var t := 0.0
		var fired := false
		while t < 10.0:
			_root.model.velocity = Vector3.ZERO
			if not mega._bolts.is_empty():
				fired = true
			await process_frame
			t += 1.0 / 60.0
		_report("its turrets fire", fired)
		_report("its bolts land on the player", _root.player_hp < hp0)
		# Counted on the craft: in free flight a launch clears a far-off ambient
		# ship for room, so the roster size alone doesn't move.
		_report("it launches fighters", not mega._launched.is_empty() and mega._launched[0] in sp.ships() and fighters0 >= 0)
		var h0 := mega.health()
		var c := gen.get_structure_center()
		gen.shatter_at(c, gen.approx_extent() * 0.2)
		_report("shooting parts off lowers its health", mega.health() < h0)
		var lost := 0
		while not mega.is_dead() and lost < 50:
			var parts := gen._parts.keys()
			if parts.is_empty():
				break
			gen._detach_part(parts[randi() % parts.size()], Vector3.UP)
			lost += 1
		_report("enough damage breaks it up", mega.is_dead())
		await _seconds(4.0)
		_report("the wreck is cleared away", not is_instance_valid(gen) or not gen in _root.large_craft())
	JuiceSettings.player_invulnerable = true

	# --- Its hull is solid (the reach test used to skip scaled parts) ---
	var wall := _root.spawn_large_craft(LargeCraftGenerator.Archetype.RING_STATION, Vector3.ZERO, FlightRoot.CraftSize.DEFAULT)
	await _seconds(0.3)
	var target := wall.get_structure_center()
	var closest := INF
	var start := target + Vector3(0, 0, wall.approx_extent() * 1.6)
	_root.model.global_position = start
	_root.model.reset_physics_interpolation()
	var t2 := 0.0
	while t2 < 6.0:
		_root.model.velocity = (target - _root.model.global_position).normalized() * 160.0
		await physics_frame
		t2 += 1.0 / 60.0
		closest = minf(closest, _root.model.global_position.distance_to(target))
	var through := _root.model.global_position.distance_to(start) > start.distance_to(target) * 1.5
	_report("the ship can't fly through a megastructure", not through)
	_finish()


func _worlds() -> int:
	var n := 0
	for lm: Dictionary in _root.landmarks():
		if float(lm.get("radius", 0.0)) >= 150.0 and not bool(lm.get("dynamic", false)):
			n += 1
	return n


func _last_job() -> Dictionary:
	var jobs: Array = _root.sandbox._jobs
	return jobs[jobs.size() - 1] if not jobs.is_empty() else {}


func _job_of(kind: String) -> Dictionary:
	var jobs: Array = _root.sandbox._jobs
	for i in range(jobs.size() - 1, -1, -1):
		if String(jobs[i]["kind"]) == kind:
			return jobs[i]
	return {}


func _seconds(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += 1.0 / 60.0


func _report(label: String, ok: bool) -> void:
	print("  %-60s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	print("── %s ─────────────────────────────────────────" % ("PASS" if _failures.is_empty() else "FAIL (%d)" % _failures.size()))
	JuiceSettings.load_from_disk()
	quit(0 if _failures.is_empty() else 1)
