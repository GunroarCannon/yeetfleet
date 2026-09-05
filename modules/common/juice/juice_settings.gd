## Juice's two accessibility/taste knobs, persisted independently of any design.
##
## Kept apart from [Juice] itself so the load/save path can be exercised without
## a scene tree, and so a future settings screen has one small surface to bind
## to instead of reaching into the runtime.
class_name JuiceSettings
extends RefCounted

const SETTINGS_PATH := "user://juice.cfg"
const SECTION := "juice"

const INTENSITY_MIN := 0.0
const INTENSITY_MAX := 1.5
const INTENSITY_DEFAULT := 1.0

static var intensity := INTENSITY_DEFAULT
## When true, every entry point in [Juice] that produces motion — shake, hitstop,
## streaks, speed lines — is short-circuited to nothing. Colour and scale cues
## stay, because those carry information reduce_motion is not meant to hide.
static var reduce_motion := false


static func set_intensity(value: float) -> void:
	intensity = clampf(value, INTENSITY_MIN, INTENSITY_MAX)
	_save()


static func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	_save()


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	intensity = clampf(
		float(cfg.get_value(SECTION, "intensity", INTENSITY_DEFAULT)), INTENSITY_MIN, INTENSITY_MAX
	)
	reduce_motion = bool(cfg.get_value(SECTION, "reduce_motion", false))


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "intensity", intensity)
	cfg.set_value(SECTION, "reduce_motion", reduce_motion)
	cfg.save(SETTINGS_PATH)
