## PerformancePanel: the ⚡ Performance chip's panel. Frame pacing, motion
## smoothing, resolution, anti-aliasing, lighting cost, and how much the world
## is allowed to spawn.
##
## Every row writes through [PerformanceSettings] (saved on change, restored
## on launch) and re-applies at once via [method FlightRoot.apply_performance].
## The presets set every dial together; "Smoothest" is everything at its
## cheapest.
class_name PerformancePanel
extends PanelContainer

var _root: FlightRoot = null
var _vbox: VBoxContainer = null


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	custom_minimum_size = Vector2(440.0, 540.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.94)
	sb.border_color = Color("ffd24a", 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0.9, 0.7, 0.1, 0.2)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_vbox)
	_build_rows()


## Rebuilt from scratch after a preset, so every row shows its new value.
## Deferred: the preset button that asked for it is itself one of the nodes
## being freed.
func _rebuild() -> void:
	for c in _vbox.get_children():
		c.queue_free()
	_build_rows()


func _build_rows() -> void:
	PerformanceSettings.ensure_loaded()
	var header := HBoxContainer.new()
	_vbox.add_child(header)
	var title := Label.new()
	title.text = "⚡ PERFORMANCE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ffd24a"))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	_vbox.add_child(presets)
	for preset_name: String in PerformanceSettings.PRESETS:
		var b := Button.new()
		b.text = preset_name
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_preset.bind(preset_name))
		presets.add_child(b)

	_section("Smooth motion")
	_check("Physics interpolation (no 60 Hz judder)", "physics_interpolation")
	_options("Frame cap", "max_fps", [["Uncapped", 0], ["30", 30], ["60", 60], ["120", 120], ["144", 144], ["240", 240]])
	_options("V-Sync", "vsync", [["Off", 0], ["On", 1], ["Adaptive", 2]])
	_options("Physics rate", "physics_tps", [["30 Hz", 30], ["60 Hz", 60], ["120 Hz", 120], ["240 Hz", 240]])

	_section("Image")
	_slider("Render scale", "render_scale", 0.5, 1.0, 0.05, "%.0f%%", 100.0)
	_options("MSAA", "msaa", [["Off", 0], ["2×", 1], ["4×", 2], ["8×", 3]])
	_check("FXAA (cheap edge smoothing)", "fxaa")
	_slider("Mesh LOD aggressiveness", "mesh_lod", 0.25, 8.0, 0.25, "%.2f px")

	_section("Lighting")
	_options("Shadows", "shadows", [["Off", 0], ["Sun only", 1], ["All lights", 2]])
	_check("Glow / bloom", "glow")

	_section("How much the world spawns")
	_slider("Max AI ships", "max_ai_ships", 0.0, 40.0, 1.0, "%.0f")
	_slider("Effects budget", "vfx_budget", 4.0, 128.0, 1.0, "%.0f live")
	_slider("Max debris pieces", "max_debris", 10.0, 500.0, 10.0, "%.0f")
	_slider("Debris lifetime", "debris_lifetime", 0.1, 3.0, 0.1, "×%.1f")

	var note := Label.new()
	note.text = "World detail (planet quality, star/asteroid density, high-res) lives in Settings and rebuilds the scene."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_vbox.add_child(note)


func _on_preset(preset_name: String) -> void:
	PerformanceSettings.apply_preset(preset_name)
	_apply()
	_rebuild.call_deferred()


func _write(field: String, value: Variant) -> void:
	PerformanceSettings.set_value(field, value)
	_apply()


func _apply() -> void:
	if _root != null and is_instance_valid(_root):
		_root.apply_performance()


func _section(text: String) -> void:
	_vbox.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("ffe08a"))
	_vbox.add_child(label)


func _check(text: String, field: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = bool(PerformanceSettings.get_value(field))
	check.toggled.connect(func(on: bool) -> void: _write(field, on))
	_vbox.add_child(check)


func _options(text: String, field: String, choices: Array) -> void:
	var row := _row(text)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current: int = int(PerformanceSettings.get_value(field))
	for i in choices.size():
		opt.add_item(String(choices[i][0]), i)
		if int(choices[i][1]) == current:
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void: _write(field, int(choices[i][1])))
	row.add_child(opt)


func _slider(
	text: String, field: String, min_v: float, max_v: float, step: float, fmt: String,
	display_mult := 1.0
) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := float(PerformanceSettings.get_value(field))
	slider.set_value_no_signal(value)
	var value_label := Label.new()
	value_label.text = fmt % (value * display_mult)
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		_write(field, v)
		if is_instance_valid(value_label):
			value_label.text = fmt % (v * display_mult)
	)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_vbox.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170.0, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return row
