## Top-left icon toolbar for the flight HUD: one icon button per category, each
## opening a draggable popup panel (title bar drags it, ✕ closes it).
##
## This replaces the single ☰ hamburger. Categories are surfaced as icons across
## the top-left corner instead of buried behind one button, and each popup floats
## like a small window — move it where you need it, close it with ✕, and only one
## is open at a time so the screen never piles up panels.
##
## The toolbar only opens and moves popups; [FlightHud] owns what goes inside each
## one via [signal category_pressed]: the HUD reads the popup back with
## [method popup_for], clears and fills its content, then calls
## [method recentre_open].
class_name FlightMenu
extends HBoxContainer

## A category button was pressed; the HUD should fill that popup's content.
signal category_pressed(id: int)

var _hud: Control = null
var _buttons: Dictionary = {}  # id -> Button
var _popups: Dictionary = {}  # id -> DraggablePopup
var _open_id := -1


func _ready() -> void:
	add_theme_constant_override("separation", BuilderTheme.GAP)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Attach the HUD the popups are created under (they float over the instruments).
func attach(hud: Control) -> void:
	_hud = hud


## Add a category button. [param icon_path] is under res://assets/icons.
func add_category(id: int, icon_path: String, tooltip: String) -> void:
	var b := _icon_button(id, icon_path, tooltip)
	b.pressed.connect(func() -> void: _on_button(id))
	add_child(b)
	_buttons[id] = b


## A plain toolbar button that performs an action directly (no popup) — the
## hangar exit, say.
func add_action_icon(id: int, icon_path: String, tooltip: String, action: Callable) -> void:
	var b := _icon_button(id, icon_path, tooltip)
	b.pressed.connect(action)
	add_child(b)


func _icon_button(id: int, icon_path: String, tooltip: String) -> Button:
	var b := Button.new()
	b.icon = load("res://assets/icons/" + icon_path) as Texture2D
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN, BuilderTheme.TOUCH_MIN)
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 22)
	b.add_theme_constant_override("icon_max_height", 22)
	return b


func _on_button(id: int) -> void:
	if _open_id == id:
		close_all()
		return
	close_all()
	_open(id)


func _open(id: int) -> void:
	if _hud == null:
		return
	var popup := _popups.get(id) as DraggablePopup
	if popup == null:
		popup = DraggablePopup.new()
		popup.name = "Popup_%d" % id
		_hud.add_child(popup)
		_popups[id] = popup
		# ✕ on the popup means "not open" as far as the toolbar is concerned, so
		# pressing the same icon again reopens it instead of appearing dead.
		popup.closed.connect(func() -> void: _on_popup_closed(id))
	# Tell the HUD to fill the content before sizing/placing it.
	category_pressed.emit(id)
	popup.reset_size()
	var rect := (_buttons[id] as Button).get_global_rect()
	var want := Vector2(rect.position.x, rect.end.y + BuilderTheme.GAP)
	popup.position = want.clamp(Vector2.ZERO, _hud.size - popup.size)
	popup.visible = true
	popup.move_to_front()
	_open_id = id


func _on_popup_closed(id: int) -> void:
	if _open_id == id:
		_open_id = -1


## The popup for a category, created on first request. The HUD fills its content.
func popup_for(id: int) -> DraggablePopup:
	if not _popups.has(id):
		return null
	return _popups[id] as DraggablePopup


## Clamp the open popup back inside the screen (called after the HUD rebuilds
## content that is taller/wider than before).
func recentre_open() -> void:
	if _open_id >= 0 and _popups.has(_open_id):
		var popup := _popups[_open_id] as DraggablePopup
		if popup != null:
			popup.position = popup.position.clamp(Vector2.ZERO, _hud.size - popup.size)


func close_all() -> void:
	for popup in _popups.values():
		(popup as DraggablePopup).visible = false
	_open_id = -1


func is_open() -> bool:
	return _open_id >= 0


## Closes the open popup, if any. Returns true if one was closed (so the caller
## can decide, e.g. Escape closes a menu instead of leaving the scene).
func close_open() -> bool:
	if _open_id < 0:
		return false
	close_all()
	return true


# --- DraggablePopup ----------------------------------------------------------

## A floating panel: title bar (draggable, ✕ to close) above a content VBox the
## owner fills. Lives as a HUD child so it can be positioned anywhere on screen.
class DraggablePopup:
	extends PanelContainer

	## Emitted when the ✕ is pressed.
	signal closed

	var content: VBoxContainer
	var title: String = "":
		set(value):
			title = value
			if _title_label != null:
				_title_label.text = value

	var _title_label: Label


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override(
			"panel", BuilderTheme.flat(BuilderTheme.panel_alt_bg(), BuilderTheme.border_strong(), 6, 1)
		)

		# Column: drag handle / header, then the content rows.
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", BuilderTheme.GAP)
		add_child(column)

		var handle := DragHandle.new()
		handle.custom_minimum_size = Vector2(0, 26)
		handle.drag_by.connect(func(by: Vector2) -> void: _on_drag(by))
		column.add_child(handle)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", BuilderTheme.GAP)
		handle.add_child(header)

		_title_label = Label.new()
		_title_label.add_theme_font_size_override("font_size", 12)
		_title_label.add_theme_color_override("font_color", BuilderTheme.accent())
		_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title_label.text = title
		header.add_child(_title_label)

		var close := Button.new()
		close.text = "✕"
		close.flat = true
		close.tooltip_text = "Close (drag the bar to move)"
		close.custom_minimum_size = Vector2(26, 26)
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(func() -> void: close_popup())
		header.add_child(close)

		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", BuilderTheme.GAP)
		column.add_child(content)


	func _on_drag(by: Vector2) -> void:
		var parent := get_parent() as Control
		if parent == null:
			return
		position = (position + by).clamp(Vector2.ZERO, parent.size - size)


	func close_popup() -> void:
		visible = false
		closed.emit()


	## Popup content-row helpers. All rows are built by the HUD into [member content].

	func clear() -> void:
		for child in content.get_children():
			child.queue_free()


	func add_action_row(label: String, action: Callable) -> Button:
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(action)
		content.add_child(b)
		return b


	## A labelled checkbox row. [param on_toggle] receives the new checked state.
	func add_check_row(label: String, checked: bool, on_toggle: Callable) -> CheckButton:
		var cb := CheckButton.new()
		cb.text = label
		cb.button_pressed = checked
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(on_toggle)
		content.add_child(cb)
		return cb


	## A one-of row. Pressing fires [param action] with the row's value.
	func add_radio_row(label: String, selected: bool, value: int, action: Callable) -> Button:
		var b := Button.new()
		b.text = ("● " if selected else "○ ") + label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: action.call(value))
		content.add_child(b)
		return b


	func add_separator() -> void:
		var sep := HSeparator.new()
		sep.modulate.a = 0.4
		content.add_child(sep)


	## A plain informational row (no interaction).
	func add_label_row(text: String) -> void:
		var lbl := Label.new()
		lbl.text = text
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
		content.add_child(lbl)


	## A labelled dropdown row; [param on_selected] receives the chosen index.
	func add_option_row(
		label: String, choices: Array, initial: int, on_selected: Callable
	) -> OptionButton:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", BuilderTheme.GAP)
		var name_lbl := Label.new()
		name_lbl.text = label
		name_lbl.custom_minimum_size = Vector2(110, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
		row.add_child(name_lbl)
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(120, BuilderTheme.TOUCH_MIN - 12)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for c in choices:
			opt.add_item(String(c))
		opt.select(initial)
		opt.item_selected.connect(on_selected)
		row.add_child(opt)
		content.add_child(row)
		return opt


	## A slider row; the [param setter] receives the live value as it changes.
	func add_slider_row(
		label: String, min_value: float, max_value: float, step: float, initial: float,
		setter: Callable, format := "%.1f"
	) -> HSlider:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", BuilderTheme.GAP)
		var name_lbl := Label.new()
		name_lbl.text = label
		name_lbl.custom_minimum_size = Vector2(110, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
		row.add_child(name_lbl)
		var slider := HSlider.new()
		slider.min_value = min_value
		slider.max_value = max_value
		slider.step = step
		slider.value = initial
		slider.custom_minimum_size = Vector2(100, 24)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var val_lbl := Label.new()
		val_lbl.text = format % initial
		val_lbl.custom_minimum_size = Vector2(44, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
		row.add_child(val_lbl)
		slider.value_changed.connect(func(v: float) -> void: val_lbl.text = format % v)
		slider.value_changed.connect(func(v: float) -> void: setter.call(v))
		content.add_child(row)
		return slider


## The title bar of a [DraggablePopup]: reports how far the pointer has moved
## while held, so the owner can move the whole panel.
class DragHandle:
	extends Control

	signal drag_by(offset: Vector2)

	var _dragging := false
	var _last := Vector2.ZERO
	var _pointer := -1


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			_dragging = mb.pressed
			_last = mb.position
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			var mm := event as InputEventMouseMotion
			drag_by.emit(mm.position - _last)
			_last = mm.position
			accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_dragging = true
				_pointer = st.index
				_last = st.position
			elif st.index == _pointer:
				_dragging = false
				_pointer = -1
			accept_event()
		elif event is InputEventScreenDrag:
			var sd := event as InputEventScreenDrag
			if _dragging and sd.index == _pointer:
				drag_by.emit(sd.position - _last)
				_last = sd.position
				accept_event()
