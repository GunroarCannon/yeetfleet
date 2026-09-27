class_name DebrisRegistry
extends RefCounted

## DebrisRegistry: culls debris that isn't worth its ongoing cost.
##
## Rocks, hull chunks and other short-lived scenery `RigidBody3D`/`Node3D`
## pieces spawned by planet destruction, part breakage and structural damage
## previously had no cap and no visibility-based despawn — every piece just
## rode out its own lifetime tween (up to 120s for planet debris), however
## many were alive at once. This does not replace that lifetime tween, which
## stays as the correctness backstop; it gives a random fraction of newly
## spawned pieces a much shorter leash: once fully off-screen for a while they
## are freed early, because a piece nobody is looking at is pure simulation
## and render cost for no payoff.

## Default fraction of spawned debris that gets the early-cull treatment.
const DEFAULT_CHANCE := 0.3
## Default seconds a piece must stay fully off-screen before it is freed.
const DEFAULT_GRACE := 6.0


## Give [param piece] a [param chance] (0..1) of being freed early once it has
## spent [param grace_seconds] fully off-screen. Safe to call on any
## [Node3D] already in the tree; a no-op if the roll misses (the common case),
## so most debris is untouched and still lives out its own lifetime tween.
static func maybe_cull_when_unseen(
	piece: Node3D,
	chance := DEFAULT_CHANCE,
	grace_seconds := DEFAULT_GRACE
) -> void:
	if piece == null or not is_instance_valid(piece) or not piece.is_inside_tree():
		return
	if randf() >= chance:
		return

	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "CullNotifier"
	notifier.aabb = _approx_aabb(piece)
	piece.add_child(notifier)

	var timer := Timer.new()
	timer.name = "CullTimer"
	timer.wait_time = grace_seconds
	timer.one_shot = true
	piece.add_child(timer)

	notifier.screen_exited.connect(timer.start)
	notifier.screen_entered.connect(timer.stop)
	# A direct bound-method Callable, not a lambda capturing `piece`: Godot
	# already skips a connection silently once its target is freed, but a
	# lambda's captured Object reference has no such protection — the timer
	# outlives `piece` more often than not (its own lifetime tween below can
	# free `piece` first), and a lambda here logged "Lambda capture ... was
	# freed" on every one of those (see the class doc's destruction-cost
	# framing: this fires once per culled piece).
	timer.timeout.connect(piece.queue_free)
	# A piece that starts off-screen (spawned far out, or behind the camera)
	# gets the same grace countdown rather than an instant free.
	if not notifier.is_on_screen():
		timer.start()


## Wraps [param node] in a real, collidable [RigidBody3D] so it becomes
## physical debris instead of a purely decorative [Node3D] that drifts by
## having its transform overwritten every frame (which also fights any
## physics simulation already driving it — see [method
## PhysicsDirectBodyState3D] usage elsewhere in the project). Used for any
## part-loss debris, whether from a mid-flight break-off or a full ship
## death, so both get the same real collision instead of one silently
## passing through everything.
##
## [param node] is reparented under the new body (its own transform reset to
## identity, since the body now carries the placement); the body itself is
## added under [param parent] and placed at [param orig_xform]. A box shape
## is fit to the first [MeshInstance3D] found among [param node]'s children,
## falling back to a small default box for a meshless node. Self-frees after
## [param lifetime] seconds, and gets the same early-cull-when-unseen
## treatment as any other debris via [method maybe_cull_when_unseen].
static func wrap_rigidbody(
	node: Node3D,
	orig_xform: Transform3D,
	parent: Node,
	velocity: Vector3,
	angular_velocity: Vector3,
	lifetime := 35.0,
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Debris_" + node.name
	rb.top_level = true
	# Physics-driven, so it can be drawn smoothly between ticks.
	rb.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	var b_size := Vector3(1.5, 0.8, 1.8)
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var maabb: AABB = (child as MeshInstance3D).mesh.get_aabb()
			b_size = maabb.size.clamp(Vector3(0.5, 0.5, 0.5), Vector3(8.0, 8.0, 8.0))
			break
	box_shape.size = b_size
	col_shape.shape = box_shape
	rb.add_child(col_shape)

	node.transform = Transform3D.IDENTITY
	rb.add_child(node)

	if parent != null:
		parent.add_child(rb)
		rb.global_transform = orig_xform
		rb.reset_physics_interpolation()

	rb.linear_velocity = velocity
	rb.angular_velocity = angular_velocity

	maybe_cull_when_unseen(rb)
	PerformanceSettings.ensure_loaded()
	var tw := rb.create_tween()
	tw.tween_interval(lifetime * PerformanceSettings.debris_lifetime)
	tw.tween_callback(rb.queue_free)
	_track(rb)

	return rb


## Every live wrapped debris body, oldest first — see [method _track].
## Untyped on purpose: it holds freed bodies until the next prune, and a
## typed array refuses to hand a freed instance to a typed loop variable.
static var _live := []


## Enforce [member PerformanceSettings.max_debris]: past the cap, free the
## oldest piece. A big fight or a shattered planet used to keep every chunk
## simulated and drawn for its whole lifetime, however many there were.
static func _track(rb: RigidBody3D) -> void:
	var alive := []
	for b: Variant in _live:
		if is_instance_valid(b) and not (b as Node).is_queued_for_deletion():
			alive.append(b)
	_live = alive
	_live.append(rb)
	while _live.size() > PerformanceSettings.max_debris:
		(_live.pop_front() as Node).queue_free()


## A rough local-space AABB for [param piece], from the first
## [VisualInstance3D] found anywhere under it (debris nests its mesh a level
## or two deep depending on which system built it), else a small default box.
## [VisibleOnScreenNotifier3D] only needs to be in the right ballpark, not
## exact, to avoid culling something still half in view.
static func _approx_aabb(piece: Node3D) -> AABB:
	var found: Variant = _find_visual_aabb(piece)
	return found if found != null else AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))


static func _find_visual_aabb(node: Node) -> Variant:
	for child in node.get_children():
		if child is VisualInstance3D:
			return (child as VisualInstance3D).get_aabb()
		var nested: Variant = _find_visual_aabb(child)
		if nested != null:
			return nested
	return null
