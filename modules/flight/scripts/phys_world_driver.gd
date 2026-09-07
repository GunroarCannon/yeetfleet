## Steps a scene's [PhysWorld] once per physics frame, after every controller
## has written its body's velocity.
##
## The plan's tick order (TECHNICAL_PLAN §M1) needs the world to resolve after
## every [FlightModel] (and AI ship) has run, so it owns a dedicated node whose
## physics priority is higher than theirs. All [FlightModel]s tick at the
## default priority of 0; this node runs at 100, so a knock computed here is
## already baked into the body's velocity when the models read it back next
## frame. Owned by [FlightRoot]; holds no state of its own beyond the world.
class_name PhysWorldDriver
extends Node

## The world this node steps. Set once by whoever built it; null is safe (the
## driver is a no-op until then).
var world: PhysWorld = null


func _init() -> void:
	# Late, so every controller's _physics_process (priority 0) has run first.
	process_physics_priority = 100


func _physics_process(delta: float) -> void:
	if world != null:
		world.step(delta)
