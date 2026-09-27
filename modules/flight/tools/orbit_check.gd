## Verifies the orbit mechanic end-to-end: the spawn orbit holds (no spiralling
## in or escaping), the fast-orbit dial really does take the same circle several
## times sooner, boosting breaks out of it, and the moon actually orbits Tarn.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/orbit_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const SPAWN_DIST := 4000.0
## Frames each orbit is measured over: the coasting baseline and the fast one use
## the same window, so the two angular travels are directly comparable.
const ORBIT_WINDOW := 240
## The dial value the fast-orbit phase runs at.
const FAST_SCALE := 4.0

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _failures: Array[String] = []
var _orbit_min := INF
var _orbit_max := 0.0
var _leave_d0 := 0.0
var _moon_pos_a := Vector3.ZERO
var _moon_dist := 0.0
var _angle_t0 := 0.0
var _angle_coast := 0.0
var _angle_fast := 0.0
var _fast_min := INF
var _fast_max := 0.0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Where the ship sits around the planet, in radians.
func _orbit_angle() -> float:
	var d := _root.model.global_position - SpaceScene.PLANET_CENTRE
	return atan2(d.z, d.x)


func _process(_delta: float) -> bool:
	_frames += 1
	# Orbit mechanics need gravity that actually pulls, and the first frame is the
	# first moment the system exists to be asked: the scene's own _ready, which
	# sets pull from Session, has not run yet while _initialize does.
	#
	# The game ships with pull off ("orbit only": bodies keep their own orbits and
	# nothing falls in), and the orbital assist deliberately stands down in that
	# mode — with no radial force there is no rail to hold and catching a ship onto
	# one would only drift it outward. This check is about the rail, so it turns
	# pull on for the run, exactly as a player does from the Gravity menu.
	if _frames == 1:
		_root.gravity.pull_enabled = true
		Session.gravity_pull = true
	# Normal speed, whatever time warp the last session saved (restored a
	# frame late, so set after it).
	if _frames == 3 and not is_equal_approx(_root.time_scale(), 1.0):
		_root.set_time_scale(1.0)
	var d := _root.model.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	var moon := _root.space.get_node_or_null("Planet/Moon") as Node3D
	match _phase:
		0:
			# Coast in the spawn orbit for ~8 s, measuring the second half.
			_orbit_min = minf(_orbit_min, d)
			_orbit_max = maxf(_orbit_max, d)
			if _frames == ORBIT_WINDOW and moon != null:
				_moon_pos_a = moon.global_position
			if _frames == ORBIT_WINDOW:
				_angle_t0 = _orbit_angle()
			if _frames == ORBIT_WINDOW * 2:
				_angle_coast = absf(wrapf(_orbit_angle() - _angle_t0, -PI, PI))
				_frames = 0
				_phase = 1
		1:
			# The same window again, now with the dial on — measured over the
			# *second* window so the assist has finished spinning the ship up to
			# the faster speed before the measurement starts, exactly as phase 0
			# does for the coasting baseline. Otherwise the comparison is really
			# "steady state vs a 4× ramp" and understates the dial.
			if _frames == 1:
				Session.fast_orbits = true
				Session.orbit_speed_scale = FAST_SCALE
			if _frames == ORBIT_WINDOW:
				_angle_t0 = _orbit_angle()
			if _frames > ORBIT_WINDOW:
				_fast_min = minf(_fast_min, d)
				_fast_max = maxf(_fast_max, d)
			if _frames >= ORBIT_WINDOW * 2:
				_angle_fast = absf(wrapf(_orbit_angle() - _angle_t0, -PI, PI))
				Session.fast_orbits = false
				_frames = 0
				_phase = 2
		2:
			# Record how far from the planet we are, then throttle+boost to leave.
			if _frames == 1:
				_leave_d0 = d
				_root.set_throttle(1.0)
				_root.set_boosting(true)
			if _frames >= 360:
				_frames = 0
				_phase = 3
		3:
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

	print("  fast orbits ×%.0f over the same %.0fs: %.3f rad vs %.3f rad coasting; radius %.0f-%.0f m" % [
		FAST_SCALE, float(ORBIT_WINDOW) / 60.0, _angle_fast, _angle_coast, _fast_min, _fast_max,
	])
	# "Really fast" is the whole point of the dial, and it must still be an orbit:
	# the same circle taken sooner, not a ship flung off into space. Settled, the
	# ratio should land near the dial's own value, so anything under 3 has lost
	# most of it to the initial spin-up or to the hold dragging.
	_check(_angle_fast > _angle_coast * 3.0,
		"fast orbits did not speed the orbit up (%.3f rad vs %.3f rad coasting)" % [_angle_fast, _angle_coast])
	_check(_fast_min > SPAWN_DIST - 600.0 and _fast_max < SPAWN_DIST + 600.0,
		"the fast orbit wandered off its radius (%.0f-%.0f m, spawn %.0f m)" % [_fast_min, _fast_max, SPAWN_DIST])

	print("  boosting: %.0f m -> %.0f m after 6s of boost" % [_leave_d0, d])
	# The invariant is "a boost pushes you out of orbit", not a fixed distance:
	# under a cartoon gravity profile (shallower falloff) escape takes longer, so
	# require a solid outward climb rather than the inverse-square's ~380 m.
	_check(d > _leave_d0 + 120.0, "boosting did not push the ship out of orbit (%.0f -> %.0f m)" % [_leave_d0, d])

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
