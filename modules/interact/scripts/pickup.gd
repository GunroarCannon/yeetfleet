## Pickup: touch-to-collect items that scale with ship size.
##
## Examples: resources, fuel, credits, power-ups.
##
## When touched, emits touched() with what set to the pickup type
## (e.g., "fuel", "credits"), allowing collection systems to respond.
##
## The radius scales with the touching ship's size for easier collection
## of larger ships.

@tool
class_name Pickup extends Touchable

# What type of pickup this is (override in instances or set in editor)
@export var pickup_type := "resource"

# Base radius for pickup detection (scales with ship size in on_touch)
@export var base_radius := 2.0

func _ready() -> void:
	pass

func on_touch(other: PhysBody, impulse: float) -> void:
	# Calculate effective radius based on ship size
	# In a full implementation, we'd get the ship's size from stats or PhysBody
	var ship_size_factor := 1.0  # Placeholder - would be based on other.mass or similar
	var effective_radius := base_radius * ship_size_factor

	# Emit the generic touched signal (for base Touchable compatibility)
	emit_signal("touched", what, other, impulse)

	# Report to interaction registry for systems that care about pickups
	var registry = InteractRegistry.instance()
	if registry:
		registry.report_pickup_collected(pickup_type, other)

	# Optional: provide visual/audio feedback for collection
	# (e.g., play sound, show effect, fade out)