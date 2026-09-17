## InteractRegistry: facade for the interact module.
##
## Provides a clean API for other modules to interact with the interaction
## system without needing to know implementation details.
##
## Other modules should interact with this singleton rather than reaching
## directly into the interact module's internals.
##
## See TECHNICAL_PLAN.md §0.2 for the shared context pattern - this
## complements NebulaContext by providing interaction-specific functionality.

@tool
class_name InteractRegistry extends Node

# Singleton pattern
static var _instance: InteractRegistry

# Signals for monitoring interaction events (optional, for debugging/tuning)
signal pickup_collected(item_type: String, collector: PhysBody)
signal cargo_attached(cargo_type: String, destination: PhysBody)
signal tow_started(tower: PhysBody, towed: PhysBody)
signal tow_ended(tower: PhysBody, towed: PhysBody)

func _init() -> void:
	if _instance:
		push_error("InteractRegistry is a singleton! Use InteractRegistry.instance()")
	else:
		_instance = self

static func instance() -> InteractRegistry:
	if not _instance:
		# Auto-create on first access (lazy singleton)
		_instance = InteractRegistry.new()
	return _instance

# Convenience methods for common interactions
# These would be called by Touchable subclasses when they want to
# report specific interaction types to interested systems

func report_pickup_collected(item_type: String, collector: PhysBody) -> void:
	emit_signal("pickup_collected", item_type, collector)

func report_cargo_attached(cargo_type: String, destination: PhysBody) -> void:
	emit_signal("cargo_attached", cargo_type, destination)

func report_tow_started(tower: PhysBody, towed: PhysBody) -> void:
	emit_signal("tow_started", tower, towed)

func report_tow_ended(tower: PhysBody, towed: PhysBody) -> void:
	emit_signal("tow_ended", tower, towed)