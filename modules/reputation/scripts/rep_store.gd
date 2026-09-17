## RepStore: abstract interface for faction memory.
##
## Designed as the swap point (TECHNICAL_PLAN §M5): the caller always talks to
## a RepStore — never to a SessionRepStore or SavedRepStore directly. Swapping
## the implementation in NebulaContext is one line and zero consumer changes.
##
## Serialisation contract: all state is plain dicts and ints. No node refs,
## no Callables stored in state. Every subclass must honour this so that a
## SavedRepStore can write to user:// without any extra work.
##
## Faction IDs are plain Strings ("empire", "traders", "pirates", …).
## Heat values are clamped ints in [0, 100]. 0 = neutral, 100 = kill-on-sight.
class_name RepStore
extends RefCounted

# --- Interface — subclasses must override ---------------------------------

## Record an act that may affect how faction [param faction_id] remembers
## [param actor_id]. [param act] is a plain String key from [constant ACTS].
## [param severity] is 1–10 (higher = worse). Only call after Witness confirms
## someone from [param faction_id] actually saw it.
func record_act(_actor_id: String, _faction_id: String, _act: String, _severity: int) -> void:
	push_error("RepStore.record_act must be overridden")


## Return the heat value (0–100) that [param faction_id] has towards
## [param actor_id]. 0 = neutral / unknown, 100 = kill-on-sight.
func get_heat(_actor_id: String, _faction_id: String) -> int:
	push_error("RepStore.get_heat must be overridden")
	return 0


## Advance all grudge timers by [param delta_seconds]. Called once per physics
## tick by whoever holds the RepStore. Grudges below [constant DECAY_FLOOR]
## after decay are removed entirely.
func tick(_delta_seconds: float) -> void:
	pass


## Serialise all state to a plain Dictionary (no node refs, no Callables).
## Used by SavedRepStore to write to user:// — must be the inverse of
## [method from_dict].
func to_dict() -> Dictionary:
	push_error("RepStore.to_dict must be overridden")
	return {}


## Restore state from a plain Dictionary produced by [method to_dict].
func from_dict(_data: Dictionary) -> void:
	push_error("RepStore.from_dict must be overridden")


# --- Constants shared by all implementations ------------------------------

## Recognised act keys. Severity multiplier is caller's responsibility.
const ACTS := {
	ATTACK    = "attack",     ## direct weapons fire
	RAM       = "ram",        ## collision at speed
	STEAL     = "steal",      ## cargo/loot taken
	RESCUE    = "rescue",     ## towed / assisted a faction member
	ESCORT    = "escort",     ## flew protective detail
	PAYMENT   = "payment",    ## goods/credits exchanged in good faith
}

## Heat point increments per severity unit for hostile acts.
const HEAT_PER_SEVERITY := 8

## Heat point decrements per severity unit for friendly acts.
const COOL_PER_SEVERITY := 6

## Threshold above which a faction ship will say "IDENTIFIED: HOSTILE".
const HOSTILE_THRESHOLD := 40

## Threshold above which a faction ship will attack on sight.
const KOS_THRESHOLD := 70

## Grudge heat cannot fall below this before the grudge is deleted.
const DECAY_FLOOR := 0

## Heat decayed per real-time second (session clock, not game clock).
const DECAY_RATE := 0.5
