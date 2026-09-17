## Derelict Tumble: an abandoned, powered-down ship drifting with salvageable crates.
##
## The hull has residual angular velocity and tumbles through space. Crates
## floating near it can be collected by flying through them (bump-to-interact).
class_name DerelictTumbleIncident
extends Incident

var derelict_node: Node3D = null
var crate_nodes: Array[Node3D] = []
var derelict_body: PhysBody = null
var crate_bodies: Array[PhysBody] = []

var crates_total := 3
var crates_collected := 0


func _init() -> void:
	incident_type = "derelict_tumble"
	title = "DERELICT DETECTED"
	subtitle = "Abandoned hull drifting with salvage"
	symbol = "!"
	marker_color = Color(1.0, 0.67, 0.0)
	pulse_marker = true
	lifetime = 120.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	# Tumbling derelict hull
	derelict_node = Node3D.new()
	derelict_node.name = "DerelictHull"
	derelict_node.position = spawn_pos
	actors.append(derelict_node)

	if context != null and context.phys != null:
		derelict_body = PhysBody.new()
		derelict_body.node = derelict_node
		derelict_body.mass = 50.0
		derelict_body.radius = 8.0
		derelict_body.velocity = player_vel * 0.2 + Vector3(-2.0, 1.0, 3.0)
		derelict_body.angular = Vector3(0.5, 1.2, -0.4) # Fast tumble
		derelict_body.layer = PhysBody.Layer.DEBRIS
		context.phys.add(derelict_body)
		phys_bodies.append(derelict_body)

	# 3 Floating crates around the derelict
	var crate_offsets := [
		Vector3(15.0, 8.0, 12.0),
		Vector3(-20.0, -5.0, 10.0),
		Vector3(5.0, 18.0, -15.0)
	]
	for i in crates_total:
		var c_node := Node3D.new()
		c_node.name = "SalvageCrate_%d" % i
		c_node.position = spawn_pos + crate_offsets[i]
		actors.append(c_node)
		crate_nodes.append(c_node)

		if context != null and context.phys != null:
			var c_body := PhysBody.new()
			c_body.node = c_node
			c_body.mass = 2.0
			c_body.radius = 1.5
			c_body.velocity = derelict_body.velocity + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			c_body.layer = PhysBody.Layer.PICKUP
			context.phys.add(c_body)
			phys_bodies.append(c_body)
			crate_bodies.append(c_body)


func on_touch(item_type: String, _collector: PhysBody) -> void:
	if item_type == "pickup" or item_type == "crate":
		crates_collected += 1
		if crates_collected >= crates_total:
			resolve("salvaged")


func on_impact(body_a: PhysBody, body_b: PhysBody, _impulse: float) -> void:
	# Bumping into crates collects them
	for body in crate_bodies:
		if body_a == body or body_b == body:
			crates_collected += 1
			if is_instance_valid(body.node):
				body.node.visible = false
			if crates_collected >= crates_total:
				resolve("salvaged", body_a.node if body_a != body else body_b.node)
			break
