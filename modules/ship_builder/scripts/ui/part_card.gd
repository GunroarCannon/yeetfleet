## One draggable part in the palette.
##
## Built by hand rather than as a nested scene so the whole card is a single
## focusable, draggable control: a Button with children drawn on top. That matters
## for accessibility — the card is reachable by Tab, activated by Enter, and its
## tooltip carries the full stat block for anyone who cannot read the tiny text.
class_name PartCard
extends Button

## The card was activated (clicked or Enter) rather than dragged.
signal chosen(part_id: String)
## Pointer entered/left, for the stat-preview comparison.
signal considered(part_id: String)
signal unconsidered

const CARD_HEIGHT := 62

var part: ShipPart
## Set when the palette is filtered to a socket that this part does not fit; the
## card stays visible but explains itself instead of pretending to be available.
var rejection := ""


func setup(p_part: ShipPart, p_rejection := "") -> void:
	part = p_part
	rejection = p_rejection
	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	# Text is drawn by child labels so the two lines can have different colours;
	# the Button itself keeps an accessible name for screen readers.
	text = ""
	tooltip_text = _build_tooltip()
	if not is_node_ready():
		await ready
	_build_children()


func _build_children() -> void:
	for child in get_children():
		child.queue_free()

	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 5
	row.offset_bottom = -5
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var swatch := TextureRect.new()
	swatch.texture = BuilderTheme.swatch(_category_color(), 16)
	swatch.custom_minimum_size = Vector2(6, 0)
	swatch.stretch_mode = TextureRect.STRETCH_SCALE
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var title := Label.new()
	title.text = part.display_name
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", BuilderTheme.text() if rejection == "" else BuilderTheme.text_dim())
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var detail := Label.new()
	detail.text = rejection if rejection != "" else _headline()
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override(
		"font_color", BuilderTheme.bad() if rejection != "" else BuilderTheme.text_dim()
	)
	detail.clip_text = true
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(detail)

	var size_tag := Label.new()
	size_tag.text = part.size_class.substr(0, 3).to_upper()
	size_tag.add_theme_font_size_override("font_size", 10)
	size_tag.add_theme_color_override("font_color", BuilderTheme.text_dim())
	size_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(size_tag)

	disabled = false
	modulate = Color(1, 1, 1, 1.0 if rejection == "" else 0.55)


## The two or three numbers that actually decide whether you want this part. Which
## ones those are depends on the category — thrust matters on an engine, damage on
## a gun — so the headline is chosen per category rather than showing a fixed set.
func _headline() -> String:
	var bits: Array[String] = []
	match part.category:
		"engine":
			bits.append("%.0f kN" % part.stat("thrust"))
			bits.append("%.1f t" % part.stat("mass"))
		"weapon":
			var dmg := float(part.func_data.get("damage", 0.0))
			var rate := float(part.func_data.get("fire_rate", 1.0))
			bits.append("%.0f dps" % (dmg * rate))
			if part.func_data.has("ammo"):
				bits.append("%d rds" % int(part.func_data["ammo"]))
		"cargo":
			if part.stat("cargo_capacity") > 0.0:
				bits.append("%.0f t hold" % part.stat("cargo_capacity"))
			if part.stat("power_output") > 0.0:
				bits.append("+%.0f MW" % part.stat("power_output"))
			if part.stat("shield_hp") > 0.0:
				bits.append("%.0f shield" % part.stat("shield_hp"))
		"armor":
			if part.stat("hull_hp") > 0.0:
				bits.append("+%.0f hull" % part.stat("hull_hp"))
			if part.stat("heat_dissipation") > 0.0:
				bits.append("%.0f cooling" % part.stat("heat_dissipation"))
		"wing":
			bits.append("%+.1f control" % part.stat("agility_pool"))
			bits.append("%.1f t" % part.stat("mass"))
		"chassis":
			bits.append("%.0f t limit" % part.mass_limit)
			bits.append("%d sockets" % part.sockets.size())
		_:
			bits.append("%.1f t" % part.stat("mass"))
	if bits.is_empty():
		bits.append(part.category_label())
	return " · ".join(bits)


func _build_tooltip() -> String:
	var lines: Array[String] = [part.display_name, part.summary()]
	if part.description != "":
		lines.append(part.description)
	var stat_bits: Array[String] = []
	for key in ShipStats.STAT_KEYS:
		var v := part.stat(key)
		if is_zero_approx(v):
			continue
		stat_bits.append("%s %s" % [ShipStats.stat_label(key), ShipStats.format_delta(key, v)])
	if not stat_bits.is_empty():
		lines.append("\n".join(stat_bits))
	if not part.sockets.is_empty():
		lines.append("Mounts: " + ", ".join(part.sockets.map(
			func(s: PartSocket) -> String: return s.display_name if s.display_name != "" else s.id
		)))
	if part.cost > 0:
		lines.append("%s cr" % part.cost)
	if rejection != "":
		lines.append("✗ " + rejection)
	return "\n\n".join(lines)


func _category_color() -> Color:
	# A stable hue per category so the palette is scannable by colour, with the
	# category name always present as text so colour is never the only cue.
	match part.category:
		"chassis": return Color("6f7d94")
		"cockpit": return Color("57c7ff")
		"engine": return Color("ff9b4d")
		"weapon": return Color("ff6b6b")
		"cargo": return Color("6fe0a8")
		"wing": return Color("c99bff")
		"armor": return Color("d8c470")
		_: return Color("8b97a8")


func _get_drag_data(_at_position: Vector2) -> Variant:
	if rejection != "":
		return null
	# The drag preview is a copy of the card, so what the player is holding is
	# visually identical to what they picked up.
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(size.x, CARD_HEIGHT)
	preview.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_alt_bg(), BuilderTheme.accent(), 4, 2)
	)
	var label := Label.new()
	label.text = part.display_name
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"type": "part", "part_id": part.id, "category": part.category}


func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(part.id))
	mouse_entered.connect(func() -> void: considered.emit(part.id))
	mouse_exited.connect(func() -> void: unconsidered.emit())
	focus_entered.connect(func() -> void: considered.emit(part.id))
	focus_exited.connect(func() -> void: unconsidered.emit())
