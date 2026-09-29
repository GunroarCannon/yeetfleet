## The three on/off switches for the optional effect layers, persisted
## independently of any scene.
##
## [member library_sounds] swaps the flight module's procedural synth bank for
## the bundled Sci-Fi Sound Library MP3s, [member addon_vfx] layers the
## BinbunVFX addon's effects over the existing [Juice] one-shots, and
## [member sprite_hits] adds the sprite-sheet hit flash from
## [code]assets/hit-effects[/code]. Each is independent so a look can be
## compared layer by layer — the whole point of the comparison lab.
##
## Kept apart from [Juice] for the same reason [JuiceSettings] is: the load/save
## path can be exercised without a scene tree, and a settings screen has one
## small surface to bind to. Every read goes through [method ensure_loaded], so
## asking for a toggle before anything has loaded it still returns the saved
## value rather than the default.
class_name FxSettings
extends RefCounted

const SETTINGS_PATH := "user://fx.cfg"
const SECTION := "fx"

## Use the Sci-Fi Sound Library instead of the procedural synth bank.
static var library_sounds := true
## Layer the BinbunVFX addon's hit/impact/explosion/electric effects.
static var addon_vfx := true
## Add the animated sprite hit flash on top of the 3D hit effect.
static var sprite_hits := true

static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()


static func load_from_disk() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH, FxSettings.load_from_disk) != OK:
		return
	library_sounds = bool(cfg.get_value(SECTION, "library_sounds", library_sounds))
	addon_vfx = bool(cfg.get_value(SECTION, "addon_vfx", addon_vfx))
	sprite_hits = bool(cfg.get_value(SECTION, "sprite_hits", sprite_hits))


static func set_library_sounds(value: bool) -> void:
	ensure_loaded()
	library_sounds = value
	_save()


static func set_addon_vfx(value: bool) -> void:
	ensure_loaded()
	addon_vfx = value
	_save()


static func set_sprite_hits(value: bool) -> void:
	ensure_loaded()
	sprite_hits = value
	_save()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "library_sounds", library_sounds)
	cfg.set_value(SECTION, "addon_vfx", addon_vfx)
	cfg.set_value(SECTION, "sprite_hits", sprite_hits)
	cfg.save(SETTINGS_PATH)
	GameDefaults.note_saved(SETTINGS_PATH)
