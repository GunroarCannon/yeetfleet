## Top-left icon toolbar for the flight HUD: one icon button per category, each
## opening a draggable popup panel (title bar drags it, ✕ closes it).
##
## This replaces the single ☰ hamburger. Categories are surfaced as icons across
## the top-left corner instead of buried behind one button, and each popup floats
## like a small window — move it where you need it, close it with ✕ or by tapping
## anywhere outside it, and only one is open at a time so the screen never piles
## up panels.
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
var _backdrop: BackdropShade = null
var _open_id := -1


func _ready() -> void:
	add_theme_constant_override("separation", BuilderTheme.GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Attach the HUD the popups are created under (they float over the instruments).
func attach(hud: Control) -> void:
	_hud = hud
	_backdrop = BackdropShade.new()
	_backdrop.name = "PopupBackdrop"
	_backdrop.tapped.connect(func() -> void: close_all())
	_backdrop.visible = false
	hud.add_child(_backdrop)


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
	# A tap anywhere outside the popup dismisses it: a full-screen shade sits under
	# the popup but above everything else, and its tap closes the menu.
	if _backdrop != null:
		_backdrop.visible = true
		_backdrop.move_to_front()
	var top_bar := _hud.get_node_or_null("TopBar") as Control
	if top_bar != null:
		top_bar.move_to_front()
	_open_id = id
	# Fill the content, show a first pass, then re-measure and re-place on the
	# next frame — row minimums are not reliable until a layout pass has run, and
	# measuring too early is what made tall menus open as a sliver.
	category_pressed.emit(id)
	_place_open(id)
	_measure_open(id)


## Position the open popup under its toolbar button and show it. Called twice:
## once provisionally (before sizes are final) and again after the measure pass.
func _place_open(id: int) -> void:
	if _hud == null or not _popups.has(id) or not _buttons.has(id):
		return
	var popup := _popups[id] as DraggablePopup
	var rect := (_buttons[id] as Button).get_global_rect()
	popup.position = Vector2(rect.position.x, rect.end.y + BuilderTheme.GAP).clamp(
		Vector2.ZERO, _hud.size - popup.size
	)
	popup.visible = true
	popup.move_to_front()


## Re-fit the open popup after a layout frame so its content minimums are real,
## then place it. If it was closed while waiting, do nothing.
func _measure_open(id: int) -> void:
	await get_tree().process_frame
	if _open_id != id or not _popups.has(id):
		return
	var popup := _popups[id] as DraggablePopup
	if popup == null or not is_instance_valid(popup):
		return
	popup.auto_fit(_hud.size)
	_place_open(id)


func _on_popup_closed(id: int) -> void:
	if _open_id == id:
		_open_id = -1
	if _backdrop != null:
		_backdrop.visible = false


## The popup for a category, created on first request. The HUD fills its content.
func popup_for(id: int) -> DraggablePopup:
	if not _popups.has(id):
		return null
	return _popups[id] as DraggablePopup


## Clamp the open popup back inside the screen. Called by the HUD after it
## rebuilds content that is taller/wider than before; the refit happens on the
## next frame so the new rows' minimums are known.
func recentre_open() -> void:
	if _open_id >= 0 and _popups.has(_open_id):
		_measure_open(_open_id)


func close_all() -> void:
	for popup in _popups.values():
		(popup as DraggablePopup).visible = false
	if _backdrop != null:
		_backdrop.visible = false
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


# --- BackdropShade ------------------------------------------------------------

## A transparent full-screen control behind the open popup. It swallows any tap
## that lands outside the popup and reports it as a dismiss, so the menu goes
## away when you touch anywhere else.
class BackdropShade:
	extends Control

	signal tapped


	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_ARROW


	func _gui_input(event: InputEvent) -> void:
		var dismiss := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			dismiss = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			dismiss = st.pressed
		if dismiss:
			tapped.emit()
			accept_event()


# --- DraggablePopup ----------------------------------------------------------

## A floating panel: title bar (draggable, ✕ to close) above a content VBox the
## owner fills. Lives as a HUD child so it can be positioned anywhere on screen.
## Content taller than the screen scrolls inside the panel, so a long menu can
## never get stuck past its own bottom edge.
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
	var _scroll: ScrollContainer
	const HEADER_H := 26.0
	const PAD := 10.0


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override(
			"panel", BuilderTheme.flat(BuilderTheme.panel_alt_bg(), BuilderTheme.border_strong(), 6, 1)
		)

		# A plain body Control fills the panel; the header is pinned to its top and
		# the scroll area takes the rest. Using a plain Control (not a VBox) means
		# the panel's minimum size is whatever we set it to — the content cannot
		# force the panel taller than the screen.
		var body := Control.new()
		body.name = "Body"
		add_child(body)

		var handle := DragHandle.new()
		handle.name = "Handle"
		handle.drag_by.connect(func(by: Vector2) -> void: _on_drag(by))
		body.add_child(handle)

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

		_scroll = ScrollContainer.new()
		_scroll.name = "Scroll"
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(_scroll)

		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", BuilderTheme.GAP)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(content)

		# Manual anchors: body fills the panel, the handle is a fixed strip at the
		# top, and the scroll area is everything below it.
		body.set_anchors_preset(Control.PRESET_FULL_RECT)
		handle.set_anchors_preset(Control.PRESET_TOP_WIDE)
		handle.offset_bottom = HEADER_H
		_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		_scroll.offset_top = HEADER_H + BuilderTheme.GAP


	func _on_drag(by: Vector2) -> void:
		var parent := get_parent() as Control
		if parent == null:
			return
		position += by
		# Clamp per axis. A panel taller than the screen must be allowed to slide
		# up past zero, or it pins at the top and rows below the fold become
		# unreachable — the "stuck" bug. With this clamp it can move so its bottom
		# edge is reachable and slide back to show the top again.
		position.x = clampf(position.x, minf(0.0, parent.size.x - size.x), maxf(0.0, parent.size.x - size.x))
		position.y = clampf(position.y, minf(0.0, parent.size.y - size.y), maxf(0.0, parent.size.y - size.y))


	## Size the panel to its content, capped so it never exceeds the screen:
	## short menus hug their rows, tall ones scroll internally instead of
	## overflowing past the bottom edge.
	func auto_fit(screen_size: Vector2) -> void:
		var inner := content.get_combined_minimum_size()
		var w := clampf(inner.x + PAD * 2.0, 140.0, maxf(screen_size.x - PAD, 140.0))
		var h := clampf(HEADER_H + PAD + inner.y, HEADER_H + PAD, screen_size.y - PAD)
		custom_minimum_size = Vector2(w, h)
		reset_size()


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


	## A dim section header row. Menus use it to group related rows.
	func add_section(title: String) -> void:
		var lbl := Label.new()
		lbl.text = title
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", BuilderTheme.accent())
		content.add_child(lbl)


	## A wrapped line of explanation under a control, in plain language.
	##
	## Separate from [method add_label_row] because that one does not wrap: it is
	## a caption, one short line, and a sentence in it runs off the side of the
	## popup. A settings list whose names nobody can decode is worse than no
	## settings list, so the explanation has to fit.
	func add_help_row(text: String) -> void:
		var lbl := Label.new()
		lbl.text = text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
		content.add_child(lbl)


	## A name + value readout row, for live state (AI count, orbit status, the
	## current feel profile) that the menu refreshes on every open. The value is
	## right-aligned in the accent colour so it reads as a number, not a button.
	func add_value_row(label: String, value: String) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", BuilderTheme.GAP)
		var name_lbl := Label.new()
		name_lbl.text = label
		name_lbl.custom_minimum_size = Vector2(110, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = value
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
		row.add_child(val_lbl)
		content.add_child(row)


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
