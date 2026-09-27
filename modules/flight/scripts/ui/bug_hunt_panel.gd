## BugHuntPanel: the 🐞 Bug hunt chip's panel — the UI over [BugHunt].
##
## Lists every suspect with its live value (tick = include it in a hunt; the
## value button flips it for real), the stimulus switches, and the runs so far
## as a table, newest last, with the hunt's verdict on top. "Record" takes one
## run at the current settings, so a person can flip things by hand and
## compare; "Hunt" does the flipping itself.
class_name BugHuntPanel
extends PanelContainer

var accent := Color("ffd23a")
var _hunt: BugHunt = null
var _status: Label
var _verdict: Label
var _table: GridContainer
var _value_buttons: Dictionary = {}


func setup(hunt: BugHunt) -> void:
	_hunt = hunt
	_hunt.run_finished.connect(func(_r: Dictionary) -> void: _refresh())
	_hunt.hunt_finished.connect(func(v: Dictionary) -> void: _verdict.text = String(v.get("text", "")))
	_hunt.status_changed.connect(func(t: String) -> void: _status.text = t)


func _ready() -> void:
	custom_minimum_size = Vector2(520.0, 540.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.95)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "🐞 BUG HUNT — which setting bends the shots?"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	_note(vbox, "Each run holds the trigger, weaves the stick and lands fake hits on "
		+ "your hull for a few seconds, then reports how far shots left the line a "
		+ "perfect gun takes. Hunt = baseline, then each ticked suspect flipped alone.")

	_label(vbox, "Suspects (tick = include in hunt · button = flip now)", Color("6ec6ff"))
	for id: String in _hunt.suspects.keys():
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var tick := CheckBox.new()
		tick.text = String(_hunt.suspects[id]["label"])
		tick.button_pressed = _hunt.hunt_ids.has(id)
		tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tick.toggled.connect(_on_tick.bind(id))
		row.add_child(tick)
		var val := Button.new()
		val.custom_minimum_size = Vector2(90.0, 0.0)
		val.focus_mode = Control.FOCUS_NONE
		val.pressed.connect(_on_flip.bind(id))
		row.add_child(val)
		_value_buttons[id] = val

	_label(vbox, "Stimulus", Color("6ec6ff"))
	var stim := HBoxContainer.new()
	vbox.add_child(stim)
	for trio: Array in [["Hold fire", "stim_fire"], ["Weave stick", "stim_weave"], ["Fake hits", "stim_hits"]]:
		var c := CheckBox.new()
		c.text = trio[0]
		c.button_pressed = bool(_hunt.get(trio[1]))
		c.toggled.connect(func(on: bool) -> void: _hunt.set(trio[1], on))
		stim.add_child(c)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	_button(buttons, "● Record run", func() -> void: _hunt.start_run("manual #%d" % (_hunt.runs.size() + 1)))
	_button(buttons, "🔎 Hunt", func() -> void:
		_verdict.text = ""
		_hunt.start_hunt())
	_button(buttons, "Stop", func() -> void: _hunt.cancel())
	_button(buttons, "Clear", func() -> void:
		_hunt.clear_runs()
		_verdict.text = ""
		_refresh())
	_button(buttons, "Copy", func() -> void: DisplayServer.clipboard_set(_as_text()))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status)
	_verdict = Label.new()
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.add_theme_color_override("font_color", accent)
	vbox.add_child(_verdict)

	_table = GridContainer.new()
	_table.columns = 5
	_table.add_theme_constant_override("h_separation", 12)
	vbox.add_child(_table)
	_note(vbox, "Runs are also appended to %s." % BugHunt.CSV_PATH)
	_refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	for id: String in _value_buttons.keys():
		var v: Variant = (_hunt.suspects[id]["get"] as Callable).call()
		(_value_buttons[id] as Button).text = _fmt(v)


func _on_tick(on: bool, id: String) -> void:
	if on and not _hunt.hunt_ids.has(id):
		_hunt.hunt_ids.append(id)
	elif not on:
		_hunt.hunt_ids.erase(id)


func _on_flip(id: String) -> void:
	(_hunt.suspects[id]["set"] as Callable).call(_hunt.alt_value(id))


func _refresh() -> void:
	if _table == null:
		return
	for c in _table.get_children():
		c.queue_free()
	for h: String in ["run", "shots", "mean °", "p95 °", "max °"]:
		_cell(h, Color("6ec6ff"))
	for run: Dictionary in _hunt.runs:
		var m: Dictionary = run["metrics"]
		_cell(String(run["label"]), Color.WHITE)
		_cell(str(int(m.get("shot_dev_n", 0))), Color.WHITE)
		_cell("%.2f" % float(m.get("shot_dev_mean", -1.0)), accent)
		_cell("%.2f" % float(m.get("shot_dev_p95", -1.0)), Color.WHITE)
		_cell("%.2f" % float(m.get("shot_dev_max", -1.0)), Color.WHITE)


func _as_text() -> String:
	var lines: Array[String] = [_verdict.text, "run\tshots\tmean\tp95\tmax"]
	for run: Dictionary in _hunt.runs:
		var m: Dictionary = run["metrics"]
		lines.append("%s\t%d\t%.3f\t%.3f\t%.3f" % [run["label"], int(m.get("shot_dev_n", 0)),
			float(m.get("shot_dev_mean", -1.0)), float(m.get("shot_dev_p95", -1.0)), float(m.get("shot_dev_max", -1.0))])
	return "\n".join(lines)


func _fmt(v: Variant) -> String:
	if v is bool:
		return "ON" if v else "off"
	if v is float:
		return "%.2f" % v
	return str(v)


func _cell(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col)
	_table.add_child(l)


func _label(vbox: VBoxContainer, text: String, col: Color) -> void:
	vbox.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	vbox.add_child(l)


func _note(vbox: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vbox.add_child(l)


func _button(row: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	row.add_child(b)
