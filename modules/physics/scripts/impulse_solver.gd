## ImpulseSolver: what happens when two bodies actually touch.
##
## The line this module exists for is `b.velocity += n * j / mb` — the second
## half of a collision. Before M1 the game only ever wrote `self.velocity` on
## the one body the player flies; everything else was scenery that absorbed the
## hit and never moved. Here a collision hands momentum to *both* bodies, by
## the same formula in both directions, so a hauler can finally knock a scout
## and a rock can finally be knocked anywhere.
##
## Spheres, resolved with impulses: a contact normal impulse from restitution,
## a tangential friction impulse from slip, the tangential part converted into
## spin by the profile's impulse_to_spin, and a positional correction that
## pushes the pair apart by the overlap. Bodies are spheres because every
## actor in the game already *is* a sphere for collision purposes — the flight
## model's "collision radius = design bounds + a fudge" is exactly a sphere.
class_name ImpulseSolver
extends RefCounted


## Resolve one contact between two bodies this step. Reads current positions
## and velocities, writes velocities and (for the positional correction) node
## positions. Returns a Dictionary the world can report as `impacted`:
##   resolved : whether the pair touched at all this step
##   impulse  : the normal impulse applied (0 when only separated)
##   normal   : the contact normal
##   point    : the contact point
##   closing  : the approach speed in m/s that produced the hit (0 when the
##              pair was separating and only needed pushing apart)
static func resolve(a: PhysBody, b: PhysBody, delta: float, profile: PhysProfile) -> Dictionary:
	var contact := _contact(a, b, delta, profile)
	if not bool(contact["hit"]):
		return _report(false, 0.0, Vector3.ZERO, Vector3.ZERO, 0.0)
	var normal: Vector3 = contact["normal"]

	# Relative velocity of B with respect to A along the normal (which points
	# A → B). Negative means approaching — that is the case an impulse resolves.
	var vrel := b.velocity - a.velocity
	var vn := vrel.dot(normal)
	var ia := _effective_inv_mass(a, profile)
	var ib := _effective_inv_mass(b, profile)
	var inv_sum := ia + ib
	if inv_sum <= 0.0:
		return _report(false, 0.0, Vector3.ZERO, Vector3.ZERO, 0.0)

	# Bounce: a normal impulse that reverses the approaching component by the
	# pair's restitution. Applied in opposite directions to both bodies — the
	# line the whole module exists for.
	var e := _restitution(a, b, profile)
	var jn := -(1.0 + e) * vn / inv_sum
	# The approach speed is what a consumer keys damage and lockout on — the
	# number a pilot reads as "how hard did I hit that".
	var closing := maxf(-vn, 0.0)
	if jn > 0.0:
		# knock_transfer > 1 lets the victim be flung harder than strict momentum
		# allows — the arcade "asteroid goes flying" knob. 1.0 is exact.
		var kb := profile.knock_transfer
		a.velocity -= normal * (jn * ia)
		b.velocity += normal * (jn * ib * kb)
		_apply_friction(a, b, vrel, normal, jn, ia, ib, profile)
		_separate(a, b, normal, ia, ib, profile)
		_record_blame(a, b)
	else:
		# Separating already — but the pair may still be overlapping, in which
		# case they need pushing apart, not bouncing.
		_separate(a, b, normal, ia, ib, profile)
	return _report(true, maxf(jn, 0.0), normal, contact["point"], closing)


static func _report(resolved: bool, impulse: float, normal: Vector3, point: Vector3, closing := 0.0) -> Dictionary:
	return {
		"resolved": resolved,
		"impulse": impulse,
		"normal": normal,
		"point": point,
		"closing": closing,
	}


## Swept or discrete contact test for this step. Fast relative travel gets the
## swept test so nothing tunnels; everything else is a plain overlap check.
static func _contact(a: PhysBody, b: PhysBody, delta: float, profile: PhysProfile) -> Dictionary:
	var pa := a.position()
	var pb := b.position()
	var travel := (a.velocity - b.velocity) * delta
	var sweep_radius := maxf(a.radius, b.radius) * maxf(profile.ccd_ratio, 0.001)
	if travel.length() > sweep_radius:
		return Ccd.hit_info(pa, a.velocity, a.radius, pb, b.velocity, b.radius, delta)
	var touch := a.radius + b.radius
	var f := pb - pa
	if f.length_squared() < touch * touch:
		var n := f.normalized() if f.length_squared() > 1e-12 else Vector3.UP
		return {"hit": true, "normal": n, "point": pb - n * b.radius, "t": 0.0}
	return {"hit": false, "normal": Vector3.ZERO, "point": Vector3.ZERO, "t": 0.0}


## Tangential slip becomes a friction impulse on both bodies (equal and
## opposite, so linear momentum is untouched) and, scaled by the profile, a
## spin on each. Friction is what turns a glancing hit into a deflection at
## all; without it every contact would be a straight bounce along the normal.
static func _apply_friction(
	a: PhysBody, b: PhysBody, vrel: Vector3, normal: Vector3, jn: float,
	ia: float, ib: float, profile: PhysProfile
) -> void:
	var slip := vrel - normal * vrel.dot(normal)
	var slip_len := slip.length()
	if slip_len < 1e-6 or profile.friction <= 0.0:
		return
	var t_hat := slip / slip_len
	var jt := profile.friction * slip_len / (ia + ib)
	# Coulomb-style clamp: friction cannot exceed the normal impulse it rides on.
	jt = minf(jt, profile.friction * absf(jn))
	# Friction opposes the slip: the follower is dragged toward the direction of
	# relative travel, the leader is dragged back.
	a.velocity += t_hat * (jt * ia)
	b.velocity -= t_hat * (jt * ib)
	_spin_from_contact(a, b, t_hat, normal, jt, profile)


## A contact off the centre line spins a body. For a sphere the contact offset
## is along the normal, so only the tangential (friction) part can torque it —
## which is exactly the cartoony outcome the plan wants: a glancing hit tumbles
## the ship, a dead-on one does not.
static func _spin_from_contact(
	a: PhysBody, b: PhysBody, t_hat: Vector3, normal: Vector3, jt: float, profile: PhysProfile
) -> void:
	var axis := normal.cross(t_hat)
	if axis.length_squared() < 1e-12 or profile.impulse_to_spin <= 0.0:
		return
	if not a.kinematic and a.radius > 0.0:
		# torque = r × F; for a sphere r is along the normal, |r|=radius, and
		# I = 2/5·m·r². The profile scales how much of the slip becomes spin.
		# The friction impulse on each body torques it the same way (Newton's
		# third law reverses both the force and the lever arm), so both spin on
		# the same axis.
		var inv_i := 1.0 / (0.4 * a.mass * a.radius * a.radius)
		a.angular += axis * (jt * a.radius * inv_i * profile.impulse_to_spin)
	if not b.kinematic and b.radius > 0.0:
		var inv_i := 1.0 / (0.4 * b.mass * b.radius * b.radius)
		b.angular += axis * (jt * b.radius * inv_i * profile.impulse_to_spin)


## Push two overlapping bodies apart along the contact normal (Baumgarte with a
## slop), proportional to their inverse masses so a ship shoves a rock far more
## than the rock shoves the ship.
static func _separate(
	a: PhysBody, b: PhysBody, normal: Vector3, ia: float, ib: float, profile: PhysProfile
) -> void:
	var pa := a.position()
	var pb := b.position()
	var touch := a.radius + b.radius
	var overlap := touch - pa.distance_to(pb)
	if overlap <= profile.penetration_slop:
		return
	var push := (overlap - profile.penetration_slop) * profile.position_correction / maxf(ia + ib, 1e-6)
	a.set_position(pa - normal * (push * ia))
	b.set_position(pb + normal * (push * ib))


## Effective inverse mass for the profile's mass_influence dial. 0 makes every
## body respond to a hit as if it had mass 1 (the pre-M1 behaviour); 1 makes a
## ten-tonne hauler behave ten times harder to move. Kinematic bodies stay at
## zero either way.
static func _effective_inv_mass(body: PhysBody, profile: PhysProfile) -> float:
	if body.kinematic:
		return 0.0
	return lerpf(1.0, body.inv_mass(), profile.mass_influence)


static func _restitution(a: PhysBody, b: PhysBody, profile: PhysProfile) -> float:
	if profile != null:
		return profile.restitution_for_pair(a.layer, b.layer)
	return (a.restitution + b.restitution) * 0.5


## Whoever pushed records that on the other body's last_pusher, so M5's blame
## attribution has a trail to read without re-solving anything.
static func _record_blame(a: PhysBody, b: PhysBody) -> void:
	a.last_pusher = b.faction_id
	b.last_pusher = a.faction_id
