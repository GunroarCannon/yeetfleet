## Gameplay takes for the demo video, recorded with Godot's Movie Maker so
## every frame lands at exactly 1/60 s however slowly it renders. A bot thumb
## flies the slingshot (press on the ship, pull back from an enemy, let go;
## taps to shoot mid-flight). Shot as a phone sees it: the window at 20:9
## landscape, the canvas a phone's after its DPI scale, the mobile HUD; no
## tutorial, no coach, no callouts ("BOSS AHEAD!"). On a scratch save (the
## player's own save is never touched), on the shipped Juice defaults, the
## music bus muted (the editor adds music).
##
##     godot --path . --fixed-fps 60 --write-movie out.avi --script launch/tools/demo_reel.gd -- <take> [seconds] [ship id]
##
## Windowed. Takes: intro (the studio splash into the home screen), home,
## fight, boss, swarm, map, garage. Each flight take flies its own hull
## ([constant TAKE_SHIP]), so the video shows the fleet. For 2400×1080 on a
## smaller screen, an override.cfg with window/size/window_*_override is
## needed for the length of the run (launch/video/render_takes.sh does it).
extends SceneTree

const SCRATCH := "user://demo_reel_scratch.json"
const CHAIN_SCRATCH := "user://demo_reel_chain.cfg"
## A phone's density correction (BuilderTheme.density_scale): ~400 dpi / 160
## over the 1.5 stretch of 1080 px tall, so the canvas comes out 960×432.
const PHONE_SCALE := 5.0 / 3.0
## The window: a phone held sideways (20:9).
const WINDOW := Vector2i(2400, 1080)
## The hull each flight take flies (index into ShipCatalog.ids()).
const TAKE_SHIP := {"fight": 1, "boss": 5, "swarm": 8}

var _take := "fight"
var _length := 24.0
var _frame := 0
var _end_frame := -1
var _rng := RandomNumberGenerator.new()

# The bot thumb.
var _phase := "idle"
var _phase_t := 0.0
var _rest_t := 0.0
var _pull_from := Vector2.ZERO
var _pull_to := Vector2.ZERO
var _tap_t := 0.0
var _target: AiShip = null
## The thumb waits for the level's intro card to clear.
var _bot_from := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_take = args[0]
	if args.size() >= 2:
		_length = float(args[1])
	_rng.seed = 7
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	Session.prefs["mobile_layout"] = true
	RenderingServer.frame_pre_draw.connect(_before_draw)
	JuiceSettings._loaded = true
	Campaign.save_path = SCRATCH
	Campaign.reset()
	var levels: Array = Campaign.sectors()[0]["levels"]
	for i in 4:
		Campaign.apply_result(levels[i], {"won": true, "time": 40.0, "kills": 6, "hull": 0.7})
	Campaign.add_coins(1000000)
	# Own the whole fleet, so each take can fly its own hull.
	for id in ShipCatalog.ids():
		Campaign.buy_ship(id)
	Campaign.add_coins(1480 - Campaign.coins())
	var ids := ShipCatalog.ids()
	var ship := String(args[2]) if args.size() >= 3 else ids[int(TAKE_SHIP.get(_take, 0)) % ids.size()]
	Campaign.select_ship(ship)
	print("[reel] ship %s" % ship)
	for n in ["intro", "ships", "upgrade"]:
		Campaign.mark_nudge(n)
	Session.prefs["tutorial_done"] = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHAIN_SCRATCH))
	Chain.save_path = CHAIN_SCRATCH
	Chain.api_url = ""
	Chain.reset(true)
	_run.call_deferred()


func _run() -> void:
	match _take:
		"intro":
			change_scene_to_file("res://modules/menu/splash.tscn")
			_end_after(_length)
		"home":
			change_scene_to_file(ModuleRegistry.scene_path("menu"))
			_end_after(_length)
		"map", "garage":
			change_scene_to_file(ModuleRegistry.scene_path("menu"))
			await _wait_frames(30)
			(current_scene as MenuRoot).go(MenuRoot.Screen.MAP if _take == "map" else MenuRoot.Screen.GARAGE)
			_end_after(_length)
		"fight", "boss", "swarm":
			var kinds: Array = {"fight": ["battle", "skirmish", "ambush"], "boss": ["boss"], "swarm": ["waves", "assault", "survive"]}[_take]
			_bot_from = _frame + int((CampaignLevelOverlay.START_DELAY + 0.3) * 60.0)
			Campaign.launch(_level_of(kinds))
			change_scene_to_file(ModuleRegistry.scene_path("flight"))
			JuiceSettings.player_invulnerable = true
			_end_after(_length + CampaignLevelOverlay.START_DELAY)
		_:
			push_error("[reel] unknown take %s" % _take)
			quit(1)


## The first level whose kind is one of [param kinds], from the third sector
## on (the first two are onboarding), down the first fork each time.
func _level_of(kinds: Array) -> Dictionary:
	var r: Array[int] = [LevelGen.first_theme()]
	for depth in 8:
		if depth >= 2:
			for i in LevelGen.LEVELS_PER_SECTOR:
				var lvl := LevelGen.level(r, i)
				if String(lvl["kind"]) in kinds:
					print("[reel] level %s (%s, sector %d)" % [lvl["title"], lvl["kind"], depth + 1])
					return lvl
		r.append(LevelGen.fork_options(r, r[-1])[0])
	return Campaign.sectors()[0]["levels"][2]


func _end_after(seconds: float) -> void:
	_end_frame = _frame + int(seconds * 60.0)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _process(delta: float) -> bool:
	_frame += 1
	var music := AudioServer.get_bus_index(&"Music")
	if music >= 0:
		AudioServer.set_bus_mute(music, true)
	# The scenes put a desktop's factor (1) back on every resize.
	if not is_equal_approx(root.content_scale_factor, PHONE_SCALE):
		root.content_scale_factor = PHONE_SCALE
	var fr := current_scene as FlightRoot
	if fr != null and is_instance_valid(fr):
		if not is_equal_approx(fr.time_scale(), 1.0) and _frame < 30:
			fr.set_time_scale(1.0)
		if _frame >= _bot_from:
			_bot(fr, delta)
	return _end_frame >= 0 and _frame >= _end_frame


## Last thing before a frame is drawn, so nothing turns them back on after.
func _before_draw() -> void:
	var fr := current_scene as FlightRoot
	if fr != null and is_instance_valid(fr):
		_quiet(fr)


## No coach, no hints or callouts on screen: the video's captions do the talking.
func _quiet(fr: FlightRoot) -> void:
	var coach := fr.get_node_or_null("Ui/Coach") as CanvasItem
	if coach != null:
		coach.visible = false
	if fr._hud != null:
		for l: Label in [fr._hud._hint_label, fr._hud._damage_label]:
			if l != null:
				l.visible = false


# --- Bot thumb -------------------------------------------------------------------

## Press on the ship, pull back away from the enemy it wants, hold, let go;
## mid-flight, tap on the target to shoot.
func _bot(fr: FlightRoot, delta: float) -> void:
	var pilot := fr.pilot() as SlingshotPilot
	if pilot == null:
		if _frame > 10 and fr.has_method("set_move_profile"):
			fr.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
		return
	if pilot.run == null:
		return
	_phase_t += delta
	var cam := fr.camera_node()
	match _phase:
		"idle":
			if pilot.run.state != SlingRun.State.READY:
				_tap(fr, pilot, cam, delta)
				_rest_t = 0.0
				return
			_rest_t += delta
			if _rest_t < 0.45:
				return
			var s := pilot.ship_screen_pos()
			if s == Vector2.INF:
				return
			_target = _pick(fr, cam)
			var dir := Vector2(0.0, -1.0)
			if _target != null:
				var t := cam.unproject_position(_target.global_position)
				if t.distance_to(s) > 8.0:
					dir = (t - s).normalized()
			dir = dir.rotated(_rng.randf_range(-0.08, 0.08))
			_pull_from = s
			_pull_to = s - dir * pilot.short_edge() * _rng.randf_range(0.26, 0.34)
			pilot._on_pressed(s)
			_phase = "pull"
			_phase_t = 0.0
		"pull":
			var k := clampf(_phase_t / 0.55, 0.0, 1.0)
			var at := _pull_from.lerp(_pull_to, 1.0 - pow(1.0 - k, 3.0))
			pilot._on_dragged(at, _pull_from)
			if _phase_t >= 0.75:
				# Let go straight at the target, wherever it is: off screen the
				# pull can only guess.
				if is_instance_valid(_target) and _target._alive and pilot.will_launch():
					pilot.aim_dir = (_target.global_position - fr.model.global_position).normalized()
				pilot._on_released(at)
				_phase = "idle"
				_phase_t = 0.0
				_tap_t = 0.1


func _tap(fr: FlightRoot, pilot: SlingshotPilot, cam: Camera3D, delta: float) -> void:
	_tap_t -= delta
	if _tap_t > 0.0 or pilot.run.state != SlingRun.State.FLYING:
		return
	_tap_t = 0.45
	var t := _pick(fr, cam)
	if t != null:
		pilot._on_tap(cam.unproject_position(t.global_position))


## The live enemy on screen nearest the player, else the nearest at all.
func _pick(fr: FlightRoot, cam: Camera3D) -> AiShip:
	var best: AiShip = null
	var best_d := INF
	var any: AiShip = null
	var any_d := INF
	for ship in fr.live_enemies():
		var d := ship.global_position.distance_to(fr.model.global_position)
		if d < any_d:
			any_d = d
			any = ship
		if cam.is_position_behind(ship.global_position) or not cam.is_position_in_frustum(ship.global_position):
			continue
		if d < best_d:
			best_d = d
			best = ship
	return best if best != null else any
