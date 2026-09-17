## Cargo Request: a merchant or transport ship awaiting supplies or transfer.
##
## Touching or bumping the ship with a cargo container satisfies the transfer
## via the M2 bump-to-interact system (cargo_attach).
class_name CargoRequestIncident
extends Incident

var ship_node: Node3D = null
var ship_body: PhysBody = null


func _init() -> void:
	incident_type = "cargo_request"
	title = "CARGO REQUEST"
	subtitle = "Supply vessel awaiting transfer"
	symbol = "📦"
	marker_color = Color(0.0, 0.9, 1.0)
	pulse_marker = false
	lifetime = 100.0


func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	super.setup(context, spawn_pos, player_vel)

	ship_node = Node3D.new()
	ship_node.name = "CargoRequestShip"
	ship_node.position = spawn_pos
	actors.append(ship_node)

	if context != null and context.phys != null:
		ship_body = PhysBody.new()
		ship_body.node = ship_node
		ship_body.mass = 60.0
		ship_body.radius = 7.0
		ship_body.velocity = player_vel * 0.5 + Vector3(3.0, 0.0, 2.0)
		ship_body.layer = PhysBody.Layer.SHIP
		context.phys.add(ship_body)
		phys_bodies.append(ship_body)


func on_impact(body_a: PhysBody, body_b: PhysBody, impulse: float) -> void:
	# Bumping or docking with the ship
	if body_a == ship_body or body_b == ship_body:
		if impulse > 5.0:
			resolve("delivered", body_a.node if body_a != ship_body else body_b.node)


func on_touch(item_type: String, collector: PhysBody) -> void:
	if item_type == "cargo":
		resolve("cargo_attached", collector.node if collector != null else null)
