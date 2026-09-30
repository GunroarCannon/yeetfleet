## End-to-end headless check of the front end and its handoff to flight:
## the menu boots to HOME, the map opens a level's report, FLY loads the real
## flight scene with that level's scenario and ship, a win and MAP come back
## to the menu, and the campaign counts it once (record, stars, coins). Also:
## SWAP on the report picks a ship in the garage and comes back to the
## report; the loading card covers the swap and lifts; the pause stops the
## game; bailing out from the pause pays nothing and shows no pay-out card.
##
##     godot --headless --path . --audio-driver Dummy --script modules/menu/tools/menu_check.gd
##
## Runs on a scratch campaign save. Judge by the PASS/FAIL line: headless
## runs segfault at exit (a pre-existing engine issue, see the memory notes).
extends SceneTree

const SCRATCH := "user://menu_check_scratch.json"

var _failures: Array[String] = []


func _initialize() -> void:
	Campaign.save_path = SCRATCH
	Campaign.reset()
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
	print("  %-52s %s" % [msg, "ok" if cond else "FAILED"])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	print("── menu check ─────────────────────────────────────────")
	change_scene_to_file("res://modules/menu/menu.tscn")
	await _frames(6)
	var menu := current_scene as MenuRoot
	_check(menu != null, "menu scene boots as MenuRoot")
	if menu == null:
		return _finish()
	_check(menu.current == MenuRoot.Screen.HOME, "fresh boot lands on HOME")
	menu.go(MenuRoot.Screen.MAP)
	await _secs(0.8)
	_check(menu.current == MenuRoot.Screen.MAP, "CAMPAIGN opens the map")
	var map := menu._screens[MenuRoot.Screen.MAP] as MapScreen
	var lvl: Dictionary = Campaign.sectors()[0]["levels"][0]
	map._on_level(lvl)
	await _frames(3)
	_check(map._report.is_open(), "tapping a card opens the report")
	# SWAP: the garage as a ship picker, and back to the same report.
	map._report.pick_ship.emit(lvl)
	await _secs(0.8)
	var garage := menu._screens[MenuRoot.Screen.GARAGE] as GarageScreen
	_check(menu.current == MenuRoot.Screen.GARAGE and garage._bar.title == "PICK A SHIP", "SWAP opens the garage as a ship picker")
	_check(garage._action.text == "SELECT SHIP", "an allowed owned ship offers SELECT SHIP")
	garage._on_action()
	await _secs(0.8)
	_check(menu.current == MenuRoot.Screen.MAP and map._report.is_open() and String(map._report._paper.lvl.get("key", "")) == String(lvl["key"]),
		"SELECT SHIP returns to that level's report")
	var coins := Campaign.coins()
	map._report._on_fly()
	# Through the wipe and the loading card (a threaded load): wait for it.
	var until := Time.get_ticks_msec() + 20000
	var saw_loading := false
	while Time.get_ticks_msec() < until and not (current_scene is FlightRoot):
		if menu != null and is_instance_valid(menu) and menu.ui.find_children("*", "LoadingScreen", true, false).size() > 0:
			saw_loading = true
		await process_frame
	await _frames(3)
	_check(saw_loading, "FLY! shows the loading card")
	var flight := current_scene as FlightRoot
	_check(flight != null, "FLY! loads the flight scene")
	if flight == null:
		return _finish()
	_check(flight.campaign_overlay != null, "flight shows the level overlay")
	_check(flight.design != null and String(Session.pending_ship.get("preset", "")) != "", "flight flies the handed-over hull")
	await _secs(1.5)
	_check(root.get_node_or_null("LoadingCover") == null, "the loading card lifts off the flight")
	await _secs(CampaignLevelOverlay.START_DELAY - 0.9)
	_check(flight.scenarios.is_running(), "the level's scenario starts by itself")
	flight.campaign_overlay.toggle_pause()
	await _frames(2)
	_check(paused and flight.campaign_overlay.is_paused(), "MAP / Back pauses the game")
	flight.campaign_overlay.toggle_pause()
	await _frames(2)
	_check(not paused, "RESUME unpauses")
	_check(String(flight.scenarios.config.get("name", "")) == String(lvl["title"]), "scenario runs the level's config")
	# A real run has to last a moment: instant "wins" are refused.
	await _secs(2.0)
	flight.scenarios._finish(true)
	await _secs(CampaignLevelOverlay.CARD_DELAY + 0.4)
	_check(flight.campaign_overlay._card != null, "a win shows the end card")
	flight.campaign_overlay._leave()
	await _frames(8)
	menu = current_scene as MenuRoot
	_check(menu != null and menu.current == MenuRoot.Screen.MAP, "MAP returns to the menu's map")
	var rec := Campaign.record(String(lvl["key"]))
	_check(int(rec["wins"]) == 1 and int(rec["attempts"]) == 1, "the win is on the record once")
	_check(Campaign.coins() > coins, "the level paid out")
	_check(Session.level_result.is_empty() and Session.pending_level.is_empty(), "handoff dictionaries are cleared")
	# Again, and bail out from the pause: a try, no pay, no card.
	await _secs(0.6)
	map = menu._screens[MenuRoot.Screen.MAP] as MapScreen
	if map._payout != null and is_instance_valid(map._payout):
		map._payout.queue_free()
		map._payout = null
	coins = Campaign.coins()
	map._on_level(lvl)
	await _frames(3)
	map._report._on_fly()
	until = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until and not (current_scene is FlightRoot):
		await process_frame
	flight = current_scene as FlightRoot
	if flight == null:
		_check(false, "second flight loads")
		return _finish()
	await _secs(CampaignLevelOverlay.START_DELAY + 1.0)
	flight.campaign_overlay.toggle_pause()
	await _frames(2)
	flight.campaign_overlay._leave()
	await _frames(8)
	menu = current_scene as MenuRoot
	map = menu._screens[MenuRoot.Screen.MAP] as MapScreen if menu != null else null
	_check(map != null and (map._payout == null or not is_instance_valid(map._payout)), "bailing out shows no pay-out card")
	rec = Campaign.record(String(lvl["key"]))
	_check(int(rec["attempts"]) == 2 and int(rec["wins"]) == 1 and Campaign.coins() == coins, "a bail-out is a try and pays nothing")
	_check(not paused, "leaving from the pause unpauses")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("PASS menu_check" if _failures.is_empty() else "FAIL menu_check (%d)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
