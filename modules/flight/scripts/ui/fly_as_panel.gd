## FlyAsPanel: the 🛩 Fly as chip's panel — pick a hull size, a weapon and a
## firing style, and fly a ship like that to feel how it handles and fights.
## See [method FlightRoot.fly_as]; "Back to my ship" hands it back and frees it.
class_name FlyAsPanel
extends PanelContainer

var accent := Color("7df9ff")
var _root: FlightRoot = null
var _size := 1.0
var _weapon := -1
var _style := ""
var _size_buttons: Array[Button] = []


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	custom_minimum_size = Vector2(400.0, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.95)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "🛩 FLY AS ANOTHER SHIP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	vbox.add_child(_caption("Size"))
	var sizes := HFlowContainer.new()
	vbox.add_child(sizes)
	for label: String in FlightRoot.FLY_AS_SIZES.keys():
		var b := Button.new()
		b.text = label
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = is_equal_approx(float(FlightRoot.FLY_AS_SIZES[label]), _size)
		b.pressed.connect(_pick_size.bind(float(FlightRoot.FLY_AS_SIZES[label]), b))
		sizes.add_child(b)
		_size_buttons.append(b)

	vbox.add_child(_caption("Weapon"))
	var weapons := OptionButton.new()
	weapons.add_item("Auto (fits the size)", 0)
	for i in SystemsSim.WEAPONS.size():
		var w: Dictionary = SystemsSim.WEAPONS[i]
		weapons.add_item("%s  [%s]" % [w["name"], w.get("size_class", "fighter")], i + 1)
	weapons.item_selected.connect(func(idx: int) -> void: _weapon = idx - 1)
	vbox.add_child(weapons)

	vbox.add_child(_caption("Firing style"))
	var styles := OptionButton.new()
	styles.add_item("Plain (the weapon's own)", 0)
	var names := AiFirePatterns.style_names()
	for i in names.size():
		styles.add_item(names[i].capitalize(), i + 1)
	styles.item_selected.connect(func(idx: int) -> void: _style = "" if idx == 0 else names[idx - 1])
	vbox.add_child(styles)

	var row := HBoxContainer.new()
	vbox.add_child(row)
	var go := Button.new()
	go.text = "Fly it"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func() -> void:
		if _root != null:
			_root.fly_as(_size, _weapon, _style)
			visible = false)
	row.add_child(go)
	var back := Button.new()
	back.text = "Back to my ship"
	back.pressed.connect(func() -> void:
		if _root != null:
			_root.leave_control())
	row.add_child(back)


func _pick_size(value: float, pressed_btn: Button) -> void:
	_size = value
	for b in _size_buttons:
		b.set_pressed_no_signal(b == pressed_btn)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("6ec6ff"))
	return l
