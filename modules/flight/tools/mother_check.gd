## Headless check for the mother-ship spawner: a mother is much larger than the
## fighters it ejects, both register in the shared world/gravity, and a mother's
## launch timer spawns a fighter through the spawner.
##
##     godot --path . --headless --script modules/flight/tools/mother_check.gd
extends SceneTree


func _initialize() -> void:
	print("── mother ship check ─────────────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var root_node := packed.instantiate() as FlightRoot
	root.add_child(root_node)
	await process_frame
	await process_frame

	var failures := 0
	var spawner := root_node._ai_spawner
	if spawner == null or root_node.phys_world == null:
		push_error("mother check: no spawner/world to mother in")
		quit(1)
		return

	spawner.kill_all()  # start from an empty roster so the cap does not bite
	await process_frame

	var mother := spawner.spawn_mother()
	if mother == null:
		push_error("mother check: spawn_mother returned null")
		quit(1)
	if not mother.is_mother or mother.model == null or mother._view == null:
		push_error("mother check: mother is not wired (is_mother=%s)" % mother.is_mother)
		failures += 1

	var fighter := spawner.spawn_fighter_near(mother)
	if fighter == null:
		push_error("mother check: spawn_fighter_near returned null")
		failures += 1
	else:
		var mother_r := mother._view.aabb.size.length()
		var fighter_r := fighter._view.aabb.size.length()
		print("  mother hull span %.0f m, fighter %.0f m" % [mother_r, fighter_r])
		if mother_r < fighter_r * 4.0:
			push_error("mother check: mother (%.0f) is not much bigger than its fighter (%.0f)" % [mother_r, fighter_r])
			failures += 1

	# A mother's own launch tick spawns another fighter.
	var before := spawner._ships.size()
	mother._launch_timer = 0.0
	mother.tick_ai(0.016)
	if spawner._ships.size() <= before:
		push_error("mother check: the mother's launch tick did not spawn a fighter")
		failures += 1

	# Both are live physics bodies with gravity set, so they fly and collide.
	if mother.model._phys == null or not root_node.phys_world.bodies.has(mother.model._phys):
		push_error("mother check: mother has no body in the world")
		failures += 1
	if mother.model.gravity == null:
		push_error("mother check: mother has no gravity")
		failures += 1

	print("  %-44s %s" % ["mother ships spawn huge and launch fighters", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
