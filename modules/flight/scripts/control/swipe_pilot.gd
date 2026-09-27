## SwipePilot: the one-swipe movement profile.
##
## - **Swipe** anywhere: the flight path swings (fast, not instantly) to the
##   swiped direction in the camera's view plane and the ship dashes. A longer,
##   quicker swipe dashes harder; the dash then bleeds off to a cruise speed and
##   the ship keeps that heading until the next swipe.
## - **Tap**: a short volley at the course-corrected target.
## - **Hold**: boost; keep holding and it warps.
## - **Course correction**: inside a cone around the swipe, the heading bends
##   onto the best target ([TargetPriority]: hostile, weak, close), so a flick
##   toward a crowd rams the ship that is about to die. The launch magnet
##   ([method MovePilot.magnet_bend]'s dials) widens it to any ship and drifts
##   the pick into the path.
##
## The ship is faster and tougher in a ram than on the stick (the
## "Movement: swipe" dials in the Juice panel).
class_name SwipePilot
extends MovePilot

## Seconds of fire per tap.
const VOLLEY_TIME := 0.45
## Tap fire looks this wide around the heading (dot product ≈ 60°).
const FIRE_CONE_COS := 0.5
const FIRE_RANGE := 1800.0
const ASSIST_RANGE := 1500.0

## The swiped flight direction (world).
var heading := Vector3.ZERO
## The heading bent by course correction, what the ship is actually turning to.
var steer_dir := Vector3.ZERO
## The ship course correction is bending toward, or null.
var assist_target: AiShip = null
## Current speed goal along the path (a dash decays from here to cruise).
var _speed := 0.0
var _fire_time := 0.0
var _boosting := false
## 1 just after a swipe, fading: how bright the heading arrow still is.
var _heading_glow := 0.0


func _init(flight_root: FlightRoot) -> void:
	super(flight_root)
	gestures.swipe.connect(_on_swipe)
	gestures.tap.connect(_on_tap)
	gestures.hold_started.connect(func(_p: Vector2) -> void: _set_boost(true))
	gestures.hold_long.connect(func(_p: Vector2) -> void:
		if model != null:
			model.warp_active = true
	)
	gestures.hold_ended.connect(func(_p: Vector2) -> void: _set_boost(false))


func activate(flight: FlightModel) -> void:
	super(flight)
	model.external_drive = true
	model.command.throttle = 0.0
	var v := model.velocity
	heading = v.normalized() if v.length() > 5.0 else -model.global_transform.basis.z
	steer_dir = heading
	_speed = maxf(v.length(), _cruise())
	model.impacted.connect(_on_impacted)


func deactivate() -> void:
	_set_boost(false)
	if model != null and is_instance_valid(model) and model.impacted.is_connected(_on_impacted):
		model.impacted.disconnect(_on_impacted)
	super()


## A ram knocks the dash out of the ship; the path swings back from wherever
## the hit sent it.
func _on_impacted(_other: PhysBody, _normal: Vector3, _closing: float) -> void:
	_speed = maxf(_speed * 0.55, _cruise() * 0.6)


## Top speed for this profile (m/s).
func base_speed() -> float:
	return model.top_speed * JuiceSettings.swipe_speed_mult


func _cruise() -> float:
	var c := base_speed() * JuiceSettings.swipe_cruise
	if _boosting:
		c = maxf(c, base_speed() * FlightModel.BOOST_SPEED)
	if model.warp_active:
		c = maxf(c, base_speed() * FlightModel.WARP_SPEED_MULT * 0.5)
	return c


## With [member JuiceSettings.swipe_from_ship], a drag that doesn't start on
## the ship swings the camera instead of flying.
func _drag_orbits(pos: Vector2) -> bool:
	return JuiceSettings.swipe_from_ship and not near_ship(pos)


func _on_swipe(start: Vector2, end: Vector2, seconds: float) -> void:
	if model == null or camera_drag:
		return
	var d := end - start
	var dir := view_dir(d)
	if dir == Vector3.ZERO:
		return
	heading = dir
	# How hard: half length (how far across the screen), half flick speed.
	var reach := clampf(d.length() / (short_edge() * 0.5), 0.0, 1.0)
	var flick := clampf(d.length() / seconds / (short_edge() * 4.0), 0.0, 1.0)
	var strength := reach * 0.5 + flick * 0.5
	var dash := lerpf(_cruise(), base_speed() * JuiceSettings.swipe_dash, strength)
	_speed = maxf(dash, _cruise())
	_heading_glow = 1.0


func _on_tap(_pos: Vector2) -> void:
	if model == null:
		return
	var from := model.global_position
	var look := steer_dir if steer_dir != Vector3.ZERO else -model.global_transform.basis.z
	var target := assist_target
	# Never a volley at a friend the magnet happens to be steering toward.
	if target == null or not is_instance_valid(target) or not target._alive 			or TargetPriority.score(target, from, Vector3.ZERO, -1.0, INF) <= 0.0:
		target = TargetPriority.best(root.live_enemies(), from, look, FIRE_CONE_COS, FIRE_RANGE)
	if target != null:
		root.locked_target = target
	_fire_time = VOLLEY_TIME


func _set_boost(on: bool) -> void:
	_boosting = on
	root.set_boosting(on)
	if not on and model != null:
		model.warp_active = false


func physics_tick(delta: float) -> void:
	if model == null:
		return
	var pos := model.global_position
	model.command.throttle = 0.0
	model.command.roll = 0.0

	# Course correction: bend the heading onto the best target near it.
	steer_dir = heading
	assist_target = null
	var cone := cos(deg_to_rad(JuiceSettings.swipe_assist_cone_deg))
	magnet_target = find_magnet(heading)
	if magnet_target != null:
		# The launch magnet: wider and harder than the old correction, any
		# side, and the pick drifts into the path.
		assist_target = magnet_target
		var to_aim := (intercept_point(magnet_target, _speed) - pos).normalized()
		steer_dir = heading.slerp(to_aim, JuiceSettings.magnet_strength).normalized()
		pull_into_path(magnet_target, steer_dir, delta)
	elif JuiceSettings.swipe_assist_strength > 0.0 and JuiceSettings.swipe_assist_cone_deg > 0.0:
		assist_target = TargetPriority.best(root.live_enemies(), pos, heading, cone, ASSIST_RANGE)
		if assist_target != null:
			var aim := TargetPriority.aim_point(assist_target, pos, model.velocity, maxf(_speed, 1.0))
			var to_aim := (aim - pos).normalized()
			steer_dir = heading.slerp(to_aim, JuiceSettings.swipe_assist_strength).normalized()

	# Swing the flight path toward the steer direction at a bounded rate.
	var v := model.velocity
	var cur := v.normalized() if v.length() > 1.0 else steer_dir
	var angle := cur.angle_to(steer_dir)
	var max_step := JuiceSettings.swipe_turn_rate * delta
	var new_dir := steer_dir
	if angle > max_step and angle > 1e-4:
		new_dir = cur.slerp(steer_dir, max_step / angle).normalized()

	# The dash bleeds off toward cruise (and a slow ship picks up to it).
	var cruise := _cruise()
	_speed = cruise + (_speed - cruise) * exp(-JuiceSettings.swipe_drag * delta)
	model.velocity = new_dir * _speed

	# The nose follows the path, or the target while a volley is out.
	var firing := _fire_time > 0.0
	if firing:
		_fire_time -= delta
		var t := root.locked_target
		if t != null and is_instance_valid(t):
			root.steer_nose_toward(TargetPriority.aim_point(t, pos, model.velocity, shot_speed()) - pos)
		else:
			root.steer_nose_toward(new_dir)
	else:
		root.steer_nose_toward(new_dir)
	root.set_firing(firing)


func frame_tick(delta: float) -> void:
	super(delta)
	if root.camera_rig != null:
		root.camera_rig.profile_distance = 1.0 + JuiceSettings.swipe_cam_zoom
	_heading_glow = move_toward(_heading_glow, 0.0, delta / 1.4)
	if model == null:
		return
	# While swiping from the ship: where it will go, longer for a longer swipe.
	var a := gestures.start_position()
	var b := gestures.current_position()
	if gestures.is_down() and not camera_drag and a.distance_to(b) > gestures.move_threshold:
		var reach := clampf(a.distance_to(b) / (short_edge() * 0.5), 0.0, 1.0)
		lay_arrow(0, view_dir(b - a), reach, ARROW_BLUE, 1.0)
	elif _heading_glow > 0.0 and steer_dir != Vector3.ZERO:
		# After it: the path the ship is on (bent onto its target), fading out.
		var reach := clampf(_speed / maxf(base_speed() * JuiceSettings.swipe_dash, 1.0), 0.0, 1.0)
		lay_arrow(0, steer_dir, reach, ARROW_BLUE, _heading_glow * 0.8)
	else:
		hide_arrows()


func draw(canvas: Control) -> void:
	# The live swipe: a line from where the finger landed (a dot under the
	# thumb when the 3D arrow shows the way).
	if not gestures.is_down() or camera_drag:
		return
	var a := gestures.start_position()
	var b := gestures.current_position()
	if a.distance_to(b) > gestures.move_threshold:
		if not JuiceSettings.move_arrows:
			canvas.draw_line(a, b, Color(0.5, 0.95, 1.0, 0.55), 4.0, true)
		canvas.draw_circle(b, 7.0, Color(0.5, 0.95, 1.0, 0.7))
