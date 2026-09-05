## Behaviour state machine for AI ships, now with group context.
##
## The individual state machine (CRUISE, PATROL, INVESTIGATE, FLEE) handles
## per-ship decisions. Group forces (boids, formation, wolfpack) are computed
## by [AiGroupBehaviour] and blended in by this class based on the ship's
## [member ArchetypeData].
##
## Architecture:
##   AiShip.tick_ai() → calls behaviour.update() with group member data
##   behaviour.update() → evaluates state machine + group forces
##   behaviour.update() → returns {throttle, yaw, pitch, roll, boost}
##   AiShip applies the result to FlightModel.command
##
## To add a new group behaviour:
##   1. Add a static func to [AiGroupBehaviour]
##   2. Add a call in [method _compute_group_force] with a weight
##   3. The blend happens automatically
class_name AiBehaviour
extends RefCounted


enum State {
	IDLE,
	CRUISE,
	PATROL,
	INVESTIGATE,
	FLEE,
	## In formation — maintaining offset from a leader or group centre.
	FORMATION,
	## Orbiting a point — station guard, cult ritual, loiter pattern.
	ORBIT,
	## Pursuing a target — wolfpack, bounty hunter, attack run.
	PURSUIT,
	## Holding position — defense grid, leapfrog cover.
	HOLD,
}


const ARRIVAL_DIST := 120.0
const PATROL_RADIUS := 400.0
const DETECTION_RANGE := 800.0
const FLEE_RANGE := 200.0
const INVESTIGATE_TIMEOUT := 12.0
const FLEE_TIMEOUT := 6.0
const THROTTLE_SMOOTH := 2.0
const ROTATION_SMOOTH := 2.5

var state: State = State.IDLE
var _waypoint := Vector3.ZERO
var _patrol_centre := Vector3.ZERO
var _state_timer := 0.0
var _current_throttle := 0.0
var _rng := RandomNumberGenerator.new()

## Set by [AiShip]; the behaviour reads this to decide state transitions.
var player_position := Vector3.ZERO
var player_visible := false

## Group context: set by [AiShip.tick_ai] before calling update().
var group_members: Array = []  # Array of AiGroupBehaviour.Member
var my_index_in_group := 0
var group_total := 1
var archetype_data: AiFactions.ArchetypeData = null
## Group centre position (average of all members).
var group_centre := Vector3.ZERO
## Leader position (first member, or a designated leader).
var leader_position := Vector3.ZERO
## Current time, for noise functions.
var _time := 0.0
## Threat position detected by the group.
var threat_position := Vector3.ZERO
var threat_detected := false
## Gravity system reference, set by [AiShip] so behaviour can do gravity-aware throttle.
var gravity_ref: GravitySystem = null


func _init() -> void:
	_rng.randomize()


func initialise(spawn_pos: Vector3) -> void:
	_patrol_centre = spawn_pos
	_pick_cruise_waypoint(spawn_pos)
	state = State.CRUISE
	_state_timer = 0.0


## Main entry point. Returns command values for one frame.
func update(delta: float, ship_pos: Vector3, ship_basis: Basis, top_speed: float) -> Dictionary:
	_time += delta
	_state_timer += delta

	_evaluate_transitions(ship_pos)

	var target_pos := _waypoint
	var desired_throttle := 0.0
	var desired_boost := false

	match state:
		State.IDLE:
			desired_throttle = 0.05
			target_pos = _waypoint
		State.CRUISE:
			desired_throttle = 0.6
			if ship_pos.distance_to(_waypoint) < ARRIVAL_DIST:
				_pick_cruise_waypoint(ship_pos)
		State.PATROL:
			desired_throttle = 0.4
			_update_patrol_waypoint(ship_pos)
		State.INVESTIGATE:
			desired_throttle = 0.85
			target_pos = player_position
			if _state_timer > INVESTIGATE_TIMEOUT:
				state = State.PATROL
				_pick_patrol_waypoint(ship_pos)
		State.FLEE:
			desired_throttle = 1.0
			desired_boost = archetype_data == null or archetype_data.can_boost
			if _state_timer > FLEE_TIMEOUT:
				state = State.CRUISE
				_pick_cruise_waypoint(ship_pos)
		State.FORMATION:
			desired_throttle = 0.7
			target_pos = group_centre
		State.ORBIT:
			desired_throttle = 0.5
		State.PURSUIT:
			desired_throttle = 0.9
			desired_boost = true
			target_pos = threat_position if threat_detected else player_position
			# Turret/sniper combat style: inside weapons range the ship stops
			# chasing and holds nearly still, rotating fully onto the target so
			# its guns land. The steering below still points at the target; only
			# the closing speed dies.
			if archetype_data != null and archetype_data.hold_to_aim \
				and ship_pos.distance_to(target_pos) < 500.0:
				desired_throttle = 0.05
				desired_boost = false
		State.HOLD:
			desired_throttle = 0.05
			target_pos = ship_pos

	# Compute the individual steering force toward the target.
	var individual_force := _steer_toward(ship_pos, ship_basis, target_pos)

	# A hold-to-aim ship that has a target in range must rotate exactly onto it —
	# the group forces would dilute the aim for the sake of formation shape.
	var aiming := false
	if archetype_data != null and archetype_data.hold_to_aim:
		var aim_at := threat_position if threat_detected else player_position
		aiming = ship_pos.distance_to(aim_at) < 500.0

	# Compute group-level steering force.
	var group_force := _compute_group_force(ship_pos, ship_basis, delta)

	# Blend individual and group forces. Group force weight depends on archetype.
	var group_weight := 0.0
	if not aiming and archetype_data != null:
		if archetype_data.use_boids or archetype_data.use_swarm:
			group_weight = 0.6
		elif archetype_data.group_size_min > 1:
			group_weight = 0.3
		else:
			group_weight = 0.0

	var blended := individual_force * (1.0 - group_weight) + group_force * group_weight

	# Gravity-aware throttle reduction: when near a dominant body, the ship
	# can let gravity do some of the work. Civilian and mining archetypes
	# reduce throttle more aggressively (fuel saving behaviour).
	if archetype_data != null and gravity_ref != null:
		var dominant := gravity_ref.find_dominant_body(ship_pos)
		if dominant != null:
			var dist := ship_pos.distance_to(dominant.position)
			var influence := dominant.relevant_range
			if dist < influence:
				# Reduce throttle proportionally — closer = less thrust needed.
				var gravity_factor := clampf(dist / influence, 0.2, 1.0)
				if "civilian" in archetype_data.tags or "mining" in archetype_data.tags:
					desired_throttle *= gravity_factor
				else:
					desired_throttle *= lerpf(gravity_factor, 1.0, 0.5)

	# Extract yaw/pitch from the blended force.
	var forward := -ship_basis.z
	var yaw := 0.0
	var pitch := 0.0
	if forward.length_squared() > 0.001 and blended.length_squared() > 0.001:
		var local_target := ship_basis.inverse() * blended.normalized()
		yaw = clampf(-atan2(local_target.x, -local_target.z), -1.0, 1.0)
		var flat_dist := sqrt(local_target.x * local_target.x + local_target.z * local_target.z)
		pitch = clampf(atan2(local_target.y, flat_dist), -1.0, 1.0)

	# Speed multiplier from archetype.
	if archetype_data != null:
		desired_throttle *= archetype_data.speed_mult

	_current_throttle = lerpf(_current_throttle, desired_throttle, clampf(delta * THROTTLE_SMOOTH, 0.0, 1.0))

	return {
		"throttle": _current_throttle,
		"yaw": yaw,
		"pitch": pitch,
		"roll": 0.0,
		"boost": desired_boost,
	}


# --- Group force computation -------------------------------------------------

func _compute_group_force(ship_pos: Vector3, ship_basis: Basis, delta: float) -> Vector3:
	if group_members.size() <= 1 or archetype_data == null:
		return Vector3.ZERO

	var me := AiGroupBehaviour.Member.new()
	me.position = ship_pos
	me.velocity = Vector3.ZERO  # Caller should set this; approximation is fine
	me.forward = -ship_basis.z
	me.index = my_index_in_group

	var force := Vector3.ZERO

	# Boid flocking.
	if archetype_data.use_boids:
		force += AiGroupBehaviour.boid_flock(me, group_members, _time)

	# Swarm rules (cellular automata — local rules → emergent patterns).
	if archetype_data.use_swarm:
		force += AiGroupBehaviour.swarm_steer(me, group_members, _time)

	# Formation offset (if not using boids/swarm exclusively).
	if not archetype_data.use_boids and not archetype_data.use_swarm:
		if group_total > 1:
			var offsets := AiGroupBehaviour.formation_offsets(
				archetype_data.group_mode, group_total, archetype_data.formation_spacing
			)
			if my_index_in_group < offsets.size():
				force += AiGroupBehaviour.formation_steer(
					ship_pos, -ship_basis.z,
					leader_position, offsets[my_index_in_group],
					1.0
				)

	# Threat response.
	if threat_detected:
		force += AiGroupBehaviour.threat_steer(
			ship_pos, threat_position,
			my_index_in_group, group_total,
			archetype_data.default_response, _time
		)

	# Wolfpack pursuit (if in PURSUIT state and aggression is high).
	if state == State.PURSUIT and archetype_data.aggression > 0.5:
		force += AiGroupBehaviour.wolfpack_pursuit(
			ship_pos, -ship_basis.z,
			my_index_in_group, group_total,
			threat_position, Vector3.ZERO, _time,
			archetype_data.combat_pattern
		)

	# Orbit behaviour.
	if state == State.ORBIT:
		force = AiGroupBehaviour.orbit_steer(
			ship_pos, -ship_basis.z,
			_patrol_centre, 200.0, 0.5
		)

	return force


func _steer_toward(ship_pos: Vector3, ship_basis: Basis, target_pos: Vector3) -> Vector3:
	var to_target := (target_pos - ship_pos).normalized()
	return to_target


# --- State transitions -------------------------------------------------------

func _evaluate_transitions(ship_pos: Vector3) -> void:
	var dist_to_player := ship_pos.distance_to(player_position)

	# Group-level threat assessment: if any member detects the player, the
	# whole group knows. Threat position is shared.
	if player_visible and dist_to_player < DETECTION_RANGE:
		threat_position = player_position
		threat_detected = true

	match state:
		State.FLEE:
			if dist_to_player > FLEE_RANGE * 2.5:
				state = State.CRUISE
				_pick_cruise_waypoint(ship_pos)
		State.PURSUIT:
			if dist_to_player > DETECTION_RANGE * 1.5:
				state = State.CRUISE
				_pick_cruise_waypoint(ship_pos)
		_:
			# Individual state transitions based on player proximity.
			if archetype_data != null and archetype_data.aggression >= 1.0:
				# Always aggressive: attack immediately.
				if player_visible and dist_to_player < archetype_data.detection_range:
					state = State.PURSUIT
					_state_timer = 0.0
			elif player_visible and dist_to_player < (archetype_data.flee_range if archetype_data != null else FLEE_RANGE):
				state = State.FLEE
				_state_timer = 0.0
				_waypoint = ship_pos + (ship_pos - player_position).normalized() * 600.0
			elif player_visible and dist_to_player < (archetype_data.detection_range if archetype_data != null else DETECTION_RANGE):
				if archetype_data != null and archetype_data.aggression > 0.5:
					state = State.PURSUIT
				else:
					state = State.INVESTIGATE
				_state_timer = 0.0


# --- Waypoint helpers --------------------------------------------------------

func _pick_cruise_waypoint(from: Vector3) -> void:
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(600.0, 2400.0)
	var height := _rng.randf_range(-120.0, 120.0)
	_waypoint = Vector3(cos(angle) * radius, height, sin(angle) * radius)


func _pick_patrol_waypoint(from: Vector3) -> void:
	var offset := Vector3(
		_rng.randf_range(-PATROL_RADIUS, PATROL_RADIUS),
		_rng.randf_range(-80.0, 80.0),
		_rng.randf_range(-PATROL_RADIUS, PATROL_RADIUS),
	)
	_waypoint = _patrol_centre + offset


func _update_patrol_waypoint(ship_pos: Vector3) -> void:
	if ship_pos.distance_to(_waypoint) < ARRIVAL_DIST:
		_pick_patrol_waypoint(ship_pos)
