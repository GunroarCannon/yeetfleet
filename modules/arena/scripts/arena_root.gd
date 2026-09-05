## The AI test arena, as its own module scene: a pure spectator platform for
## watching and testing AI combat.
##
## There is no player ship here. A free camera orbits the box (drag to look,
## wheel to zoom, WASD to pan while unfocused); the roster lets you focus a ship
## or take control of one to fly it yourself (L hands it back). The translucent
## box is the AI's bounding box — ships are clamped inside it and bounce off
## the faces, so the fight stays in frame for viewing.
class_name ArenaRoot
extends Node3D

const FLIGHT_SCENE := "res://modules/flight/flight_test.tscn"
const HANGAR_SCENE := "res://modules/ship_builder/ship_builder.tscn"

## How fast the keyboard throttle keys move the lever, per second.
const THROTTLE_KEY_RATE := 0.8

var arena: AiTestArena
var camera_rig: FlightCamera
var _ai_spawner: AiSpawner
var _hud: ArenaHud

## The AI ship the player is currently piloting, or null.
var controlled_ai: AiShip = null

## Whether the "bigger view" restart pulled the camera right out.
static var _big_view := false

var _look_pointer := -1
var _looking := false
var _button_firing := false
var _button_boost := false


## The box, the spawner and the camera are built here rather than in _ready for
## the same reason as [FlightRoot]: the HUD is readied before this node, and
## anything created during _ready has not had its own _ready run by the time the
## HUD asks for it.
func _enter_tree() -> void:
	_build_environment()
	arena = AiTestArena.new()
	arena.name = "Arena"
	add_child(arena)
	_ai_spawner = AiSpawner.new()
	_ai_spawner.name = "AiSpawner"
	# The arena spawns its own team-vs-team squads; no random default fleet.
	_ai_spawner.auto_fleet = false
	add_child(_ai_spawner)
	_build_camera()


func _ready() -> void:
	get_window().theme = BuilderTheme.build()
	BuilderTheme.apply_density_scale(get_window())
	get_viewport().size_changed.connect(
		func() -> void: BuilderTheme.apply_density_scale(get_window())
	)
	_hud = %Hud as ArenaHud
	_spawn_opening_squads()


## The spectator camera: a [FlightCamera] in free-pan TARGET mode centred on the
## box. There is no player ship, so the rig's ship slot gets this node as a
## static stand-in — TARGET mode never reads the ship, and _process needs a
## non-null ship to run at all.
func _build_camera() -> void:
	camera_rig = FlightCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.ship = self
	camera_rig.model = null
	camera_rig.hull_radius = 500.0
	camera_rig.hull_length = 1000.0
	camera_rig.set_mode(FlightCamera.Mode.TARGET)
	camera_rig.set_target_centre(Vector3.ZERO)
	camera_rig.set_focus(null)


## The arena's opening battle: a Red squad and a Blue squad, both hunting.
func _spawn_opening_squads() -> void:
	if _ai_spawner == null:
		return
	_ai_spawner.spawn_group_with(
		AiFactions.custom(AiFactions.Behavior.HUNT, AiGroupBehaviour.FormationShape.V_FORM, 3), 3, 1
	)
	_ai_spawner.spawn_group_with(
		AiFactions.custom(AiFactions.Behavior.HUNT, AiGroupBehaviour.FormationShape.V_FORM, 3), 3, 2
	)
	if _big_view:
		camera_rig.zoom(-10.0)  # pull right out
		_big_view = false
	if _hud != null:
		_hud.show_hint("Red vs Blue — focus a ship or take one over")


# --- Bounding box -------------------------------------------------------------

## Keep every live AI ship inside the box: clamp position and reflect the
## outward velocity component, so a ship that tries to leave bounces off the
## face instead of drifting out into the void. Applies to the controlled ship
## too, which is fine — taking over a ship in the arena still keeps it in view.
func _constrain_to_arena() -> void:
	if _ai_spawner == null:
		return
	var half := AiTestArena.ARENA_HALF
	for ship in _ai_spawner._ships:
		if not is_instance_valid(ship) or not ship._alive or ship.model == null:
			continue
		var m := ship.model
		var p := m.global_position
		var v := m.velocity
		var changed := false
		if p.x > half.x:
			p.x = half.x
			v.x = -absf(v.x) * 0.6
			changed = true
		elif p.x < -half.x:
			p.x = -half.x
			v.x = absf(v.x) * 0.6
			changed = true
		if p.y > half.y:
			p.y = half.y
			v.y = -absf(v.y) * 0.6
			changed = true
		elif p.y < -half.y:
			p.y = -half.y
			v.y = absf(v.y) * 0.6
			changed = true
		if p.z > half.z:
			p.z = half.z
			v.z = -absf(v.z) * 0.6
			changed = true
		elif p.z < -half.z:
			p.z = -half.z
			v.z = absf(v.z) * 0.6
			changed = true
		if changed:
			m.global_position = p
			m.velocity = v


# --- Take control -------------------------------------------------------------

## Take control of an AI ship: its behaviour pauses, the player's inputs move
## it, and the camera rides behind it in chase view.
func take_control(ship: AiShip) -> void:
	if ship == null or not is_instance_valid(ship) or not ship._alive:
		return
	leave_control()
	controlled_ai = ship
	ship._ai_paused = true
	if camera_rig != null:
		camera_rig.adopt(ship, ship.model, ship._view)
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if _hud != null:
		_hud.show_hint("Piloting %s — L to leave control" % ship.preset_name)


## Give control back to the AI and return the camera to the free pan.
func leave_control() -> void:
	if controlled_ai != null and is_instance_valid(controlled_ai):
		controlled_ai._ai_paused = false
	controlled_ai = null
	if camera_rig != null:
		camera_rig.ship = self
		camera_rig.model = null
		camera_rig.set_mode(FlightCamera.Mode.TARGET)
		camera_rig.set_focus(null)
	if _hud != null:
		_hud.show_hint("Back to the free camera")


# --- Per-frame --------------------------------------------------------------

func _process(_delta: float) -> void:
	# If the ship being piloted died, hand control back to the free camera.
	if controlled_ai != null and (not is_instance_valid(controlled_ai) or not controlled_ai._alive):
		leave_control()
	_constrain_to_arena()
	if camera_rig != null and _view_light != null:
		_view_light.global_transform = Transform3D(camera_rig.camera.global_transform.basis, Vector3.ZERO)


func _physics_process(delta: float) -> void:
	if controlled_ai != null:
		_read_keyboard(delta, controlled_ai.model)
	elif camera_rig != null and camera_rig.mode == FlightCamera.Mode.TARGET and camera_rig.focus_node == null:
		_handle_pan(delta)


## WASD slides the free camera's orbit centre around the map (in the camera's
## horizontal plane), so the player can tour the box before picking a ship to
## focus or pilot.
func _handle_pan(delta: float) -> void:
	var cam := camera_rig.camera
	if cam == null:
		return
	var basis := cam.global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right := basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var move := Vector3.ZERO
	move += fwd * (Input.get_action_strength("flight_thrust") - Input.get_action_strength("flight_reverse"))
	move += right * (Input.get_action_strength("flight_roll_right") - Input.get_action_strength("flight_roll_left"))
	camera_rig.pan_world(move * (500.0 * delta))


## Keyboard flying of a controlled AI ship, feeding the same [FlightModel.Command]
## the touch widgets would. WASD on the ground moves the throttle/stick; here the
## full keyboard is the only control surface in the arena.
func _read_keyboard(delta: float, flight: FlightModel) -> void:
	var stick := Vector2(
		Input.get_action_strength("flight_yaw_right") - Input.get_action_strength("flight_yaw_left"),
		Input.get_action_strength("flight_pitch_down") - Input.get_action_strength("flight_pitch_up")
	)
	flight.command.yaw = stick.x
	flight.command.pitch = stick.y
	flight.command.roll = (
		Input.get_action_strength("flight_roll_right")
		- Input.get_action_strength("flight_roll_left")
	)
	var throttle_up := Input.get_action_strength("flight_thrust")
	var throttle_down := Input.get_action_strength("flight_reverse")
	if not is_zero_approx(throttle_up) or not is_zero_approx(throttle_down):
		flight.command.throttle = clampf(
			flight.command.throttle + (throttle_up - throttle_down) * THROTTLE_KEY_RATE * delta,
			ThrottleLever.MIN_VALUE, 1.0
		)
	flight.command.boost = Input.is_action_pressed("flight_boost") or _button_boost
	controlled_ai.systems.set_firing(Input.is_action_pressed("flight_fire") or _button_firing)
	controlled_ai.systems.set_boost(flight.command.boost)
	controlled_ai.systems.set_throttle(clampf(absf(flight.command.throttle), 0.0, 1.0))


# --- Actions -----------------------------------------------------------------

func kill_all() -> void:
	if _ai_spawner != null:
		_ai_spawner.kill_all()
		_hud.show_hint("All AI ships destroyed")


func restart_fight() -> void:
	get_tree().reload_current_scene()


## Restart into the arena with the camera pulled right out — the "bigger view"
## button.
func restart_big() -> void:
	_big_view = true
	restart_fight()


func back_to_flight() -> void:
	get_tree().change_scene_to_file(FLIGHT_SCENE)


func back_to_hangar() -> void:
	get_tree().change_scene_to_file(HANGAR_SCENE)


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				camera_rig.zoom(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			camera_rig.set_looking(_looking)
	elif event is InputEventMouseMotion and _looking:
		camera_rig.look((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _look_pointer < 0:
			_look_pointer = st.index
			camera_rig.set_looking(true)
		elif not st.pressed and st.index == _look_pointer:
			_look_pointer = -1
			camera_rig.set_looking(false)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _look_pointer:
			camera_rig.look(sd.relative)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_L:
			if controlled_ai != null:
				leave_control()
		KEY_F5:
			restart_fight()
		KEY_ESCAPE:
			back_to_flight()


# --- Environment -------------------------------------------------------------

var _view_light: DirectionalLight3D


## Shared empty-box lighting: the same cool ambient and two fixed lights the
## flight test volume uses, plus a weak light aimed down the camera's own axis
## so a hull is never a silhouette against the void from any viewing angle.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.29, 0.35, 0.47)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	add_child(holder)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 2.1
	key.light_color = Color("fff1de")
	key.shadow_enabled = false
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -0.7, -0.45), Vector3.UP)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.45
	fill.light_color = Color("6b86c4")
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.6, 0.45, 0.65), Vector3.UP)
	add_child(fill)

	_view_light = DirectionalLight3D.new()
	_view_light.name = "ViewLight"
	_view_light.light_energy = 0.95
	_view_light.light_color = Color("c8d4e8")
	_view_light.light_specular = 0.25
	_view_light.shadow_enabled = false
	add_child(_view_light)
