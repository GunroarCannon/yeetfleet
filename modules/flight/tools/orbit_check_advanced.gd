## Advanced orbital system modularity test
##
## Builds upon the existing orbit_check.gd to provide configurable,
## modular testing of orbital mechanics for different celestial bodies
## and orbital configurations.
##
##     godot --path . --headless --script modules/flight/tools/orbit_check_advanced.gd
##
## Each case is the same three steps: turn gravity pull on, put the ship at the
## case's orbit distance around the case's body, and give it that radius's
## circular velocity. The scene on its own only ever spawns the player next to
## Tarn IV, so without the placement a case aimed at Ashara was really measuring
## the distance from Tarn IV's doorstep to Ashara — a reading that can only say
## "escaped".
extends SceneTree

# === CONFIGURATION ===

# Test cases to run - each defines a different orbital scenario to test
const TEST_CASES := [
	{
		"name": "Tarn IV - Standard Orbit",
		"scene": "res://modules/flight/flight_test.tscn",
		"target_body": "Tarn IV",
		"target_radius": 1400.0,
		"orbit_distance": 4000.0,
		"orbit_tolerance": 300.0,
		"boost_threshold": 120.0,
		"moon_name": "Tarn IV Moon",
		"expected_moon_distance": 3500.0,
		"moon_tolerance": 400.0,
		"coast_frames": 480,
		"boost_frames": 360
	},
	{
		"name": "Ashara - Close Orbit",
		"scene": "res://modules/flight/flight_test.tscn", 
		"target_body": "Ashara",
		"target_radius": 600.0,
		"orbit_distance": 2500.0,
		"orbit_tolerance": 200.0,
		"boost_threshold": 100.0,
		"moon_name": "",  # Ashara has no moon in current setup
		"expected_moon_distance": 0.0,
		"moon_tolerance": 0.0,
		"coast_frames": 480,
		"boost_frames": 360
	},
	{
		"name": "Glacius - Distant Orbit",
		"scene": "res://modules/flight/flight_test.tscn",
		"target_body": "Glacius", 
		"target_radius": 220.0,
		"orbit_distance": 6000.0,
		"orbit_tolerance": 400.0,
		"boost_threshold": 150.0,
		"moon_name": "",  # Glacius has no moon in current setup
		"expected_moon_distance": 0.0,
		"moon_tolerance": 0.0,
		"coast_frames": 480,
		"boost_frames": 360
	}
]

# === TEST STATE ===

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _test_index := 0
var _failures: Array[String] = []
var _any_failure := false
var _orbit_min := INF
var _orbit_max := 0.0
var _leave_d0 := 0.0
var _target_pos_a := Vector3.ZERO
var _target_dist := 0.0
var _test_passed: bool = false

var _current_test: Dictionary

func _initialize() -> void:
	_current_test = TEST_CASES[_test_index]
	var packed := load(_current_test["scene"]) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false

	_orbit_min = INF
	_orbit_max = 0.0
	_leave_d0 = 0.0
	_failures.clear()
	_test_passed = false
	_frames = 0
	_phase = 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("FAIL: %s" % message)


## Put the ship where the case says it should start: at [member orbit_distance]
## from the target body, carrying that radius's circular velocity and pointing
## along it, exactly as [method FlightRoot.enter_orbit] would leave it. Returns
## false when the scene has no such body to orbit (the node is missing, or the
## gravity system cannot supply a circular speed there).
func _place_in_orbit() -> bool:
	if _root == null or not _root.is_inside_tree() or _root.gravity == null \
			or _root.model == null or not _root.model.is_inside_tree():
		return false
	var target_body := _get_target_body()
	if target_body == null:
		return false
	# Orbit mechanics need gravity that pulls, and the ship needs the orbital
	# assist, which stands down without it — see the pull toggle's own comment in
	# [method GravitySystem]. The game ships with pull off.
	# The system is only reachable once the scene is in the tree, which is why
	# this runs from the first process frame rather than _initialize.
	_root.gravity.pull_enabled = true
	Session.gravity_pull = true
	if _root.model.gravity == null:
		_root.model.gravity = _root.gravity
	_root.model.set_assist_mode(2)
	var distance := float(_current_test["orbit_distance"])
	var pos := target_body.global_position + Vector3(distance, 0.0, 0.0)
	var body := _root.gravity.find_dominant_body(pos)
	if body == null:
		return false
	var vel := _root.gravity.circular_orbit_velocity(body, pos)
	if vel.length_squared() < 0.001:
		return false
	_root.model.global_position = pos
	_root.model.set_velocity(vel)
	_root.model.global_transform.basis = Basis.looking_at(vel.normalized(), Vector3.UP)
	_root.model.command.throttle = 0.0
	_root.model.command.boost = false
	return true


func _get_target_body() -> Node3D:
	var target_name := String(_current_test["target_body"])
	if target_name == "Tarn IV":
		return _root.space.get_node_or_null("Planet")
	elif target_name == "Ashara":
		return _root.space.get_node_or_null("Planet2")
	elif target_name == "Glacius":
		return _root.space.get_node_or_null("Planet3")
	else:
		return _root.space.get_node_or_null(target_name)


func _process(_delta: float) -> bool:
	_frames += 1

	var target_body := _get_target_body()
	var d := 0.0
	if target_body != null:
		d = _root.model.global_position.distance_to(target_body.global_position)
	else:
		d = _root.model.global_position.length()

	match _phase:
		0:
			# Nothing can be placed until the scene is in the tree, which is the
			# first process frame after it was added.
			if not _place_in_orbit():
				_check(false, "could not start the %s scenario" % _current_test["name"])
				return _finish_test()
			_frames = 0
			_phase = 1
		1:
			_orbit_min = minf(_orbit_min, d)
			_orbit_max = maxf(_orbit_max, d)
			if _frames == 240 and target_body != null:
				_target_pos_a = target_body.global_position
			if _frames >= _current_test["coast_frames"]:
				_frames = 0
				_phase = 2
		2:
			if _frames == 1:
				_leave_d0 = d
				_root.set_throttle(1.0)
				_root.set_boosting(true)
			if _frames >= _current_test["boost_frames"]:
				_frames = 0
				_phase = 3
		3:
			return _finish_test()
	return false


func _finish_test() -> bool:
	var target_body := _get_target_body()
	var d := 0.0
	if target_body != null:
		d = _root.model.global_position.distance_to(target_body.global_position)
	else:
		d = _root.model.global_position.length()

	var target_moon := _get_target_moon()
	var moon_dist := 0.0
	var moon_moved := 0.0
	if target_moon != null:
		moon_dist = target_moon.global_position.distance_to(SpaceScene.PLANET_CENTRE)
		moon_moved = target_moon.global_position.distance_to(_target_pos_a)
	
	print("\n=== ORBIT TEST: %s ===" % _current_test["name"])
	print("  Target body: %s" % _current_test["target_body"])
	print("  Spawn orbit: min=%.0f m max=%.0f m (target: %.0f ± %.0f)" % [
		_orbit_min, _orbit_max, _current_test["orbit_distance"], _current_test["orbit_tolerance"]
	])
	
	if _orbit_min <= (_current_test["orbit_distance"] - _current_test["orbit_tolerance"]):
		_check(false, "ship fell from orbit to %.0f m" % _orbit_min)
	if _orbit_max >= (_current_test["orbit_distance"] + _current_test["orbit_tolerance"]):
		_check(false, "ship escaped to %.0f m" % _orbit_max)
	
	print("  Boosting: %.0f m -> %.0f m" % [_leave_d0, d])
	
	var boosted_out := d > (_leave_d0 + float(_current_test["boost_threshold"]))
	if not boosted_out:
		_check(false, "boosting did not push ship out of orbit")
	
	if target_moon != null and _current_test["expected_moon_distance"] > 0:
		print("  Moon: dist=%.0f m, moved=%.0f m" % [moon_dist, moon_moved])
		var moon_at_correct_dist := absf(moon_dist - float(_current_test["expected_moon_distance"])) < float(_current_test["moon_tolerance"])
		var moon_is_moving := moon_moved > 50.0
		
		if not moon_at_correct_dist:
			_check(false, "moon not at expected distance")
		if not moon_is_moving:
			_check(false, "moon is not moving")
	
	_test_passed = _failures.is_empty()
	if not _test_passed:
		_any_failure = true
	
	if _test_passed:
		print("  RESULT: PASS")
	else:
		print("  RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("    - %s" % f)
	
	print("========================\n")
	
	_test_index += 1
	if _test_index < TEST_CASES.size():
		_root.queue_free()
		_initialize()
		return false
	print("=== ALL TESTS COMPLETED ===")
	if _any_failure:
		print("SOME TESTS FAILED")
		quit(1)
		return true
	print("ALL TESTS PASSED")
	quit(0)
	return true


func _get_target_moon() -> Node3D:
	var moon_name := String(_current_test["moon_name"])
	if moon_name == "":
		return null

	if moon_name == "Tarn IV Moon":
		var planet := _root.space.get_node_or_null("Planet")
		if planet != null:
			return planet.get_node_or_null("Moon")
		return null
	else:
		return _root.get_node_or_null("%s/%s" % [String(_current_test["target_body"]), moon_name])
