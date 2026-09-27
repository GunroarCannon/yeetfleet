## Headless check for [GameDefaults]: per-key layering (shipped under the
## player's), debug prefs stripped from what ships, no baking from a headless
## run, and a reset that deletes only registered files and re-loads them.
##
##     godot --path . --headless --script modules/core/tools/game_defaults_check.gd
##
## Touches only a throwaway user:// file; the real settings files are never
## registered, so they cannot be deleted.
extends SceneTree

const TEMP := "user://game_defaults_check.cfg"

var _failures: Array[String] = []
var _reloaded := 0


func _initialize() -> void:
	print("── game defaults check ───────────────────────────────────")
	# Layering: shipped values fill in, the player's win.
	var shipped := ConfigFile.new()
	shipped.set_value("s", "a", 1)
	shipped.set_value("s", "b", 2)
	var mine := ConfigFile.new()
	mine.set_value("s", "b", 5)
	var merged := ConfigFile.new()
	GameDefaults._overlay(merged, shipped)
	GameDefaults._overlay(merged, mine)
	_report("layering: a key only the shipped file has comes through", merged.get_value("s", "a") == 1)
	_report("layering: the player's own value wins", merged.get_value("s", "b") == 5)

	# Debug prefs never ship.
	var session := ConfigFile.new()
	session.set_value("session", "prefs", {"time_scale": 4.0, "warp": true, "craft_size": 2})
	GameDefaults._strip_debug(session)
	var prefs: Dictionary = session.get_value("session", "prefs")
	_report("bake: time warp and warp are stripped, tuning kept", not prefs.has("time_scale") and not prefs.has("warp") and prefs.has("craft_size"))

	# Headless never writes res://.
	_report("headless: cannot bake", not GameDefaults.can_bake() and GameDefaults.bake() == -1)
	_report("shipped path maps user:// to the defaults folder", GameDefaults.shipped_path("user://juice.cfg") == "res://data/game_defaults/juice.cfg")

	# A user file with no shipped copy loads as before.
	GameDefaults._registered.clear()
	var f := ConfigFile.new()
	f.set_value("x", "k", 42)
	f.save(TEMP)
	var loaded := ConfigFile.new()
	var err := GameDefaults.load_layered(loaded, TEMP, _on_reload)
	_report("load_layered: reads the player's file", err == OK and loaded.get_value("x", "k") == 42)

	# Reset: only registered files go, and each class re-loads.
	var removed := GameDefaults.reset_player_files()
	_report("reset: removes the registered file", removed == 1 and not FileAccess.file_exists(TEMP))
	_report("reset: re-loads the class", _reloaded == 1)
	GameDefaults._registered.clear()
	_finish()


func _on_reload() -> void:
	_reloaded += 1


func _report(label: String, ok: bool) -> void:
	print("  %-62s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		quit(1)
