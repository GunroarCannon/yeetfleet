## LogCensus: counts everything the game writes to the log — prints, warnings
## and errors — grouped by where it comes from, to find what logs the most.
##
## A Godot [Logger] (4.5+), so it sees every line without touching the code
## that prints it: [method install] hooks it in, and from then on each line is
## grouped under a key — an error by its script file and line, a print by its
## text with the numbers taken out (so "hit 12 m" and "hit 40 m" are one
## entry). [method top] ranks the keys by how many lines (and bytes) they
## wrote. The 🧾 Log census panel shows it live; the headless
## [code]log_census_check.gd[/code] runs a fight and prints the ranking.
##
## Loggers are called from whatever thread logged, so the tallies sit behind a
## [Mutex].
class_name LogCensus
extends Logger

## The installed census, or null. One per game.
static var _instance: LogCensus = null

var _mutex := Mutex.new()
## key -> {count, bytes, kind, sample}
var _tally: Dictionary = {}
var _lines := 0
var _bytes := 0
var _started_ms := 0
var _digits := RegEx.create_from_string("[0-9]+(\\.[0-9]+)?")


## Hook the census into the engine's logging (once) and return it.
static func install() -> LogCensus:
	if _instance == null:
		_instance = LogCensus.new()
		_instance._started_ms = Time.get_ticks_msec()
		OS.add_logger(_instance)
	return _instance


## The installed census, or null if [method install] never ran.
static func instance() -> LogCensus:
	return _instance


## Unhook it (the tallies are kept until it is freed).
static func uninstall() -> void:
	if _instance != null:
		OS.remove_logger(_instance)
		_instance = null


func _log_message(message: String, error: bool) -> void:
	var text := message.strip_edges()
	if text.is_empty():
		return
	var key := _digits.sub(text, "#", true).left(90)
	_add(key, "stderr" if error else "print", message.length(), text)


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind: String = ["error", "warning", "script error", "shader error"][clampi(error_type, 0, 3)]
	var what := rationale if rationale != "" else code
	var key := "%s  %s:%d (%s)" % [kind.to_upper(), file.get_file(), line, function]
	# push_warning / push_error all come from the same engine line: group
	# those by what they say instead.
	if function == "push_warning" or function == "push_error":
		key = "%s  %s" % [kind.to_upper(), _digits.sub(what, "#", true).left(90)]
	_add(key, kind, what.length() + file.length() + 16, what.left(160))


func _add(key: String, kind: String, size: int, sample: String) -> void:
	_mutex.lock()
	var e: Dictionary = _tally.get(key, {})
	if e.is_empty():
		e = {"count": 0, "bytes": 0, "kind": kind, "sample": sample}
		_tally[key] = e
	e["count"] = int(e["count"]) + 1
	e["bytes"] = int(e["bytes"]) + size
	_lines += 1
	_bytes += size
	_mutex.unlock()


## Forget everything counted so far and start the clock again.
func reset() -> void:
	_mutex.lock()
	_tally.clear()
	_lines = 0
	_bytes = 0
	_started_ms = Time.get_ticks_msec()
	_mutex.unlock()


## The [param n] biggest loggers, most lines first: an Array of
## {key, count, bytes, kind, sample, per_sec}.
func top(n := 15) -> Array:
	_mutex.lock()
	var rows: Array = []
	for key: String in _tally:
		var e: Dictionary = _tally[key].duplicate()
		e["key"] = key
		rows.append(e)
	_mutex.unlock()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	var secs := maxf((Time.get_ticks_msec() - _started_ms) / 1000.0, 0.001)
	for r: Dictionary in rows:
		r["per_sec"] = float(r["count"]) / secs
	return rows.slice(0, n)


## Totals since the last reset: {lines, bytes, seconds}.
func totals() -> Dictionary:
	_mutex.lock()
	var out := {"lines": _lines, "bytes": _bytes, "seconds": (Time.get_ticks_msec() - _started_ms) / 1000.0}
	_mutex.unlock()
	return out


## The ranking as plain text — for the panel's copy button and the check.
func report(n := 15) -> String:
	var t := totals()
	var lines := PackedStringArray()
	lines.append("%d log lines (%.1f KB) in %.0f s" % [t["lines"], float(t["bytes"]) / 1024.0, t["seconds"]])
	for r: Dictionary in top(n):
		lines.append("%6d  %5.1f/s  %6.1f KB  %s" % [r["count"], r["per_sec"], float(r["bytes"]) / 1024.0, r["key"]])
		if String(r["sample"]) != String(r["key"]):
			lines.append("                             e.g. %s" % String(r["sample"]).left(110))
	return "\n".join(lines)
