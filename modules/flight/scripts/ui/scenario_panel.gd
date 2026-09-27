## ScenarioPanel: pick a set-piece fight ([FlightScenarios]) or build a custom
## one from its dials, and start, retry or stop it. Opened from the Combat
## menu, the D debug strip, and by tapping the mobile HUD's top band.
class_name ScenarioPanel
extends PanelContainer

var _scenarios: FlightScenarios
var _status: Label
## The custom scenario being edited (a [constant FlightScenarios.DEFAULTS] copy).
var _custom: Dictionary = FlightScenarios.preset("")


func setup(scenarios: FlightScenarios) -> void:
	_scenarios = scenarios


func _ready() -> void:
	custom_minimum_size = Vector2(480.0, 460.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.95)
	sb.border_color = Color("ffcc1a", 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "⚔ SCENARIOS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("ffcc1a"))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("46ff9b"))
	outer.add_child(_status)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	outer.add_child(controls)
	_button(controls, "↺ Retry", func() -> void:
		_scenarios.restart()
		visible = false)
	_button(controls, "■ Stop — free roam", func() -> void: _scenarios.stop())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 360.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	for id: String in FlightScenarios.PRESET_ORDER:
		var p := FlightScenarios.preset(id)
		var b := Button.new()
		b.text = "%s\n%s" % [p["name"], p["desc"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0.0, 52.0)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_scenarios.start(FlightScenarios.preset(id))
			visible = false)
		vbox.add_child(b)

	vbox.add_child(HSeparator.new())
	var ctitle := Label.new()
	ctitle.text = "Custom scenario"
	ctitle.add_theme_color_override("font_color", Color("ffcc1a"))
	vbox.add_child(ctitle)
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
	_button(vbox, "▶ Start custom scenario", func() -> void:
		_scenarios.start(_custom.duplicate())
		visible = false)

	_scenarios.changed.connect(_sync_status)
	visibility_changed.connect(_sync_status)
	_sync_status()


func _sync_status() -> void:
	if _status == null or _scenarios == null:
		return
	var line := _scenarios.status_line()
	_status.text = line if line != "" else "Free roam — pick a scenario below."


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


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
