## GameDefaults: the tuning that ships inside the game.
##
## Every settings class (Session, JuiceSettings, FxSettings, PerformanceSettings,
## StyleSettings, MobileHudProfiles) still keeps the player's own values in its
## `user://` file. Underneath that sits a copy of the same file in
## [constant DEFAULTS_DIR], baked from the flight test with
## [method bake]. That folder is part of the project, so it goes into every
## exported build: a fresh install (or a reset) starts from the tuning done in
## the flight test instead of the code's defaults.
##
## Load order, per key: code default < shipped default < player's file.
##
## Only a PC run from the project can bake (`res://` is read-only in an
## exported build and on a phone); [method can_bake] says so. Headless runs
## never write, so smoke tests cannot change what ships.
class_name GameDefaults
extends RefCounted

const DEFAULTS_DIR := "res://data/game_defaults/"

## Session [member Session.prefs] keys that are debug/testing state, not
## tuning: never baked into what ships.
const SKIP_PREFS: Array[String] = ["time_scale", "warp", "mobile_layout"]

## user:// path → the Callable that reloads that class from disk. Filled as each
## class loads through [method load_layered].
static var _registered: Dictionary = {}


## Load [param user_path] into [param cfg] on top of its shipped default.
## Returns OK when either file was found (drop-in for `cfg.load(user_path)`).
## [param reload] is remembered so [method reset_player_files] can re-apply
## the shipped values.
static func load_layered(cfg: ConfigFile, user_path: String, reload: Callable = Callable()) -> Error:
	if reload.is_valid():
		_registered[user_path] = reload
	elif not _registered.has(user_path):
		_registered[user_path] = Callable()
	var found := ERR_FILE_NOT_FOUND
	var shipped := ConfigFile.new()
	if shipped.load(shipped_path(user_path)) == OK:
		_overlay(cfg, shipped)
		found = OK
	var mine := ConfigFile.new()
	if mine.load(user_path) == OK:
		_overlay(cfg, mine)
		found = OK
	return found


## The shipped copy of a `user://` settings file.
static func shipped_path(user_path: String) -> String:
	return DEFAULTS_DIR + user_path.get_file()


## True when this run can write the shipped defaults: a desktop run from the
## project folder, with a window.
static func can_bake() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web") or OS.has_feature("template"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("editor")


## Copy every registered player file into [constant DEFAULTS_DIR]. Session is
## saved first (the others save on every change). Returns how many files were
## written, or -1 when this run cannot bake.
static func bake() -> int:
	if not can_bake():
		return -1
	Session.save_to_disk()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFAULTS_DIR))
	var written := 0
	for user_path: String in _registered.keys():
		var cfg := ConfigFile.new()
		if cfg.load(user_path) != OK:
			continue
		_strip_debug(cfg)
		if cfg.save(ProjectSettings.globalize_path(shipped_path(user_path))) == OK:
			written += 1
		else:
			push_error("[GameDefaults] could not write " + shipped_path(user_path))
	print("[GameDefaults] baked %d settings files into %s" % [written, DEFAULTS_DIR])
	return written


## Delete the player's own settings files and re-load every class, so each
## falls back to what ships. Returns how many files were removed.
static func reset_player_files() -> int:
	var removed := 0
	for user_path: String in _registered.keys():
		if FileAccess.file_exists(user_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))
			removed += 1
	for user_path: String in _registered.keys():
		var reload: Callable = _registered[user_path]
		if reload.is_valid():
			reload.call()
	return removed


# --- Internals ---

static func _overlay(into: ConfigFile, from: ConfigFile) -> void:
	for section in from.get_sections():
		for key in from.get_section_keys(section):
			into.set_value(section, key, from.get_value(section, key))


static func _strip_debug(cfg: ConfigFile) -> void:
	for section in cfg.get_sections():
		if not cfg.has_section_key(section, "prefs"):
			continue
		var prefs: Variant = cfg.get_value(section, "prefs")
		if prefs is Dictionary:
			var clean := (prefs as Dictionary).duplicate(true)
			for key in SKIP_PREFS:
				clean.erase(key)
			cfg.set_value(section, "prefs", clean)
