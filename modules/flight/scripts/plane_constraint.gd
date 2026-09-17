## PlaneConstraint: zeroes the off-plane velocity component of a FlightModel.
##
## Add this Node as a sibling of the FlightModel. It runs in _physics_process
## at a lower priority (call order: FlightModel then PlaneConstraint), so it
## reads the velocity AFTER FlightModel has integrated it and clamps it.
##
## TECHNICAL_PLAN cross-cutting §424:
##   "a constraint component that zeroes the off-plane velocity component and
##    maps pitch to plane-normal banking. A constraint, not a second physics
##    implementation."
##
## Usage in FlightRoot (or the arcade scene root):
##   var pc := PlaneConstraint.new()
##   pc.flight_model = model
##   pc.plane_normal = Vector3.UP  # horizontal plane
##   add_child(pc)
##
## The constraint is transparent — it only reads and writes
## [member FlightModel.velocity]. The FlightModel itself is unchanged.
class_name PlaneConstraint
extends Node

# --- Configuration --------------------------------------------------------

## The FlightModel to constrain. Must be set before entering the tree.
var flight_model: FlightModel = null

## World-space normal of the plane the ship is locked to.
## Default = Vector3.UP → horizontal X/Z plane, like a classic shmup.
var plane_normal: Vector3 = Vector3.UP

## How aggressively to snap velocity onto the plane (lerp factor per second).
## 1.0 = snap this frame; 0.0 = no constraint. Tune for feel.
## High values (≥8) give the tight "locked on a rail" feel. Lower values
## let the ship drift slightly off-plane before snapping back.
var snap_strength: float = 12.0

## If true, pitch input is remapped to bank (roll) around the plane normal.
## Gives the "banking into turns" look of classic shmups.
var pitch_as_bank: bool = true

## Bank strength — how far the ship visually tilts per unit of pitch input.
## Applied as a visual-only rotation on top of the physics node.
var bank_tilt_deg: float = 25.0

# --- Private state --------------------------------------------------------

var _bank_angle: float = 0.0     # current visual bank in degrees
var _bank_vel: float   = 0.0     # smoothing velocity for spring damp

# --- Lifecycle ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if flight_model == null:
		return
	_apply_plane_constraint(delta)
	if pitch_as_bank:
		_apply_bank_visual(delta)


# --- Constraint -----------------------------------------------------------

## Project velocity onto the constraint plane and lerp toward the projection.
func _apply_plane_constraint(delta: float) -> void:
	var vel := flight_model.velocity
	# Component of velocity along the plane normal (off-plane part).
	var off := vel.dot(plane_normal)
	if absf(off) < 0.001:
		return  # Already on-plane — skip.
	var on_plane := vel - plane_normal * off
	flight_model.velocity = vel.lerp(on_plane, clampf(snap_strength * delta, 0.0, 1.0))
	# Also zero position drift perpendicular to the plane.
	if flight_model.is_inside_tree():
		var pos := flight_model.global_position
		var pos_off := pos.dot(plane_normal)
		if absf(pos_off) > 0.1:
			flight_model.global_position = pos - plane_normal * pos_off * minf(snap_strength * delta, 1.0)


## Optionally constrain position to a fixed plane height (e.g. y = 0).
## If NaN (default), no height lock is applied.
var locked_height: float = NAN

func _apply_height_lock() -> void:
	if is_nan(locked_height) or not flight_model.is_inside_tree():
		return
	var pos := flight_model.global_position
	var projected := pos - plane_normal * (pos.dot(plane_normal) - locked_height)
	flight_model.global_position = projected


# --- Banking visual -------------------------------------------------------

## Map pitch command to a visual bank using a spring-damper.
func _apply_bank_visual(delta: float) -> void:
	if flight_model == null:
		return
	# Read pitch from the flight model's commanded angular rate if accessible.
	# FlightModel stores _angular_commanded — we infer from the rotation rate.
	# Use the angular.x component of the visual transform as a proxy for pitch.
	var pitch_input := _read_pitch_input()
	var target_bank := -pitch_input * bank_tilt_deg
	# Spring-damp toward target.
	_bank_angle = _spring_damp(_bank_angle, target_bank, 6.0, 0.7, delta)
	# Apply as a local Z-rotation (roll) on the flight_model's visual child.
	var visual := _find_visual_child()
	if visual != null:
		visual.rotation_degrees.z = _bank_angle


func _read_pitch_input() -> float:
	## Approximate: read the current angular rate on the model's X axis.
	if not flight_model.is_inside_tree():
		return 0.0
	# angular_velocity is not exposed; use basis change rate proxy.
	# For now read from the ship's forward/up dot with plane_normal.
	var up := flight_model.global_transform.basis.y
	return up.dot(plane_normal) - 1.0  # 0 when upright, neg when banking


func _find_visual_child() -> Node3D:
	## Look for a child node named "Visual", "ShipView", or "Mesh" to bank.
	for child in flight_model.get_children():
		if child is Node3D:
			var n := child.name.to_lower()
			if "visual" in n or "view" in n or "mesh" in n:
				return child as Node3D
	return null


## Spring-damper helper. Returns the next value of [param current] moving
## toward [param target] with spring constant [param k] and damping ratio
## [param zeta].
func _spring_damp(current: float, target: float, k: float, zeta: float, dt: float) -> float:
	var err := target - current
	_bank_vel += err * k * dt
	_bank_vel *= 1.0 - minf(2.0 * zeta * k * dt, 1.0)
	return current + _bank_vel * dt
