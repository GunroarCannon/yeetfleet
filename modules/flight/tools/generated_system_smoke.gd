## Verifies [constant FlightRoot.Location] value GENERATED_SYSTEM end to end: a
## solar-system-gen lab handoff (Session.pending_solar_system +
## pending_spawn_body_name + flight_location) produces a real flight scene
## with the player ship in a clean orbit under the generated system's own
## gravity — the scene-side half of "flight test loads the solar system into
## the real flight scene" (the lab-side half is
## modules/solar_system_gen/tools/solar_system_gen_lab_smoke.gd's
## _check_flight_test_handoff).
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/generated_system_smoke.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _failures: Array[String] = []
var _dominant: GravitySystem.GravityBody = null
var _d0 := 0.0
var _d_min := INF
var _d_max := 0.0


func _initialize() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 55
	gen.planet_count = 3
	gen.generate_system()
	var planets := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)
	var target_name: String = String(planets[0]["name"]) if not planets.is_empty() else ""

	Session.pending_solar_system = SolarSystemData.from_generator(gen)
	Session.pending_spawn_body_name = target_name
	Session.flight_location = FlightRoot.Location.GENERATED_SYSTEM

	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_check(_root.location == FlightRoot.Location.GENERATED_SYSTEM, "FlightRoot did not boot into GENERATED_SYSTEM")
		_check(_root.generated_system != null, "FlightRoot built no generated_system")
		if _root.generated_system != null:
			_check(_root.gravity == _root.generated_system.gravity, "FlightRoot did not reuse the generator's own gravity")
			_check(not _root.generated_system.bodies.is_empty(), "the handed-off system generated no bodies")
		var pos := _root.model.global_position
		_check(is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z), "player ship spawned at a non-finite position")
		_check(pos.length() > 1.0, "player ship spawned at the world origin — spawn-near-body placement did not run")
		_dominant = _root.gravity.find_dominant_body(pos) if _root.gravity != null else null
		if _dominant == null:
			_failures.append("player ship has no dominant gravity body at spawn")
			return _finish()
		_d0 = pos.distance_to(_dominant.position)
		_d_min = _d0
		_d_max = _d0
		return false
	if _frames <= 240:
		var d := _root.model.global_position.distance_to(_dominant.position)
		_d_min = minf(_d_min, d)
		_d_max = maxf(_d_max, d)
		if _frames == 240:
			return _finish()
	return false


## The spawn orbit must hold for a few seconds — same invariant
## modules/flight/tools/orbit_check.gd checks for the hand-authored SpaceScene.
func _finish() -> bool:
	print("── generated-system flight scene smoke test ────────────")
	print("  spawn orbit over 4s: start=%.0f min=%.0f max=%.0f" % [_d0, _d_min, _d_max])
	_check(_d_min > _d0 * 0.5, "ship fell toward the body (%.0f -> %.0f)" % [_d0, _d_min])
	_check(_d_max < _d0 * 2.0, "ship escaped its spawn orbit (%.0f -> %.0f)" % [_d0, _d_max])
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
		return true
	print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
	for f in _failures:
		print("  · " + f)
	quit(1)
	return true
