## FpsPilot: shooter-style controls on the classic buttons.
##
## - **Stick** (or WASD / arrows): moves the ship relative to where you look —
##   up is forward, sideways strafes. How far it is pushed is how fast it goes
##   (no throttle); pushed to the rim, it boosts.
## - **Bare screen** (hold and drag, or mouse drag): looks around. The camera
##   turns with the look at once and the nose follows, so the guns fire where
##   you look.
## - **Fire / boost / weapon buttons**: as in the classic profile.
class_name FpsPilot
extends MovePilot

## Where the player looks (world, unit).
var look_dir := Vector3.FORWARD
var _look_pointer := -1
var _mouse_look := false
## A touchscreen: ignore the mouse events it emulates.
var _touch_device := false
var _dir_cb := Callable()


func _init(flight_root: FlightRoot) -> void:
	super(flight_root)
	_dir_cb = func() -> Vector3: return look_dir


func activate(flight: FlightModel) -> void:
	super(flight)
	model.external_drive = true
	look_dir = -model.global_transform.basis.z
	if root.camera_rig != null:
		root.camera_rig.follow_dir = _dir_cb
		root.camera_rig.follow_dir_rate = 14.0


func deactivate() -> void:
	_look_pointer = -1
	_mouse_look = false
	super()


## Only the look is read here — the stick and buttons are HUD widgets and take
## their own touches before anything reaches the bare screen.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		_touch_device = true
		var st := event as InputEventScreenTouch
		if st.pressed and _look_pointer == -1:
			_look_pointer = st.index
		elif not st.pressed and st.index == _look_pointer:
			_look_pointer = -1
		return true
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _look_pointer:
			look(sd.relative)
		return true
	if _touch_device:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_mouse_look = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				_on_wheel(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
				return true
		return false
	if event is InputEventMouseMotion and _mouse_look:
		look((event as InputEventMouseMotion).relative)
		return true
	return false


## Turn the look by a screen drag, pixels: about the view's own up and right,
## so it behaves the same whichever way the ship is rolled.
func look(relative: Vector2) -> void:
	var cam := root.camera_node()
	if cam == null:
		return
	var k := deg_to_rad(180.0) / short_edge() * JuiceSettings.fps_look_speed
	var b := cam.global_transform.basis
	var dy := relative.y * (-1.0 if JuiceSettings.fps_invert_y else 1.0)
	look_dir = look_dir.rotated(b.y, -relative.x * k)
	look_dir = look_dir.rotated(b.x, -dy * k).normalized()


## Movement wanted this tick, screen axes (right/down positive), 0..1 long.
func move_input() -> Vector2:
	var keys := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	return (root.touch_stick() + keys).limit_length(1.0)


func physics_tick(delta: float) -> void:
	if model == null:
		return
	var cam := root.camera_node()
	var m := move_input()
	var push := m.length()
	var right := look_dir.cross(Vector3.UP)
	if cam != null:
		right = cam.global_transform.basis.x
	var wish := look_dir * -m.y + right * m.x
	# The boost button still works; a stick pushed to the rim boosts too.
	var boosting := model.command.boost or push >= JuiceSettings.fps_boost_at
	model.command.boost = boosting
	var top := model.top_speed * JuiceSettings.fps_speed_mult
	if boosting:
		top *= FlightModel.BOOST_SPEED
	var goal := wish.normalized() * top * push if push > 0.02 else Vector3.ZERO
	var step := maxf(top, 1.0) * JuiceSettings.fps_accel * delta
	model.velocity = model.velocity.move_toward(goal, step)
	model.command.throttle = push
	root.steer_nose_toward(look_dir)


func frame_tick(delta: float) -> void:
	super(delta)
	if root.camera_rig != null:
		root.camera_rig.profile_distance = 1.0 + JuiceSettings.fps_cam_zoom
