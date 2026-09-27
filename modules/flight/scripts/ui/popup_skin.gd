## PopupSkin: the flight HUD's popups dressed like the mobile HUD — sprayed
## stickers instead of generic rounded dark boxes.
##
## Everything comes from the active [MobileHudProfiles] look, so a popup always
## matches the HUD around it: the profile's panel colour for the sticker's
## thick, uneven border and hard offset shadow, its title font (with the
## profile's outline) for headings, its label font for the rest, and a few
## paint drips and flecks hanging off the top edge ([SprayDecor]). Panels and
## buttons lean a touch, like the HUD's own skewed bands.
##
## [method skin] applies it to a popup that is already built: a [Theme] on the
## root (fonts, buttons, checkboxes), the panel box, headings restyled, and the
## emoji stripped out of every label and button — the popups leaned on them
## for character, and read generic because of it. Called by the HUD for every
## panel it opens; a popup's own colour overrides are kept.
class_name PopupSkin
extends RefCounted

## How far panels and buttons lean (StyleBoxFlat skew, x per unit height).
const LEAN := -0.06
const BUTTON_LEAN := -0.14
## A label with at least this font size is treated as a heading.
const HEADING_SIZE := 14
## The panel's top content margin (the drips hang from the rim above it).
const PANEL_MARGIN_TOP := 18

static var _theme: Theme = null
static var _theme_rev := -1


## The shared popup theme, rebuilt when the mobile HUD's look changes.
static func theme() -> Theme:
	MobileHudProfiles.ensure_loaded()
	if _theme != null and _theme_rev == MobileHudProfiles.revision:
		return _theme
	_theme_rev = MobileHudProfiles.revision
	var ink := ink_color()
	var accent := accent_color()
	var th := Theme.new()
	th.default_font_size = 14
	var label_font := MobileHudProfiles.font("label")
	if label_font != null:
		th.default_font = label_font
	th.set_stylebox("panel", "PanelContainer", panel_box(accent))
	th.set_stylebox("panel", "Panel", panel_box(accent))
	# Buttons: dark stickers with a coloured rim, a fat bottom edge for depth,
	# and the accent filling in when pressed.
	th.set_stylebox("normal", "Button", _button_box(ink.lightened(0.08), accent, 2, 5))
	th.set_stylebox("hover", "Button", _button_box(ink.lightened(0.18), accent.lightened(0.25), 2, 5))
	th.set_stylebox("pressed", "Button", _button_box(accent, accent.darkened(0.35), 2, 2))
	th.set_stylebox("disabled", "Button", _button_box(ink, Color(accent, 0.3), 1, 3))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", ink)
	th.set_color("font_outline_color", "Button", Color(0.0, 0.0, 0.0, 0.85))
	th.set_constant("outline_size", "Button", 3)
	for kind: String in ["CheckBox", "CheckButton", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", kind, _button_box(Color(ink.lightened(0.05), 0.6), Color(accent, 0.35), 1, 2))
		th.set_stylebox("hover", kind, _button_box(ink.lightened(0.15), accent, 1, 2))
		th.set_stylebox("pressed", kind, _button_box(ink.lightened(0.1), accent, 1, 2))
		th.set_stylebox("focus", kind, StyleBoxEmpty.new())
		th.set_color("font_color", kind, Color.WHITE)
		th.set_color("font_pressed_color", kind, Color.WHITE)
		th.set_color("font_hover_color", kind, accent.lightened(0.3))
	th.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.7))
	th.set_constant("outline_size", "Label", 2)
	var sep := StyleBoxLine.new()
	sep.color = Color(accent, 0.45)
	sep.thickness = 2
	th.set_stylebox("separator", "HSeparator", sep)
	_theme = th
	return th


## The sticker's backing: near-black ink from the profile's panel edge.
static func ink_color() -> Color:
	var edge := MobileHudProfiles.color("panel_edge")
	return Color(edge.r, edge.g, edge.b, 1.0).darkened(0.2).lerp(Color("120f18"), 0.5)


## The profile's loud colour — the comic look's orange, pop art's pink.
static func accent_color() -> Color:
	var c := MobileHudProfiles.color("panel")
	return Color(c.r, c.g, c.b, 1.0) if c.a > 0.2 else MobileHudProfiles.color("dial_ring")


## A sticker panel: thick uneven rim in [param rim], hard offset shadow, a lean.
static func panel_box(rim: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ink_color(), 0.96)
	sb.border_color = rim
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 5
	sb.border_width_bottom = 7
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 5
	sb.corner_radius_bottom_left = 18
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.75)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(7.0, 8.0)
	sb.skew = Vector2(LEAN, 0.0)
	sb.set_content_margin_all(16)
	sb.content_margin_top = PANEL_MARGIN_TOP
	sb.anti_aliasing = true
	return sb


static func _button_box(bg: Color, rim: Color, width: int, bottom: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = rim
	sb.set_border_width_all(width)
	sb.border_width_bottom = bottom
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 9
	sb.corner_radius_bottom_right = 3
	sb.corner_radius_bottom_left = 9
	sb.skew = Vector2(BUTTON_LEAN, 0.0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


## Dress [param root] (an already-built popup) in the look. [param accent]
## overrides the rim colour; by default it is the profile's.
static func skin(root: Control, accent := Color.TRANSPARENT) -> void:
	if root == null:
		return
	var rim := accent if accent.a > 0.0 else accent_color()
	root.theme = theme()
	if root is PanelContainer or root is Panel:
		root.add_theme_stylebox_override("panel", panel_box(rim))
	_restyle(root)
	if root.get_node_or_null("SprayDecor") == null:
		var decor := SprayDecor.new()
		decor.name = "SprayDecor"
		decor.color = rim
		decor.seed_val = hash(String(root.name))
		root.add_child(decor)
		root.move_child(decor, 0)


## Headings get the title font and an outline; every label and button loses
## its emoji. Recurses through the popup.
static func _restyle(node: Node) -> void:
	if node is Label:
		var l := node as Label
		l.text = strip_emoji(l.text)
		if l.has_theme_font_size_override("font_size") and l.get_theme_font_size("font_size") >= HEADING_SIZE:
			style_heading(l)
	elif node is Button:
		var b := node as Button
		b.text = strip_emoji(b.text)
	for child in node.get_children():
		_restyle(child)


## A heading in the profile's title font, outlined like the HUD's titles.
static func style_heading(l: Label) -> void:
	var f := MobileHudProfiles.font("title")
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_outline_color", MobileHudProfiles.color("title_outline"))
	l.add_theme_constant_override("outline_size", maxi(int(MobileHudProfiles.profile().get("outline", 0)), 4))
	l.uppercase = true


## [param text] without emoji (pictographs, dingbats, flags, the invisible
## joiners and variation selectors). The close ✕, ticks and × are kept.
static func strip_emoji(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		var keep := true
		if c >= 0x1F000 and c <= 0x1FAFF:
			keep = false
		elif c >= 0x2600 and c <= 0x27BF:
			keep = c in [0x2713, 0x2714, 0x2715, 0x2716, 0x2717]
		elif c >= 0x2B00 and c <= 0x2BFF:
			keep = false
		elif c == 0xFE0F or c == 0x200D or c == 0x21BA or c == 0x21BB:
			keep = false
		if keep:
			out += String.chr(c)
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


## Paint drips and flecks hanging off a popup's top edge, in its rim colour.
## Drawn behind the popup's content; seeded, so each popup keeps its drips.
class SprayDecor:
	extends Control

	var color := Color.WHITE
	var seed_val := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		show_behind_parent = false
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var w := size.x
		if w < 40.0:
			return
		# This sits inside the panel's content margin; the rim is above it.
		var rim_y := -float(PANEL_MARGIN_TOP) + 3.0
		# Drips from the top rim: a stroke with a round blob at the end.
		for i in 3 + rng.randi() % 3:
			var x := rng.randf_range(w * 0.08, w * 0.92)
			var drip_len := rng.randf_range(8.0, 26.0)
			var thick := rng.randf_range(2.0, 4.0)
			var top := Vector2(x, rim_y)
			var bottom := Vector2(x + rng.randf_range(-1.0, 1.0), rim_y + drip_len)
			draw_line(top, bottom, Color(color, 0.85), thick, true)
			draw_circle(bottom, thick * 0.8, Color(color, 0.85))
		# Overspray round the top corners.
		for i in 14:
			var corner := Vector2(-12.0, rim_y) if i % 2 == 0 else Vector2(w + 12.0, rim_y)
			var p := corner + Vector2(rng.randf_range(-6.0, 22.0) * (1.0 if i % 2 == 0 else -1.0), rng.randf_range(-6.0, 18.0))
			draw_circle(p, rng.randf_range(0.8, 2.2), Color(color, rng.randf_range(0.3, 0.7)))
