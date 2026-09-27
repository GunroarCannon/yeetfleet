## MobileHudFontsPanel: choose the mobile HUD's look, style each text role's
## font, roll random font combos, and pick the touch control scheme. Opened
## from the 🔤 HUD fonts button on the D debug strip (and the View menu).
## Every pick is live and saved straight away by [MobileHudProfiles]; the HUD
## notices through its revision counter.
class_name MobileHudFontsPanel
extends PanelContainer

var _profile_pick: OptionButton
var _rows: VBoxContainer
var _fonts := PackedStringArray()
var _scheme_desc: Label


func _ready() -> void:
	custom_minimum_size = Vector2(460.0, 420.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.94)
	sb.border_color = Color("ff9a1f", 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "🔤 MOBILE HUD — LOOK, FONTS & CONTROLS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ff9a1f"))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 380.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# --- Controls ---
	_section(vbox, "Touch controls", Color("46ff9b"))
	var srow := HBoxContainer.new()
	vbox.add_child(srow)
	srow.add_child(_row_label("Scheme"))
	var scheme_pick := OptionButton.new()
	scheme_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scheme_pick.focus_mode = Control.FOCUS_NONE
	for id: String in MobileHudProfiles.SCHEME_ORDER:
		scheme_pick.add_item(String(MobileHudProfiles.SCHEMES[id]["name"]))
		scheme_pick.set_item_metadata(scheme_pick.item_count - 1, id)
		if id == MobileHudProfiles.scheme:
			scheme_pick.select(scheme_pick.item_count - 1)
	scheme_pick.item_selected.connect(func(i: int) -> void:
		MobileHudProfiles.set_scheme(String(scheme_pick.get_item_metadata(i)))
		_sync_scheme_desc()
	)
	srow.add_child(scheme_pick)
	_scheme_desc = _note(vbox, "")
	_sync_scheme_desc()
	var swap := CheckBox.new()
	swap.text = "Swap left and right (stick on the right, buttons on the left)"
	swap.button_pressed = MobileHudProfiles.swap_sides
	swap.focus_mode = Control.FOCUS_NONE
	swap.toggled.connect(MobileHudProfiles.set_swap_sides)
	vbox.add_child(swap)
	_slider(vbox, "Simple: cruise speed", 0.1, 1.0, 0.05, MobileHudProfiles.simple_speed,
		MobileHudProfiles.set_simple_speed, "%.0f%%", 100.0)

	# --- Look ---
	_section(vbox, "Look", Color("ff9a1f"))
	var prow := HBoxContainer.new()
	vbox.add_child(prow)
	prow.add_child(_row_label("Profile"))
	_profile_pick = OptionButton.new()
	_profile_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_pick.focus_mode = Control.FOCUS_NONE
	for id: String in MobileHudProfiles.profile_ids():
		_profile_pick.add_item(String(MobileHudProfiles.PROFILES[id]["name"]))
		_profile_pick.set_item_metadata(_profile_pick.item_count - 1, id)
	_profile_pick.item_selected.connect(func(i: int) -> void:
		MobileHudProfiles.set_active(String(_profile_pick.get_item_metadata(i)))
		_rebuild_rows()
	)
	prow.add_child(_profile_pick)

	# --- Fonts ---
	_section(vbox, "Fonts", Color("ffcc1a"))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	vbox.add_child(brow)
	var dice := Button.new()
	dice.text = "🎲 Randomize font combo"
	dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice.focus_mode = Control.FOCUS_NONE
	dice.pressed.connect(func() -> void:
		MobileHudProfiles.randomize_fonts()
		_rebuild_rows()
	)
	brow.add_child(dice)
	var reset := Button.new()
	reset.text = "Reset"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		MobileHudProfiles.reset_fonts()
		_rebuild_rows()
	)
	brow.add_child(reset)
	var launch := CheckBox.new()
	launch.text = "New random combo every launch"
	launch.button_pressed = MobileHudProfiles.random_fonts_on_launch
	launch.focus_mode = Control.FOCUS_NONE
	launch.toggled.connect(MobileHudProfiles.set_random_fonts_on_launch)
	vbox.add_child(launch)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows)

	_note(vbox, "Fonts come from res://assets/fonts — drop a .ttf/.otf there and it shows up here.")

	_fonts = MobileHudProfiles.available_fonts()
	_sync_profile_pick()
	_rebuild_rows()
	visibility_changed.connect(func() -> void:
		if visible:
			_sync_profile_pick()
			_rebuild_rows()
	)


func _sync_profile_pick() -> void:
	for i in _profile_pick.item_count:
		if String(_profile_pick.get_item_metadata(i)) == MobileHudProfiles.active:
			_profile_pick.select(i)


func _sync_scheme_desc() -> void:
	_scheme_desc.text = String(MobileHudProfiles.SCHEMES[MobileHudProfiles.scheme]["desc"])


## Per role: a font picker with a preview in that font, then its size, weight
## and spacing. The profile-wide outline and lean close the list.
func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for role: String in MobileHudProfiles.ROLES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rows.add_child(row)
		var label := _row_label(MobileHudProfiles.ROLE_NAMES[role])
		label.add_theme_color_override("font_color", Color("ffcc1a"))
		row.add_child(label)
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(130.0, 0.0)
		pick.add_item("(theme default)")
		pick.set_item_metadata(0, MobileHudProfiles.DEFAULT_FONT)
		var current := MobileHudProfiles.font_file(role)
		for f in _fonts:
			pick.add_item(f.get_basename())
			pick.set_item_metadata(pick.item_count - 1, f)
			if f == current:
				pick.select(pick.item_count - 1)
		row.add_child(pick)
		var preview := Label.new()
		preview.text = "HEALTH 920 KMH!" if role != "label" else "KMH · 920"
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.clip_text = true
		row.add_child(preview)
		_apply_preview(preview, role)
		pick.item_selected.connect(func(i: int) -> void:
			MobileHudProfiles.set_font(role, String(pick.get_item_metadata(i)))
			_apply_preview(preview, role)
		)
		for kind: Array in [["size", "  size", 0.05, "×%.2f"], ["bold", "  weight", 0.05, "+%.2f"], ["space", "  letter spacing", 1.0, "%+.0f px"]]:
			var key := "%s_%s" % [kind[0], role]
			var r := MobileHudProfiles.style_range(key)
			var on_change := func(v: float) -> void:
				MobileHudProfiles.set_style(key, v)
				_apply_preview(preview, role)
			_slider(_rows, String(kind[1]), r.x, r.y, float(kind[2]), MobileHudProfiles.style(key),
				on_change, String(kind[3]))
	_rows.add_child(HSeparator.new())
	for kind: Array in [["outline", "Outline thickness"], ["lean", "Comic lean (italic)"]]:
		var key := String(kind[0])
		var r := MobileHudProfiles.style_range(key)
		_slider(_rows, String(kind[1]), r.x, r.y, 0.05, MobileHudProfiles.style(key),
			func(v: float) -> void: MobileHudProfiles.set_style(key, v), "×%.2f")


func _apply_preview(preview: Label, role: String) -> void:
	var f := MobileHudProfiles.font(role)
	if f != null:
		preview.add_theme_font_override("font", f)
	else:
		preview.remove_theme_font_override("font")
	preview.add_theme_font_size_override("font_size", roundi(20.0 * MobileHudProfiles.style("size_" + role)))


func _section(vbox: VBoxContainer, text: String, color: Color) -> void:
	vbox.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(150.0, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _note(vbox: VBoxContainer, text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	vbox.add_child(note)
	return note


## Label + slider + live value. Set without a signal so opening the panel
## never re-saves a value nobody touched.
func _slider(
	parent: VBoxContainer, text: String, min_v: float, max_v: float, step: float,
	value: float, setter: Callable, fmt: String, display_mult := 1.0
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	row.add_child(_row_label(text))
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.set_value_no_signal(value)
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(64.0, 0.0)
	readout.text = fmt % (value * display_mult)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = fmt % (v * display_mult)
		setter.call(v)
	)
