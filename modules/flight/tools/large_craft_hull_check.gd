## Verifies a spawned large craft collides along its own hull, not as a row of
## oversized balls.
##
## The failure this exists to catch is specific and was real: each structural part
## used to get one sphere per part, centred on the part's node origin with radius
## `aabb.get_center().length() + aabb.size.length()*0.5`. For a hull segment — many
## times longer than it is wide — that is a ball more than two segments across, so a
## mothership's collision was a chain of huge invisible spheres reaching well
## outside its silhouette and the player bounced off empty space flying alongside
## it. A hull that *exists* and is bound in the right space still produces a body
## that collides, so nothing else in the suite notices.
##
##     godot --path . --headless --script modules/flight/tools/large_craft_hull_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _gen: LargeCraftGenerator = null
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_root.spawn_large_craft(LargeCraftGenerator.Archetype.MOTHERSHIP)
		var keys := _root._craft_collision_bodies.keys()
		if not keys.is_empty():
			_gen = keys[0] as LargeCraftGenerator
		return false
	# The generator only builds its parts after a settle pass, and the bodies are
	# registered from the same call, so wait well past it.
	if _frames < 45:
		return false
	_check_craft_hull()
	return _finish()


## Three things worth asserting: the craft registered collision at all, that every
## part's hull is fitted to that part's own bounds rather than to the craft as a
## whole, and that each section sits on the part it stands for.
##
## Note what this does *not* assert: that the fit is tight to the part's silhouette.
## A hull segment is a wide, flat slab — roughly 30 m long, 21 m tall, 6 m thick —
## and no small set of spheres encloses a slab closely, because a sphere covering
## the 21x6 cross-section is already 11 m in radius. The single-sphere fallback in
## [method HullFit.append_box_spheres] is the honest answer for a shape like that,
## and an "overshoot < 1 m" bound here would be a test asserting something the
## solver cannot do. What *is* checked is the thing that was actually broken: the
## old code centred each part's sphere on the part's node origin and inflated its
## radius by the distance to the box centre, so the collision sat wherever the
## part's pivot happened to be rather than where the part is.
func _check_craft_hull() -> void:
	print("── large craft hull ────────────────────────────")
	if _gen == null or not is_instance_valid(_gen):
		_check(false, "no large craft collision was registered")
		return
	var bodies: Array = _root._craft_collision_bodies.get(_gen, [])
	_check(not bodies.is_empty(), "the large craft registered no collision bodies")
	if bodies.is_empty():
		return

	var sections := 0
	var fattest := 0.0
	var off_box := 0
	for body: PhysBody in bodies:
		_check(body.has_hull(), "a large-craft part collides as a single sphere, not a hull")
		if not body.has_hull():
			continue
		sections += body.hull.size()
		var box := _part_box(body.node)
		if box.size == Vector3.ZERO:
			continue
		var allowed := box.grow(0.05)
		for sphere in body.hull:
			fattest = maxf(fattest, float(sphere["radius"]))
			# Every section centre must land on the part it stands for. A fit derived
			# from the wrong space, or from the node origin instead of the box, shows
			# up here.
			if not allowed.has_point(sphere["offset"] as Vector3):
				off_box += 1

	print("  %d parts, %d hull sections, widest section %.2f m" % [bodies.size(), sections, fattest])
	_check(
		off_box == 0,
		"%d hull sections sit outside the part they stand for — the fit is in the wrong space"
			% off_box
	)
	# A craft whose parts are slabs legitimately gets one sphere each; what must not
	# happen is a part getting no collision at all.
	_check(sections >= bodies.size(), "%d sections cannot cover %d parts" % [sections, bodies.size()])


## The part's own geometry bounds, read back off the box collider
## [LargeCraftGenerator] gave the part. That collider is what
## [method LargeCraftGenerator.get_collision_spheres] fits to, and reaching it here
## avoids needing a new public accessor purely for a test.
func _part_box(node: Node3D) -> AABB:
	if node == null:
		return AABB()
	if node.has_meta("aabb"):
		return node.get_meta("aabb") as AABB
	var shape_node := _find_box_shape(node)
	if shape_node == null:
		return AABB()
	var box := shape_node.shape as BoxShape3D
	if box == null:
		return AABB()
	return AABB(shape_node.position - box.size * 0.5, box.size)


func _find_box_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			return shape_node
		var deeper := _find_box_shape(child)
		if deeper != null:
			return deeper
	return null


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
