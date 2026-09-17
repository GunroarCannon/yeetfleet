## Headless stability check: proves a generated system doesn't blow up over an
## extended run, and that the predicted-orbit reference hysteresis (see
## [constant SolarSystemGenerator.PREDICTED_REF_SWITCH_MARGIN]) actually
## suppresses the rapid re-switching that used to make the debug overlay
## flicker — the discrete-jump symptom this hysteresis exists to fix.
##
##     godot --path . --headless --script modules/solar_system_gen/tools/orbit_stability_check.gd
extends SceneTree

const DT := 1.0 / 60.0
var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── orbit stability check ───────────────────────────────")
	_test_no_blowup_over_long_run()
	_test_predicted_ref_hysteresis_suppresses_flicker()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


## Several seeds, several simulated minutes at a brisk time_scale, with a wide
## belt thrown in: nothing should go non-finite or need a debugger to notice
## it's broken. This turns "run the game and watch for a while" into an
## assertion instead of a manual eyeball check.
func _test_no_blowup_over_long_run() -> void:
	for seed_candidate in [1, 2, 3, 4, 5]:
		var gen := SolarSystemGenerator.new()
		gen.system_seed = seed_candidate
		gen.planet_count = 5
		gen.time_scale = 20.0
		gen.generate_system()
		# manual=true: exercise real rock physics (not a no-op LUMPED ring) for
		# this NaN sweep — see SolarSystemGenerator.BeltState's doc.
		gen.spawn_asteroid_belt(Vector3.ZERO, 3000.0 * gen._distance_mult(), 20, 200.0, "", true)

		var steps := int(180.0 / (DT * gen.time_scale))  # ~3 simulated minutes
		for _i in steps:
			gen._physics_process(DT)

		for entry in gen.bodies:
			var pos: Vector3 = (entry["node"] as Node3D).position
			_check(is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z),
				"seed %d: %s position went non-finite (%s)" % [seed_candidate, entry["name"], pos])
		print("  seed %d: %d bodies simulated without NaN" % [seed_candidate, gen.bodies.size()])
	_done("Long run produces no NaN / infinite positions")


## Drop a probe right at the noisiest spot the generator can produce — a moon
## sitting at its own placement limit (half the Hill radius, the same one
## [method SolarSystemGenerator._spawn_moons] clamps against) — and confirm the
## predicted-orbit reference doesn't thrash every refresh now that hysteresis
## is in play. Before the fix this counted well past half the samples.
func _test_predicted_ref_hysteresis_suppresses_flicker() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 42
	gen.planet_count = 3
	gen.log_events = true
	gen.generate_system()

	var planets := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)
	var worst_switches := 0
	for planet_entry in planets:
		var node := planet_entry["node"] as Node3D
		var gbody := planet_entry["gbody"] as GravitySystem.GravityBody
		var probe_dist := gen._hill_radius(gbody, node.position) * 0.5
		if probe_dist == INF or probe_dist <= 0.0:
			continue
		var probe_pos := node.position + Vector3(probe_dist, 0.0, 0.0)
		var dominant := gen.gravity.find_dominant_body(probe_pos)
		if dominant == null:
			continue
		var probe_node := Node3D.new()
		probe_node.position = probe_pos
		var probe_entry := {
			"name": "Probe_%s" % planet_entry["name"], "node": probe_node,
			"velocity": gen._orbit_velocity_at(probe_pos, dominant),
		}
		var switches := 0
		for _i in 60:
			var before: GravitySystem.GravityBody = gen._predicted_ref.get(probe_entry["name"])
			gen.predicted_orbit_points(probe_entry)
			var after: GravitySystem.GravityBody = gen._predicted_ref.get(probe_entry["name"])
			if before != null and after != before:
				switches += 1
			# Step the probe forward under the live field between samples so its
			# position (and thus the raw, unsmoothed dominant pick) actually moves.
			for _s in 20:
				var accel := gen.gravity.compute_gravity(probe_node.position)
				probe_entry["velocity"] = (probe_entry["velocity"] as Vector3) + accel * 0.05
				probe_node.position += (probe_entry["velocity"] as Vector3) * 0.05
		worst_switches = maxi(worst_switches, switches)
	print("  worst predicted-ref switch count over 60 samples: %d" % worst_switches)
	_check(worst_switches < 15, "predicted-orbit reference still thrashes (%d switches / 60 samples)" % worst_switches)
	_done("Predicted-orbit reference hysteresis suppresses flicker")


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
