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

## Optional scene gravity, applied each step to *free* bodies — things that are
## neither kinematic scenery nor driven by a controller, which in flight means a
## rock that was knocked loose. With this set, a promoted rock falls and orbits
## like everything else instead of coasting forever. Null leaves free bodies
## drifting at constant velocity.
var gravity: GravitySystem = null

var _stepped_pairs := 0
var _resolved_pairs := 0


func _init(p: PhysProfile = null) -> void:
	profile = p if p != null else PhysProfile.new()


func add(body: PhysBody) -> void:
	bodies.append(body)
	if body.kinematic:
		_scenery_dirty = true


func remove(body: PhysBody) -> void:
	bodies.erase(body)
	if body.kinematic:
		_scenery_dirty = true


func clear() -> void:
	bodies.clear()
	_scenery_dirty = true


## A body's kinematic flag changed outside the world (a rock promoted to free
## body or demoted back to scenery): the scenery index must rebuild next step so
## the body lands in the right bucket.
func mark_scenery_dirty() -> void:
	_scenery_dirty = true


## One physics step at `delta` seconds: broadphase, pair resolution, then
## integration. Call after every controller has written its body's velocity.
func step(delta: float) -> void:
	if bodies.size() < 2:
		# Fewer than two bodies cannot collide; integrate what there is.
		for body in bodies:
			_integrate(body, delta)
		return
	if _scenery_dirty:
		_build_scenery_index()

	# Movers are bodies that can be pushed (ships, rocks, debris); scenery is
	# kinematic — infinite-mass walls. Two movers pair through the spatial hash.
	# Scenery never pairs against itself and never hashes with movers: a rock is
	# only ever collided with by the movers near it, so instead of sweeping every
	# mover against every rock (O(ships × 270 rocks) every step — plan §3.1 #10,
	# and a measured ~10 ms/tick) the scenery is spatially indexed once and a
	# mover is tested against the few rocks in its neighbourhood.
	var movers: Array[PhysBody] = []
	for body in bodies:
		if not body.kinematic:
			movers.append(body)

	_stepped_pairs = 0
	_resolved_pairs = 0
	var budget := profile.max_pairs_per_step
	if movers.size() >= 2:
		for pair in Broadphase.pairs(movers):
			budget = _try_pair(movers[pair[0]], movers[pair[1]], delta, budget)
	# Huge scenery (planets, the station, the moon): a handful, direct-tested.
	for s in _scenery_large:
		for m in movers:
			budget = _try_pair(s, m, delta, budget)
			if budget <= 0:
				break
		if budget <= 0:
			break
	# Small scenery (rocks): look up only the cells near each mover. Skipped
	# entirely when there is none — the per-mover cell probe is cheap only when
	# it returns rocks.
	if movers.size() > 0 and not _scenery_grid.is_empty():
		for m in movers:
			budget = _query_scenery(m, delta, budget)
			if budget <= 0:
				break

	for body in bodies:
		_integrate(body, delta)


## Test a mover against the small scenery (rocks) whose grid cells overlap its
## swept neighbourhood. Returns the drained budget.
func _query_scenery(m: PhysBody, delta: float, budget: int) -> int:
	var reach := m.radius + _scenery_max_r + m.velocity.length() * delta
	var span := int(ceil(reach / maxf(_scenery_cell, 0.001)))
	var base := _cell_of(m)
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			for dz in range(-span, span + 1):
				var key := base + Vector3i(dx, dy, dz)
				if not _scenery_grid.has(key):
					continue
				for s in _scenery_grid[key] as Array:
					budget = _try_pair(s as PhysBody, m, delta, budget)
					if budget <= 0:
						return budget
	return budget


func _cell_of(body: PhysBody) -> Vector3i:
	return Vector3i(
		floori(body.position().x / maxf(_scenery_cell, 0.001)),
		floori(body.position().y / maxf(_scenery_cell, 0.001)),
		floori(body.position().z / maxf(_scenery_cell, 0.001)),
	)


## Index kinematic scenery into a fixed grid. Bodies too large for the cell
## (planets, the station, the moon) are set aside and direct-tested instead —
## a 1400 m planet must not define the cell size for 6 m rocks.
func _build_scenery_index() -> void:
	_scenery_dirty = false
	_scenery_grid.clear()
	_scenery_large.clear()
	var small_r := 1.0
	for body in bodies:
		if body.kinematic and body.radius <= SCENERY_SMALL_MAX:
			small_r = maxf(small_r, body.radius)
	_scenery_cell = small_r * 2.0
	_scenery_max_r = small_r
	for body in bodies:
		if not body.kinematic:
			continue
		if body.radius > SCENERY_SMALL_MAX:
			_scenery_large.append(body)
			continue
		var key := _cell_of(body)
		if not _scenery_grid.has(key):
			_scenery_grid[key] = []
		(_scenery_grid[key] as Array).append(body)


## Rocks and debris this size or under go in the scenery grid; anything bigger
## (a station, a moon, a planet) is direct-tested. Set well above the biggest
## rock so a 70 m boulder still gets the grid's spatial pruning.
const SCENERY_SMALL_MAX := 100.0

var _scenery_dirty := true
var _scenery_cell := 1.0
var _scenery_max_r := 1.0
var _scenery_grid := {}
var _scenery_large: Array[PhysBody] = []


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
	# Free bodies feel the scene's gravity (a knocked-loose rock falls and orbits).
	if gravity != null and gravity.mode != GravitySystem.GravityMode.OFF:
		body.velocity += gravity.compute_gravity(body.node.global_position) * delta
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
