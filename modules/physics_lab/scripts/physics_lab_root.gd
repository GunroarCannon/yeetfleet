## PhysicsLabRoot: the lab scene for tuning collision feel.
##
## A standalone scene for authoring PhysProfile resources. It shows
## one ship, a few rocks, a planet, and sliders for every field in
## PhysProfile. The sliders live-edit a PhysProfile resource, and
## "Save profile as .tres" writes it to disk.
##
## Features:
## - Repeat button: re-runs the exact same impact with current dials
## - Ghost trail: overlay of the previous run
## - Preset scenarios: glancing rock, head-on rock, etc.
##
## Consumes: PhysProfile (edited live)
## Emits: none (standalone tool)

class_name PhysicsLabRoot extends Node3D

# Exported so the lab scene can set it
@export var profile: PhysProfile

# Demo objects
@onready var ship: Node3D = $Ship
@onready var planet: Node3D = $Planet
@onready var rocks: Array[Node3D] = [$Rock1, $Rock2, $Rock3]

# For ghost trail
var _ghost_transforms: Array[Transform3D] = []
const GHOST_FADE_TIME := 2.0
var _ghost_timer := 0.0

func _ready() -> void:
	# Start with the ship and rocks at rest for clean impacts
	ship.global_transform.origin = Vector3(0, 10, 0)
	ship.global_transform.basis = Basis()
	for rock in rocks:
		rock.global_transform.origin = rock.global_transform.origin.snapped(Vector3(1, 0, 0))
		rock.global_transform.basis = Basis()

	# Planet at origin
	planet.global_transform.origin = Vector3.ZERO
	planet.global_transform.basis = Basis()

## Apply the current profile's feel dials onto the lab rig's native bodies. The
## scene sliders live-edit [member profile]; this pushes the changed dials down
## onto the demo bodies' physics materials.
func _apply_profile() -> void:
	if profile == null:
		return
	var ship_body := ship as CollisionObject3D
	if ship_body != null:
		var hull_mat := PhysicsMaterial.new()
		hull_mat.bounce = profile.restitution_ship
		hull_mat.friction = profile.friction
		ship_body.physics_material_override = hull_mat
	for rock in rocks:
		var rock_body := rock as CollisionObject3D
		if rock_body == null:
			continue
		var rock_mat := PhysicsMaterial.new()
		rock_mat.bounce = profile.restitution_rock
		rock_mat.friction = profile.friction
		rock_body.physics_material_override = rock_mat

func _process(delta: float) -> void:
	# Update ghost trail timer
	if _ghost_timer > 0:
		_ghost_timer -= delta
		if _ghost_timer <= 0:
			_ghost_transforms.clear()

func _on_repeat_button_pressed() -> void:
	# Reset to initial state and record ghost
	_forge_ghost()
	_reset_demo()

func _forge_ghost() -> void:
	# Record current transforms for ghost trail
	_ghost_transforms = []
	_ghost_transforms.append(ship.global_transform)
	for rock in rocks:
		_ghost_transforms.append(rock.global_transform)
	_ghost_transforms.append(planet.global_transform)
	_ghost_timer = GHOST_FADE_TIME

func _reset_demo() -> void:
	# Put ship in launch position, rocks in launch positions
	ship.global_transform.origin = Vector3(0, 15, -20)  # Coming in from front-left
	ship.global_transform.basis = Basis().rotated(Vector3.UP, deg_to_rad(15))  # Slight yaw

	# Reset rocks to stationary positions
	var rock_positions = [
		Vector3(5, 0, 0),
		Vector3(-3, 0, 4),
		Vector3(0, 0, -6)
	]
	for i in rocks.size():
		rocks[i].global_transform.origin = rock_positions[i]
		rocks[i].global_transform.basis = Basis()

	# Planet stays at origin
	planet.global_transform.origin = Vector3.ZERO

# GUI signal forwarders (to be connected in scene)
func _on_save_profile_requested() -> void:
	# TODO: Implement save dialog
	pass

func _on_scenario_selected(scenario_name: String) -> void:
	# TODO: Implement preset scenarios
	match scenario_name:
		"glancing rock":
			_setup_glancing_rock()
		"head-on rock":
			_setup_head_on_rock()
		"rock into rock":
			_setup_rock_into_rock()
		"ram a hauler":
			_setup_ram_hauler()
		"scatter a swarm":
			_setup_scatter_swarm()
		"slingshot":
			_setup_slingshot()

func _setup_glancing_rock() -> void:
	# TODO
	pass

func _setup_head_on_rock() -> void:
	# TODO
	pass

func _setup_rock_into_rock() -> void:
	# TODO
	pass

func _setup_ram_hauler() -> void:
	# TODO
	pass

func _setup_scatter_swarm() -> void:
	# TODO
	pass

func _setup_slingshot() -> void:
	# TODO
	pass
