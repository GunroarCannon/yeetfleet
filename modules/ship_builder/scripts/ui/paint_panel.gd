## Ship-wide paint: three channels, a surface finish, and faction liveries.
##
## The GDD's colour-mask system is what makes a small part library look like a large
## one, so this panel is deliberately front-and-centre rather than buried in a
## submenu. Scrubbing a picker retints the whole ship immediately — the mesh is not
## rebuilt, only three shader uniforms are written — which is what makes choosing a
## colour feel like choosing a colour rather than like waiting for a render.
class_name PaintPanel
extends VBoxContainer

var _root: BuilderRoot
var _pickers: Dictionary = {}
var _material_options: OptionButton
var _faction_label: Label
var _updating := false


func _ready() -> void:
	_root = owner as BuilderRoot
	_build_ui()
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: refresh())


func _build_ui() -> void:
	var header := Label.new()
	header.text = "PAINT"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(header)

	for channel in ShipDesign.CHANNELS:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = String(ShipDesign.CHANNEL_LABELS.get(channel, channel))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		row.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(64, BuilderTheme.TOUCH_MIN - 12)
		picker.edit_alpha = false
		picker.tooltip_text = "Repaint every part's %s channel" % channel
		row.add_child(picker)
		picker.color_changed.connect(func(c: Color) -> void:
			if _updating:
				return
			_root.set_palette_color(channel, c, true)
		)
		picker.pressed.connect(func() -> void: _root.begin_continuous("Paint " + channel))
		picker.popup_closed.connect(func() -> void: _root.end_continuous())
		_pickers[channel] = picker

	var finish_row := HBoxContainer.new()
	add_child(finish_row)
	var finish_label := Label.new()
	finish_label.text = "Finish"
	finish_label.add_theme_font_size_override("font_size", 11)
	finish_label.custom_minimum_size.x = 62
	finish_row.add_child(finish_label)
	_material_options = OptionButton.new()
	_material_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material_options.tooltip_text = "Surface finish: roughness, metallic and panel weathering"
	var index := 0
	for preset: String in ShipDesign.MATERIAL_PRESETS:
		_material_options.add_item(preset.capitalize(), index)
		_material_options.set_item_metadata(index, preset)
		index += 1
	_material_options.item_selected.connect(func(i: int) -> void:
		if _updating:
			return
		_root.set_material_preset(String(_material_options.get_item_metadata(i)))
	)
	finish_row.add_child(_material_options)

	var livery_header := Label.new()
	livery_header.text = "LIVERIES"
	livery_header.add_theme_font_size_override("font_size", 11)
	livery_header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(livery_header)

	_faction_label = Label.new()
	_faction_label.add_theme_font_size_override("font_size", 10)
	_faction_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_faction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_faction_label)

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	add_child(grid)
	for faction in _root.library.factions:
		grid.add_child(_make_livery_button(faction))

	refresh()


## A livery button shows the actual three colours it will apply. A row of names
## tells you nothing; a row of colour chips tells you everything.
func _make_livery_button(faction: Dictionary) -> Button:
	var id := String(faction.get("id", ""))
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 30)
	button.text = String(faction.get("name", id))
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 11)
	button.tooltip_text = "%s\n\n%s" % [
		String(faction.get("name", id)), String(faction.get("desc", ""))
	]
	var palette: Dictionary = faction.get("palette", {})
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -5
	strip.offset_left = 3
	strip.offset_right = -3
	strip.offset_bottom = -2
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for channel in ShipDesign.CHANNELS:
		var chip := TextureRect.new()
		chip.texture = BuilderTheme.swatch(
			Color.from_string(String(palette.get(channel, "888888")), Color.GRAY), 8
		)
		chip.stretch_mode = TextureRect.STRETCH_SCALE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(chip)
	button.add_child(strip)
	button.pressed.connect(func() -> void: _root.apply_faction(id))
	return button


func refresh() -> void:
	if _root == null:
		return
	# Writing a picker's colour emits color_changed, which would immediately push the
	# same value back into the design and open a stray history transaction.
	_updating = true
	for channel: String in _pickers:
		(_pickers[channel] as ColorPickerButton).color = _root.design.get_color(channel)
	for i in _material_options.item_count:
		if String(_material_options.get_item_metadata(i)) == _root.design.material_preset:
			_material_options.select(i)
			break
	_updating = false

	if _root.design.faction_id == "":
		_faction_label.text = "Custom paint. Pick a livery to repaint the whole hull."
	else:
		var faction := _root.library.get_faction(_root.design.faction_id)
		_faction_label.text = "Wearing %s colours. Per-part overrides are kept." % String(
			faction.get("name", _root.design.faction_id)
		)
