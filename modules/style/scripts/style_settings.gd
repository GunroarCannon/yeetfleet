## The chosen look and palette, persisted independently of any scene.
##
## Kept apart from [StyleManager] itself so the load/save path can be exercised
## without a scene tree, mirroring [JuiceSettings]'s split. [StyleManager] owns
## the live objects; this owns which two of them the player picked last time.
class_name StyleSettings
extends RefCounted

const SETTINGS_PATH := "user://style.cfg"
const SECTION := "style"

## Id of the [StyleProfile] to start on. Default is "cartoony" for a rounded, toon look.
static var profile_id := "cartoony"
## Id of the [Palette] to start on. A fresh install starts on "toybox", the
## palette built for the soft-toy art direction; empty means the pre-palette
## fallback ([constant Palette.DEFAULTS]).
static var palette_id := "toybox"
## When true, every element that supports it is forced into the toon shading
## path, independent of the style profile's own band dial. See [ToonOverride].
static var toon_shading := false
## When true, forces wireframe vector arcade rendering across all systems.
static var wireframe_mode := false


static func set_profile_id(value: String) -> void:
	profile_id = value
	_save()


static func set_palette_id(value: String) -> void:
	palette_id = value
	_save()


static func set_toon_shading(value: bool) -> void:
	toon_shading = value
	_save()


static func set_wireframe_mode(value: bool) -> void:
	wireframe_mode = value
	_save()


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH, StyleSettings.load_from_disk) != OK:
		return
	profile_id = String(cfg.get_value(SECTION, "profile", "cartoony"))
	palette_id = String(cfg.get_value(SECTION, "palette", "toybox"))
	toon_shading = bool(cfg.get_value(SECTION, "toon_shading", false))
	wireframe_mode = bool(cfg.get_value(SECTION, "wireframe_mode", false))


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "profile", profile_id)
	cfg.set_value(SECTION, "palette", palette_id)
	cfg.set_value(SECTION, "toon_shading", toon_shading)
	cfg.set_value(SECTION, "wireframe_mode", wireframe_mode)
	cfg.save(SETTINGS_PATH)
	GameDefaults.note_saved(SETTINGS_PATH)
