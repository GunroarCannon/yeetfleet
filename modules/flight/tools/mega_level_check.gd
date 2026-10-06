## Headless check for the levels' big pieces:
## - a megastructure boss stands in the field, armed, and the fight is not
##   won while it holds together; breaking it up wins;
## - an assault's carrier can be a megastructure mothership, and breaking it
##   wins;
## - a protect (guard) job looks like one: a guard ring round the hauler, no
##   route beacon, and a tip that says how long;
## - the climb rolls megastructure bosses, sizes and hulls ([Difficulty]).
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/mega_level_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _initialize() -> void:
	print("── mega level check ──────────────────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 20:
		await process_frame
	_root.get_node("Ui/Coach").visible = false
	JuiceSettings.player_invulnerable = true
	var sc := _root.scenarios

	# --- Megastructure boss ---
	var cfg := FlightScenarios.preset("boss")
	cfg["mega_boss"] = true
	cfg["mega_kind"] = 0
	cfg["mega_size"] = FlightRoot.CraftSize.SMALL
	cfg["boss_reinforce"] = 0.0
	sc.start(cfg)
	await _seconds(0.5)
	_report("a megastructure boss stands in the field", sc.mega_alive())
	_report("it is armed", sc.mega_boss != null and sc.mega_boss.hostile)
	_report("the band shows the boss's hull", sc.status_line().contains("BOSS"))
	for s in sc._enemies.duplicate():
		if is_instance_valid(s) and s._alive:
			s.take_damage(s.max_hp * 10.0, true)
	await _seconds(4.0)
	_report("not won while it holds together", sc.state == FlightScenarios.State.RUNNING)
	if sc.mega_boss != null:
		_break(sc.mega_boss)
	await _seconds(1.0)
	for s in sc._enemies.duplicate():
		if is_instance_valid(s) and s._alive:
			s.take_damage(s.max_hp * 10.0, true)
	await _seconds(4.0)
	_report("breaking it up wins", sc.state == FlightScenarios.State.WON)
	sc.stop(false)
	await _seconds(0.5)
	_report("stopping clears the megastructure", _root.large_craft().is_empty())

	# --- Megastructure assault ---
	cfg = FlightScenarios.preset("assault")
	cfg["mega"] = true
	cfg["mega_size"] = FlightRoot.CraftSize.SMALL
	cfg["enemies"] = 0
	cfg["allies"] = 0
	sc.start(cfg)
	await _seconds(0.5)
	var mega: MegaCraft = sc._objectives.mega if sc._objectives != null else null
	_report("an assault's carrier can be a megastructure mothership", mega != null and mega.gen.archetype == LargeCraftGenerator.Archetype.MOTHERSHIP)
	_report("the band shows the mothership's hull", sc.status_line().contains("MOTHERSHIP"))
	if mega != null:
		_break(mega)
	await _seconds(1.0)
	_report("breaking it wins", sc.state == FlightScenarios.State.WON)
	sc.stop(false)
	await _seconds(0.5)

	# --- Protect looks like a guard job ---
	cfg = FlightScenarios.preset("protect")
	cfg["hold_time"] = 60.0
	cfg["enemies"] = 0
	sc.start(cfg)
	await _seconds(0.3)
	var obj := sc._objectives
	_report("a guard ring circles the hauler", obj != null and obj._guard_ring != null and is_instance_valid(obj._guard_ring))
	_report("no route beacon on a guard job", obj != null and obj._markers.is_empty() and obj._route_line == null)
	_report("the tip says how long", String(sc.config.get("tip", "")) == "GUARD IT FOR 1 MINUTE")
	_report("hold words read right", FlightScenarios.hold_words(30) == "30 SECONDS" and FlightScenarios.hold_words(120) == "2 MINUTES" and FlightScenarios.hold_words(90) == "1 MINUTE 30")
	sc.stop(false)

	# --- The climb rolls them ---
	var megas := 0
	var sizes := {}
	var presets := {}
	var boss_sizes: Array[float] = []
	for i in 200:
		var o := Difficulty.for_level(30, "boss", float(i) / 200.0)
		if bool(o.get("mega_boss", false)):
			megas += 1
			sizes[int(o["mega_size"])] = true
		presets[String(o.get("boss_preset", ""))] = true
		boss_sizes.append(float(o["boss_size"]))
	boss_sizes.sort()
	_report("late bosses are sometimes megastructures", megas > 20 and megas < 180)
	_report("megastructures come in sizes up to sun-sized", sizes.has(3) and sizes.size() >= 2)
	_report("bosses fly more than one hull", presets.size() >= 3)
	_report("boss sizes vary a lot (biggest 2x+ the smallest)", boss_sizes[-1] >= boss_sizes[0] * 2.0)
	var assault := Difficulty.for_level(20, "assault", 0.5)
	_report("later assaults bring megastructure carriers", bool(assault.get("mega", false)))
	_finish()


## Shoot parts off until it breaks up.
func _break(mega: MegaCraft) -> void:
	var gen := mega.gen
	var n := 0
	while not mega.is_dead() and n < 400 and is_instance_valid(gen):
		var parts := gen._parts.keys()
		if parts.is_empty():
			break
		gen._detach_part(parts[randi() % parts.size()], Vector3.UP)
		n += 1


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
