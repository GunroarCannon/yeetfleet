## Rare Drift: an exotic mineral deposit or valuable derelict cargo cluster.
##
## Drifts gently through space with the symbol ◆. The player collects it
## simply by flying through it (M2 bump-to-interact).
class_name RareDriftIncident
extends Incident

var crystal_nodes: Array[Node3D] = []
var crystal_bodies: Array[PhysBody] = []

var crystals_total := 3
var crystals_collected := 0


func _init() -> void:
	incident_type = "rare_drift"
	title = "RARE DRIFT DETECTED"
	subtitle = "Valuable mineral cluster in transit"
	symbol = "◆"
	marker_color = Color(1.0, 0.84, 0.0)
	pulse_marker = false
	lifetime = 110.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	var offsets := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(8.0, 4.0, -6.0),
		Vector3(-6.0, -3.0, 7.0)
	]

	for i in crystals_total:
		var node := Node3D.new()
		node.name = "RareCrystal_%d" % i
		node.position = spawn_pos + offsets[i]
		actors.append(node)
		crystal_nodes.append(node)

		if context != null and context.phys != null:
			var body := PhysBody.new()
			body.node = node
			body.mass = 3.0
			body.radius = 2.0
			body.velocity = player_vel * 0.15 + Vector3(randf_range(-2.0, 2.0), 0.5, randf_range(-2.0, 2.0))
			body.layer = PhysBody.Layer.PICKUP
			context.phys.add(body)
			phys_bodies.append(body)
			crystal_bodies.append(body)


func on_touch(item_type: String, _collector: PhysBody) -> void:
	if item_type == "resource" or item_type == "pickup":
		crystals_collected += 1
		if crystals_collected >= crystals_total:
			resolve("collected")


func on_impact(body_a: PhysBody, body_b: PhysBody, _impulse: float) -> void:
	for body in crystal_bodies:
		if body_a == body or body_b == body:
			crystals_collected += 1
			if is_instance_valid(body.node):
				body.node.visible = false
			if crystals_collected >= crystals_total:
				resolve("collected", body_a.node if body_a != body else body_b.node)
			break
