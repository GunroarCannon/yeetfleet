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
}

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
## Set on a mode change so the new view snaps into place instead of flying across
## the scene from wherever the old one was.
var _snap := true
## Whether the FREE view's centre is still tracking the player's ship. A pan sets
## it false; [method recentre] restores it.
var _free_follow := true


func _ready() -> void:
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
	camera.fov = 72.0
	add_child(camera)
	# The rig places itself in world space; being parented under anything that
	# moves would double every motion.
	top_level = true


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
	set_mode((mode + 1) % Mode.size())


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


## Everything runs in _process, not _physics_process: the camera should be as
## smooth as the display, and it only ever reads the ship's state.
func _process(delta: float) -> void:
	if ship == null:
		return
	match mode:
		Mode.COCKPIT:
			_update_cockpit(delta)
		Mode.CHASE:
			_update_chase(delta)
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
	if space != null:
		space.recentre(global_position)


func _update_cockpit(delta: float) -> void:
	var seat := ship.global_transform * eye
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
	_apply_head(deg_to_rad(look_yaw + _sway.x), deg_to_rad(look_pitch + _sway.y))
	_relax_freelook(delta)


func _update_chase(delta: float) -> void:
	var ship_x := ship.global_transform
	var speed_fraction := 0.0
	if model != null and model.top_speed > 0.0:
		speed_fraction = clampf(absf(model.forward_speed()) / model.top_speed, 0.0, 1.0)

	_update_bank_and_lag(delta)
	# Eased on the way in, snapped forward on release — boost is a decision, and
	# the release should read as instant, not as another thing settling.
	var boosting_now := model != null and model.command.boost
	if not boosting_now:
		_boost_dolly = 0.0
	elif _snap:
		_boost_dolly = 1.0
	else:
		_boost_dolly = lerpf(_boost_dolly, 1.0, clampf(delta * BOOST_DOLLY_SMOOTH, 0.0, 1.0))
	camera.fov = BASE_FOV + BOOST_DOLLY_FOV * _boost_dolly

	var back := (
		hull_length * CHASE_BACK
		+ hull_radius * (1.0 + speed_fraction * CHASE_SPEED_STRETCH)
		+ hull_length * CHASE_BACK * BOOST_DOLLY_BACK * _boost_dolly
	)
	var up := hull_radius * CHASE_UP + 0.4
	var wanted_pos := ship_x.origin + ship_x.basis * Vector3(0.0, up, back)

	# Aim at a point ahead of the ship, not at the hull. Aiming at the hull puts
	# your own ship in the centre of the screen, which is exactly where the thing
	# you are flying towards needs to be.
	var focus := ship_x.origin - ship_x.basis.z * (hull_length * 1.5)

	if _snap:
		_chase_offset = wanted_pos - ship_x.origin
	else:
		_chase_offset = _chase_offset.lerp(
			wanted_pos - ship_x.origin, clampf(delta * CHASE_POSITION_SMOOTH, 0.0, 1.0)
		)
	global_position = ship_x.origin + _chase_offset

	var wanted_basis := _look_basis(global_position, focus, ship_x.basis.y)
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
			clampf(delta * CHASE_AIM_SMOOTH, 0.0, 1.0)
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
		bank_target = clampf(
			-model.angular.y / maxf(model.turn_rate, 0.01), -1.0, 1.0
		) * BANK_MAX
		lag_target = clampf(
			-model.angular.x / maxf(model.turn_rate, 0.01), -1.0, 1.0
		) * PITCH_LAG_MAX
	if _snap:
		_bank = bank_target
		_pitch_lag = lag_target
	else:
		_bank = lerpf(_bank, bank_target, clampf(delta * BANK_SMOOTH, 0.0, 1.0))
		_pitch_lag = lerpf(_pitch_lag, lag_target, clampf(delta * PITCH_LAG_SMOOTH, 0.0, 1.0))


func _update_orbit(delta: float) -> void:
	var centre := ship.global_transform.origin
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
	var centre := focus_node.global_position if focus_node != null else target_centre
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
		target_centre = ship.global_transform.origin
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
	var ship_x := ship.global_transform
	# "Behind" is +basis.z (forward is -z), so push the camera forward of the
	# ship and look back along the hull.
	var wanted_pos := ship_x.origin + ship_x.basis * Vector3(0.0, hull_radius * REAR_UP + 0.4, hull_length * -REAR_BACK)
	if _snap:
		_chase_offset = wanted_pos - ship_x.origin
	else:
		_chase_offset = _chase_offset.lerp(
			wanted_pos - ship_x.origin, clampf(delta * CHASE_POSITION_SMOOTH, 0.0, 1.0)
		)
	global_position = ship_x.origin + _chase_offset
	var focus := ship_x.origin + ship_x.basis.z * (hull_length * 3.0)
	var wanted_basis := _look_basis(global_position, focus, ship_x.basis.y)
	var aimed := wanted_basis
	if not _snap:
		aimed = Basis(global_transform.basis.get_rotation_quaternion().slerp(
			wanted_basis.get_rotation_quaternion(),
			clampf(delta * CHASE_AIM_SMOOTH, 0.0, 1.0)
		))
	global_transform = Transform3D(aimed, global_position)
	_apply_head(deg_to_rad(look_yaw), deg_to_rad(look_pitch))
	_relax_freelook(delta)


## Rotate the camera inside the rig. The rig holds the flight-derived transform
## and the camera holds the head turn, so free look never feeds back into the
## smoothing that produced the rig.
func _apply_head(yaw_rad: float, pitch_rad: float) -> void:
	var basis := Basis()
	basis = basis.rotated(Vector3.UP, yaw_rad)
	basis = basis.rotated(basis * Vector3.RIGHT, pitch_rad)
	camera.transform = Transform3D(basis, Vector3.ZERO)


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
