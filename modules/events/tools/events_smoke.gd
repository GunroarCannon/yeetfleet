## Headless smoke test for M4: in-world incident director & visual language.
##
##     godot --path . --headless --script modules/events/tools/events_smoke.gd
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	print("\n── events module smoke test ──────────────────────────")

	_test_icons_data()
	_test_world_marker()
	_test_event_bubble()
	_test_base_incident_lifecycle()
	_test_concrete_incident_types()
	_test_director_budget_and_pacing()
	_test_director_impact_and_touch_routing()

	if _failures.is_empty():
		print("\n── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("\n── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ %s" % f)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  %-45s ok" % description)
	else:
		print("  %-45s FAILED" % description)
		_failures.append(description)


func _test_icons_data() -> void:
	var path := "res://modules/events/data/icons.json"
	_check(FileAccess.file_exists(path), "icons.json exists")

	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "icons.json opens for read")
	if file == null:
		return

	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	_check(err == OK, "icons.json parses as valid JSON")

	var data: Dictionary = json.data
	_check(data.has("distress") and data.has("wanted") and data.has("cargo"), "icons.json contains standard vocab keys")
	_check(data.get("distress", {}).get("symbol") == "🚨", "distress symbol is 🚨")


func _test_world_marker() -> void:
	var marker := WorldMarker.new()
	_check(marker != null, "WorldMarker instantiates")

	marker.configure("distress")
	_check(marker.symbol == "🚨", "WorldMarker configures distress symbol")
	_check(marker.pulse == true, "WorldMarker distress enables pulse")

	marker.configure("cargo")
	_check(marker.symbol == "📦", "WorldMarker configures cargo symbol")
	_check(marker.pulse == false, "WorldMarker cargo pulse is false")

	# Verify process without camera does not crash
	marker._process(0.016)
	_check(true, "WorldMarker process without camera runs safely")
	marker.free()


func _test_event_bubble() -> void:
	var bubble := EventBubble.create("🚨", "DISTRESS SIGNAL", "Civilian ship under attack", Color.RED)
	_check(bubble != null, "EventBubble creates via factory")
	_check(bubble.symbol == "🚨", "EventBubble holds symbol")
	_check(bubble.title == "DISTRESS SIGNAL", "EventBubble holds title")
	_check(bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE, "EventBubble mouse filter is ignore")

	bubble._build_ui()
	_check(bubble.has_node("BubblePanel"), "EventBubble builds UI panel")
	bubble.free()


func _test_base_incident_lifecycle() -> void:
	var inc := Incident.new()
	var ctx := NebulaContext.new()
	inc.setup(ctx, Vector3(100.0, 0.0, 100.0), Vector3.ZERO)

	_check(inc.id != "", "Incident receives generated id")
	_check(not inc.is_done(), "Incident starts not done")

	inc.tick(1.0)
	_check(inc.elapsed_time == 1.0, "Incident accumulates elapsed time")

	var signal_state := {"fired": false, "cause": ""}
	inc.completed.connect(func(_id: String, how: String, _who: Variant) -> void:
		signal_state["fired"] = true
		signal_state["cause"] = how
	)

	inc.resolve("custom_reason")
	_check(inc.is_done(), "Incident is done after resolve()")
	_check(signal_state["fired"], "Incident emits completed signal on resolve")
	_check(signal_state["cause"] == "custom_reason", "Incident completed carries resolution cause")


func _test_concrete_incident_types() -> void:
	var ctx := NebulaContext.new()
	ctx.phys = PhysWorld.new()

	var types := [
		DistressCallIncident.new(),
		PirateRaidIncident.new(),
		CargoRequestIncident.new(),
		DerelictTumbleIncident.new(),
		MeteorStrikeIncident.new(),
		FactionSkirmishIncident.new(),
		RareDriftIncident.new(),
	]

	var all_setup := true
	for inc in types:
		inc.setup(ctx, Vector3(200.0, 0.0, 200.0), Vector3(10.0, 0.0, 0.0))
		if inc.actors.is_empty() and inc.phys_bodies.is_empty():
			all_setup = false
		inc.tick(0.016)
		inc.cleanup()

	_check(all_setup, "All 7 concrete incident types setup with physical bodies")


func _test_director_budget_and_pacing() -> void:
	var director := IncidentDirector.new()
	var ctx := NebulaContext.new()
	director.context = ctx
	director.max_active_incidents = 2
	director.bubble_cooldown = 10.0
	director.auto_spawn = false

	var inc1 := director.trigger_incident("distress_call", Vector3(500.0, 0.0, 0.0))
	_check(inc1 != null, "Director triggers first incident")
	_check(director.active_incidents.size() == 1, "Active count is 1")

	var inc2 := director.trigger_incident("rare_drift", Vector3(1200.0, 0.0, 0.0))
	_check(inc2 != null, "Director triggers second incident")
	_check(director.active_incidents.size() == 2, "Active count reaches max budget of 2")

	director._time_since_bubble = 0.0
	director.auto_spawn = true
	director._eval_timer = director.eval_interval + 1.0
	director.step(0.1)
	_check(director.active_incidents.size() == 2, "Director respects max active incidents budget")

	# Resolve one
	inc1.resolve("rescued")
	director.step(0.016)
	_check(director.active_incidents.size() == 1, "Director removes resolved incident from active pool")

	director.clear_all()
	_check(director.active_incidents.is_empty(), "Director clear_all cleans up cleanly")
	director.free()


func _test_director_impact_and_touch_routing() -> void:
	var director := IncidentDirector.new()
	var ctx := NebulaContext.new()
	ctx.phys = PhysWorld.new()
	director.context = ctx
	director.auto_spawn = false

	var inc := director.trigger_incident("meteor_strike", Vector3(300.0, 0.0, 0.0)) as MeteorStrikeIncident
	_check(inc != null, "MeteorStrike incident spawned")
	_check(inc.meteor_body != null, "Meteor has phys body")

	# Route high impact
	var other_body := PhysBody.new()
	director.route_impact(inc.meteor_body, other_body, 60.0)

	_check(inc.deflected, "High impact routed through director deflected the meteor")
	_check(inc.is_done(), "Deflected meteor resolved incident")

	director.clear_all()
	director.free()
