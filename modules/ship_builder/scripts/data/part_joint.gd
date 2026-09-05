## Articulation limits for a socket.
##
## This is the "joint" of the modular ship system. A part placed in a socket may
## be rotated, slid and scaled inside these bounds. That is what lets a small
## part library produce a large silhouette space: one nacelle mesh becomes a
## swept-out pod, a tucked-in booster or an oversized main drive depending on how
## its joint is posed.
##
## Ranges are (min, max) pairs. A range of (0, 0) means the axis is locked.
class_name PartJoint
extends Resource

## Degrees around the socket's local Y axis (swivel left/right).
@export var yaw_range := Vector2.ZERO
## Degrees around the socket's local X axis (tilt up/down).
@export var pitch_range := Vector2.ZERO
## Degrees around the socket's local Z axis (bank/spin, e.g. wing dihedral).
@export var roll_range := Vector2.ZERO
## Local-space direction the part may slide along. Zero means no sliding.
@export var slide_axis := Vector3.ZERO
## Metres of travel along [member slide_axis], as (min, max).
@export var slide_range := Vector2.ZERO
## Uniform scale multiplier bounds, as (min, max). (1, 1) locks scale.
@export var scale_range := Vector2.ONE
## When a socket is auto-mirrored, negate the yaw pose so the pair stays
## visually symmetric instead of both pods pointing the same way.
@export var mirror_negates_yaw := true

## A joint that allows nothing — the default for rigidly bolted parts.
static func rigid() -> PartJoint:
	return PartJoint.new()


static func from_dict(d: Dictionary) -> PartJoint:
	var j := PartJoint.new()
	j.yaw_range = _v2(d.get("yaw", Vector2.ZERO))
	j.pitch_range = _v2(d.get("pitch", Vector2.ZERO))
	j.roll_range = _v2(d.get("roll", Vector2.ZERO))
	if d.has("slide_axis"):
		var a: Array = d["slide_axis"]
		j.slide_axis = Vector3(a[0], a[1], a[2])
	j.slide_range = _v2(d.get("slide", Vector2.ZERO))
	j.scale_range = _v2(d.get("scale", Vector2.ONE))
	j.mirror_negates_yaw = bool(d.get("mirror_negates_yaw", true))
	return j


static func _v2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func has_yaw() -> bool:
	return not is_equal_approx(yaw_range.x, yaw_range.y)


func has_pitch() -> bool:
	return not is_equal_approx(pitch_range.x, pitch_range.y)


func has_roll() -> bool:
	return not is_equal_approx(roll_range.x, roll_range.y)


func has_slide() -> bool:
	return slide_axis.length_squared() > 0.0001 and not is_equal_approx(slide_range.x, slide_range.y)


func has_scale() -> bool:
	return not is_equal_approx(scale_range.x, scale_range.y)


## True when the joint can be posed at all — used to decide whether the
## inspector shows articulation controls and whether drag-to-articulate works.
func is_articulated() -> bool:
	return has_yaw() or has_pitch() or has_roll() or has_slide() or has_scale()


## A short human-readable description of what this joint permits, shown in the
## inspector so players understand why a part can or cannot be moved.
func describe() -> String:
	var bits: PackedStringArray = []
	if has_yaw():
		bits.append("swivel %d°..%d°" % [yaw_range.x, yaw_range.y])
	if has_pitch():
		bits.append("tilt %d°..%d°" % [pitch_range.x, pitch_range.y])
	if has_roll():
		bits.append("bank %d°..%d°" % [roll_range.x, roll_range.y])
	if has_slide():
		bits.append("slide %.2fm..%.2fm" % [slide_range.x, slide_range.y])
	if has_scale():
		bits.append("scale %.2f..%.2f" % [scale_range.x, scale_range.y])
	if bits.is_empty():
		return "Rigid mount"
	return ", ".join(bits)


## Force a pose dictionary back inside the joint's limits. Mutates and returns
## the dictionary so callers can chain.
func clamp_pose(pose: Dictionary) -> Dictionary:
	pose["yaw"] = clampf(float(pose.get("yaw", 0.0)), min(yaw_range.x, yaw_range.y), max(yaw_range.x, yaw_range.y))
	pose["pitch"] = clampf(float(pose.get("pitch", 0.0)), min(pitch_range.x, pitch_range.y), max(pitch_range.x, pitch_range.y))
	pose["roll"] = clampf(float(pose.get("roll", 0.0)), min(roll_range.x, roll_range.y), max(roll_range.x, roll_range.y))
	pose["slide"] = clampf(float(pose.get("slide", 0.0)), min(slide_range.x, slide_range.y), max(slide_range.x, slide_range.y))
	pose["scale"] = clampf(float(pose.get("scale", 1.0)), min(scale_range.x, scale_range.y), max(scale_range.x, scale_range.y))
	return pose


## Build the local offset transform produced by a pose, relative to the socket.
func pose_transform(pose: Dictionary, mirrored: bool) -> Transform3D:
	var p := clamp_pose(pose.duplicate())
	var yaw := float(p["yaw"])
	if mirrored and mirror_negates_yaw:
		yaw = -yaw
	var roll := float(p["roll"])
	if mirrored:
		roll = -roll
	var basis := Basis.from_euler(Vector3(deg_to_rad(float(p["pitch"])), deg_to_rad(yaw), deg_to_rad(roll)))
	var s := float(p["scale"])
	basis = basis.scaled(Vector3(s, s, s))
	var origin := Vector3.ZERO
	if slide_axis.length_squared() > 0.0001:
		var axis := slide_axis.normalized()
		if mirrored:
			axis.x = -axis.x
		origin = axis * float(p["slide"])
	return Transform3D(basis, origin)
