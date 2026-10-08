## Screenshots of every front-end screen, for judging the look (windowed —
## the headless renderer draws nothing):
##
##     godot --path . --audio-driver Dummy --resolution 1280x720 \
##         --script modules/menu/tools/menu_shot.gd -- <out_dir> [w h [canvas_w canvas_h]]
##
## Writes home.png, quit.png, map.png, report.png, pick.png (the garage as a
## level's ship picker), fork.png, garage.png, shop.png, settings.png,
## settings_sub.png (the PERFORMANCE submenu), store.png, rename.png, loading.png, and
## pilot.png / pilot_card.png (the Pilot ID signed in on the mock wallet) and daily.png
## (the Daily Sortie, offline: its board says so). Runs on a scratch campaign save with a little progress
## (first sector won, some coins) so the map and garage have something to
## show; the player's own save is never touched.
extends SceneTree

const SCRATCH := "user://menu_shot_scratch.json"
const CHAIN_SCRATCH := "user://menu_shot_chain.cfg"

var _out := "res://debug_shots/menu"
var _menu: MenuRoot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	if args.size() >= 3:
		root.size = Vector2i(int(args[1]), int(args[2]))
		DisplayServer.window_set_size(root.size)
		# The canvas: the window itself, or (5th/6th args) a phone's canvas
		# after its DPI scale, e.g. 960 432 or 432 960, drawn into a window
		# of the same shape that fits the desktop.
		root.content_scale_size = root.size
		if args.size() >= 5:
			root.content_scale_size = Vector2i(int(args[3]), int(args[4]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") or _out.begins_with("user://") else _out)
	Campaign.save_path = SCRATCH
	Campaign.reset()
	Campaign.add_coins(900)
	# The mock wallet, signed out, with an RPC that fails at once.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHAIN_SCRATCH))
	Chain.save_path = CHAIN_SCRATCH
	Chain.reset(true)
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"
	Chain.client().mock.device["seeker"] = true
	var secs := Campaign.sectors()
	var levels: Array = secs[0]["levels"]
	for i in 3:
		Campaign.apply_result(levels[i], {"won": true, "time": 20.0 + i * 30.0, "kills": 3, "hull": 0.7 - i * 0.25})
	Campaign.apply_result(levels[3], {"won": false, "time": 40.0, "kills": 1, "attempts": 2})
	_run.call_deferred()


func _run() -> void:
	_menu = (load("res://modules/menu/menu.tscn") as PackedScene).instantiate() as MenuRoot
	root.add_child(_menu)
	current_scene = _menu
	await _wait(3.0)
	await _shot("home")
	var home := _menu._screens[MenuRoot.Screen.HOME] as HomeScreen
	home._ask_quit()
	await _wait(0.5)
	await _shot("quit")
	home._close_quit()
	await Chain.sign_in()
	await _wait(0.4)
	home._pilot._skr = 1240.0
	home._pilot.queue_redraw()
	await _shot("pilot")
	home._pilot._open_card()
	await _wait(0.5)
	await _shot("pilot_card")
	home._pilot.close_card()
	_menu.go(MenuRoot.Screen.MAP)
	await _wait(1.2)
	await _shot("map")
	var map := _menu._screens[MenuRoot.Screen.MAP] as MapScreen
	map._on_level(Campaign.sectors()[0]["levels"][3])
	await _wait(0.8)
	await _shot("report")
	# SWAP: the garage as this level's ship picker.
	map._report.pick_ship.emit(Campaign.sectors()[0]["levels"][3])
	await _wait(1.4)
	await _shot("pick")
	_menu.finish_ship_pick()
	await _wait(1.0)
	map._report.close()
	# Win the rest of the sector: the fork appears.
	for l in Campaign.sectors()[0]["levels"]:
		Campaign.apply_result(l, {"won": true, "time": 30.0, "kills": 9, "hull": 0.8})
	map._map.rebuild()
	map._map.focus_next(true)
	await _wait(0.6)
	map._on_fork(Campaign.fork_options()[1])
	await _wait(0.8)
	await _shot("fork")
	map._report.close()
	_menu.go(MenuRoot.Screen.GARAGE)
	await _wait(1.4)
	await _shot("garage")
	var garage := _menu._screens[MenuRoot.Screen.GARAGE] as GarageScreen
	garage._set_shelf(GarageScreen.Shelf.SHOP)
	garage._step(1)
	await _wait(1.0)
	await _shot("shop")
	_menu.go(MenuRoot.Screen.SETTINGS)
	await _wait(1.0)
	await _shot("settings")
	var settings := _menu._screens[MenuRoot.Screen.SETTINGS] as SettingsScreen
	settings._open_sub("PERFORMANCE")
	await _wait(2.0)
	await _shot("settings_sub")
	settings._close_sub()
	await _wait(0.6)
	_menu.go(MenuRoot.Screen.STORE)
	await _wait(1.0)
	await _shot("store")
	_menu.go(MenuRoot.Screen.DAILY)
	await _wait(1.2)
	await _shot("daily")
	var wallet := (_menu._screens[MenuRoot.Screen.STORE] as StoreScreen)._bar._wallet
	wallet._ask_name()
	await _wait(0.5)
	await _shot("rename")
	wallet._close_name()
	var card := LoadingScreen.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.ui.add_child(card)
	card._title = "LEVEL 3: WOBBLY DRIFT"
	card._tip = LoadingScreen.TIPS[0]
	card._target = 0.62
	await _wait(0.8)
	await _shot("loading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHAIN_SCRATCH))
	quit()


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("[menu_shot] ", path)
