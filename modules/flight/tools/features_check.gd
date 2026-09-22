## Verifies the flight-feature batch: planet view camera, planet axial spin,
## drift field (default on + disc + streaks), default assist, and the gravity-viz
## vertex-colour fix.
##
##     godot --path . --headless --script modules/flight/tools/features_check.gd
##
## Stepped from _process, same pattern as flight_smoke.gd (which is the one the
## repo's SceneTree tools rely on; awaiting in _initialize proved fragile).
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const FRAMES_PER_STEP := 15

enum { PH_BASELINE, PH_PLANET_VIEW_SET, PH_PLANET_VIEW_CHECK, PH_STREAKS_SET, PH_STREAKS_CHECK, PH_DONE }

var _root: FlightRoot
var _phase := PH_BASELINE
var _frames := 0
var _failures: Array[String] = []
var _planet_q0 := Quaternion()
var _planet_q1 := Quaternion()
var _streak_max := 0.0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _process(_delta: float) -> bool:
	_frames += 1
	# The streak phase samples every frame to catch the stretch peak as the ship
	# accelerates under manual mode, then advances once it has 15 samples.
	if _phase == PH_STREAKS_CHECK:
		_streak_max = maxf(_streak_max, _root._mote_stretch)
		if _frames >= 15:
			# Restore the assist so later checks see the default state.
			_root.model.set_assist_mode(2)
			_check_streaks()
			_phase = PH_DONE
		return false
	if _frames < FRAMES_PER_STEP:
		return false
	_frames = 0
	match _phase:
		PH_BASELINE:
			_check_baseline()
			_phase = PH_PLANET_VIEW_SET
		PH_PLANET_VIEW_SET:
			# Engage the view; the camera settles over the next few frames.
			_root.set_view(FlightCamera.Mode.PLANET)
			_phase = PH_PLANET_VIEW_CHECK
		PH_PLANET_VIEW_CHECK:
			_check_planet_view()
			_phase = PH_STREAKS_SET
		PH_STREAKS_SET:
			# Force high speed with gravity OFF — otherwise the orbital assist
			# brakes the ship toward orbit speed and the stretch never ramps.
			if _root.gravity != null:
				_root.gravity.mode = GravitySystem.GravityMode.OFF
			# Manual mode: the throttle is a thrust lever and nothing slows you down.
			# The fly-by-wire assist (mode 2) would brake toward zero throttle, so the
			# speed has to be set in a mode that honours it.
			_root.model.set_assist_mode(0)
			_root.model.set_velocity(Vector3(0.0, 0.0, -420.0))
			# Reset the streak tracker so the measurement starts fresh.
			_root._mote_stretch = 0.0
			_root._mote_stretch_written = 0.0
			_root._mote_writing_streak = false
			_streak_max = 0.0
			_phase = PH_STREAKS_CHECK
		PH_DONE:
			return _finish()
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_baseline() -> void:
	print("── baseline ─────────────────────────────────────────")
	# Default assist is ON.
	_check(_root.assist_enabled(), "controls did not default to assist")
	print("  assist on by default: %s" % _root.assist_enabled())

	# Drift field is on by default and circular (a disc, not a cube).
	_check(_root.drift_field_on(), "drift field was off at spawn")
	# Read the CPU-side copy, not the GPU MultiMesh buffer: the headless dummy
	# renderer returns zeros from [method MultiMesh.get_instance_transform], so
	# a geometry check against it would always report "no thickness". The build
	# writes the same array to both (see [method FlightRoot._build_drift_field]).
	var positions := _root._mote_positions
	var radius := 0.0
	var max_y := 0.0
	var min_r := INF
	for i in positions.size():
		var p: Vector3 = positions[i]
		var r := Vector2(p.x, p.z).length()
		radius = maxf(radius, r)
		min_r = minf(min_r, r)
		max_y = maxf(max_y, absf(p.y))
	print("  motes: radius=%.0f max_r=%.0f max_y=%.0f" % [radius, radius, max_y])
	# Cube lattice would have corner motes at ~396 m; a disc tops out near the
	# radius (~280 m). Check no mote sits past radius + a small tolerance.
	_check(radius < 320.0, "motes extend to %.0f m — still cube-like" % radius)
	# And they are not all in the plane: there is a vertical spread.
	_check(max_y > 10.0, "drift field has no vertical thickness")
	# And some motes are near the centre (a disc fills the area).
	_check(min_r < 40.0, "drift field motes avoid the centre")

	# Planet spin: capture the body rotation to compare later.
	_planet_q0 = _get_planet_rotation()


func _get_planet_rotation() -> Quaternion:
	var body := _root.space.get_node_or_null("Planet/Body") as Node3D
	if body == null:
		return Quaternion()
	return body.global_transform.basis.get_rotation_quaternion()


func _check_planet_view() -> void:
	print("── planet view ─────────────────────────────────────")
	var body := _root.space.get_node_or_null("Planet/Body") as Node3D
	_check(_root.camera_mode() == FlightCamera.Mode.PLANET, "planet view did not engage")
	if _root.camera_mode() != FlightCamera.Mode.PLANET:
		return
	var cam := _root.camera_node()
	var nearest := _root.gravity.nearest_body(_root.model.global_position)
	_check(nearest != null, "no nearest body for the planet view")
	if nearest == null:
		return
	var centre := nearest.position
	var dist := cam.global_position.distance_to(centre)
	var expected := nearest.radius * FlightCamera.PLANET_DIST_SCALE
	print("  camera distance %.0f (expected ~%.0f, body %s r %.0f)" % [dist, expected, nearest.name, nearest.radius])
	_check(absf(dist - expected) < expected * 0.2, "planet view camera %.0f m from %s, not ~%.0f" % [dist, nearest.name, expected])
	# The camera must be looking at the body.
	var look_dir := (centre - cam.global_position).normalized()
	var fwd := -cam.global_transform.basis.z
	_check(fwd.dot(look_dir) > 0.98, "planet view camera is not looking at the body")
	# The ship is somewhere inside the frame (it's the thing orbiting the body).
	_check(cam.global_position.distance_to(_root.model.global_position) < dist * 2.0, "ship not near the planet view")

	# Planet spin: rotation should have accumulated between the baseline and now.
	_planet_q1 = _get_planet_rotation()
	var spin := _planet_q0.angle_to(_planet_q1)
	print("  planet axial spin over %.1fs: %.3f rad" % [FRAMES_PER_STEP * 3.0 / 60.0, spin])
	_check(spin > 0.001, "the planet is not spinning on its axis")

	# Gravity-viz materials must now use vertex colours (the "blue line" fix).
	_root.toggle_gravity_viz()
	var viz := _root._gravity_viz
	if viz != null and viz.is_showing():
		var orbit_mat: StandardMaterial3D = viz._orbit_mesh.material_override
		_check(orbit_mat != null and orbit_mat.vertex_color_use_as_albedo, "gravity-viz orbit material still discards vertex colours")
		print("  gravity-viz vertex colours: on")
	else:
		_check(false, "gravity visualizer failed to enable")
	_root.toggle_gravity_viz()


func _check_streaks() -> void:
	print("── streaks ─────────────────────────────────────────")
	print("  mote stretch peak after 420 m/s: %.2f" % _streak_max)
	_check(_streak_max > 0.3, "mote stretch did not ramp up with speed")


func _finish() -> bool:
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
