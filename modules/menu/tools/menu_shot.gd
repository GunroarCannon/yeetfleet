## Screenshots of every front-end screen, for judging the look (windowed —
## the headless renderer draws nothing):
##
##     godot --path . --audio-driver Dummy --resolution 1280x720 \
##         --script modules/menu/tools/menu_shot.gd -- <out_dir> [w h]
##
## Writes home.png, map.png, report.png, fork.png, garage.png, shop.png and
## settings.png. Runs on a scratch campaign save with a little progress
## (first sector won, some coins) so the map and garage have something to
## show; the player's own save is never touched.
extends SceneTree

const SCRATCH := "user://menu_shot_scratch.json"

var _out := "res://.shots/menu"
var _menu: MenuRoot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	if args.size() >= 3:
		root.size = Vector2i(int(args[1]), int(args[2]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") or _out.begins_with("user://") else _out)
	Campaign.save_path = SCRATCH
	Campaign.reset()
	Campaign.add_coins(900)
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
	_menu.go(MenuRoot.Screen.MAP)
	await _wait(1.2)
	await _shot("map")
	var map := _menu._screens[MenuRoot.Screen.MAP] as MapScreen
	map._on_level(Campaign.sectors()[0]["levels"][3])
	await _wait(0.8)
	await _shot("report")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
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
