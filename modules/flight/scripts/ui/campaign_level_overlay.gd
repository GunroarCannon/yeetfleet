## CampaignLevelOverlay: the flight scene's side of a level handed over by
## the game's menu ([member Session.pending_level]).
##
## It starts the level's scenario once the scene has settled, slams the
## level's name on screen, and when the scenario ends shows a graffiti end
## card — YEET! or why it was lost (WRECKED, ESCORT DESTROYED, OUT OF TIME), the
## stars, time and wrecks — with RETRY, MAP and, after a win that opened a
## level not yet won, NEXT.
## The MAP button, Back and Escape pause the game ([method toggle_pause]): a
## card with the level's brief (what to do), RESUME, RETRY and MAP.
## Leaving writes [member Session.level_result] and goes back to the menu,
## which counts it. Sandbox flights (a ship but no level) pause the same way,
## with only RESUME and HOME, and a wreck there shows the points card: the
## life's points counting up into coins, then RETRY, MAP and HOME.
##
## Its own [CanvasLayer] above the HUD. Reads the scenario through
## [member FlightRoot.scenarios] and never touches the campaign module.
class_name CampaignLevelOverlay
extends CanvasLayer

## The opening shot: the camera swoops in from far out onto the ship, with
## the controls held, before anything starts.
const INTRO_TIME := 2.6
## Seconds after the scene is up before the level starts: once the opening
## shot has landed.
const START_DELAY := INTRO_TIME + 0.2
## Seconds between the scenario ending and the card appearing — the kill cam
## and the explosion get their moment first.
const CARD_DELAY := 1.6

var _root: FlightRoot
var _level := {}
var _top: Control
var _home: SlabButton
var _card: Control = null
var _pause: Control = null
var _banner: Control = null
var _started := false
var _attempts := 0
## The best finished run: `{won, time, kills, hull}`; {} until one ends.
var _best := {}
var _state_seen := -1
## Sandbox: seconds alive this life, and coins banked across lives (paid on
## the way out).
var _life_t := 0.0
var _bank := 0
## Points per second alive in the sandbox, and points per coin.
const POINTS_PER_SEC := 3.0
const POINTS_PER_COIN := 20


func setup(root: FlightRoot) -> void:
	_root = root
	_level = Session.pending_level.duplicate(true)


func _ready() -> void:
	layer = 20
	# Runs while the game is paused: it is the pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = Control.new()
	_top.name = "Top"
	_top.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_home = SlabButton.new()
	_home.name = "Home"
	_home.text = "MAP" if not _level.is_empty() else "HOME"
	_home.font_size = 20
	_home.fill = GraffitiStyle.VIOLET
	_home.skew = 10.0
	_home.custom_minimum_size = Vector2(96, 52)
	_home.size = Vector2(96, 52)
	_home.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_home.position = Vector2(14, _top.get_viewport_rect().size.y - 70)
	_home.pressed.connect(toggle_pause)
	_top.add_child(_home)
	get_viewport().size_changed.connect(_place_home)
	_place_home()
	_prewarm()
	if not _level.is_empty():
		_intro()
		_root.scenarios.changed.connect(_on_scenario_changed)
		get_tree().create_timer(START_DELAY, false, false, true).timeout.connect(_start_level)
		_show_banner()


## Draw every blast look once in front of the camera, under the loading card
## that is still up, so the first kill doesn't stall compiling them.
func _prewarm() -> void:
	for i in 2:
		await get_tree().process_frame
	var cam := _root.camera_node()
	if cam == null or not is_instance_valid(_root):
		return
	CartoonBlast.prewarm(_root, cam.global_position - cam.global_basis.z * 60.0)


## The opening shot, and a sheet over the HUD so no button fires under it.
func _intro() -> void:
	if _root.camera_rig == null:
		return
	_root.camera_rig.start_intro(INTRO_TIME)
	var block := Control.new()
	block.name = "IntroBlock"
	block.set_anchors_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.add_child(block)
	_top.move_child(block, 0)
	get_tree().create_timer(INTRO_TIME, false, false, true).timeout.connect(block.queue_free)


func _place_home() -> void:
	var vp := _top.get_viewport_rect().size
	_home.position = Vector2(14, vp.y - 70)


## Start (or restart) the level's scenario: the flight preset under its id,
## with the level's overrides on top.
func _start_level() -> void:
	if not is_instance_valid(_root) or _root.scenarios == null:
		return
	var cfg := FlightScenarios.preset(String(_level.get("preset", "duel")))
	cfg.merge(_level.get("overrides", {}) as Dictionary, true)
	_attempts += 1
	_started = true
	_state_seen = -1
	_root.scenarios.start(cfg)
	if _attempts == 1:
		_show_guarded.call_deferred()


## [param ship]'s size as the kill cam reads a wreck's (its view's box is
## unscaled, so times the hull's scale), for framing it.
static func ship_radius(ship: AiShip) -> float:
	if ship == null or ship._view == null:
		return 30.0
	return maxf(ship._view.aabb.size.length() * 0.5 * maxf(ship.scale_multiplier, 1.0), 12.0)


## An escort: a short look at the ship to guard, so the player knows which
## one it is, then back to their own ship. First try only.
func _show_guarded() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_root) or _root.camera_rig == null:
		return
	var guarded := _root.scenarios.guarded_ship()
	if guarded == null:
		return
	if _root.camera_rig.show_ship(guarded, ship_radius(guarded), 1.6, 1.0, 1.0):
		_root.announce("PROTECT THIS SHIP!")


func _on_scenario_changed() -> void:
	var sc := _root.scenarios
	if sc == null or not _started:
		return
	var st := sc.state
	if st == _state_seen:
		return
	_state_seen = st
	if st != FlightScenarios.State.WON and st != FlightScenarios.State.LOST:
		return
	# A "win" in the first moments is a scenario that never really started
	# (see FlightScenarios' empty-wave guard); never pay for one.
	if st == FlightScenarios.State.WON and sc.elapsed < 1.5:
		return
	var run := {
		"won": st == FlightScenarios.State.WON,
		"time": sc.elapsed,
		"kills": sc.kills,
		"hull": clampf(_root.player_hp / maxf(_root.player_max_hp, 1.0), 0.0, 1.0) if not _root.is_player_dead() else 0.0,
		"reason": sc.lose_reason,
		"guard": sc.guard_hull(),
		# The player's own share of the kills: the fight star.
		"fight": maxf(sc.kill_share(), 0.0),
	}
	_keep_best(run)
	# Flight school: the lesson finishes before the card.
	var lesson := _root.tutorial
	if bool(_level.get("tutorial", false)) and lesson != null and is_instance_valid(lesson):
		await lesson.finished
	get_tree().create_timer(CARD_DELAY).timeout.connect(_show_card.bind(run))


## A win beats a loss; between wins, the faster one; kills add up across tries.
func _keep_best(run: Dictionary) -> void:
	var kills := int(_best.get("kills", 0)) + int(run["kills"])
	if _best.is_empty() or (bool(run["won"]) and not bool(_best["won"])) \
			or (bool(run["won"]) and float(run["time"]) < float(_best["time"])):
		_best = run.duplicate()
	_best["kills"] = kills


func _result() -> Dictionary:
	var r := {"key": String(_level.get("key", "")), "won": false, "time": 0.0, "kills": 0,
		"hull": 0.0, "attempts": maxi(_attempts, 1)}
	r.merge(_best, true)
	return r


# --- Pause and leaving ----------------------------------------------------------

## Pause (or resume). With the end card up there is nothing to pause: MAP
## there leaves.
func toggle_pause() -> void:
	if _card != null:
		return
	if _pause != null and is_instance_valid(_pause):
		_resume()
	else:
		_show_pause()


func is_paused() -> bool:
	return _pause != null and is_instance_valid(_pause)


func _unhandled_input(event: InputEvent) -> void:
	# The flight scene's own Escape handling is paused with it: resume here.
	if is_paused() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_resume()


func _resume() -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.queue_free()
	_pause = null
	get_tree().paused = false
	_home.visible = true


## Back to the menu. [param open] "map" opens the campaign map (sandbox);
## [param next_key] flies that level next (NEXT on a win card).
func _leave(open := "", next_key := "") -> void:
	get_tree().paused = false
	if not _level.is_empty():
		Session.level_result = _result()
		if next_key != "":
			Session.level_result["go_next"] = next_key
	else:
		Session.level_result = {"key": "sandbox", "coins": _bank, "open": open}
	Session.pending_level = {}
	if _root.scenarios != null:
		_root.scenarios.stop(false)
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("menu"))


func _retry() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	var mid_run := is_paused() and _root.scenarios.is_running()
	_resume()
	if mid_run:
		# Restarting mid-run counts the try that was going.
		_root.scenarios.stop(false)
	_root.revive_player()
	_show_banner()
	get_tree().create_timer(0.6).timeout.connect(_start_level)


# --- Pieces -------------------------------------------------------------------

func _show_banner() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	var vp := _top.get_viewport_rect().size
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top.add_child(_banner)
	var lvl := GraffitiStyle.label("LEVEL %d" % int(_level.get("number", 1)), GraffitiStyle.fit(30, vp), GraffitiStyle.SUN)
	var name := Label.new()
	name.text = String(_level.get("title", "")).to_upper()
	name.add_theme_font_override("font", GraffitiStyle.number_font())
	name.add_theme_font_size_override("font_size", GraffitiStyle.fit(76, vp))
	name.add_theme_color_override("font_color", GraffitiStyle.LIME)
	name.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	name.add_theme_constant_override("outline_size", 14)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lvl)
	box.add_child(name)
	_banner.add_child(box)
	_banner.pivot_offset = vp * 0.5
	_banner.scale = Vector2(1.8, 1.8)
	_banner.modulate.a = 0.0
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.3)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.35)
	tw.tween_callback(_banner.queue_free)


## The pause card: PAUSED, the level and what to do in it (its brief, the
## clock if it has one), then RESUME, RETRY and MAP. The game is stopped
## under it ([member SceneTree.paused]).
func _show_pause() -> void:
	get_tree().paused = true
	_home.visible = false
	var vp := _top.get_viewport_rect().size
	_pause = _dim_layer()
	var card := _PauseCard.new()
	card.level = _level
	card.clock = _root.scenarios.time_left() if _root.scenarios != null else -1.0
	var u := clampf(minf(vp.x, vp.y) / 720.0, 0.7, 1.6)
	card.custom_minimum_size = Vector2(minf(vp.x - 32.0, 620.0 * u), 250.0 * u if not _level.is_empty() else 150.0 * u)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(22 * u))
	box.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(18 * u))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bw := minf((vp.x - 64.0) / (3.0 if not _level.is_empty() else 2.0), 200.0 * u)
	var go := _slab("RESUME", GraffitiStyle.LIME)
	go.text_color = GraffitiStyle.INK
	go.custom_minimum_size = Vector2(bw, 64 * u)
	go.pressed.connect(_resume)
	row.add_child(go)
	if not _level.is_empty():
		var again := _slab("RETRY", GraffitiStyle.SUN)
		again.text_color = GraffitiStyle.INK
		again.custom_minimum_size = Vector2(bw, 64 * u)
		again.pressed.connect(_retry)
		row.add_child(again)
	var out := _slab("MAP" if not _level.is_empty() else "HOME", GraffitiStyle.HOT)
	out.custom_minimum_size = Vector2(bw, 64 * u)
	out.pressed.connect(_leave)
	row.add_child(out)
	box.add_child(row)
	_center(_pause, box)
	box.pivot_offset = box.get_combined_minimum_size() * 0.5
	box.scale = Vector2(0.85, 0.85)
	box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	go.grab_focus()


## PAUSED on a slanted slab; for a level, its number and name, its word and
## the brief under it, and the clock left.
class _PauseCard:
	extends Control
	var level := {}
	var clock := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var u := size.y / (250.0 if not level.is_empty() else 150.0)
		GraffitiStyle.draw_slab(self, r, GraffitiStyle.PAPER, 22.0 * u, 4.0, Vector2(9, 11) * u)
		GraffitiStyle.draw_halftone(self, r.grow(-8), Color(0, 0, 0, 0.07), 11.0 * u, false, 22.0 * u)
		var tf := GraffitiStyle.title_font()
		var ink := GraffitiStyle.INK
		if level.is_empty():
			GraffitiStyle.draw_text(self, "PAUSED", size * 0.5, int(64 * u), GraffitiStyle.VIOLET, int(10 * u), tf)
			return
		GraffitiStyle.draw_text(self, "PAUSED", Vector2(size.x * 0.5, size.y * 0.2), int(54 * u), GraffitiStyle.VIOLET, int(9 * u), tf)
		var head := "LEVEL %d: %s" % [int(level.get("number", 1)), String(level.get("title", "")).to_upper()]
		GraffitiStyle.draw_text(self, head, Vector2(size.x * 0.5, size.y * 0.44), int(30 * u), ink, 0, GraffitiStyle.number_font())
		var word := String(level.get("word", ""))
		var brief := String(level.get("brief", "")).to_upper()
		if word != "":
			GraffitiStyle.draw_text(self, word, Vector2(size.x * 0.5, size.y * 0.62), int(30 * u), GraffitiStyle.HOT, int(5 * u), GraffitiStyle.head_font())
		if brief != "":
			GraffitiStyle.draw_text(self, brief, Vector2(size.x * 0.5, size.y * 0.79), int(24 * u), ink, 0)
		if clock >= 0.0:
			GraffitiStyle.draw_text(self, "CLOCK " + FlightScenarios.clock_text(clock), Vector2(size.x * 0.5, size.y * 0.93), int(20 * u), GraffitiStyle.VIOLET, 0)


func _show_card(run: Dictionary) -> void:
	if not is_instance_valid(_root) or _card != null:
		return
	var won := bool(run["won"])
	_card = _dim_layer()
	# The fanfare swells in; the trombone just plays.
	if won:
		GameAudio.ui(&"win", 0.0, 0.8)
	else:
		GameAudio.ui(&"lose", 0.0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	var head := Label.new()
	# A loss says why, in a word or three: WRECKED, ESCORT DESTROYED, OUT OF TIME.
	var reason := String(run.get("reason", ""))
	head.text = "YEET!" if won else (reason if reason != "" else "WRECKED")
	head.add_theme_font_override("font", GraffitiStyle.title_font())
	head.add_theme_font_size_override("font_size", _head_size(head.text, 96 if head.text.length() <= 8 else 72))
	head.add_theme_color_override("font_color", GraffitiStyle.LIME if won else GraffitiStyle.HOT)
	head.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	head.add_theme_constant_override("outline_size", 16)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var stars := StarPopRow.new()
	stars.count = _stars_for(run) if won else 0
	stars.custom_minimum_size = Vector2(260, 70)
	box.add_child(stars)
	var facts := GraffitiStyle.label("TIME %ds    WRECKS %d" % [roundi(float(run["time"])), int(run["kills"])], 32)
	facts.add_theme_font_override("font", GraffitiStyle.number_font())
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(facts)
	# What this level's stars were for, so the next try knows what to chase.
	var focus := StarRating.focus_words(_level.get("grade", {}))
	if focus != "":
		var fl := GraffitiStyle.label(focus, 24, GraffitiStyle.SUN)
		fl.add_theme_font_override("font", GraffitiStyle.tip_font())
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(fl)
	var row := _button_row()
	var again := _slab("RETRY" if not won else "AGAIN", GraffitiStyle.SUN)
	again.text_color = GraffitiStyle.INK
	again.pressed.connect(_retry)
	var map := _slab("MAP", GraffitiStyle.HOT)
	map.pressed.connect(_leave)
	# A win that leaves a branch to pick: NEXT is the map, where it is picked.
	var branch_pending := won and bool(_level.get("ends_road", false))
	var next_key := _next_key(run) if won and not branch_pending else ""
	var next: SlabButton = null
	if branch_pending:
		next = _slab("NEXT", GraffitiStyle.LIME)
		next.text_color = GraffitiStyle.INK
		next.pressed.connect(_leave)
		row.add_child(next)
	else:
		row.add_child(again)
		row.add_child(map)
	if next_key != "":
		next = _slab("NEXT", GraffitiStyle.LIME)
		next.text_color = GraffitiStyle.INK
		next.pressed.connect(_leave.bind("", next_key))
		row.add_child(next)
	box.add_child(row)
	_center(_card, box)
	_pop_in(box)
	(next if next != null else (map if won else again)).grab_focus()


## The level NEXT goes to after this win: the first not-yet-won level that
## is open now or that this win opens, with the stars it asks for in hand
## (counting the ones this run earned), or "".
func _next_key(run: Dictionary) -> String:
	var here := int(_level.get("stars_here", 0))
	var stars := int(_level.get("stars_now", 0)) - here + maxi(here, _stars_for(run))
	for c: Dictionary in _level.get("next", []):
		if int(c.get("stars_req", 0)) <= stars:
			return String(c["key"])
	return ""


# --- Sandbox --------------------------------------------------------------------

func _process(delta: float) -> void:
	if _level.is_empty() and not get_tree().paused and is_instance_valid(_root) and not _root.is_player_dead():
		_life_t += delta


## The player's ship just went down (after the slow-mo beat). A level's own
## end card handles it there; the sandbox shows its points card.
func player_wrecked() -> void:
	if not _level.is_empty() or _card != null:
		return
	var points := _root.score + int(_life_t * POINTS_PER_SEC)
	var coins := points / POINTS_PER_COIN
	_bank += coins
	_card = _dim_layer()
	GameAudio.ui(&"lose", 0.0)
	_home.visible = false
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	var head := Label.new()
	head.text = "WRECKED"
	head.add_theme_font_override("font", GraffitiStyle.title_font())
	head.add_theme_font_size_override("font_size", _head_size(head.text, 96))
	head.add_theme_color_override("font_color", GraffitiStyle.HOT)
	head.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	head.add_theme_constant_override("outline_size", 16)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var tally := _Tally.new()
	tally.points = points
	tally.coins = coins
	tally.custom_minimum_size = Vector2(420, 150)
	box.add_child(tally)
	var row := _button_row()
	var again := _slab("RETRY", GraffitiStyle.SUN)
	again.text_color = GraffitiStyle.INK
	again.custom_minimum_size = Vector2(190, 70)
	again.pressed.connect(_sandbox_retry)
	var map := _slab("MAP", GraffitiStyle.CYAN)
	map.text_color = GraffitiStyle.INK
	map.custom_minimum_size = Vector2(170, 70)
	map.pressed.connect(_leave.bind("map"))
	var home := _slab("HOME", GraffitiStyle.HOT)
	home.custom_minimum_size = Vector2(170, 70)
	home.pressed.connect(_leave.bind("home"))
	row.add_child(again)
	row.add_child(map)
	row.add_child(home)
	box.add_child(row)
	_center(_card, box)
	_pop_in(box)
	again.grab_focus()


func _sandbox_retry() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	_home.visible = true
	_root.score = 0
	_life_t = 0.0
	_root.respawn_player_ship()


## POINTS counting up in Orange Juice, then the coins they make popping in.
## Wall-clock timed: the wreck may still be in slow motion.
class _Tally:
	extends Control
	var points := 0
	var coins := 0
	var _start := Time.get_ticks_msec()
	var _ticked := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := (Time.get_ticks_msec() - _start) / 1000.0
		var nf := GraffitiStyle.number_font()
		var k := clampf(t / 1.2, 0.0, 1.0)
		var shown := int(round(points * ease(k, 0.4)))
		GraffitiStyle.draw_text(self, "POINTS", Vector2(size.x * 0.5, size.y * 0.14), 26, GraffitiStyle.PAPER, 5)
		GraffitiStyle.draw_text(self, str(shown), Vector2(size.x * 0.5, size.y * 0.45), 64, GraffitiStyle.SUN, 10, nf)
		if t > 1.35:
			var pop := clampf((t - 1.35) / 0.25, 0.0, 1.0)
			if not _ticked:
				_ticked = true
				Juice.haptic(Juice.HapticKind.LIGHT)
				GameAudio.ui(&"coin")
			var s := int(40 * lerpf(1.6, 1.0, ease(pop, 0.5)))
			GraffitiIcons.draw(self, "coin", Vector2(size.x * 0.5 - 70, size.y * 0.82), 44)
			GraffitiStyle.draw_text(self, "+%d" % coins, Vector2(size.x * 0.5 + 20, size.y * 0.82), s, GraffitiStyle.LIME, 8, nf)
		if t > 2.2:
			set_process(false)


## The same star rule the campaign pays by ([StarRating], with the level's own
## grading): hull left, speed against par, the guarded ship's hull.
func _stars_for(run: Dictionary) -> int:
	var r := run.duplicate()
	r["won"] = true
	return StarRating.stars(_level.get("grade", {}), float(_level.get("par", 0.0)), r)


func _dim_layer() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.add_child(dim)
	return dim


## The end card's buttons: side by side, or stacked on a portrait screen
## (three slabs in a row are wider than a phone held upright).
func _button_row() -> BoxContainer:
	var row := BoxContainer.new()
	row.vertical = _portrait()
	row.add_theme_constant_override("separation", 14 if row.vertical else 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


## A headline's type size: [param base], or smaller so it fits across the
## screen (the spray face's swashes draw past its measured width).
func _head_size(text: String, base: int) -> int:
	var w := GraffitiStyle.title_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x * 1.25 + 32.0
	var room := _top.get_viewport_rect().size.x - 40.0
	return clampi(int(100.0 * room / maxf(w, 1.0)), 36, base)


func _portrait() -> bool:
	var vp := _top.get_viewport_rect().size
	return vp.y > vp.x


## Pop a centred card in, to a scale that fits it on screen (a 96 pt
## headline is wider than a phone held upright).
func _pop_in(box: Control) -> void:
	var vp := _top.get_viewport_rect().size
	var need := box.get_combined_minimum_size()
	var k := minf(1.0, minf((vp.x - 24.0) / maxf(need.x, 1.0), (vp.y - 24.0) / maxf(need.y, 1.0)))
	box.pivot_offset = need * 0.5
	box.scale = Vector2.ONE * k * 0.6
	box.create_tween().tween_property(box, "scale", Vector2.ONE * k, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _center(parent: Control, child: Control) -> void:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	parent.add_child(c)


func _slab(label: String, col: Color) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.fill = col
	b.custom_minimum_size = Vector2(230, 70)
	return b
