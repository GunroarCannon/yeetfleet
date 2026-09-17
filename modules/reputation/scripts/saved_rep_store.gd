## SavedRepStore: user:// persistence implementation of RepStore.
##
## NOT YET ACTIVE — this is the future swap-in (TECHNICAL_PLAN §M5).
## To enable, change NebulaContext.reputation = SessionRepStore.new()
## to NebulaContext.reputation = SavedRepStore.new().
## Zero consumer changes required.
##
## Delegates all live computation to SessionRepStore and adds load/save
## calls around scene transitions.
class_name SavedRepStore
extends RepStore

const SAVE_PATH := "user://reputation.json"

## Live delegate — all RepStore operations forward here.
var _delegate: SessionRepStore = SessionRepStore.new()

# --- RepStore interface ---------------------------------------------------

func record_act(actor_id: String, faction_id: String, act: String, severity: int) -> void:
	_delegate.record_act(actor_id, faction_id, act, severity)


func get_heat(actor_id: String, faction_id: String) -> int:
	return _delegate.get_heat(actor_id, faction_id)


func tick(delta_seconds: float) -> void:
	_delegate.tick(delta_seconds)


func to_dict() -> Dictionary:
	return _delegate.to_dict()


func from_dict(data: Dictionary) -> void:
	_delegate.from_dict(data)

# --- Persistence ----------------------------------------------------------

## Load state from user://reputation.json. Safe to call even if the file does
## not exist — starts with a clean slate.
func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SavedRepStore: could not open %s" % SAVE_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("SavedRepStore: corrupt save file, starting clean")
		return
	from_dict(parsed as Dictionary)


## Flush current state to user://reputation.json.
func save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SavedRepStore: could not write to %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
