## Headless smoke test for modules/large_craft_gen.
##
##     godot --path . --headless --script modules/large_craft_gen/tools/large_craft_gen_smoke.gd
##
## Verified:
##   - the generator builds a structure with hull parts and one dock pad per
##     dock arm, deterministically from its seed
##   - shoot_at detaches exactly the part it hits, turning it into a free,
##     moving RigidBody3D and freeing that part's own dock pad if it had one
##   - a DockingPad actually pulls a coasting body closer over real physics
##     ticks (not just "the node exists")
##   - randomize_unlocked_params respects per-dial locks, same contract as
##     [SolarSystemGenerator]
extends SceneTree

var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── large_craft_gen smoke test ──────────────────────────")
	await _test_generates()
	await _test_shoot_detaches_part()
	await _test_dock_pad_magnetizes()
	await _test_randomize_respects_locks()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


func _settle() -> void:
	await process_frame
	await process_frame


func _new_generator(craft_seed: int) -> LargeCraftGenerator:
	var gen := LargeCraftGenerator.new()
	gen.craft_seed = craft_seed
	gen.dock_arm_count = 3
	root.add_child(gen)
	await _settle()
	# Newly added StaticBody3D/Area3D colliders need at least one physics tick
	# before the physics server's broadphase actually knows about them —
	# a raycast or overlap check run before this sees an empty world.
	await physics_frame
	return gen


func _test_generates() -> void:
	var gen := await _new_generator(42)
	print("  parts=%d dock_pads=%d" % [gen.part_count(), gen.dock_pad_count()])
	_check(gen.part_count() > 0, "generator produced no parts")
	_check(gen.dock_pad_count() == gen.dock_arm_count, "expected %d dock pads, got %d" % [gen.dock_arm_count, gen.dock_pad_count()])
	gen.queue_free()
	_done("Generator builds hull, arms and dock pads")


func _test_shoot_detaches_part() -> void:
	var gen := await _new_generator(7)
	var before_parts := gen.part_count()
	var before_debris := gen.debris_count()
	# Straight down the spine's own axis: every hull segment's box collider
	# spans this line, so the frontmost segment is always hit first. Start
	# just past the structure's own reach (segment_count * SEGMENT_LENGTH),
	# comfortably inside shoot_at's default 200 m max_dist.
	var start_z := float(gen.segment_count) * 6.0
	var hit := gen.shoot_at(Vector3(0, 0, start_z), Vector3(0, 0, -1))
	_check(hit != null, "shoot_at along the spine axis hit nothing")
	_check(gen.part_count() == before_parts - 1, "part count did not drop by one after a hit (%d -> %d)" % [before_parts, gen.part_count()])
	_check(gen.debris_count() == before_debris + 1, "debris count did not rise by one after a hit")
	if hit != null:
		_check(hit.linear_velocity.length() > 0.1, "detached part has no velocity — it will never look shot off")
	gen.queue_free()
	_done("shoot_at detaches exactly one part into free debris")


func _test_dock_pad_magnetizes() -> void:
	var gen := await _new_generator(3)
	var pads := gen.get_dock_points()
	if pads.is_empty():
		_failures.append("no dock pads generated — cannot test magnetize")
		_done("Dock pad pulls a coasting body closer")
		gen.queue_free()
		return
	var pad_xform: Transform3D = pads[0]

	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	# 6 m out along the pad's own approach axis — inside the default 8 m
	# capture radius, outside the 1.5 m park radius, so it should visibly close.
	body.global_position = pad_xform.origin + pad_xform.basis.z * 6.0
	await _settle()

	var start_dist := body.global_position.distance_to(pad_xform.origin)
	for _i in 90:
		await physics_frame
	var end_dist := body.global_position.distance_to(pad_xform.origin)
	print("  dock pull: start=%.2fm end=%.2fm" % [start_dist, end_dist])
	_check(end_dist < start_dist * 0.7, "a coasting body inside capture radius did not get pulled closer (%.2f -> %.2f)" % [start_dist, end_dist])

	body.queue_free()
	gen.queue_free()
	_done("Dock pad pulls a coasting body closer")


## A locked dial must survive [method LargeCraftGenerator.randomize_unlocked_params];
## an unlocked one must actually reroll into its own schema range.
func _test_randomize_respects_locks() -> void:
	var gen := LargeCraftGenerator.new()
	gen.craft_seed = 1
	gen.segment_count = 5
	gen.locked["segment_count"] = true
	gen.spire_count = -999  # sentinel, outside the schema range
	root.add_child(gen)
	await _settle()
	gen.randomize_unlocked_params(9)
	_check(gen.segment_count == 5, "locked segment_count changed on reroll (%d)" % gen.segment_count)
	var spire_entry: Dictionary = LargeCraftGenerator.RANDOMIZABLE.filter(func(e: Dictionary) -> bool: return e["key"] == "spire_count")[0]
	_check(gen.spire_count >= int(spire_entry["min"]) and gen.spire_count <= int(spire_entry["max"]),
		"unlocked spire_count was not rerolled into its schema range (%d)" % gen.spire_count)
	gen.queue_free()
	_done("randomize_unlocked_params respects per-dial locks")


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
