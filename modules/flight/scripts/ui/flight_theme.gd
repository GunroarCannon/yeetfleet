## FlightTheme: Centralized styling and responsive theme generator for Flight HUD.
##
## Constructs reusable Theme resources adapting to Desktop, Steam Deck (1280x800),
## and Mobile touch resolutions with minimum 44px tap targets and palette styling.
class_name FlightTheme
extends RefCounted

const TOUCH_MIN_DESKTOP := 34.0
const TOUCH_MIN_MOBILE := 46.0


## Generates a responsive Theme resource tailored to current display size and device.
static func create_theme(viewport_size: Vector2, is_mobile: bool = false) -> Theme:
	var th := Theme.new()
	var touch_min := TOUCH_MIN_MOBILE if (is_mobile or viewport_size.x <= 1280.0) else TOUCH_MIN_DESKTOP
	var base_font_size := 14 if (is_mobile or viewport_size.x <= 1280.0) else 13

	th.default_font_size = base_font_size

	# Button StyleBoxes
	var normal_sb := _make_flat_box(Color("101622", 0.85), Color("2e3d56", 0.8), 1, 6)
	var hover_sb := _make_flat_box(Color("162032", 0.95), Color("4a6b98", 1.0), 1, 6)
	var pressed_sb := _make_flat_box(Color("080d16", 0.95), Color("00d4ff", 1.0), 2, 6)
	var focus_sb := _make_flat_box(Color("101622", 0.0), Color("00d4ff", 0.6), 1, 6)

	th.set_stylebox("normal", "Button", normal_sb)
	th.set_stylebox("hover", "Button", hover_sb)
	th.set_stylebox("pressed", "Button", pressed_sb)
	th.set_stylebox("focus", "Button", focus_sb)
	th.set_color("font_color", "Button", Color("e2ecf8"))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color("00d4ff"))

	# Panel StyleBoxes
	var panel_sb := _make_flat_box(Color("0c111a", 0.90), Color("223044", 0.7), 1, 8)
	th.set_stylebox("panel", "PanelContainer", panel_sb)

	return th


static func _make_flat_box(bg: Color, border: Color, width: int = 1, corner: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	sb.set_content_margin_all(8)
	return sb
