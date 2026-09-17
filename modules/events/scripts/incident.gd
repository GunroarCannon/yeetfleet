## Base class for all dynamic in-world incidents.
##
## An incident is a physical arrangement of bodies in space (ships, debris,
## asteroids) that presents an emergent situation to the player. It has no
## quest log or dialogue trees — it lives in the simulation, ticks each frame,
## and resolves itself if ignored or interacted with.
##
## Emits [signal completed] when resolved, which the director routes to M5
## (reputation & faction memory).
class_name Incident
extends RefCounted

# --- Signals ----------------------------------------------------------------

signal completed(incident_id: String, how: String, who: Variant)

# --- State ------------------------------------------------------------------

var id: String = ""
var incident_type: String = "generic"
var title: String = "INCIDENT DETECTED"
var subtitle: String = ""
var symbol: String = "!"
var marker_color := Color.WHITE
var pulse_marker := false

var origin := Vector3.ZERO
var lifetime := 90.0
var elapsed_time := 0.0
var is_resolved := false
var resolution_reason := ""

var marker: WorldMarker = null
var actors: Array[Node3D] = []
var phys_bodies: Array[PhysBody] = []

var _context: NebulaContext = null


# --- Lifecycle Interface ----------------------------------------------------

## Called when the incident is instantiated and placed in the world.
func setup(context: NebulaContext, spawn_pos: Vector3, player_vel: Vector3) -> void:
	_context = context
	origin = spawn_pos
	elapsed_time = 0.0
	is_resolved = false
	if id.is_empty():
		id = "%s_%d" % [incident_type, Time.get_ticks_msec()]


## Called each frame by the IncidentDirector.
func tick(delta: float) -> void:
	if is_resolved:
		return

	elapsed_time += delta
	if elapsed_time >= lifetime:
		resolve("expired")


## Whether the incident has finished and can be removed from active pool.
func is_done() -> bool:
	return is_resolved


## Mark the incident as resolved with a cause.
func resolve(how: String, who: Variant = null) -> void:
	if is_resolved:
		return
	is_resolved = true
	resolution_reason = how
	completed.emit(id, how, who)
	cleanup()


## Tear down actors, markers, and physics bodies.
func cleanup() -> void:
	if is_instance_valid(marker):
		marker.queue_free()
		marker = null

	for body in phys_bodies:
		if _context != null and _context.phys != null:
			_context.phys.remove(body)
	phys_bodies.clear()

	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()


# --- Event Callbacks --------------------------------------------------------

## Optional hook called when an impact occurs involving any of this incident's bodies.
func on_impact(_body_a: PhysBody, _body_b: PhysBody, _impulse: float) -> void:
	pass


## Optional hook called when a touchable object from this incident is collected or linked.
func on_touch(_item_type: String, _collector: PhysBody) -> void:
	pass


# --- Helpers ----------------------------------------------------------------

## Attach a 3D billboard marker to an actor node or position.
func create_marker(parent_node: Node, target: Node3D = null) -> WorldMarker:
	if marker != null:
		return marker

	marker = WorldMarker.new()
	marker.symbol = symbol
	marker.marker_color = marker_color
	marker.pulse = pulse_marker
	marker.target_node = target
	if target == null:
		marker.global_position = origin

	if parent_node != null:
		parent_node.add_child(marker)

	return marker
