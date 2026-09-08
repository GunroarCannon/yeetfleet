## Nested-orbit check: "what orbits what" is decided by strength and closeness —
## whichever body pulls hardest (g·M/r^falloff) at a point is the orbital parent.
## A moon heavy enough to win near itself must hold a body in a stable orbit
## around it even though the moon itself sits inside a planet's field.
##
##     godot --path . --headless --script modules/flight/tools/nested_orbit_check.gd
extends SceneTree


func _initialize() -> void:
	print("── nested orbit check ─────────────────────────────────")
	var failures := 0

	# --- Pure gravity-law test: does the moon win near itself, and lose far away?
	var gs := GravitySystem.new()
	var planet := gs.register_body(Vector3.ZERO, 10000000.0, 1400.0, "Tarn", true)
	var moon := gs.register_body(Vector3(3500.0, 0.0, 0.0), 2000000.0, 300.0, "Moon", true)
	var near := moon.position + Vector3(600.0, 0.0, 0.0)
	var far := moon.position + Vector3(4000.0, 0.0, 0.0)
	if gs.find_dominant_body(near) != moon:
		push_error("nested check: the moon does not win 600 m out (strength+closeness rule)")
		failures += 1
	if gs.find_dominant_body(far) != planet:
		push_error("nested check: the planet should win far out, but did not")
		failures += 1

	# --- Dynamics: a ballistic body given moon-circular velocity stays orbiting
	# the moon, not the planet, for 10 simulated seconds.
	var pos := near
	var speed := gs.orbit_velocity(moon, 600.0)
	var vel := Vector3(0.0, 0.0, -speed)
	var min_d := INF
	var max_d := 0.0
	for i in 200:
		vel += gs.compute_gravity(pos) * 0.05
		pos += vel * 0.05
		min_d = minf(min_d, pos.distance_to(moon.position))
		max_d = maxf(max_d, pos.distance_to(moon.position))
	if min_d < 500.0 or max_d > 760.0:
		push_error("nested check: moon-orbit drifted (moon dist %.0f..%.0f m)" % [min_d, max_d])
		failures += 1

	# --- In the real scene: the registered moon is heavy enough to own its sky.
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var root_node := packed.instantiate() as FlightRoot
	root.add_child(root_node)
	await process_frame
	await process_frame
	var g := root_node.gravity
	if g == null or g._bodies.size() < 4:
		push_error("nested check: no gravity bodies in the flight scene")
		failures += 1
	else:
		var scene_moon := g._bodies[3]
		if scene_moon.mass < 1000000.0:
			push_error("nested check: flight moon is still too light to own an orbit (mass %.0f)" % scene_moon.mass)
			failures += 1
		var probe := scene_moon.position + Vector3(550.0, 0.0, 0.0)
		if g.find_dominant_body(probe) != scene_moon:
			push_error("nested check: in the flight scene the moon does not own the sky 550 m out")
			failures += 1

	print("  %-44s %s" % ["orbits nest: things orbit moons that orbit planets", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("  (moon-orbit radius held %.0f..%.0f m over 10 s)" % [min_d, max_d])
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
