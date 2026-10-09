## Store screenshots (Play and the Solana dApp Store), taken from the real
## game on a scratch save (the player's own save is never touched): the home
## screen, the campaign map, a mission report, the garage, two levels in
## flight, and the Solana screens: the Pilot ID, the Daily Sortie and the
## SKR shop, signed in on the mock wallet against the leaderboard Worker's
## local dev server (needs `node`; skipped without it).
##
##     godot --path . --audio-driver Dummy --script launch/tools/store_shots.gd [-- 1920 1080]
##
## Windowed (the headless renderer draws nothing). Writes
## launch/screenshots/01_home.png … 09_skr_shop.png at the given size
## (default 1920×1080 landscape; pass 1080 1920 for portrait). The home
## screen's blast is a different kind each run.
extends SceneTree

const OUT := "res://launch/screenshots"
const SCRATCH := "user://store_shots_scratch.json"
const CHAIN_SCRATCH := "user://store_shots_chain.cfg"
const DAILY_SCRATCH := "user://store_shots_daily.cfg"
const PORT := 8794

var _size := Vector2i(1920, 1080)
var _menu: MenuRoot
var _pid := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_size = Vector2i(int(args[0]), int(args[1]))
	Campaign.save_path = SCRATCH
	Campaign.reset()
	# A little progress, so the map and garage have something to show.
	var levels: Array = Campaign.sectors()[0]["levels"]
	for i in 3:
		Campaign.apply_result(levels[i], {"won": true, "time": 40.0, "kills": 6, "hull": 0.7})
	Campaign.add_coins(900)
	for n in ["intro", "ships", "upgrade"]:
		Campaign.mark_nudge(n)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHAIN_SCRATCH))
	Chain.save_path = CHAIN_SCRATCH
	Chain.api_url = ""
	Chain.reset(true)
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"
	Chain.client().mock.device["seeker"] = true
	DailySortie.save_path = DAILY_SCRATCH
	_run.call_deferred()


func _run() -> void:
	root.size = _size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file(ModuleRegistry.scene_path("menu"))
	await _wait(3.0)
	_menu = current_scene as MenuRoot
	await _shot("01_home")
	_menu.go(MenuRoot.Screen.MAP)
	await _wait(1.4)
	await _shot("02_map")
	var map := _menu._screens[MenuRoot.Screen.MAP] as MapScreen
	map._on_level(Campaign.sectors()[0]["levels"][3])
	await _wait(0.9)
	await _shot("03_report")
	map._report.close()
	_menu.go(MenuRoot.Screen.GARAGE)
	await _wait(1.6)
	await _shot("04_garage")
	await _solana_shots()
	await _fly(Campaign.sectors()[0]["levels"][2], "05_flight_a")
	await _fly(Campaign.sectors()[0]["levels"][5], "06_flight_b")
	for p in [SCRATCH, CHAIN_SCRATCH, DAILY_SCRATCH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if _pid > 0:
		OS.kill(_pid)
	quit()


## The Pilot ID card, the Daily Sortie (with a board) and the SKR shop.
func _solana_shots() -> void:
	var out: Array = []
	if OS.execute("node", ["--version"], out) != 0:
		print("[shots] no node: Solana screens skipped")
		return
	_pid = OS.create_process("node", [ProjectSettings.globalize_path("res://services/leaderboard-worker/test/dev_server.js"), str(PORT)])
	var base := "http://127.0.0.1:%d" % PORT
	for i in 40:
		if (await Chain.Api.fetch(base, "/health")).ok:
			break
		await _wait(0.25)
	Chain.api_url = base
	await Chain.sign_in("Ace")
	# Today's board: one ranked run (armed by the mock wallet) and a practice.
	await DailySortie.refresh()
	for ranked in [true, false]:
		if (await DailySortie.start(ranked)).ok:
			await _wait(4.2)
			Session.level_result = {"key": Session.pending_level.key, "won": true, "time": 4.0, "kills": 7, "hull": 0.8}
			DailySortie.take_result()
			await _wait(0.6)
	await Chain.buy("paint:skr_gold")
	Chain.equip("paint:skr_gold")
	_menu.go(MenuRoot.Screen.HOME)
	await _wait(1.2)
	var home := _menu._screens[MenuRoot.Screen.HOME] as HomeScreen
	home._pilot._skr = 1240.0
	home._pilot._open_card()
	await _wait(0.6)
	await _shot("07_pilot_id")
	home._pilot.close_card()
	_menu.go(MenuRoot.Screen.DAILY)
	await _wait(1.6)
	await _shot("08_daily_sortie")
	_menu.go(MenuRoot.Screen.STORE)
	await _wait(0.8)
	var store := _menu._screens[MenuRoot.Screen.STORE] as StoreScreen
	store.show_tab("skr")
	await _wait(1.0)
	store._skr._balance = 1240.0
	store._skr.refresh()
	await _shot("09_skr_shop")


## Fly [param lvl] a few seconds in (past the opening swoop) and shoot it.
func _fly(lvl: Dictionary, name: String) -> void:
	Campaign.launch(lvl)
	change_scene_to_file(ModuleRegistry.scene_path("flight"))
	await _wait(CampaignLevelOverlay.START_DELAY + 4.0)
	await _shot(name)


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := OUT.path_join(name + ".png")
	img.save_png(ProjectSettings.globalize_path(path))
	print("[shots] ", path)
