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
## pushes the pair apart by the overlap. A roundish body — every rock, planet
## and station in the game — is one sphere. A ship is a compound of them, one
## per hull section (see [member PhysBody.hull]), and the contact reported is
## the pair of sections that actually met.
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
		_apply_friction(a, b, contact, vrel, normal, jn, ia, ib, profile)
		_separate(a, b, contact, normal, ia, ib, profile)
		_record_blame(a, b)
	else:
		# Separating already — but the pair may still be overlapping, in which
		# case they need pushing apart, not bouncing.
		_separate(a, b, contact, normal, ia, ib, profile)
	return _report(true, maxf(jn, 0.0), normal, contact["point"], closing)


static func _report(resolved: bool, impulse: float, normal: Vector3, point: Vector3, closing := 0.0) -> Dictionary:
	return {
		"resolved": resolved,
		"impulse": impulse,
		"normal": normal,
		"point": point,
		"closing": closing,
	}


static func _miss() -> Dictionary:
	return {"hit": false, "normal": Vector3.ZERO, "point": Vector3.ZERO, "t": 0.0,
		"pa": Vector3.ZERO, "pb": Vector3.ZERO, "ra": 0.0, "rb": 0.0}


## One contact, fully described. `pa`/`pb` and `ra`/`rb` are the two *spheres*
## that met — the hull sections, for a ship — which is what the separation push
## and the contact torque are computed from. The normal points A → B and the
## contact point sits on B's surface.
static func _contact_report(
	normal: Vector3, point: Vector3, t: float,
	pa: Vector3, pb: Vector3, ra: float, rb: float
) -> Dictionary:
	return {"hit": true, "normal": normal, "point": point, "t": t,
		"pa": pa, "pb": pb, "ra": ra, "rb": rb}


## Swept or discrete contact test for this step. Fast relative travel gets the
## swept test so nothing tunnels; everything else is a plain overlap check.
##
## A body with a compound [member PhysBody.hull] is tested sphere by sphere, and
## the section pair that touches first (swept) or deepest (discrete) is the one
## reported — so two ships meet along the hulls that actually met rather than
## between the bounding spheres that contain them.
static func _contact(a: PhysBody, b: PhysBody, delta: float, profile: PhysProfile) -> Dictionary:
	var travel := (a.velocity - b.velocity) * delta
	var sweep_radius := maxf(a.radius, b.radius) * maxf(profile.ccd_ratio, 0.001)
	if travel.length() > sweep_radius:
		return _swept_contact(a, b, delta)
	return _discrete_contact(a, b)


## The deepest overlap between any sphere of A and any sphere of B, or a miss.
##
## Plain numbers in the inner loop and one Dictionary at the end: a pair of real
## ships is thousands of sphere pairs, and an allocation per pair measured ~5 µs
## of the ~6 µs each one took — 24 ms for a single ship-against-ship resolve,
## where this shape costs a fraction of a millisecond.
static func _discrete_contact(a: PhysBody, b: PhysBody) -> Dictionary:
	var a_hull := a.has_hull()
	var b_hull := b.has_hull()
	if not a_hull and not b_hull:
		return _sphere_overlap(a.position(), a.radius, b.position(), b.radius)
	# One transform read per *body*, not per sphere, and B's sections resolved
	# into world space once — the inner loop then reads two packed arrays rather
	# than re-transforming a dictionary entry for every section of A.
	var a_xform := a.node.global_transform if a_hull and a.node != null else Transform3D()
	var b_xform := b.node.global_transform if b_hull and b.node != null else Transform3D()
	var a_count := a.hull.size() if a_hull else 1
	var b_count := b.hull.size() if b_hull else 1
	var a_solo := a.position()
	var b_solo := b.position()
	var b_centers := PackedVector3Array()
	var b_radii := PackedFloat32Array()
	b_centers.resize(b_count)
	b_radii.resize(b_count)
	for j in b_count:
		b_centers[j] = b_xform * (b.hull[j]["offset"] as Vector3) if b_hull else b_solo
		b_radii[j] = float(b.hull[j]["radius"]) if b_hull else b.radius

	var best_overlap := 0.0
	var best_pa := Vector3.ZERO
	var best_pb := Vector3.ZERO
	var best_ra := 0.0
	var best_rb := 0.0
	var hit := false
	for i in a_count:
		var pa := a_xform * (a.hull[i]["offset"] as Vector3) if a_hull else a_solo
		var ra := float(a.hull[i]["radius"]) if a_hull else a.radius
		for j in b_count:
			var pb := b_centers[j]
			var rb := b_radii[j]
			var touch := ra + rb
			var f := pb - pa
			var f2 := f.length_squared()
			if f2 >= touch * touch:
				continue
			var overlap := touch - sqrt(f2)
			if overlap > best_overlap:
				best_overlap = overlap
				best_pa = pa
				best_pb = pb
				best_ra = ra
				best_rb = rb
				hit = true
	if not hit:
		return _miss()
	var f := best_pb - best_pa
	var f2 := f.length_squared()
	var n := f / sqrt(f2) if f2 > 1e-12 else Vector3.UP
	return _contact_report(n, best_pb - n * best_rb, 0.0, best_pa, best_pb, best_ra, best_rb)


## Earliest contact along the step between any sphere of A and any sphere of B.
## Each section pair is its own moving sphere, so a long hull sweeping sideways
## is tested where its nose actually is, not at its centre.
##
## The scan tracks a time, not a Dictionary: see [method _discrete_contact] for
## why, and [method Ccd.impact_time] for the split that makes it possible. Only
## the winning pair is turned into a contact.
static func _swept_contact(a: PhysBody, b: PhysBody, delta: float) -> Dictionary:
	var a_hull := a.has_hull()
	var b_hull := b.has_hull()
	var a_xform := a.node.global_transform if a_hull and a.node != null else Transform3D()
	var b_xform := b.node.global_transform if b_hull and b.node != null else Transform3D()
	var a_count := a.hull.size() if a_hull else 1
	var b_count := b.hull.size() if b_hull else 1
	var a_solo := a.position()
	var b_solo := b.position()
	var best_t := Ccd.NO_HIT
	var best_pa := Vector3.ZERO
	var best_pb := Vector3.ZERO
	var best_ra := 0.0
	var best_rb := 0.0
	for i in a_count:
		var pa := a_xform * (a.hull[i]["offset"] as Vector3) if a_hull else a_solo
		var ra := float(a.hull[i]["radius"]) if a_hull else a.radius
		for j in b_count:
			var pb := b_xform * (b.hull[j]["offset"] as Vector3) if b_hull else b_solo
			var rb := float(b.hull[j]["radius"]) if b_hull else b.radius
			# ALREADY_OVERLAPPING is -1, so it sorts ahead of any real t and the
			# maxf below clamps it back to the start of the step.
			var t := Ccd.impact_time(pa, a.velocity, ra, pb, b.velocity, rb, delta)
			if t < best_t:
				best_t = t
				best_pa = pa
				best_pb = pb
				best_ra = ra
				best_rb = rb
	if best_t == Ccd.NO_HIT:
		return _miss()
	var at := maxf(best_t, 0.0)
	var normal := Ccd.normal_at(best_pa, a.velocity, best_pb, b.velocity, delta, at)
	return _contact_report(normal, best_pb - normal * best_rb, at, best_pa, best_pb, best_ra, best_rb)


## Overlap test between one pair of spheres. `pa`/`pb` are the sphere centres;
## the normal points A → B and the contact point sits on B's surface.
static func _sphere_overlap(pa: Vector3, ra: float, pb: Vector3, rb: float) -> Dictionary:
	var f := pb - pa
	var touch := ra + rb
	var f2 := f.length_squared()
	if f2 >= touch * touch:
		return _miss()
	var n := f / sqrt(f2) if f2 > 1e-12 else Vector3.UP
	return _contact_report(n, pb - n * rb, 0.0, pa, pb, ra, rb)


## Tangential slip becomes a friction impulse on both bodies (equal and
## opposite, so linear momentum is untouched) and, scaled by the profile, a
## spin on each. Friction is what turns a glancing hit into a deflection at
## all; without it every contact would be a straight bounce along the normal.
static func _apply_friction(
	a: PhysBody, b: PhysBody, contact: Dictionary, vrel: Vector3, normal: Vector3,
	jn: float, ia: float, ib: float, profile: PhysProfile
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
	_spin_from_contact(a, b, contact, t_hat, jt, profile)


## A contact off the centre line spins a body. The lever arm runs from the
## body's origin to the point on its *own* surface that took the hit, so a hit
## on the nose of a long hull torques it hard and a hit on its centre barely
## turns it — which is the cartoony outcome the plan wants: a glancing hit
## tumbles the ship, a dead-on one does not.
##
## For a single sphere that lever is exactly `radius` along the normal, so this
## reduces to the old `normal.cross(t_hat)` at the sphere's own radius. Both
## bodies take a torque from the same contact; the equal and opposite forces and
## lever arms of Newton's third law leave them spinning the same way.
static func _spin_from_contact(
	a: PhysBody, b: PhysBody, contact: Dictionary, t_hat: Vector3, jt: float, profile: PhysProfile
) -> void:
	if profile.impulse_to_spin <= 0.0:
		return
	var normal: Vector3 = contact["normal"]
	# torque = r × F, with F = ±t_hat·jt and I = 2/5·m·r² for a sphere.
	if not a.kinematic and a.radius > 0.0:
		var lever_a := (contact["pa"] as Vector3) + normal * float(contact["ra"]) - a.position()
		var inv_i_a := 1.0 / (0.4 * a.mass * a.radius * a.radius)
		a.angular += lever_a.cross(t_hat) * (jt * inv_i_a * profile.impulse_to_spin)
	if not b.kinematic and b.radius > 0.0:
		var lever_b := (contact["pb"] as Vector3) - normal * float(contact["rb"]) - b.position()
		var inv_i_b := 1.0 / (0.4 * b.mass * b.radius * b.radius)
		b.angular -= lever_b.cross(t_hat) * (jt * inv_i_b * profile.impulse_to_spin)


## Push two overlapping spheres apart along their contact normal (Baumgarte with
## a slop), proportional to the inverse masses so a ship shoves a rock far more
## than the rock shoves the ship. The bodies' *nodes* move; the overlap is the
## one between the contacting sections, so two ships separate from the hulls
## that met rather than from their centres.
static func _separate(
	a: PhysBody, b: PhysBody, contact: Dictionary, normal: Vector3, ia: float, ib: float, profile: PhysProfile
) -> void:
	var pa: Vector3 = contact["pa"]
	var pb: Vector3 = contact["pb"]
	var touch := float(contact["ra"]) + float(contact["rb"])
	var overlap := touch - pa.distance_to(pb)
	if overlap <= profile.penetration_slop:
		return
	var push := (overlap - profile.penetration_slop) * profile.position_correction / maxf(ia + ib, 1e-6)
	a.set_position(a.position() - normal * (push * ia))
	b.set_position(b.position() + normal * (push * ib))


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
