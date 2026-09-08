## Headless check for the gravity-chaos toggle (Y): on, the force law slams to
## cartoon extremes and the range widens; off, the live profile's own law and
## normal range are restored.
##
##     godot --path . --headless --script modules/flight/tools/chaos_check.gd
extends SceneTree


func _initialize() -> void:
	print("── gravity chaos toggle check ─────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var root_node := packed.instantiate() as FlightRoot
	root.add_child(root_node)
	await process_frame
	await process_frame

	var failures := 0
	var g := root_node.gravity
	if g == null or root_node.phys_world == null:
		push_error("chaos check: no gravity/world")
		quit(1)
		return
	var profile := root_node.phys_world.profile

	root_node.toggle_gravity_chaos()
	if not is_equal_approx(g.falloff, root_node.GRAVITY_CHAOS_FALLOFF) \
		or not is_equal_approx(g.g, root_node.GRAVITY_CHAOS_G):
		push_error("chaos check: on did not slam the law (g %.1f falloff %.2f)" % [g.g, g.falloff])
		failures += 1
	if g.range_multiplier < 4.0:
		push_error("chaos check: range did not widen (x%.1f)" % g.range_multiplier)
		failures += 1

	root_node.toggle_gravity_chaos()
	if not is_equal_approx(g.falloff, profile.gravity_falloff) \
		or not is_equal_approx(g.g, profile.gravity_g):
		push_error("chaos check: off did not restore the profile law (g %.1f falloff %.2f)" % [g.g, g.falloff])
		failures += 1
	if not is_equal_approx(g.range_multiplier, 1.0):
		push_error("chaos check: range not restored (x%.1f)" % g.range_multiplier)
		failures += 1

	print("  %-44s %s" % ["chaos slams gravity on, restores it off", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("  (chaos g=%.0f falloff=%.2f -> profile g=%.0f falloff=%.2f)" % [
			root_node.GRAVITY_CHAOS_G, root_node.GRAVITY_CHAOS_FALLOFF,
			profile.gravity_g, profile.gravity_falloff,
		])
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
