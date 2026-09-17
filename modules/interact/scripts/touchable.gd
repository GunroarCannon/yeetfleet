## Touchable: base component for objects that can be interacted with via bump.
##
## Attach to any Node3D with a PhysBody to make it respond to touches.
##
## The touched() signal emits what was touched, by what, and with what impulse,
## allowing higher-level systems (pickups, cargo, etc.) to implement their
## specific logic without knowing details of the toucher.
##
## Modules do not reach into Touchable; they connect to its touched() signal.
##
## See TECHNICAL_PLAN.md §M2 for the interaction system design.

@tool
class_name Touchable extends Node3D

# Emitted when touched by another PhysBody
signal touched(what: String, by: PhysBody, impulse: float)

# What this object is (for identification in touched signal)
# Override in subclasses to return meaningful names
var what := "Touchable"

# Virtual method called when touched - override in subclasses
func on_touch(other: PhysBody, impulse: float) -> void:
	# Default implementation does nothing - subclasses should override
	pass

# Forward physics impacts to our virtual method. The signature matches
# PhysBody.impacted so a body owner can connect this directly.
func _on_phys_body_impacted(other: PhysBody, impulse: float, point: Vector3, normal: Vector3, closing: float) -> void:
	on_touch(other, impulse)
	# Emit the generic touched signal for modules that don't care about specifics.
	emit_signal("touched", what, other, impulse)


## The PhysBody this touchable belongs to, read from the parent node's
## `phys_body` member (the physics bridge keeps the body on the node that owns
## it). Null when not attached to a body yet.
func _phys_body_of_parent() -> PhysBody:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get("phys_body") as PhysBody