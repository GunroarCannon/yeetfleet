## Newtonian gravity system with dominant-body selection.
##
## Instead of summing every body's pull (which causes moons to orbit the sun
## instead of their planet), we find the body producing the largest local
## acceleration and blend it with the runner-up. This is computed, not
## categorized — a procedurally-generated body slots in automatically with
## zero setup, and "moon" vs "star" emerges from the math, not from flags.
##
## Physics model:
##   F = G * M * m / r²  →  a = G * M / r²  (ship mass cancels)
##
## Key algorithm:
##   1. For each body, compute acceleration magnitude at query point
##   2. Sort by acceleration descending
##   3. Take top N (default 2) and weight by softmax of their accelerations
##   4. Blend the weighted direction vectors
##   5. Orbit math always runs against the single dominant body
##
## "Relevant range" is derived from mass alone:
##   r_relevant = sqrt(G * M / epsilon)
## where epsilon is the minimum acceleration we care about (e.g. 0.01 m/s²).
## This replaces the old is_planet flag for performance filtering.
class_name GravitySystem
extends RefCounted


## Gravity strength multiplier.
enum GravityMode {
	OFF,
	NORMAL,
	HIGH,
}


## Tuning constant: gravitational constant in game units.
## Tuned arcade-first: strong enough that falling toward a planet piles up
## serious speed (and a wrong orbit ends in a spectacular impact), while a
## matched tangential speed still holds a stable orbit.
const GAME_G := 3.0

## Minimum distance from a body's centre to avoid singularity.
const MIN_ORBIT_RADIUS := 10.0

## Below this acceleration (m/s²), a body is ignored entirely.
const RELEVANCE_EPSILON := 0.008

## Softmax temperature: controls how "winner-take-all" the blend is.
## Lower = sharper (closer to 100/0), higher = smoother blend.
## 3.0 means the runner-up gets ~15% weight when it's half as strong.
const BLEND_TEMPERATURE := 3.0

## How many top bodies to blend (2 = dominant + runner-up).
const BLEND_COUNT := 2


## A single gravitating body (planet, station, asteroid, gate, etc.).
class GravityBody:
	## World-space position of the body's centre.
	var position := Vector3.ZERO
	## Mass in game units. Determines gravitational pull.
	var mass := 1.0
	## Surface radius. Determines surface gravity and collision.
	var radius := 100.0
	## Surface gravity in m/s². Computed: g = G * M / R²
	var surface_gravity := 9.8
	## Human-readable name for debug/display.
	var name := ""
	## Optional UI hint — not used by physics. Keep for labels/tooltips.
	var is_planet := false
	## Derived: distance at which acceleration drops below epsilon.
	## Computed at registration time from mass.
	var relevant_range := 1000.0


## All registered gravitating bodies.
var _bodies: Array[GravityBody] = []
## Current gravity mode.
var mode: int = GravityMode.NORMAL
## Whether bodies attract things in ("pull"). When false, gravity is orbit-only:
## bodies still exist and keep their own orbits, and a ship can still be given a
## circular-orbit velocity, but nothing is ever dragged *towards* a body — no
## falling in. The player toggles this from the Gravity menu (or 6/…).
var pull_enabled := true
## Range multiplier: scales how far gravity reaches (applied to effective_dist).
var range_multiplier := 1.0

## The gravitational constant and falloff exponent of this system's force law,
## a = g·M / r^falloff. Both are profile-driven (M1): a profile can turn gravity
## up, or set falloff below the inverse-square 2.0 so it reaches further and
## slingshots turn dramatic and cartoonish. Defaults are the historical values;
## set them before bodies are registered (or call [method apply_law]) so every
## derived number uses the same law as the force itself.
var g := GAME_G
var falloff := 2.0


func _init() -> void:
	pass


# --- Registration ------------------------------------------------------------

## Register a gravitating body. relevant_range is derived from mass automatically.
func register_body(
	body_position: Vector3, body_mass: float, body_radius: float,
	body_name: String = "", is_planet_flag: bool = false
) -> GravityBody:
	var body := GravityBody.new()
	body.position = body_position
	body.mass = body_mass
	body.radius = body_radius
	body.name = body_name
	body.is_planet = is_planet_flag
	body.surface_gravity = g * body_mass / pow(maxf(body_radius, 0.01), falloff)
	# Derived relevance range: where acceleration drops below epsilon.
	body.relevant_range = pow(g * body_mass / RELEVANCE_EPSILON, 1.0 / falloff)
	_bodies.append(body)
	return body


## Apply a force law (g, falloff) and recompute every body's derived numbers so
## nothing keeps using the old law — the ranges a dominant-body search prunes by
## must match the force actually being integrated. Called when a feel profile is
## applied or cycled live.
func apply_law(new_g: float, new_falloff: float) -> void:
	g = new_g
	falloff = maxf(new_falloff, 1.01)
	for body in _bodies:
		body.surface_gravity = g * body.mass / pow(maxf(body.radius, 0.01), falloff)
		body.relevant_range = pow(g * body.mass / RELEVANCE_EPSILON, 1.0 / falloff)


## Remove all registered bodies. Call on scene teardown.
func clear() -> void:
	_bodies.clear()


# --- Dominant body selection --------------------------------------------------

## Acceleration magnitude at a point from a single body (scalar, no direction).
func _accel_magnitude(body: GravityBody, pos: Vector3) -> float:
	var diff := body.position - pos
	var dist := maxf(diff.length(), MIN_ORBIT_RADIUS)
	var effective_dist := dist / maxf(range_multiplier, 0.1)
	return g * body.mass / pow(effective_dist, falloff)


## Find the top N bodies by acceleration at a given position.
## Returns an Array of Dictionaries: [{body, accel, weight}, ...]
## Weight is softmax-normalized so they sum to ~1.0.
func find_dominant_bodies(pos: Vector3, n: int = BLEND_COUNT) -> Array[Dictionary]:
	# First pass: compute acceleration for every body within its relevant range.
	var candidates: Array[Dictionary] = []
	for body in _bodies:
		var dist := pos.distance_to(body.position)
		# Skip a body whose centre the query point is sitting on: a body must not
		# pull itself toward its own centre (the clamped near-field term would
		# otherwise read as a huge spurious force). This is what lets a body that
		# is itself gravitating — the moon — integrate against the field it lives
		# in without tearing its own orbit apart.
		if dist < MIN_ORBIT_RADIUS:
			continue
		# Quick reject: if we're outside the body's relevant range AND the
		# range multiplier doesn't extend it, skip. But always include if
		# we're very close (within 2× radius) — near surface, even weak
		# bodies matter for collision.
		if dist > body.relevant_range * maxf(range_multiplier, 0.1) and dist > body.radius * 2.0:
			continue
		var accel := _accel_magnitude(body, pos)
		if accel < RELEVANCE_EPSILON * 0.1:
			continue
		candidates.append({"body": body, "accel": accel})

	if candidates.is_empty():
		return []

	# A body that pulls under 5% as hard as the strongest is not competing for
	# the orbit — it must not dilute the dominant body's pull in the softmax
	# blend. Without this, a distant dwarf half a solar-system away would split
	# Tarn's weight and every orbit would drift outward (the moon was climbing
	# out because Glacius and Ashara at ~0.01 m/s² stole ~40% of the blend).
	var peak := 0.0
	for c in candidates:
		peak = maxf(peak, float(c["accel"]))
	var contenders: Array[Dictionary] = []
	for c in candidates:
		if float(c["accel"]) >= peak * 0.05:
			contenders.append(c)
	candidates = contenders

	# Sort by acceleration descending.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["accel"] > b["accel"]
	)

	# Take top n.
	var top_n: Array[Dictionary] = []
	for i in mini(n, candidates.size()):
		top_n.append(candidates[i])

	# Softmax weights from accelerations.
	var max_accel: float = top_n[0]["accel"]
	var total := 0.0
	for c in top_n:
		c["weight"] = exp((c["accel"] - max_accel) / BLEND_TEMPERATURE)
		total += c["weight"]
	# Normalize so weights sum to 1.0.
	for c in top_n:
		c["weight"] /= total

	return top_n


## Convenience: find the single dominant body at a position.
func find_dominant_body(pos: Vector3) -> GravityBody:
	var dominant := find_dominant_bodies(pos, 1)
	if dominant.is_empty():
		return null
	return dominant[0]["body"] as GravityBody


# --- Force computation -------------------------------------------------------

## Compute gravitational acceleration using dominant-body weighted blend.
## Returns m/s² in world space. Smooth transition at sphere-of-influence
## boundaries because the blend is continuous, not a hard switch.
func compute_gravity(object_position: Vector3) -> Vector3:
	if mode == GravityMode.OFF or not pull_enabled:
		return Vector3.ZERO

	var strength_mult := 2.0 if mode == GravityMode.HIGH else 1.0
	var dominant := find_dominant_bodies(object_position, BLEND_COUNT)

	if dominant.is_empty():
		return Vector3.ZERO

	var total_force := Vector3.ZERO
	for entry in dominant:
		var body: GravityBody = entry["body"]
		var weight: float = entry["weight"]
		var diff := body.position - object_position
		var dist := maxf(diff.length(), MIN_ORBIT_RADIUS)
		var effective_dist := dist / maxf(range_multiplier, 0.1)
		var accel_mag := g * body.mass / pow(effective_dist, falloff) * strength_mult
		total_force += diff.normalized() * accel_mag * weight

	return total_force


## Compute gravitational acceleration from a single body (for visualization, etc).
func compute_gravity_from(body: GravityBody, object_position: Vector3) -> Vector3:
	if mode == GravityMode.OFF or not pull_enabled:
		return Vector3.ZERO
	var diff := body.position - object_position
	var dist := maxf(diff.length(), MIN_ORBIT_RADIUS)
	var accel_magnitude := g * body.mass / pow(dist, falloff)
	if mode == GravityMode.HIGH:
		accel_magnitude *= 2.0
	return diff.normalized() * accel_magnitude


# --- Orbital mechanics -------------------------------------------------------

## Circular orbit velocity at a given distance from a body's centre, for the
## system's own force law: a = gM/r^falloff needs v = sqrt(gM·r^(1-falloff)),
## which collapses to the familiar sqrt(gM/r) at the inverse-square falloff 2.
func orbit_velocity(body: GravityBody, distance: float) -> float:
	var r := maxf(distance, MIN_ORBIT_RADIUS)
	return sqrt(g * body.mass * pow(r, 1.0 - falloff))


## Escape velocity at a given distance from a body's centre. For falloff > 1 the
## power-law potential is bounded below at infinity; at falloff 2 this is the
## usual sqrt(2)·v_orbit.
func escape_velocity(body: GravityBody, distance: float) -> float:
	var r := maxf(distance, MIN_ORBIT_RADIUS)
	var denom := falloff - 1.0
	if denom <= 0.01:
		return INF
	return sqrt(2.0 * g * body.mass * pow(r, 1.0 - falloff) / denom)


## Roche limit — inside this distance, tidal forces break apart a body.
func roche_limit(body: GravityBody) -> float:
	return body.radius * 2.4


## Check if an object at pos with vel is in a stable orbit around body.
func is_in_orbit(body: GravityBody, pos: Vector3, vel: Vector3) -> bool:
	var diff := body.position - pos
	var dist := diff.length()
	if dist < body.radius * 1.1:
		return false
	var v_orbit := orbit_velocity(body, dist)
	var speed := vel.length()
	# Within 40% of circular velocity counts as "in orbit". Real orbits are
	# rarely perfectly circular — speed varies around an ellipse — so a tight
	# band just flickers between in/out. The caller adds hysteresis on top.
	return absf(speed - v_orbit) / v_orbit < 0.40


## Compute the velocity vector for a stable circular orbit around body at pos.
func circular_orbit_velocity(body: GravityBody, pos: Vector3) -> Vector3:
	var to_body := body.position - pos
	var dist := to_body.length()
	if dist < MIN_ORBIT_RADIUS:
		return Vector3.ZERO
	var radial := to_body.normalized()
	var v_orbit := orbit_velocity(body, dist)
	# Tangential direction: perpendicular to radial, in a mostly-horizontal plane
	# (world up), so the orbit matches the player's own spawn orbit instead of
	# taking a plane that depends on where in the world the body happens to sit.
	var tangent := Vector3.UP.cross(radial).normalized()
	if tangent.length_squared() < 0.001:
		tangent = radial.cross(Vector3.RIGHT).normalized()
	return tangent * v_orbit


## Given a position and velocity, compute the predicted orbit elements.
## Returns {periapsis, apoapsis, eccentricity, period, ...} or empty dict.
func orbit_elements(body: GravityBody, pos: Vector3, vel: Vector3) -> Dictionary:
	var r_vec := pos - body.position
	var r := r_vec.length()
	if r < MIN_ORBIT_RADIUS:
		return {}
	var v := vel.length()
	# Effective mu for this system's law. Orbital elements assume the inverse-
	# square shape, so for a cartoon falloff this is an approximation, not exact.
	var mu := g * body.mass
	# Specific orbital energy: E = v²/2 - μ/r
	var energy := v * v / 2.0 - mu / r
	# Semi-major axis: a = -μ / (2E)  (negative E = bound orbit)
	if energy >= 0.0:
		return {}  # Hyperbolic or parabolic — unbound
	var a := -mu / (2.0 * energy)
	# Eccentricity from angular momentum.
	var h_vec := r_vec.cross(vel)
	var h := h_vec.length()
	var e := sqrt(1.0 + 2.0 * energy * h * h / (mu * mu))
	# Periapsis and apoapsis.
	var periapsis := a * (1.0 - e)
	var apoapsis := a * (1.0 + e) if e < 1.0 else INF
	# Orbital period: T = 2π * sqrt(a³ / μ)
	var period := TAU * sqrt(a * a * a / mu) if e < 1.0 else INF
	return {
		"periapsis": periapsis,
		"apoapsis": apoapsis,
		"eccentricity": e,
		"semi_major_axis": a,
		"period": period,
		"energy": energy,
	}


# --- Utility ----------------------------------------------------------------

## Find the nearest gravitating body to a position (by distance, not acceleration).
func nearest_body(pos: Vector3) -> GravityBody:
	var best: GravityBody = null
	var best_dist := INF
	for body in _bodies:
		var dist := pos.distance_to(body.position)
		if dist < best_dist:
			best_dist = dist
			best = body
	return best


## Find all bodies within a given distance of a position.
func bodies_within(pos: Vector3, max_distance: float) -> Array[GravityBody]:
	var result: Array[GravityBody] = []
	for body in _bodies:
		if pos.distance_to(body.position) < max_distance:
			result.append(body)
	return result


## Total number of registered bodies.
func body_count() -> int:
	return _bodies.size()


## Hill sphere radius — derived from mass ratio, not a category.
## For visualization/UI only — the real SOI is implicit in the acceleration blend.
func hill_sphere(body: GravityBody) -> float:
	return body.relevant_range


## Human-readable summary of all registered bodies.
func describe() -> String:
	var parts: PackedStringArray = []
	for body in _bodies:
		parts.append("%s: %.0f t, r=%.0f, g=%.1f m/s², range=%.0fm" % [
			body.name, body.mass, body.radius, body.surface_gravity,
			body.relevant_range,
		])
	return "GravitySystem [%s]: %d bodies\n  %s" % [
		["OFF", "NORMAL", "HIGH"][mode], _bodies.size(), "\n  ".join(parts)
	]
