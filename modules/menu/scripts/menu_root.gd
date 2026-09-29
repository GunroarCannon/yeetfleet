## MenuRoot (modules/menu/menu.tscn): the game's front door — the home
## screen, the campaign map, the garage and settings, over the 3D [MenuStage].
##
## The module's façade. It boots the session, takes back the result of a
## level that just ended ([method Campaign.take_result]) and opens the map
## on it, and hands levels and sandbox flights to the flight scene through
## [Campaign] (which fills [Session]). Screens are Controls built in code, like
## the rest of the project's UI, and switch behind a spray-paint wipe.
class_name MenuRoot
extends Node

enum Screen { HOME, MAP, GARAGE, SETTINGS }

var stage: MenuStage
var ui: Control
var current: int = -1
## A pay-out waiting to be shown on the map (from a level just flown).
var last_result := {}

var _screens := {}
var _wipe: _Wipe
var _busy := false


func _enter_tree() -> void:
	StyleManager.instance().load_saved()
	Session.start()
	Engine.time_scale = 1.0
	get_tree().paused = false


func _ready() -> void:
	# Launched with --module=<something else>: go there (the old launcher's
	# contract, so tools and shortcuts keep working).
	if Session.boot_requested and Session.boot_module != "menu" and ModuleRegistry.has(Session.boot_module):
		var path := ModuleRegistry.scene_path(Session.boot_module)
		Session.boot_requested = false
		get_tree().change_scene_to_file.call_deferred(path)
		return
	Campaign.ensure_loaded()
	last_result = Campaign.take_result()
	Session.pending_level = {}
	Session.pending_ship = {}
	apply_volume()
	# The ⚡ performance dials hold here too: battery saver's frame cap and
	# render scale matter most on a screen people leave open.
	PerformanceSettings.ensure_loaded()
	PerformanceSettings.apply(get_tree())
	stage = MenuStage.new()
	stage.name = "Stage"
	add_child(stage)
	var layer := CanvasLayer.new()
	layer.name = "Ui"
	add_child(layer)
	ui = Control.new()
	ui.name = "Root"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	BuilderTheme.apply_density_scale(get_window())
	get_viewport().size_changed.connect(_on_resized)
	_screens[Screen.HOME] = HomeScreen.new()
	_screens[Screen.MAP] = MapScreen.new()
	_screens[Screen.GARAGE] = GarageScreen.new()
	_screens[Screen.SETTINGS] = SettingsScreen.new()
	for k in _screens:
		var s := _screens[k] as MenuScreen
		s.menu = self
		s.visible = false
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui.add_child(s)
	_wipe = _Wipe.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_wipe)
	_on_resized()
	_show(Screen.MAP if not last_result.is_empty() else Screen.HOME)


## Switch screens behind the wipe. The garage also swings the 3D camera to
## the pad while the wipe covers the screen.
func go(screen: int) -> void:
	if _busy or screen == current:
		return
	_busy = true
	_wipe.play(func() -> void: _show(screen), func() -> void: _busy = false)


func _show(screen: int) -> void:
	for k in _screens:
		(_screens[k] as MenuScreen).visible = k == screen
	current = screen
	stage.set_mode(MenuStage.Mode.GARAGE if screen == Screen.GARAGE else MenuStage.Mode.HOME)
	(_screens[screen] as MenuScreen).opened()


## Fly a campaign level.
func launch_level(lvl: Dictionary) -> void:
	Campaign.launch(lvl)
	_to_flight()


## Free flight in the player's own ship.
func launch_sandbox() -> void:
	Campaign.launch_sandbox()
	_to_flight()


func _to_flight() -> void:
	if _busy:
		return
	_busy = true
	var lvl := Session.pending_level
	var title := "SANDBOX" if lvl.is_empty() else "LEVEL %d · %s" % [int(lvl.get("number", 1)), String(lvl.get("title", "")).to_upper()]
	# Behind the wipe, the loading card goes up and starts pulling the flight
	# scene in on a worker thread.
	_wipe.play(func() -> void:
		var card := LoadingScreen.new()
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui.add_child(card)
		ui.move_child(_wipe, -1)
		card.start(ModuleRegistry.scene_path("flight"), title), Callable())


## The dev workbench: the old module launcher (labs, builder, arena...).
func open_workbench() -> void:
	get_tree().change_scene_to_file("res://modules/core/core.tscn")


## The saved master volume (Settings), pushed onto the Master bus.
static func apply_volume() -> void:
	var v := clampf(float(Session.pref("master_volume", 1.0)), 0.0, 1.0)
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(bus, v <= 0.001)


func is_portrait() -> bool:
	var s := get_viewport().get_visible_rect().size
	return s.y > s.x


func _on_resized() -> void:
	BuilderTheme.apply_density_scale(get_window())
	if stage != null:
		stage.set_portrait(is_portrait())
	for k in _screens:
		(_screens[k] as MenuScreen).layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


## Android Back / Escape: the screen first (close a panel), then home.
func back() -> void:
	if current < 0 or _busy:
		return
	if (_screens[current] as MenuScreen).back():
		return
	if current != Screen.HOME:
		go(Screen.HOME)


## The screen change: a hot-pink slab with an ink edge sweeps across,
## the screens swap while it covers everything, and it sweeps off.
class _Wipe:
	extends Control
	var _t := -1.0
	var _mid: Callable
	var _end: Callable
	var _swapped := false

	func play(mid: Callable, end: Callable) -> void:
		_mid = mid
		_end = end
		_t = 0.0
		_swapped = false
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		if _t < 0.0:
			return
		_t += delta / 0.5
		if _t >= 0.5 and not _swapped:
			_swapped = true
			if _mid.is_valid():
				_mid.call()
		if _t >= 1.0:
			_t = -1.0
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			if _end.is_valid():
				_end.call()
		queue_redraw()

	func _draw() -> void:
		if _t < 0.0:
			return
		var w := size.x
		var h := size.y
		var lean := h * 0.35
		# First half: the leading edge sweeps in from the right until the band
		# covers everything. Second half: the trailing edge follows it off left.
		var far_r := w + lean + 60.0
		var far_l := -lean - 60.0
		var left := lerpf(far_r, far_l, ease(clampf(_t * 2.0, 0.0, 1.0), -2.2))
		var right := lerpf(far_r, far_l, ease(clampf(_t * 2.0 - 1.0, 0.0, 1.0), -2.2))
		var band := PackedVector2Array([
			Vector2(left + lean, 0), Vector2(right + lean, 0),
			Vector2(right, h), Vector2(left, h),
		])
		if right - left < 2.0:
			return
		draw_colored_polygon(band, GraffitiStyle.HOT)
		if right - left < 70.0:
			return
		var inner := PackedVector2Array([
			Vector2(left + lean + 30, 0), Vector2(right + lean - 30, 0),
			Vector2(right - 30, h), Vector2(left + 30, h),
		])
		draw_colored_polygon(inner, GraffitiStyle.INK)
		draw_polyline(PackedVector2Array([band[0], band[3]]), GraffitiStyle.LIME, 8.0)
		draw_polyline(PackedVector2Array([band[1], band[2]]), GraffitiStyle.LIME, 8.0)
