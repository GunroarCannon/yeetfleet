## Grudge: one faction's memory of a single witnessed act.
##
## A grudge is the atomic unit of reputation. It records who committed the
## act, what it was, how bad it was, and when it happened (session seconds).
## Heat decays over time; once heat reaches zero the grudge is discarded.
##
## No node references, no Callables. Serialisable to a plain Dictionary.
class_name Grudge
extends RefCounted

# --- Data -----------------------------------------------------------------

## The actor who committed the act (usually the player ship ID).
var actor_id: String = ""

## The faction that witnessed and now holds this grudge.
var faction_id: String = ""

## Act key — one of [constant RepStore.ACTS] values.
var act: String = ""

## Original severity (1–10) for bookkeeping; heat is the live value.
var severity: int = 0

## Current heat contribution (starts at severity × [constant RepStore.HEAT_PER_SEVERITY],
## decays at [constant RepStore.DECAY_RATE] per second).
var heat: float = 0.0

## Session-clock timestamp when the act occurred.
var timestamp: float = 0.0

# --- Lifecycle ------------------------------------------------------------

## Initialise from the act details. Heat starts at severity × HEAT_PER_SEVERITY.
func _init(p_actor: String, p_faction: String, p_act: String, p_severity: int, p_time: float) -> void:
	actor_id  = p_actor
	faction_id = p_faction
	act        = p_act
	severity   = p_severity
	timestamp  = p_time
	heat       = float(p_severity * RepStore.HEAT_PER_SEVERITY)


## Advance decay by [param delta] seconds. Returns true if the grudge is still
## alive (heat > 0), false if it should be discarded.
func tick(delta: float) -> bool:
	heat -= RepStore.DECAY_RATE * delta
	return heat > RepStore.DECAY_FLOOR


# --- Serialisation --------------------------------------------------------

## Convert to a plain Dictionary with no node refs.
func to_dict() -> Dictionary:
	return {
		"actor_id":   actor_id,
		"faction_id": faction_id,
		"act":        act,
		"severity":   severity,
		"heat":       heat,
		"timestamp":  timestamp,
	}


## Restore from a Dictionary produced by [method to_dict].
static func from_dict(d: Dictionary) -> Grudge:
	var g := Grudge.new(
		d.get("actor_id",   ""),
		d.get("faction_id", ""),
		d.get("act",        ""),
		d.get("severity",   1),
		d.get("timestamp",  0.0),
	)
	g.heat = float(d.get("heat", 0.0))
	return g
