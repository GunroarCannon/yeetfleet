## Group-level AI behaviour algorithms. Pure functions — no state, no nodes.
##
## Each function takes a ship's position/basis and an array of group member
## data, and returns a steering vector (direction + magnitude). The caller
## ([AiBehaviour]) blends these with its own per-ship state machine.
##
## Design principles:
##   - Every function is a pure computation: same inputs → same output.
##   - No allocation in the hot path (no Array.append, no Dictionary creation).
##   - Results are Vector3 steering forces, combined by the caller.
##   - Adding a new algorithm means adding one static func here and one
##     enum value in [enum AiBehaviour.GroupMode].
##
## Algorithms implemented:
##   1. Boid flocking (Reynolds 1987) — separation, alignment, cohesion
##   2. Formation flying — V, line, sphere, scatter, trail
##   3. Wolfpack pursuit — encircle, pincer, feint
##   4. Orbit behaviour — circle a target at fixed radius
##   5. Swarm cellular automata — local rules → emergent patterns
##   6. Threat response — group investigate, group flee, group attack
##   7. Leapfrog — alternating ships advance while others hold
class_name AiGroupBehaviour
extends RefCounted


## --- Member data passed into every function -----------------------------------
## Lightweight struct: just position, velocity, forward, and a tag.
## The caller builds a PackedArray of these each frame (no allocation after warmup).
class Member:
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var forward := Vector3.FORWARD
	var index := 0
	## Arbitrary tag for grouping (faction id hash, squad id, etc.).
	var tag := 0


# =============================================================================
# 1. BOID FLOCKING (Reynolds 1987)
# =============================================================================
# Three simple rules produce emergent group movement:
#   Separation: steer away from nearby members (avoid collision)
#   Alignment: steer toward the average heading of nearby members
#   Cohesion: steer toward the average position of nearby members
#
# Each rule has a range and a weight. The caller sums the three forces.
# Perlin noise is added to the result so the flock breathes instead of
# flying in perfect lockstep.

const BOID_SEPARATION_RANGE := 40.0
const BOID_ALIGNMENT_RANGE := 150.0
const BOID_COHESION_RANGE := 200.0
const BOID_SEPARATION_WEIGHT := 2.5
const BOID_ALIGNMENT_WEIGHT := 1.0
const BOID_COHESION_WEIGHT := 0.8
const BOID_NOISE_AMPLITUDE := 0.15


## Compute the boid steering force for one ship within its group.
## [param me] is the ship's own data; [param neighbors] is the full group array.
## Returns a normalised direction × strength, ready to be blended with other forces.
static func boid_flock(me: Member, neighbors: Array, time: float) -> Vector3:
	var separation := Vector3.ZERO
	var alignment := Vector3.ZERO
	var cohesion := Vector3.ZERO
	var sep_count := 0
	var align_count := 0
	var coh_count := 0

	for i in neighbors.size():
		var other: Member = neighbors[i]
		if other.index == me.index:
			continue
		var diff := me.position - other.position
		var dist := diff.length()

		# Separation: push away from close neighbors.
		if dist > 0.001 and dist < BOID_SEPARATION_RANGE:
			separation += diff.normalized() / dist
			sep_count += 1

		# Alignment: match heading of nearby neighbors.
		if dist < BOID_ALIGNMENT_RANGE:
			alignment += other.forward
			align_count += 1

		# Cohesion: steer toward centre of nearby neighbors.
		if dist < BOID_COHESION_RANGE:
			cohesion += other.position
			coh_count += 1

	var force := Vector3.ZERO
	if sep_count > 0:
		force += (separation / float(sep_count)).normalized() * BOID_SEPARATION_WEIGHT
	if align_count > 0:
		force += (alignment / float(align_count)).normalized() * BOID_ALIGNMENT_WEIGHT
	if coh_count > 0:
		var centre := cohesion / float(coh_count)
		force += (centre - me.position).normalized() * BOID_COHESION_WEIGHT

	# Add Perlin-like noise so the flock breathes.
	var noise := Vector3(
		sin(me.position.x * 0.01 + time * 0.7) * BOID_NOISE_AMPLITUDE,
		sin(me.position.y * 0.013 + time * 0.5) * BOID_NOISE_AMPLITUDE,
		sin(me.position.z * 0.011 + time * 0.9) * BOID_NOISE_AMPLITUDE,
	)
	return force + noise


# =============================================================================
# 2. FORMATION FLYING
# =============================================================================
# Ships maintain a fixed offset from a leader or a formation centre.
# The formation shape is defined by a set of offsets; each ship picks one.
# The ship steers toward its offset position, with a spring force that
# damps oscillation.

enum FormationShape {
	## Two diverging lines from a leader — the classic fighter sweep.
	V_FORM,
	## Single file, one behind the other.
	LINE,
	## Roughly spherical cloud around a centre.
	SPHERE,
	## Scattered randomly, no fixed positions — just保持 loose proximity.
	SCATTER,
	## Ships trail behind the leader at staggered distances.
	TRAIL,
	## Alternating left-right offset, like a zipper.
	ZIPPER,
}


## Generate formation offsets for [param count] ships in the given shape.
## Each offset is relative to the formation centre/leader.
static func formation_offsets(shape: int, count: int, spacing: float) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	match shape:
		FormationShape.V_FORM:
			for i in count:
				var side := 1.0 if i % 2 == 0 else -1.0
				var rank := float(i / 2 + 1)
				offsets.append(Vector3(side * spacing * rank * 0.6, 0.0, spacing * rank))
		FormationShape.LINE:
			for i in count:
				offsets.append(Vector3(0.0, 0.0, spacing * float(i + 1)))
		FormationShape.SPHERE:
			for i in count:
				var phi := acos(1.0 - 2.0 * float(i + 0.5) / float(count))
				var theta := TAU * float(i) / float(count) * (1.0 + sqrt(5.0))
				offsets.append(Vector3(
					sin(phi) * cos(theta),
					sin(phi) * sin(theta),
					cos(phi)
				) * spacing)
		FormationShape.SCATTER:
			for i in count:
				var angle := float(i) * TAU / float(count) + float(i) * 0.618
				var r := spacing * (0.5 + 0.5 * sin(float(i) * 2.3))
				offsets.append(Vector3(cos(angle) * r, sin(float(i) * 1.7) * r * 0.3, sin(angle) * r))
		FormationShape.TRAIL:
			for i in count:
				var side := sin(float(i) * 1.2) * spacing * 0.3
				offsets.append(Vector3(side, 0.0, spacing * float(i + 1) * 0.8))
		FormationShape.ZIPPER:
			for i in count:
				var side := spacing * 0.5 * (1.0 if i % 2 == 0 else -1.0)
				offsets.append(Vector3(side, 0.0, spacing * float(i + 1) * 0.5))
	return offsets


## Steer toward a formation offset position. Returns a direction vector.
static func formation_steer(
	me_position: Vector3, me_forward: Vector3,
	target_world_pos: Vector3, offset: Vector3,
	strength: float
) -> Vector3:
	var desired := target_world_pos + offset
	var to_desired := desired - me_position
	if to_desired.length_squared() < 0.01:
		return Vector3.ZERO
	return to_desired.normalized() * strength


# =============================================================================
# 3. WOLFPACK PURSUIT
# =============================================================================
# Multiple ships coordinate to chase a target. Three classic patterns:
#   Encircle: ships spread around the target's predicted position
#   Pincer: two groups approach from opposite sides
#   Feint: some ships distract while others flank

## Compute a pursuit steering vector for one ship in a wolfpack.
## [param my_index] and [param total] determine which role this ship plays.
## [param target_pos] and [param target_vel] are the prey's state.
static func wolfpack_pursuit(
	me_pos: Vector3, me_fwd: Vector3,
	my_index: int, total: int,
	target_pos: Vector3, target_vel: Vector3,
	time: float, pattern: int = 0
) -> Vector3:
	if total <= 1:
		return (target_pos - me_pos).normalized()

	var to_target := target_pos - me_pos
	var dist := to_target.length()

	match pattern:
		0:  # Encircle — spread around the target's predicted position
			var predict_time := clampf(dist / 300.0, 0.5, 3.0)
			var predicted := target_pos + target_vel * predict_time
			var angle := TAU * float(my_index) / float(total) + time * 0.3
			var circle_radius := clampf(dist * 0.4, 30.0, 200.0)
			var offset := Vector3(cos(angle) * circle_radius, sin(angle * 0.7) * circle_radius * 0.3, sin(angle) * circle_radius)
			return (predicted + offset - me_pos).normalized()

		1:  # Pincer — half the group goes left, half goes right
			var side := 1.0 if my_index < total / 2 else -1.0
			var flank_offset := to_target.normalized().cross(Vector3.UP) * side * dist * 0.5
			var ahead := to_target.normalized() * dist * 0.3
			return (target_pos + flank_offset + ahead - me_pos).normalized()

		2:  # Feint — some ships approach directly, others circle wide
			if my_index % 3 == 0:
				# Direct approach (the feint)
				return to_target.normalized()
			else:
				# Wide flanking approach
				var angle := PI * 0.5 * float(my_index % 3) + time * 0.2
				var flank := to_target.normalized().cross(Vector3.UP) * sin(angle) * dist * 0.6
				var ahead := to_target.normalized() * dist * 0.4
				return (target_pos + flank + ahead - me_pos).normalized()

		_:  # Default: direct pursuit with slight spread
			var spread_angle := TAU * float(my_index) / float(total)
			var spread := Vector3(cos(spread_angle), 0.0, sin(spread_angle)) * 20.0
			return (target_pos + spread - me_pos).normalized()


# =============================================================================
# 4. ORBIT BEHAVIOUR
# =============================================================================
# Circle a point at a fixed radius and altitude. Used for station patrols,
# planet orbits, and loiter patterns.

## Steer to orbit [param centre] at [param radius] metres, at [param speed].
## The orbit plane is determined by [param up] (default Y-up).
static func orbit_steer(
	me_pos: Vector3, me_fwd: Vector3,
	centre: Vector3, radius: float, speed: float,
	up := Vector3.UP
) -> Vector3:
	var to_centre := centre - me_pos
	var dist := to_centre.length()

	# Tangential direction: perpendicular to the radial vector in the orbit plane.
	var radial := to_centre.normalized()
	var tangent := up.cross(radial).normalized()
	if tangent.length_squared() < 0.001:
		tangent = Vector3.FORWARD.cross(radial).normalized()

	# Desired position: on the orbit circle, ahead of current position.
	var orbit_error := absf(dist - radius)
	var radial_pull := radial * (dist - radius) * 0.5  # Pull toward correct radius
	var tangential_pull := tangent * speed              # Push along the orbit

	return (radial_pull + tangential_pull).normalized() * (1.0 + orbit_error * 0.01)


# =============================================================================
# 5. SWARM CELLULAR AUTOMATA
# =============================================================================
# Each ship follows simple local rules based on its immediate neighbors.
# Complex group patterns emerge without a central coordinator.
#
# Rules (inspired by Reynolds' boids + Craig's aggregation):
#   1. If too close to any neighbor → repel (separation)
#   2. If isolated (no neighbors within range) → move toward nearest neighbor
#   3. If in a cluster (enough neighbors) → match velocity (alignment)
#   4. Random perturbation prevents deadlocks
#
# The "cellular" aspect: each ship's state depends only on its local
# neighborhood, not on global state. This makes it scale naturally —
# 3 ships or 300, the rules are the same.

const SWARM_REPEL_RANGE := 25.0
const SWARM_ALIGN_RANGE := 100.0
const SWARM_CLUSTER_THRESHOLD := 3
const SWARM_REPEL_FORCE := 3.0
const SWARM_ALIGN_FORCE := 1.5
const SWARM_ATTRACT_FORCE := 1.0


## Compute swarm steering for one ship. Rules are evaluated in priority order.
static func swarm_steer(me: Member, neighbors: Array, time: float) -> Vector3:
	var force := Vector3.ZERO
	var nearby_count := 0
	var nearest_dist := INF
	var nearest_dir := Vector3.ZERO

	for i in neighbors.size():
		var other: Member = neighbors[i]
		if other.index == me.index:
			continue
		var diff := me.position - other.position
		var dist := diff.length()

		if dist < SWARM_REPEL_RANGE and dist > 0.001:
			# Rule 1: too close → repel hard
			force += diff.normalized() * SWARM_REPEL_FORCE / dist
			nearby_count += 1
		elif dist < SWARM_ALIGN_RANGE:
			nearby_count += 1
			# Rule 3: in a cluster → match velocity
			force += (other.velocity - me.velocity).normalized() * SWARM_ALIGN_FORCE

		if dist < nearest_dist and dist > 0.001:
			nearest_dist = dist
			nearest_dir = (other.position - me.position).normalized()

	# Rule 2: isolated → move toward nearest neighbor
	if nearby_count == 0 and nearest_dist < INF:
		force += nearest_dir * SWARM_ATTRACT_FORCE

	# Rule 4: random perturbation (prevents gridlock)
	var noise := Vector3(
		sin(time * 1.3 + float(me.index) * 7.1) * 0.3,
		sin(time * 0.9 + float(me.index) * 11.3) * 0.3,
		sin(time * 1.7 + float(me.index) * 3.7) * 0.3,
	)
	return force + noise


# =============================================================================
# 6. THREAT RESPONSE (GROUP-LEVEL)
# =============================================================================
# When one ship detects a threat, the whole group reacts. These functions
# compute group-level steering from a shared threat assessment.

enum ThreatResponse {
	## Ignore the threat.
	IGNORE,
	## Group investigates — ships converge on the threat from spread positions.
	INVESTIGATE,
	## Group flees — ships scatter away from the threat.
	FLEE,
	## Group attacks — wolfpack pursuit of the threat.
	ATTACK,
	## Group defends — orbit around a friendly asset being threatened.
	DEFEND,
}


## Compute a threat response steering vector for one ship.
## [param threat_pos] is where the danger is.
## [param my_index] and [param total] determine spread within the response.
## [param response] is the chosen group response.
static func threat_steer(
	me_pos: Vector3, threat_pos: Vector3,
	my_index: int, total: int,
	response: int, time: float
) -> Vector3:
	match response:
		ThreatResponse.IGNORE:
			return Vector3.ZERO
		ThreatResponse.FLEE:
			var away := (me_pos - threat_pos).normalized()
			var scatter := Vector3(
				sin(float(my_index) * 2.1 + time * 0.5),
				cos(float(my_index) * 3.7 + time * 0.3) * 0.3,
				sin(float(my_index) * 1.3 + time * 0.7)
			) * 0.4
			return (away + scatter).normalized()
		ThreatResponse.INVESTIGATE:
			var approach := (threat_pos - me_pos).normalized()
			var spread_angle := TAU * float(my_index) / float(total)
			var spread := Vector3(cos(spread_angle), 0.0, sin(spread_angle)) * 0.3
			return (approach + spread).normalized()
		ThreatResponse.ATTACK:
			return wolfpack_pursuit(me_pos, Vector3.FORWARD, my_index, total, threat_pos, Vector3.ZERO, time, 0)
		ThreatResponse.DEFEND:
			# Orbit the threatened asset, facing outward.
			return orbit_steer(me_pos, Vector3.FORWARD, threat_pos, 150.0, 1.0)
	return Vector3.ZERO


# =============================================================================
# 7. LEAPFROG
# =============================================================================
# Alternating ships advance while others hold position. Used by military
# formations to maintain suppressive coverage while closing on a target.

## Determine if this ship should advance or hold based on its index and a timer.
## Returns true if the ship should push forward, false if it should hold.
static func leapfrog_should_advance(my_index: int, timer: float, period: float) -> bool:
	var phase := fmod(timer, period * 2.0)
	var group_phase := fmod(float(my_index) * period, period * 2.0)
	return fmod(phase + group_phase, period * 2.0) < period


## Steering for a leapfrog advance. [param advance] is true if this ship
## should push forward, false if it should hold and cover.
static func leapfrog_steer(
	me_pos: Vector3, me_fwd: Vector3,
	advance: bool, objective_pos: Vector3,
	cover_angle: float
) -> Vector3:
	if advance:
		# Push toward the objective.
		return (objective_pos - me_pos).normalized()
	else:
		# Hold position, rotate to cover a specific angle.
		var to_obj := (objective_pos - me_pos).normalized()
		var cover_dir := to_obj.rotated(Vector3.UP, cover_angle)
		return cover_dir * 0.3  # Low throttle — holding, not rushing


# =============================================================================
# UTILITY: BLEND MULTIPLE STEERING FORCES
# =============================================================================
# The caller collects several forces (boid + formation + threat, etc.)
# and blends them with weights. This function does the weighted average.

## Blend an array of {force: Vector3, weight: float} dictionaries into one vector.
static func blend_forces(forces: Array[Dictionary]) -> Vector3:
	var result := Vector3.ZERO
	var total_weight := 0.0
	for f: Dictionary in forces:
		var w: float = f.get("weight", 1.0)
		var v: Vector3 = f.get("force", Vector3.ZERO)
		result += v * w
		total_weight += w
	if total_weight > 0.001:
		result /= total_weight
	return result
