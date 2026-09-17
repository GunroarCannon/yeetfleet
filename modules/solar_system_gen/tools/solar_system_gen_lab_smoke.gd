## Headless smoke test for the solar_system_gen lab scene itself: proves the
## scene loads, builds its camera/UI/generator without error, that the
## belt-spawn button handlers actually add rocks, that clicking a body in the
## list moves the camera focus, and that "flight test" actually builds a real,
## flyable ship under the generator's gravity — the parts
## solar_system_gen_smoke.gd can't cover because it only exercises
## [SolarSystemGenerator] directly, never the lab scene wrapped around it.
##
##     godot --path . --headless --script modules/solar_system_gen/tools/solar_system_gen_lab_smoke.gd
extends SceneTree

const LAB_SCENE := "res://modules/solar_system_gen/solar_system_gen_lab.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	print("── solar_system_gen_lab smoke test ─────────────────────")
	await process_frame
	await process_frame
	await _run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var packed: PackedScene = load(LAB_SCENE)
	_check(packed != null, "lab scene failed to load")
	if packed == null:
		_finish()
		return

	var lab: SolarSystemGenLabRoot = packed.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame

	_check(lab.generator != null, "lab did not build a generator")
	_check(not lab.generator.bodies.is_empty(), "generator produced no bodies")

	var ui_canvas := lab.get_node_or_null("Ui")
	_check(ui_canvas != null, "lab did not build its UI canvas")

	var before := lab.generator.bodies.size()
	lab._on_spawn_near_belt_pressed()
	_check(lab.generator.bodies.size() > before, "spawn-near-planet belt added no rocks")

	var before_wide := lab.generator.bodies.size()
	lab._on_spawn_wide_belt_pressed()
	_check(lab.generator.bodies.size() > before_wide, "spawn-wide-system belt added no rocks")

	var text := lab.generator.describe_hierarchy()
	_check(not text.is_empty(), "describe_hierarchy() returned nothing")
	print("  hierarchy sample: " + text.split("\n")[0])

	_check_body_focus(lab)
	_check_flight_test_handoff(lab)

	lab.queue_free()
	_finish()


## Clicking a body in the list must move the orbit-camera's focus onto it, not
## leave the camera permanently centred on the star.
func _check_body_focus(lab: SolarSystemGenLabRoot) -> void:
	var planets := lab.generator.pickable_bodies().filter(
		func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET
	)
	if planets.is_empty():
		_failures.append("no planet available to test body-list focus")
		return
	var planet_name: String = planets[0]["name"]
	lab._on_body_selected(planet_name)
	_check(lab._selected_body_name == planet_name, "selecting a body did not record it as the focus")
	var focus := lab._focus_position()
	var planet_pos := (planets[0]["node"] as Node3D).global_position
	_check(focus.distance_to(planet_pos) < 1.0, "camera focus did not move to the selected body")


## "Enter flight test" no longer simulates flight in this lab scene — it hands
## the system off to the real flight_test.tscn scene (see
## [method SolarSystemGenLabRoot._on_enter_flight_test_pressed]). This checks
## the handoff data lands on [Session] correctly; whether the real scene then
## builds a flyable ship from it is
## modules/flight/tools/generated_system_smoke.gd's job, which loads that
## scene end to end.
func _check_flight_test_handoff(lab: SolarSystemGenLabRoot) -> void:
	var planets := lab.generator.pickable_bodies().filter(
		func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET
	)
	if planets.is_empty():
		_failures.append("no planet available to test the flight-test handoff")
		return
	var planet_name: String = planets[0]["name"]
	lab._on_body_selected(planet_name)
	var seed_before := lab.generator.system_seed
	lab._on_enter_flight_test_pressed()
	var recipe := Session.pending_solar_system as SolarSystemData
	_check(recipe != null, "entering flight test did not stash a SolarSystemData recipe on Session")
	if recipe != null:
		_check(recipe.system_seed == seed_before, "handed-off recipe's seed does not match the lab's system (%d vs %d)" % [recipe.system_seed, seed_before])
	_check(Session.pending_spawn_body_name == planet_name, "handed-off spawn body was not the selected planet")
	_check(Session.flight_location == FlightRoot.Location.GENERATED_SYSTEM, "flight_location was not set to GENERATED_SYSTEM")


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ " + f)
		quit(1)
