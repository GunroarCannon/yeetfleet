## The live stat readout: what the ship you just built actually does.
##
## The rows are built once from [method ShipStats.derived_rows] and then updated in
## place, because this panel redraws on every edit — including mid-drag, sixty times
## a second — and rebuilding thirteen rows of controls at that rate is exactly the
## kind of thing that makes a web build stutter.
##
## The delta column is the part that turns numbers into decisions: hover a part in
## the palette and every stat it would change is shown as a signed difference, so
## "is this engine worth the mass" is answered before committing.
class_name StatPanel
extends VBoxContainer

## The four figures that answer "what did that change do to my ship". The other
## nine matter, but not on every glance, and thirteen gauges on a phone screen is
## a wall of numbers nobody reads.
const HEADLINE_KEYS: Array[String] = ["top_speed", "agility", "hull_hp", "cost"]

var _root: BuilderRoot

var _detail_box: VBoxContainer
var _detail_button: Button
var _title: Label
var _verdict: Label
var _preview_label: Label
var _rows: Dictionary = {}
var _messages: VBoxContainer
var _cargo_row: HBoxContainer
var _cargo_slider: HSlider
var _cargo_value: Label
var _cargo_dragging := false
var _updating_cargo := false


func _ready() -> void:
	_root = owner as BuilderRoot
	_build_ui()
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: refresh())
	_root.preview_changed.connect(_on_preview_changed)


func _build_ui() -> void:
	var header := Label.new()
	header.text = "PERFORMANCE"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(header)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)

	_verdict = Label.new()
	_verdict.add_theme_font_size_override("font_size", 11)
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_verdict)

	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 11)
	_preview_label.add_theme_color_override("font_color", BuilderTheme.accent())
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.visible = false
	add_child(_preview_label)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	add_child(grid)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 2)
	_detail_box.visible = false

	# A throwaway stats object supplies the row skeleton, so the panel never has to
	# repeat the list of stats the model already owns. Headline rows stay up;
	# everything else is built into the drawer, hidden but live, so a preview delta
	# is already correct the moment the drawer is opened.
	for row in ShipStats.new().derived_rows():
		var target := grid if HEADLINE_KEYS.has(String(row["key"])) else _detail_box
		target.add_child(_make_row(row))

	_detail_button = Button.new()
	_detail_button.toggle_mode = true
	_detail_button.text = "Show all stats"
	_detail_button.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 12
	_detail_button.add_theme_font_size_override("font_size", 11)
	_detail_button.tooltip_text = "Shield, cargo, power, capacitor, jump, cooling, sensors, mass"
	_detail_button.toggled.connect(func(on: bool) -> void:
		_detail_box.visible = on
		_detail_button.text = "Hide extra stats" if on else "Show all stats"
	)
	add_child(_detail_button)
	add_child(_detail_box)

	_cargo_row = HBoxContainer.new()
	add_child(_cargo_row)
	var cargo_label := Label.new()
	cargo_label.text = "Cargo aboard"
	cargo_label.add_theme_font_size_override("font_size", 11)
	cargo_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_cargo_row.add_child(cargo_label)
	_cargo_slider = HSlider.new()
	_cargo_slider.min_value = 0.0
	_cargo_slider.step = 1.0
	_cargo_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cargo_slider.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 16
	_cargo_slider.tooltip_text = "Simulate a laden hold — mass affects speed, turn rate and jump range"
	_cargo_slider.value_changed.connect(func(v: float) -> void:
		if _updating_cargo:
			return
		_root.set_cargo_load(v)
	)
	_cargo_slider.drag_started.connect(func() -> void: _cargo_dragging = true)
	_cargo_slider.drag_ended.connect(func(_c: bool) -> void: _cargo_dragging = false)
	_cargo_row.add_child(_cargo_slider)
	_cargo_value = Label.new()
	_cargo_value.custom_minimum_size.x = 54
	_cargo_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cargo_value.add_theme_font_size_override("font_size", 11)
	_cargo_row.add_child(_cargo_value)

	_messages = VBoxContainer.new()
	_messages.add_theme_constant_override("separation", 2)
	add_child(_messages)


func _make_row(row: Dictionary) -> Control:
	var key := String(row["key"])
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = String(row["label"])
	label.custom_minimum_size.x = 82
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	box.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(40, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)

	var value := Label.new()
	value.custom_minimum_size.x = 66
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 11)
	box.add_child(value)

	var delta := Label.new()
	delta.custom_minimum_size.x = 62
	delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	delta.add_theme_font_size_override("font_size", 11)
	box.add_child(delta)

	_rows[key] = {"bar": bar, "value": value, "delta": delta, "label": label}
	return box


func refresh(preview: ShipStats = null, preview_label := "") -> void:
	if _root == null or _root.view == null:
		return
	var stats := _root.view.resolution.stats
	_title.text = _root.design.design_name
	_update_verdict(stats)

	_preview_label.visible = preview_label != ""
	_preview_label.text = "Preview · " + preview_label if preview_label != "" else ""

	var live := stats.to_compare_dict()
	var compare: Dictionary = preview.to_compare_dict() if preview != null else {}
	for row in stats.derived_rows():
		var key := String(row["key"])
		if not _rows.has(key):
			continue
		var refs: Dictionary = _rows[key]
		var bar := refs["bar"] as ProgressBar
		var fill := float(row["fill"])
		bar.value = fill
		bar.add_theme_stylebox_override("fill", BuilderTheme.flat(BuilderTheme.gauge_color(fill), Color.TRANSPARENT, 2, 0))
		bar.tooltip_text = "%s: %s" % [String(row["label"]), String(row["text"])]
		(refs["value"] as Label).text = String(row["text"])
		var delta_label := refs["delta"] as Label
		if compare.is_empty() or not compare.has(key):
			delta_label.text = ""
			continue
		var delta := float(compare[key]) - float(live.get(key, 0.0))
		if is_zero_approx(delta):
			delta_label.text = "—"
			delta_label.add_theme_color_override("font_color", BuilderTheme.delta_color(false, true))
			continue
		var improved := ShipStats.is_improvement(key, delta)
		# In high-contrast mode colour alone is not enough, so the direction is also
		# spelled out with an arrow.
		var arrow := ""
		if BuilderTheme.high_contrast:
			arrow = "▲ " if improved else "▼ "
		delta_label.text = arrow + ShipStats.format_delta(key, delta)
		delta_label.add_theme_color_override("font_color", BuilderTheme.delta_color(improved, false))

	_update_cargo(stats)
	_update_messages(stats)


func _update_verdict(stats: ShipStats) -> void:
	var bits: Array[String] = ["%d part(s)" % stats.part_count]
	if stats.weapon_count > 0:
		bits.append("%d gun(s)" % stats.weapon_count)
	if stats.engine_count > 0:
		bits.append("%d engine(s)" % stats.engine_count)
	if stats.is_flyable():
		_verdict.text = "Flightworthy · " + " · ".join(bits)
		_verdict.add_theme_color_override("font_color", BuilderTheme.good())
	else:
		_verdict.text = "Not flightworthy · " + " · ".join(bits)
		_verdict.add_theme_color_override("font_color", BuilderTheme.bad())


func _update_cargo(stats: ShipStats) -> void:
	var capacity := stats.get_stat("cargo_capacity")
	_cargo_row.visible = capacity > 0.0
	if capacity <= 0.0:
		return
	# Guard the write-back: setting `value` fires value_changed, which would loop
	# straight back into set_cargo_load and fight the player's drag.
	_updating_cargo = true
	_cargo_slider.max_value = capacity
	if not _cargo_dragging:
		_cargo_slider.value = minf(_root.cargo_load, capacity)
	_updating_cargo = false
	_cargo_value.text = "%.0f / %.0f t" % [_cargo_slider.value, capacity]


func _update_messages(stats: ShipStats) -> void:
	for child in _messages.get_children():
		child.queue_free()
	for text in stats.errors:
		_add_message("✗ " + text, BuilderTheme.bad())
	for text in stats.warnings:
		_add_message("! " + text, BuilderTheme.warn())
	for text in stats.notes:
		_add_message("· " + text, BuilderTheme.text_dim())
	for text in _root.view.resolution.content_errors:
		_add_message("data: " + text, BuilderTheme.bad())


func _add_message(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	_messages.add_child(label)


func _on_preview_changed(preview: ShipStats, label: String) -> void:
	refresh(preview, label)
