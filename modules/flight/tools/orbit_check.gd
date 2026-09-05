## Verifies the orbit mechanic end-to-end: the spawn orbit holds (no spiralling
## in or escaping), boosting breaks out of it, and the moon actually orbits Tarn.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/orbit_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const SPAWN_DIST := 4000.0

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _failures: Array[String] = []
var _orbit_min := INF
var _orbit_max := 0.0
var _leave_d0 := 0.0
var _moon_pos_a := Vector3.ZERO
var _moon_dist := 0.0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _process(_delta: float) -> bool:
	_frames += 1
	var d := _root.model.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	var moon := _root.space.get_node_or_null("Planet/Moon") as Node3D
	match _phase:
		0:
			# Coast in the spawn orbit for ~8 s (480 frames).
			_orbit_min = minf(_orbit_min, d)
			_orbit_max = maxf(_orbit_max, d)
			if _frames == 240 and moon != null:
				_moon_pos_a = moon.global_position
			if _frames == 480:
				_frames = 0
				_phase = 1
		1:
			# Record how far from the planet we are, then throttle+boost to leave.
			if _frames == 1:
				_leave_d0 = d
				_root.set_throttle(1.0)
				_root.set_boosting(true)
			if _frames >= 360:
				_frames = 0
				_phase = 2
		2:
			return _finish()
	return false


func _finish() -> bool:
	var d := _root.model.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	var moon := _root.space.get_node_or_null("Planet/Moon") as Node3D
	_moon_dist = moon.global_position.distance_to(SpaceScene.PLANET_CENTRE) if moon != null else -1.0

	print("── orbit check ────────────────────────────────────")
	print("  spawn orbit over 8s: min=%.0f m max=%.0f m (target ~%.0f ± 300)" % [
		_orbit_min, _orbit_max, SPAWN_DIST,
	])
	# The orbit holds: the ship never falls toward the surface nor escapes.
	_check(_orbit_min > SPAWN_DIST - 300.0, "ship fell from orbit to %.0f m — orbit did not hold" % _orbit_min)
	_check(_orbit_max < SPAWN_DIST + 400.0, "ship climbed to %.0f m — escaping on its own" % _orbit_max)

	print("  boosting: %.0f m -> %.0f m after 6s of boost" % [_leave_d0, d])
	_check(d > _leave_d0 + 300.0, "boosting did not break the orbit (%.0f -> %.0f m)" % [_leave_d0, d])

	if moon != null:
		var moved := moon.global_position.distance_to(_moon_pos_a)
		print("  moon: dist from Tarn=%.0f m, moved %.0f m in 4s" % [_moon_dist, moved])
		_check(absf(_moon_dist - 3500.0) < 400.0, "moon not on its %.0f m orbit (%.0f m)" % [3500.0, _moon_dist])
		_check(moved > 50.0, "moon is not moving — it is not orbiting")

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
