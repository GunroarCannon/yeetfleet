## Distress Call: a damaged civilian ship under attack by a hostile raider.
##
## The victim spins with disabled engines while the raider strafes. If the
## player destroys or rams the raider, the civilian escapes. If ignored, the
## raider eventually destroys the transport.
class_name DistressCallIncident
extends Incident

var victim_node: Node3D = null
var attacker_node: Node3D = null
var victim_body: PhysBody = null
var attacker_body: PhysBody = null

var victim_hp := 120.0
var attacker_hp := 80.0


func _init() -> void:
	incident_type = "distress_call"
	title = "DISTRESS SIGNAL"
	subtitle = "Civilian craft under attack"
	symbol = "🚨"
	marker_color = Color(1.0, 0.2, 0.27)
	pulse_marker = true
	lifetime = 80.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	# Victim ship node
	victim_node = Node3D.new()
	victim_node.name = "VictimShip"
	victim_node.position = spawn_pos
	actors.append(victim_node)

	# Attacker ship node positioned ~120m off
	attacker_node = Node3D.new()
	attacker_node.name = "PirateAttacker"
	attacker_node.position = spawn_pos + Vector3(80.0, 20.0, 90.0)
	actors.append(attacker_node)

	# Physics bodies
	if context != null and context.phys != null:
		victim_body = PhysBody.new()
		victim_body.node = victim_node
		victim_body.mass = 45.0
		victim_body.radius = 6.0
		victim_body.velocity = player_vel * 0.4 + Vector3(2.0, 0.5, -1.0)
		victim_body.angular = Vector3(0.2, 0.8, 0.1) # Tumble
		victim_body.layer = PhysBody.Layer.SHIP
		context.phys.add(victim_body)
		phys_bodies.append(victim_body)

		attacker_body = PhysBody.new()
		attacker_body.node = attacker_node
		attacker_body.mass = 20.0
		attacker_body.radius = 4.0
		attacker_body.velocity = player_vel * 0.5 + Vector3(-5.0, 1.0, 3.0)
		attacker_body.layer = PhysBody.Layer.SHIP
		context.phys.add(attacker_body)
		phys_bodies.append(attacker_body)


func tick(delta: float) -> void:
	super.tick(delta)
	if is_resolved:
		return

	# Simulation of combat between the two actors
	if attacker_hp > 0 and victim_hp > 0:
		# Attacker slowly damages victim if close
		if victim_node != null and attacker_node != null:
			var pos_a := attacker_node.global_position if attacker_node.is_inside_tree() else attacker_node.position
			var pos_v := victim_node.global_position if victim_node.is_inside_tree() else victim_node.position
			var d := pos_a.distance_to(pos_v)
			if d < 250.0:
				victim_hp -= delta * 3.5
				if victim_hp <= 0.0:
					resolve("victim_destroyed", attacker_node)


func on_impact(body_a: PhysBody, body_b: PhysBody, impulse: float) -> void:
	# Heavy ramming or weapons fire
	if body_a == attacker_body or body_b == attacker_body:
		attacker_hp -= impulse * 0.15
		if attacker_hp <= 0.0:
			resolve("rescued", body_a.node if body_a != attacker_body else body_b.node)
	elif body_a == victim_body or body_b == victim_body:
		victim_hp -= impulse * 0.1
		if victim_hp <= 0.0:
			resolve("victim_destroyed")
