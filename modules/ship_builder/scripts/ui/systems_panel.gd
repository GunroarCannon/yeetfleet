## The systems test rig: throttle, trigger, capacitor, heat.
##
## Everything above this panel answers "does it look right". This one answers "does
## it work". Holding the trigger fires the guns that are actually fitted, at their
## own rates, from their own muzzles, spending real capacitor charge — so an
## over-gunned build browns out here rather than in the flight module three weeks
## from now.
class_name SystemsPanel
extends VBoxContainer

var _root: BuilderRoot
var _systems: SystemsSim

var _energy_bar: ProgressBar
var _heat_bar: ProgressBar
var _energy_value: Label
var _heat_value: Label
var _note: Label
var _summary: Label
var _fire_button: Button
var _throttle: HSlider


func _ready() -> void:
	_root = owner as BuilderRoot
	_systems = %Systems as SystemsSim
	_build_ui()
	_systems.state_changed.connect(_on_state_changed)
	_systems.fire_blocked.connect(_on_fire_blocked)
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: _refresh_summary())


func _build_ui() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "SYSTEMS TEST"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", BuilderTheme.text_dim())
	header.add_child(title)
	var run_toggle := CheckButton.new()
	run_toggle.text = "Live"
	run_toggle.button_pressed = true
	run_toggle.add_theme_font_size_override("font_size", 11)
	run_toggle.tooltip_text = "Pause the simulation to inspect a frozen ship"
	run_toggle.toggled.connect(func(on: bool) -> void:
		_systems.running = on
		if not on:
			_systems.stop_all()
			_fire_button.button_pressed = false
	)
	header.add_child(run_toggle)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 10)
	_summary.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	add_child(_make_gauge("Capacitor", true))
	add_child(_make_gauge("Heat", false))

	var throttle_row := HBoxContainer.new()
	add_child(throttle_row)
	var throttle_label := Label.new()
	throttle_label.text = "Throttle"
	throttle_label.custom_minimum_size.x = 62
	throttle_label.add_theme_font_size_override("font_size", 11)
	throttle_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	throttle_row.add_child(throttle_label)
	_throttle = HSlider.new()
	_throttle.min_value = 0.0
	_throttle.max_value = 1.0
	_throttle.step = 0.01
	_throttle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_throttle.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 16
	_throttle.tooltip_text = "Spool the engines that are fitted; plumes grow and heat rises"
	_throttle.value_changed.connect(func(v: float) -> void: _systems.set_throttle(v))
	throttle_row.add_child(_throttle)

	_fire_button = Button.new()
	_fire_button.text = "Hold to fire"
	_fire_button.toggle_mode = true
	_fire_button.custom_minimum_size.y = BuilderTheme.TOUCH_MIN
	_fire_button.tooltip_text = "Fire every fitted weapon. Toggling works on touch; hold works with a mouse."
	_fire_button.toggled.connect(func(on: bool) -> void: _systems.set_firing(on))
	add_child(_fire_button)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	_note.add_theme_color_override("font_color", BuilderTheme.warn())
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)

	_refresh_summary()


func _make_gauge(label_text: String, is_energy: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 62
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(40, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var value := Label.new()
	value.custom_minimum_size.x = 46
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 11)
	row.add_child(value)
	if is_energy:
		_energy_bar = bar
		_energy_value = value
	else:
		_heat_bar = bar
		_heat_value = value
	return row


func _on_state_changed(energy_fraction: float, heat_fraction: float, notes: String) -> void:
	_energy_bar.value = energy_fraction
	_energy_bar.add_theme_stylebox_override(
		"fill", BuilderTheme.flat(BuilderTheme.gauge_color(energy_fraction), Color.TRANSPARENT, 2, 0)
	)
	_energy_value.text = "%d%%" % roundi(energy_fraction * 100.0)
	_heat_bar.value = heat_fraction
	# Heat is inverted: a full bar is bad, so the gauge colour is fed 1 - fraction.
	_heat_bar.add_theme_stylebox_override(
		"fill", BuilderTheme.flat(BuilderTheme.gauge_color(1.0 - heat_fraction), Color.TRANSPARENT, 2, 0)
	)
	_heat_value.text = "%d%%" % roundi(heat_fraction * 100.0)
	_note.text = notes
	_note.visible = notes != ""


func _on_fire_blocked(reason: String) -> void:
	_note.text = reason
	_note.visible = reason != ""


func _refresh_summary() -> void:
	_summary.text = _systems.describe()
	var has_guns := _root.view != null and not _root.view.muzzles.is_empty()
	_fire_button.disabled = not has_guns
	_fire_button.text = "Hold to fire" if has_guns else "No weapons fitted"
	var has_engines := _root.view != null and not _root.view.exhausts.is_empty()
	_throttle.editable = has_engines
	if not has_engines:
		_throttle.value = 0.0
