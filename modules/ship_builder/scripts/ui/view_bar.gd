## The tool bar that floats over the 3D view: what a drag does, and how the ship
## is displayed.
##
## It sits at the bottom of the viewport for two reasons. It is where a thumb
## already is on a phone, and it puts the controls against the thing they change
## instead of at the far end of the window.
##
## Only two kinds of control are exposed. The drag mode is a segmented switch,
## because it is modal -- the player has to be able to see which mode they are in
## without opening anything. Everything else is display state that is set and
## forgotten, so it goes in one menu.
class_name ViewBar
extends HBoxContainer

const MENU_SOCKETS := 1
const MENU_LABELS := 2
const MENU_FRAME := 3
const VIEW_BASE := 10


var _root: BuilderRoot
var _viewport: BuilderViewport
var _mode_buttons: Array[Button] = []
var _view_menu: MenuButton


func _ready() -> void:
	_root = owner as BuilderRoot
	_viewport = %ViewportFrame as BuilderViewport
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", BuilderTheme.GAP)
	_build_ui()
	_viewport.drag_mode_changed.connect(_on_drag_mode_changed)
	_on_drag_mode_changed(_viewport.drag_mode)


func _build_ui() -> void:
	# Mode buttons rather than modifier keys: a hidden ctrl-drag cannot be found by
	# a new player and cannot be performed at all on a touchscreen.
	var segmented := HBoxContainer.new()
	segmented.add_theme_constant_override("separation", 1)
	add_child(segmented)
	for mode: int in [BuilderViewport.DragMode.LOOK, BuilderViewport.DragMode.POSE, BuilderViewport.DragMode.MOVE]:
		var button := Button.new()
		button.text = String(BuilderViewport.DRAG_MODE_LABELS[mode])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(56, BuilderTheme.TOUCH_MIN - 6)
		button.tooltip_text = "%s (P cycles)" % String(BuilderViewport.DRAG_MODE_HINTS[mode])
		button.pressed.connect(func() -> void: _viewport.set_drag_mode(mode))
		segmented.add_child(button)
		_mode_buttons.append(button)

	_view_menu = MenuButton.new()
	_view_menu.text = "View"
	_view_menu.flat = false
	_view_menu.custom_minimum_size = Vector2(64, BuilderTheme.TOUCH_MIN - 6)
	_view_menu.tooltip_text = "Mounts, mount names, camera angles"
	_view_menu.get_popup().id_pressed.connect(_on_menu)
	_view_menu.about_to_popup.connect(_rebuild_menu)
	add_child(_view_menu)
	_rebuild_menu()


func _rebuild_menu() -> void:
	var popup := _view_menu.get_popup()
	popup.clear()
	popup.add_check_item("Show empty mounts (G)", MENU_SOCKETS)
	popup.set_item_checked(
		popup.get_item_index(MENU_SOCKETS),
		_root.view != null and _root.view.sockets_visible()
	)
	popup.add_check_item("Label the mounts (L)", MENU_LABELS)
	popup.set_item_checked(popup.get_item_index(MENU_LABELS), _viewport.socket_labels_on)
	popup.add_separator()
	popup.add_item("Fit ship in view (F)", MENU_FRAME)
	popup.add_separator("Camera")
	for i in BuilderRoot.CAMERA_VIEWS.size():
		var view_name: String = BuilderRoot.CAMERA_VIEWS[i]
		popup.add_item("%s (%d)" % [view_name.capitalize(), i + 1], VIEW_BASE + i)


func _on_menu(id: int) -> void:
	match id:
		MENU_SOCKETS:
			_viewport.toggle_sockets()
		MENU_LABELS:
			_viewport.toggle_socket_labels()
		MENU_FRAME:
			_viewport.frame_ship()
		_:
			if id >= VIEW_BASE:
				_root.set_camera_view(BuilderRoot.CAMERA_VIEWS[id - VIEW_BASE])


func _on_drag_mode_changed(mode: int) -> void:
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == mode
