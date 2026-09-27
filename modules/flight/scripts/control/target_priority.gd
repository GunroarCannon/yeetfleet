## TargetPriority: which ship a one-thumb movement profile should go for.
##
## Used by the swipe profile's course correction and tap-to-fire, and by the
## slingshot's bounce ("the next body to ping-pong toward"). Nearest is not
## enough: a pilot flicking toward a crowd wants the ship that is both an enemy
## and about to die, not the harmless satellite that happens to be closer.
##
##     score = hostility × (1 + weakness) × facing / (1 + distance / FALLOFF)
##
## - hostility: HOSTILE 1, WARY 0.5, anything else 0 (friendlies and harmless
##   ships are never picked) — unless [param any_side], where harmless ships
##   score [constant HARMLESS_WEIGHT] and friendlies [constant FRIENDLY_WEIGHT]
##   (the launch magnet goes for anything, hostiles first);
## - weakness: 1 − hp/max_hp, plus [constant POPCORN_BONUS] for popcorn ships
##   (they die to any ram);
## - facing: how well the ship lines up with [param dir], 0 outside the cone.
class_name TargetPriority
extends RefCounted

## Distance at which a ship's score has halved.
const FALLOFF := 450.0
const POPCORN_BONUS := 0.6
const HARMLESS_WEIGHT := 0.4
const FRIENDLY_WEIGHT := 0.3


## The best ship in [param ships] seen from [param from] looking along
## [param dir], inside a cone of [param cone_cos] (dot product) and
## [param max_range]. Pass [param dir] = ZERO to ignore direction. Null if none.
static func best(ships: Array, from: Vector3, dir: Vector3, cone_cos: float, max_range: float, any_side := false) -> AiShip:
	var winner: AiShip = null
	var top := 0.0
	for ship in ships:
		var s := score(ship as AiShip, from, dir, cone_cos, max_range, any_side)
		if s > top:
			top = s
			winner = ship as AiShip
	return winner


static func score(ship: AiShip, from: Vector3, dir: Vector3, cone_cos: float, max_range: float, any_side := false) -> float:
	if ship == null or not is_instance_valid(ship) or not ship._alive or not ship.is_inside_tree():
		return 0.0
	var hostility := 0.0
	match ship.attitude_to_player():
		AiShip.Attitude.HOSTILE: hostility = 1.0
		AiShip.Attitude.WARY: hostility = 0.5
		AiShip.Attitude.HARMLESS: hostility = HARMLESS_WEIGHT if any_side else 0.0
		AiShip.Attitude.FRIENDLY: hostility = FRIENDLY_WEIGHT if any_side else 0.0
	if hostility <= 0.0:
		return 0.0
	var to := ship.global_position - from
	var dist := to.length()
	if dist > max_range or dist < 0.01:
		return 0.0
	var facing := 1.0
	if dir != Vector3.ZERO:
		var d := (to / dist).dot(dir.normalized())
		if d < cone_cos:
			return 0.0
		# 1 dead ahead, down to 0.3 at the cone's edge.
		facing = lerpf(0.3, 1.0, inverse_lerp(cone_cos, 1.0, d)) if cone_cos < 1.0 else 1.0
	var weakness := 1.0 - clampf(ship.hp / maxf(ship.max_hp, 1.0), 0.0, 1.0)
	if ship.archetype != null and ship.archetype.popcorn:
		weakness += POPCORN_BONUS
	return hostility * (1.0 + weakness) * facing / (1.0 + dist / FALLOFF)


## Where to aim at [param ship] from [param from] (moving at
## [param from_velocity]) with shots of [param shot_speed]: its lead point.
static func aim_point(ship: Node3D, from: Vector3, from_velocity: Vector3, shot_speed: float) -> Vector3:
	var vel := Vector3.ZERO
	var v: Variant = ship.get("velocity")
	if v is Vector3:
		vel = v
	elif ship is AiShip and (ship as AiShip).model != null:
		vel = (ship as AiShip).model.velocity
	return TargetLeadReticle.calculate_lead_position(from, from_velocity, ship.global_position, vel, shot_speed)
