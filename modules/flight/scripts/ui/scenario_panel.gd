## ScenarioPanel: pick a set-piece fight ([FlightScenarios]) or build a custom
## one from its dials, and start, retry or stop it. Opened from the Combat
## menu, the D debug strip, and by tapping the mobile HUD's top band.
##
## Dressed like the game's menus ([GraffitiStyle]): an ink sheet with a hot
## rim, the title in the spray face, every choice a slanted [SlabButton] with
## its name big and one short line under — words only, no emoji.
class_name ScenarioPanel
extends PanelContainer

var _scenarios: FlightScenarios
## The flight scene, for the endless run ([EndlessRunner]); null leaves it out.
var _flight: FlightRoot = null
var _status: Label
## The custom scenario being edited (a [constant FlightScenarios.DEFAULTS] copy).
var _custom: Dictionary = FlightScenarios.preset("")


func setup(scenarios: FlightScenarios, flight: FlightRoot = null) -> void:
	_scenarios = scenarios
	_flight = flight


## The endless run, if this scene has one going: stopped before a scenario.
func _stop_run() -> void:
	if _flight != null:
		var run := _flight.get_node_or_null("EndlessRunner") as EndlessRunner
		if run != null:
			run.stop()


func _ready() -> void:
	custom_minimum_size = Vector2(500.0, 480.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GraffitiStyle.INK, 0.96)
	sb.border_color = GraffitiStyle.HOT
	sb.set_border_width_all(4)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(8, 10)
	add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := GraffitiStyle.label("SCENARIOS", 34, GraffitiStyle.SUN, 8)
	title.add_theme_font_override("font", GraffitiStyle.title_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := _slab("CLOSE", Color("3a3150"), Vector2(110.0, 44.0), 18)
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	_status = GraffitiStyle.label("", 16, GraffitiStyle.LIME, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	outer.add_child(controls)
	_button(controls, "RETRY", func() -> void:
		_stop_run()
		_scenarios.restart()
		visible = false)
	_button(controls, "STOP", func() -> void:
		_stop_run()
		_scenarios.stop())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 360.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var fights: Array[Color] = [GraffitiStyle.HOT, GraffitiStyle.ORANGE, GraffitiStyle.VIOLET]
	var jobs: Array[Color] = [GraffitiStyle.CYAN, GraffitiStyle.LIME, GraffitiStyle.SUN]
	_head(vbox, "FIGHTS")
	if _flight != null:
		var run := _choice(vbox, "ENDLESS RUN", "Dodge, thread rings, ram. It speeds up.", GraffitiStyle.SUN)
		run.pressed.connect(func() -> void:
			EndlessRunner.attach(_flight).start()
			visible = false)
	var i := 0
	for id: String in FlightScenarios.PRESET_ORDER:
		var p := FlightScenarios.preset(id)
		var b := _choice(vbox, String(p["name"]), String(p["desc"]), fights[i % fights.size()])
		i += 1
		b.pressed.connect(func() -> void:
			_stop_run()
			_scenarios.start(FlightScenarios.preset(id))
			visible = false)

	_head(vbox, "JOBS")
	i = 0
	for id: String in FlightScenarios.OBJECTIVE_ORDER:
		var p := FlightScenarios.preset(id)
		var b := _choice(vbox, String(p["name"]), String(p["desc"]), jobs[i % jobs.size()])
		i += 1
		b.pressed.connect(func() -> void:
			_stop_run()
			_scenarios.start(FlightScenarios.preset(id))
			visible = false)

	_head(vbox, "MAKE YOUR OWN")
	_pick(vbox, "Goal", ["Destroy them all", "Survive the clock"], 0, func(i: int) -> void:
		_custom["objective"] = FlightScenarios.Objective.DESTROY if i == 0 else FlightScenarios.Objective.SURVIVE)
	var arch_names: Array = FlightScenarios.FIGHTER_ARCHETYPES.keys()
	_pick(vbox, "Enemies are", arch_names, 0, func(i: int) -> void: _custom["enemy_arch"] = arch_names[i])
	_pick(vbox, "Wingmen are", arch_names, 1, func(i: int) -> void: _custom["ally_arch"] = arch_names[i])
	_slider(vbox, "Enemies", 1.0, 12.0, 1.0, "enemies", "%d")
	_slider(vbox, "Wingmen", 0.0, 8.0, 1.0, "allies", "%d")
	_slider(vbox, "Waves", 1.0, 10.0, 1.0, "waves", "%d")
	_slider(vbox, "  more per wave", 0.0, 4.0, 1.0, "wave_growth", "+%d")
	_slider(vbox, "Survive for", 20.0, 300.0, 10.0, "survive_time", "%d s")
	_slider(vbox, "Start distance", 200.0, 2000.0, 50.0, "enemy_distance", "%d m")
	_slider(vbox, "Enemy toughness", 0.2, 5.0, 0.1, "enemy_hp", "×%.1f")
	_slider(vbox, "Enemy damage", 0.0, 3.0, 0.1, "enemy_damage", "×%.1f")
	var frozen := CheckBox.new()
	frozen.text = "Enemies sit still (target practice)"
	frozen.focus_mode = Control.FOCUS_NONE
	frozen.toggled.connect(func(on: bool) -> void: _custom["frozen_enemies"] = on)
	vbox.add_child(frozen)
	_button(vbox, "START IT", func() -> void:
		_stop_run()
		_scenarios.start(_custom.duplicate())
		visible = false)

	_scenarios.changed.connect(_sync_status)
	visibility_changed.connect(_sync_status)
	_sync_status()


func _sync_status() -> void:
	if _status == null or _scenarios == null:
		return
	var line := _scenarios.status_line()
	_status.text = line if line != "" else "FREE ROAM. PICK ONE."


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := _slab(text, GraffitiStyle.SUN, Vector2(0.0, 52.0), 22)
	b.text_color = GraffitiStyle.INK
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _slab(text: String, col: Color, min_size: Vector2, fs: int) -> SlabButton:
	var b := SlabButton.new()
	b.text = text
	b.fill = col
	b.skew = 8.0
	b.font_size = fs
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b


## A section word in the spray face, a little tilted.
func _head(parent: Control, text: String) -> void:
	var l := GraffitiStyle.label(text, 26, GraffitiStyle.LIME, 6)
	l.add_theme_font_override("font", GraffitiStyle.title_font())
	parent.add_child(l)


## One pickable scenario: its name big on a slab, one short line under it.
func _choice(parent: Control, name: String, desc: String, col: Color) -> SlabButton:
	var b := _slab(name.to_upper(), col, Vector2(0.0, 72.0), 22)
	b.sub = _short(desc).to_upper()
	b.centered = false
	b.text_color = GraffitiStyle.INK if col in [GraffitiStyle.SUN, GraffitiStyle.LIME, GraffitiStyle.CYAN, GraffitiStyle.ORANGE] else Color.WHITE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


## The first sentence of [param desc], without key hints like "(T)".
static func _short(desc: String) -> String:
	var s := desc.get_slice(".", 0).strip_edges()
	var paren := s.find(" (")
	if paren >= 0:
		s = s.substr(0, paren)
	return s


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(l)
	return row


func _pick(parent: Control, text: String, items: Array, selected: int, cb: Callable) -> void:
	var row := _row(parent, text)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		ob.add_item(String(it))
	ob.select(selected)
	ob.item_selected.connect(cb)
	row.add_child(ob)


func _slider(parent: Control, text: String, lo: float, hi: float, step: float, key: String, fmt: String) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.set_value_no_signal(float(_custom[key]))
	row.add_child(s)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(56.0, 0.0)
	readout.text = _fmt(fmt, float(_custom[key]))
	row.add_child(readout)
	s.value_changed.connect(func(v: float) -> void:
		_custom[key] = int(v) if fmt.contains("%d") else v
		readout.text = _fmt(fmt, v))


static func _fmt(fmt: String, v: float) -> String:
	return fmt % (roundi(v) if fmt.contains("%d") else v)
