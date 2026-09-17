## Pirate Raid: raiders intercepting a heavy cargo transport.
##
## Multiple pirate craft swarm around a slow hauler. Ramming or destroying
## the raiders scatters the ambush.
class_name PirateRaidIncident
extends Incident

var hauler_node: Node3D = null
var pirate_nodes: Array[Node3D] = []
var hauler_body: PhysBody = null
var pirate_bodies: Array[PhysBody] = []

var hauler_hp := 300.0
var pirates_remaining := 2


func _init() -> void:
	incident_type = "pirate_raid"
	title = "PIRATE AMBUSH"
	subtitle = "Raiders attacking cargo hauler"
	symbol = "🎯"
	marker_color = Color(1.0, 0.13, 0.0)
	pulse_marker = false
	lifetime = 90.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	# Heavy hauler node
	hauler_node = Node3D.new()
	hauler_node.name = "CargoHauler"
	hauler_node.position = spawn_pos
	actors.append(hauler_node)

	if context != null and context.phys != null:
		hauler_body = PhysBody.new()
		hauler_body.node = hauler_node
		hauler_body.mass = 120.0
		hauler_body.radius = 12.0
		hauler_body.velocity = player_vel * 0.3 + Vector3(10.0, 0.0, 5.0)
		hauler_body.layer = PhysBody.Layer.SHIP
		context.phys.add(hauler_body)
		phys_bodies.append(hauler_body)

	# 2 Pirate raiders
	var offsets := [Vector3(-70.0, 15.0, 40.0), Vector3(60.0, -20.0, -50.0)]
	for i in 2:
		var p_node := Node3D.new()
		p_node.name = "Pirate_%d" % i
		p_node.position = spawn_pos + offsets[i]
		actors.append(p_node)
		pirate_nodes.append(p_node)

		if context != null and context.phys != null:
			var p_body := PhysBody.new()
			p_body.node = p_node
			p_body.mass = 18.0
			p_body.radius = 4.0
			p_body.velocity = player_vel * 0.4 + Vector3(randf_range(-15.0, 15.0), 0.0, randf_range(-15.0, 15.0))
			p_body.layer = PhysBody.Layer.SHIP
			context.phys.add(p_body)
			phys_bodies.append(p_body)
			pirate_bodies.append(p_body)


func tick(delta: float) -> void:
	super.tick(delta)
	if is_resolved:
		return

	if hauler_hp > 0 and pirates_remaining > 0:
		hauler_hp -= delta * (pirates_remaining * 4.0)
		if hauler_hp <= 0.0:
			resolve("hauler_destroyed")


func on_impact(body_a: PhysBody, body_b: PhysBody, impulse: float) -> void:
	for body in pirate_bodies:
		if body_a == body or body_b == body:
			pirates_remaining -= 1
			if pirates_remaining <= 0:
				resolve("pirates_routed", body_a.node if body_a != body else body_b.node)
			break
