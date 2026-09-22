## TargetLeadReticle: Predictive lead reticle and target lock bracket calculator.
##
## Computes dynamic projectile travel time, relative velocity compensation,
## and renders the predictive lead reticle and lock brackets on HUD overlay.
class_name TargetLeadReticle
extends RefCounted

const RETICLE_RADIUS := 16.0


## Computes the predicted intercept position in 3D world space.
static func calculate_lead_position(
	shooter_pos: Vector3,
	shooter_vel: Vector3,
	target_pos: Vector3,
	target_vel: Vector3,
	projectile_speed: float
) -> Vector3:
	if projectile_speed <= 1.0:
		return target_pos

	var dist := shooter_pos.distance_to(target_pos)
	# First-order time of flight estimate
	var t := dist / projectile_speed

	# Refined quadratic intercept solver:
	# |target_pos + target_rel_vel * t - shooter_pos|^2 = (projectile_speed * t)^2
	var rel_vel := target_vel - shooter_vel
	var diff := target_pos - shooter_pos
	var a := rel_vel.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * diff.dot(rel_vel)
	var c := diff.length_squared()

	var disc := b * b - 4.0 * a * c
	if disc >= 0.0 and absf(a) > 0.001:
		var t1 := (-b - sqrt(disc)) / (2.0 * a)
		var t2 := (-b + sqrt(disc)) / (2.0 * a)
		if t1 > 0.0 and t2 > 0.0:
			t = minf(t1, t2)
		elif t1 > 0.0:
			t = t1
		elif t2 > 0.0:
			t = t2

	return target_pos + rel_vel * t


## Renders the predictive lead reticle on the HUD overlay.
static func draw_lead_reticle(
	overlay: Control,
	camera: Camera3D,
	shooter_pos: Vector3,
	shooter_vel: Vector3,
	target_pos: Vector3,
	target_vel: Vector3,
	projectile_speed: float,
	crosshair_pos: Vector2
) -> void:
	if camera == null or camera.is_position_behind(target_pos):
		return

	var lead_3d := calculate_lead_position(shooter_pos, shooter_vel, target_pos, target_vel, projectile_speed)
	if camera.is_position_behind(lead_3d):
		return

	var lead_2d := camera.unproject_position(lead_3d)
	var target_2d := camera.unproject_position(target_pos)

	# Faint dashed link between current target pos and lead reticle
	overlay.draw_line(target_2d, lead_2d, Color(1.0, 1.0, 1.0, 0.25), 1.0, true)

	# Check if player crosshair is lined up within lead reticle
	var is_aligned := crosshair_pos.distance_to(lead_2d) < RETICLE_RADIUS * 1.5
	var lead_color := Color("46ff9b") if is_aligned else Color("ffb03a")

	# Outer reticle circle
	overlay.draw_arc(lead_2d, RETICLE_RADIUS, 0.0, TAU, 32, lead_color, 1.5, true)
	# Center pip
	overlay.draw_circle(lead_2d, 2.5, lead_color)

	# Cross tick marks
	var tick := 6.0
	overlay.draw_line(lead_2d - Vector2(RETICLE_RADIUS + tick, 0.0), lead_2d - Vector2(RETICLE_RADIUS - 2.0, 0.0), lead_color, 1.5)
	overlay.draw_line(lead_2d + Vector2(RETICLE_RADIUS - 2.0, 0.0), lead_2d + Vector2(RETICLE_RADIUS + tick, 0.0), lead_color, 1.5)
	overlay.draw_line(lead_2d - Vector2(0.0, RETICLE_RADIUS + tick), lead_2d - Vector2(0.0, RETICLE_RADIUS - 2.0), lead_color, 1.5)
	overlay.draw_line(lead_2d + Vector2(0.0, RETICLE_RADIUS - 2.0), lead_2d + Vector2(0.0, RETICLE_RADIUS + tick), lead_color, 1.5)

	if is_aligned:
		# Lock-on confirmation diamond
		var d := RETICLE_RADIUS * 1.35
		var diamond := PackedVector2Array([
			lead_2d + Vector2(0.0, -d),
			lead_2d + Vector2(d, 0.0),
			lead_2d + Vector2(0.0, d),
			lead_2d + Vector2(-d, 0.0)
		])
		overlay.draw_polyline(diamond, Color("46ff9b", 0.7), 1.5, true)
