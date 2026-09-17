## TowLink: creates a soft spring constraint when touching a disabled ship.
##
## Attach to a rescue ship or tow beam. When it touches a disabled ship
## (one with low velocity or disabled PhysBody), it creates a springy
## constraint that allows towing without rigid attachment.
##
## The constraint strength and damping can be tuned for different tow
## behaviors (e.g., stiff for precision, soft for gentle towing).

@tool
class_name TowLink extends Touchable

# Spring constant for the tow constraint (higher = stiffer tow)
@export var spring_constant := 50.0

# Damping constant for the tow constraint (higher = less oscillation)
@export var damping_constant := 5.0

# Maximum tow distance before constraint breaks
@export var max_tow_distance := 15.0

# Minimum relative velocity to consider a ship "disabled" for towing
@export var disabled_velocity_threshold := 2.0

# Reference to the constraint (set when towing active)
var _current_constraint: Node3D = null
var _towed_ship: PhysBody = null

func _ready() -> void:
	pass

func on_touch(other: PhysBody, impulse: float) -> void:
	# Only tow if the other ship appears disabled (low velocity)
	if other.velocity.length() < disabled_velocity_threshold:
		_start_tow(other)
	else:
		# Ship is moving too fast - bounce off instead
		pass

func _exit_tree() -> void:
	# Clean up constraint if we're exiting while towing
	_end_tow()

func _start_tow(other: PhysBody) -> void:
	if _towed_ship != null:
		return  # Already towing something

	_towed_ship = other

	# Report to interaction registry
	var registry := InteractRegistry.instance()
	if registry != null:
		# Get the tower's PhysBody (assuming we're on a ship)
		var tower_body := _phys_body_of_parent()
		if tower_body != null:
			registry.report_tow_started(tower_body, other)

	# In a full implementation, this would:
	# 1. Create a Constraint3D (like a Generic6DOFConstraint or custom spring)
	# 2. Attach it between this ship and the towed ship
	# 3. Configure spring and damping parameters
	# 4. Monitor distance and break if too far

	# For now, we'll just note that we're towing
	print("Started towing %s" % other)

func _end_tow() -> void:
	if _towed_ship == null:
		return

	# Report to interaction registry
	var registry := InteractRegistry.instance()
	if registry != null:
		# Get the tower's PhysBody (assuming we're on a ship)
		var tower_body := _phys_body_of_parent()
		if tower_body != null:
			registry.report_tow_ended(tower_body, _towed_ship)

	# In a full implementation, we'd remove and free the constraint here
	_towed_ship = null
	_current_constraint = null

	print("Ended tow")
