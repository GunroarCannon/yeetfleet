## CampaignLevelOverlay: the flight scene's side of a level handed over by
## the game's menu ([member Session.pending_level]).
##
## It starts the level's scenario once the scene has settled, slams the
## level's name on screen, and when the scenario ends shows a graffiti end
## card — YEET! or WRECKED, the stars, time and wrecks — with RETRY and MAP.
## Leaving writes [member Session.level_result] and goes back to the menu,
## which counts it. Sandbox flights (a ship but no level) get only the home
## button.
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
var _confirm: Control = null
var _banner: Control = null
var _started := false
var _attempts := 0
## The best finished run: `{won, time, kills, hull}`; {} until one ends.
var _best := {}
var _state_seen := -1


func setup(root: FlightRoot) -> void:
	_root = root
	_level = Session.pending_level.duplicate(true)


func _ready() -> void:
	layer = 20
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
	_home.pressed.connect(_on_home)
	_top.add_child(_home)
	get_viewport().size_changed.connect(_place_home)
	_place_home()
	if not _level.is_empty():
		_intro()
		_root.scenarios.changed.connect(_on_scenario_changed)
		get_tree().create_timer(START_DELAY, true, false, true).timeout.connect(_start_level)
		_show_banner()


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
	get_tree().create_timer(INTRO_TIME, true, false, true).timeout.connect(block.queue_free)


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
	}
	_keep_best(run)
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


# --- Leaving ------------------------------------------------------------------

func _on_home() -> void:
	# Mid-level, ask first: leaving counts as a try.
	if not _level.is_empty() and _card == null and _root.scenarios.is_running():
		_show_confirm()
		return
	_leave()


func _leave() -> void:
	if not _level.is_empty():
		Session.level_result = _result()
	Session.pending_level = {}
	if _root.scenarios != null:
		_root.scenarios.stop(false)
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("menu"))


func _retry() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
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
	name.add_theme_font_override("font", GraffitiStyle.title_font())
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


func _show_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		return
	_confirm = _dim_layer()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var q := GraffitiStyle.label("BAIL OUT?", 48, GraffitiStyle.SUN, 10)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes := _slab("MAP", GraffitiStyle.HOT)
	yes.pressed.connect(_leave)
	var no := _slab("FLY ON", GraffitiStyle.LIME)
	no.text_color = GraffitiStyle.INK
	no.pressed.connect(func() -> void:
		_confirm.queue_free()
		_confirm = null
	)
	row.add_child(no)
	row.add_child(yes)
	box.add_child(row)
	_center(_confirm, box)
	no.grab_focus()


func _show_card(run: Dictionary) -> void:
	if not is_instance_valid(_root) or _card != null:
		return
	var won := bool(run["won"])
	_card = _dim_layer()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	var head := Label.new()
	head.text = "YEET!" if won else "WRECKED"
	head.add_theme_font_override("font", GraffitiStyle.title_font())
	head.add_theme_font_size_override("font_size", 96)
	head.add_theme_color_override("font_color", GraffitiStyle.LIME if won else GraffitiStyle.HOT)
	head.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	head.add_theme_constant_override("outline_size", 16)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var stars := StarPopRow.new()
	stars.count = _stars_for(run) if won else 0
	stars.custom_minimum_size = Vector2(260, 70)
	box.add_child(stars)
	var facts := GraffitiStyle.label("TIME %ds    WRECKS %d" % [roundi(float(run["time"])), int(run["kills"])], 28)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(facts)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var again := _slab("RETRY" if not won else "AGAIN", GraffitiStyle.SUN)
	again.text_color = GraffitiStyle.INK
	again.pressed.connect(_retry)
	var map := _slab("MAP", GraffitiStyle.HOT)
	map.pressed.connect(_leave)
	row.add_child(again)
	row.add_child(map)
	box.add_child(row)
	_center(_card, box)
	box.pivot_offset = box.get_combined_minimum_size() * 0.5
	box.scale = Vector2(0.6, 0.6)
	box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	(map if won else again).grab_focus()


## The same star rule the campaign pays by (see [code]Campaign.apply_result[/code]):
## one for the win, one for half a hull left, one for beating par.
func _stars_for(run: Dictionary) -> int:
	var n := 1
	if float(run["hull"]) >= 0.5:
		n += 1
	var par := float(_level.get("par", 0.0))
	if par > 0.0 and float(run["time"]) <= par:
		n += 1
	return n


func _dim_layer() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.add_child(dim)
	return dim


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
