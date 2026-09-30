## IncidentDirector: orchestrates emergent in-world incidents and visual signalling.
##
## Governed by the rules in TECHNICAL_PLAN.md M4 and GAMEDOC.md §8-10:
## - Budget: at most [member max_active_incidents] live at once.
## - Spacing: at most one within [member min_player_dist] of the player.
## - Pacing: minimum [member bubble_cooldown] seconds between HUD blooms.
## - Natural discovery: spawns outside perception cone and drifts in.
## - Auto-resolution: resolves if ignored when player moves beyond range.
##
## Consumes M1 (physics impacts) and M2 (touch interactions), and emits
## [signal incident_resolved] for M5 (reputation & grudges).
class_name IncidentDirector
extends Node

# --- Signals ----------------------------------------------------------------

signal incident_started(incident: Incident)
signal incident_resolved(id: String, how: String, who: Variant)
signal bubble_requested(symbol: String, title: String, subtitle: String, color: Color)

# --- Tunables / Budget ------------------------------------------------------

var max_active_incidents := 3
var min_player_dist := 450.0
var max_player_dist := 1200.0
var min_incident_spacing := 600.0
var despawn_player_dist := 3500.0
var bubble_cooldown := 25.0
var eval_interval := 3.0
var auto_spawn := true
## Player view (not debug): a banner shows the incident's title only, and at
## most one every [constant QUIET_COOLDOWN] seconds.
var quiet := false
const QUIET_COOLDOWN := 60.0

# --- State ------------------------------------------------------------------

var active_incidents: Array[Incident] = []
var context: NebulaContext = null
var world_parent: Node3D = null
var hud_container: Control = null

var _time_since_bubble := 999.0
var _eval_timer := 0.0
var _incident_counter := 0

# --- Incident Catalog -------------------------------------------------------

const INCIDENT_TYPES: Array[String] = [
	"distress_call",
	"pirate_raid",
	"cargo_request",
	"derelict_tumble",
	"meteor_strike",
	"faction_skirmish",
	"rare_drift",
]


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_connect_interact_registry()


func _process(delta: float) -> void:
	step(delta)


## Step the director simulation (can be called manually in headless tests).
func step(delta: float) -> void:
	_time_since_bubble += delta
	_eval_timer += delta

	# Tick active incidents
	var player_pos := _get_player_pos()
	for i in range(active_incidents.size() - 1, -1, -1):
		var inc := active_incidents[i]
		inc.tick(delta)

		# Auto-resolve if player flew far away
		if player_pos.distance_to(inc.origin) > despawn_player_dist:
			inc.resolve("out_of_range")

		if inc.is_done():
			active_incidents.remove_at(i)

	# Periodic evaluation for spawning new incidents
	if auto_spawn and _eval_timer >= eval_interval:
		_eval_timer = 0.0
		_evaluate_spawning()


# --- Spawning & Evaluation --------------------------------------------------

func _evaluate_spawning() -> void:
	if active_incidents.size() >= max_active_incidents:
		return
	if _time_since_bubble < bubble_cooldown:
		return

	var player_pos := _get_player_pos()
	var player_vel := _get_player_vel()

	# Check spacing: avoid crowding existing incidents
	for inc in active_incidents:
		if inc.origin.distance_to(player_pos) < min_incident_spacing:
			return

	# Determine spawn position in front or flanking player trajectory
	var rng := context.rng if context != null and context.rng != null else RandomNumberGenerator.new()
	var forward := player_vel.normalized()
	if forward.length_squared() < 0.1:
		forward = Vector3.FORWARD

	var spread := Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.7, 0.7)).normalized()
	var spawn_dir := (forward * 0.7 + spread * 0.3).normalized()
	var dist := rng.randf_range(min_player_dist, max_player_dist)
	var spawn_pos := player_pos + spawn_dir * dist

	# Pick random type
	var type_index := rng.randi_range(0, INCIDENT_TYPES.size() - 1)
	var type_name := INCIDENT_TYPES[type_index]
	trigger_incident(type_name, spawn_pos)


## Instantiate and launch a specific incident type by name.
func trigger_incident(type_name: String, spawn_pos: Vector3 = Vector3.ZERO) -> Incident:
	var inc := _create_incident_instance(type_name)
	if inc == null:
		return null

	_incident_counter += 1
	inc.id = "%s_%d" % [type_name, _incident_counter]

	var player_pos := _get_player_pos()
	var player_vel := _get_player_vel()
	if spawn_pos == Vector3.ZERO:
		var forward := player_vel.normalized()
		if forward.length_squared() < 0.1:
			forward = Vector3.FORWARD
		spawn_pos = player_pos + forward * 600.0 + Vector3(0.0, 50.0, 0.0)

	inc.setup(context, spawn_pos, player_vel)

	# Wire completion
	inc.completed.connect(_on_incident_completed)

	# Add physical actors to world parent
	if world_parent != null:
		for actor in inc.actors:
			world_parent.add_child(actor)

		# Attach 3D WorldMarker
		var target := inc.actors[0] if not inc.actors.is_empty() else null
		inc.create_marker(world_parent, target)

	active_incidents.append(inc)
	incident_started.emit(inc)

	# Trigger visual HUD bloom (quiet: the title alone, and rarely).
	if not quiet:
		_request_bubble(inc.symbol, inc.title, inc.subtitle, inc.marker_color)
		_time_since_bubble = 0.0
	elif _time_since_bubble >= QUIET_COOLDOWN:
		_request_bubble(inc.symbol, inc.title, "", inc.marker_color)
		_time_since_bubble = 0.0

	return inc


func _create_incident_instance(type_name: String) -> Incident:
	match type_name:
		"distress_call":
			return DistressCallIncident.new()
		"pirate_raid":
			return PirateRaidIncident.new()
		"cargo_request":
			return CargoRequestIncident.new()
		"derelict_tumble":
			return DerelictTumbleIncident.new()
		"meteor_strike":
			return MeteorStrikeIncident.new()
		"faction_skirmish":
			return FactionSkirmishIncident.new()
		"rare_drift":
			return RareDriftIncident.new()
		_:
			return null


func _request_bubble(sym: String, tit: String, sub: String, col: Color) -> void:
	bubble_requested.emit(sym, tit, sub, col)

	if hud_container != null and is_instance_valid(hud_container):
		var bubble := EventBubble.create(sym, tit, sub, col)
		hud_container.add_child(bubble)


# --- Event Handling ---------------------------------------------------------

func _on_incident_completed(id: String, how: String, who: Variant) -> void:
	incident_resolved.emit(id, how, who)


func _connect_interact_registry() -> void:
	# Connect to M2 Touchable / Pickup / Cargo events if available
	var reg := InteractRegistry.instance()
	if reg != null:
		reg.pickup_collected.connect(func(type: String, col: PhysBody) -> void:
			for inc in active_incidents:
				inc.on_touch(type, col)
		)
		reg.cargo_attached.connect(func(type: String, dest: PhysBody) -> void:
			for inc in active_incidents:
				inc.on_touch("cargo", dest)
		)


## Route a physics collision from M1 PhysWorld into active incidents.
func route_impact(body_a: PhysBody, body_b: PhysBody, impulse: float) -> void:
	for inc in active_incidents:
		inc.on_impact(body_a, body_b, impulse)


# --- Queries & Helpers ------------------------------------------------------

func _get_player_pos() -> Vector3:
	if world_parent != null and world_parent.has_node("Model"):
		var m: Node3D = world_parent.get_node("Model")
		return m.global_position
	return Vector3.ZERO


func _get_player_vel() -> Vector3:
	if world_parent != null and world_parent.has_node("Model"):
		var m: Object = world_parent.get_node("Model")
		if "velocity" in m:
			return m.velocity
	return Vector3.ZERO


## Clear and cleanup all active incidents.
func clear_all() -> void:
	for inc in active_incidents:
		inc.resolve("cleared")
	active_incidents.clear()
