## One body in the shared impulse layer (modules/physics).
##
## This is not a physics-server body and not a node. It is a registry entry the
## scene owns: a reference to the [Node3D] the controller actually moves, the
## numbers that decide how collisions feel (mass, radius, restitution, which
## layers it touches), and the two velocities the controller *writes* and the
## solver *modifies*. The node is the position; the body is the rest.
##
## The layer exists so every actor can push every other actor. Today's flight
## model collides against scenery and only ever changes its own velocity; the
## whole point of M1 is that a collision here hands momentum to *both* sides —
## see [ImpulseSolver].
class_name PhysBody
extends RefCounted

## Collision layers. A planet or station is STATIC; a ship, rock, debris or
## pickup is a normal body. Layers choose who can push whom via [member mask].
enum Layer {
	SHIP,
	ROCK,
	DEBRIS,
	PICKUP,
	STATIC,
}

## Emitted when this body took an impulse from another. `impulse` is the scalar
## along the contact normal (positive = hit); point and normal are world space.
signal impacted(other: PhysBody, impulse: float, point: Vector3, normal: Vector3)

## The node whose position is this body's position. Written by the controller,
## moved by [PhysWorld] integration. May be null only in a headless test that
## drives positions through the body directly.
var node: Node3D = null

## Tonnes. Comes from [ShipStats].mass for ships, or volume for a rock. Only the
## *ratio* between two masses ever matters, and [member PhysProfile.mass_influence]
## decides how much even that matters.
var mass := 1.0
## Collision sphere radius, metres, from the design's bounds or the rock's size.
var radius := 1.0
## World velocity, m/s. The controller writes it; the solver modifies it; the
## world integrates it into [member node].
var velocity := Vector3.ZERO
## Angular velocity, rad/s, world axes. A real body would spin only from an
## off-centre impulse; this one picks up spin from tangential slip, scaled by
## [member PhysProfile.impulse_to_spin].
var angular := Vector3.ZERO
## How fast an induced tumble decays, per second, when nothing sustains it.
var angular_damping := 0.5

## Bounciness used when no [PhysProfile] is attached to the world (tests, and
## the fallback a profile author starts from). In play, the profile's per-layer
## restitution is authoritative — see [method PhysProfile.restitution_for_pair].
var restitution := 0.4

var layer := Layer.SHIP
## Which layers this body collides with, as a bitmask over [enum Layer]. 0xFF
## means everything, which is the right default: fights are decided by the
## impulse solver, not by a config mistake that quietly turns collision off.
var mask := 0xFF

## Infinite mass, never pushed, not integrated. Planets and stations. A
## kinematic body still collides — it is a wall with a radius.
var kinematic := false

## Faction this body belongs to, for blame attribution (M5). -1 = nobody.
var faction_id := -1
## Who last hit this body and changed its motion, for the same reason.
var last_pusher := -1


func _init(mass := 1.0, radius := 1.0) -> void:
	self.mass = mass
	self.radius = radius


## 1/mass for the impulse equations; zero for kinematic bodies so they absorb
## momentum without ever moving.
func inv_mass() -> float:
	return 0.0 if kinematic else 1.0 / mass


## World position. Kinematic bodies are moved by their controllers; the solver
## reads this and [method PhysWorld] writes [member node]'s position each step.
func position() -> Vector3:
	if node != null:
		return node.global_position
	push_error("PhysBody has no node and no standalone position — attach a Node3D")
	return Vector3.ZERO


func set_position(p: Vector3) -> void:
	if node != null:
		node.global_position = p


## How far this body travelled last physics step, used to decide whether a
## swept test is needed this frame.
func step_distance(delta: float) -> float:
	return velocity.length() * delta


## Centres-to-centres separation at which the two collide.
static func touch_distance(a: PhysBody, b: PhysBody) -> float:
	return a.radius + b.radius
