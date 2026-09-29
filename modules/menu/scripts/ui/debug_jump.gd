## DebugJump: a debug-build-only way from the home screen to anywhere — every
## front-end screen, a sandbox flight, every module in [ModuleRegistry] (the
## builder and the labs), and a few test helpers (coins, unlock the road).
##
## A small DEBUG chip in the corner; tapping it opens a scrolling list. Never
## built in a release export ([method OS.is_debug_build]).
class_name DebugJump
extends Control

var menu: MenuRoot
var _chip: SlabButton
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip = SlabButton.new()
	_chip.text = "DEBUG"
	_chip.fill = Color("3a3150")
	_chip.skew = 6.0
	_chip.font_size = 16
	_chip.custom_minimum_size = Vector2(96, 38)
	_chip.size = _chip.custom_minimum_size
	_chip.pressed.connect(_toggle)
	add_child(_chip)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.03, 0.1, 0.94)
	sb.border_color = GraffitiStyle.LIME
	sb.set_border_width_all(3)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(300, 420)
	_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_head(list, "SCREENS")
	_item(list, "HOME", func() -> void: menu.go(MenuRoot.Screen.HOME))
	_item(list, "CAMPAIGN MAP", func() -> void: menu.go(MenuRoot.Screen.MAP))
	_item(list, "GARAGE", func() -> void: menu.go(MenuRoot.Screen.GARAGE))
	_item(list, "SETTINGS", func() -> void: menu.go(MenuRoot.Screen.SETTINGS))
	_item(list, "SANDBOX FLIGHT", func() -> void: menu.launch_sandbox())
	_head(list, "MODULES")
	for id in ModuleRegistry.ids():
		if id == "menu":
			continue
		var path := ModuleRegistry.scene_path(id)
		_item(list, ModuleRegistry.display_name(id).to_upper(), func() -> void:
			get_tree().change_scene_to_file(path))
	_item(list, "WORKBENCH", func() -> void: menu.open_workbench())
	_head(list, "CHEATS")
	_item(list, "+5000 COINS", func() -> void: Campaign.add_coins(5000))
	_item(list, "WIN THE ROAD", _win_all)


func _head(list: VBoxContainer, text: String) -> void:
	var l := GraffitiStyle.label(text, 18, GraffitiStyle.LIME, 4)
	list.add_child(l)


func _item(list: VBoxContainer, text: String, on_press: Callable) -> void:
	var b := SlabButton.new()
	b.text = text
	b.fill = GraffitiStyle.VIOLET
	b.skew = 6.0
	b.font_size = 18
	b.custom_minimum_size = Vector2(260, 44)
	b.pressed.connect(func() -> void:
		_panel.visible = false
		on_press.call())
	list.add_child(b)


func _toggle() -> void:
	_panel.visible = not _panel.visible
	var vp := get_viewport_rect().size
	_panel.position = Vector2(12, maxf(12.0, vp.y - 480.0))


## Win every level on the road so far with three stars: the map, the fork
## and the star gates can be looked at without playing.
func _win_all() -> void:
	for s in Campaign.sectors():
		for l in s["levels"]:
			Campaign.apply_result(l, {"won": true, "time": 1.0, "kills": 5, "hull": 1.0})


func place(vp: Vector2) -> void:
	_chip.position = Vector2(12, vp.y - _chip.size.y - 12)
