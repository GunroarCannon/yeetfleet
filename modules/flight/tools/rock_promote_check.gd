## Headless end-to-end check for rock promotion (M1): a hard knock must turn a
## kinematic belt rock into a free body that the world moves under gravity. (The
## visual MultiMesh instance transform cannot be trusted headless — MultiMesh
## instance buffers read back as origin outside a real rendering pass — so this
## checks the physics and that the visual binding is wired, and visual following
## is confirmed by running the game.)
##
##     godot --path . --headless --script modules/flight/tools/rock_promote_check.gd
extends SceneTree


func _initialize() -> void:
	print("── rock promotion check ───────────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var root_node := packed.instantiate() as FlightRoot
	root.add_child(root_node)
	await process_frame
	await process_frame

	var failures := 0
	var world := root_node.phys_world
	var space := root_node.space
	if world == null or space == null or world.gravity == null:
		push_error("rock check: no world/space/gravity to promote in")
		quit(1)
		return

	# A small belt rock (radius >= 6): light enough to fly visibly in 0.5 s.
	var rock: PhysBody = null
	for body in world.bodies:
		if body.kinematic and body.layer == PhysBody.Layer.ROCK and body.radius >= 6.0:
			if rock == null or body.radius < rock.radius:
				rock = body
	if rock == null:
		push_error("rock check: no rock bodies registered")
		quit(1)
		return

	var anchor := rock.node
	var anchor_pos0 := anchor.global_position
	var mm := anchor.get_meta("mm") as MultiMeshInstance3D
	if mm == null or not anchor.has_meta("j"):
		push_error("rock check: rock has no visual binding (mm/j)")
		quit(1)
		return

	# Knock it loose, pushing it away from the planet's centre. The player is
	# brought alongside: flying rocks farther than ROCK_DEMOTE_RANGE from them
	# are frozen back into scenery, and the rock picked can be kilometres off.
	var away := (anchor_pos0 - space.planet_centre).normalized()
	root_node.model.halt()
	root_node.model.global_position = anchor_pos0 - away * 300.0
	root_node._on_rock_impacted(null, 0.0, anchor_pos0, -away, 90.0, rock)
	if rock.kinematic:
		push_error("rock check: hard knock did not free the rock")
		failures += 1

	var speed0 := rock.velocity.length()
	for i in 30:
		await physics_frame

	if rock.kinematic:
		push_error("rock check: rock was demoted before it could fly")
		failures += 1
	var travelled := anchor.global_position.distance_to(anchor_pos0)
	if speed0 < 10.0:
		push_error("rock check: knock barely moved the rock (v %.1f m/s)" % speed0)
		failures += 1
	if travelled < 5.0:
		push_error("rock check: freed rock barely moved (%.1f m)" % travelled)
		failures += 1

	print("  %-44s %s" % ["a hard knock frees a rock and it flies", "ok" if failures == 0 else "FAIL"])
	if failures == 0:
		print("  (rock r=%.0f m, knocked at %.0f m/s, flew %.0f m)" % [rock.radius, speed0, travelled])
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)
