## YeetDash: one AI ship's "yeet" attack — it hurls itself at the player.
##
##     IDLE ──cooldown, in view──▶ WINDUP ──wind-up over──▶ DASH ──hit / overshoot──▶ RECOVER ──braked──▶ IDLE
##
## Only a ship the player can see ([method AiShip.in_player_view]) starts one,
## and only [member JuiceSettings.yeet_max_ships] may be winding up or dashing
## at once, so the attacks come as readable, dodgeable runs rather than a
## swarm. The wind-up shows the same red glow and aim line as a ship about to
## fire ([AiTelegraph]); the dash then owns the hull's velocity ([member
## FlightModel.external_drive]) at [member JuiceSettings.yeet_speed] × its top
## speed along the player's lead point, bending only slightly after them.
##
## Who gets hurt in the clash is [method clash_player_wins]'s rule, applied in
## [method FlightModel._apply_collision_damage]: the player moving into the
## ship faster than it moves into them takes nothing; slower, both take it.
class_name YeetDash
extends RefCounted

enum State { IDLE, WINDUP, DASH, RECOVER }

## Nearest and furthest a ship starts a dash from, metres.
const MIN_RANGE := 40.0
const MAX_RANGE := 1100.0
## Degrees per second a dash still bends after the player (dodgeable).
const HOMING_DEG := 22.0
## Longest a dash lasts, seconds, and how long the brake after it takes.
const MAX_DASH := 2.8
const RECOVER_TIME := 0.6
## Most a dash aims off the straight line to the player to lead them, radians.
const MAX_LEAD := 0.6109  # 35°

## Ships winding up or dashing now, by instance id (shared by every ship).
static var _live := {}

var ship: AiShip
var state := State.IDLE
var _t := 0.0
var _cooldown := 0.0
var _dir := Vector3.ZERO
var _speed := 0.0
var _max_t := MAX_DASH
var _hit := false


func _init(owner_ship: AiShip) -> void:
	ship = owner_ship
	# Stagger the first run, so a squad in view doesn't all go at once.
	_cooldown = randf_range(0.3, 1.0) * JuiceSettings.yeet_interval


## Ships mid-yeet right now (stale entries of freed ships are dropped).
static func live_count() -> int:
	for id: int in _live.keys():
		if not is_instance_id_valid(id):
			_live.erase(id)
	return _live.size()


## The clash rule: along the line between the two hulls, is the player
## ([param player]) closing faster than the AI ship ([param other]) is? Uses
## the velocities each hull carried into this physics step, before the
## collision changed them.
static func clash_player_wins(player: FlightModel, other: FlightModel) -> bool:
	var to := other.global_position - player.global_position
	if to.length_squared() < 1e-4:
		return false
	var dir := to.normalized()
	return player.pre_impact_velocity().dot(dir) >= other.pre_impact_velocity().dot(-dir)


## One tick. Returns true while the dash owns the model's command and
## velocity (the behaviour's output is skipped then).
func tick(delta: float, target: Node3D, target_velocity: Vector3) -> bool:
	var model := ship.model
	match state:
		State.IDLE:
			_cooldown -= delta
			if _cooldown <= 0.0 and _can_start(target):
				_set_live(true)
				state = State.WINDUP
				_t = 0.0
			return false
		State.WINDUP:
			if not _target_ok(target):
				_finish()
				return false
			_t += delta
			var wind := maxf(JuiceSettings.yeet_windup, 0.0)
			ship.show_yeet_charge(target.global_position, _t / maxf(wind, 0.01))
			if _t >= wind:
				_launch(target, target_velocity)
			# The behaviour keeps the nose on the player while it winds up.
			return false
		State.DASH:
			_t += delta
			model.command.throttle = 0.0
			model.command.boost = false
			model.command.roll = 0.0
			if _target_ok(target):
				var want := (target.global_position - ship.global_position).normalized()
				var ang := _dir.angle_to(want)
				var step := deg_to_rad(HOMING_DEG) * delta
				# Only while still coming in: once past, it flies on by.
				if ang < PI * 0.5 and ang > 1e-4:
					_dir = _dir.slerp(want, minf(step / ang, 1.0)).normalized()
			model.velocity = _dir * _speed
			if _hit or _t >= _max_t:
				state = State.RECOVER
				_t = 0.0
				_set_live(false)
			return true
		State.RECOVER:
			_t += delta
			var v := model.velocity
			model.velocity = v.move_toward(Vector3.ZERO, maxf(v.length(), 20.0) * 2.5 * delta)
			if _t >= RECOVER_TIME:
				_finish()
				return false
			return true
	return false


## Stop at once (the ship died, was taken over, or the toggle went off).
func release() -> void:
	if state == State.DASH or state == State.RECOVER:
		ship.model.external_drive = false
	ship.show_yeet_charge(Vector3.ZERO, -1.0)
	_set_live(false)
	state = State.IDLE


func _can_start(target: Node3D) -> bool:
	# Passive enemies (the debugger's toggle) don't attack at all — rams included.
	if not JuiceSettings.yeet_combat or JuiceSettings.enemies_passive or not _target_ok(target):
		return false
	if ship.is_mother or ship.is_satellite or ship.pilot_host != null or not ship.can_attack():
		return false
	# At the player only once it is hostile to them; at another ship, whatever
	# it is already fighting (a scenario's enemies mostly target the wingmen).
	if target == ship.player_ref and ship.attitude_to_player() != AiShip.Attitude.HOSTILE:
		return false
	var d := ship.global_position.distance_to(target.global_position)
	if d < MIN_RANGE or d > MAX_RANGE or not ship.in_player_view():
		return false
	return live_count() < int(JuiceSettings.yeet_max_ships)


## Still the ship's own target — the player's hull or the ship it is
## fighting — alive and in the tree.
func _target_ok(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target != ship.current_target:
		return false
	if target is AiShip:
		return (target as AiShip)._alive
	return true


func _launch(target: Node3D, target_velocity: Vector3) -> void:
	var model := ship.model
	ship.show_yeet_charge(Vector3.ZERO, -1.0)
	# Not slower than the player (up to a point): against a faster target the
	# intercept has no solution and the lead point ran off anywhere — ships
	# dashed away from the player. A player going flat out can still outrun it.
	var base := maxf(model.top_speed, 40.0) * JuiceSettings.yeet_speed
	_speed = clampf(target_velocity.length() * 1.15, base, base * 1.6)
	var lead := TargetLeadReticle.calculate_lead_position(
		ship.global_position, Vector3.ZERO, target.global_position, target_velocity, _speed
	)
	var straight := target.global_position - ship.global_position
	var to := lead - ship.global_position
	_dir = to.normalized() if to.length() > 1.0 else -ship.global_transform.basis.z
	# And the lead only ever leans the dash a little off the straight line.
	if straight.length() > 1.0:
		var direct := straight.normalized()
		var ang := _dir.angle_to(direct)
		if ang > MAX_LEAD:
			_dir = direct.slerp(_dir, MAX_LEAD / ang).normalized()
		to = _dir * straight.length()
	# Long enough to reach the player and carry on past a bit.
	_max_t = clampf(to.length() / _speed * 1.4 + 0.3, 0.5, MAX_DASH)
	_hit = false
	if not model.impacted.is_connected(_on_impacted):
		model.impacted.connect(_on_impacted)
	model.external_drive = true
	model.set_velocity(_dir * _speed)
	state = State.DASH
	_t = 0.0
	# Tell whoever runs the fleet, for the "YEET!" shout.
	var fleet := ship.spawner_ref
	if fleet != null and is_instance_valid(fleet) and fleet.has_signal("ship_yeeted"):
		fleet.emit_signal("ship_yeeted", ship)


func _on_impacted(_other: PhysBody, _normal: Vector3, _closing: float) -> void:
	if state == State.DASH:
		_hit = true


func _finish() -> void:
	ship.model.external_drive = false
	ship.show_yeet_charge(Vector3.ZERO, -1.0)
	_set_live(false)
	state = State.IDLE
	_cooldown = JuiceSettings.yeet_interval * randf_range(0.8, 1.3)


func _set_live(on: bool) -> void:
	var id := ship.get_instance_id()
	if on:
		_live[id] = true
	else:
		_live.erase(id)
