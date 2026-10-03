## SlingshotPilot: the pull-back-and-let-go movement profile.
##
## Put a thumb on the ship and drag back: the ship is aimed the opposite way,
## harder the further you pull. The aim is 3D: pulling down throws it into the
## screen (away from the camera, [member JuiceSettings.sling_aim_depth]),
## sideways throws it left or right, and it snaps onto a ship close to the aim
## line. How the pull becomes a launch is [member JuiceSettings.sling_aim_style]:
## classic (straight opposite on the screen), dome (the pull wraps round the
## half-sphere facing the camera, so pulling back throws it forward — see
## [method dome_dir]) or smart (the dome, and it locks onto what you pull
## toward and adds the power to reach it). Let go and it launches — the hull tumbles (or flies like a rocket),
## the launch magnet bends it onto a ship ahead ([method MovePilot.magnet_bend])
## and it ping-pongs off whatever it hits, each bounce turned toward the next
## body ([SlingRun]). It can be caught by a planet's orbit. When it slows down
## or runs out of time it brakes and it is ready again.
##
## The camera: while pulling it stays where it is and turns to look along
## the aim — where the launch will throw the ship ([member
## JuiceSettings.sling_aim_look]) — easing out a step ([member
## JuiceSettings.sling_aim_zoom]). It used to swing round behind the ship
## instead, which moved the whole view to where the ship would go rather than
## looking there. A second finger during the pull looks around by hand
## ([signal GestureReader.look_dragged]); from then until the pull ends the
## camera leaves the view alone. Let go and it resets: a launch hands it to
## the flight framing below; a pull let go without a launch goes back to how
## it was before the touch. At rest (the start, after a fling) it sits
## [member JuiceSettings.sling_rest_distance] out. The pull is read in the camera's frame from when the thumb
## went down and measured from where the ship was on screen then, so the swing
## never moves the aim under a still thumb; the band and rings are still drawn
## from where the ship is drawn now. Launched, it keeps looking along the
## launch ([member JuiceSettings.sling_cam_hold_launch]) — no re-framing on
## magnet picks or bounces — and pulls out with speed; as the ship slows or
## nears another ship it eases back in ([member JuiceSettings.sling_close_zoom]).
## The aim also snaps onto an objective (a ring, a drop point) near the line.
##
## A tap off the ship shoots: at a ship near the tap, else (auto-aim, [member
## JuiceSettings.sling_tap_auto_aim]) at the best target on screen — in flight
## and, with auto-aim, while resting between launches. In flight the guns can
## also fire on their own at whatever the launch is heading for — one volley
## per launch by default, or the whole flight ([member
## JuiceSettings.sling_auto_shoot]) — and a thumb on the ship catches it for the
## next launch. All toggles.
class_name SlingshotPilot
extends MovePilot

## Seconds of fire per tap.
const VOLLEY_TIME := 0.35
## A tap within this many pixels of a ship shoots that ship.
const TAP_MAGNET_PX := 90.0
## The aim snaps onto a ship within this many degrees of the aim line.
const AIM_SNAP_DEG := 12.0
## Auto-aim taps pick from on-screen ships within this range, m.
const TAP_AIM_RANGE := 1500.0
## Auto-fire in flight: targets within this range and cone (dot) of the flight.
const AUTO_FIRE_RANGE := 900.0
const AUTO_FIRE_CONE_COS := 0.5
## Once the pull is past this, the camera swings behind the ship along the aim.
const AIM_CAM_POWER := 0.12
## The aim snaps onto an objective point within this many degrees of the line.
const GOAL_SNAP_DEG := 22.0
## How far a snap bends the aim onto its ship or goal (1 = all the way). At
## 0.85 a pull could launch well off the line it was pulled along.
const AIM_SNAP_BEND := 0.55
## Dome aim: how far every pull leans round toward the camera at full
## [member JuiceSettings.sling_aim_depth] (so sideways and up launches tip into
## the screen too — a dome, not its flat rim).
const DOME_LEAN := 0.55
## Smart aim: the wider snap cones and the harder bend onto the pick.
const SMART_SNAP_DEG := 28.0
const SMART_GOAL_DEG := 38.0
const SMART_SNAP_BEND := 0.9
## The aim favours enemies: it snaps onto one this much wider than onto a
## friend (a wingman, the guarded ship), which only wins inside the plain cone.
const ENEMY_SNAP_MULT := 2.0
## Smart aim: a launch at a pick carries this × the distance, so it arrives
## with speed to spare instead of drifting to a stop just short.
const SMART_REACH_MARGIN := 1.3

var run: SlingRun = null
## Finger → ship screen offset while aiming (pixels), and the launch it gives.
var pull := Vector2.ZERO
var aim_dir := Vector3.ZERO
## A pull shorter than this share of a full one cancels the sling on release.
const CANCEL_PULL := 0.3
var aim_power := 0.0
## A finger that caught the flying ship: it turns into the next aim once the
## ship has stopped.
var _catching := false
var _fire_time := 0.0
## The camera's frame when the aim began: the pull is read in it, so the view
## easing out and looking ahead doesn't move the aim under the thumb.
var _aim_frame := Basis()
## The camera's line of sight through the ship when the aim began.
var _aim_ray := Vector3.ZERO
## The direction of the last launch: the camera holds it while the ship flies.
var _launch_dir := Vector3.ZERO
## Where the ship was on screen at touch-down: the aim is measured from here.
## Measured from the live ship instead, the view swinging round shifted the
## ship under a still thumb and moved the aim (the check caught 35°).
var _aim_anchor := Vector2.INF
## The thumb, for drawing the band from the ship as drawn now.
var finger := Vector2.ZERO
## The ship the aim has snapped onto, or null.
var aim_target: AiShip = null
## Auto-shoot volleys this launch may still fire ([member
## JuiceSettings.sling_auto_shoot] 1: one per launch).
var _auto_volleys := 0
## The flight direction the camera follows (see [member FlightCamera.follow_dir]).
var _dir_cb := Callable()
## The aim the camera locked onto this pull (ZERO until the pull gets going),
## and the look-ahead it framed then: the one camera move of the pull.
var _cam_lock := Vector3.ZERO
var _cam_ahead := Vector3.INF
## Where the camera looked when the thumb went down: a pull let go without
## a launch swings back here. ZERO after a launch (the flight owns it).
var _rest_dir := Vector3.ZERO
## The player looked around by hand during this pull: the camera stays as
## they left it until the pull ends.
var _looked := false


func _init(flight_root: FlightRoot) -> void:
	super(flight_root)
	gestures.pressed.connect(_on_pressed)
	gestures.dragged.connect(_on_dragged)
	gestures.released.connect(_on_released)
	gestures.tap.connect(_on_tap)
	gestures.look_dragged.connect(_on_look_drag)
	gestures.alt_dragged.connect(func(_r: Vector2) -> void: _note_look())
	_dir_cb = _flight_dir


func activate(flight: FlightModel) -> void:
	super(flight)
	run = SlingRun.new(flight)
	run.seek = _seek
	model.command.throttle = 0.0


func deactivate() -> void:
	if run != null:
		run.release()
		if model != null and is_instance_valid(model):
			if model.impacted.is_connected(run._on_impacted):
				model.impacted.disconnect(run._on_impacted)
			if model.orbit_changed.is_connected(run._on_orbit_changed):
				model.orbit_changed.disconnect(run._on_orbit_changed)
	run = null
	if root.camera_rig != null:
		root.camera_rig.hold_zoom(0.0)
	aim_target = null
	var sys := root.active_systems()
	if sys != null:
		sys.aim_override = Vector3.INF
	super()


## Off the ship, a drag swings the camera (a tap there still shoots).
func _drag_orbits(pos: Vector2) -> bool:
	return not near_ship(pos)


func _on_pressed(pos: Vector2) -> void:
	if run == null:
		return
	match run.state:
		SlingRun.State.READY:
			if near_ship(pos):
				_begin_aim()
				_update_aim(pos)
		SlingRun.State.FLYING, SlingRun.State.RECALLING:
			if JuiceSettings.sling_catch and near_ship(pos):
				run.catch_ship()
				_catching = true


func _on_dragged(pos: Vector2, _start: Vector2) -> void:
	if run != null and run.state == SlingRun.State.AIMING:
		_update_aim(pos)


## A second finger while pulling: look around, and hand the view to the player
## for the rest of the pull.
func _on_look_drag(relative: Vector2) -> void:
	orbit_camera(relative)
	_note_look()


func _note_look() -> void:
	if run != null and run.state == SlingRun.State.AIMING:
		_looked = true


func _begin_aim() -> void:
	run.set_aiming(true)
	_looked = false
	var cam := root.camera_node()
	_aim_frame = cam.global_transform.basis.orthonormalized() if cam != null else Basis()
	_aim_anchor = ship_screen_pos()
	# The line of sight through the ship, for "into the screen" (see
	# [method MovePilot.depth_dir]): held with the frame for the whole pull.
	_aim_ray = cam.project_ray_normal(_aim_anchor) if cam != null and _aim_anchor != Vector2.INF else Vector3.ZERO
	_cam_lock = Vector3.ZERO
	_cam_ahead = Vector3.INF
	_rest_dir = -_aim_frame.z


func _update_aim(at: Vector2) -> void:
	finger = at
	var s := _aim_anchor if _aim_anchor != Vector2.INF else ship_screen_pos()
	if s == Vector2.INF:
		return
	pull = at - s
	var style := roundi(JuiceSettings.sling_aim_style)
	var smart := style >= 2
	if style == 0:
		aim_dir = MovePilot.depth_dir(-pull, _aim_frame, JuiceSettings.sling_aim_depth, _aim_ray)
	else:
		aim_dir = dome_dir(pull, _aim_frame, JuiceSettings.sling_aim_depth, _aim_ray)
	aim_power = clampf(pull.length() / (short_edge() * 0.38), 0.0, 1.0)
	var bend := SMART_SNAP_BEND if smart else AIM_SNAP_BEND
	# Snap onto a ship close to the aim line: a 3D aim doesn't have to be exact.
	var snap_deg := SMART_SNAP_DEG if smart else AIM_SNAP_DEG
	aim_target = null
	if aim_dir != Vector3.ZERO:
		aim_target = find_magnet(aim_dir, snap_deg * ENEMY_SNAP_MULT, true)
		if aim_target == null:
			aim_target = find_magnet(aim_dir, snap_deg)
	if aim_target != null:
		var speed := clampf(aim_power, 0.05, 1.0) * JuiceSettings.sling_power * maxf(model.top_speed, 40.0)
		var hit := intercept_point(aim_target, speed)
		if smart and aim_power > 0.08:
			# Enough power to get there, then re-lead at the new speed.
			aim_power = maxf(aim_power, _reach_power(hit))
			speed = aim_power * JuiceSettings.sling_power * maxf(model.top_speed, 40.0)
			hit = intercept_point(aim_target, speed)
		# Bent toward it, not onto it: the launch still reads as the pull.
		aim_dir = aim_dir.slerp((hit - model.global_position).normalized(), bend).normalized()
	elif aim_dir != Vector3.ZERO:
		# No ship on the line: snap onto an objective (the next ring, a drop
		# point) near it instead.
		var goal := _goal_near(aim_dir, SMART_GOAL_DEG if smart else GOAL_SNAP_DEG)
		if goal != Vector3.INF:
			aim_dir = aim_dir.slerp((goal - model.global_position).normalized(), bend).normalized()
			if smart and aim_power > 0.08:
				aim_power = maxf(aim_power, _reach_power(goal))
	# The one camera move of this pull: locked the first time it gets going.
	if _cam_lock == Vector3.ZERO and aim_power > AIM_CAM_POWER and aim_dir != Vector3.ZERO:
		_cam_lock = aim_dir


## The dome aim ([member JuiceSettings.sling_aim_style] 1 and 2): the pulled-
## back band sits on the half-sphere round the ship that faces the camera, and
## the launch goes out the far side through the ship. [param pull_vec] is the
## finger's screen offset from the ship (right/down positive). Pulling down
## wraps round toward the camera, so a pull back throws the ship forward — into
## the screen along [param ray], the line of sight through the ship — not up;
## pulling up goes over the top and throws it down; sideways stays sideways,
## and every pull leans [param depth] × [constant DOME_LEAN] toward the camera.
static func dome_dir(pull_vec: Vector2, frame: Basis, depth: float, ray := Vector3.ZERO) -> Vector3:
	if pull_vec.length_squared() < 1e-6:
		return Vector3.ZERO
	var u := pull_vec.normalized()
	var toward_cam := -ray.normalized() if ray != Vector3.ZERO else frame.z
	var lean := clampf(depth, 0.0, 1.0) * DOME_LEAN
	var band := frame.x * u.x + frame.y * maxf(-u.y, 0.0) + toward_cam * (maxf(u.y, 0.0) + lean)
	return -band.normalized()


## Smart aim: the pull (0–1) that carries the ship to [param point] before the
## run ends — drag, the end speed and the time limit all counted.
func _reach_power(point: Vector3) -> float:
	var d := point.distance_to(model.global_position) * SMART_REACH_MARGIN
	var ref := maxf(model.top_speed, 40.0)
	var t := maxf(JuiceSettings.sling_max_time, 0.1)
	var k := JuiceSettings.sling_drag
	var v := d / t
	if k > 0.0:
		# v·e^(−kt) decays: it covers (v − v_end)/k before the end speed, and
		# v(1 − e^(−kT))/k before the time runs out.
		v = maxf(d * k + JuiceSettings.sling_end_speed * ref, d * k / maxf(1.0 - exp(-k * t), 1e-3))
	return clampf(v / maxf(JuiceSettings.sling_power * ref, 1.0), 0.0, 1.0)


## The objective point closest to the line along [param dir] within
## [param cone_deg], or Vector3.INF.
func _goal_near(dir: Vector3, cone_deg: float) -> Vector3:
	if root.scenarios == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_ang := deg_to_rad(cone_deg)
	for p: Vector3 in root.scenarios.objective_points():
		var to := p - model.global_position
		if to.length() < 1.0:
			continue
		var ang := dir.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = p
	return best


func _on_released(_pos: Vector2) -> void:
	_catching = false
	_looked = false
	if run == null or run.state != SlingRun.State.AIMING:
		return
	# A feeble pull (under a third of a full one) is a let-go, not a launch: they
	# most likely meant to cancel it.
	var raw_pull := pull.length() / (short_edge() * 0.38)
	if aim_power >= CANCEL_PULL and raw_pull >= CANCEL_PULL and aim_dir != Vector3.ZERO:
		run.launch(aim_dir, aim_power)
		_auto_volleys = 1
		_launch_dir = aim_dir
		# Launched: the flight framing takes over from the aim.
		_rest_dir = Vector3.ZERO
		root.tutorial_note("launch")
		if aim_power > 0.35:
			GameAudio.ui(&"launch", 0.1)
	else:
		# Let go without a launch: the camera goes back to where it was.
		run.set_aiming(false)
	_cam_lock = Vector3.ZERO
	_cam_ahead = Vector3.INF
	pull = Vector2.ZERO
	aim_power = 0.0
	aim_target = null


func _on_tap(pos: Vector2) -> void:
	if run == null or not JuiceSettings.sling_tap_fire:
		return
	var flying := run.state == SlingRun.State.FLYING
	# Mid-launch the guns only fire on their own (Settings > Difficulty > Auto fire).
	if flying and roundi(JuiceSettings.sling_auto_shoot) < 2:
		return
	# Resting between launches, only an auto-aim tap shoots.
	if not flying and not (JuiceSettings.sling_tap_auto_aim and run.state == SlingRun.State.READY):
		return
	if near_ship(pos) and (JuiceSettings.sling_catch or not flying):
		return
	var cam := root.camera_node()
	if cam == null:
		return
	# Pulled onto a ship near the tap; else, with auto-aim, the best target on
	# screen; else at the tapped point at the ship's depth.
	var best: AiShip = null
	var best_px := TAP_MAGNET_PX
	var on_screen: Array = []
	for ship in root.live_enemies():
		if ship == root.controlled_ai or cam.is_position_behind(ship.global_position):
			continue
		if cam.is_position_in_frustum(ship.global_position):
			on_screen.append(ship)
		var px := cam.unproject_position(ship.global_position).distance_to(pos)
		if px < best_px:
			best_px = px
			best = ship
	if best == null and JuiceSettings.sling_tap_auto_aim:
		best = TargetPriority.best(on_screen, model.global_position, Vector3.ZERO, -1.0, TAP_AIM_RANGE)
	root.tutorial_note("tap_fire")
	var sys := root.active_systems()
	if best != null:
		root.locked_target = best
		if sys != null:
			sys.aim_override = best.global_position
	else:
		root.locked_target = null
		var depth := cam.global_position.distance_to(model.global_position) + 400.0
		if sys != null:
			sys.aim_override = cam.project_position(pos, depth)
	_fire_time = VOLLEY_TIME


## The next body a bounce heads for: the best target ship, else the nearest body.
func _seek(from: Vector3, just_hit: Node3D) -> Vector3:
	var ships: Array = []
	for s in root.live_enemies():
		if s != just_hit and not (just_hit != null and s.model == just_hit):
			ships.append(s)
	var t := TargetPriority.best(ships, from, Vector3.ZERO, -1.0, SlingRun.SEEK_RANGE, JuiceSettings.magnet_friendlies)
	return t.global_position if t != null else Vector3.INF


func physics_tick(delta: float) -> void:
	if run == null or model == null:
		return
	run.tick(delta)
	model.command.throttle = 0.0
	model.command.roll = 0.0
	if _catching and run.state == SlingRun.State.READY and gestures.is_down():
		_catching = false
		_begin_aim()
		_update_aim(gestures.current_position())
	magnet_target = null
	match run.state:
		SlingRun.State.AIMING:
			if aim_dir != Vector3.ZERO:
				root.steer_nose_toward(aim_dir)
		SlingRun.State.FLYING:
			# The launch magnet bends the flight onto a ship ahead.
			var v := model.velocity
			var sp := v.length()
			if sp > 5.0:
				model.velocity = magnet_bend(v / sp, sp, delta) * sp
		SlingRun.State.READY, SlingRun.State.RECALLING:
			model.command.yaw = 0.0
			model.command.pitch = 0.0
	var firing := _fire_time > 0.0 and run.state in [SlingRun.State.FLYING, SlingRun.State.READY]
	if _fire_time > 0.0:
		_fire_time -= delta
	var auto_mode := roundi(JuiceSettings.sling_auto_shoot)
	if run.state == SlingRun.State.FLYING and (auto_mode >= 2 or (auto_mode == 1 and _auto_volleys > 0)):
		var auto := _auto_fire_target()
		if auto != null:
			root.locked_target = auto
			firing = true
			# One volley per launch: a tap's worth, then the guns rest.
			if auto_mode == 1:
				_auto_volleys = 0
				_fire_time = maxf(_fire_time, VOLLEY_TIME)
	# Resting, an auto-aimed volley turns the nose onto its target.
	if firing and run.state == SlingRun.State.READY and root.locked_target != null \
			and is_instance_valid(root.locked_target):
		root.steer_nose_toward(root.locked_target.global_position - model.global_position)
	var sys := root.active_systems()
	if not firing and sys != null:
		sys.aim_override = Vector3.INF
	elif firing and sys != null and root.locked_target != null and is_instance_valid(root.locked_target):
		sys.aim_override = root.locked_target.global_position
	root.set_firing(firing)


## Launched: what the guns fire at on their own — the magnet's pick, else
## the best enemy ahead of the flight. Null when there is nothing.
func _auto_fire_target() -> AiShip:
	if magnet_target != null and is_instance_valid(magnet_target) and magnet_target._alive 			and TargetPriority.score(magnet_target, model.global_position, Vector3.ZERO, -1.0, AUTO_FIRE_RANGE) > 0.0:
		return magnet_target
	var v := model.velocity
	if v.length() < 5.0:
		return null
	var ships: Array = []
	for s in root.live_enemies():
		if s != root.controlled_ai:
			ships.append(s)
	return TargetPriority.best(ships, model.global_position, v.normalized(), AUTO_FIRE_CONE_COS, AUTO_FIRE_RANGE)


## Where the steady camera looks: along the flight while the ship moves;
## along the aim once the pull is under way (the view swings round behind
## the ship to look where it will fly); held still (ZERO) while it sits.
func _flight_dir() -> Vector3:
	if model == null or run == null:
		return Vector3.ZERO
	if run.state == SlingRun.State.AIMING:
		# The frame holds still while pulling: the view turns to look along
		# the aim (see [method _update_camera]) instead of moving.
		return Vector3.ZERO
	if run.state == SlingRun.State.FLYING and _holds_launch():
		return _launch_dir
	if run.state == SlingRun.State.READY and _rest_dir != Vector3.ZERO:
		return _rest_dir
	var v := model.velocity
	return v if v.length() > 8.0 else Vector3.ZERO


## Whether the flying camera holds the launch line (the old framing) rather
## than sitting behind where the ship is really going.
func _holds_launch() -> bool:
	return JuiceSettings.sling_cam_hold_launch and not JuiceSettings.sling_cam_follow_flight \
			and _launch_dir != Vector3.ZERO


func frame_tick(delta: float) -> void:
	super(delta)
	if run == null or root.camera_rig == null:
		return
	# While pulling, a second finger looks around instead of ending the pull.
	gestures.keep_primary = run.state == SlingRun.State.AIMING
	# A still thumb sends no drag events, but the ship still drifts on
	# screen: re-read the pull every frame so the band stays on the hull.
	if run.state == SlingRun.State.AIMING and gestures.is_down():
		_update_aim(gestures.current_position())
	# The camera rides the flight, not the tumbling hull.
	root.camera_rig.follow_dir = _dir_cb if JuiceSettings.sling_steady_cam else Callable()
	# Aiming, the swing round behind the ship is gentle, so the view never
	# whips about under the thumb.
	root.camera_rig.follow_dir_rate = 1.3 if run.state == SlingRun.State.AIMING else 1.6
	if run.state == SlingRun.State.AIMING and aim_power > 0.02:
		var tint := ARROW_BLUE.lerp(Color(0.75, 0.35, 1.0), aim_power * 0.7)
		lay_arrow(0, aim_dir, aim_power, tint, 0.6 + 0.4 * aim_power)
	else:
		hide_arrows()
	_update_camera()


## The dynamic camera (see the class doc): pull-out, look-ahead and the
## ease back in near ships and as the ship slows. All targets the camera eases
## to — nothing here moves it directly.
func _update_camera() -> void:
	var rig := root.camera_rig
	var cam := root.camera_node()
	if model == null or cam == null:
		return
	var pos := model.global_position
	rig.look_ahead_rate = 1.0 / maxf(JuiceSettings.sling_look_ahead_time, 0.05)
	# Looked around by hand this pull: leave the view exactly as they set it.
	if run.state == SlingRun.State.AIMING and _looked:
		return
	# Look-ahead is measured against the camera's distance, so it frames the
	# same at any zoom (capped, so it can't run away with itself).
	var reach := minf(cam.global_position.distance_to(pos), rig.hull_length * 40.0)
	var near := _closeness()
	var zoom := 0.0
	var ahead := Vector3.ZERO
	var close_in := 0.0
	# 1 = the resting framing (further out), 0 = the flight's own.
	var rest := 1.0
	match run.state:
		SlingRun.State.AIMING:
			# The camera stays put and turns to look where the pull will throw
			# the ship — toward the ship the launch magnet will bend onto, if
			# any — following the aim as the thumb moves (eased).
			# On a touchscreen the view stays put: the thumb pulls, a second finger
			# looks around (and two fingers off the ship pinch and pan freely).
			if not DisplayServer.is_touchscreen_available() and _cam_lock != Vector3.ZERO and aim_dir != Vector3.ZERO:
				zoom = JuiceSettings.sling_aim_zoom
				var aim_look := aim_dir
				var r := reach * JuiceSettings.sling_aim_look
				var pick := find_magnet(aim_dir)
				if pick != null:
					var to_pick := pick.global_position - pos
					if to_pick.length() > 1.0:
						aim_look = (aim_dir + to_pick.normalized()).normalized()
						r = minf(r, to_pick.length() * 0.7)
				ahead = aim_look * r
		SlingRun.State.FLYING:
			var sf := run.speed_fraction()
			rest = 1.0 - sf
			reach *= JuiceSettings.sling_look_ahead
			zoom = maxf(sf, 0.35) * JuiceSettings.sling_zoom * (1.0 - near * 0.8)
			var v := model.velocity
			var look := v.normalized() if v.length() > 5.0 else Vector3.ZERO
			if _holds_launch():
				# Held on the launch line: no re-framing onto picks or bounces.
				look = _launch_dir
			elif magnet_target != null and is_instance_valid(magnet_target):
				# What it is about to hit, when it has a pick.
				var to := magnet_target.global_position - pos
				look = (look + to.normalized()).normalized()
				reach = minf(reach, to.length() * 0.6)
			ahead = look * reach * maxf(sf, 0.35)
			close_in = near
		_:
			close_in = near
	rig.hold_zoom(zoom)
	# The same window as the swipe camera, with the slingshot's own nearest:
	# however far the launch pulls it out, the ship never shrinks to a speck,
	# and easing in never comes right onto the hull.
	var lo := JuiceSettings.sling_cam_min
	rig.distance_limits = Vector2(lo, maxf(JuiceSettings.swipe_cam_max, lo))
	rig.look_ahead = ahead
	# At rest (the level's start, a fling run out) it sits further out; near
	# other ships it eases in a little, never past the window's nearest.
	var base := lerpf(1.0, JuiceSettings.sling_rest_distance, rest)
	rig.profile_distance = base * (1.0 - close_in * JuiceSettings.sling_close_zoom)


## 0..1: how close the nearest other ship is (1 = nearly touching, 0 = far).
func _closeness() -> float:
	var r := root.camera_rig.hull_radius if root.camera_rig != null else 3.0
	var best := INF
	for s in root.live_enemies():
		if s == root.controlled_ai or s.model == model:
			continue
		best = minf(best, s.global_position.distance_to(model.global_position))
	return 1.0 - smoothstep(r * 6.0, maxf(r * 40.0, 250.0), best)


func draw(canvas: Control) -> void:
	if run == null:
		return
	var s := ship_screen_pos()
	if s == Vector2.INF:
		return
	var t := Time.get_ticks_msec() * 0.001
	var gr := grab_radius()
	if run.state == SlingRun.State.READY:
		# "Grab me": a dashed ring slowly turning, breathing a little.
		var r := gr * (0.8 + 0.04 * sin(t * 3.0))
		for i in 12:
			var a0 := t * 0.8 + TAU * float(i) / 12.0
			canvas.draw_arc(s, r, a0, a0 + TAU / 12.0 * 0.55, 6, Color(1.0, 0.85, 0.35, 0.45), 2.5, true)
	elif run.state in [SlingRun.State.FLYING, SlingRun.State.RECALLING] and JuiceSettings.sling_catch:
		# In flight it can be caught: the same ring, fainter, still on the hull.
		var r := gr * 0.8
		for i in 12:
			var a0 := -t * 1.4 + TAU * float(i) / 12.0
			canvas.draw_arc(s, r, a0, a0 + TAU / 12.0 * 0.4, 6, Color(1.0, 0.85, 0.35, 0.25), 2.0, true)
	elif run.state == SlingRun.State.AIMING and pull.length() > 1.0:
		# Drawn from the ship as it is now to the thumb (the aim itself is
		# read from the touch-down anchor).
		_draw_pull_band(canvas, s, finger - s, gr, t)
		if JuiceSettings.move_arrows:
			return
		var col := Color(1.0, 0.8, 0.3).lerp(Color(1.0, 0.3, 0.2), aim_power)
		var tip := s - pull.normalized() * (40.0 + 160.0 * aim_power)
		canvas.draw_line(s, tip, col, 5.0, true)
		var side := (tip - s).normalized().orthogonal() * 10.0
		var back := tip - (tip - s).normalized() * 16.0
		canvas.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)


## The pull-back while aiming: an elastic band in two strands from either
## side of the ship to a pouch under the finger, thinning as it stretches,
## and a power arc round the ship that fills (gold → red) with the pull,
## ticked every 10%, pulsing when it's maxed.
func _draw_pull_band(canvas: Control, s: Vector2, band: Vector2, gr: float, t: float) -> void:
	var power := clampf(aim_power, 0.0, 1.0)
	var col := Color("ffd23f").lerp(Color("ff3b3b"), power)
	# Too weak to launch: the band greys out, so letting go reads as a cancel.
	if power < CANCEL_PULL:
		col = Color(0.7, 0.7, 0.75, 0.6)
	var ink := Color(0.05, 0.02, 0.08, 0.85)
	var pouch := s + band
	var along := band.normalized()
	var across := along.orthogonal()
	# Two strands from the ship's "prongs" to the pouch; thinner the harder
	# it's pulled, like real elastic.
	var prong := gr * 0.55
	var thick := lerpf(7.0, 3.0, power)
	for side: float in [-1.0, 1.0]:
		var from := s + across * prong * side - along * gr * 0.15
		var to := pouch + across * 7.0 * side
		canvas.draw_line(from, to, ink, thick + 3.0, true)
		canvas.draw_line(from, to, col, thick, true)
		canvas.draw_circle(from, thick * 0.9, col.lightened(0.3))
	# The pouch under the finger.
	canvas.draw_circle(pouch, 13.0, ink)
	canvas.draw_circle(pouch, 10.0, col)
	canvas.draw_circle(pouch - Vector2(3.0, 3.0), 3.5, Color(1, 1, 1, 0.55))
	# The power arc: a 270° gauge round the ship, opening toward the launch.
	var r := gr * 1.25
	var start := (-along).angle() + PI * 0.75
	var sweep := PI * 1.5
	canvas.draw_arc(s, r, start, start + sweep, 48, ink, 12.0, true)
	canvas.draw_arc(s, r, start, start + sweep, 48, Color(1, 1, 1, 0.22), 8.0, true)
	var pulse := 1.0 + (0.25 * sin(t * 18.0) if power >= 0.99 else 0.0)
	if power > 0.005:
		canvas.draw_arc(s, r, start, start + sweep * power, 48, Color(col, 0.95), 8.0 * pulse, true)
	for i in range(1, 10):
		var a := start + sweep * float(i) / 10.0
		var d := Vector2.from_angle(a)
		canvas.draw_line(s + d * (r - 5.0), s + d * (r + 5.0), Color(1, 1, 1, 0.35 if float(i) / 10.0 > power else 0.8), 1.5, true)
