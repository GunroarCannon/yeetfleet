## The AI test arena's spectator HUD: a roster to focus or pilot ships, a spawn
## panel to build test squads, and a ☰ menu for navigation. Deliberately small —
## the arena is a viewing platform, not a cockpit, so there are no flight
## controls; the whole screen stays clear for watching the fight.
class_name ArenaHud
extends Control

const MENU_BACK_FLIGHT := 1
const MENU_BACK_HANGAR := 2
const MENU_RESTART := 3
const MENU_KILL_ALL := 4
const MENU_ROSTER := 5
const MENU_SPAWN := 6

var _root: ArenaRoot

var _menu_button: MenuButton
var _hint_label: Label
var _roster_panel: VBoxContainer = null
var _roster_rows: VBoxContainer = null
var _roster_timer := 0.0
var _spawn_panel: VBoxContainer = null
var _spawn_behavior := 0
var _spawn_formation := 0
var _spawn_count := 3
var _spawn_team := 1


func _ready() -> void:
	_root = owner as ArenaRoot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The HUD must keep running when the game is paused (menu) so the menu
	# button still works.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	_build_top_bar()
	_build_roster()
	_build_spawn_panel()


func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = BuilderTheme.PAD
	bar.offset_right = -BuilderTheme.PAD
	bar.offset_top = BuilderTheme.PAD
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_menu_button = MenuButton.new()
	_menu_button.text = "☰"
	_menu_button.flat = false
	_menu_button.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN, BuilderTheme.TOUCH_MIN)
	_menu_button.tooltip_text = "Arena menu"
	var popup := _menu_button.get_popup()
	popup.id_pressed.connect(_on_menu)
	popup.about_to_popup.connect(_refill_menu)
	_refill_menu()
	bar.add_child(_menu_button)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	bar.add_child(_hint_label)


# --- Menu -------------------------------------------------------------------

func _refill_menu() -> void:
	var popup := _menu_button.get_popup()
	popup.clear()
	popup.add_check_item("Ship roster", MENU_ROSTER)
	popup.set_item_checked(popup.get_item_index(MENU_ROSTER), _roster_panel != null and _roster_panel.visible)
	popup.add_item("Spawn ships…", MENU_SPAWN)
	popup.add_separator()
	popup.add_item("Restart fight (F5)", MENU_RESTART)
	popup.add_item("Kill all AI", MENU_KILL_ALL)
	popup.add_separator()
	popup.add_item("Back to flight (Esc)", MENU_BACK_FLIGHT)
	popup.add_item("Back to the hangar", MENU_BACK_HANGAR)


func _on_menu(id: int) -> void:
	match id:
		MENU_BACK_FLIGHT: _root.back_to_flight()
		MENU_BACK_HANGAR: _root.back_to_hangar()
		MENU_RESTART: _root.restart_fight()
		MENU_KILL_ALL: _root.kill_all()
		MENU_ROSTER: _toggle_roster()
		MENU_SPAWN: _toggle_spawn_panel()


# --- Roster -----------------------------------------------------------------

func _toggle_roster() -> void:
	if _roster_panel == null:
		_build_roster()
	if _roster_panel != null:
		_roster_panel.visible = not _roster_panel.visible
		if _roster_panel.visible:
			_refresh_roster()


func _build_roster() -> void:
	_roster_panel = VBoxContainer.new()
	_roster_panel.name = "Roster"
	_roster_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_roster_panel.offset_right = -BuilderTheme.PAD
	_roster_panel.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_roster_panel.offset_left = -340.0
	_roster_panel.offset_bottom = 480.0
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_roster_panel.visible = false
	add_child(_roster_panel)

	var title := Label.new()
	title.text = "SHIPS"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", BuilderTheme.warn())
	_roster_panel.add_child(title)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var back := Button.new()
	back.text = "Back to pan"
	back.add_theme_font_size_override("font_size", 11)
	back.custom_minimum_size = Vector2(0, 24)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: _root.camera_rig.set_focus(null))
	head.add_child(back)
	var big := Button.new()
	big.text = "Bigger view"
	big.add_theme_font_size_override("font_size", 11)
	big.custom_minimum_size = Vector2(0, 24)
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.pressed.connect(func() -> void: _root.restart_big())
	head.add_child(big)
	_roster_panel.add_child(head)

	var leave := Button.new()
	leave.text = "Leave control (L)"
	leave.add_theme_font_size_override("font_size", 11)
	leave.custom_minimum_size = Vector2(0, 24)
	leave.pressed.connect(func() -> void: _root.leave_control())
	_roster_panel.add_child(leave)

	_roster_rows = VBoxContainer.new()
	_roster_panel.add_child(_roster_rows)


func _refresh_roster() -> void:
	if _roster_panel == null or _roster_rows == null or _root._ai_spawner == null:
		return
	for child in _roster_rows.get_children():
		child.queue_free()
	var ships := _root._ai_spawner.ship_snapshot()
	if ships.is_empty():
		var none := Label.new()
		none.text = "no ships"
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", BuilderTheme.text_dim())
		_roster_rows.add_child(none)
		return
	for s in ships:
		_roster_rows.add_child(_roster_row(s))


func _roster_row(s: Dictionary) -> Control:
	var ship := s["node"] as AiShip
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 42)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var name_lbl := Label.new()
	name_lbl.text = "%s" % String(s["name"])
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", _team_color(int(s["team"])))
	name_lbl.custom_minimum_size = Vector2(130, 0)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)
	var hp_lbl := Label.new()
	hp_lbl.text = "%d/%d" % [int(s["hp"]), int(s["max_hp"])]
	hp_lbl.add_theme_font_size_override("font_size", 10)
	hp_lbl.custom_minimum_size = Vector2(50, 0)
	top.add_child(hp_lbl)
	var focus := Button.new()
	focus.text = "Focus"
	focus.add_theme_font_size_override("font_size", 10)
	focus.custom_minimum_size = Vector2(0, 22)
	focus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus.pressed.connect(func() -> void: _root.camera_rig.set_focus(ship))
	top.add_child(focus)
	var take := Button.new()
	take.text = "Take"
	take.add_theme_font_size_override("font_size", 10)
	take.custom_minimum_size = Vector2(0, 22)
	take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take.pressed.connect(func() -> void: _root.take_control(ship))
	top.add_child(take)
	box.add_child(top)

	var aggro_lbl := Label.new()
	var aggro_short: Array[String] = []
	for t in s["aggro"]:
		aggro_short.append(_team_short(int(t)))
	aggro_lbl.text = "aggro: " + ("/" .join(aggro_short) if not aggro_short.is_empty() else "—")
	aggro_lbl.add_theme_font_size_override("font_size", 9)
	aggro_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	box.add_child(aggro_lbl)
	return box


func _team_color(team: int) -> Color:
	match team:
		1: return Color("ff5c5c")
		2: return Color("5c9cff")
		3: return Color("5cff7a")
		4: return Color("ffd24a")
		_: return Color("9aa0aa")


func _team_short(team: int) -> String:
	match team:
		1: return "Red"
		2: return "Blue"
		3: return "Green"
		4: return "Gold"
		_: return "None"


# --- Spawn panel -------------------------------------------------------------

func _toggle_spawn_panel() -> void:
	if _spawn_panel == null:
		_build_spawn_panel()
	if _spawn_panel != null:
		_spawn_panel.visible = not _spawn_panel.visible


func _build_spawn_panel() -> void:
	_spawn_panel = VBoxContainer.new()
	_spawn_panel.name = "SpawnPanel"
	_spawn_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_spawn_panel.offset_left = BuilderTheme.PAD
	_spawn_panel.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_spawn_panel.offset_right = 250.0
	_spawn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_spawn_panel.visible = false
	add_child(_spawn_panel)

	var title := Label.new()
	title.text = "SPAWN SHIPS"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", BuilderTheme.warn())
	_spawn_panel.add_child(title)

	_spawn_behavior = _add_spawn_option(
		"Behaviour",
		["Hunt", "Patrol", "Boid swarm", "Flee", "Guard"],
		_spawn_behavior,
		func(idx: int) -> void: _spawn_behavior = idx
	)
	_spawn_formation = _add_spawn_option(
		"Formation",
		["Scatter", "V-formation", "Line", "Sphere", "Trail"],
		_spawn_formation,
		func(idx: int) -> void: _spawn_formation = idx
	)
	_spawn_team = _add_spawn_option(
		"Team",
		["None", "Red", "Blue", "Green", "Gold"],
		_spawn_team,
		func(idx: int) -> void: _spawn_team = idx
	)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	var size_lbl := Label.new()
	size_lbl.text = "Group size"
	size_lbl.custom_minimum_size = Vector2(110, 0)
	size_lbl.add_theme_font_size_override("font_size", 11)
	size_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	size_row.add_child(size_lbl)
	var size_slider := HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = 8
	size_slider.step = 1
	size_slider.value = _spawn_count
	size_slider.custom_minimum_size = Vector2(100, 24)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_slider)
	var size_val := Label.new()
	size_val.text = str(_spawn_count)
	size_val.custom_minimum_size = Vector2(24, 0)
	size_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_val.add_theme_font_size_override("font_size", 11)
	size_row.add_child(size_val)
	size_slider.value_changed.connect(func(v: float) -> void: size_val.text = str(int(v)))
	size_slider.value_changed.connect(func(v: float) -> void: _spawn_count = int(v))
	_spawn_panel.add_child(size_row)

	var btn := Button.new()
	btn.text = "Spawn group"
	btn.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	btn.pressed.connect(_on_spawn_pressed)
	_spawn_panel.add_child(btn)


func _add_spawn_option(label: String, choices: Array, initial: int, setter: Callable) -> int:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(120, BuilderTheme.TOUCH_MIN - 12)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in choices:
		opt.add_item(String(c))
	opt.select(initial)
	opt.item_selected.connect(func(idx: int) -> void: setter.call(idx))
	row.add_child(opt)
	_spawn_panel.add_child(row)
	return initial


func _on_spawn_pressed() -> void:
	if _root._ai_spawner == null:
		return
	var forms := [
		AiGroupBehaviour.FormationShape.SCATTER,
		AiGroupBehaviour.FormationShape.V_FORM,
		AiGroupBehaviour.FormationShape.LINE,
		AiGroupBehaviour.FormationShape.SPHERE,
		AiGroupBehaviour.FormationShape.TRAIL,
	]
	var arch := AiFactions.custom(_spawn_behavior, forms[_spawn_formation], _spawn_count)
	_root._ai_spawner.spawn_group_with(arch, _spawn_count, _spawn_team)
	var names: Array[String] = ["Hunt", "Patrol", "Swarm", "Flee", "Guard"]
	var form_names: Array[String] = ["scatter", "V", "line", "sphere", "trail"]
	show_hint("Spawned %d %s (%s formation, team %s)" % [
		_spawn_count, names[_spawn_behavior], form_names[_spawn_formation], _team_short(_spawn_team)
	])


# --- Per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if _roster_panel != null and _roster_panel.visible:
		_roster_timer -= delta
		if _roster_timer <= 0.0:
			_roster_timer = 0.5
			_refresh_roster()


func show_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
