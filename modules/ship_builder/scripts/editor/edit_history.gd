## Undo/redo over whole-design snapshots.
##
## Snapshotting the entire design as a dictionary sounds heavy-handed next to a
## command pattern, and for this data it is the right trade: a design is a few
## kilobytes of plain dictionaries, so a snapshot costs less than the bookkeeping
## an inverse-operation system would need. More importantly it cannot drift — every
## edit path in the builder, however exotic (chassis swap that re-parents children,
## break-symmetry that duplicates a subtree), is undone by exactly the same code.
##
## Continuous edits — dragging a joint slider, scrubbing a colour picker — would
## otherwise flood the stack with one entry per frame, so they open a transaction
## and commit a single entry when the drag ends.
class_name EditHistory
extends RefCounted

## Emitted whenever undo/redo availability changes, so buttons can enable/disable.
signal changed

const MAX_ENTRIES := 120

## Each entry: {label: String, before: Dictionary, after: Dictionary}.
var _entries: Array[Dictionary] = []
## Index of the next entry that redo would apply. Everything below it is undoable.
var _cursor := 0

var _txn_open := false
var _txn_label := ""
var _txn_before: Dictionary = {}


func clear(baseline: Dictionary = {}) -> void:
	_entries.clear()
	_cursor = 0
	_txn_open = false
	_txn_before = baseline.duplicate(true)
	changed.emit()


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func undo_label() -> String:
	return String(_entries[_cursor - 1]["label"]) if can_undo() else ""


func redo_label() -> String:
	return String(_entries[_cursor]["label"]) if can_redo() else ""


## Record a completed, discrete edit.
func push(label: String, before: Dictionary, after: Dictionary) -> void:
	if before == after:
		return
	# Anything that was redoable is now unreachable: the timeline has forked.
	if _cursor < _entries.size():
		_entries.resize(_cursor)
	_entries.append({
		"label": label,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_cursor = _entries.size()
	changed.emit()


## Begin coalescing a continuous edit. [param before] is the state as it was when
## the interaction started.
func begin(label: String, before: Dictionary) -> void:
	if _txn_open:
		# A drag started while another was open. The first one's start state is the
		# honest baseline, so keep it and just retitle.
		_txn_label = label
		return
	_txn_open = true
	_txn_label = label
	_txn_before = before.duplicate(true)


## Close a continuous edit, collapsing the whole drag into one entry.
func commit(after: Dictionary) -> void:
	if not _txn_open:
		return
	_txn_open = false
	push(_txn_label, _txn_before, after)


func abort() -> void:
	_txn_open = false


func in_transaction() -> bool:
	return _txn_open


## The design state to undo to, or an empty dictionary if there is nothing to undo.
func undo() -> Dictionary:
	if not can_undo():
		return {}
	_cursor -= 1
	changed.emit()
	return (_entries[_cursor]["before"] as Dictionary).duplicate(true)


## The design state to redo to, or an empty dictionary.
func redo() -> Dictionary:
	if not can_redo():
		return {}
	var state: Dictionary = (_entries[_cursor]["after"] as Dictionary).duplicate(true)
	_cursor += 1
	changed.emit()
	return state


## For the help overlay and debugging: a short description of the stack.
func summary() -> String:
	if _entries.is_empty():
		return "No edits yet"
	return "%d/%d edits" % [_cursor, _entries.size()]
