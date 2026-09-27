## SlingRun: one ship's slingshot cycle, shared by the player's
## [SlingshotPilot] and an AI ship that fights by launches.
##
##     READY ──launch()──▶ FLYING ──slow / timeout / catch──▶ RECALLING ──stopped──▶ READY
##       ▲                    │
##       └──── in orbit ──────┘   (orbit ends the run; the ship keeps orbiting)
##
## (AIMING is the player's pull-back, owned by [SlingshotPilot]; the run only
## needs to know it is not flying.)
##
## While FLYING the hull spins freely ([member FlightModel.free_spin]), its
## velocity is its own ([member FlightModel.external_drive]) and everything it
## hits sends it off again: the reflection off what it hit, turned toward the
## next body to hit ([member seek]) by [member JuiceSettings.sling_bounce_seek],
## plus a little jitter. Ramming damage is the flight model's own, scaled by
## its [member FlightModel.ram_dealt_mult].
class_name SlingRun
extends RefCounted

signal launched(dir: Vector3, speed: float)
signal bounced(at: Vector3)
## The run is over (the ship is braking, or it went into orbit).
signal ended(in_orbit: bool)
signal state_changed(state: int)

enum State { READY, AIMING, FLYING, RECALLING }

## How bouncy a launched hull is, whatever the physics profile says.
const FLIGHT_RESTITUTION := 0.9
## Jitter on each bounce, radians either way.
const BOUNCE_JITTER := 0.26
## How far a bounce looks for its next body, metres.
const SEEK_RANGE := 1600.0
## Braking after a run (per second, fraction of speed) and after a catch.
const RECALL_BRAKE := 3.0
const CATCH_BRAKE := 9.0

var model: FlightModel
var state := State.READY
## Speed of the hull the numbers are scaled by (m/s) — its top speed at launch.
var speed_ref := 240.0
## Optional: (from: Vector3, just_hit: Node3D) -> Vector3, the point the next
## bounce should head for, or Vector3.INF for "none, use the nearest body".
var seek := Callable()
## Seconds into the current flight.
var flight_time := 0.0
var bounces := 0

var _brake := RECALL_BRAKE
var _rng := RandomNumberGenerator.new()


func _init(flight_model: FlightModel) -> void:
	model = flight_model
	_rng.randomize()
	model.impacted.connect(_on_impacted)
	model.orbit_changed.connect(_on_orbit_changed)


## Throw the ship along [param dir] at [param power] (0..1 of a full pull).
func launch(dir: Vector3, power: float) -> void:
	if dir.length_squared() < 1e-6:
		return
	speed_ref = maxf(model.top_speed, 40.0)
	var speed := clampf(power, 0.05, 1.0) * JuiceSettings.sling_power * speed_ref
	model.external_drive = true
	model.command.throttle = 0.0
	model.command.boost = false
	model.free_spin = true
	model.rocket_spin = JuiceSettings.sling_rocket_spin
	model.rocket_roll_rate = JuiceSettings.sling_spin * (1.0 if _rng.randf() < 0.5 else -1.0)
	if not model.rocket_spin:
		model.apply_impact_spin(_random_axis() * JuiceSettings.sling_spin * clampf(power, 0.3, 1.0))
	var body := model.phys_body()
	if body != null:
		body.restitution_override = FLIGHT_RESTITUTION
	model.set_velocity(dir.normalized() * speed)
	flight_time = 0.0
	bounces = 0
	_set_state(State.FLYING)
	launched.emit(dir.normalized(), speed)


## Grab the flying ship: it brakes hard and the run ends.
func catch_ship() -> void:
	if state == State.FLYING:
		_brake = CATCH_BRAKE
		_end(false)


func set_aiming(on: bool) -> void:
	if on and state == State.READY:
		_set_state(State.AIMING)
	elif not on and state == State.AIMING:
		_set_state(State.READY)


## Hand the ship back to its normal flight (profile switched off).
func release() -> void:
	model.external_drive = false
	model.free_spin = false
	model.rocket_spin = false
	var body := model.phys_body()
	if body != null:
		body.restitution_override = -1.0
	_set_state(State.READY)


## 0..1: how fast the ship is going against its launch scale — the camera
## pulls out by this.
func speed_fraction() -> float:
	if state != State.FLYING:
		return 0.0
	return clampf(model.velocity.length() / maxf(JuiceSettings.sling_power * speed_ref, 1.0), 0.0, 1.0)


func tick(delta: float) -> void:
	match state:
		State.FLYING:
			flight_time += delta
			model.command.throttle = 0.0
			var v := model.velocity
			if JuiceSettings.sling_drag > 0.0:
				model.velocity = v * clampf(1.0 - JuiceSettings.sling_drag * delta, 0.0, 1.0)
			var slow := model.velocity.length() < JuiceSettings.sling_end_speed * speed_ref
			if slow or flight_time >= JuiceSettings.sling_max_time:
				_brake = RECALL_BRAKE
				_end(false)
		State.RECALLING:
			var v := model.velocity
			var step := maxf(v.length(), 20.0) * _brake * delta
			model.velocity = v.move_toward(Vector3.ZERO, step)
			if model.velocity.length() < 2.0:
				model.set_velocity(Vector3.ZERO)
				model.external_drive = false
				_set_state(State.READY)


# --- Internals ---

func _end(in_orbit: bool) -> void:
	model.free_spin = false
	model.rocket_spin = false
	var body := model.phys_body()
	if body != null:
		body.restitution_override = -1.0
	if in_orbit:
		# Leave it on its orbit: normal flight, throttle at zero, coasting.
		model.external_drive = false
		_set_state(State.READY)
	else:
		_set_state(State.RECALLING)
	ended.emit(in_orbit)


func _on_orbit_changed(_body_name: String, in_orbit: bool) -> void:
	if in_orbit and state == State.FLYING:
		_end(true)


func _on_impacted(other: PhysBody, normal: Vector3, closing: float) -> void:
	if state != State.FLYING:
		return
	var pos := model.global_position
	var hit_node: Node3D = other.node if other != null else null
	# The normal pointing away from what was hit.
	var n := normal.normalized()
	if hit_node != null and is_instance_valid(hit_node):
		var away := pos - hit_node.global_position
		if away.length_squared() > 1e-6:
			n = away.normalized()
	var v_in := model.velocity
	var speed := maxf(v_in.length(), closing) * JuiceSettings.sling_bounce_keep
	var dir := v_in.bounce(n).normalized() if v_in.dot(n) < 0.0 else v_in.normalized()
	if dir.length_squared() < 1e-6:
		dir = n
	var goal := _seek_point(pos, hit_node)
	if goal != Vector3.INF:
		var to_goal := (goal - pos).normalized()
		# Only toward something on the open side — never back through the wall.
		if to_goal.dot(n) > -0.1:
			dir = dir.slerp(to_goal, JuiceSettings.sling_bounce_seek).normalized()
	dir = dir.rotated(_random_axis(), _rng.randf_range(-BOUNCE_JITTER, BOUNCE_JITTER)).normalized()
	if dir.dot(n) < 0.0:
		dir = (dir - n * dir.dot(n) * 2.0).normalized()
	model.set_velocity(dir * speed)
	if not model.rocket_spin:
		model.apply_impact_spin(_random_axis() * JuiceSettings.sling_spin * 0.5)
	bounces += 1
	bounced.emit(pos)


func _seek_point(from: Vector3, just_hit: Node3D) -> Vector3:
	if seek.is_valid():
		var p: Variant = seek.call(from, just_hit)
		if p is Vector3 and p != Vector3.INF:
			return p
	# The nearest other solid thing in the physics world.
	if model.phys_world == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := SEEK_RANGE * SEEK_RANGE
	var mine := model.phys_body()
	for b in model.phys_world.bodies:
		if b == mine or b.node == null or not is_instance_valid(b.node) or b.node == just_hit:
			continue
		if b.layer == PhysBody.Layer.DEBRIS or b.layer == PhysBody.Layer.PICKUP:
			continue
		var d := from.distance_squared_to(b.node.global_position)
		if d < best_d:
			best_d = d
			best = b.node.global_position
	return best


func _random_axis() -> Vector3:
	var a := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	return a.normalized() if a.length_squared() > 1e-4 else Vector3.UP


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
