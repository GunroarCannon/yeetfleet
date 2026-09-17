## SessionRepStore: in-memory implementation of RepStore.
##
## This is the "today" implementation (TECHNICAL_PLAN §M5).  All state lives
## in plain Dictionaries keyed by "actor_id:faction_id". When M6 persistence
## arrives, swap this for SavedRepStore.new() in NebulaContext — every
## consumer that talks through RepStore sees zero change.
##
## State layout:
##   _grudges: Dictionary[String, Array[Grudge]]
##       key = "<actor_id>:<faction_id>"
##       value = list of live Grudge objects
##
##   _friendly: Dictionary[String, int]
##       key = "<actor_id>:<faction_id>"
##       value = accumulated friendly points (reduce heat)
##
## Heat query formula:
##   raw_heat = sum(grudge.heat for grudge in list)
##   net_heat = clamp(raw_heat - _friendly[key] * COOL_PER_SEVERITY, 0, 100)
class_name SessionRepStore
extends RepStore

# --- Private state --------------------------------------------------------

## Live grudges keyed by "actor:faction".
var _grudges: Dictionary = {}  # String -> Array[Grudge]

## Accumulated friendly points keyed by "actor:faction".
var _friendly: Dictionary = {}  # String -> int

## Session clock (seconds elapsed since store creation). Advanced by tick().
var _session_time: float = 0.0

# --- RepStore interface ---------------------------------------------------

func record_act(actor_id: String, faction_id: String, act: String, severity: int) -> void:
	var key := _key(actor_id, faction_id)
	if act in [RepStore.ACTS.RESCUE, RepStore.ACTS.ESCORT, RepStore.ACTS.PAYMENT]:
		# Friendly act — accumulate cool points.
		_friendly[key] = (_friendly.get(key, 0) as int) + severity
	else:
		# Hostile act — append a new grudge.
		if not _grudges.has(key):
			_grudges[key] = []
		_grudges[key].append(Grudge.new(actor_id, faction_id, act, severity, _session_time))


func get_heat(actor_id: String, faction_id: String) -> int:
	var key := _key(actor_id, faction_id)
	var raw := 0.0
	for g: Grudge in _grudges.get(key, []):
		raw += g.heat
	var cool := (_friendly.get(key, 0) as int) * RepStore.COOL_PER_SEVERITY
	return clampi(int(raw) - cool, 0, 100)


func tick(delta_seconds: float) -> void:
	_session_time += delta_seconds
	# Decay grudges; remove dead ones.
	var to_clean: Array[String] = []
	for key: String in _grudges.keys():
		var live: Array = []
		for g: Grudge in _grudges[key]:
			if g.tick(delta_seconds):
				live.append(g)
		if live.is_empty():
			to_clean.append(key)
		else:
			_grudges[key] = live
	for key: String in to_clean:
		_grudges.erase(key)


func to_dict() -> Dictionary:
	var grudge_data: Dictionary = {}
	for key: String in _grudges.keys():
		var arr: Array = []
		for g: Grudge in _grudges[key]:
			arr.append(g.to_dict())
		grudge_data[key] = arr
	return {
		"grudges":      grudge_data,
		"friendly":     _friendly.duplicate(),
		"session_time": _session_time,
	}


func from_dict(data: Dictionary) -> void:
	_grudges.clear()
	_friendly.clear()
	_session_time = float(data.get("session_time", 0.0))
	_friendly = data.get("friendly", {}).duplicate()
	var gd: Dictionary = data.get("grudges", {})
	for key: String in gd.keys():
		var list: Array = []
		for d in gd[key]:
			list.append(Grudge.from_dict(d))
		_grudges[key] = list

# --- Introspection (debug / smoke) ----------------------------------------

## Return all live grudges for a given actor across all factions.
## Used by debug UI and smoke tests.
func get_grudges_for(actor_id: String) -> Array:
	var result: Array = []
	for key: String in _grudges.keys():
		if key.begins_with(actor_id + ":"):
			result.append_array(_grudges[key])
	return result


## Return every faction that has any opinion of [param actor_id].
func get_factions_for(actor_id: String) -> Array[String]:
	var result: Array[String] = []
	for key: String in _grudges.keys():
		if key.begins_with(actor_id + ":"):
			result.append(key.split(":")[1])
	return result


## Number of live grudge objects (for smoke assertions).
func grudge_count() -> int:
	var n := 0
	for arr in _grudges.values():
		n += (arr as Array).size()
	return n

# --- Private helpers ------------------------------------------------------

func _key(actor_id: String, faction_id: String) -> String:
	return actor_id + ":" + faction_id
