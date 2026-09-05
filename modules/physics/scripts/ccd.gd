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
	# A's motion relative to B. Treating B as still and A as sweeping keeps the
	# maths one quadratic instead of two moving spheres.
	var move := (a_vel - b_vel) * delta
	var f := a_pos - b_pos
	var radius := a_radius + b_radius

	var move_len2 := move.length_squared()
	if move_len2 <= STATIC_EPSILON:
		var d2 := f.length_squared()
		if d2 < radius * radius:
			return _hit(0.0, -f, b_pos, b_radius)
		return _miss()

	# |f + move·t|² = radius²  →  a·t² + 2b·t + c = 0
	var a_coef := move_len2
	var b_coef := f.dot(move)
	var c_coef := f.length_squared() - radius * radius
	if c_coef <= 0.0:
		# Already overlapping at the start of the step.
		return _hit(0.0, -f, b_pos, b_radius)

	var disc := b_coef * b_coef - a_coef * c_coef
	if disc < 0.0:
		return _miss()
	var t := (-b_coef - sqrt(disc)) / a_coef
	if t < 0.0 or t > 1.0:
		# Second root: first contact is behind us (t<0) or after the step (t>1).
		return _miss()
	var impact := a_pos + move * t
	return _hit(t, b_pos - impact, b_pos, b_radius)


static func _hit(t: float, toward_b: Vector3, b_pos: Vector3, b_radius: float) -> Dictionary:
	var normal := _normal_or(toward_b, Vector3.UP)
	return {
		"hit": true,
		"t": t,
		"normal": normal,
		"point": b_pos - normal * b_radius,
	}


static func _miss() -> Dictionary:
	return {"hit": false, "t": 0.0, "normal": Vector3.ZERO, "point": Vector3.ZERO}


## A degenerate-centres fallback normal: two bodies whose centres coincide have
## no direction to push along, so pick one that cannot be zero.
static func _normal_or(v: Vector3, fallback: Vector3) -> Vector3:
	var len2 := v.length_squared()
	if len2 < 1e-12:
		return fallback
	return v / sqrt(len2)
