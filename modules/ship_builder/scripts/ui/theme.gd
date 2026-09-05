## Colours, fonts and pre-built StyleBoxes for the builder UI.
##
## Built in code rather than as a .theme resource for two reasons: the palette has
## to switch to high contrast at runtime without reloading the scene, and a theme
## generated from constants can share exactly the same colours the 3D view uses
## (see [ShipMaterials]) so a selected part and its row in the tree read as the
## same thing.
class_name BuilderTheme
extends RefCounted

# --- Palette ---------------------------------------------------------------
# Dark, low-saturation greys so the ship and its accent colours are the only
# saturated things on screen.

const BG_DEEP := Color("0b0e13")
const BG_PANEL := Color("141922")
const BG_PANEL_ALT := Color("1b2230")
const BG_FIELD := Color("0e131b")
const BG_HOVER := Color("232c3d")
const BORDER := Color("2b3546")
const BORDER_STRONG := Color("3f4c63")

const TEXT := Color("d7dee8")
const TEXT_DIM := Color("8b97a8")
const TEXT_STRONG := Color("f2f6fb")

const ACCENT := Color("39c0ff")
const ACCENT_DIM := Color("1d6f96")
const GOOD := Color("5ddba0")
const WARN := Color("ffc65c")
const BAD := Color("ff7a6b")
const SELECT := Color("ffd84d")

# High-contrast overrides. Not a separate theme: only the values that fail a
# contrast check are replaced, so the layout never shifts when the toggle flips.
const HC_BG_PANEL := Color("000000")
const HC_BG_PANEL_ALT := Color("0a0a0a")
const HC_BG_FIELD := Color("000000")
const HC_BORDER := Color("8899aa")
const HC_BORDER_STRONG := Color("ffffff")
const HC_TEXT := Color("ffffff")
const HC_TEXT_DIM := Color("cfd8e3")
const HC_ACCENT := Color("00e5ff")
const HC_GOOD := Color("46ff9b")
const HC_WARN := Color("ffb000")
const HC_BAD := Color("ff5b47")

## Minimum height for anything tappable. 44 units is the smallest target that is
## reliably hittable with a thumb, and the builder is meant to work on a phone.
##
## That promise only holds if one UI unit is roughly one density-independent
## pixel, which is what [method apply_density_scale] exists to arrange. Without
## it, a 44-unit button on a 400 dpi phone lands at about 26 dp — visibly there,
## and consistently missed.
const TOUCH_MIN := 44
const GAP := 6
const PAD := 10

## Reference resolution, matching the project's stretch settings. The scale the
## stretch system has already applied has to be divided back out before a density
## correction can be applied on top of it.
const BASE_SIZE := Vector2(1280, 720)
## Android's baseline: 160 dpi is 1 dp = 1 px.
const BASELINE_DPI := 160.0
## Bounds on the correction. A phone that reports nonsense for its DPI — and some
## do — should give a slightly wrong UI, never an unusable one.
const MIN_SCALE := 0.75
const MAX_SCALE := 3.0

static var high_contrast := false


## Make one UI unit mean one density-independent pixel on a handheld screen.
##
## The project stretches a 1280x720 canvas to fill the window, which already
## multiplies everything by `min(w/1280, h/720)`. On a desktop monitor that is
## the right answer and nothing more is needed. On a 1080x2400 phone it is not:
## the window is enormous in pixels and small in centimetres, so the stretch
## leaves the whole interface at roughly half the physical size a thumb needs.
##
## Dividing the stretch factor back out and multiplying by dpi/160 leaves the
## content scale expressed in dp — which incidentally hands the layout a sensible
## logical size to make its narrow/wide decision from, instead of the 1600-unit
## fiction the raw stretch produces for a phone held sideways.
static func apply_density_scale(window: Window) -> void:
	if window == null:
		return
	var wanted := density_scale(Vector2(window.size))
	if not is_equal_approx(window.content_scale_factor, wanted):
		window.content_scale_factor = wanted


## The correction factor for a window of this pixel size. Split out from
## [method apply_density_scale] so it can be reasoned about and tested without a
## Window.
static func density_scale(window_px: Vector2) -> float:
	# Desktops are already in the right ballpark, and a user who has set their OS
	# scaling has said what they want; second-guessing it shrinks their UI.
	if not OS.has_feature("mobile"):
		return 1.0
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 1.0:
		return 1.0
	var stretch := minf(
		maxf(window_px.x, 1.0) / BASE_SIZE.x,
		maxf(window_px.y, 1.0) / BASE_SIZE.y
	)
	if stretch <= 0.001:
		return 1.0
	return clampf((dpi / BASELINE_DPI) / stretch, MIN_SCALE, MAX_SCALE)


static func text() -> Color:
	return HC_TEXT if high_contrast else TEXT


static func text_dim() -> Color:
	return HC_TEXT_DIM if high_contrast else TEXT_DIM


static func accent() -> Color:
	return HC_ACCENT if high_contrast else ACCENT


static func good() -> Color:
	return HC_GOOD if high_contrast else GOOD


static func warn() -> Color:
	return HC_WARN if high_contrast else WARN


static func bad() -> Color:
	return HC_BAD if high_contrast else BAD


static func panel_bg() -> Color:
	return HC_BG_PANEL if high_contrast else BG_PANEL


static func panel_alt_bg() -> Color:
	return HC_BG_PANEL_ALT if high_contrast else BG_PANEL_ALT


static func field_bg() -> Color:
	return HC_BG_FIELD if high_contrast else BG_FIELD


static func border() -> Color:
	return HC_BORDER if high_contrast else BORDER


static func border_strong() -> Color:
	return HC_BORDER_STRONG if high_contrast else BORDER_STRONG


## Colour for a stat's delta: green when the change is an improvement.
static func delta_color(improved: bool, unchanged: bool) -> Color:
	if unchanged:
		return text_dim()
	return good() if improved else bad()


## Severity colour for a stat bar, from 0 (bad) to 1 (good).
static func gauge_color(fraction: float) -> Color:
	if fraction < 0.34:
		return bad()
	if fraction < 0.67:
		return warn()
	return good()


# --- StyleBox factories ----------------------------------------------------

static func flat(
	bg: Color,
	border_color := Color.TRANSPARENT,
	radius := 4,
	border_width := 1
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border_color.a > 0.0:
		sb.border_color = border_color
		sb.set_border_width_all(border_width)
	sb.content_margin_left = PAD
	sb.content_margin_right = PAD
	sb.content_margin_top = GAP
	sb.content_margin_bottom = GAP
	return sb


static func empty(margin := 0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


## Build the whole UI theme. Called once at startup and again whenever the
## high-contrast toggle flips.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	var panel := flat(panel_bg(), border(), 5)
	panel.content_margin_left = PAD
	panel.content_margin_right = PAD
	panel.content_margin_top = PAD
	panel.content_margin_bottom = PAD
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", flat(panel_bg(), border(), 5))

	# Buttons. The focus style is a bright outline rather than a subtle tint,
	# because keyboard users need to see where they are at a glance.
	var btn := flat(panel_alt_bg(), border(), 4)
	var btn_hover := flat(HC_BG_PANEL_ALT if high_contrast else BG_HOVER, border_strong(), 4)
	var btn_pressed := flat(accent().darkened(0.55), accent(), 4)
	var btn_disabled := flat(panel_bg(), border().darkened(0.4), 4)
	var btn_focus := flat(Color.TRANSPARENT, accent(), 4, 2)
	for type in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, btn_hover)
		t.set_stylebox("pressed", type, btn_pressed)
		t.set_stylebox("disabled", type, btn_disabled)
		t.set_stylebox("focus", type, btn_focus)
		t.set_color("font_color", type, text())
		t.set_color("font_hover_color", type, text_strong_color())
		t.set_color("font_pressed_color", type, text_strong_color())
		t.set_color("font_disabled_color", type, text_dim().darkened(0.3))
		t.set_constant("h_separation", type, GAP)

	t.set_stylebox("normal", "LineEdit", flat(field_bg(), border(), 4))
	t.set_stylebox("focus", "LineEdit", flat(field_bg(), accent(), 4, 2))
	t.set_color("font_color", "LineEdit", text())
	t.set_color("font_placeholder_color", "LineEdit", text_dim())
	t.set_color("caret_color", "LineEdit", accent())

	t.set_color("font_color", "Label", text())
	t.set_color("font_color", "RichTextLabel", text())
	t.set_color("default_color", "RichTextLabel", text())

	t.set_stylebox("panel", "Tree", flat(field_bg(), border(), 4))
	t.set_color("font_color", "Tree", text())
	t.set_color("font_selected_color", "Tree", BG_DEEP if not high_contrast else Color.BLACK)
	t.set_stylebox("selected", "Tree", flat(accent().darkened(0.2), Color.TRANSPARENT, 3))
	t.set_stylebox("selected_focus", "Tree", flat(accent(), Color.TRANSPARENT, 3))
	t.set_stylebox("hovered", "Tree", flat(BG_HOVER, Color.TRANSPARENT, 3))
	t.set_stylebox("focus", "Tree", flat(Color.TRANSPARENT, accent(), 4, 2))
	t.set_constant("v_separation", "Tree", 5)
	t.set_color("guide_color", "Tree", border())
	t.set_color("relationship_line_color", "Tree", border_strong())

	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_stylebox("tab_selected", "TabContainer", flat(panel_alt_bg(), accent(), 4))
	t.set_stylebox("tab_unselected", "TabContainer", flat(panel_bg(), border(), 4))
	t.set_stylebox("tab_hovered", "TabContainer", flat(BG_HOVER, border_strong(), 4))
	t.set_stylebox("panel", "TabContainer", flat(panel_bg(), border(), 4))
	t.set_color("font_selected_color", "TabContainer", text_strong_color())
	t.set_color("font_unselected_color", "TabContainer", text_dim())

	t.set_stylebox("slider", "HSlider", flat(field_bg(), border(), 3))
	t.set_stylebox("grabber_area", "HSlider", flat(accent_dim_color(), Color.TRANSPARENT, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(accent(), Color.TRANSPARENT, 3))

	t.set_stylebox("background", "ProgressBar", flat(field_bg(), border(), 3))
	t.set_stylebox("fill", "ProgressBar", flat(accent(), Color.TRANSPARENT, 3))
	t.set_color("font_color", "ProgressBar", text())

	t.set_stylebox("panel", "PopupMenu", flat(panel_alt_bg(), border_strong(), 4))
	t.set_color("font_color", "PopupMenu", text())
	t.set_color("font_hover_color", "PopupMenu", text_strong_color())
	t.set_constant("v_separation", "PopupMenu", 4)

	t.set_stylebox("panel", "TooltipPanel", flat(BG_DEEP, accent(), 4))
	t.set_color("font_color", "TooltipLabel", text())

	t.set_constant("separation", "VBoxContainer", GAP)
	t.set_constant("separation", "HBoxContainer", GAP)
	return t


static func text_strong_color() -> Color:
	return Color.WHITE if high_contrast else TEXT_STRONG


static func accent_dim_color() -> Color:
	return HC_ACCENT.darkened(0.4) if high_contrast else ACCENT_DIM


## A small coloured square used as a legend swatch, built as an icon so it can sit
## inline in a Label or Button.
static func swatch(color: Color, size := 14) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	# A one-pixel border keeps a dark swatch visible against a dark panel.
	var edge := border_strong()
	for i in size:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, size - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(size - 1, i, edge)
	return ImageTexture.create_from_image(img)
