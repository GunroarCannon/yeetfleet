## The camera, in three views: from the pilot's seat, from behind, and off the
## ship entirely.
##
## The rig is a sibling of the ship rather than a child of it, and it copies the
## ship's transform each frame instead of inheriting it. That is the whole trick
## behind the chase view feeling like a camera and not like a rigid boom: a child
## node snaps with the hull and turns every turn into a whip-pan, while a rig that
## chases the hull lags, overshoots slightly and lets you see your own ship bank.
##
## The cockpit view does inherit rigidly — a pilot's head is bolted to the ship —
## but gains a small counter-sway, because a completely locked first-person view
## in a game with no cockpit interior gives the eye nothing to read rotation from.
class_name FlightCamera
extends Node3D

signal mode_changed(mode: int)

enum Mode {
	## First person, at the cockpit's eye marker.
	COCKPIT,
	## Third person, behind and slightly above.
	CHASE,
	## Detached: orbits the ship, for looking at what you built.
	ORBIT,
	## A camera ahead of the ship looking back: what is behind you, and the
	## ship's own tail, without snapping the nose around.
	REAR,
	## A far, high overview: the whole arena at a glance. Zoomable like ORBIT.
	FAR,
	## Orbiting the nearest planet or moon — the planet view. Zoomable like ORBIT,
	## but the centre is the body, not the ship.
	PLANET,
	## A free-pan camera: starts centred on the player's ship and follows it until
	## the player pans the centre away. Drag orbits, wheel zooms out to far-view
	## distance, right-drag / second finger pans. Re-centre with [method recentre].
	FREE,
	## Orbiting an arbitrary point — the AI arena's free pan (orbits the arena
	## centre) or a focused ship. Centre set via [method set_focus] /
	## [method set_target_centre].
	TARGET,
	## A tight, low over-the-shoulder chase: closer, banks harder, reacts faster.
	ACTION,
	## A slow movie camera drifting around the ship as it flies, like a
	## chase-plane cameraman looking for the good angle.
	CINEMATIC,
	## Side-on profile, trailing the ship's heading — the "flyby" view.
	SIDE,
	## Tactical overhead, nose to the top of the screen: see what is around you.
	TOP_DOWN,
}

## The order [method cycle_mode] (V) walks. TARGET is left out: it is the AI
## arena's camera, set explicitly through [method set_focus].
const CYCLE := [
	Mode.CHASE, Mode.ACTION, Mode.CINEMATIC, Mode.SIDE, Mode.TOP_DOWN,
	Mode.COCKPIT, Mode.REAR, Mode.ORBIT, Mode.FAR, Mode.PLANET, Mode.FREE,
]
## The views that ride along behind/beside the player's ship: touch-hold
## accelerates in them and the kill cam may take over from them.
const FOLLOW_MODES := [
	Mode.COCKPIT, Mode.CHASE, Mode.REAR, Mode.ACTION, Mode.CINEMATIC, Mode.SIDE, Mode.TOP_DOWN,
]

## Distance behind the ship in chase view, as a multiple of the hull's own
## length. Scaling to the hull is what lets one camera serve a 6 m scout and a
## 90 m capital ship without a per-design tuning table.
const CHASE_BACK := 1.7
## How far above the hull, as a multiple of its radius. High enough to look down
## on the ship rather than along it: from level with the wing plane a ship is a
## line, and the whole point of the third-person view is seeing what you built.
const CHASE_UP := 0.95
## How fast the chase camera swings back into place, per second. Position is
## looser than aim: the camera may trail through a turn, but it must never look
## away from the ship.
##
## Applied to the *offset* from the hull, never to the camera's world position.
## Smoothing a world position towards a target that is itself moving at 240 m/s
## leaves a first-order lag of speed/rate — forty metres at cruise, growing with
## every point of top speed a design gains. The ship shrank to a speck the faster
## it went, which is the exact opposite of what a chase camera is for.
const CHASE_POSITION_SMOOTH := 6.0
const CHASE_AIM_SMOOTH := 11.0
## Extra distance at full speed, so acceleration is felt as the camera falling
## back before it catches up.
const CHASE_SPEED_STRETCH := 0.45

## Degrees the cockpit view swings against a full-rate turn. Deliberately small:
## this is a hint of mass, not a simulation of a pilot's neck.
const COCKPIT_SWAY := 3.5
const COCKPIT_SWAY_SMOOTH := 5.0
## Small translational bob layered on the cockpit sway, metres.
const COCKPIT_BOB := 0.04

## Roll into a sustained turn, degrees. The single biggest juice win in flight
## for the least code — see `juice-and-more.md` §3.6.
const BANK_MAX := 12.0
const BANK_SMOOTH := 1.0 / 0.3
## The camera trails hard pitch by this many degrees before springing back.
const PITCH_LAG_MAX := 3.0
const PITCH_LAG_SMOOTH := 6.0

## Boost pulls the chase camera back and widens the FOV, then snaps forward on
## release — the camera's own read of "we are going faster now", distinct from
## [FlightModel]'s actual speed (which chase distance already reacts to via
## [constant CHASE_SPEED_STRETCH]).
const BOOST_DOLLY_BACK := 0.15
const BOOST_DOLLY_FOV := 8.0
const BOOST_DOLLY_SMOOTH := 5.0
const BASE_FOV := 72.0

## Sub-Hz idle drift so a stationary ship is not a still photograph. Fades out
## as soon as the ship is actually moving, where bank and pitch lag take over
## the job of making the view feel alive.
const IDLE_DRIFT_AMOUNT := 0.15
const IDLE_DRIFT_FREQ := 0.11

const ORBIT_MIN_DIST := 1.6
const ORBIT_MAX_DIST := 600.0
## The FAR view is an orbit view pulled right out — enough to frame the belt,
## the planet and a bit of the arena at once. A var (not const) so the settings
## panel's "Far-view distance" slider can raise it.
const FAR_MIN_DIST := 20.0
var far_max_dist := 400.0
## Planet view sits outside the body, scaled to its radius: body.radius × this.
const PLANET_DIST_SCALE := 1.6
## Planet view zoom clamp, before the body-radius scale is applied.
const PLANET_ZOOM_MIN := 0.35
const PLANET_ZOOM_MAX := 5.0
## How far out the TARGET (arena) camera can pull — enough to frame the whole
## 4000 m arena box at a glance.
const TARGET_MAX_DIST := 6000.0
## How far the rear camera sits behind the ship (× hull length) and above it.
const REAR_BACK := 1.9
const REAR_UP := 0.9
const LOOK_SENSITIVITY := 0.22
## Free-look limits in cockpit and chase, in degrees. Full 360 is disorienting
## when the only way back is to find centre by hand, so the view springs back.
const FREELOOK_YAW_LIMIT := 130.0
const FREELOOK_PITCH_LIMIT := 70.0
const FREELOOK_RETURN := 5.0

## User camera FOV dial (degrees), Session-backed so it survives a restart. The
## chase camera adds its boost dolly on top of this base; other modes use it as
## the plain field of view.
var base_fov := Session.camera_fov
## Third-person chase-distance multiplier (1.0 = the default framing), from the
## Settings/View menus.
var chase_scale := Session.camera_chase

var mode: int = Mode.CHASE

var camera: Camera3D

## Set by [FlightRoot] once the ship exists.
var ship: Node3D
var model: FlightModel
var space: SpaceScene
## The shared gravity system, for the planet view's nearest-body search.
var gravity: GravitySystem
## TARGET-mode centre: a ship to follow, or null to orbit [member target_centre]
## (the arena's free pan).
var focus_node: Node3D = null
## TARGET-mode fallback centre when no ship is focused (the arena centre).
var target_centre := Vector3.ZERO

## Eye transform in ship space, from the cockpit part's marker.
var eye := Transform3D(Basis(), Vector3(0.0, 0.6, -0.6))
## Hull size, used to scale the chase distance and the near plane.
var hull_radius := 3.0
var hull_length := 6.0

## Free-look offset, degrees, applied on top of whatever the mode produces.
var look_yaw := 0.0
var look_pitch := 0.0
var _looking := false

## Orbit state, only used in [constant Mode.ORBIT].
var _orbit_yaw := 150.0
var _orbit_pitch := 18.0
var _orbit_distance := 12.0

var _sway := Vector2.ZERO
## Smoothed offset from the hull to the camera, in world space. See
## [constant CHASE_POSITION_SMOOTH] for why this is an offset and not a position.
var _chase_offset := Vector3.ZERO

var _bank := 0.0
var _pitch_lag := 0.0
var _boost_dolly := 0.0
var _idle_time := 0.0

## Dynamic zoom (0..1): hits and crashes pull the camera out, it holds there
## while hits keep landing, then eases back in. Raised by [method bump_zoom],
## advanced in [method _update_zoom], read as a scale on the chase offset and
## a wider FOV. The zoom is scaled onto the smoothed offset after the follow
## smoothing, not fed into it, so nothing else fights it.
##
## Three stages so nothing snaps: [member _zoom_target] is what hits raise.
## It holds for [member JuiceSettings.cam_zoom_hold] seconds, then slides back
## to 0 over [member JuiceSettings.cam_zoom_return_time]. [member _zoom] follows
## the target through a critically damped spring ([method _smooth_damp]). Its
## velocity carries over, so a hit landing mid-return turns the camera round
## smoothly instead of popping it. The zoom used to be a plain lerp that
## decayed faster than it could rise, so a hit barely moved the camera and
## the recovery looked like a jolt.
var _zoom := 0.0
var _zoom_vel := 0.0
var _zoom_target := 0.0
var _zoom_hold := 0.0
## Smoothed multiplier on the zoom distance: 1 for a normal hit, and eases
## toward [constant ZOOM_MASSIVE_SCALE] after a planet/station crash, so the
## crash pulls much further out without the distance jumping.
var _zoom_scale := 1.0
var _zoom_massive := false
## A hit on kinematic scenery this size or larger (metres) is a planet/station/
## anomaly, not a rock or a ship — see [method FlightRoot._on_model_collided].
const MASSIVE_HIT_RADIUS := 25.0
## Massive hits pull out this many times further, enough to clear a planet or
## station's surface instead of leaving the camera inside the mesh.
const ZOOM_MASSIVE_SCALE := 4.0
## Extra FOV (degrees) at full zoom, on top of the distance pull-back.
const ZOOM_FOV := 12.0

## Real (unscaled) frame time. Hitstop and slow-mo lower [member
## Engine.time_scale]; camera smoothing that ran on scaled delta froze during a
## freeze-frame and then lurched to catch up. Smoothing uses this, while
## anything that tracks the ship's game-time motion still uses delta.
var _dt := 0.016
## The time scale that produced this frame's delta. [member Engine.time_scale]
## is often changed partway through a frame (a hitstop from a physics impact,
## a freeze from a hit), and dividing delta by the new value instead turned
## one ordinary frame into a 7× smoothing step: the "ship jumps back and
## snaps home" pop at the start of every freeze. Captured at the first hook
## of each engine iteration, before anything this frame can change it.
var _frame_ts := 1.0
var _frame_ts_id := -1

## Kill cam (see [method start_kill_cam]). Runs on [member _dt], real time, so
## it moves at full speed while the game itself is paused.
var _kc_active := false
var _kc_t := 0.0
var _kc_target := Vector3.ZERO
var _kc_node: Node3D = null
var _kc_dir := Vector3.BACK
var _kc_dist := 12.0
## The mode's own transform before the kill cam overlay, restored at the top
## of each frame so the chase smoothing never sees (and fights) the overlay.
var _base_xform := Transform3D()
var _kc_weight := 0.0
## Degrees per real second the kill cam circles the wreck.
const KILL_CAM_ORBIT := 14.0
## A slower kill cam (a planet's): swoop in and hold × this.
var _kc_slow := 1.0
## Per shot, seconds: ease in, hold, ease out. Negative = the Juice dials
## (a kill); [method show_ship] sets its own.
var _kc_times := Vector3(-1.0, -1.0, -1.0)
## Level intro (see [method start_intro]): real seconds left and in total,
## and the view the camera mode computed this frame (restored next frame so
## the modes' own smoothing never sees the intro's offset).
var _intro_left := 0.0
var _intro_total := 0.0
## The running kill-cam shot is a [method spotlight] (the game is held under it).
var _spot := false
## When the intro ends (ticks, ms). It runs on the wall clock and counts down
## even while a kill cam holds the view or there is no ship yet — it used to
## count only frames it was drawn in, and a kill cam in the opening seconds
## left the controls locked for good.
var _intro_end_ms := 0
var _intro_base := Transform3D.IDENTITY
## Most the kill cam advances in one frame, seconds. The frames right after a
## kill are the likeliest to hitch (explosions, debris, a first-use shader
## compile on a phone), and an uncapped step let one or two long frames eat the
## whole swoop in: the camera seemed to cut straight to the wreck instead of
## travelling there from the player. Capped, a hitch only slows the swoop.
const KILL_CAM_MAX_STEP := 1.0 / 30.0

## The follow point: the hull's origin minus [member _knock_lag]. At a steady
## speed the lag is exactly zero and the camera is rigidly locked to the hull.
## A sudden velocity change (knockback, a ram) opens a small lag that eases
## shut over a few frames, so the view absorbs the kick instead of lurching.
## Capped at [constant ANCHOR_MAX_ERROR] × hull radius so the ship can never
## drift out of frame.
##
## The lag is computed in [method _physics_process], on the same ticks the
## ship moves on. An earlier version advanced the follow point by the ship's
## velocity every render frame. The ship only moves on 60 Hz physics ticks
## (no physics interpolation in this project), so on any faster display the
## point ran ahead between ticks and fell back on them, and the ship jittered
## forward and back in frame.
var _anchor := Vector3.ZERO
var _knock_lag := Vector3.ZERO
var _knock_lag_prev := Vector3.ZERO
var _knock_vel := Vector3.ZERO
var _knock_reset := true
const ANCHOR_VEL_RATE := 7.0
const ANCHOR_POS_RATE := 5.0
const ANCHOR_MAX_ERROR := 0.6

## The frame the chase camera builds its offset and aim from. It normally
## tracks the hull almost exactly, but while the ship is out of control it
## drifts only slowly. A tumbling hull spins inside a steady view (the
## "spinning top") instead of dragging the camera round with it, which used to
## whip the ship out of frame.
var _ref_quat := Quaternion.IDENTITY
var _ooc_blend := 0.0
const REF_FOLLOW_RATE := 40.0
const REF_OOC_RATE := 0.6
const OOC_BLEND_IN := 0.25
const OOC_BLEND_OUT := 0.9
## Boost release eases out instead of snapping (it used to snap instantly).
const BOOST_DOLLY_RELEASE_SMOOTH := 2.5
## ACTION view framing, as multiples of the chase distance and height.
const ACTION_BACK := 0.62
const ACTION_UP := 0.55
## How fast [member _turn] follows the hull's turn rate, per second.
const TURN_SMOOTH := 4.0
const SPEED_FOV_SMOOTH := 2.5
## How fast each lazy follow view's frame turns after the hull, per second.
const VIEW_FOLLOW_RATE := {Mode.CINEMATIC: 1.1, Mode.SIDE: 2.5, Mode.TOP_DOWN: 1.8}
## Radians per second the CINEMATIC camera's wander phase advances.
const CINE_SPEED := 0.16
var _turn := Vector2.ZERO
var _speed_fov := 0.0
var _cine_t := 0.0
## Set on a mode change so the new view snaps into place instead of flying across
## the scene from wherever the old one was.
var _snap := true
## Whether the FREE view's centre is still tracking the player's ship. A pan sets
## it false; [method recentre] restores it.
var _free_follow := true

## When true, the chase (and cockpit) cameras freeze their smoothed position/aim
## while the ship is [member FlightModel.out_of_control], letting the hull tumble
## away from frame until the player regains control — a dramatic "watch it spin"
## beat. When false (the default) the camera follows normally throughout the OOC.
var ooc_camera_hold := false


func _ready() -> void:
	# The rig places itself every render frame from already-interpolated ship
	# transforms, so interpolating it again would only add a tick of lag.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	# The sky dome is re-centred on the camera at [constant SpaceScene.SKY_RADIUS]
	# (14 km), with the sun inside it, so the far plane has to clear that or the
	# whole sky — stars, nebula, sun — is clipped and space reads as a black void.
	# A cockpit view sits centimetres from the canopy frame; that is a wide range,
	# but the sky writes no depth so the precision that matters is all in the
	# near few hundred metres.
	camera.near = 0.2
	camera.far = 30000.0
	camera.fov = base_fov
	add_child(camera)
	# The rig places itself in world space; being parented under anything that
	# moves would double every motion.
	top_level = true
	get_tree().physics_frame.connect(_capture_frame_ts)
	get_tree().process_frame.connect(_capture_frame_ts)


## Record the time scale in force at the start of this engine iteration (see
## [member _frame_ts]). Both signals fire before any node's step, and only
## the first one in an iteration counts.
func _capture_frame_ts() -> void:
	var id := Engine.get_process_frames()
	if id == _frame_ts_id:
		return
	_frame_ts_id = id
	_frame_ts = Engine.time_scale


## Fit the rig to a freshly assembled ship.
func adopt(ship_node: Node3D, flight: FlightModel, view: ShipView) -> void:
	ship = ship_node
	model = flight
	var box := view.aabb
	hull_radius = maxf(box.size.length() * 0.5, 1.0)
	hull_length = maxf(box.size.z, 1.0)
	_orbit_distance = clampf(hull_radius * 3.0, ORBIT_MIN_DIST, ORBIT_MAX_DIST)
	# The first cockpit's eye marker is the pilot's head. Without one — a drone
	# hull, or a design mid-edit — sit just above and ahead of the hull centre so
	# the first-person view still shows the nose rather than the inside of it.
	if not view.eyes.is_empty():
		eye = view.eyes[0]["xform"] as Transform3D
	else:
		eye = Transform3D(Basis(), Vector3(box.get_center().x, box.end.y + 0.2, box.position.z))
	_snap = true


func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	cancel_kill_cam()
	mode = new_mode
	# Free look is a property of a view, not of the pilot: carrying a 90-degree
	# head turn from the chase camera into the cockpit means arriving in the seat
	# facing the wrong way.
	look_yaw = 0.0
	look_pitch = 0.0
	# Landing in FAR at a close orbit distance is jarring — pull the view out so
	# the "here is the whole arena" promise of the mode holds from the first frame.
	if mode == Mode.FAR:
		_orbit_distance = maxf(_orbit_distance, hull_length * 8.0)
	# Entering the planet view, frame the nearest body from a readable distance.
	if mode == Mode.PLANET:
		var body := _planet_target()
		if body != null:
			_orbit_distance = body.radius * PLANET_DIST_SCALE
	# Entering FREE view, resume following the player and pull out far enough to
	# see the hull and a margin of space around it.
	if mode == Mode.FREE:
		_free_follow = true
		_orbit_distance = maxf(_orbit_distance, hull_length * 4.0)
	_snap = true
	mode_changed.emit(mode)


func cycle_mode() -> void:
	var i := CYCLE.find(mode)
	set_mode(CYCLE[(i + 1) % CYCLE.size()])


## Whether the current view follows the player's ship (see [constant FOLLOW_MODES]).
func is_follow_mode() -> bool:
	return mode in FOLLOW_MODES


func mode_label() -> String:
	match mode:
		Mode.COCKPIT: return "Cockpit"
		Mode.CHASE: return "Chase"
		Mode.ORBIT: return "External"
		Mode.REAR: return "Rear"
		Mode.FAR: return "Far"
		Mode.PLANET: return "Planet"
		Mode.FREE: return "Free"
		Mode.TARGET: return "Target"
		Mode.ACTION: return "Action"
		Mode.CINEMATIC: return "Cinematic"
		Mode.SIDE: return "Side"
		Mode.TOP_DOWN: return "Top-down"
		_: return "External"


## Begin or end a free-look drag. While looking, the stick still flies the ship.
func set_looking(active: bool) -> void:
	_looking = active


## Feed a look drag, in pixels.
func look(delta_px: Vector2) -> void:
	if mode == Mode.ORBIT or mode == Mode.FAR or mode == Mode.PLANET or mode == Mode.TARGET or mode == Mode.FREE:
		_orbit_yaw = wrapf(_orbit_yaw - delta_px.x * LOOK_SENSITIVITY, 0.0, 360.0)
		# Clamped well short of vertical: past ~±64° the world-up fallback in
		# [_method _look_basis] snaps to a different up and the whole view rolls
		# — which reads as the external camera gittering.
		_orbit_pitch = clampf(_orbit_pitch + delta_px.y * LOOK_SENSITIVITY, -60.0, 60.0)
		return
	look_yaw = clampf(look_yaw - delta_px.x * LOOK_SENSITIVITY, -FREELOOK_YAW_LIMIT, FREELOOK_YAW_LIMIT)
	look_pitch = clampf(look_pitch - delta_px.y * LOOK_SENSITIVITY, -FREELOOK_PITCH_LIMIT, FREELOOK_PITCH_LIMIT)


func zoom(steps: float) -> void:
	if mode != Mode.ORBIT and mode != Mode.FAR and mode != Mode.PLANET and mode != Mode.TARGET and mode != Mode.FREE:
		return
	if mode == Mode.FAR:
		_orbit_distance = clampf(
			_orbit_distance * pow(0.88, steps), FAR_MIN_DIST, far_max_dist
		)
	elif mode == Mode.FREE:
		# FREE zooms from close enough to read the hull right out to the same far
		# ceiling the settings panel's "Far-view distance" slider drives.
		_orbit_distance = clampf(
			_orbit_distance * pow(0.88, steps), ORBIT_MIN_DIST, far_max_dist
		)
	elif mode == Mode.PLANET:
		# Zoom is relative to the body's own scale, so a moon and a gas giant
		# both feel like "pull in / pull out".
		var body := _planet_target()
		var base := body.radius * PLANET_DIST_SCALE if body != null else 1000.0
		_orbit_distance = clampf(
			_orbit_distance * pow(0.88, steps),
			base * PLANET_ZOOM_MIN, base * PLANET_ZOOM_MAX
		)
	elif mode == Mode.TARGET:
		_orbit_distance = clampf(
			_orbit_distance * pow(0.88, steps), ORBIT_MIN_DIST, TARGET_MAX_DIST
		)
	else:
		_orbit_distance = clampf(
			_orbit_distance * pow(0.88, steps), ORBIT_MIN_DIST, ORBIT_MAX_DIST
		)


## Dial the camera FOV, degrees. Writes [member base_fov]; the chase mode adds
## its boost dolly on top of this base each frame, so no extra apply is needed.
func set_fov(deg: float) -> void:
	base_fov = clampf(deg, 50.0, 120.0)
	if camera != null:
		camera.fov = base_fov


## Dial the third-person chase-distance multiplier (1.0 = default framing).
func set_chase_scale(scale: float) -> void:
	chase_scale = maxf(scale, 0.25)


## Adapts camera framing for mobile screens: tighter chase distance and focused FOV.
func set_mobile_view(enabled: bool) -> void:
	if enabled:
		set_chase_scale(0.72)
		set_fov(62.0)
	else:
		set_chase_scale(1.0)
		set_fov(72.0)


## Pull the camera out for a hit or crash (see [member _zoom]'s doc comment).
## [param strength] 0..1. Called by [FlightRoot] for physical collisions and
## for weapon hits. Repeated hits stack a little on top of the strongest one,
## so a sustained volley keeps pushing the view out and holds it there.
##
## [param massive]: the hit was on kinematic scenery at or above [constant
## MASSIVE_HIT_RADIUS] (a planet, station or anomaly), so the camera pulls
## [constant ZOOM_MASSIVE_SCALE] times further and holds twice as long.
func bump_zoom(strength: float, massive: bool = false) -> void:
	var s := clampf(strength, 0.0, 1.0)
	if massive:
		_zoom_massive = true
		s = 1.0
	_zoom_target = minf(maxf(_zoom_target, s) + s * 0.25, 1.0)
	_zoom_hold = maxf(_zoom_hold, JuiceSettings.cam_zoom_hold * (2.0 if massive else 1.0))


## How far out the dynamic zoom currently has the camera, as a fraction of the
## normal chase distance (0 = normal framing).
func zoom_extra() -> float:
	return _zoom * JuiceSettings.cam_zoom_amount * _zoom_scale + _held_zoom


## A sustained pull-out, held until changed: the slingshot profile sets it from
## the launch speed while the ship ping-pongs, and 0 when the run ends. It
## eases both ways (never a snap) and adds to the hit/crash zoom above.
## [param amount] is a fraction of the normal chase distance.
func hold_zoom(amount: float) -> void:
	_held_zoom_target = maxf(amount, 0.0)


## Current and wanted [method hold_zoom] pull-out.
var _held_zoom := 0.0
var _held_zoom_target := 0.0


# --- Player camera gestures (movement profiles) ---------------------------------
# The one-thumb profiles let the player swing the follow views round the ship
# (a drag off the ship, two fingers twisting, right-drag) and pinch them in and
# out (two fingers, mouse wheel). All of it is a target the view eases to —
# never a snap — and it pivots about the ship, not the camera.

## Furthest the swing may tilt over or under the ship, degrees (short of the
## vertical, where the look-at up vector would flip).
const USER_PITCH_LIMIT := 70.0
const USER_DISTANCE_MIN := 0.35
const USER_DISTANCE_MAX := 5.0
## How fast the eased view catches the gesture targets, per second.
const USER_VIEW_RATE := 12.0

## Wanted swing round the ship (degrees, in the followed frame) and pinch
## distance (× the normal chase distance).
var user_yaw := 0.0
var user_pitch := 0.0
var user_distance := 1.0
## A profile's own extra pull-out, × (the swipe profile sits further out).
var profile_distance := 1.0
## Optional: () -> Vector3, a forward direction the follow views track instead
## of the hull's rotation (Vector3.ZERO = hold the current frame). The
## slingshot passes the flight direction, so a tumbling hull never spins the
## view; the FPS profile passes where the player is looking.
var follow_dir := Callable()
## How fast the frame turns onto [member follow_dir], per second.
var follow_dir_rate := 2.0
## A profile's look-ahead: a world offset the aim point moves by, eased — the
## slingshot looks along its aim and its flight, so what the ship is about to
## hit is on screen. Kept even when swung round (the ship slides off centre).
var look_ahead := Vector3.ZERO
## The most [member look_ahead] may shift the aim point, × the camera's
## distance: about 28° off the ship, inside any follow view's half-FOV.
const LOOK_AHEAD_MAX := 0.55
## How fast [member look_ahead] is eased in, per second.
var look_ahead_rate := 2.5
## Optional window the follow views' whole distance stays inside, × the
## normal chase distance (x: closest, y: furthest; ZERO = no limits). Pinch,
## the profile's pull-out and the hit/dash zoom all multiply together, and the
## swipe profile sets this so none of them can take the camera too far out or
## right onto the hull.
var distance_limits := Vector2.ZERO

## Optional: () -> Vector3, where the nearest foe is ([constant Vector3.INF]:
## none). The motion focus looks at it after a knock-back.
var foe_focus := Callable()
## Speed (× the hull's top speed) where the motion focus starts and where it is
## full: a yeet or a hard shove, not cruising.
const MOTION_START := 1.0
const MOTION_FULL := 1.8
## How far the motion focus may pull the aim point, × the camera's distance
## (on top of [constant LOOK_AHEAD_MAX]'s room: the ship stays in the shot).
const MOTION_REACH := 0.45
## How fast the motion focus eases in and out, per second.
const MOTION_IN_RATE := 1.6
const MOTION_OUT_RATE := 2.4
var _motion_focus := Vector3.ZERO
## A [member follow_dir] flight within this many degrees of the view's own line
## is already "behind the ship": the frame stays put (full swing by the far
## angle) and the aim shifts below fade out, so a launch along the view never
## turns the camera.
const BEHIND_NEAR_DEG := 12.0
const BEHIND_FAR_DEG := 35.0
## 0..1: how much the followed flight is already along the view (see above).
var _behind := 0.0
## 0..1, how far the motion focus is pulling now (for the checks).
var motion_focus_amount := 0.0

var _user_yaw := 0.0
var _user_pitch := 0.0
var _user_distance := 1.0
var _profile_distance := 1.0
var _look_ahead := Vector3.ZERO
## 0..1: how much the view is on [member follow_dir] (eased, for the swap).
var _dir_blend := 0.0


## Swing the view round the ship by [param delta_deg] (x: yaw, y: pitch).
func orbit_by(delta_deg: Vector2) -> void:
	user_yaw = wrapf(user_yaw + delta_deg.x, -180.0, 180.0)
	user_pitch = clampf(user_pitch + delta_deg.y, -USER_PITCH_LIMIT, USER_PITCH_LIMIT)


## Pinch: [param factor] > 1 pulls the view in (fingers spreading).
func pinch_by(factor: float) -> void:
	if factor <= 0.0:
		return
	user_distance = clampf(user_distance / factor, USER_DISTANCE_MIN, USER_DISTANCE_MAX)
	if distance_limits != Vector2.ZERO:
		# Pinching past the window would just bank up distance the limits then
		# hide, and the way back would feel dead.
		var pd := maxf(profile_distance, 0.05)
		user_distance = clampf(user_distance, distance_limits.x / pd, distance_limits.y / pd)


## Back to the normal framing (eased).
func reset_user_view() -> void:
	user_yaw = 0.0
	user_pitch = 0.0
	user_distance = 1.0
	profile_distance = 1.0
	follow_dir = Callable()
	look_ahead = Vector3.ZERO
	look_ahead_rate = 2.5
	distance_limits = Vector2.ZERO


func _update_user_view(dt: float) -> void:
	var k := 1.0 - exp(-USER_VIEW_RATE * dt)
	if _snap:
		k = 1.0
	# The shortest way round, so a swing past ±180° doesn't unwind the long way.
	_user_yaw += wrapf(user_yaw - _user_yaw, -180.0, 180.0) * k
	_user_pitch = lerpf(_user_pitch, user_pitch, k)
	_user_distance = lerpf(_user_distance, user_distance, k)
	_profile_distance = lerpf(_profile_distance, profile_distance, 1.0 - exp(-3.0 * dt))
	_look_ahead = look_ahead if _snap else _look_ahead.lerp(look_ahead, 1.0 - exp(-look_ahead_rate * dt))
	# Never look so far ahead that the ship itself leaves the shot.
	_look_ahead = _look_ahead.limit_length(maxf(_chase_offset.length(), 1.0) * LOOK_AHEAD_MAX)
	_dir_blend = move_toward(_dir_blend, 1.0 if follow_dir.is_valid() else 0.0, dt / 0.4)
	_update_motion_focus(dt)


## Whether the player is turning the view by hand (a free-look drag, a swing
## round the ship): the automatic focus then keeps out of the way.
func _hands_on_view() -> bool:
	return _looking or absf(user_yaw) > 2.0 or absf(user_pitch) > 2.0 		or absf(_user_yaw) > 2.0 or absf(_user_pitch) > 2.0 		or absf(look_yaw) > 2.0 or absf(look_pitch) > 2.0


## In high motion the view leans where the action is: after a yeet (or any fast
## run) at where the ship is heading; after a knock-back, at the foe that did it.
## Never when the player is turning the view by hand, never a snap — it is one
## more eased offset on the aim point, like [member look_ahead].
##
## A knock-back is the hull really tumbling ([member FlightModel.out_of_control])
## and nothing else. It used to also count any fast run with the nose turned
## away from the flight — but a sling launch flies before the hull has turned
## onto it, and a dash can leave the nose behind, so mid-yeet the view swung
## round to a foe behind the player and looked the wrong way.
func _update_motion_focus(dt: float) -> void:
	var want := Vector3.ZERO
	motion_focus_amount = 0.0
	var dial := JuiceSettings.cam_motion_focus
	if model != null and dial > 0.0 and not _hands_on_view() and not _kc_active and _intro_left <= 0.0:
		var vel := model.velocity
		var sp := vel.length()
		var high := smoothstep(MOTION_START, MOTION_FULL, sp / maxf(model.top_speed, 1.0))
		var knocked := model.out_of_control
		var vdir := vel / maxf(sp, 0.001)
		var ship_x := _ship_xform()
		if knocked:
			high = maxf(high, 0.8)
		var reach := maxf(_chase_offset.length(), 1.0) * MOTION_REACH * dial
		if high > 0.0:
			var dir := vdir
			if knocked:
				# Thrown back: look at what threw us. With nobody there, leave it be.
				dir = Vector3.ZERO
				if foe_focus.is_valid():
					var foe: Variant = foe_focus.call()
					if foe is Vector3 and (foe as Vector3).is_finite():
						var to := (foe as Vector3) - ship_x.origin
						if to.length() > 1.0:
							dir = to.normalized()
			want = dir * reach * high
			motion_focus_amount = high if dir != Vector3.ZERO else 0.0
	if _snap:
		_motion_focus = want
	else:
		var rate := MOTION_IN_RATE if want.length_squared() > _motion_focus.length_squared() else MOTION_OUT_RATE
		_motion_focus = _motion_focus.lerp(want, 1.0 - exp(-rate * dt))


## The aim point's extra shift: a profile's look-ahead and the motion focus,
## together never further than the ship can be and still stay in the shot.
func _aim_extra() -> Vector3:
	return (_look_ahead + _motion_focus).limit_length(maxf(_chase_offset.length(), 1.0) * (LOOK_AHEAD_MAX + MOTION_REACH)) * (1.0 - _behind)


## The gesture swing, as a rotation in the followed frame's local space.
func _user_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(_user_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-_user_pitch))


## 0..1: how far the view has been swung off its normal line (the aim then
## moves from "ahead of the ship" onto the ship itself, so it stays the pivot).
func _user_swing() -> float:
	return clampf(maxf(absf(_user_yaw), absf(_user_pitch)) / 45.0, 0.0, 1.0)


func _user_scale() -> float:
	return _user_distance * _profile_distance


## The factor that brings the view's whole distance (gesture × profile ×
## [param zoom]) back inside [member distance_limits]; 1 with no limits. A
## wider FOV (speed stretch, zoom) shrinks the ship on screen just like
## distance does, so it counts too: the limit is on how small (or big) the
## ship looks, not only on metres. The inputs are all eased, so the clamped
## distance moves smoothly too.
func _limit_factor(zoom: float) -> float:
	if distance_limits == Vector2.ZERO:
		return 1.0
	var fov_k := tan(deg_to_rad(camera.fov) * 0.5) / maxf(tan(deg_to_rad(base_fov) * 0.5), 0.01)
	var s := _user_scale() * (1.0 + zoom) * fov_k
	return clampf(s, distance_limits.x, maxf(distance_limits.y, distance_limits.x)) / maxf(s, 1e-3)


## The rotation the follow views are built from: the hull's, or the
## [member follow_dir] frame when a profile supplies one.
func _follow_quat(ship_q: Quaternion) -> Quaternion:
	if not follow_dir.is_valid():
		_behind = move_toward(_behind, 0.0, _dt / 0.3)
		return ship_q
	var fwd: Variant = follow_dir.call()
	if not (fwd is Vector3) or (fwd as Vector3).length_squared() < 1e-6:
		return _ref_quat
	var up := Basis(_ref_quat).y
	var f := (fwd as Vector3).normalized()
	if absf(f.dot(up)) > 0.98:
		up = Basis(_ref_quat).z
	var target := Basis.looking_at(f, up).get_rotation_quaternion()
	# Already behind the ship (the flight runs along the view): hold the frame
	# instead of turning onto the exact line, and let the aim shifts fade.
	var off := rad_to_deg((-Basis(_ref_quat).z).angle_to(f))
	var swing := smoothstep(BEHIND_NEAR_DEG, BEHIND_FAR_DEG, off)
	_behind = move_toward(_behind, 1.0 - swing, _dt / 0.3)
	return _ref_quat.slerp(target, swing)


## The follow frame eased [param step] of the way to [param target] — but,
## while a profile steers it ([member follow_dir]), never faster than
## [member JuiceSettings.cam_max_turn_deg]: a U-turn swings the view round
## steadily instead of whipping it (the ship spinning out of shot and back).
func _turn_ref(target: Quaternion, step: float, dt: float) -> Quaternion:
	if follow_dir.is_valid():
		var ang := _ref_quat.angle_to(target)
		var most := deg_to_rad(JuiceSettings.cam_max_turn_deg) * dt
		# A launch (or a bounce) that sends the ship far off the view's line must
		# not leave it showing the ship's front: wide turns swing up to 3x faster,
		# narrow ones stay as gentle as before.
		most *= 1.0 + 2.0 * smoothstep(0.5, 1.8, ang)
		if ang > 1e-4 and ang * step > most:
			step = most / ang
	return _ref_quat.slerp(target, step)


## How settled the view is against hull motion: 1 while tumbling out of
## control or tracking a [member follow_dir] (turn swing, bank and lead fade).
func _calm() -> float:
	return maxf(_ooc_blend, _dir_blend)


# --- Kill cam ---------------------------------------------------------------

## Swoop in on a ship the player just destroyed, hold on the wreck while it
## circles slowly, then swoop back to the normal view. Only the camera moves
## here: [FlightRoot] reads [method kill_cam_weight] to pause the game under
## it. [param target] may be freed at any point; the shot then holds on
## [param target_pos]. Returns false (and does nothing) in the views that
## are not following the player's ship, or while one is already running.
func start_kill_cam(target: Node3D, target_pos: Vector3, target_radius: float, slow := 1.0) -> bool:
	if _kc_active or ship == null:
		return false
	if not is_follow_mode():
		return false
	_kc_active = true
	_kc_slow = maxf(slow, 0.1)
	_kc_times = Vector3(-1.0, -1.0, -1.0)
	_kc_t = 0.0
	_kc_weight = 0.0
	_kc_node = target
	_kc_target = target_pos
	_base_xform = global_transform
	# Come in from the side the player was already looking from, a little
	# above, so the swoop reads as a push in rather than a cut.
	var from := global_position - target_pos
	if from.length_squared() < 0.01:
		from = Vector3.BACK
	_kc_dir = (from.normalized() + Vector3.UP * 0.35).normalized()
	# Always a push in: a big hull's radii can put the dial's framing further
	# out than the camera already is, so cap it at 70% of the way — but never
	# inside the wreck itself.
	var r := maxf(target_radius, 1.5)
	_kc_dist = maxf(minf(r * JuiceSettings.kill_cam_distance + 4.0, from.length() * 0.7), r * 1.6)
	return true


## A look at a ship the player should know about (the hauler an escort
## guards): the kill cam's eased swoop onto [param target], held for
## [param hold] seconds, then eased back to the player's view. Nothing slows.
func show_ship(target: Node3D, target_radius: float, hold := 1.4, ease_in := 0.9, ease_out := 0.9) -> bool:
	if target == null or not start_kill_cam(target, target.global_position, target_radius):
		return false
	_kc_times = Vector3(ease_in, hold, ease_out)
	# Framed a little wider than a wreck: the ship and where it is going.
	_kc_dist *= 1.6
	return true


## A look at the threat a level opens on (a boss, the lone ace) with the whole
## game held still under it: [method show_ship]'s shot, and [FlightRoot] reads
## [method spotlight_active] to freeze time and the controls until the camera
## is back behind the player's ship.
func spotlight(target: Node3D, target_radius: float, hold := 1.6, ease_in := 0.9, ease_out := 0.9) -> bool:
	if not show_ship(target, target_radius, hold, ease_in, ease_out):
		return false
	_spot = true
	return true


func spotlight_active() -> bool:
	return _kc_active and _spot


func cancel_kill_cam() -> void:
	if not _kc_active:
		return
	_spot = false
	_kc_active = false
	_kc_weight = 0.0
	global_transform = _base_xform


func kill_cam_active() -> bool:
	return _kc_active


## 0 = the normal view, 1 = fully on the wreck. Eased both ways.
func kill_cam_weight() -> float:
	return _kc_weight


## A level's opening shot: the camera starts far out and above, swings
## round and eases in onto the normal view over [param seconds] of real time.
## [FlightRoot] holds the controls while it runs ([method intro_active]).
func start_intro(seconds := 2.6) -> void:
	_intro_total = maxf(seconds, 0.1)
	_intro_left = _intro_total
	_intro_end_ms = Time.get_ticks_msec() + int(_intro_total * 1000.0)


func intro_active() -> bool:
	_tick_intro()
	return _intro_left > 0.0


func _tick_intro() -> void:
	if _intro_left > 0.0:
		_intro_left = maxf((_intro_end_ms - Time.get_ticks_msec()) / 1000.0, 0.0)


func _apply_intro() -> void:
	_tick_intro()
	var k := 1.0 - _intro_left / _intro_total
	# 1 = all the way out, easing to 0 as the camera settles in behind the ship.
	var w := 1.0 - smoothstep(0.0, 1.0, k)
	var target := ship.global_position if ship != null else _intro_base.origin
	var from := _intro_base.origin - target
	if from.length_squared() < 0.01:
		from = Vector3.BACK
	var far_dist := maxf(from.length() * 14.0, 600.0)
	var dir := (from.normalized() + Vector3.UP * 0.6).normalized().rotated(Vector3.UP, deg_to_rad(70.0) * w)
	var pos := _intro_base.origin.lerp(target + dir * far_dist, w)
	var look := _look_basis(pos, target, Vector3.UP)
	var q := _intro_base.basis.get_rotation_quaternion().slerp(look.get_rotation_quaternion(), w)
	global_transform = Transform3D(Basis(q), pos)


func _apply_kill_cam() -> void:
	_kc_t += minf(_dt, KILL_CAM_MAX_STEP)
	# The length dial shortens the whole shot (and so the slow-mo under it).
	var length := maxf(JuiceSettings.kill_cam_length, 0.1)
	var blend := maxf(JuiceSettings.kill_cam_blend, 0.05) * length
	var blend_in := blend * maxf(JuiceSettings.kill_cam_ease_in, 0.1) * _kc_slow
	var hold := JuiceSettings.kill_cam_hold * _kc_slow * length
	if _kc_times.x >= 0.0:
		blend_in = maxf(_kc_times.x, 0.05)
		hold = _kc_times.y
		blend = maxf(_kc_times.z, 0.05)
	if _kc_t >= blend_in + blend + hold:
		cancel_kill_cam()
		return
	var w := 1.0
	if _kc_t < blend_in:
		w = smoothstep(0.0, 1.0, _kc_t / blend_in)
	elif _kc_t > blend_in + hold:
		w = 1.0 - smoothstep(0.0, 1.0, (_kc_t - blend_in - hold) / blend)
	_kc_weight = w
	if _kc_node != null:
		if is_instance_valid(_kc_node) and _kc_node.is_inside_tree():
			_kc_target = _kc_node.global_position
		else:
			_kc_node = null
	var orbit_dir := _kc_dir.rotated(Vector3.UP, deg_to_rad(KILL_CAM_ORBIT) * _kc_t)
	var kc_pos := _kc_target + orbit_dir * _kc_dist
	var pos := _base_xform.origin.lerp(kc_pos, w)
	# Aim along the blend too: from where the normal view was looking toward
	# the wreck, so the shot never whips round mid-swoop.
	var base_focus := _base_xform.origin - _base_xform.basis.z * maxf(
		_base_xform.origin.distance_to(_kc_target), 1.0
	)
	var focus := base_focus.lerp(_kc_target, w)
	var up := _base_xform.basis.y.lerp(Vector3.UP, w).normalized()
	var look := _look_basis(pos, focus, up)
	var q := _base_xform.basis.get_rotation_quaternion().slerp(look.get_rotation_quaternion(), w)
	global_transform = Transform3D(Basis(q), pos)


## Everything runs in _process, not _physics_process: the camera should be as
## smooth as the display, and it only ever reads the ship's state.
func _process(delta: float) -> void:
	_tick_intro()
	if ship == null:
		return
	_dt = minf(delta / maxf(_frame_ts, 0.001), 0.1)
	# Hand the mode back its own last transform; the overlay goes on after.
	if _kc_active:
		global_transform = _base_xform
	elif _intro_left > 0.0:
		global_transform = _intro_base
	_update_zoom(_dt)
	_update_user_view(_dt)
	match mode:
		Mode.COCKPIT:
			_update_cockpit(delta)
		Mode.CHASE, Mode.ACTION:
			_update_chase(delta)
		Mode.CINEMATIC, Mode.SIDE, Mode.TOP_DOWN:
			_update_follow_view(delta)
		Mode.ORBIT, Mode.FAR:
			_update_orbit(delta)
		Mode.REAR:
			_update_rear(delta)
		Mode.PLANET:
			_update_planet(delta)
		Mode.FREE:
			_update_free(delta)
		Mode.TARGET:
			_update_target(delta)
	_snap = false
	if _kc_active:
		_base_xform = global_transform
		_apply_kill_cam()
	elif _intro_left > 0.0:
		_intro_base = global_transform
		_apply_intro()
	if space != null:
		space.recentre(global_position)


func _update_cockpit(delta: float) -> void:
	var seat := _ship_xform() * eye
	global_transform = Transform3D(seat.basis, seat.origin)

	# Sway reads the ship's actual rotation rate rather than the stick, so it also
	# fires when assist damps a turn out — the head lags the hull either way.
	var wanted := Vector2.ZERO
	if model != null:
		wanted = Vector2(
			clampf(-model.angular.y / maxf(model.turn_rate, 0.01), -1.0, 1.0),
			clampf(-model.angular.x / maxf(model.turn_rate, 0.01), -1.0, 1.0)
		) * COCKPIT_SWAY
	if _snap:
		_sway = wanted
	else:
		_sway = _sway.lerp(wanted, clampf(delta * COCKPIT_SWAY_SMOOTH, 0.0, 1.0))

	# A completely locked first-person view with no cockpit interior gives the
	# eye nothing to read rotation from, so a small translational bob rides
	# alongside the existing rotational sway.
	var bob := Vector3(
		sin(_idle_time * TAU * 0.9) * COCKPIT_BOB, cos(_idle_time * TAU * 0.6) * COCKPIT_BOB * 0.6, 0.0
	)
	# No room to pull back from the pilot's seat, so the cockpit zooms through
	# FOV alone.
	camera.fov = base_fov + ZOOM_FOV * minf(zoom_extra(), 1.0)
	_apply_head(deg_to_rad(look_yaw + _sway.x), deg_to_rad(look_pitch + _sway.y))
	_relax_freelook(delta)


func _update_chase(delta: float) -> void:
	var ship_x := _ship_xform()
	var speed_fraction := 0.0
	if model != null and model.top_speed > 0.0:
		speed_fraction = clampf(absf(model.forward_speed()) / model.top_speed, 0.0, 1.0)

	var dt := _dt
	# ACTION is the same camera pulled in tight and low, reacting faster.
	var action := mode == Mode.ACTION
	var ooc := model != null and model.out_of_control
	_ooc_blend = move_toward(
		_ooc_blend, 1.0 if ooc else 0.0, dt / (OOC_BLEND_IN if ooc else OOC_BLEND_OUT)
	)
	_update_anchor(ship_x.origin)

	# ── OOC camera hold ──────────────────────────────────────────────────────
	# When the player opts into this mode, freeze the camera while the ship is
	# tumbling out of control, and the hull drifts away from frame. It no longer
	# snaps back when control returns: the normal smoothing below eases it in.
	if ooc_camera_hold and ooc:
		_apply_head(deg_to_rad(look_yaw), deg_to_rad(look_pitch))
		return
	# ─────────────────────────────────────────────────────────────────────────

	# The frame the offset and aim are built from: the hull's own orientation,
	# except mid-tumble, where it only drifts (see [member _ref_quat]).
	var ship_q := _follow_quat(ship_x.basis.get_rotation_quaternion())
	if _snap:
		_ref_quat = ship_q
	else:
		var follow := JuiceSettings.cam_follow_rate * (1.6 if action else 1.0)
		var tumble := _ooc_blend
		if follow_dir.is_valid():
			# A profile's frame is already steady; it sets its own pace.
			follow = follow_dir_rate
			tumble = 0.0
		var ref_rate := lerpf(follow, REF_OOC_RATE, tumble)
		_ref_quat = _turn_ref(ship_q, 1.0 - exp(-ref_rate * dt), dt)
	var ref := Basis(_ref_quat)

	_update_bank_and_lag(dt)
	_update_turn(dt)
	# Eased both ways now. The release used to snap forward instantly, and that
	# is exactly the kind of forced camera jump that reads as jank.
	var boosting_now := model != null and model.command.boost
	var boost_goal := 1.0 if boosting_now else 0.0
	if _snap:
		_boost_dolly = boost_goal
	else:
		var boost_rate := BOOST_DOLLY_SMOOTH if boosting_now else BOOST_DOLLY_RELEASE_SMOOTH
		_boost_dolly = lerpf(_boost_dolly, boost_goal, 1.0 - exp(-boost_rate * dt))
	var zoom := zoom_extra()
	_update_speed_fov(speed_fraction, dt)
	camera.fov = base_fov + BOOST_DOLLY_FOV * _boost_dolly + ZOOM_FOV * minf(zoom, 1.0) + _speed_fov

	var back := (
		hull_length * CHASE_BACK
		+ hull_radius * (1.0 + speed_fraction * CHASE_SPEED_STRETCH)
		+ hull_length * CHASE_BACK * BOOST_DOLLY_BACK * _boost_dolly
	) * chase_scale
	var up := hull_radius * CHASE_UP + 0.4
	if action:
		back *= ACTION_BACK
		up *= ACTION_UP
	# Swing to the outside of a turn: the ship slides across the frame and the
	# view opens up towards where it is heading.
	var swing := hull_radius * JuiceSettings.cam_turn_swing * (1.3 if action else 1.0)
	var wanted_offset := ref * (_user_basis() * Vector3(_turn.x * swing, up - _turn.y * swing * 0.6, back)) * _user_scale()

	# Aim at a point ahead of the ship, not at the hull. Aiming at the hull puts
	# your own ship in the centre of the screen, which is exactly where the thing
	# you are flying towards needs to be. The lead pulls the aim from the
	# smoothed frame toward where the nose really points, so the view looks
	# into a turn before the frame has caught up with it.
	var nose := -ship_x.basis.z
	var lead := (nose + ref.z) * hull_length * 3.0 * JuiceSettings.cam_turn_lead
	var focus := _anchor - ref.z * (hull_length * 1.5) + lead * (1.0 - _calm())
	# Swung round by the player: the ship is the pivot, so aim at it.
	focus = focus.lerp(_anchor, _user_swing()) + _aim_extra()

	if _snap:
		_chase_offset = wanted_offset
	else:
		var pos_rate := JuiceSettings.cam_position_smooth * (1.5 if action else 1.0)
		_chase_offset = _chase_offset.lerp(
			wanted_offset, 1.0 - exp(-pos_rate * dt)
		)
	# Zoom scales the already-smoothed offset instead of feeding into it, so it
	# moves the camera straight out along its own line to the ship and never
	# fights the follow smoothing above.
	global_position = _anchor + _chase_offset * (1.0 + zoom) * _limit_factor(zoom)

	var wanted_basis := _look_basis(global_position, focus, ref.y)
	# Bank, pitch lag and idle drift ride on top of the aim solve rather than
	# feeding back into it — [FlightCamera]'s own camera-work, kept apart from
	# the shake [Juice] contributes purely on `camera` in [method _apply_head].
	var idle_fade := 1.0 - clampf(speed_fraction * 4.0, 0.0, 1.0)
	var idle_phase := _idle_time * TAU * IDLE_DRIFT_FREQ
	var idle_roll := sin(idle_phase) * IDLE_DRIFT_AMOUNT * idle_fade
	var idle_pitch := cos(idle_phase * 0.7) * IDLE_DRIFT_AMOUNT * idle_fade
	wanted_basis = wanted_basis.rotated(wanted_basis.z, deg_to_rad(_bank + idle_roll))
	wanted_basis = wanted_basis.rotated(wanted_basis.x, deg_to_rad(_pitch_lag + idle_pitch))

	var aimed := wanted_basis
	if not _snap:
		# Slerping the quaternion rather than lerping the basis: a component-wise
		# lerp of two rotations passes through a shear on the way, which shows up
		# as the horizon squashing during hard turns.
		aimed = Basis(global_transform.basis.get_rotation_quaternion().slerp(
			wanted_basis.get_rotation_quaternion(),
			1.0 - exp(-JuiceSettings.cam_aim_smooth * (1.5 if action else 1.0) * _dt)
		))
	global_transform = Transform3D(aimed, global_position)

	_apply_head(deg_to_rad(look_yaw), deg_to_rad(look_pitch))
	_relax_freelook(delta)


## The smoothed turn signal the chase swing reads: x is the yaw rate, y the
## pitch rate, each as a fraction of the hull's top turn rate (left/up
## positive). Eased so a twitchy stick doesn't twitch the camera.
func _update_turn(dt: float) -> void:
	var want := Vector2.ZERO
	if model != null:
		var tr := maxf(model.turn_rate, 0.01)
		want = Vector2(
			clampf(model.angular.y / tr, -1.0, 1.0), clampf(model.angular.x / tr, -1.0, 1.0)
		) * (1.0 - _calm())
	if _snap:
		_turn = want
	else:
		_turn = _turn.lerp(want, 1.0 - exp(-TURN_SMOOTH * dt))


## Ease the speed FOV stretch toward the current speed (see
## [member JuiceSettings.cam_speed_fov]).
func _update_speed_fov(speed_fraction: float, dt: float) -> void:
	var want := speed_fraction * speed_fraction * JuiceSettings.cam_speed_fov
	_speed_fov = want if _snap else lerpf(_speed_fov, want, 1.0 - exp(-SPEED_FOV_SMOOTH * dt))


## The CINEMATIC, SIDE and TOP_DOWN views: an offset from the hull in a
## slowly-following frame (the same [member _ref_quat] trick as the chase, but
## much lazier), aimed at a point just ahead of the ship. Like the chase view,
## the smoothing acts on the offset, never on a world position, so speed never
## drags the camera behind.
func _update_follow_view(delta: float) -> void:
	var ship_x := _ship_xform()
	var dt := _dt
	var ooc := model != null and model.out_of_control
	_ooc_blend = move_toward(
		_ooc_blend, 1.0 if ooc else 0.0, dt / (OOC_BLEND_IN if ooc else OOC_BLEND_OUT)
	)
	_update_anchor(ship_x.origin)
	var rate: float = VIEW_FOLLOW_RATE.get(mode, 2.0)
	var ship_q := _follow_quat(ship_x.basis.get_rotation_quaternion())
	if _snap:
		_ref_quat = ship_q
		_cine_t = randf() * TAU
	elif follow_dir.is_valid():
		_ref_quat = _turn_ref(ship_q, 1.0 - exp(-minf(rate, follow_dir_rate) * dt), dt)
	else:
		_ref_quat = _ref_quat.slerp(ship_q, 1.0 - exp(-lerpf(rate, REF_OOC_RATE, _ooc_blend) * dt))
	var ref := Basis(_ref_quat)
	var r := hull_radius
	var l := hull_length
	var offset := Vector3.ZERO
	var focus := _anchor
	var up := ref.y
	match mode:
		Mode.SIDE:
			offset = Vector3(l * 2.4 + r * 1.2, r * 0.45, -l * 0.25)
			focus = _anchor - ref.z * (l * 0.8)
		Mode.TOP_DOWN:
			offset = Vector3(0.0, l * 4.5 + r * 2.5, l * 0.9)
			focus = _anchor - ref.z * (l * 1.4)
			# Nose to the top of the screen.
			up = -ref.z
		_:
			# CINEMATIC: wander round the ship on a slow Lissajous path, never
			# dipping far below it and never parked dead ahead.
			_cine_t += dt * CINE_SPEED
			var yaw := sin(_cine_t) * 2.3
			var lift := 0.28 + 0.22 * sin(_cine_t * 0.61 + 1.0)
			var dir := Vector3(sin(yaw), lift, cos(yaw)).normalized()
			offset = dir * (l * 2.2 + r * 1.6) * (1.0 + 0.25 * sin(_cine_t * 0.43))
			focus = _anchor - ref.z * (l * 0.6)
	offset = ref * (_user_basis() * offset) * chase_scale * _user_scale()
	focus = focus.lerp(_anchor, _user_swing()) + _aim_extra()
	if _snap:
		_chase_offset = offset
	else:
		_chase_offset = _chase_offset.lerp(offset, 1.0 - exp(-rate * 1.2 * dt))
	global_position = _anchor + _chase_offset * (1.0 + zoom_extra()) * _limit_factor(zoom_extra())
	var speed_fraction := 0.0
	if model != null and model.top_speed > 0.0:
		speed_fraction = clampf(absf(model.forward_speed()) / model.top_speed, 0.0, 1.0)
	_update_speed_fov(speed_fraction, dt)
	camera.fov = base_fov + ZOOM_FOV * minf(zoom_extra(), 1.0) + _speed_fov
	var wanted_basis := _look_basis(global_position, focus, up)
	var aimed := wanted_basis
	if not _snap:
		aimed = Basis(global_transform.basis.get_rotation_quaternion().slerp(
			wanted_basis.get_rotation_quaternion(), 1.0 - exp(-JuiceSettings.cam_aim_smooth * dt)
		))
	global_transform = Transform3D(aimed, global_position)
	_apply_head(deg_to_rad(look_yaw), deg_to_rad(look_pitch))
	_relax_freelook(delta)


## Bank into a sustained turn and let the view trail hard pitch, both eased
## independently of the position/aim smoothing above — see `juice-and-more.md`
## §3.6. Reads angular *rate*, the same signal [method _update_cockpit]'s sway
## already uses, so a turn banks the chase view and sways the cockpit view from
## the same physical quantity.
func _update_bank_and_lag(delta: float) -> void:
	var bank_target := 0.0
	var lag_target := 0.0
	if model != null:
		# Faded out mid-tumble: the spin is the hull's, not a turn the pilot is
		# making, and banking with it would just rock the view.
		var steady := 1.0 - _calm()
		bank_target = clampf(
			-model.angular.y / maxf(model.turn_rate, 0.01), -1.0, 1.0
		) * BANK_MAX * JuiceSettings.cam_bank_mult * (1.5 if mode == Mode.ACTION else 1.0) * steady
		lag_target = clampf(
			-model.angular.x / maxf(model.turn_rate, 0.01), -1.0, 1.0
		) * PITCH_LAG_MAX * steady
	if _snap:
		_bank = bank_target
		_pitch_lag = lag_target
	else:
		_bank = lerpf(_bank, bank_target, clampf(delta * BANK_SMOOTH, 0.0, 1.0))
		_pitch_lag = lerpf(_pitch_lag, lag_target, clampf(delta * PITCH_LAG_SMOOTH, 0.0, 1.0))


## Advance the dynamic zoom: hold, then slide the target back to 0, with
## [member _zoom] spring-following it (see [member _zoom]'s doc comment).
func _update_zoom(dt: float) -> void:
	# The held pull-out: out a little quicker than it comes back in.
	var held_rate := 3.0 if _held_zoom_target > _held_zoom else 1.8
	_held_zoom = lerpf(_held_zoom, _held_zoom_target, 1.0 - exp(-held_rate * dt))
	if _zoom_hold > 0.0:
		_zoom_hold -= dt
	else:
		_zoom_target = move_toward(
			_zoom_target, 0.0, dt / maxf(JuiceSettings.cam_zoom_return_time, 0.05)
		)
	var going_out := _zoom_target > _zoom
	var smooth_time := JuiceSettings.cam_zoom_out_time if going_out else JuiceSettings.cam_zoom_return_time * 0.35
	_zoom = _smooth_damp(_zoom, _zoom_target, smooth_time, dt)
	_zoom_scale = lerpf(
		_zoom_scale, ZOOM_MASSIVE_SCALE if _zoom_massive else 1.0, 1.0 - exp(-3.0 * dt)
	)
	if _zoom_massive and _zoom_target <= 0.0 and _zoom < 0.02:
		_zoom_massive = false


## Critically damped spring toward [param target] (Game Programming Gems 4,
## "Critically Damped Ease-In/Ease-Out Smoothing"): no overshoot, and the
## velocity in [member _zoom_vel] carries over, so a target that changes
## direction mid-move bends the motion rather than kinking it.
func _smooth_damp(current: float, target: float, smooth_time: float, dt: float) -> float:
	var omega := 2.0 / maxf(smooth_time, 0.01)
	var x := omega * dt
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (_zoom_vel + omega * change) * dt
	_zoom_vel = (_zoom_vel - omega * temp) * decay
	return target + (change + temp) * decay


## The ship's transform as it is drawn this frame. With physics interpolation
## on ([member PerformanceSettings.physics_interpolation]), the hull is drawn
## between its last two physics ticks, not at the latest one. Following the
## raw [member Node3D.global_transform] then puts the camera up to a tick
## ahead of what is on screen, which shakes the ship in frame. Returns the raw
## transform when interpolation is off.
func _ship_xform() -> Transform3D:
	return ship.get_global_transform_interpolated()


## Place the follow point for this render frame (see [member _anchor]).
func _update_anchor(ship_pos: Vector3) -> void:
	if _snap:
		_knock_reset = true
		_knock_lag = Vector3.ZERO
		_knock_lag_prev = Vector3.ZERO
	# The lag only updates on physics ticks, so blend between its last two
	# values the same way the ship's own transform is blended between ticks.
	var lag := _knock_lag
	if is_inside_tree() and get_tree().physics_interpolation:
		lag = _knock_lag_prev.lerp(_knock_lag, Engine.get_physics_interpolation_fraction())
	_anchor = ship_pos - lag


## Grow and heal [member _knock_lag], tick-aligned with the ship's own motion.
## The lag is how far a follower moving at the smoothed velocity [member
## _knock_vel] would have fallen behind: zero once the ship holds any steady
## velocity, non-zero only while the velocity is changing abruptly.
func _physics_process(delta: float) -> void:
	if model == null:
		return
	var vel := model.velocity
	_knock_lag_prev = _knock_lag
	if _knock_reset:
		_knock_reset = false
		_knock_vel = vel
		_knock_lag = Vector3.ZERO
		_knock_lag_prev = Vector3.ZERO
		return
	_knock_vel = _knock_vel.lerp(vel, 1.0 - exp(-ANCHOR_VEL_RATE * delta))
	_knock_lag += (vel - _knock_vel) * delta
	_knock_lag = _knock_lag.lerp(Vector3.ZERO, 1.0 - exp(-ANCHOR_POS_RATE * delta))
	_knock_lag = _knock_lag.limit_length(hull_radius * ANCHOR_MAX_ERROR)


func _update_orbit(delta: float) -> void:
	var centre := _ship_xform().origin
	# Orbit angles are in world space, not ship space, so the external view holds
	# still while the ship rotates inside it. That is the point of the view.
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * _orbit_distance
	var wanted := centre + offset
	var here := wanted if _snap else global_position.lerp(
		wanted, clampf(delta * 8.0, 0.0, 1.0)
	)
	global_transform = Transform3D(_look_basis(here, centre, Vector3.UP), here)


## The body the planet view orbits: the nearest one to the ship, by surface
## distance. Re-evaluated every frame, so flying near a moon swings the view
## onto it.
func _planet_target() -> GravitySystem.GravityBody:
	if gravity == null or ship == null:
		return null
	return gravity.nearest_body(ship.global_position)


## The planet view: the ORBIT view, but centred on the nearest body instead of
## the ship, at a distance scaled to the body so a moon and a gas giant both
## frame sensibly. The ship stays visible as the thing flying around the body.
func _update_planet(delta: float) -> void:
	var body := _planet_target()
	if body == null:
		_update_orbit(delta)
		return
	var centre := body.position
	if _snap:
		_orbit_distance = body.radius * PLANET_DIST_SCALE
	_orbit_distance = clampf(
		_orbit_distance,
		body.radius * PLANET_ZOOM_MIN, body.radius * PLANET_ZOOM_MAX
	)
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * _orbit_distance
	var wanted := centre + offset
	var here := wanted if _snap else global_position.lerp(
		wanted, clampf(delta * 8.0, 0.0, 1.0)
	)
	global_transform = Transform3D(_look_basis(here, centre, Vector3.UP), here)


## Point the TARGET camera at a specific ship (arena focus). Pass null to go
## back to orbiting [member target_centre] (the free pan).
func set_focus(node: Node3D) -> void:
	focus_node = node
	if mode != Mode.TARGET:
		set_mode(Mode.TARGET)
	else:
		# Already in TARGET — set_mode early-returns, so snap by hand so the view
		# jumps to the new target instead of lingering on the old orbit.
		_snap = true


## Set the TARGET camera's fallback orbit centre (used when nothing is focused).
func set_target_centre(centre: Vector3) -> void:
	target_centre = centre


## Pan the free arena camera: move the orbit centre in the view plane. Only
## active while nothing is focused.
func pan_world(delta_move: Vector3) -> void:
	if focus_node != null:
		return
	target_centre += delta_move


## The arena camera: orbit whatever is focused (a ship) or the arena centre (free
## pan), at an orbit distance large enough to frame the whole box.
func _update_target(delta: float) -> void:
	var centre := focus_node.get_global_transform_interpolated().origin if focus_node != null else target_centre
	if _snap:
		# Close in on a focused ship; the free pan frames the whole arena.
		_orbit_distance = 500.0 if focus_node != null else 3500.0
	_orbit_distance = clampf(_orbit_distance, ORBIT_MIN_DIST, TARGET_MAX_DIST)
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * _orbit_distance
	var wanted := centre + offset
	var here := wanted if _snap else global_position.lerp(
		wanted, clampf(delta * 8.0, 0.0, 1.0)
	)
	global_transform = Transform3D(_look_basis(here, centre, Vector3.UP), here)


## The FREE view: an orbit camera whose centre starts on the player's ship and
## follows it until the player pans away. Same orbit machinery as TARGET, but
## framed close enough to read the hull instead of the whole arena.
func _update_free(delta: float) -> void:
	if _free_follow and ship != null:
		target_centre = _ship_xform().origin
	if _snap:
		# Close enough to see the hull and a margin, not so tight that the view
		# is inside it.
		_orbit_distance = hull_length * 6.0
	_orbit_distance = clampf(_orbit_distance, ORBIT_MIN_DIST, far_max_dist)
	var centre := target_centre
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * _orbit_distance
	var wanted := centre + offset
	var here := wanted if _snap else global_position.lerp(
		wanted, clampf(delta * 8.0, 0.0, 1.0)
	)
	global_transform = Transform3D(_look_basis(here, centre, Vector3.UP), here)


## Pan the FREE view's centre in the camera's view plane, scaled by the orbit
## distance so the drag feels constant on screen no matter how far out the view
## is. Detaches the centre from the player ship — [method recentre] brings it
## back.
func pan_from_screen(delta_px: Vector2) -> void:
	if focus_node != null:
		return
	var cam := camera
	if cam == null:
		return
	# A pixel drag maps to world metres through the current view frustum: two
	# radians of view across the screen's height, at the orbit distance.
	var viewport_h := maxf(cam.get_viewport().get_visible_rect().size.y, 1.0)
	var metres_per_px := 2.0 * _orbit_distance * tan(deg_to_rad(cam.fov) * 0.5) / viewport_h
	var basis := cam.global_transform.basis
	var move := (-basis.x * delta_px.x + basis.y * delta_px.y) * metres_per_px
	pan_world(move)
	_free_follow = false


## Re-centre the FREE view on the player's ship and resume tracking it. No-op
## outside FREE mode.
func recentre() -> void:
	if mode != Mode.FREE:
		return
	_free_follow = true
	_snap = true


## Live far-clip override, driven by the settings panel. Raised from the 16 km
## default so planets keep rendering long after ships have despawned.
func set_far_clip(distance: float) -> void:
	camera.far = maxf(distance, 1000.0)


## Live "how far out the FAR view can pull" override, driven by the settings
## panel. The current orbit distance is left alone; only the ceiling changes.
func set_far_view_max(distance: float) -> void:
	far_max_dist = maxf(distance, FAR_MIN_DIST)


## A camera ahead of the ship looking back down the ship's own length: you see
## the hull and everything behind you — where you just came from — without
## turning the nose around. Rigidly tracks the hull like the cockpit view, with
## the same small free-look offsets.
func _update_rear(delta: float) -> void:
	var ship_x := _ship_xform()
	# "Behind" is +basis.z (forward is -z), so push the camera forward of the
	# ship and look back along the hull.
	var wanted_pos := ship_x.origin + ship_x.basis * Vector3(0.0, hull_radius * REAR_UP + 0.4, hull_length * -REAR_BACK)
	_update_anchor(ship_x.origin)
	if _snap:
		_chase_offset = wanted_pos - ship_x.origin
	else:
		_chase_offset = _chase_offset.lerp(
			wanted_pos - ship_x.origin, 1.0 - exp(-CHASE_POSITION_SMOOTH * _dt)
		)
	global_position = _anchor + _chase_offset * (1.0 + zoom_extra()) * _limit_factor(zoom_extra())
	var focus := ship_x.origin + ship_x.basis.z * (hull_length * 3.0)
	var wanted_basis := _look_basis(global_position, focus, ship_x.basis.y)
	var aimed := wanted_basis
	if not _snap:
		aimed = Basis(global_transform.basis.get_rotation_quaternion().slerp(
			wanted_basis.get_rotation_quaternion(),
			1.0 - exp(-CHASE_AIM_SMOOTH * _dt)
		))
	global_transform = Transform3D(aimed, global_position)
	_apply_head(deg_to_rad(look_yaw), deg_to_rad(look_pitch))
	_relax_freelook(delta)


## Rotate the camera inside the rig. The rig holds the flight-derived transform
## and the camera holds the head turn, so free look never feeds back into the
## smoothing that produced the rig.
##
## This is also where [Juice] screen shake/kick lands — see the class doc
## comment. Every weapon fire and hit already calls [method Juice.kick] /
## [method Juice.shake]; nothing previously read the trauma model back, so
## the recoil kick and hit reactions existed but were never actually visible.
## Landing it here, on the camera child rather than the rig itself, keeps it
## out of [member _chase_offset]/aim smoothing entirely — a shake never feeds
## back into next frame's position or aim solve.
func _apply_head(yaw_rad: float, pitch_rad: float) -> void:
	var basis := Basis()
	basis = basis.rotated(Vector3.UP, yaw_rad)
	basis = basis.rotated(basis * Vector3.RIGHT, pitch_rad)
	var shake_rot := Juice.shake_rotation_3d()
	basis = basis.rotated(Vector3.UP, shake_rot.y)
	basis = basis.rotated(basis * Vector3.RIGHT, shake_rot.x)
	basis = basis.rotated(basis * Vector3.FORWARD, shake_rot.z)
	var local_shake := global_transform.basis.inverse() * Juice.shake_offset_3d()
	camera.transform = Transform3D(basis, local_shake)


## Let go of the stick and the view drifts back to centre. Without this the
## player can lose the forward view and have no obvious way to find it again.
func _relax_freelook(delta: float) -> void:
	if _looking:
		return
	var t := clampf(delta * FREELOOK_RETURN, 0.0, 1.0)
	look_yaw = lerpf(look_yaw, 0.0, t)
	look_pitch = lerpf(look_pitch, 0.0, t)


## [method Basis.looking_at] without its degenerate cases: when the ship is
## rolled so that its up vector lines up with the view direction, an arbitrary
## fallback beats a printed error and an identity basis.
static func _look_basis(from: Vector3, to: Vector3, up: Vector3) -> Basis:
	var dir := to - from
	if dir.length_squared() < 1e-8:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var safe_up := up
	if absf(safe_up.dot(dir)) > 0.999:
		safe_up = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	return Basis.looking_at(dir, safe_up)
