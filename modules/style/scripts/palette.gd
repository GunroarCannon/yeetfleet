## Palette: one named set of colours the whole game draws from.
##
## A palette is the single source of truth for every colour in the game — the void
## behind the stars, hull paint, rock and station greys, planet hues, the nebula,
## and the interface chrome itself. Modules never read a colour literal; they ask
## [method color] for a role by name, so switching the active palette recolours the
## whole game from one place.
##
## Roles are declared once in [constant ROLES] — key, human label, and the group
## the picker files it under — and every key has a matching [code]@export[/code]
## below. [method swatches] walks [constant ROLES] and reads each key back off this
## resource, which is what lets the palette picker draw every colour a palette
## contains without a hand-maintained second list to drift out of step.
##
## The active palette lives on [StyleManager] and is read through the static
## [method color] helper, mirroring [method Palette.get_sat_lifted_color]'s
## "read the live manager, need no instance" shape. With no palette set, every
## role falls back to [constant DEFAULTS], which holds the exact literals this
## system replaced — so an unconfigured game looks like it always did.
##
## See TECHNICAL_PLAN.md §3.3.
@tool
class_name Palette extends Resource

# --- Role table -------------------------------------------------------------

## Every colour role: the key [method color] takes, the label the picker shows,
## and the group it is filed under. Order matters — the picker draws the palette
## in exactly this order.
const ROLES: Array[Dictionary] = [
	{"key": "background", "label": "Void", "group": "World"},
	{"key": "ambient", "label": "Ambient light", "group": "World"},
	{"key": "star", "label": "Star", "group": "World"},
	{"key": "nebula_core", "label": "Nebula core", "group": "World"},
	{"key": "nebula_edge", "label": "Nebula edge", "group": "World"},
	{"key": "hull_primary", "label": "Hull primary", "group": "Hull"},
	{"key": "hull_accent", "label": "Hull accent", "group": "Hull"},
	{"key": "hull_trim", "label": "Hull trim", "group": "Hull"},
	{"key": "rock_light", "label": "Rock light", "group": "Rock"},
	{"key": "rock_mid", "label": "Rock mid", "group": "Rock"},
	{"key": "rock_dark", "label": "Rock dark", "group": "Rock"},
	{"key": "rock_accent", "label": "Rock accent", "group": "Rock"},
	{"key": "metal_light", "label": "Metal light", "group": "Metal"},
	{"key": "metal_mid", "label": "Metal mid", "group": "Metal"},
	{"key": "metal_dark", "label": "Metal dark", "group": "Metal"},
	{"key": "planet_primary", "label": "Planet ground", "group": "Planet"},
	{"key": "planet_secondary", "label": "Planet highland", "group": "Planet"},
	{"key": "planet_water", "label": "Planet water", "group": "Planet"},
	{"key": "planet_ring", "label": "Planet ring", "group": "Planet"},
	{"key": "planet_cloud", "label": "Planet cloud", "group": "Planet"},
	{"key": "planet_atmosphere", "label": "Planet atmosphere", "group": "Planet"},
	{"key": "ui_bg_deep", "label": "UI void", "group": "Interface"},
	{"key": "ui_bg_panel", "label": "UI panel", "group": "Interface"},
	{"key": "ui_bg_panel_alt", "label": "UI panel alt", "group": "Interface"},
	{"key": "ui_bg_field", "label": "UI field", "group": "Interface"},
	{"key": "ui_bg_hover", "label": "UI hover", "group": "Interface"},
	{"key": "ui_border", "label": "UI border", "group": "Interface"},
	{"key": "ui_border_strong", "label": "UI border strong", "group": "Interface"},
	{"key": "ui_text", "label": "UI text", "group": "Interface"},
	{"key": "ui_text_dim", "label": "UI text dim", "group": "Interface"},
	{"key": "ui_text_strong", "label": "UI text strong", "group": "Interface"},
	{"key": "ui_accent", "label": "UI accent", "group": "Interface"},
	{"key": "ui_accent_dim", "label": "UI accent dim", "group": "Interface"},
	{"key": "ui_good", "label": "UI good", "group": "Interface"},
	{"key": "ui_warn", "label": "UI warn", "group": "Interface"},
	{"key": "ui_bad", "label": "UI bad", "group": "Interface"},
	{"key": "ui_select", "label": "UI select", "group": "Interface"},
	{"key": "valid", "label": "Drop valid", "group": "Affordance"},
	{"key": "invalid", "label": "Drop invalid", "group": "Affordance"},
	{"key": "hover", "label": "Hover", "group": "Affordance"},
	{"key": "socket", "label": "Socket", "group": "Affordance"},
	{"key": "grid", "label": "Grid", "group": "Affordance"},
	{"key": "beam", "label": "Beam", "group": "Affordance"},
]

## The literals this system replaced, used when a role is missing or no palette is
## active. Keeping them exact is what lets the palette rollout be invisible until
## somebody actually picks a different palette.
const DEFAULTS := {
	"background": Color("03050a"),
	"ambient": Color("2a3448"),
	"star": Color(1.0, 0.85, 0.55),
	"nebula_core": Color(1.0, 0.55, 0.28),
	"nebula_edge": Color(0.35, 0.15, 0.55),
	"hull_primary": Color(0.29, 0.33, 0.40),
	"hull_accent": Color(0.87, 0.55, 0.16),
	"hull_trim": Color(0.09, 0.10, 0.13),
	"rock_light": Color("8d97a6"),
	"rock_mid": Color("6a6257"),
	"rock_dark": Color("3d3831"),
	"rock_accent": Color("d0a24a"),
	"metal_light": Color(0.86, 0.90, 1.0),
	"metal_mid": Color(0.45, 0.42, 0.40),
	"metal_dark": Color(0.09, 0.10, 0.13),
	"planet_primary": Color(0.45, 0.32, 0.22),
	"planet_secondary": Color(0.68, 0.55, 0.38),
	"planet_water": Color(0.09, 0.22, 0.38),
	"planet_ring": Color(0.75, 0.70, 0.62),
	"planet_cloud": Color(0.95, 0.96, 1.0),
	"planet_atmosphere": Color(0.45, 0.72, 1.0),
	"ui_bg_deep": Color("0b0e13"),
	"ui_bg_panel": Color("141922"),
	"ui_bg_panel_alt": Color("1b2230"),
	"ui_bg_field": Color("0e131b"),
	"ui_bg_hover": Color("232c3d"),
	"ui_border": Color("2b3546"),
	"ui_border_strong": Color("3f4c63"),
	"ui_text": Color("d7dee8"),
	"ui_text_dim": Color("8b97a8"),
	"ui_text_strong": Color("f2f6fb"),
	"ui_accent": Color("39c0ff"),
	"ui_accent_dim": Color("1d6f96"),
	"ui_good": Color("5ddba0"),
	"ui_warn": Color("ffc65c"),
	"ui_bad": Color("ff7a6b"),
	"ui_select": Color("ffd84d"),
	"valid": Color("39c0ff"),
	"invalid": Color("ff8a3d"),
	"hover": Color("8fe3ff"),
	"socket": Color("7d8b9c"),
	"grid": Color(0.30, 0.36, 0.44, 0.35),
	"beam": Color("6ff0d0"),
}

## Where the built-in palettes live, and the one the game starts on.
const DIR := "res://modules/style/data/palettes"

# --- Identity ---------------------------------------------------------------

## Stable id, matching the file name. What [method StyleManager.set_palette_by_id]
## and the saved setting use.
@export var id := ""
## Name shown in the picker.
@export var display_name := "Untitled"

# --- World ------------------------------------------------------------------

@export_group("World")
@export var background := Color("03050a")
@export var ambient := Color("2a3448")
@export var star := Color(1.0, 0.85, 0.55)
@export var nebula_core := Color(1.0, 0.55, 0.28)
@export var nebula_edge := Color(0.35, 0.15, 0.55)

# --- Hull -------------------------------------------------------------------

@export_group("Hull")
@export var hull_primary := Color(0.29, 0.33, 0.40)
@export var hull_accent := Color(0.87, 0.55, 0.16)
@export var hull_trim := Color(0.09, 0.10, 0.13)

# --- Rock -------------------------------------------------------------------

@export_group("Rock")
@export var rock_light := Color("8d97a6")
@export var rock_mid := Color("6a6257")
@export var rock_dark := Color("3d3831")
@export var rock_accent := Color("d0a24a")

# --- Metal ------------------------------------------------------------------

@export_group("Metal")
@export var metal_light := Color(0.86, 0.90, 1.0)
@export var metal_mid := Color(0.45, 0.42, 0.40)
@export var metal_dark := Color(0.09, 0.10, 0.13)

# --- Planet -----------------------------------------------------------------

@export_group("Planet")
@export var planet_primary := Color(0.45, 0.32, 0.22)
@export var planet_secondary := Color(0.68, 0.55, 0.38)
@export var planet_water := Color(0.09, 0.22, 0.38)
@export var planet_ring := Color(0.75, 0.70, 0.62)
@export var planet_cloud := Color(0.95, 0.96, 1.0)
@export var planet_atmosphere := Color(0.45, 0.72, 1.0)

# --- Interface --------------------------------------------------------------

@export_group("Interface")
@export var ui_bg_deep := Color("0b0e13")
@export var ui_bg_panel := Color("141922")
@export var ui_bg_panel_alt := Color("1b2230")
@export var ui_bg_field := Color("0e131b")
@export var ui_bg_hover := Color("232c3d")
@export var ui_border := Color("2b3546")
@export var ui_border_strong := Color("3f4c63")
@export var ui_text := Color("d7dee8")
@export var ui_text_dim := Color("8b97a8")
@export var ui_text_strong := Color("f2f6fb")
@export var ui_accent := Color("39c0ff")
@export var ui_accent_dim := Color("1d6f96")
@export var ui_good := Color("5ddba0")
@export var ui_warn := Color("ffc65c")
@export var ui_bad := Color("ff7a6b")
@export var ui_select := Color("ffd84d")

# --- Affordance -------------------------------------------------------------

@export_group("Affordance")
@export var valid := Color("39c0ff")
@export var invalid := Color("ff8a3d")
@export var hover := Color("8fe3ff")
@export var socket := Color("7d8b9c")
@export var grid := Color(0.30, 0.36, 0.44, 0.35)
@export var beam := Color("6ff0d0")

# --- Reading ----------------------------------------------------------------

## This palette's colour for [param role]. Falls back to [constant DEFAULTS] for a
## key this palette does not define, so a palette saved before a role existed
## still renders instead of coming back magenta.
func get_role(role: String) -> Color:
	var value: Variant = get(role)
	if value is Color:
		return value
	var fallback: Variant = DEFAULTS.get(role)
	if fallback is Color:
		return fallback
	push_warning("Palette '%s' has no colour role '%s'" % [id, role])
	return Color.MAGENTA


## Every colour this palette contains, in picker order: one
## `{key, label, group, color}` row per entry in [constant ROLES].
func swatches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in ROLES:
		var key := String(row["key"])
		out.append({
			"key": key,
			"label": String(row["label"]),
			"group": String(row["group"]),
			"color": get_role(key),
		})
	return out


# --- Static access ----------------------------------------------------------

## The live palette's colour for [param role], or [constant DEFAULTS] when
## nothing is active. This is what every module calls.
static func color(role: String) -> Color:
	var active := _active()
	if active != null:
		return active.get_role(role)
	var fallback: Variant = DEFAULTS.get(role)
	if fallback is Color:
		return fallback
	push_warning("Palette has no colour role '%s'" % role)
	return Color.MAGENTA


## The live palette's colour for [param role] with the live style's saturation and
## lift dials applied. This is the one world-facing call sites want: it is
## [method color] plus the pastel-ise pass, so a palette and a look compose
## without either knowing about the other.
static func styled_color(role: String) -> Color:
	return get_sat_lifted_color(color(role))


## The active palette, or null when the game is running on [constant DEFAULTS].
static func _active() -> Palette:
	var mgr := StyleManager.instance()
	return mgr.current_palette if mgr != null else null


## Load every palette in [constant DIR], sorted by display name, for the picker.
## Returns an empty array rather than erroring when the directory is missing, so a
## stripped build still boots.
static func all() -> Array[Palette]:
	var out: Array[Palette] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		# Exported projects report the stripped name; the editor reports the
		# full one.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var res := load(DIR.path_join(file_name.trim_suffix(".remap")))
		if res is Palette:
			out.append(res)
	out.sort_custom(func(a: Palette, b: Palette) -> bool: return a.display_name < b.display_name)
	return out


## Look a palette up by [member id], falling back to the first one available so a
## saved id that no longer exists cannot leave the game unpaletted.
static func find_by_id(wanted: String) -> Palette:
	var available := all()
	for p in available:
		if p.id == wanted:
			return p
	return available[0] if not available.is_empty() else null


## How many nebula wash variants the backdrops cycle through.
const NEBULA_WASHES := 4


## The `{core, edge}` pair for nebula wash [param index], from the palette's nebula
## roles.
##
## Each variant turns the hue a little and alternates which of the pair leads, so
## four washes read as four clouds rather than one colour at four widths. Alphas
## are left at 1.0 — the caller sets its own, because a billboard puff and a sky
## ribbon want very different opacities out of the same wash.
static func nebula_wash(index: int) -> Dictionary:
	var core := color("nebula_core")
	var edge := color("nebula_edge")
	var i := posmod(index, NEBULA_WASHES)
	var shift: float = [0.0, 0.10, -0.12, 0.22][i]
	var lead := i % 2 == 1
	var primary := edge if lead else core
	var secondary := core if lead else edge
	primary = Color.from_hsv(fmod(primary.h + shift + 1.0, 1.0), primary.s, primary.v, 1.0)
	return {"core": primary, "edge": secondary}


## A planet body colour, anchored to one of the palette's two planet hues.
##
## [param index] picks the anchor — even draws [code]planet_primary[/code], odd
## [code]planet_secondary[/code] — [param jitter] is how far the hue may wander, in
## turns, and [param rng] supplies the wander.
##
## Planets used to take a hue from the whole colour wheel, which meant a generated
## system landed somewhere different from the rest of the game and no palette could
## ever describe one. Anchoring keeps a system's worlds recognisably from the same
## place while the hue jitter and the saturation/value spread stop a system's eight
## planets reading as eight copies of one colour.
static func planet_color(index: int, jitter: float, rng: RandomNumberGenerator) -> Color:
	var anchor := color("planet_primary") if index % 2 == 0 else color("planet_secondary")
	var hue := fmod(anchor.h + rng.randf_range(-jitter, jitter) + 1.0, 1.0)
	var sat := clampf(anchor.s * rng.randf_range(0.75, 1.30), 0.12, 0.95)
	var val := clampf(anchor.v * rng.randf_range(0.80, 1.25), 0.18, 0.96)
	return Color.from_hsv(hue, sat, val)


## A planet's water colour: the palette's own sea tone, pulled toward [param ground]
## so a world's oceans sit in the same family as its land rather than looking
## borrowed from a different system.
##
## Named "sea" rather than "water" because [member planet_water] is the palette's
## own role and a static cannot share a name with a property.
static func planet_sea(ground: Color, mix: float) -> Color:
	return color("planet_water").lerp(ground, clampf(mix, 0.0, 1.0))


## A planet's atmosphere colour: the palette's atmosphere tone, nudged toward
## [param ground] and rotated by [param hue_shift] so a system's worlds do not all
## wear the same sky. Named "sky" for the same reason as [method planet_sea].
static func planet_sky(ground: Color, hue_shift: float, mix: float) -> Color:
	var base := color("planet_atmosphere").lerp(ground, clampf(mix, 0.0, 1.0))
	if is_zero_approx(hue_shift):
		return base
	return Color.from_hsv(fmod(base.h + hue_shift + 1.0, 1.0), base.s, base.v, base.a)


## How many rock colour families the world draws from. Four because a belt of
## identical asteroids reads as one asset repeated rather than a field of rocks.
const ROCK_FAMILIES := 4


## The `{primary, accent, trim}` triple for rock family [param index], derived from
## the palette's rock roles.
##
## Four *related* triples rather than four independent colour lists: a palette
## author picks three rock colours and gets a varied field out of them, instead of
## having to supply twelve values that already agree with each other.
static func rock_family(index: int) -> Dictionary:
	var light := color("rock_light")
	var mid := color("rock_mid")
	var dark := color("rock_dark")
	var accent := color("rock_accent")
	var families := [
		{"primary": light, "accent": accent, "trim": mid.darkened(0.28)},
		{"primary": mid, "accent": light.darkened(0.08), "trim": dark},
		{"primary": mid.lightened(0.10), "accent": accent.darkened(0.22), "trim": dark.lightened(0.05)},
		{"primary": dark.lightened(0.22), "accent": mid, "trim": dark.darkened(0.30)},
	]
	return families[posmod(index, families.size())]


## Apply the style dials to [param base] and return the result.
##
## Reads the live [StyleManager] profile rather than any instance state, so
## callers use it as `Palette.get_sat_lifted_color(color)` with no Palette
## instance needed. That is what lets [ShipMaterials] and the rock/planet material
## builders call into the style module through one function without owning a
## Palette resource each.
static func get_sat_lifted_color(base: Color) -> Color:
	var style := StyleManager.instance().current_profile
	if not style:
		return base

	# Lift the palette: palette_lift interpolates toward white (negative pulls
	# the other way, darkening). palette_lift is -0.5..0.5, so double it to use
	# the full lerp range.
	var lifted := base
	if style.palette_lift > 0.0:
		lifted = base.lerp(Color.WHITE, style.palette_lift * 2.0)
	elif style.palette_lift < 0.0:
		lifted = base.lerp(Color.BLACK, -style.palette_lift * 2.0)
	# Then desaturate: interpolate toward a gray at the same value by how far the
	# palette_saturation dial drops below full saturation. Above 1.0, push past
	# full saturation instead (extrapolating the lerp) for a punchier look.
	var gray := Color(lifted.v, lifted.v, lifted.v, lifted.a)
	return gray.lerp(lifted, style.palette_saturation)
