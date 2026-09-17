## Advanced orbital system modularity test
##
## Builds upon the existing orbit_check.gd to provide configurable,
## modular testing of orbital mechanics for different celestial bodies
## and orbital configurations.

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
var _orbit_min := INF
var _orbit_max := 0.0
var _leave_d0 := 0.0
var _target_pos_a := Vector3.ZERO
var _target_dist := 0.0
var _test_passed: bool = false

var _current_test: Dictionary

func _initialize() -> void:
	var packed := load(TEST_CASES[_test_index]["scene"]) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	
	_orbit_min = INF
	_orbit_max = 0.0
	_frames = 0
	_phase = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("FAIL: %s" % message)

func _process(_delta: float) -> bool:
	_frames += 1
	_current_test = TEST_CASES[_test_index]
	
	var target_body := _get_target_body()
	var d := 0.0
	if target_body != null:
		d = _root.model.global_position.distance_to(target_body.global_position)
	else:
		d = _root.model.global_position.length()

	match _phase:
		0:
			_orbit_min = minf(_orbit_min, d)
			_orbit_max = maxf(_orbit_max, d)
			if _frames == 240 and target_body != null:
				_target_pos_a = target_body.global_position
			if _frames >= _current_test["coast_frames"]:
				_frames = 0
				_phase = 1
		1:
			if _frames == 1:
				_leave_d0 = d
				_root.set_throttle(1.0)
				_root.set_boosting(true)
			if _frames >= _current_test["boost_frames"]:
				_frames = 0
				_phase = 2
		2:
			return _finish_test()
	return false

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
	
	var orbit_held := true
	if _orbit_min <= (_current_test["orbit_distance"] - _current_test["orbit_tolerance"]):
		_check(false, "ship fell from orbit to %.0f m" % _orbit_min)
		orbit_held = false
	if _orbit_max >= (_current_test["orbit_distance"] + _current_test["orbit_tolerance"]):
		_check(false, "ship escaped to %.0f m" % _orbit_max)
		orbit_held = false
	
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
	
	_test_passed = _failures.size() == 0
	
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
	else:
		print("=== ALL TESTS COMPLETED ===")
		if _test_passed:
			print("ALL TESTS PASSED")
			quit(0)
			return true
		else:
			print("SOME TESTS FAILED")
			quit(1)
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
