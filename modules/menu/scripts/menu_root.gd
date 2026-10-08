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

enum Screen { HOME, MAP, GARAGE, SETTINGS, STORE, DAILY }

var stage: MenuStage
var ui: Control
var current: int = -1
## A pay-out waiting to be shown on the map (from a level just flown).
var last_result := {}
## The level whose ship is being picked in the garage ({} when the garage
## was opened for itself), and the one the map reopens its report on.
var ship_pick_level := {}
var reopen_level := {}

var _screens := {}
var _wipe: _Wipe
var _busy := false

#just used to track if song is playing for the first time per instance
var first_go := true


func _enter_tree() -> void:
	StyleManager.instance().load_saved()
	Session.start()
	Engine.time_scale = 1.0
	get_tree().paused = false


func _ready() -> void:
	# Launched with --module=<something else>: go there (the old launcher's
	# contract, so tools and shortcuts keep working).
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.z_index = 100
	add_child(fade)
	
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 0.0, 0.4)
	tw.tween_callback(fade.queue_free)
	
	if Session.boot_requested and Session.boot_module != "menu" and ModuleRegistry.has(Session.boot_module):
		var path := ModuleRegistry.scene_path(Session.boot_module)
		Session.boot_requested = false
		get_tree().change_scene_to_file.call_deferred(path)
		return
	# Closing the window asks QUIT? first (see _notification); the flight
	# scene puts the default back when it takes over.
	get_tree().set_auto_accept_quit(false)
	Campaign.ensure_loaded()
	# Where a flight asked to come back to: the sandbox's MAP, flight school.
	var back_key := String(Session.level_result.get("key", ""))
	var open_map := back_key == "tutorial" or String(Session.level_result.get("open", "")) == "map"
	# A Daily Sortie run is the daily module's, not the campaign's: it looks first.
	var daily := DailySortie.take_result()
	last_result = Campaign.take_result()
	Session.pending_level = {}
	Session.pending_ship = {}
	Session.space_setup = {}
	apply_volume()
	apply_orientation()
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
	_screens[Screen.STORE] = StoreScreen.new()
	_screens[Screen.DAILY] = DailyScreen.new()
	# The wallet's + (on every screen's wallet) opens the store.
	WalletChip.on_store = func() -> void: go(Screen.STORE)
	CoinStore.start()
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
	# NEXT on a win card: straight on into the next level, if it opened.
	var next_key := String(last_result.get("go_next", ""))
	var next_lvl := LevelGen.from_key(next_key) if next_key != "" else {}
	if not next_lvl.is_empty() and Campaign.is_unlocked(next_lvl):
		last_result = {}
		reopen_level = next_lvl
		_show(Screen.MAP)
		launch_level.call_deferred(next_lvl)
		return
	if not daily.is_empty():
		_show(Screen.DAILY)
		return
	_show(Screen.MAP if not last_result.is_empty() or open_map else Screen.HOME)


## Switch screens behind the wipe. The garage also swings the 3D camera to
## the pad while the wipe covers the screen.
func go(screen: int) -> void:
	if _busy or screen == current:
		return
	_busy = true
	_wipe.play(func() -> void: _show(screen), func() -> void: _busy = false)

func push_forward_song():
	GameAudio.current_song.play(25)

func _show(screen: int) -> void:
	for k in _screens:
		(_screens[k] as MenuScreen).visible = k == screen
	if current >= 0 and screen != current:
		GameAudio.ui(&"garage" if screen == Screen.GARAGE else &"open")
	current = screen
	
	var callback
	if screen == Screen.HOME and first_go:
		callback = push_forward_song
	
	var playlist := "submenus"
	if screen == Screen.HOME:
		playlist = "main"
	elif screen == Screen.GARAGE:
		playlist = "garage"
	GameAudio.music(playlist, callback)
	first_go = false
	stage.set_mode(MenuStage.Mode.GARAGE if screen == Screen.GARAGE else MenuStage.Mode.HOME)
	(_screens[screen] as MenuScreen).opened()


## Open the garage to pick the ship for [param lvl]; SELECT SHIP (or back)
## returns to the map with that level's report open.
func pick_ship_for(lvl: Dictionary) -> void:
	ship_pick_level = lvl
	go(Screen.GARAGE)


## Leave the ship pick: back to the map, the level's report open again.
func finish_ship_pick() -> void:
	reopen_level = ship_pick_level
	ship_pick_level = {}
	go(Screen.MAP)


## Fly a campaign level.
func launch_level(lvl: Dictionary) -> void:
	Campaign.launch(lvl)
	_to_flight()


## Fly today's Daily Sortie, ranked or practice. A refused ticket comes
## back for the daily screen to explain; nothing is flown then.
func launch_daily(ranked: bool) -> Dictionary:
	if _busy:
		return {"ok": false, "code": "busy", "message": "Already leaving"}
	var r := await DailySortie.start(ranked)
	if r.ok:
		_to_flight()
	return r


## The tutorial, flown like a level.
func launch_tutorial() -> void:
	Campaign.launch_tutorial()
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
	var title := "SANDBOX" if lvl.is_empty() else "LEVEL %d: %s" % [int(lvl.get("number", 1)), String(lvl.get("title", "")).to_upper()]
	if String(lvl.get("key", "")).begins_with(DailySortie.KEY_PREFIX):
		title = "DAILY SORTIE: %s" % String(lvl.get("title", "")).to_upper()
	if bool(lvl.get("tutorial", false)):
		title = "FLIGHT SCHOOL"
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


## Phones and tablets stay landscape (forced, not sensor-driven) unless the
## player picked portrait in Settings.
static func apply_orientation() -> void:
	if not OS.has_feature("mobile"):
		return
	var portrait := bool(Session.pref("portrait", false))
	DisplayServer.screen_set_orientation(
			DisplayServer.SCREEN_PORTRAIT if portrait else DisplayServer.SCREEN_LANDSCAPE)


## The saved SOUND and MUSIC levels (Settings), pushed onto their buses.
static func apply_volume() -> void:
	# SOUND and MUSIC each turn their own bus now; Master stays full (an old
	# save may have muted it).
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.set_bus_mute(bus, false)
	GameAudio.apply_volumes()


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
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		# The window's close button: home, and the QUIT? card there.
		if current == Screen.HOME:
			(_screens[Screen.HOME] as HomeScreen)._ask_quit()
		elif not _busy:
			go(Screen.HOME)
			_wipe_then_ask_quit()
	elif what == NOTIFICATION_EXIT_TREE:
		get_tree().set_auto_accept_quit(true)


func _wipe_then_ask_quit() -> void:
	while _busy:
		await get_tree().process_frame
	(_screens[Screen.HOME] as HomeScreen)._ask_quit()


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
