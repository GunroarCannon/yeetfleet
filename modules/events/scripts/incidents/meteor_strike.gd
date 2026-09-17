## Meteor Strike: a high-mass, fast-moving meteoroid hurtling through space.
##
## A heavy asteroid moving at significant velocity. The player can shoot it,
## boost-ram it to deflect its trajectory, or watch it fly past.
class_name MeteorStrikeIncident
extends Incident

var meteor_node: Node3D = null
var meteor_body: PhysBody = null
var initial_trajectory := Vector3.ZERO
var deflected := false


func _init() -> void:
	incident_type = "meteor_strike"
	title = "METEOR INCOMING"
	subtitle = "High-velocity projectile on collision course"
	symbol = "🚨"
	marker_color = Color(1.0, 0.25, 0.1)
	pulse_marker = true
	lifetime = 45.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	meteor_node = Node3D.new()
	meteor_node.name = "MeteorRock"
	meteor_node.position = spawn_pos
	actors.append(meteor_node)

	initial_trajectory = (player_vel.normalized() * 80.0 + Vector3(randf_range(-30.0, 30.0), -20.0, randf_range(-30.0, 30.0)))
	if initial_trajectory.length_squared() < 100.0:
		initial_trajectory = Vector3(60.0, -10.0, 40.0)

	if context != null and context.phys != null:
		meteor_body = PhysBody.new()
		meteor_body.node = meteor_node
		meteor_body.mass = 250.0
		meteor_body.radius = 9.0
		meteor_body.velocity = initial_trajectory
		meteor_body.angular = Vector3(1.0, 0.4, -0.6)
		meteor_body.layer = PhysBody.Layer.ROCK
		context.phys.add(meteor_body)
		phys_bodies.append(meteor_body)


func on_impact(body_a: PhysBody, body_b: PhysBody, impulse: float) -> void:
	if body_a == meteor_body or body_b == meteor_body:
		if impulse > 40.0:
			deflected = true
			resolve("deflected", body_a.node if body_a != meteor_body else body_b.node)
