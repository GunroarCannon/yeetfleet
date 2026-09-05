## PhysProfile: every tunable that decides how collisions *feel*.
##
## A Resource rather than a pile of consts so that a feel is an object you can
## save, name and hand around. Two profiles ship with the module — grounded and
## cartoony — and the physics lab (M1's companion scene) is where new ones are
## authored: every field below is a live slider there, and "save profile as
## .tres" writes exactly this Resource.
##
## Not every dial in the plan lands in M1a. The dials that route an impact into
## [Juice] (hitstop, squash), the gravity g and the assist-lockout live here as
## numbers so a profile is one place to look at, but only the collision-solver
## subset is read yet; the others become live when the module that consumes them
## lands.
class_name PhysProfile
extends Resource

## 0: every body responds to a hit alike, whatever its mass (the game before
## M1). 1: a hauler is a wrecking ball and a scout is a ping-pong ball. The
## impulse solver blends a body's 1/mass toward equal by this much.
@export_range(0.0, 1.0) var mass_influence := 1.0

## Per-layer restitution, because a rock, a hull and a planet do not feel the
## same to bounce off. A pair's restitution is the average of the two sides'.
@export_range(0.0, 1.0) var restitution_ship := 0.4
@export_range(0.0, 1.0) var restitution_rock := 0.25
@export_range(0.0, 1.0) var restitution_planet := 0.6

## Fraction of the impulse handed to the thing you hit. 1 = momentum conserved
## exactly (equal and opposite); more than 1 = the "asteroid goes flying" knob,
## where the victim gets a bonus kick for drama. Intentionally non-conserving
## when not 1.
@export_range(0.0, 2.0) var knock_transfer := 1.0

## How much tangential slip at a contact becomes spin instead of being damped
## away. The knob that makes getting knocked into a tumble — and boosting to
## recover — a real event.
@export_range(0.0, 1.0) var impulse_to_spin := 0.5

## Tangential friction at a contact, 0 = perfectly slick to 1 = sticky. Feeds
## the same tangential slip that [member impulse_to_spin] turns into rotation;
## friction is what makes a glancing hit deflect at all.
@export_range(0.0, 1.0) var friction := 0.25

## The solver's positional correction: the fraction of the overlap pushed out
## each step (Baumgarte). Too low and bodies sink into each other; too high and
## a resting contact jitters.
@export_range(0.05, 0.5) var position_correction := 0.2
## Overlap smaller than this (metres) is left alone — zero noise on a resting
## contact.
@export var penetration_slop := 0.02

## Above (radius * ccd_ratio) of travel per step, a swept test engages instead
## of a plain overlap test, so a fast mover cannot tunnel through a small rock.
@export_range(0.2, 1.0) var ccd_ratio := 0.5

## Mobile safety valve: the most broadphase pairs resolved in one step. Past
## this, extra pairs are dropped for a frame rather than blowing the budget.
@export var max_pairs_per_step := 1500

## Spin damping applied to a body whose tumble was induced (assist off), per
## second. Tuned per mode later; one value per profile for now.
@export var spin_damp_induced := 1.5


## The bounciness of a contact between two layers: the average of the two
## sides' restitution values from this profile.
func restitution_for_pair(a_layer: int, b_layer: int) -> float:
	return (_restitution_of(a_layer) + _restitution_of(b_layer)) * 0.5


func _restitution_of(layer: int) -> float:
	match layer:
		PhysBody.Layer.SHIP: return restitution_ship
		PhysBody.Layer.STATIC: return restitution_planet
		_: return restitution_rock
