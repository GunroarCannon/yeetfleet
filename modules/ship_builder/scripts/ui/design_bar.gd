## The top bar: which ship this is, and the file-level things you do to it.
##
## Everything that used to sit out here as its own button -- hull swap, presets,
## autofill, strip, save, load, clipboard, contrast, help -- now lives inside one
## menu. A builder is used one action at a time, and a row of a dozen unlabelled
## affordances is slower to read than a menu you open twice a session: it costs a
## beginner the whole screen to scan and costs a phone the whole width to draw.
## What stays visible is only what is used *while* building: the name, and undo.
##
## The view tools moved out of here entirely and onto the viewport itself
## ([ViewBar]), next to the thing they act on and within thumb reach.
class_name DesignBar
extends HBoxContainer

const MENU_NEW := 1
const MENU_AUTOFILL := 2
const MENU_STRIP := 3
const MENU_SAVE := 4
const MENU_COPY := 5
const MENU_PASTE := 6
const MENU_CONTRAST := 7
const MENU_HELP := 8
const MENU_WALKTHROUGH := 9
const MENU_FLIGHT := 10
const MENU_LOAD_BASE := 100

var _root: BuilderRoot
var _viewport: BuilderViewport

var _menu_button: MenuButton
var _hull_popup: PopupMenu
var _preset_popup: PopupMenu
var _saved_popup: PopupMenu
var _name_field: LineEdit
var _undo_button: Button
var _redo_button: Button
var _status: Label
var _updating := false


func _ready() -> void:
	_root = owner as BuilderRoot
	_viewport = %ViewportFrame as BuilderViewport
	_status = %StatusLabel as Label
	add_theme_constant_override("separation", BuilderTheme.GAP)
	_build_ui()
	_wire_panel_toggles()
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: refresh())
	_root.history_changed.connect(_refresh_history)
	_viewport.status_changed.connect(func(text: String) -> void: _status.text = text)
	refresh()


func _build_ui() -> void:
	_menu_button = MenuButton.new()
	_menu_button.text = "☰"
	_menu_button.flat = false
	_menu_button.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN, BuilderTheme.TOUCH_MIN - 10)
	_menu_button.tooltip_text = "Ship menu — hull, presets, saving, help"
	add_child(_menu_button)

	var popup := _menu_button.get_popup()
	# Submenus are built once and refilled on open, so the popup owns no stale
	# copy of the saved-design list.
	_hull_popup = PopupMenu.new()
	_hull_popup.name = "HullMenu"
	_hull_popup.id_pressed.connect(_on_hull_chosen)
	popup.add_child(_hull_popup)
	_preset_popup = PopupMenu.new()
	_preset_popup.name = "PresetMenu"
	_preset_popup.id_pressed.connect(_on_preset_chosen)
	popup.add_child(_preset_popup)
	_saved_popup = PopupMenu.new()
	_saved_popup.name = "SavedMenu"
	_saved_popup.id_pressed.connect(_on_saved_chosen)
	popup.add_child(_saved_popup)
	_fill_hull_menu()
	_fill_preset_menu()
	popup.id_pressed.connect(_on_menu)
	popup.about_to_popup.connect(_rebuild_menu)
	_rebuild_menu()

	_name_field = LineEdit.new()
	_name_field.custom_minimum_size = Vector2(140, BuilderTheme.TOUCH_MIN - 10)
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.placeholder_text = "Ship name"
	_name_field.tooltip_text = "Name this design. Used for the save file name."
	_name_field.text_submitted.connect(func(t: String) -> void:
		_root.rename_design(t)
		_name_field.release_focus()
	)
	_name_field.focus_exited.connect(func() -> void: _root.rename_design(_name_field.text))
	add_child(_name_field)

	_undo_button = _add_icon_button("↶", "Undo (Ctrl+Z)", _root.undo)
	_redo_button = _add_icon_button("↷", "Redo (Ctrl+Y)", _root.redo)


func _add_icon_button(text: String, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN - 8, BuilderTheme.TOUCH_MIN - 10)
	button.pressed.connect(action)
	add_child(button)
	return button


## In narrow layout the side panels become drawers; these two buttons are the only
## way to reach them, so they live outside the bar where nothing can reflow them off
## the screen.
func _wire_panel_toggles() -> void:
	var toggles: Control = %PanelToggles
	var left := toggles.get_node_or_null("LeftToggle") as Button
	var right := toggles.get_node_or_null("RightToggle") as Button
	if left != null:
		left.pressed.connect(func() -> void: _root.toggle_panel("left"))
	if right != null:
		right.pressed.connect(func() -> void: _root.toggle_panel("right"))


# --- Menu ------------------------------------------------------------------

func _fill_hull_menu() -> void:
	_hull_popup.clear()
	var index := 0
	for chassis in _root.library.chassis_list():
		_hull_popup.add_item("%s (%s)" % [chassis.display_name, chassis.size_class], index)
		_hull_popup.set_item_metadata(index, chassis.id)
		index += 1


func _fill_preset_menu() -> void:
	_preset_popup.clear()
	var index := 0
	for preset in _root.library.presets:
		_preset_popup.add_item(String(preset.get("name", preset.get("id", "?"))), index)
		_preset_popup.set_item_metadata(index, String(preset.get("id", "")))
		index += 1


func _rebuild_menu() -> void:
	var popup := _menu_button.get_popup()
	popup.clear()
	popup.add_submenu_node_item("Example ships", _preset_popup)
	popup.add_submenu_node_item("Change hull", _hull_popup)
	popup.add_separator()
	popup.add_item("New design", MENU_NEW)
	popup.add_item("Fit required mounts", MENU_AUTOFILL)
	popup.add_item("Strip to bare hull", MENU_STRIP)
	popup.add_separator()
	popup.add_item("Save copy", MENU_SAVE)
	var saved := _root.saved_designs()
	_saved_popup.clear()
	for i in saved.size():
		_saved_popup.add_item(saved[i].get_file().get_basename(), i)
		_saved_popup.set_item_metadata(i, saved[i])
	if not saved.is_empty():
		popup.add_submenu_node_item("Open saved", _saved_popup)
	popup.add_item("Copy JSON to clipboard", MENU_COPY)
	popup.add_item("Paste JSON from clipboard", MENU_PASTE)
	popup.add_separator()
	popup.add_item("Test flight", MENU_FLIGHT)
	popup.add_separator()
	popup.add_check_item("High contrast", MENU_CONTRAST)
	popup.set_item_checked(popup.get_item_index(MENU_CONTRAST), BuilderTheme.high_contrast)
	popup.add_item("Controls and shortcuts (?)", MENU_HELP)
	popup.add_item("Show the walkthrough again", MENU_WALKTHROUGH)


func _on_hull_chosen(index: int) -> void:
	_root.swap_chassis(String(_hull_popup.get_item_metadata(index)))


func _on_preset_chosen(index: int) -> void:
	_root.load_preset(String(_preset_popup.get_item_metadata(index)))


func _on_saved_chosen(index: int) -> void:
	_root.load_from_file(String(_saved_popup.get_item_metadata(index)))


func _on_menu(id: int) -> void:
	match id:
		MENU_NEW:
			_root.new_design()
		MENU_AUTOFILL:
			_root.autofill()
		MENU_STRIP:
			_root.strip_design()
		MENU_SAVE:
			_root.save_to_file()
		MENU_COPY:
			DisplayServer.clipboard_set(_root.design_json())
			_root.notice.emit("Design JSON copied to clipboard", "info")
		MENU_PASTE:
			if not _root.load_json(DisplayServer.clipboard_get()):
				_root.notice.emit("Clipboard does not hold a valid design", "error")
		MENU_CONTRAST:
			_root.toggle_high_contrast()
		MENU_HELP:
			(%HelpOverlay as HelpOverlay).toggle()
		MENU_WALKTHROUGH:
			_root.coach().start(false)
		MENU_FLIGHT:
			_root.launch_test_flight()


# --- Sync ------------------------------------------------------------------

func refresh() -> void:
	_updating = true
	if not _name_field.has_focus():
		_name_field.text = _root.design.design_name
	_updating = false
	_refresh_history()


func _refresh_history() -> void:
	_undo_button.disabled = not _root.history.can_undo()
	_redo_button.disabled = not _root.history.can_redo()
	_undo_button.tooltip_text = "Undo %s (Ctrl+Z)" % _root.history.undo_label() \
		if _root.history.can_undo() else "Nothing to undo"
	_redo_button.tooltip_text = "Redo %s (Ctrl+Y)" % _root.history.redo_label() \
		if _root.history.can_redo() else "Nothing to redo"
