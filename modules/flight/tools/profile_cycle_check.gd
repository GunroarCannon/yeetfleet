## Headless check for the profile A/B toggle (KEY_K in flight): cycling the
## live profile swaps the Resource the PhysWorld holds, and the swap must change
## the dials the flight model reads (assist lockout) and push the new gravity
## law into the GravitySystem.
##
##     godot --path . --headless --script modules/flight/tools/profile_cycle_check.gd
##
## Loads the real flight scene so it exercises the exact path a player hits, and
## is order-independent: whichever profile the scene defaults to, cycling twice
## must visit the other profile and then return to the first.
extends SceneTree


func _initialize() -> void:
	print("── profile cycle check ─────────────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	if packed == null:
		push_error("profile check: cannot load flight_test.tscn")
		quit(1)
		return
	var root_node := packed.instantiate() as FlightRoot
	if root_node == null:
		push_error("profile check: flight_test.tscn is not a FlightRoot")
		quit(1)
		return
	root.add_child(root_node)
	# Let a couple of frames run so the scene is fully alive.
	await process_frame
	await process_frame

	var failures := 0
	var g := root_node.gravity
	if root_node.phys_world == null:
		push_error("profile check: no PhysWorld in space")
		quit(1)
		return

	var first_profile := root_node.phys_world.profile
	var first_id := root_node.phys_profile_id()
	# Cycle once: must land on a different profile and apply its gravity law.
	var second_id := root_node.cycle_phys_profile()
	var second_profile := root_node.phys_world.profile
	if second_id == first_id or second_profile == first_profile:
		push_error("profile check: cycling did not change the profile (still %s)" % first_id)
		failures += 1
	else:
		var second_lockout := second_profile.assist_lockout_on_impact
		if second_id == "cartoony" and not is_equal_approx(second_lockout, 0.35):
			push_error("profile check: cartoony lockout is %.2f, expected 0.35" % second_lockout)
			failures += 1
		if g != null and not is_equal_approx(g.falloff, second_profile.gravity_falloff):
			push_error("profile check: gravity falloff (%.2f) did not follow profile '%s' (%.2f)" % [
				g.falloff, second_id, second_profile.gravity_falloff,
			])
			failures += 1
	# Cycle back: restores the original profile resource and its gravity.
	var back_id := root_node.cycle_phys_profile()
	if back_id != first_id or root_node.phys_world.profile != first_profile:
		push_error("profile check: cycling back did not restore '%s' (id %s)" % [first_id, back_id])
		failures += 1
	if g != null and not is_equal_approx(g.falloff, first_profile.gravity_falloff):
		push_error("profile check: gravity falloff (%.2f) did not restore '%s' (%.2f)" % [
			g.falloff, first_id, first_profile.gravity_falloff,
		])
		failures += 1

	print("  %-44s %s" % ["live profile cycle swaps feel (collision + gravity)", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("  (%s lockout %.2fs / falloff %.2f  ->  %s lockout %.2fs / falloff %.2f)" % [
			first_id, first_profile.assist_lockout_on_impact, first_profile.gravity_falloff,
			second_id, second_profile.assist_lockout_on_impact, second_profile.gravity_falloff,
		])
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
