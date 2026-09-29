## The looks the mobile HUD ([MobileHud]) can wear, which font each uses for
## each text role, and how the touch controls are laid out.
##
## A profile is a palette plus a few shape switches (halftone dots, comic
## bands, how far the panels skew) and a default font per role. The font for
## any role of any profile can be swapped live from the 🔤 HUD fonts panel
## ([MobileHudFontsPanel]), along with its size, weight, spacing, outline and
## lean; overrides persist in [constant SETTINGS_PATH]. The touch scheme
## (Simple / Standard / Pro) and the left-right swap live here too, so the
## whole phone setup is one file.
## Static, like [JuiceSettings], so the HUD, the panel and a smoke can all
## reach it without a node.
class_name MobileHudProfiles
extends RefCounted

const SETTINGS_PATH := "user://mobile_hud.cfg"
## Every .ttf/.otf in here is offered in the font pickers.
const FONT_DIR := "res://assets/fonts/"
## Picker entry meaning "no override: the HUD theme's own font".
const DEFAULT_FONT := ""

## The text roles a profile sets a font for, in picker order.
const ROLES := ["title", "number", "label"]
const ROLE_NAMES := {
	"title": "Titles (HEALTH, KMH!)",
	"number": "Numbers (speed readouts)",
	"label": "Small labels",
}

const PROFILES := {
	"comic": {
		"name": "Comic",
		"fonts": {"title": "FOO.ttf", "number": "FOO.ttf", "label": "nasalization-rg.ttf"},
		"halftone": true, "bands": true, "skew": 0.35, "outline": 7, "comic_fx": true, "graffiti": true,
		"panel": Color("ffb21e"), "panel_dots": Color("ff7a00"), "panel_edge": Color("1a1a1a"),
		"band": Color("1f6fff"), "band_light": Color("ffffff"), "corner": Color("ff9a1f"),
		"hull": Color("ff3b3b"), "shield": Color("3fa9ff"), "bar_bg": Color("26262e"),
		"icon_bg": Color("1d2a44"), "icon": Color("ffffff"),
		"title": Color("ffffff"), "title_outline": Color("141414"),
		"speed": Color("ffffff"), "speed_unit": Color("ffcc1a"), "speed_outline": Color("141414"),
		"button": Color("1a1d27", 0.88), "button_rim": Color("ffffff"), "button_icon": Color("ffffff"),
		"fire_rim": Color("ffffff"), "dial_ring": Color("3fa9ff"), "stick": Color("1a1d27", 0.8),
	},
	"pop": {
		"name": "Pop Art",
		"fonts": {"title": "orange juice 2.0.ttf", "number": "ka1.ttf", "label": "Bo_Toy.otf"},
		"halftone": true, "bands": true, "skew": 0.28, "outline": 8, "comic_fx": true, "graffiti": true,
		"panel": Color("ff4fa3"), "panel_dots": Color("c2187a"), "panel_edge": Color("15101c"),
		"band": Color("ffe23d"), "band_light": Color("15101c"), "corner": Color("3dd6ff"),
		"hull": Color("ffe23d"), "shield": Color("3dd6ff"), "bar_bg": Color("2a1830"),
		"icon_bg": Color("15101c"), "icon": Color("ffe23d"),
		"title": Color("ffe23d"), "title_outline": Color("15101c"),
		"speed": Color("ffffff"), "speed_unit": Color("ff4fa3"), "speed_outline": Color("15101c"),
		"button": Color("2a1830", 0.9), "button_rim": Color("ffe23d"), "button_icon": Color("ffffff"),
		"fire_rim": Color("ff4fa3"), "dial_ring": Color("3dd6ff"), "stick": Color("2a1830", 0.8),
	},
	"neon": {
		"name": "Neon",
		"fonts": {"title": "nasalization-rg.ttf", "number": "nasalization-rg.ttf", "label": "Terminus.ttf"},
		"halftone": false, "bands": false, "skew": 0.18, "outline": 0,
		"panel": Color("06121f", 0.72), "panel_dots": Color("33f0ff", 0.0), "panel_edge": Color("33f0ff"),
		"band": Color("33f0ff", 0.0), "band_light": Color("33f0ff", 0.0), "corner": Color("33f0ff", 0.0),
		"hull": Color("ff3d7f"), "shield": Color("33f0ff"), "bar_bg": Color("0b1e2c", 0.9),
		"icon_bg": Color("0b1e2c"), "icon": Color("33f0ff"),
		"title": Color("33f0ff"), "title_outline": Color("000000", 0.0),
		"speed": Color("eaffff"), "speed_unit": Color("ff3d7f"), "speed_outline": Color("000000", 0.0),
		"button": Color("06121f", 0.55), "button_rim": Color("33f0ff"), "button_icon": Color("33f0ff"),
		"fire_rim": Color("ff3d7f"), "dial_ring": Color("33f0ff"), "stick": Color("06121f", 0.5),
	},
	"clean": {
		"name": "Clean",
		"fonts": {"title": "Aadhunik.ttf", "number": "nasalization-rg.ttf", "label": ""},
		"halftone": false, "bands": false, "skew": 0.0, "outline": 0,
		"panel": Color("000000", 0.32), "panel_dots": Color("ffffff", 0.0), "panel_edge": Color("ffffff", 0.18),
		"band": Color("ffffff", 0.0), "band_light": Color("ffffff", 0.0), "corner": Color("ffffff", 0.0),
		"hull": Color("ff5a5a"), "shield": Color("6ec6ff"), "bar_bg": Color("ffffff", 0.12),
		"icon_bg": Color("ffffff", 0.1), "icon": Color("ffffff", 0.85),
		"title": Color("ffffff", 0.9), "title_outline": Color("000000", 0.0),
		"speed": Color("ffffff"), "speed_unit": Color("ffffff", 0.6), "speed_outline": Color("000000", 0.0),
		"button": Color("000000", 0.3), "button_rim": Color("ffffff", 0.55), "button_icon": Color("ffffff", 0.9),
		"fire_rim": Color("ffffff", 0.8), "dial_ring": Color("ffffff", 0.6), "stick": Color("000000", 0.28),
	},
}

## Touch control schemes: which widgets the mobile HUD shows and how the
## throttle is driven.
const SCHEMES := {
	"simple": {
		"name": "Simple — hold to fly",
		"desc": "Hold anywhere on the stick side to fly at your cruise speed; drag to steer. Let go and the ship slows. Fire only.",
	},
	"standard": {
		"name": "Standard",
		"desc": "Stick, throttle dial with up/down, fire, boost and weapon swap.",
	},
	"pro": {
		"name": "Pro",
		"desc": "Standard plus roll left/right and a target-lock button.",
	},
}
const SCHEME_ORDER := ["simple", "standard", "pro"]

## Per-profile text styling beyond the font file, stored beside the font
## overrides: "size_<role>" (× size), "bold_<role>" (embolden), "space_<role>"
## (extra px between glyphs), "outline" (× the profile's outline) and "lean"
## (× the comic italic lean). These are the neutral values.
const STYLE_DEFAULTS := {
	"size_title": 1.0, "size_number": 1.0, "size_label": 1.0,
	"bold_title": 0.0, "bold_number": 0.0, "bold_label": 0.0,
	"space_title": 0.0, "space_number": 0.0, "space_label": 0.0,
	"outline": 1.0, "lean": 1.0,
}
## Slider range per style kind (the key's prefix before the first "_").
const STYLE_RANGES := {
	"size": Vector2(0.6, 1.6), "bold": Vector2(0.0, 1.2), "space": Vector2(-2.0, 8.0),
	"outline": Vector2(0.0, 2.5), "lean": Vector2(0.0, 2.5),
}

static var active := "comic"
## profile id -> {role -> font file name, or DEFAULT_FONT; style key -> float}.
## Only overrides.
static var _overrides := {}
## Bumped on every change, so a HUD can notice by polling instead of wiring.
static var revision := 0
static var _loaded := false
static var _font_cache := {}

## The active touch scheme (a [constant SCHEMES] key).
static var scheme := "standard"
## Mirror the controls: stick on the right, buttons and throttle on the left.
static var swap_sides := false
## The throttle the Simple scheme flies at while a thumb is down, 0..1.
static var simple_speed := 0.75
## Roll a fresh font combo for the active profile every time the game starts.
static var random_fonts_on_launch := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH) != OK:
		return
	var id := String(cfg.get_value("hud", "active", active))
	if PROFILES.has(id):
		active = id
	for pid: String in PROFILES:
		if cfg.has_section_key("fonts", pid):
			var d: Variant = cfg.get_value("fonts", pid)
			if d is Dictionary:
				_overrides[pid] = d
	var sc := String(cfg.get_value("controls", "scheme", scheme))
	if SCHEMES.has(sc):
		scheme = sc
	swap_sides = bool(cfg.get_value("controls", "swap_sides", swap_sides))
	simple_speed = clampf(float(cfg.get_value("controls", "simple_speed", simple_speed)), 0.1, 1.0)
	random_fonts_on_launch = bool(cfg.get_value("hud", "random_fonts_on_launch", false))
	if random_fonts_on_launch:
		randomize_fonts()


static func profile_ids() -> Array:
	return PROFILES.keys()


static func profile(id := "") -> Dictionary:
	ensure_loaded()
	return PROFILES.get(id if id != "" else active, PROFILES["comic"])


static func color(key: String) -> Color:
	return profile().get(key, Color.WHITE)


static func set_active(id: String) -> void:
	ensure_loaded()
	if not PROFILES.has(id):
		return
	active = id
	_changed()


## The font file a role uses in a profile: its override if set, else the
## profile's default. [constant DEFAULT_FONT] means the theme font.
static func font_file(role: String, id := "") -> String:
	ensure_loaded()
	var pid := id if id != "" else active
	var o: Dictionary = _overrides.get(pid, {})
	if o.has(role):
		return String(o[role])
	return String((profile(pid)["fonts"] as Dictionary).get(role, DEFAULT_FONT))


## The loaded font for a role, or null for "use the theme's font". Wrapped in
## a [FontVariation] when the role has a bold or letter-spacing style set.
static func font(role: String, id := "") -> Font:
	var file := font_file(role, id)
	if file == DEFAULT_FONT:
		return null
	if not _font_cache.has(file):
		var path := FONT_DIR + file
		_font_cache[file] = load(path) as Font if ResourceLoader.exists(path) else null
	var base: Font = _font_cache[file]
	var bold := style("bold_" + role, id)
	var space := style("space_" + role, id)
	if base == null or (is_zero_approx(bold) and is_zero_approx(space)):
		return base
	var key := "%s|%.2f|%.1f" % [file, bold, space]
	if not _font_cache.has(key):
		var v := FontVariation.new()
		v.base_font = base
		v.variation_embolden = bold
		v.spacing_glyph = roundi(space)
		_font_cache[key] = v
	return _font_cache[key]


static func set_font(role: String, file: String, id := "") -> void:
	ensure_loaded()
	var pid := id if id != "" else active
	var o: Dictionary = _overrides.get(pid, {})
	o[role] = file
	_overrides[pid] = o
	_changed()


## Drop a profile's font and text-style overrides, back to its shipped defaults.
static func reset_fonts(id := "") -> void:
	ensure_loaded()
	_overrides.erase(id if id != "" else active)
	_changed()


## One text-style value for a profile (see [constant STYLE_DEFAULTS]).
static func style(key: String, id := "") -> float:
	ensure_loaded()
	var o: Dictionary = _overrides.get(id if id != "" else active, {})
	return float(o.get(key, STYLE_DEFAULTS.get(key, 0.0)))


static func set_style(key: String, value: float, id := "") -> void:
	ensure_loaded()
	var pid := id if id != "" else active
	var r := style_range(key)
	var o: Dictionary = _overrides.get(pid, {})
	o[key] = clampf(value, r.x, r.y)
	_overrides[pid] = o
	_changed()


## The slider range for a style key.
static func style_range(key: String) -> Vector2:
	return STYLE_RANGES[key.get_slice("_", 0)]


## Roll a random font combo for a profile: a face for the titles, (usually) a
## different one for the numbers, anything for the small labels, plus a little
## random weight, spacing, lean and outline so combos differ in more than the
## typeface. Sizes and spacing stay near neutral so the HUD stays legible.
static func randomize_fonts(id := "") -> void:
	var pid := id if id != "" else active
	var fonts := available_fonts()
	if fonts.is_empty():
		return
	var title := fonts[randi() % fonts.size()]
	var number := fonts[randi() % fonts.size()]
	# The contrast between two faces is what makes a combo read as designed.
	if number == title and fonts.size() > 1 and randf() < 0.75:
		number = fonts[(fonts.find(title) + 1 + randi() % (fonts.size() - 1)) % fonts.size()]
	var o := {
		"title": title,
		"number": number,
		"label": fonts[randi() % fonts.size()] if randf() < 0.7 else DEFAULT_FONT,
		"size_title": snappedf(randf_range(0.9, 1.2), 0.05),
		"size_number": snappedf(randf_range(0.9, 1.15), 0.05),
		"bold_title": snappedf(randf_range(0.0, 0.6), 0.1) if randf() < 0.5 else 0.0,
		"space_title": float(randi_range(-1, 3)),
		"space_number": float(randi_range(-1, 2)),
		"lean": snappedf(randf_range(0.4, 1.6), 0.1),
		"outline": snappedf(randf_range(0.8, 1.5), 0.1),
	}
	_overrides[pid] = o
	_changed()


static func set_scheme(id: String) -> void:
	ensure_loaded()
	if SCHEMES.has(id):
		scheme = id
		_changed()


static func set_swap_sides(on: bool) -> void:
	ensure_loaded()
	swap_sides = on
	_changed()


static func set_simple_speed(v: float) -> void:
	ensure_loaded()
	simple_speed = clampf(v, 0.1, 1.0)
	_changed()


static func set_random_fonts_on_launch(on: bool) -> void:
	ensure_loaded()
	random_fonts_on_launch = on
	_changed()


## Every font file in [constant FONT_DIR]. An exported build lists the
## `.import` stubs rather than the fonts, so those are mapped back.
static func available_fonts() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(FONT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".import")
		var ext := name.get_extension().to_lower()
		if (ext == "ttf" or ext == "otf") and not out.has(name):
			out.append(name)
	out.sort()
	return out


static func _changed() -> void:
	revision += 1
	var cfg := ConfigFile.new()
	cfg.set_value("hud", "active", active)
	cfg.set_value("hud", "random_fonts_on_launch", random_fonts_on_launch)
	cfg.set_value("controls", "scheme", scheme)
	cfg.set_value("controls", "swap_sides", swap_sides)
	cfg.set_value("controls", "simple_speed", simple_speed)
	for pid: String in _overrides:
		cfg.set_value("fonts", pid, _overrides[pid])
	cfg.save(SETTINGS_PATH)
	GameDefaults.note_saved(SETTINGS_PATH)
