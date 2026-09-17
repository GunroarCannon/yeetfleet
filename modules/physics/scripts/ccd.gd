## CCD: continuous collision detection for fast movers.
##
## The bug this solves is the one where a ship at speed passes through a rock
## between two frames — at 520 m/s a ship moves ~8.7 m per frame against rocks
## of radius 3-10 m, and under a gravity dive it moves far more. A discrete
## overlap test asks "are the two spheres overlapping *right now*?", which a
## fast body can answer "no" to on both sides of a rock it has crossed.
##
## This answers the right question: *does the path of body A this step cross the
## sphere of body B?* Body A sweeps from where it is to where it is going; B is
## expanded by A's radius and treated as static in A's frame (B's own motion is
## subtracted). The result is the time of first contact and the surface normal
## there, which [ImpulseSolver] resolves like any other collision.
class_name Ccd
extends RefCounted

## Very small relative travel — treat as a static overlap test, because solving
## a quadratic for a body that barely moved invites floating-point noise.
const STATIC_EPSILON := 1e-9

## [method impact_time]'s two non-answers: the pair never touches within the
## step, or they start the step already touching.
const NO_HIT := INF
const ALREADY_OVERLAPPING := -1.0


## Where, if anywhere, A's swept sphere hits B's during a step of `delta`
## seconds. Returns a Dictionary with:
##   hit     : bool
##   t       : time of first contact in [0, 1] along the step
##   normal  : unit vector from A's centre toward B's at contact (A → B)
##   point   : the contact point on B's near surface
static func hit_info(
	a_pos: Vector3, a_vel: Vector3, a_radius: float,
	b_pos: Vector3, b_vel: Vector3, b_radius: float,
	delta: float
) -> Dictionary:
	var t := impact_time(a_pos, a_vel, a_radius, b_pos, b_vel, b_radius, delta)
	if t == NO_HIT:
		return _miss()
	var at := maxf(t, 0.0)
	var normal := normal_at(a_pos, a_vel, b_pos, b_vel, delta, at)
	return {"hit": true, "t": at, "normal": normal, "point": b_pos - normal * b_radius}


## When A's swept sphere first touches B's, as a time in [0, 1] along the step —
## [constant NO_HIT] if it never does, [constant ALREADY_OVERLAPPING] if the pair
## starts the step touching.
##
## The same maths [method hit_info] does, split out so a caller sweeping many
## sphere pairs against each other can find the earliest one without building a
## Dictionary per pair: a ship's hull is dozens of spheres, and the pair scan an
## allocation each ran into milliseconds.
static func impact_time(
	a_pos: Vector3, a_vel: Vector3, a_radius: float,
	b_pos: Vector3, b_vel: Vector3, b_radius: float,
	delta: float
) -> float:
	# A's motion relative to B. Treating B as still and A as sweeping keeps the
	# maths one quadratic instead of two moving spheres.
	var move := (a_vel - b_vel) * delta
	var f := a_pos - b_pos
	var radius := a_radius + b_radius

	var move_len2 := move.length_squared()
	if move_len2 <= STATIC_EPSILON:
		if f.length_squared() < radius * radius:
			return ALREADY_OVERLAPPING
		return NO_HIT

	# |f + move·t|² = radius²  →  a·t² + 2b·t + c = 0
	var b_coef := f.dot(move)
	var c_coef := f.length_squared() - radius * radius
	if c_coef <= 0.0:
		# Already overlapping at the start of the step.
		return ALREADY_OVERLAPPING

	var disc := b_coef * b_coef - move_len2 * c_coef
	if disc < 0.0:
		return NO_HIT
	var t := (-b_coef - sqrt(disc)) / move_len2
	if t < 0.0 or t > 1.0:
		# Second root: first contact is behind us (t<0) or after the step (t>1).
		return NO_HIT
	return t


## The unit normal from A's centre toward B's at contact, for an impact found at
## [param t] by [method impact_time] — the two must be given the same arguments.
static func normal_at(
	a_pos: Vector3, a_vel: Vector3, b_pos: Vector3, b_vel: Vector3, delta: float, t: float
) -> Vector3:
	var move := (a_vel - b_vel) * delta
	var impact := a_pos + move * maxf(t, 0.0)
	return _normal_or(b_pos - impact, Vector3.UP)


static func _miss() -> Dictionary:
	return {"hit": false, "t": 0.0, "normal": Vector3.ZERO, "point": Vector3.ZERO}


## A degenerate-centres fallback normal: two bodies whose centres coincide have
## no direction to push along, so pick one that cannot be zero.
static func _normal_or(v: Vector3, fallback: Vector3) -> Vector3:
	var len2 := v.length_squared()
	if len2 < 1e-12:
		return fallback
	return v / sqrt(len2)
