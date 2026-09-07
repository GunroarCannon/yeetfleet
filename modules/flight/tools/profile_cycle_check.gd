## Headless check for the profile A/B toggle (KEY_K in flight): cycling the
## live profile swaps the Resource the PhysWorld holds, and the swap must change
## the dials the flight model reads (here, the assist lockout).
##
##     godot --path . --headless --script modules/flight/tools/profile_cycle_check.gd
##
## Loads the real flight scene so it exercises the exact path a player hits:
## the world built from grounded.tres, then KEY_K's cycle_phys_profile().
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
	if root_node.phys_world == null:
		push_error("profile check: no PhysWorld in space")
		quit(1)
		return

	var grounded := root_node.phys_world.profile
	var start_id := root_node.phys_profile_id()
	var cartoony_id := root_node.cycle_phys_profile()
	if cartoony_id != "cartoony":
		push_error("profile check: cycled to '%s', expected 'cartoony'" % cartoony_id)
		failures += 1
	var cartoony := root_node.phys_world.profile
	if not is_equal_approx(cartoony.assist_lockout_on_impact, 0.35):
		push_error("profile check: cartoony lockout is %.2f, expected 0.35" % cartoony.assist_lockout_on_impact)
		failures += 1
	# Back to grounded; the swap must be a live Resource change, not a rebuild.
	var back_id := root_node.cycle_phys_profile()
	if back_id != "grounded" or root_node.phys_world.profile != grounded:
		push_error("profile check: cycling back did not restore grounded (id %s)" % back_id)
		failures += 1

	print("  %-40s %s" % ["live profile cycle swaps grounded⇄cartoony", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("  (grounded lockout %.2fs, cartoony %.2fs)" % [grounded.assist_lockout_on_impact, cartoony.assist_lockout_on_impact])
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
