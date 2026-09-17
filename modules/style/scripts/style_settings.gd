## The chosen look and palette, persisted independently of any scene.
##
## Kept apart from [StyleManager] itself so the load/save path can be exercised
## without a scene tree, mirroring [JuiceSettings]'s split. [StyleManager] owns
## the live objects; this owns which two of them the player picked last time.
class_name StyleSettings
extends RefCounted

const SETTINGS_PATH := "user://style.cfg"
const SECTION := "style"

## Id of the [StyleProfile] to start on. Empty means "leave the manager's own
## default alone" — a fresh install should look like the game always did, not
## like whichever profile happened to be authored first.
static var profile_id := ""
## Id of the [Palette] to start on. Empty means the same: use the fallback.
static var palette_id := ""


static func set_profile_id(value: String) -> void:
	profile_id = value
	_save()


static func set_palette_id(value: String) -> void:
	palette_id = value
	_save()


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	profile_id = String(cfg.get_value(SECTION, "profile", ""))
	palette_id = String(cfg.get_value(SECTION, "palette", ""))


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "profile", profile_id)
	cfg.set_value(SECTION, "palette", palette_id)
	cfg.save(SETTINGS_PATH)
