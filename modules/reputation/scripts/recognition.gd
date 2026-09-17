## Recognition: a faction patrol identifying a nearby ship.
##
## Called by patrol AI (or the IncidentDirector) when a faction ship
## gets close enough to read the target's transponder. Returns a
## [enum RecognitionResult] that the caller uses to decide behaviour:
##
##   UNKNOWN   → ignore / pass by
##   IDENTIFIED → announce "IDENTIFIED: [name]", no attitude change
##   HOSTILE   → announce "IDENTIFIED: HOSTILE", turn toward, raise shields
##   KOS       → announce "KILL ORDER ACTIVE", attack immediately
##
## No UI bar is rendered. Behaviour IS the reputation expression.
class_name Recognition
extends RefCounted

# --- Enums ----------------------------------------------------------------

enum RecognitionResult {
	UNKNOWN    = 0,   ## actor not in memory — neutral
	IDENTIFIED = 1,   ## known but within tolerance
	HOSTILE    = 2,   ## heat >= HOSTILE_THRESHOLD — approach and warn
	KOS        = 3,   ## heat >= KOS_THRESHOLD — attack on sight
}

# --- Constants ------------------------------------------------------------

## Range (metres) within which a patrol can read a transponder.
const TRANSPONDER_RANGE_M := 500.0

# --- Public API -----------------------------------------------------------

## Evaluate how [param faction_id] reacts to [param actor_id] given the
## provided [param rep_store]. Pass [param distance_m] to apply the range
## gate — returns [constant UNKNOWN] if out of transponder range.
static func evaluate(
	actor_id: String,
	faction_id: String,
	rep_store: RepStore,
	distance_m: float,
) -> RecognitionResult:
	if distance_m > TRANSPONDER_RANGE_M:
		return RecognitionResult.UNKNOWN

	var heat := rep_store.get_heat(actor_id, faction_id)

	if heat >= RepStore.KOS_THRESHOLD:
		return RecognitionResult.KOS
	elif heat >= RepStore.HOSTILE_THRESHOLD:
		return RecognitionResult.HOSTILE
	elif heat > 0:
		return RecognitionResult.IDENTIFIED
	return RecognitionResult.UNKNOWN


## Human-readable label for HUD / log use.
static func label_for(result: RecognitionResult) -> String:
	match result:
		RecognitionResult.KOS:
			return "KILL ORDER ACTIVE"
		RecognitionResult.HOSTILE:
			return "IDENTIFIED: HOSTILE"
		RecognitionResult.IDENTIFIED:
			return "IDENTIFIED"
		_:
			return ""
