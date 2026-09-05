## Orbit / pan / zoom camera for the builder viewport.
##
## Driven entirely by explicit calls from [BuilderViewport] rather than by reading
## input itself, so the same camera works from mouse, touch, keyboard and the
## on-screen buttons without three copies of the input logic. Everything is
## damped towards a target so a flick of the wheel reads as motion rather than a
## jump — important on a phone where a single pinch is coarse.
class_name OrbitCamera
extends Camera3D

## Degrees. Clamped short of the poles so the horizon never flips.
const PITCH_MIN := -85.0
const PITCH_MAX := 85.0

const DIST_MIN := 0.6
const DIST_MAX := 260.0

## How fast the camera converges on its target, per second. Chosen so a drag feels
## attached to the finger but a zoom still eases.
const SMOOTH := 16.0

## Breathing room left around a framed ship, as a fraction of its own size. Small
## because the fit below is exact: this is margin, not slop to cover a guess.
const FRAME_MARGIN := 1.06

var target := Vector3.ZERO
var distance := 8.0
## Degrees.
var yaw := 34.0
var pitch := 22.0

var _goal_target := Vector3.ZERO
var _goal_distance := 8.0
var _goal_yaw := 34.0
var _goal_pitch := 22.0

## When true the camera keeps turning on its own — used for the idle showcase
## rotation, switched off the moment the player touches anything.
var auto_spin := false
var auto_spin_speed := 6.0

var _snap_next := false


func _ready() -> void:
	_goal_target = target
	_goal_distance = distance
	_goal_yaw = yaw
	_goal_pitch = pitch
	_apply()


func _process(delta: float) -> void:
	if auto_spin:
		_goal_yaw += auto_spin_speed * delta
	var t := 1.0 if _snap_next else clampf(SMOOTH * delta, 0.0, 1.0)
	_snap_next = false
	yaw = lerpf(yaw, _goal_yaw, t)
	pitch = lerpf(pitch, _goal_pitch, t)
	distance = lerpf(distance, _goal_distance, t)
	target = target.lerp(_goal_target, t)
	_apply()


func _apply() -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var offset := Vector3(
		cos(p) * sin(y),
		sin(p),
		cos(p) * cos(y)
	) * distance
	var pos := target + offset
	# look_at fails on a zero-length basis, which happens if distance underflows.
	if pos.distance_to(target) < 0.001:
		pos = target + Vector3(0, 0, 0.01)
	global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP)


# --- Interaction -----------------------------------------------------------

func orbit(delta_px: Vector2, sensitivity := 0.32) -> void:
	auto_spin = false
	_goal_yaw -= delta_px.x * sensitivity
	_goal_pitch = clampf(_goal_pitch + delta_px.y * sensitivity, PITCH_MIN, PITCH_MAX)


## Pan across the view plane. Scaled by distance so the ship appears to move with
## the cursor at any zoom.
func pan(delta_px: Vector2, viewport_height: float) -> void:
	auto_spin = false
	var world_per_px := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / maxf(viewport_height, 1.0)
	var basis := global_transform.basis
	_goal_target -= basis.x * delta_px.x * world_per_px
	_goal_target += basis.y * delta_px.y * world_per_px


## Multiplicative zoom: each step is a proportion of the current distance, so the
## control has the same feel whether framing a greeble or a capital hull.
func zoom(steps: float) -> void:
	auto_spin = false
	_goal_distance = clampf(_goal_distance * pow(0.88, steps), DIST_MIN, DIST_MAX)


func nudge_orbit(yaw_deg: float, pitch_deg: float) -> void:
	auto_spin = false
	_goal_yaw += yaw_deg
	_goal_pitch = clampf(_goal_pitch + pitch_deg, PITCH_MIN, PITCH_MAX)


## Frame an AABB: pull back until the box fits both axes of a viewport of this
## aspect, and no further.
##
## The box is projected onto the camera's own right/up axes rather than reduced to
## its bounding sphere. A sphere is orientation-free and therefore convenient, and
## for ships it is badly wrong: a hull is long, wide and thin, so its diagonal is
## two or three times its height, and framing to the diagonal parks a flat ship in
## the middle of the screen surrounded by nothing. That is tolerable on a desktop
## with room to spare and not tolerable on a phone, where the wasted margin is the
## screen.
func frame(box: AABB, aspect := 1.6, instant := false) -> void:
	auto_spin = false
	if box.size.length() <= 0.0:
		return
	_goal_target = box.get_center()

	# The orbit angles the camera is heading for, not the ones it has: framing
	# during an eased move must aim at where the camera will be.
	var basis := _basis_for(_goal_yaw, _goal_pitch)
	var right := basis.x
	var up := basis.y
	var forward := -basis.z

	var vfov := deg_to_rad(fov)
	var tan_v := maxf(tan(vfov * 0.5), 0.01)
	var tan_h := tan_v * maxf(aspect, 0.05)

	# Solve each of the eight corners exactly. A corner at depth z in front of the
	# camera fits vertically once dist + z >= |corner·up| / tan_v, and the same
	# horizontally; the answer is the largest distance any corner demands.
	#
	# Doing it per corner, rather than from projected half-extents plus the box's
	# half-depth, is the difference between a fit and an over-estimate: the naive
	# version assumes the tallest point of the ship is also its nearest, which for
	# a hull seen from three-quarters it never is, and pushes the camera back far
	# enough to lose half the screen.
	var half := box.size * 0.5
	var needed := DIST_MIN
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(half.x * sx, half.y * sy, half.z * sz)
				var depth := corner.dot(forward)
				needed = maxf(needed, absf(corner.dot(up)) / tan_v - depth)
				needed = maxf(needed, absf(corner.dot(right)) / tan_h - depth)
	_goal_distance = clampf(needed * FRAME_MARGIN, DIST_MIN, DIST_MAX)
	if instant:
		snap()


## The camera basis for a pair of orbit angles, shared by [method frame] and
## [method _apply] so the two can never disagree about where the camera is
## looking from.
func _basis_for(yaw_deg: float, pitch_deg: float) -> Basis:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var offset := Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))
	return Basis.looking_at(-offset, Vector3.UP)


## Skip the easing for the next frame. Used when loading a new design, where
## gliding across the scene would just look like a glitch.
func snap() -> void:
	_snap_next = true
	yaw = _goal_yaw
	pitch = _goal_pitch
	distance = _goal_distance
	target = _goal_target
	_apply()


## Preset viewing angles, for the view buttons and the number keys.
func set_view(view_name: String) -> void:
	auto_spin = false
	match view_name:
		"front":
			_goal_yaw = 180.0
			_goal_pitch = 2.0
		"back":
			_goal_yaw = 0.0
			_goal_pitch = 2.0
		"side":
			_goal_yaw = 90.0
			_goal_pitch = 0.0
		"top":
			_goal_yaw = 180.0
			_goal_pitch = 84.0
		"bottom":
			_goal_yaw = 180.0
			_goal_pitch = -84.0
		_:
			_goal_yaw = 34.0
			_goal_pitch = 22.0


func state() -> Dictionary:
	return {
		"target": _goal_target,
		"distance": _goal_distance,
		"yaw": _goal_yaw,
		"pitch": _goal_pitch,
	}


func restore(s: Dictionary) -> void:
	_goal_target = s.get("target", _goal_target)
	_goal_distance = float(s.get("distance", _goal_distance))
	_goal_yaw = float(s.get("yaw", _goal_yaw))
	_goal_pitch = float(s.get("pitch", _goal_pitch))
