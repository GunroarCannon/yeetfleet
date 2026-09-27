## MovePilot: base for the one-thumb movement profiles ([SwipePilot],
## [SlingshotPilot]). A pilot is a strategy object [FlightRoot] swaps in: it
## gets the bare-screen input first ([method handle_input]), runs once per
## physics tick after the root's own assists ([method physics_tick]) and may
## draw on the HUD's instrument layer ([method draw]).
##
## Every pilot flies whichever ship the player is flying
## ([method FlightRoot.active_model]); when that changes (fly as, respawn) the
## root deactivates and re-activates it.
##
## Camera gestures are shared here: two fingers pinch the view in and out and
## twist or drag it round the ship (mouse wheel and right-drag on PC), and a
## one-finger drag that a profile says is not movement ([method
## _drag_orbits] — one that doesn't start on the ship) swings the view round
## the ship too. A drag that starts on the ship never turns the camera.
class_name MovePilot
extends RefCounted

## Degrees of swing for a drag across the screen's short edge.
const ORBIT_DEG_PER_EDGE := 200.0
## The "on the ship" grab circle: at least this many pixels, at most this share
## of the short edge (before [member JuiceSettings.grab_radius_scale]).
const GRAB_MIN_PX := 40.0
const GRAB_MAX_EDGE := 0.1
## How far the launch magnet looks for a ship, metres.
const MAGNET_RANGE := 1800.0

var root: FlightRoot
var model: FlightModel
var gestures := GestureReader.new()
## The finger down now is swinging the camera, not flying.
var camera_drag := false
var _drag_last := Vector2.ZERO
## The 3D chevron arrows this pilot has laid in the world (made on first use).
var _arrows: Array[ChevronArrow3D] = []

## The profiles' arrow colour (the glowing blue of the reference art).
const ARROW_BLUE := Color(0.22, 0.55, 1.0)


func _init(flight_root: FlightRoot) -> void:
	root = flight_root
	# Connected before any subclass's handlers, so they can read camera_drag.
	gestures.pressed.connect(_base_pressed)
	gestures.dragged.connect(_base_dragged)
	gestures.released.connect(func(_p: Vector2) -> void: camera_drag = false)
	gestures.cancelled.connect(func() -> void: camera_drag = false)
	gestures.two_finger.connect(_on_two_finger)
	gestures.wheel.connect(_on_wheel)
	gestures.alt_dragged.connect(orbit_camera)


## Take over [param flight]. Subclasses call this first.
func activate(flight: FlightModel) -> void:
	model = flight
	model.ram_dealt_mult = JuiceSettings.move_ram_dealt
	model.ram_taken_mult = JuiceSettings.move_ram_taken
	model.durability_mult = JuiceSettings.move_durability


## Give the ship back to normal flight. Subclasses call this last.
func deactivate() -> void:
	gestures.reset()
	camera_drag = false
	if root.camera_rig != null:
		root.camera_rig.reset_user_view()
	for a in _arrows:
		if is_instance_valid(a):
			a.queue_free()
	_arrows.clear()
	root.set_firing(false)
	root.set_boosting(false)
	if model != null and is_instance_valid(model):
		model.external_drive = false
		model.free_spin = false
		model.rocket_spin = false
		model.warp_active = false
		model.ram_dealt_mult = 1.0
		model.ram_taken_mult = 1.0
		model.durability_mult = 1.0
	model = null


## True when the event was used.
func handle_input(event: InputEvent) -> bool:
	return gestures.feed(event)


func physics_tick(_delta: float) -> void:
	pass


## Called every frame (real time), for the gesture hold timers and camera.
func frame_tick(delta: float) -> void:
	# Taps and holds are the player's own timing: slow-mo, a kill cam or the
	# time warp must not stretch or squash them.
	gestures.tick(delta / maxf(Engine.time_scale, 0.05))


func draw(_canvas: Control) -> void:
	pass


# --- Camera gestures ---

## Whether a finger landing at [param pos] swings the camera instead of
## flying. Subclasses decide; the base never does.
func _drag_orbits(_pos: Vector2) -> bool:
	return false


func _base_pressed(pos: Vector2) -> void:
	camera_drag = _drag_orbits(pos) and JuiceSettings.cam_twist_rotate
	_drag_last = pos


func _base_dragged(pos: Vector2, _start: Vector2) -> void:
	if camera_drag:
		orbit_camera(pos - _drag_last)
	_drag_last = pos


## Swing the view round the ship by a screen drag, pixels.
func orbit_camera(relative: Vector2) -> void:
	var rig := root.camera_rig
	if rig == null or not JuiceSettings.cam_twist_rotate:
		return
	var k := ORBIT_DEG_PER_EDGE / short_edge() * JuiceSettings.cam_gesture_speed
	rig.orbit_by(Vector2(-relative.x, relative.y) * k)


func _on_two_finger(scale: float, twist: float, pan: Vector2) -> void:
	var rig := root.camera_rig
	if rig == null:
		return
	if JuiceSettings.cam_pinch_zoom:
		rig.pinch_by(scale)
	if JuiceSettings.cam_twist_rotate:
		orbit_camera(pan)
		rig.orbit_by(Vector2(-rad_to_deg(twist) * JuiceSettings.cam_gesture_speed, 0.0))


func _on_wheel(steps: float) -> void:
	if root.camera_rig != null and JuiceSettings.cam_pinch_zoom:
		root.camera_rig.pinch_by(pow(1.12, steps))


# --- Arrows ---

## The [param i]th world arrow, made and parented to the flight scene on first use.
func arrow(i: int) -> ChevronArrow3D:
	while _arrows.size() <= i:
		var a := ChevronArrow3D.new()
		root.add_child(a)
		_arrows.append(a)
	return _arrows[i]


func hide_arrows() -> void:
	for a in _arrows:
		if is_instance_valid(a):
			a.hide_arrow()


## Lay arrow [param i] out of the ship along [param dir], [param reach]
## (0..1) setting its length. Sized from the hull, so a scout and a titan both
## get an arrow that reads next to them.
func lay_arrow(i: int, dir: Vector3, reach: float, tint: Color, strength := 1.0) -> void:
	var cam := root.camera_node()
	if model == null or cam == null or dir == Vector3.ZERO or not JuiceSettings.move_arrows:
		if i < _arrows.size():
			_arrows[i].hide_arrow()
		return
	var r := 3.0
	var l := 6.0
	if root.camera_rig != null:
		r = root.camera_rig.hull_radius
		l = root.camera_rig.hull_length
	var centre := model.get_global_transform_interpolated().origin
	# Metres per pixel at the ship: the arrow is kept to a readable share of
	# the screen, so a titan's arrow doesn't run off the top of it.
	var mpp := 2.0 * cam.global_position.distance_to(centre) * tan(deg_to_rad(cam.fov) * 0.5) \
		/ maxf(root.get_viewport().get_visible_rect().size.y, 1.0)
	var edge := short_edge() * mpp
	var width := clampf(r * 1.1, edge * 0.035, edge * 0.07)
	var length := clampf(l * (1.5 + 5.0 * clampf(reach, 0.0, 1.0)), edge * 0.12, edge * (0.12 + 0.28 * reach))
	# Pointing into (or out of) the screen it is foreshortened: longer in the
	# world so it still reads on screen, with the perspective showing the depth.
	var across := sqrt(maxf(1.0 - pow(dir.normalized().dot(cam.global_transform.basis.z), 2.0), 0.0))
	length /= maxf(across, 0.45)
	var from := centre + dir * minf(r * 1.3, edge * 0.08)
	arrow(i).place(from, from + dir * length, width, cam, tint, strength)


# --- Launch magnet ---
# A launch (a swipe's dash, a slingshot's flight) bends onto a ship ahead of
# it, and that ship drifts into the path — so a rough flick still connects.

## The ship the magnet is pulling toward this tick, or null.
var magnet_target: AiShip = null


## The magnet's pick ahead of [param dir] from the ship: [TargetPriority]
## inside [member JuiceSettings.magnet_cone_deg], any side when
## [member JuiceSettings.magnet_friendlies] (hostiles still first).
## [param cone_deg] overrides the cone (the slingshot's aim snap is narrower).
func find_magnet(dir: Vector3, cone_deg := -1.0) -> AiShip:
	var cone_w := JuiceSettings.magnet_cone_deg if cone_deg < 0.0 else cone_deg
	if model == null or dir == Vector3.ZERO or JuiceSettings.magnet_strength <= 0.0 or cone_w <= 0.0:
		return null
	var ships: Array = []
	for s in root.live_enemies():
		if s != root.controlled_ai and s.model != model:
			ships.append(s)
	var cone := cos(deg_to_rad(cone_w))
	return TargetPriority.best(ships, model.global_position, dir, cone, MAGNET_RANGE, JuiceSettings.magnet_friendlies)


## Where to fly at [param ship] to meet it at [param speed].
func intercept_point(ship: AiShip, speed: float) -> Vector3:
	return TargetPriority.aim_point(ship, model.global_position, Vector3.ZERO, maxf(speed, 1.0))


## [param dir] (the unit flight direction) turned this tick toward the
## magnet's pick, at up to 30–260°/s by [member JuiceSettings.magnet_strength]
## and harder the closer it is; the pick drifts into the path meanwhile.
## Sets [member magnet_target].
func magnet_bend(dir: Vector3, speed: float, delta: float) -> Vector3:
	magnet_target = find_magnet(dir)
	if magnet_target == null:
		return dir
	var pos := model.global_position
	var aim := intercept_point(magnet_target, speed)
	var to := aim - pos
	var dist := to.length()
	if dist < 1.0:
		return dir
	var want := to / dist
	var near := 1.0 - clampf(dist / MAGNET_RANGE, 0.0, 1.0)
	var rate := deg_to_rad(lerpf(30.0, 260.0, JuiceSettings.magnet_strength)) * (1.0 + 1.5 * near)
	var ang := dir.angle_to(want)
	var out := want
	if ang > rate * delta and ang > 1e-4:
		out = dir.slerp(want, rate * delta / ang).normalized()
	pull_into_path(magnet_target, out, delta)
	return out


## Drift [param ship] toward the closest point ahead on the line the player
## flies along [param dir] ([method AiShip.drift_toward]).
func pull_into_path(ship: AiShip, dir: Vector3, delta: float) -> void:
	if JuiceSettings.magnet_pull <= 0.0 or ship == null or not is_instance_valid(ship):
		return
	var pos := model.global_position
	var along := (ship.global_position - pos).dot(dir)
	if along <= 0.0:
		return
	ship.drift_toward(pos + dir * along, JuiceSettings.magnet_pull, delta)


# --- Helpers ---

## Where the ship is drawn this frame (interpolated), for anything laid over it.
func ship_draw_position() -> Vector3:
	return model.get_global_transform_interpolated().origin

## Radius (px) around the ship's screen position that counts as "on the
## ship": the hull as drawn plus a thumb's margin, kept between
## [constant GRAB_MIN_PX] and [constant GRAB_MAX_EDGE] of the short edge, ×
## [member JuiceSettings.grab_radius_scale]. Small, so a drag meant to look
## around doesn't land on the ship by accident.
func grab_radius() -> float:
	var hull_px := 0.0
	var cam := root.camera_node()
	if cam != null and model != null and root.camera_rig != null:
		var d := cam.global_position.distance_to(model.global_position)
		var mpp := 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) / maxf(root.get_viewport().get_visible_rect().size.y, 1.0)
		hull_px = root.camera_rig.hull_radius / maxf(mpp, 1e-4)
	var r := clampf(hull_px * 1.2 + 22.0, GRAB_MIN_PX, short_edge() * GRAB_MAX_EDGE)
	return r * JuiceSettings.grab_radius_scale


func near_ship(pos: Vector2) -> bool:
	var s := ship_screen_pos()
	return s != Vector2.INF and pos.distance_to(s) <= grab_radius()


## A screen-space launch vector (right/down positive, like input) as a 3D
## direction: sideways is the view's right, and "up the screen" tips from the
## view's up (at [param depth] 0) into the screen, away from the camera (at 1).
## [param frame] is the camera basis to read it in (hold the one from when the
## finger went down, so a moving camera doesn't move the aim).
static func depth_dir(screen_vec: Vector2, frame: Basis, depth: float) -> Vector3:
	if screen_vec.length_squared() < 1e-6:
		return Vector3.ZERO
	var s := screen_vec.normalized()
	var up_screen := frame.y.lerp(-frame.z, clampf(depth, 0.0, 1.0)).normalized()
	return (frame.x * s.x - up_screen * s.y).normalized()


## A screen-space vector (right/down positive, like input) as a world
## direction in the camera's view plane.
func view_dir(screen_vec: Vector2) -> Vector3:
	var cam := root.camera_node()
	if cam == null or screen_vec.length_squared() < 1e-6:
		return Vector3.ZERO
	var b := cam.global_transform.basis
	return (b.x * screen_vec.x - b.y * screen_vec.y).normalized()


## Where the ship is on screen, or Vector2.INF when it is behind the camera.
func ship_screen_pos() -> Vector2:
	var cam := root.camera_node()
	if cam == null or model == null:
		return Vector2.INF
	if cam.is_position_behind(model.global_position):
		return Vector2.INF
	return cam.unproject_position(model.global_position)


## The shorter side of the view, in the same pixels as input positions.
func short_edge() -> float:
	var s := root.get_viewport().get_visible_rect().size
	return maxf(minf(s.x, s.y), 1.0)


## Speed of the active weapon's shots (for lead).
func shot_speed() -> float:
	var sys := root.active_systems()
	if sys != null:
		return float(sys.get_active_weapon().get("speed", 1100.0))
	return 1100.0
