## PhysWorld: the per-scene service that makes every actor able to push every
## other actor.
##
## The plan's tick order, made concrete (TECHNICAL_PLAN §M1): controllers
## (FlightModel, AI) write `velocity` on their bodies during their own physics
## pass and do *not* move their nodes; then, after every controller, the world
## steps: rebuild the broadphase, resolve each candidate pair through
## [ImpulseSolver], then integrate every body's velocity into its node. Because
## resolution happens before integration, two ships that collide both change
## each other's velocity in the same step — the pile-up the gamedoc opens with
## becomes possible instead of being the thing the physics cannot do.
##
## A scene owns one of these (or shares the one from its context) and tells it
## which [PhysBody]s are live. Rocks that only matter when the player is near
## are added when they enter the activation sphere and removed when they leave —
## see the plan's note about demoting rocks back to their MultiMesh.
class_name PhysWorld
extends RefCounted

## The bodies in the world this step. The scene mutates this list; the world
## never adds or removes on its own.
var bodies: Array[PhysBody] = []

## The feel dials for this world. Defaults are the grounded-ish starting point;
## a scene chooses (and the lab authors) the real profile.
var profile: PhysProfile = null

var _stepped_pairs := 0
var _resolved_pairs := 0


func _init(p: PhysProfile = null) -> void:
	profile = p if p != null else PhysProfile.new()


func add(body: PhysBody) -> void:
	bodies.append(body)


func remove(body: PhysBody) -> void:
	bodies.erase(body)


func clear() -> void:
	bodies.clear()


## One physics step at `delta` seconds: broadphase, pair resolution, then
## integration. Call after every controller has written its body's velocity.
func step(delta: float) -> void:
	if bodies.size() < 2:
		# Fewer than two bodies cannot collide; integrate what there is.
		for body in bodies:
			_integrate(body, delta)
		return

	# Movers are bodies that can be pushed (ships, rocks, debris); scenery is
	# kinematic — infinite-mass walls. Two movers pair through the spatial hash.
	# Scenery never hashes: it is static, so it cannot need pruning against
	# itself, and hashing a 1400 m planet alongside 6 m rocks would blow the
	# cell size up and make the hash useless. Instead every mover is tested
	# against every piece of scenery directly — a couple of hundred rocks
	# against a dozen ships is a cheap sweep, and a reach check prunes each pair
	# before it spends the budget. (When rocks become movable in M1's later
	# step they join the mover hash and this sweep stops.)
	var movers: Array[PhysBody] = []
	var scenery: Array[PhysBody] = []
	for body in bodies:
		if body.kinematic:
			scenery.append(body)
		else:
			movers.append(body)

	_stepped_pairs = 0
	_resolved_pairs = 0
	var budget := profile.max_pairs_per_step
	if movers.size() >= 2:
		for pair in Broadphase.pairs(movers):
			budget = _try_pair(movers[pair[0]], movers[pair[1]], delta, budget)
	for s in scenery:
		for m in movers:
			budget = _try_pair(s, m, delta, budget)
			if budget <= 0:
				break
		if budget <= 0:
			break

	for body in bodies:
		_integrate(body, delta)


## Resolve one candidate pair if it could actually touch this step, spending
## one unit of [param budget] (returned drained) only on a pair that reaches
## the solver. Emits `impacted` on both sides when a contact was resolved.
func _try_pair(a: PhysBody, b: PhysBody, delta: float, budget: int) -> int:
	if not _layers_touch(a, b):
		return budget
	if a.kinematic and b.kinematic:
		return budget
	# Reach check before spending budget: two bodies whose spheres cannot meet
	# this step (their radii plus the furthest either travels) are a no-op.
	var travel := (a.velocity - b.velocity).length() * delta
	var reach := a.radius + b.radius + travel
	if a.position().distance_squared_to(b.position()) > reach * reach:
		return budget
	if budget <= 0:
		return budget
	budget -= 1
	_stepped_pairs += 1
	var report := ImpulseSolver.resolve(a, b, delta, profile)
	if not bool(report["resolved"]):
		return budget
	_resolved_pairs += 1
	var impulse := float(report["impulse"])
	var point: Vector3 = report["point"]
	var normal: Vector3 = report["normal"]
	var closing := float(report.get("closing", 0.0))
	a.impacted.emit(b, impulse, point, normal, closing)
	b.impacted.emit(a, impulse, point, normal, closing)
	return budget


## Does body A's mask admit body B's layer, and vice versa? Both sides have to
## agree — a ship that wants to phase through rocks, and a rock that does not
## want to be hit by that ship, are the same statement.
func _layers_touch(a: PhysBody, b: PhysBody) -> bool:
	return (a.mask & (1 << b.layer)) != 0 and (b.mask & (1 << a.layer)) != 0


## Move the body's node by its velocity and roll it by its angular velocity.
## Kinematic bodies are skipped: their controllers move them, and the world
## must not add drift on top of a planet's orbit or a station's stillness.
## Driven bodies are skipped too: a ship's FlightModel owns its motion and
## reads the solver's velocity and spin back on its own step — the world must
## not double-integrate it or roll its basis under its own rotation code.
func _integrate(body: PhysBody, delta: float) -> void:
	if body.kinematic or body.driven or body.node == null:
		return
	body.node.global_position += body.velocity * delta
	_roll(body, delta)
	_apply_angular_damping(body, delta)


func _roll(body: PhysBody, delta: float) -> void:
	if body.angular.length_squared() < 1e-12:
		return
	var basis := body.node.global_transform.basis
	basis = basis.rotated(Vector3.RIGHT, body.angular.x * delta)
	basis = basis.rotated(Vector3.UP, body.angular.y * delta)
	basis = basis.rotated(Vector3.BACK, body.angular.z * delta)
	body.node.global_transform = Transform3D(basis.orthonormalized(), body.node.global_position)


func _apply_angular_damping(body: PhysBody, delta: float) -> void:
	if body.angular == Vector3.ZERO:
		return
	var keep := maxf(0.0, 1.0 - body.angular_damping * delta)
	body.angular *= keep
