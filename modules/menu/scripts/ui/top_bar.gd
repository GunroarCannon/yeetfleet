## TopBar: the strip along the top of every screen but home — a back slab
## and the screen's name on the left, the pilot's wallet on the right.
class_name TopBar
extends Control

signal back_pressed

var title := ""
var _back: SlabButton
var _title: Label
var _wallet: WalletChip


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = SlabButton.new()
	_back.text = "BACK"
	_back.fill = GraffitiStyle.VIOLET
	_back.skew = 10.0
	_back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back)
	_title = Label.new()
	_title.text = title
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", GraffitiStyle.title_font())
	_title.add_theme_color_override("font_color", GraffitiStyle.LIME)
	_title.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	_title.add_theme_color_override("font_shadow_color", GraffitiStyle.SHADOW)
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	add_child(_title)
	_wallet = WalletChip.new()
	add_child(_wallet)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
	var h := clampf(size.y, 44.0, 90.0 * u)
	var small := vp.x < vp.y
	# Minimum first: a size below the minimum is clamped up to it.
	_back.custom_minimum_size = Vector2(h * 1.3, h * 0.82)
	_back.size = _back.custom_minimum_size
	_back.position = Vector2(16, (size.y - _back.size.y) * 0.5)
	var ts := int(h * (0.62 if not small else 0.5))
	_title.add_theme_font_size_override("font_size", ts)
	_title.add_theme_constant_override("outline_size", maxi(4, int(ts * 0.18)))
	_title.position = Vector2(_back.position.x + _back.size.x + 22, (size.y - ts * 1.25) * 0.5)
	var ww := clampf(size.x * 0.46, 220.0, 440.0 * u)
	_wallet.size = Vector2(ww, h * 0.72)
	_wallet.position = Vector2(size.x - ww - 16, (size.y - _wallet.size.y) * 0.5)
	# A narrow phone: the title gives way to the wallet.
	# Measured in its own (wide, graffiti) font, not guessed from its length.
	var tw := GraffitiStyle.title_font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	_title.visible = _title.position.x + tw + 8.0 < _wallet.position.x


func set_title(t: String) -> void:
	title = t
	if _title != null:
		_title.text = t
		_layout()


func grab_back_focus() -> void:
	_back.grab_focus()
