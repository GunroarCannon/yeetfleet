## Headless bridge test for M1b: a real [FlightModel] flying into the PhysWorld.
##
##     godot --path . --headless --script modules/flight/tools/flight_bridge_smoke.gd
##
## This is the seam M1b exists to open: the flight model no longer hand-checks
## distances and ejects itself at a hardcoded minimum of 30 m/s — it writes its
## velocity onto a driven body, the world resolves it against scenery with the
## profile's restitution, and the model reads the impulse and spin back. The
## checks below are the plan's behavioural claims, asserted through the real
## model rather than through the physics module in isolation:
##   - a ship ramming a rock bounces back (velocity reverses) and survives
##   - a gentle touch is a touch: no ≥30 m/s ejection on a slow approach
##   - an impact sets the assist-lockout window
##   - the ship is not double-integrated (driven body; the model moves itself)
extends SceneTree

const DT := 0.016
const ROCK_RADIUS := 4.0
const SHIP_RADIUS := 3.0
const ROCK_X := 8.0  # centres gap of 1 m at start

var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── flight↔physics bridge smoke test ────────────────────")
	await _check_hard_bounce()
	await _check_gentle_touch()
	await _check_driven_no_double_move()
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


## Build a manual-flight model heading +x at [param speed] toward a rock at
## [constant ROCK_X]. Returns [model, world, rig]. The ship flies itself; the
## smoke then drives the exact controller→world order by hand.
##
## The model is settled into the tree AT REST first — it defines _physics_process,
## so the engine would otherwise fly it during the settle frames before the
## world exists and it could cruise straight past the rock it is meant to hit.
func _rig_approach(speed: float) -> Array:
	var rig := Node3D.new()
	root.add_child(rig)
	var model := FlightModel.new()
	model.name = "Ship"
	rig.add_child(model)
	model.set_assist_mode(0)  # manual: nothing damps the approach or the rebound

	var rock_node := Node3D.new()
	rock_node.position = Vector3(ROCK_X, 0.0, 0.0)
	rig.add_child(rock_node)
	await _settle()

	# Now the world is authoritative: hand the model its speed and bind it.
	model.velocity = Vector3(speed, 0.0, 0.0)
	var world := PhysWorld.new()
	var rock := PhysBody.new(1.0, ROCK_RADIUS)
	rock.node = rock_node
	rock.layer = PhysBody.Layer.ROCK
	rock.kinematic = true
	world.add(rock)
	model.set_phys_world(world, SHIP_RADIUS)
	return [model, world, rig]


## A 50 m/s ram must reverse the ship's velocity (restitution bounce through the
## layer), leave it short of the rock, and arm the assist-lockout window.
func _check_hard_bounce() -> void:
	var setup := await _rig_approach(50.0)
	var model: FlightModel = setup[0]
	var world: PhysWorld = setup[1]
	var rig: Node3D = setup[2]
	var bounced := false
	for i in 120:
		model._physics_process(DT)
		world.step(DT)
		if model._phys.velocity.x < -1.0:
			bounced = true
			break
	_check(bounced, "a 50 m/s ram never bounced (ended at vx %.1f)" % model._phys.velocity.x)
	_check(model.global_position.x < ROCK_X - ROCK_RADIUS + 1.0,
		"the ship ended past the rock's centre (x=%.1f)" % model.global_position.x)
	_check(model._assist_lockout > 0.0,
		"the impact did not arm the assist lockout")
	_done("A ram bounces, stays short, arms the lockout")
	rig.queue_free()


## A slow approach must produce a slow rebound. The pre-M1 code ejected every
## contact at a hardcoded minimum of 30 m/s — the reason a player could not
## nudge, dock or touch anything. Restitution here (~0.3) sends a 3 m/s touch
## back at under a metre per second.
func _check_gentle_touch() -> void:
	var setup := await _rig_approach(3.0)
	var model: FlightModel = setup[0]
	var world: PhysWorld = setup[1]
	var rig: Node3D = setup[2]
	var rebound := 0.0
	for i in 200:
		model._physics_process(DT)
		world.step(DT)
		if model._phys.velocity.x < 0.0:
			rebound = model._phys.velocity.x
			break
	_check(rebound < 0.0, "a gentle touch did not rebound (vx %.2f)" % rebound)
	_check(absf(rebound) < 6.0,
		"a 3 m/s touch ejected the ship at %.1f m/s — the old 30 m/s minimum is back" % absf(rebound))
	_done("A gentle touch rebounds gently, not at 30 m/s")
	rig.queue_free()


## The body is driven: the world must not also move the ship's node, or it
## would travel twice per step. Fly the model a few steps with no scenery near;
## the node's motion must match the model's own integration exactly.
func _check_driven_no_double_move() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	var model := FlightModel.new()
	rig.add_child(model)
	model.set_assist_mode(0)
	await _settle()
	model.velocity = Vector3(25.0, 0.0, 0.0)
	var world := PhysWorld.new()
	model.set_phys_world(world, SHIP_RADIUS)
	var start := model.global_position.x
	for i in 10:
		model._physics_process(DT)
		world.step(DT)
	var moved := model.global_position.x - start
	_check(absf(moved - 25.0 * DT * 10.0) < 0.02,
		"driven ship moved %.2f m over 10 steps, expected %.2f — it was double-integrated" % [
			moved, 25.0 * DT * 10.0,
		])
	_done("A driven body is moved once, by its controller")
	rig.queue_free()


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
