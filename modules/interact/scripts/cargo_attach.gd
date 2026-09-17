## CargoAttach: handles mission cargo attachment when touching a mission ship.
##
## Attach to cargo items or containers. When touched by a mission ship
## (one with a mission cargo requirement), it emits a specific signal
## that mission systems can listen for to track cargo delivery.
##
## Does not create a physical bond - that's handled by the mission system
## moving the cargo into the ship's hold. This just handles the
## "cargo attached" notification.

@tool
class_name CargoAttach extends Touchable

# What type of cargo this is (for mission matching)
@export var cargo_type := "generic"

# Whether this cargo has been delivered (prevents double-counting)
var _delivered := false

func _ready() -> void:
	pass

func on_touch(other: PhysBody, impulse: float) -> void:
	# Prevent multiple attachments of the same cargo
	if _delivered:
		return

	# In a full implementation, we'd check if 'other' is a mission ship
	# that wants this cargo_type, then notify the mission system
	# For now, we'll just report to registry and mark as delivered

	# Report to interaction registry for mission systems
	var registry = InteractRegistry.instance()
	if registry:
		registry.report_cargo_attached(cargo_type, other)

	# Emit the generic touched signal (for base Touchable compatibility)
	emit_signal("touched", "cargo_%s" % cargo_type, other, impulse)
	_delivered = true

	# Optional: provide visual feedback that cargo is attached
	# (e.g., change appearance, attach to ship visually, etc.)