## Play Store screenshots, taken from the real game on a scratch save (the
## player's own save is never touched): the home screen, the campaign map, a
## mission report, the garage, and two levels in flight.
##
##     godot --path . --audio-driver Dummy --script launch/tools/store_shots.gd [-- 1920 1080]
##
## Windowed (the headless renderer draws nothing). Writes
## launch/screenshots/01_home.png … 06_flight_b.png at the given size
## (default 1920×1080 landscape; pass 1080 1920 for portrait). The home
## screen's blast is a different kind each run.
extends SceneTree

const OUT := "res://launch/screenshots"
const SCRATCH := "user://store_shots_scratch.json"

var _size := Vector2i(1920, 1080)
var _menu: MenuRoot


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
	await _fly(Campaign.sectors()[0]["levels"][2], "05_flight_a")
	await _fly(Campaign.sectors()[0]["levels"][5], "06_flight_b")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	quit()


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
