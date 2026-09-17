## Faction Skirmish: two opposing faction patrols engaged in combat.
##
## Navy / Syndicate / Outlaw craft maneuvering and dogfighting in space.
## The player can watch the combat or intervene to change the outcome.
class_name FactionSkirmishIncident
extends Incident

var faction_a_nodes: Array[Node3D] = []
var faction_b_nodes: Array[Node3D] = []
var faction_a_bodies: Array[PhysBody] = []
var faction_b_bodies: Array[PhysBody] = []

var faction_a_remaining := 2
var faction_b_remaining := 2


func _init() -> void:
	incident_type = "faction_skirmish"
	title = "FACTION SKIRMISH"
	subtitle = "Hostile patrols in combat"
	symbol = "🎯"
	marker_color = Color(1.0, 0.15, 0.2)
	pulse_marker = false
	lifetime = 90.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	# Faction A ships
	for i in 2:
		var node_a := Node3D.new()
		node_a.name = "FactionA_Ship_%d" % i
		node_a.position = spawn_pos + Vector3(-60.0 + i * 25.0, 0.0, -30.0 + i * 15.0)
		actors.append(node_a)
		faction_a_nodes.append(node_a)

		if context != null and context.phys != null:
			var body_a := PhysBody.new()
			body_a.node = node_a
			body_a.mass = 22.0
			body_a.radius = 4.5
			body_a.velocity = player_vel * 0.4 + Vector3(15.0, randf_range(-5.0, 5.0), 0.0)
			body_a.faction_id = 1
			body_a.layer = PhysBody.Layer.SHIP
			context.phys.add(body_a)
			phys_bodies.append(body_a)
			faction_a_bodies.append(body_a)

	# Faction B ships
	for i in 2:
		var node_b := Node3D.new()
		node_b.name = "FactionB_Ship_%d" % i
		node_b.position = spawn_pos + Vector3(60.0 - i * 25.0, 10.0, 30.0 - i * 15.0)
		actors.append(node_b)
		faction_b_nodes.append(node_b)

		if context != null and context.phys != null:
			var body_b := PhysBody.new()
			body_b.node = node_b
			body_b.mass = 22.0
			body_b.radius = 4.5
			body_b.velocity = player_vel * 0.4 + Vector3(-15.0, randf_range(-5.0, 5.0), 0.0)
			body_b.faction_id = 2
			body_b.layer = PhysBody.Layer.SHIP
			context.phys.add(body_b)
			phys_bodies.append(body_b)
			faction_b_bodies.append(body_b)


func on_impact(body_a: PhysBody, body_b: PhysBody, _impulse: float) -> void:
	for body in faction_a_bodies:
		if body_a == body or body_b == body:
			faction_a_remaining -= 1
			if faction_a_remaining <= 0:
				resolve("faction_b_won", body_a.node if body_a != body else body_b.node)
			return

	for body in faction_b_bodies:
		if body_a == body or body_b == body:
			faction_b_remaining -= 1
			if faction_b_remaining <= 0:
				resolve("faction_a_won", body_a.node if body_a != body else body_b.node)
			return
