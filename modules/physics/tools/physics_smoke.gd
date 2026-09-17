## Headless smoke test for modules/physics: the impulse layer in isolation.
##
##     godot --headless --path . --script modules/physics/tools/physics_smoke.gd
##
## The plan's M1 contract, asserted headlessly (TECHNICAL_PLAN §M1):
##   - momentum is conserved across a pair collision, within 1e-4
##   - identical seed + identical inputs → identical results after 600 steps
##   - a 15,000 m/s body does not pass through a 10 m sphere (CCD)
##   - 300 bodies × 600 steps completes within a sane headless budget
##
## Bodies are created under the SceneTree's root, which is only "inside the
## tree" once the loop is running — so every test settles for a frame after
## building its rig before it steps the world.
extends SceneTree

const MOMENTUM_EPS := 1e-4

var _failures: Array[String] = []
var _reported := 0
var _serial := 0


func _initialize() -> void:
	print("── physics module smoke test ───────────────────────────")
	await _check_elastic_exchange()
	await _check_inelastic_stick()
	await _check_heavy_vs_light()
	await _check_knock_transfer()
	await _check_profiles()
	await _check_determinism()
	await _check_ccd_discrete_misses()
	await _check_ccd_no_tunnel()
	await _check_perf_budget()
	await _check_driven_not_integrated()
	await _check_closing_on_signal()
	await _check_scenery_never_pairs()
	await _check_free_body_gravity()
	await _check_pull_off_no_fall()
	await _check_hull_clearance()
	await _check_hull_contact_across_the_beam()
	await _check_hull_fit()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < MOMENTUM_EPS


## Let the tree begin so node transforms resolve. Two frames: the first puts the
## nodes in the tree, the second lets any layout settle.
func _settle() -> void:
	await process_frame
	await process_frame


## A fresh holder for one test's bodies, so tests do not trip over each other's
## nodes.
func _rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "Rig%d" % _serial
	_serial += 1
	root.add_child(rig)
	return rig


func _body(rig: Node3D, pos: Vector3, mass: float, radius: float, layer: int, vel: Vector3) -> PhysBody:
	var node := Node3D.new()
	node.name = "B%d" % _serial
	_serial += 1
	# Local position set before the node is added: the rig sits at the origin,
	# so local == global once the tree runs.
	node.position = pos
	rig.add_child(node)
	var b := PhysBody.new(mass, radius)
	b.node = node
	b.layer = layer
	b.velocity = vel
	return b


func _free_rig(rig: Node3D) -> void:
	rig.queue_free()


# --- Momentum -----------------------------------------------------------------

## Two equal 1-tonne bodies, head-on at ±5 m/s, perfectly elastic. They must
## exchange velocities exactly — and, more to the point, each body's velocity
## must change, which is the one thing the pre-M1 game could not do.
func _check_elastic_exchange() -> void:
	var rig := _rig()
	var a := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(5.0, 0.0, 0.0))
	var b := _body(rig, Vector3(1.5, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(-5.0, 0.0, 0.0))
	await _settle()
	var world := PhysWorld.new()
	world.profile.restitution_rock = 1.0
	world.add(a)
	world.add(b)
	world.step(0.016)
	_check(_near(a.velocity, Vector3(-5.0, 0.0, 0.0)), "A did not bounce back to -5 (%.1f)" % a.velocity.x)
	_check(_near(b.velocity, Vector3(5.0, 0.0, 0.0)), "B did not get pushed to +5 (%.1f)" % b.velocity.x)
	_check_momentum([a, b], Vector3.ZERO)
	_done("Elastic head-on exchanges both velocities")
	_free_rig(rig)


## Perfectly inelastic: two equal masses colliding head-on must both stop. This
## is the "no minimum outward speed" case — a gentle touch is a touch, not an
## ejection.
func _check_inelastic_stick() -> void:
	var rig := _rig()
	var a := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(5.0, 0.0, 0.0))
	var b := _body(rig, Vector3(1.5, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(-5.0, 0.0, 0.0))
	await _settle()
	var world := PhysWorld.new()
	world.profile.restitution_rock = 0.0
	world.add(a)
	world.add(b)
	world.step(0.016)
	_check(_near(a.velocity, Vector3.ZERO), "A kept %.1f m/s after a dead stop" % a.velocity.length())
	_check(_near(b.velocity, Vector3.ZERO), "B kept %.1f m/s after a dead stop" % b.velocity.length())
	_check_momentum([a, b], Vector3.ZERO)
	_done("Inelastic pair stops together")
	_free_rig(rig)


## A 10-tonne hauler nudging a 1-tonne rock: momentum conserved, and the rock
## goes flying far more than the hauler budges.
func _check_heavy_vs_light() -> void:
	var rig := _rig()
	var a := _body(rig, Vector3.ZERO, 10.0, 1.0, PhysBody.Layer.ROCK, Vector3(1.0, 0.0, 0.0))
	var b := _body(rig, Vector3(1.5, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(-1.0, 0.0, 0.0))
	await _settle()
	var world := PhysWorld.new()
	world.profile.restitution_rock = 0.5
	world.add(a)
	world.add(b)
	world.step(0.016)
	# Before: 10·1 + 1·(-1) = 9. After must be the same vector.
	_check_momentum([a, b], Vector3(9.0, 0.0, 0.0))
	_check(a.velocity.x < 1.0, "the hauler was accelerated forward (%.2f)" % a.velocity.x)
	_check(b.velocity.x > 1.5, "the rock was not flung (%.2f)" % b.velocity.x)
	_done("Mass ratio shapes the response")
	_free_rig(rig)


## knock_transfer > 1 deliberately violates momentum to make the victim fly — the
## cartoony knob. Its default is 1 (exact); this only checks the dial reaches
## the solver, not that it conserves (it must not).
func _check_knock_transfer() -> void:
	var rig := _rig()
	var a := _body(rig, Vector3.ZERO, 10.0, 1.0, PhysBody.Layer.ROCK, Vector3(1.0, 0.0, 0.0))
	var b := _body(rig, Vector3(1.5, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(-1.0, 0.0, 0.0))
	await _settle()
	var world := PhysWorld.new()
	world.profile.restitution_rock = 0.5
	world.profile.knock_transfer = 2.0
	world.add(a)
	world.add(b)
	world.step(0.016)
	_check(b.velocity.x > 3.0, "knock_transfer 2 did not fling the rock (%.2f)" % b.velocity.x)
	_done("knock_transfer reaches the victim")
	_free_rig(rig)


# --- Profiles -----------------------------------------------------------------

## The shipped feel profiles must exist, load as [PhysProfile]s, and disagree
## the way their names promise — otherwise a scene that loads cartoony.tres is
## silently flying grounded.
func _check_profiles() -> void:
	var grounded := load("res://modules/physics/data/profiles/grounded.tres") as PhysProfile
	var cartoony := load("res://modules/physics/data/profiles/cartoony.tres") as PhysProfile
	_check(grounded != null, "grounded.tres missing or not a PhysProfile")
	_check(cartoony != null, "cartoony.tres missing or not a PhysProfile")
	if grounded != null and cartoony != null:
		_check(cartoony.restitution_ship > grounded.restitution_ship,
			"cartoony hulls are not bouncier than grounded (%.2f vs %.2f)" % [
				cartoony.restitution_ship, grounded.restitution_ship,
			])
		_check(cartoony.impulse_to_spin > grounded.impulse_to_spin,
			"cartoony does not spin more on impact than grounded")
		_check(is_equal_approx(grounded.knock_transfer, 1.0),
			"grounded must conserve momentum exactly (knock_transfer %.2f)" % grounded.knock_transfer)
	_done("grounded/cartoony profiles load and differ")


# --- Determinism ---------------------------------------------------------------

## Same inputs, 600 steps, two worlds: the plan's whole "predictable rules"
## promise (§0.3). If the solver had any hidden state, a non-deterministic
## iteration order, or a source of randomness, the two runs would diverge.
func _check_determinism() -> void:
	var a := await _run_600_steps()
	var b := await _run_600_steps()
	for i in a[0].size():
		_check(a[0][i] == b[0][i], "position diverged at body %d" % i)
		_check(a[1][i] == b[1][i], "velocity diverged at body %d" % i)
	_check(_finite(a[0]) and _finite(a[1]), "a run produced a non-finite state")
	_done("Identical inputs → identical 600-step result")
	_free_rig(a[2])
	_free_rig(b[2])


## Build a small mixed world and step it 600 times. Returns [positions,
## velocities, rig] so the caller can compare or free. Two calls must be
## byte-for-byte identical — hence no RNG, only arithmetic.
func _run_600_steps() -> Array:
	var rig := _rig()
	var world := PhysWorld.new()
	var bodies: Array[PhysBody] = []
	bodies.append(_body(rig, Vector3(0.0, 0.0, 0.0), 2.0, 3.0, PhysBody.Layer.ROCK, Vector3.ZERO))
	bodies.append(_body(rig, Vector3(60.0, 0.0, 0.0), 1.0, 2.0, PhysBody.Layer.ROCK, Vector3(-8.0, 1.0, 0.0)))
	bodies.append(_body(rig, Vector3(0.0, 40.0, 0.0), 5.0, 4.0, PhysBody.Layer.ROCK, Vector3(6.0, -2.0, 0.0)))
	bodies.append(_body(rig, Vector3(20.0, 20.0, 0.0), 1.0, 1.5, PhysBody.Layer.ROCK, Vector3(-3.0, -6.0, 0.0)))
	var wall := _body(rig, Vector3(30.0, 20.0, 0.0), 1.0, 8.0, PhysBody.Layer.STATIC, Vector3.ZERO)
	wall.kinematic = true
	await _settle()
	for b in bodies:
		world.add(b)
	world.add(wall)
	for i in 600:
		world.step(1.0 / 120.0)
	var pos: Array[Vector3] = []
	var vel: Array[Vector3] = []
	for b in bodies:
		pos.append(b.position())
		vel.append(b.velocity)
	return [pos, vel, rig]


func _finite(pos: Array[Vector3]) -> bool:
	for p in pos:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


# --- CCD ----------------------------------------------------------------------

## A body that would cross a sphere in one step must be caught by the swept
## test. Same geometry, small velocity (discrete path): no contact claimed from
## far away. Big velocity (swept path): contact found and resolved.
func _check_ccd_discrete_misses() -> void:
	var rig := _rig()
	var slow := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(200.0, 0.0, 0.0))
	var target := _body(rig, Vector3(15.0, 0.0, 0.0), 1.0, 10.0, PhysBody.Layer.STATIC, Vector3.ZERO)
	target.kinematic = true
	var fast := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(15000.0, 0.0, 0.0))
	var near := _body(rig, Vector3(150.0, 0.0, 0.0), 1.0, 10.0, PhysBody.Layer.STATIC, Vector3.ZERO)
	near.kinematic = true
	await _settle()
	var world := PhysWorld.new()
	world.profile.ccd_ratio = 0.5
	# 200·0.02 = 4 m of travel < sweep threshold (10·0.5 = 5): discrete path,
	# and 15 m apart there is nothing to hit.
	var report := ImpulseSolver.resolve(slow, target, 0.02, world.profile)
	_check(not bool(report["resolved"]), "discrete test claimed a contact from 15 m away")
	# 15000·0.02 = 300 m of travel, sphere 11 m reach: swept test, and the body
	# would cross it between frames if the sweep did not fire.
	var swept := ImpulseSolver.resolve(fast, near, 0.02, world.profile)
	_check(bool(swept["resolved"]), "swept test missed a body crossing a sphere")
	_check(fast.velocity.x < 0.0, "fast body did not bounce (%.0f)" % fast.velocity.x)
	_done("Swept test catches what discrete misses")
	_free_rig(rig)


## The plan's headline: a 15,000 m/s body does not pass through a 10 m sphere.
## Through the whole world, not just the solver — broadphase pairing, CCD and
## integration working together.
func _check_ccd_no_tunnel() -> void:
	var rig := _rig()
	var bullet := _body(rig, Vector3(365.0, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(15000.0, 0.0, 0.0))
	var rock := _body(rig, Vector3(380.0, 0.0, 0.0), 1.0, 10.0, PhysBody.Layer.STATIC, Vector3.ZERO)
	rock.kinematic = true
	await _settle()
	var world := PhysWorld.new()
	world.add(bullet)
	world.add(rock)
	var max_x := -INF
	for i in 6:
		world.step(0.02)
		max_x = maxf(max_x, bullet.position().x)
	_check(bullet.velocity.x < 0.0, "bullet did not bounce off the rock (%.0f m/s)" % bullet.velocity.x)
	_check(max_x < 391.0, "bullet passed through the rock (reached x=%.0f)" % max_x)
	_check(bullet.position().x < 380.0, "bullet ended beyond the rock's far side")
	_done("15,000 m/s body does not tunnel a 10 m sphere")
	_free_rig(rig)


# --- Perf ---------------------------------------------------------------------

## The mobile budget exists to be measured. This is a loose headless bound —
## 300 bodies × 600 steps finishing comfortably — that will tighten when the
## lab has real profiles to tune against.
func _check_perf_budget() -> void:
	var rig := _rig()
	var world := PhysWorld.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250905
	var bodies: Array[PhysBody] = []
	for i in 300:
		var radius := 2.0 + rng.randf() * 3.0
		var pos := Vector3(rng.randf() * 300.0, rng.randf() * 300.0, rng.randf() * 300.0)
		var b := _body(rig, pos, 1.0 + rng.randf() * 4.0, radius, PhysBody.Layer.ROCK,
			Vector3(rng.randf() * 60.0 - 30.0, rng.randf() * 60.0 - 30.0, rng.randf() * 60.0 - 30.0))
		bodies.append(b)
		world.add(b)
	await _settle()
	var t0 := Time.get_ticks_msec()
	for i in 600:
		world.step(1.0 / 120.0)
	var elapsed := Time.get_ticks_msec() - t0
	print("  perf: %d bodies x 600 steps = %d ms" % [bodies.size(), elapsed])
	_check(elapsed < 8000, "300x600 steps took %d ms — too slow" % elapsed)
	_done("300 bodies x 600 steps within budget")
	_free_rig(rig)


func _check_momentum(bodies: Array, expected: Vector3) -> void:
	var sum := Vector3.ZERO
	for b in bodies:
		sum += b.velocity * b.mass
	_check(_near(sum, expected), "momentum is %s, expected %s" % [sum, expected])


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


# --- M1b groundwork -----------------------------------------------------------

## A driven body is controller-owned: the world must not translate or roll it,
## however fast it is going. The flight model moves its own node and only uses
## the layer for the impulses — a driven body that the world also moved would
## travel twice as far per frame.
func _check_driven_not_integrated() -> void:
	var rig := _rig()
	var b := _body(rig, Vector3(10.0, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.SHIP, Vector3(50.0, 0.0, 0.0))
	b.driven = true
	await _settle()
	var before := b.node.global_position
	var world := PhysWorld.new()
	world.add(b)
	world.step(0.016)
	world.step(0.016)
	_check(b.node.global_position.is_equal_approx(before),
		"driven body was moved by the world (%.1f)" % b.node.global_position.distance_to(before))
	_done("Driven body is not integrated by the world")
	_free_rig(rig)


## The impacted signal must carry the approach speed that caused the hit, not
## just the impulse — the flight model keys damage, hitstop and its assist
## lockout on "how hard did I hit that", which the impulse alone does not say.
func _check_closing_on_signal() -> void:
	var rig := _rig()
	var a := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(5.0, 0.0, 0.0))
	var b := _body(rig, Vector3(1.5, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3(-5.0, 0.0, 0.0))
	await _settle()
	_capture_closing_reset()
	# Bound method, not a lambda: lambdas snapshot their outer locals by value, so
	# they cannot hand a captured number back out of a synchronous signal.
	a.impacted.connect(_capture_closing)
	var world := PhysWorld.new()
	world.profile.restitution_rock = 1.0
	world.add(a)
	world.add(b)
	world.step(0.016)
	_check(_closing_seen and absf(_seen_closing - 10.0) < MOMENTUM_EPS,
		"closing speed was %s, expected ~10 m/s for a ±5 head-on" % _seen_closing)
	_done("impacted() carries the approach speed")
	_free_rig(rig)


var _closing_seen := false
var _seen_closing := 0.0


func _capture_closing_reset() -> void:
	_closing_seen = false
	_seen_closing = 0.0


func _capture_closing(_o: PhysBody, _imp: float, _p: Vector3, _n: Vector3, closing: float) -> void:
	_closing_seen = true
	_seen_closing = closing


## A free body (neither kinematic nor driven) with the world's optional gravity
## set must fall toward the gravitating body — this is the path a knocked-loose
## rock takes once it stops being scenery.
func _check_free_body_gravity() -> void:
	var rig := _rig()
	var b := _body(rig, Vector3(0.0, 0.0, 300.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3.ZERO)
	await _settle()
	var gs := GravitySystem.new()
	gs.register_body(Vector3.ZERO, 10000000.0, 200.0, "Planet", true)
	var world := PhysWorld.new()
	world.gravity = gs
	world.add(b)
	var start_z := b.position().z
	for i in 25:
		world.step(0.016)
	_check(b.velocity.z < 0.0,
		"a free body under gravity did not accelerate toward the body (vz %.2f)" % b.velocity.z)
	_check(b.position().z < start_z - 0.5,
		"a free body under gravity did not fall (z %.1f -> %.1f)" % [start_z, b.position().z])
	_done("Free bodies fall under the world's gravity")
	_free_rig(rig)


## The "no-pull" gravity toggle: bodies keep their orbits but nothing is dragged
## towards them. With pull disabled a free body must NOT fall toward the planet.
func _check_pull_off_no_fall() -> void:
	var rig := _rig()
	var b := _body(rig, Vector3(0.0, 0.0, 300.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3.ZERO)
	await _settle()
	var gs := GravitySystem.new()
	gs.register_body(Vector3.ZERO, 10000000.0, 200.0, "Planet", true)
	gs.pull_enabled = false
	var world := PhysWorld.new()
	world.gravity = gs
	world.add(b)
	var start_z := b.position().z
	for i in 25:
		world.step(0.016)
	_check(b.velocity.length() < 1e-3,
		"pull-off gravity accelerated a body (v %.2f)" % b.velocity.length())
	_check(absf(b.position().z - start_z) < 0.1,
		"pull-off gravity pulled a body down (z %.1f -> %.1f)" % [start_z, b.position().z])
	_done("Pull-off: bodies orbit, nothing falls in")
	_free_rig(rig)


## Two kinematic scenery bodies must never appear as a pair, or a belt of rocks
## sitting in shared cells would eat the pair budget every step before a single
## ship collision was resolved.
func _check_scenery_never_pairs() -> void:
	var rig := _rig()
	var rock_a := _body(rig, Vector3.ZERO, 1.0, 1.0, PhysBody.Layer.ROCK, Vector3.ZERO)
	rock_a.kinematic = true
	var rock_b := _body(rig, Vector3(1.0, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.ROCK, Vector3.ZERO)
	rock_b.kinematic = true
	var ship := _body(rig, Vector3(500.0, 0.0, 0.0), 1.0, 1.0, PhysBody.Layer.SHIP, Vector3.ZERO)
	await _settle()
	var pairs := Broadphase.pairs([rock_a, rock_b, ship] as Array[PhysBody])
	var scenery_pair := false
	for pair in pairs:
		var bi: int = pair[0]
		var bj: int = pair[1]
		var all_bodies := [rock_a, rock_b, ship] as Array[PhysBody]
		if all_bodies[bi].kinematic and all_bodies[bj].kinematic:
			scenery_pair = true
	_check(not scenery_pair, "broadphase emitted a kinematic-kinematic pair")
	_check(pairs.size() == 0, "kinematic rocks far from the ship produced %d pairs" % pairs.size())
	_done("Kinematic scenery never pairs against itself")
	_free_rig(rig)


# --- Ship hulls ---------------------------------------------------------------

## A 12 x 3 x 2 m hull: long and narrow, the shape that made one bounding sphere
## a bad collision volume. The sphere that encloses it has a radius of ~6.3 m
## while the hull is 3 m across, so two ships carrying it reported a hit at a
## centre-to-centre distance of 12.5 m — over four times their real beam.
const HULL_BOX := AABB(Vector3(-6.0, -1.5, -1.0), Vector3(12.0, 3.0, 2.0))


## A ship-shaped body: the same compound [method ShipView.collision_hull] builds
## in flight, one chain of spheres down the hull's length.
func _hulled_body(rig: Node3D, pos: Vector3, vel: Vector3) -> PhysBody:
	var b := _body(rig, pos, 10.0, 1.0, PhysBody.Layer.SHIP, vel)
	var view := ShipView.new()
	view.part_boxes.append(HULL_BOX)
	b.set_hull(view.collision_hull())
	return b


## Two hulls flying past each other with a metre of clear air between them must
## not touch. This is the whole reason for the compound: the single sphere these
## ships used to collide as reaches 6.3 m, so a 4 m lateral offset — a metre of
## daylight per side — registered as a deep overlap and shoved both ships apart
## in mid-space.
func _check_hull_clearance() -> void:
	var rig := _rig()
	var a := _hulled_body(rig, Vector3.ZERO, Vector3.ZERO)
	var b := _hulled_body(rig, Vector3(0.0, 4.0, 0.0), Vector3.ZERO)
	await _settle()
	var world := PhysWorld.new()
	_check(a.radius < 6.5,
		"a 12 x 3 x 2 hull's enclosing radius is %.1f m, not the ~6.3 m it should be" % a.radius)
	# The single sphere it replaced: proof the old shape would have collided here.
	_check(a.radius + b.radius > 4.0,
		"the old bounding spheres would not even have overlapped — the test proves nothing (%.1f m)" % (a.radius + b.radius))
	var report := ImpulseSolver.resolve(a, b, 0.016, world.profile)
	_check(not bool(report["resolved"]),
		"two hulls 4 m apart with a metre of clearance between them registered a hit")
	_done("Hulls with real clearance pass each other")
	_free_rig(rig)


## The same hulls, now genuinely overlapping across their beam, must collide —
## and the normal must run across the beam, the direction the hulls actually
## met on, not along the diagonal between their centres. The two ships sit 8 m
## apart along X and 2 m apart in Y, so the old bounding-sphere normal pointed
## mostly along X while the hulls overlap in Y.
func _check_hull_contact_across_the_beam() -> void:
	var rig := _rig()
	var a := _hulled_body(rig, Vector3.ZERO, Vector3.ZERO)
	var b := _hulled_body(rig, Vector3(8.0, 2.0, 0.0), Vector3.ZERO)
	await _settle()
	var world := PhysWorld.new()
	world.profile.restitution_ship = 0.0
	var report := ImpulseSolver.resolve(a, b, 0.016, world.profile)
	_check(bool(report["resolved"]), "two overlapping hulls reported no contact")
	var normal: Vector3 = report["normal"]
	_check(absf(normal.y) > 0.9,
		"the contact normal was %s — the hulls overlap across the beam, so it should run mostly in Y" % normal)
	_check(absf(normal.x) < 0.3,
		"the contact normal kept the centres' %.2f share of X, which is the bounding sphere talking" % absf(normal.x))
	var y_gap := absf(a.position().y - b.position().y)
	world.add(a)
	world.add(b)
	for i in 20:
		world.step(0.016)
	_check(absf(a.position().y - b.position().y) > y_gap,
		"the world did not push the overlapping hulls apart across their beam")
	_done("Hull contact resolves across the beam")
	_free_rig(rig)


## [method HullFit.spheres_for_box] directly, because it is now the one place ships
## *and* large craft get their collision from, and the property that matters is not
## visible in either caller's behaviour: the fit is derived from the box, not from
## wherever the part's pivot happens to sit.
##
## The code this replaced sized each large-craft part as
## `aabb.get_center().length() + aabb.size.length()*0.5` measured from the part
## node's origin — so a part whose geometry sat off its own origin got a sphere
## centred in the wrong place *and* inflated by the distance. A box offset from the
## origin is exactly the case that catches it.
func _check_hull_fit() -> void:
	# Offset deliberately: this box's centre is 10 m from the origin, and a fit that
	# read the origin would put its sphere there instead.
	var offset_box := AABB(Vector3(8.0, 0.0, 0.0), Vector3(4.0, 2.0, 2.0))
	var offset_fit := HullFit.spheres_for_box(offset_box)
	_check(offset_fit.size() >= 1, "an offset box produced no hull sections")
	for sphere in offset_fit:
		var centre: Vector3 = sphere["offset"]
		# Along the box's own span the chain may sit anywhere inboard; what must hold
		# is that it is inboard of the box and not of the origin.
		_check(centre.x > 6.0 and centre.x < 14.0,
			"a section at x=%.2f is not on its box (which spans x 8..12)" % centre.x)
	var enclosing := HullFit.spheres_for_box(offset_box)[0]["offset"] as Vector3
	_check(absf(enclosing.x - 10.0) < 2.1,
		"the fit is centred at %s, not on its box centre (10, 1, 1)" % enclosing)

	# Long and thin: a chain, and every section inside the box it stands for.
	var long_box := AABB(Vector3(-8.0, -0.5, -0.5), Vector3(16.0, 1.0, 1.0))
	var long_fit := HullFit.spheres_for_box(long_box)
	_check(long_fit.size() > 1, "a 16 x 1 x 1 box got %d section(s), not a chain" % long_fit.size())
	_check(long_fit.size() <= HullFit.MAX_SPHERES_PER_PART,
		"the chain ignored its own %d-section cap (%d)" % [HullFit.MAX_SPHERES_PER_PART, long_fit.size()])
	var grown := long_box.grow(0.05)
	for sphere in long_fit:
		_check(grown.has_point(sphere["offset"] as Vector3),
			"a chain section sits at %s, outside its own box" % sphere["offset"])

	# Compact: one section, and it still has to be a usable radius — the solver
	# divides by these.
	var compact_fit := HullFit.spheres_for_box(AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))
	_check(compact_fit.size() == 1, "a 1 m cube got %d sections" % compact_fit.size())
	# Degenerate: no geometry at all still has to yield something positive, or the
	# body divides by a zero radius.
	var empty_fit := HullFit.spheres_for_box(AABB())
	_check(not empty_fit.is_empty(), "an empty box produced no collision at all")
	for sphere in empty_fit:
		_check(float(sphere["radius"]) > 0.0, "a zero-radius section reached the solver")
	_done("Hull fitting is box-centred and chained")
