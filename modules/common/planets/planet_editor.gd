## In-game editor for making planets: a 3D stage with the planet on it and one
## accordion of controls beside it.
##
## The previous version of this script drew its own opaque full-rect background
## and its own scroll container over the whole Control, which hid the stage the
## sliders were for — you could edit a planet you could not see. Everything here
## is built into the nodes [code]planet_editor.tscn[/code] already provides
## ([code]%Controls[/code], [code]%TitleBar[/code], [code]%ViewBar[/code],
## [code]%StatusLabel[/code]), so the stage stays the biggest thing on screen.
##
## Three rules it follows:
##
## [br]• [b]One section open at a time.[/b] Twenty-five controls in a 320px column
## is a scrollbar, not an interface. Closed headers carry a summary of their own
## values, so the state of the whole planet is readable without opening anything.
## [br]• [b]The cheapest update that will do.[/b] A colour picker only pushes
## shader uniforms ([method Planet.refresh_appearance]); terrain and radius
## re-displace the mesh on a debounce ([method Planet.refresh_geometry]); only a
## change in the [i]set[/i] of nodes falls through to a full
## [method Planet.configure]. Dragging a slider used to rebuild six cube-sphere
## faces per pixel.
## [br]• [b]One layout for phone and desktop[/b], the same breakpoint the ship
## builder uses: below [constant NARROW_WIDTH] the panel becomes a drawer behind
## the Tune button and the planet keeps the screen.
##
## Planets are saved as content, into res://data/planets through
## [PlanetLibrary], so the flight scene can fly past one.
class_name PlanetEditor
extends Control

## Below this width the side panel becomes a drawer instead of a column. Same
## value and same reasoning as [constant BuilderRoot.NARROW_WIDTH].
const NARROW_WIDTH := 1040.0

## Seconds a geometry change waits before the mesh is re-displaced. Long enough
## that dragging a slider across its range costs one rebuild rather than sixty,
## short enough to feel like the slider did it.
const REBUILD_DELAY := 0.12

## Seconds of no input before the planet starts turning by itself. A still planet
## in a still frame reads as a texture; a turning one reads as a sphere.
const IDLE_SPIN_DELAY := 3.5

## Pixels of movement before a press counts as a drag rather than a tap. Same
## generous threshold as the builder viewport — a finger never holds still.
const DRAG_THRESHOLD := 6.0

## Reframe when the planet has changed size by more than this fraction. Without a
## deadband, every nudge of the ring width would yank a camera the player had
## deliberately zoomed in.
const REFRAME_TOLERANCE := 0.04

const SECTION_ORDER: Array[String] = [
	"identity", "shape", "terrain", "surface", "rings", "atmosphere", "motion", "library",
]

const SECTION_TITLES := {
	"identity": "Identity",
	"shape": "Shape",
	"terrain": "Terrain",
	"surface": "Surface",
	"rings": "Rings",
	"atmosphere": "Atmosphere",
	"motion": "Motion",
	"library": "Library",
}

## Syllables for the randomiser. Nonsense, but pronounceable nonsense — a planet
## called "Vorun" is a place and one called "Planet 4" is a row in a table.
const NAME_HEAD: Array[String] = [
	"Tar", "Vor", "Kes", "Mal", "Ard", "Cyn", "Dol", "Eru", "Fen", "Gal",
	"Hel", "Ith", "Jor", "Kar", "Lun", "Mor", "Nix", "Oth", "Pra", "Quel",
]
const NAME_TAIL: Array[String] = [
	"un", "is", "a", "or", "eth", "ax", "ion", "ara", "ex", "ur",
	"ane", "ys", "ol", "ith", "en",
]
const NAME_SUFFIX: Array[String] = ["", " II", " III", " IV", " V", " Prime", " Minor"]

## The planet being edited. Saved and loaded as-is.
var data := PlanetData.new()

var _planet: Planet
var _camera: OrbitCamera
var _stage: SubViewportContainer
var _panel: PanelContainer
var _toast: Toast

# Accordion state. key -> {"header": Button, "summary": Label, "body": VBoxContainer}
# Empty means every section is collapsed, which is the state _ready() opens the
# first one out of — _open_section toggles, so starting it at "identity" would
# have closed identity instead of opening it.
var _sections: Dictionary = {}
var _open_key := ""

# Rows that show a value, so a load or a randomise can push the new numbers back
# into the widgets: {"prop", "slider", "readout", "decimals", "suffix", "scale"}
var _rows: Array[Dictionary] = []
# prop -> Control, for the pickers, checkboxes and fields.
var _widgets: Dictionary = {}
# True while widgets are being written from data, so the change handlers those
# writes fire do not write straight back and fight the caller.
var _syncing := false

var _narrow := false
var _geometry_dirty := false
var _rebuild_timer := 0.0
var _idle_timer := 0.0
var _framed_radius := 0.0

# Pointer state for the stage. Tracked by hand so one gesture set covers mouse,
# pen and touch — same approach as [BuilderViewport].
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_button := MOUSE_BUTTON_LEFT
var _touches: Dictionary = {}
var _pinch_distance := 0.0

var _library_list: VBoxContainer
# Rows that only apply to some planets: {"row": Control, "gate": String}. See
# [method _gate_open].
var _gates: Array[Dictionary] = []


func _ready() -> void:
	theme = BuilderTheme.build()
	_stage = %Stage as SubViewportContainer
	_camera = %Camera as OrbitCamera
	_planet = %PreviewPlanet as Planet
	_panel = %SidePanel as PanelContainer

	_build_title_bar()
	_build_view_bar()
	_build_sections()
	_build_toast()

	_stage.gui_input.connect(_on_stage_input)
	(%PanelToggle as Button).pressed.connect(toggle_panel)
	get_viewport().size_changed.connect(_on_window_resized)

	# A default planet rather than an empty stage: the first thing the editor
	# shows should be a planet, so there is something to react to.
	data = _default_planet()
	_planet.configure(data)
	_sync_widgets()
	_open_section("identity")
	_on_window_resized()
	_frame_planet(true)
	_update_status()


func _default_planet() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "New World"
	d.seed_value = 20250824
	d.planet_radius = 5.0
	d.sphere_resolution = 64
	d.terrain_height = 0.075
	d.continent_scale = 1.1
	d.mountain_scale = 4.0
	d.ridge_strength = 0.45
	d.sea_level = 0.5
	d.ice_amount = 0.45
	d.primary_color = Color(0.52, 0.44, 0.30)
	d.secondary_color = Color(0.31, 0.46, 0.25)
	d.water_color = Color(0.07, 0.20, 0.36)
	d.atmosphere_density = 0.45
	d.atmosphere_color = Color(0.45, 0.72, 1.0)
	d.cloud_density = 0.25
	d.cloud_color = Color(0.92, 0.93, 0.97, 1.0)
	d.gravity_mass = 10.0
	d.detail_strength = 0.18
	d.rotation_speed = 0.01
	return d


# --- Frame-by-frame -------------------------------------------------------

func _process(delta: float) -> void:
	if _geometry_dirty:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			_geometry_dirty = false
			_apply_geometry()
	_idle_timer += delta
	if _idle_timer > IDLE_SPIN_DELAY and not _camera.auto_spin and not _pressed:
		_camera.auto_spin = true


func _mark_active() -> void:
	_idle_timer = 0.0
	_camera.auto_spin = false


# --- Update paths ---------------------------------------------------------

## Shader uniforms only. What the colour pickers and the swirl/detail/ice sliders
## call — no allocation, no mesh work.
func _touch_appearance() -> void:
	_planet.refresh_appearance()
	_update_summaries()
	_update_status()


## Queue a re-displacement. Coalesced, because the slider that asked will ask
## again on the next mouse motion event.
func _touch_geometry() -> void:
	_geometry_dirty = true
	_rebuild_timer = REBUILD_DELAY
	_update_summaries()


## Rebuild from scratch. Only for changes that alter which nodes exist — the
## planet type flipping between rocky and gas giant.
func _touch_structure() -> void:
	_geometry_dirty = false
	_planet.configure(data)
	_after_geometry()


func _apply_geometry() -> void:
	# refresh_geometry says no when the change needs different nodes rather than
	# different numbers — a ring switched on, an atmosphere faded up from zero.
	if not _planet.refresh_geometry():
		_planet.configure(data)
	_after_geometry()


func _after_geometry() -> void:
	_update_summaries()
	_update_status()
	# The planet may have changed size enough to leave the frame or shrink to a
	# dot. Reframe only when it actually did — see REFRAME_TOLERANCE.
	var r := _planet.outer_radius()
	if _framed_radius <= 0.0 or absf(r - _framed_radius) > _framed_radius * REFRAME_TOLERANCE:
		_frame_planet(false)


func _frame_planet(instant: bool) -> void:
	var r := _planet.outer_radius()
	if r <= 0.0:
		return
	_framed_radius = r
	# A sphere's bounding box is the same in every direction, so the exact
	# 8-corner fit OrbitCamera.frame does is free of surprises here.
	_camera.frame(AABB(Vector3.ONE * -r, Vector3.ONE * r * 2.0), _stage_aspect(), instant)


func _stage_aspect() -> float:
	var s := _stage.size
	if s.y <= 0.0:
		return 1.6
	return s.x / s.y


# --- Title bar ------------------------------------------------------------

func _build_title_bar() -> void:
	var bar := %TitleBar as HBoxContainer
	bar.add_theme_constant_override("separation", BuilderTheme.GAP)

	var title := Label.new()
	title.text = "Planet Editor"
	title.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	bar.add_child(title)

	var name_field := LineEdit.new()
	name_field.custom_minimum_size = Vector2(180, BuilderTheme.TOUCH_MIN)
	name_field.placeholder_text = "Planet name"
	name_field.tooltip_text = "Also the file name it saves under"
	name_field.text_changed.connect(func(text: String) -> void:
		if _syncing:
			return
		data.planet_name = text
		_update_summaries()
	)
	bar.add_child(name_field)
	_widgets["planet_name"] = name_field

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)

	bar.add_child(_action_button("Random", "Roll a whole new planet, terrain included", _randomise))
	bar.add_child(_action_button("Save", "Write to res://data/planets so the game can use it", _save))


func _action_button(text: String, tip: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	button.pressed.connect(handler)
	return button


func _build_view_bar() -> void:
	var bar := %ViewBar as HBoxContainer
	bar.add_theme_constant_override("separation", BuilderTheme.GAP)
	for view: String in ["front", "side", "top"]:
		var button := Button.new()
		button.text = view.capitalize()
		button.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN, BuilderTheme.TOUCH_MIN)
		button.pressed.connect(func() -> void:
			_mark_active()
			_camera.set_view(view)
		)
		bar.add_child(button)
	bar.add_child(_action_button("Fit", "Frame the whole planet (F)", func() -> void:
		_mark_active()
		_frame_planet(false)
	))
	var spin := CheckButton.new()
	spin.text = "Spin"
	spin.button_pressed = true
	spin.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	spin.toggled.connect(func(on: bool) -> void:
		_camera.auto_spin = on
		_idle_timer = 0.0 if not on else IDLE_SPIN_DELAY
	)
	bar.add_child(spin)


func _build_toast() -> void:
	_toast = Toast.new()
	_toast.name = "Toast"
	var column := _stage.get_parent().find_child("OverlayColumn", true, false) as VBoxContainer
	if column == null:
		return
	column.add_child(_toast)
	# Above the status line and the view bar, below the spacer, so notices rise
	# out of the bottom-left corner rather than covering the planet.
	column.move_child(_toast, maxi(column.get_child_count() - 3, 0))


func _notify(text: String, kind := "info") -> void:
	if _toast != null:
		_toast.show_notice(text, kind)


# --- Accordion ------------------------------------------------------------

func _build_sections() -> void:
	var controls := %Controls as VBoxContainer
	controls.add_theme_constant_override("separation", BuilderTheme.GAP)
	for key: String in SECTION_ORDER:
		_sections[key] = _make_section(controls, key, String(SECTION_TITLES[key]))
	_fill_identity(_sections["identity"]["body"])
	_fill_shape(_sections["shape"]["body"])
	_fill_terrain(_sections["terrain"]["body"])
	_fill_surface(_sections["surface"]["body"])
	_fill_rings(_sections["rings"]["body"])
	_fill_atmosphere(_sections["atmosphere"]["body"])
	_fill_motion(_sections["motion"]["body"])
	_fill_library(_sections["library"]["body"])


func _make_section(parent: VBoxContainer, key: String, title: String) -> Dictionary:
	var header := Button.new()
	header.name = key.capitalize() + "Header"
	header.text = "  " + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	header.toggle_mode = false
	header.pressed.connect(func() -> void: _open_section(key))

	# The summary rides inside the button, anchored to its right edge, so the
	# whole header stays one tap target instead of splitting into a button and a
	# label the player has to aim between.
	var summary := Label.new()
	summary.name = "Summary"
	summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.offset_right = -BuilderTheme.PAD
	summary.clip_text = true
	summary.add_theme_color_override("font_color", BuilderTheme.text_dim())
	summary.add_theme_font_size_override("font_size", 11)
	header.add_child(summary)
	parent.add_child(header)

	var body := VBoxContainer.new()
	body.name = key.capitalize() + "Body"
	body.add_theme_constant_override("separation", BuilderTheme.GAP)
	body.visible = false
	parent.add_child(body)

	return {"header": header, "summary": summary, "body": body}


## One section open at a time. Twenty-five controls unfolded at once is the
## scrollbar this editor had before.
func _open_section(key: String) -> void:
	_open_key = key if key != _open_key else ""
	for section_key: String in SECTION_ORDER:
		var section := _sections[section_key] as Dictionary
		var open := section_key == _open_key
		(section["body"] as VBoxContainer).visible = open
		var header := section["header"] as Button
		header.text = ("  ▾ " if open else "  ▸ ") + String(SECTION_TITLES[section_key])
	_update_summaries()


func _update_summaries() -> void:
	for key: String in SECTION_ORDER:
		var section := _sections[key] as Dictionary
		var label := section["summary"] as Label
		# An open section shows its values in full underneath; repeating them in
		# the header is noise.
		label.text = "" if key == _open_key else _summary_for(key)
	_sync_readouts()
	_update_enabled_state()


func _summary_for(key: String) -> String:
	match key:
		"identity":
			return "%s · seed %d" % [data.type_label(), data.seed_value]
		"shape":
			return "r %.1f · res %d" % [data.planet_radius, data.sphere_resolution]
		"terrain":
			if data.is_gas_giant():
				return "n/a"
			return "height %.3f · sea %.2f" % [data.terrain_height, data.sea_level]
		"surface":
			if data.is_gas_giant():
				return "%.0f bands · swirl %.2f" % [data.band_count, data.swirl_speed]
			return "ice %.0f%% · detail %.2f" % [data.ice_amount * 100.0, data.detail_strength]
		"rings":
			if not data.ring_enabled:
				return "off"
			return "%.2f–%.2f · %d bands" % [data.ring_inner_radius, data.ring_outer_radius, data.ring_bands]
		"atmosphere":
			var parts: PackedStringArray = []
			if data.atmosphere_density > 0.0:
				parts.append("%.0f%%" % [data.atmosphere_density * 100.0])
			if data.cloud_density > 0.0:
				parts.append("clouds %.0f%%" % [data.cloud_density * 100.0])
			return " · ".join(parts) if not parts.is_empty() else "off"
		"motion":
			return "g %.1f M" % data.gravity_mass
		"library":
			var count := PlanetLibrary.instance().entries.size()
			return "%d saved" % count
	return ""


## Grey out what the current planet does not use, rather than hiding it. A gas
## giant that keeps its terrain settings hands them straight back when the type is
## switched again, and a row that fades in place shows what turned it off — a row
## that vanishes just makes the panel jump.
func _update_enabled_state() -> void:
	for gate: Dictionary in _gates:
		_set_row_enabled(gate["row"] as Control, _gate_open(String(gate["gate"])))


func _gate_open(gate: String) -> bool:
	match gate:
		"rock":
			return not data.is_gas_giant()
		"gas":
			return data.is_gas_giant()
		"ring":
			return data.ring_enabled
		"atmo":
			return data.atmosphere_density > 0.0
	return true


func _set_row_enabled(row: Control, enabled: bool) -> void:
	row.modulate.a = 1.0 if enabled else 0.4
	_set_interactive(row, enabled)


func _set_interactive(node: Node, enabled: bool) -> void:
	# Each kind of control spells "off" differently, and setting the wrong
	# property on a Slider silently does nothing at all.
	if node is Slider:
		(node as Slider).editable = enabled
	elif node is SpinBox:
		(node as SpinBox).editable = enabled
	elif node is LineEdit:
		(node as LineEdit).editable = enabled
	elif node is BaseButton:
		(node as BaseButton).disabled = not enabled
	for child in node.get_children():
		_set_interactive(child, enabled)


# --- Rows -----------------------------------------------------------------

## A labelled slider with its value shown beside the label. The readout is the
## whole point: a slider with no number on it cannot be reproduced, written down
## or talked about.
func _slider_row(
	parent: VBoxContainer, label_text: String, prop: String,
	min_value: float, max_value: float, step: float,
	kind: String, decimals := 2, suffix := "", gate := ""
) -> void:
	var row := VBoxContainer.new()
	row.name = prop.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	head.add_child(name_label)
	var readout := Label.new()
	readout.add_theme_color_override("font_color", BuilderTheme.accent())
	readout.add_theme_font_size_override("font_size", 12)
	head.add_child(readout)
	row.add_child(head)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value = float(data.get(prop))
	slider.value_changed.connect(func(value: float) -> void:
		if _syncing:
			return
		# Integer properties must stay integers or the setter silently truncates
		# on some paths and not others.
		if step >= 1.0 and typeof(data.get(prop)) == TYPE_INT:
			data.set(prop, int(round(value)))
		else:
			data.set(prop, value)
		_dispatch(kind)
	)
	row.add_child(slider)
	parent.add_child(row)

	_rows.append({
		"prop": prop, "slider": slider, "readout": readout,
		"decimals": decimals, "suffix": suffix,
	})
	_widgets[prop] = slider
	if gate != "":
		_gates.append({"row": row, "gate": gate})


func _color_row(parent: VBoxContainer, label_text: String, prop: String, gate := "") -> void:
	var row := HBoxContainer.new()
	row.name = prop.to_pascal_case() + "Row"
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(72, BuilderTheme.TOUCH_MIN)
	picker.color = data.get(prop)
	picker.edit_alpha = false
	picker.color_changed.connect(func(color: Color) -> void:
		if _syncing:
			return
		data.set(prop, color)
		_touch_appearance()
	)
	row.add_child(picker)
	parent.add_child(row)
	_widgets[prop] = picker
	if gate != "":
		_gates.append({"row": row, "gate": gate})


func _check_row(parent: VBoxContainer, label_text: String, prop: String, kind: String) -> void:
	var check := CheckBox.new()
	check.text = label_text
	check.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	check.button_pressed = bool(data.get(prop))
	check.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		data.set(prop, on)
		_dispatch(kind)
	)
	parent.add_child(check)
	_widgets[prop] = check


func _dispatch(kind: String) -> void:
	match kind:
		"appearance":
			_touch_appearance()
		"structure":
			_touch_structure()
		_:
			_touch_geometry()


# --- Section contents -----------------------------------------------------

func _fill_identity(body: VBoxContainer) -> void:
	var type_row := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Type"
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.add_theme_font_size_override("font_size", 12)
	type_row.add_child(type_label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(120, BuilderTheme.TOUCH_MIN)
	option.add_item("Rocky", PlanetData.PlanetType.ROCKY)
	option.add_item("Gas Giant", PlanetData.PlanetType.GAS_GIANT)
	option.item_selected.connect(func(index: int) -> void:
		if _syncing:
			return
		data.planet_type = option.get_item_id(index)
		# A gas giant has no displaced mesh and no relief to shade, so the set of
		# things to build genuinely changes here.
		_touch_structure()
	)
	type_row.add_child(option)
	body.add_child(type_row)
	_widgets["planet_type"] = option

	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_row.add_child(seed_label)
	var seed_spin := SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 2147483647
	seed_spin.step = 1
	seed_spin.custom_minimum_size = Vector2(120, BuilderTheme.TOUCH_MIN)
	seed_spin.value = data.seed_value
	seed_spin.value_changed.connect(func(value: float) -> void:
		if _syncing:
			return
		data.seed_value = int(value)
		# The seed picks the coastlines and the mountain ranges, so it is terrain.
		_touch_geometry()
	)
	seed_row.add_child(seed_spin)
	var reroll := Button.new()
	reroll.text = "⟳"
	reroll.tooltip_text = "New seed — same palette, different continents"
	reroll.custom_minimum_size = Vector2(BuilderTheme.TOUCH_MIN, BuilderTheme.TOUCH_MIN)
	reroll.pressed.connect(func() -> void:
		data.seed_value = randi_range(1, 2147483646)
		_sync_widgets()
		_touch_geometry()
	)
	seed_row.add_child(reroll)
	body.add_child(seed_row)
	_widgets["seed_value"] = seed_spin


func _fill_shape(body: VBoxContainer) -> void:
	_slider_row(body, "Radius", "planet_radius", 0.5, 60.0, 0.5, "geometry", 1, " m")
	_slider_row(body, "Mesh detail", "sphere_resolution", 16, 128, 4, "geometry", 0, " per face")
	var note := Label.new()
	note.text = "Detail is vertices per cube face — six faces, so 64 is ~25k verts."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", BuilderTheme.text_dim())
	note.add_theme_font_size_override("font_size", 10)
	body.add_child(note)


func _fill_terrain(body: VBoxContainer) -> void:
	_slider_row(body, "Peak height", "terrain_height", 0.0, 0.25, 0.005, "geometry", 3, "", "rock")
	_slider_row(body, "Sea level", "sea_level", 0.0, 1.0, 0.01, "geometry", 2, "", "rock")
	_slider_row(body, "Continent size", "continent_scale", 0.2, 4.0, 0.05, "geometry", 2, "", "rock")
	_slider_row(body, "Mountain size", "mountain_scale", 1.0, 12.0, 0.1, "geometry", 1, "", "rock")
	_slider_row(body, "Ridges", "ridge_strength", 0.0, 1.0, 0.01, "geometry", 2, "", "rock")
	var note := Label.new()
	note.text = "Sea level moves the waterline and the coastline together: the ocean floor is not displaced, so the horizon stays round."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", BuilderTheme.text_dim())
	note.add_theme_font_size_override("font_size", 10)
	body.add_child(note)


func _fill_surface(body: VBoxContainer) -> void:
	# Highland and lowland do the same job on either planet type — the bright and
	# the dark end of one palette — so neither is gated.
	_color_row(body, "Highland", "primary_color")
	_color_row(body, "Lowland", "secondary_color")
	_color_row(body, "Sea", "water_color", "rock")
	_slider_row(body, "Ice", "ice_amount", 0.0, 1.0, 0.01, "appearance", 2, "", "rock")
	_slider_row(body, "Surface detail", "detail_strength", 0.0, 1.0, 0.01, "appearance", 2)
	_slider_row(body, "Spin speed", "rotation_speed", 0.0, 1.0, 0.005, "appearance", 3)
	_slider_row(body, "Bands", "band_count", 2.0, 20.0, 0.5, "appearance", 1, "", "gas")
	_slider_row(body, "Swirl speed", "swirl_speed", 0.0, 2.0, 0.01, "appearance", 2, "", "gas")
	_slider_row(body, "Swirl scale", "swirl_scale", 0.0, 10.0, 0.1, "appearance", 1, "", "gas")


func _fill_rings(body: VBoxContainer) -> void:
	_check_row(body, "Rings", "ring_enabled", "geometry")
	# Ring radii are multiples of the planet radius, so a ring stays a ring when
	# the planet is resized.
	_slider_row(body, "Inner radius", "ring_inner_radius", 0.1, 2.0, 0.01, "geometry", 2, "x", "ring")
	_slider_row(body, "Outer radius", "ring_outer_radius", 0.5, 4.0, 0.01, "geometry", 2, "x", "ring")
	_slider_row(body, "Ring count", "ring_bands", 2, 24, 1, "appearance", 0, " bands", "ring")
	_slider_row(body, "Dust", "ring_dust_density", 0.0, 2.0, 0.01, "appearance", 2, "", "ring")
	_slider_row(body, "Opacity", "ring_opacity", 0.0, 1.0, 0.01, "appearance", 2, "", "ring")
	_color_row(body, "Ring inner", "ring_color_b", "ring")
	_color_row(body, "Ring outer", "ring_color_a", "ring")


func _fill_atmosphere(body: VBoxContainer) -> void:
	# Density is geometry, not appearance: crossing zero adds or removes the glow
	# shell, and refresh_geometry is what notices that.
	_slider_row(body, "Density", "atmosphere_density", 0.0, 1.0, 0.01, "geometry", 2)
	_color_row(body, "Glow", "atmosphere_color", "atmo")
	# Clouds are a separate layer — coverage geometry (0 = no layer), colour appearance.
	_slider_row(body, "Clouds", "cloud_density", 0.0, 1.0, 0.01, "geometry", 2)
	_color_row(body, "Cloud colour", "cloud_color", "atmo")


func _fill_motion(body: VBoxContainer) -> void:
	# Gravity pull matters in flight, not in the editor preview — it is the mass
	# FlightRoot registers the planet's gravity body with.
	_slider_row(body, "Gravity pull", "gravity_mass", 0.0, 100.0, 0.5, "appearance", 1, " M")
	var note := Label.new()
	note.text = "Spin speed is in the Surface section. This mass only affects gravity pull in flight."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", BuilderTheme.text_dim())
	note.add_theme_font_size_override("font_size", 10)
	body.add_child(note)


func _fill_library(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_child(_action_button("New", "Start from the default planet", func() -> void:
		data = _default_planet()
		_sync_widgets()
		_touch_structure()
		_frame_planet(false)
		_notify("New planet")
	))
	row.add_child(_action_button("Reload", "Re-read res://data/planets from disk", func() -> void:
		PlanetLibrary.reset()
		_refresh_library()
		_notify("Library reloaded")
	))
	body.add_child(row)

	var where := Label.new()
	where.text = "Saved in %s" % PlanetLibrary.PLANETS_DIR
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_theme_color_override("font_color", BuilderTheme.text_dim())
	where.add_theme_font_size_override("font_size", 10)
	body.add_child(where)

	_library_list = VBoxContainer.new()
	_library_list.add_theme_constant_override("separation", 2)
	body.add_child(_library_list)
	_refresh_library()


func _refresh_library() -> void:
	if _library_list == null:
		return
	for child in _library_list.get_children():
		child.queue_free()
	var library := PlanetLibrary.instance()
	var ids := library.ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "Nothing saved yet."
		empty.add_theme_color_override("font_color", BuilderTheme.text_dim())
		empty.add_theme_font_size_override("font_size", 11)
		_library_list.add_child(empty)
		return
	for id: String in ids:
		var button := Button.new()
		button.text = library.name_of(id)
		button.tooltip_text = "Load %s.tres" % id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
		button.pressed.connect(func() -> void: _load(id))
		_library_list.add_child(button)


# --- Save and load --------------------------------------------------------

func _save() -> void:
	if data.planet_name.strip_edges() == "":
		data.planet_name = "Untitled"
		_sync_widgets()
	var result := PlanetLibrary.instance().save(data)
	if bool(result["ok"]):
		_refresh_library()
		_update_summaries()
		_notify("Saved %s" % String(result["path"]))
	else:
		_notify(String(result["error"]), "error")


func _load(id: String) -> void:
	var loaded := PlanetLibrary.instance().get_data(id)
	if loaded == null:
		_notify("Could not load %s" % id, "error")
		return
	data = loaded
	_sync_widgets()
	_touch_structure()
	_frame_planet(false)
	_notify("Loaded %s" % data.planet_name)


# --- Randomiser -----------------------------------------------------------

## A whole planet, terrain included. The old randomiser rolled colours, rings and
## radius but left the terrain alone, so every random planet had the same
## coastlines in different paint.
func _randomise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gas := rng.randf() < 0.3

	data.seed_value = rng.randi_range(1, 2147483646)
	data.planet_type = PlanetData.PlanetType.GAS_GIANT if gas else PlanetData.PlanetType.ROCKY
	data.planet_name = _random_name(rng)
	data.planet_radius = snappedf(rng.randf_range(3.0, 12.0), 0.5) if not gas else snappedf(rng.randf_range(9.0, 24.0), 0.5)
	data.sphere_resolution = 48 if gas else 64
	data.rotation_speed = rng.randf_range(0.004, 0.03)

	# One hue family per planet, rather than three independent colours: three
	# random RGB values give a clown, not a world.
	var hue := rng.randf()
	if gas:
		data.primary_color = Color.from_hsv(hue, rng.randf_range(0.25, 0.5), rng.randf_range(0.65, 0.9))
		data.secondary_color = Color.from_hsv(fmod(hue + rng.randf_range(0.02, 0.08), 1.0), rng.randf_range(0.35, 0.6), rng.randf_range(0.3, 0.5))
		data.band_count = snappedf(rng.randf_range(5.0, 16.0), 0.5)
		data.swirl_speed = rng.randf_range(0.05, 0.4)
		data.swirl_scale = snappedf(rng.randf_range(1.5, 6.0), 0.1)
		data.detail_strength = rng.randf_range(0.25, 0.7)
		data.ice_amount = 0.0
	else:
		data.primary_color = Color.from_hsv(hue, rng.randf_range(0.15, 0.4), rng.randf_range(0.45, 0.7))
		data.secondary_color = Color.from_hsv(fmod(hue + rng.randf_range(-0.12, 0.12), 1.0), rng.randf_range(0.25, 0.55), rng.randf_range(0.3, 0.55))
		# Water keeps to the blue-green third of the wheel unless the planet is
		# meant to be strange, which is a fifth of the time.
		var water_hue := rng.randf_range(0.5, 0.62) if rng.randf() > 0.2 else rng.randf()
		data.water_color = Color.from_hsv(water_hue, rng.randf_range(0.5, 0.85), rng.randf_range(0.2, 0.42))
		data.terrain_height = snappedf(rng.randf_range(0.02, 0.14), 0.005)
		data.continent_scale = snappedf(rng.randf_range(0.5, 2.4), 0.05)
		data.mountain_scale = snappedf(rng.randf_range(2.5, 8.0), 0.1)
		data.ridge_strength = snappedf(rng.randf_range(0.2, 0.8), 0.01)
		# An airless rock has no sea at all; everything else keeps its waterline
		# somewhere it can be seen.
		data.sea_level = 0.0 if rng.randf() < 0.2 else snappedf(rng.randf_range(0.3, 0.62), 0.01)
		data.ice_amount = snappedf(rng.randf_range(0.0, 0.85), 0.01)
		data.detail_strength = snappedf(rng.randf_range(0.08, 0.35), 0.01)

	data.atmosphere_density = 0.0 if rng.randf() < 0.3 else snappedf(rng.randf_range(0.2, 0.8), 0.01)
	data.atmosphere_color = Color.from_hsv(fmod(hue + 0.5, 1.0), rng.randf_range(0.3, 0.6), 1.0)

	# Clouds: ~40% of planets have visible cloud cover.
	data.cloud_density = 0.0 if rng.randf() < 0.4 else snappedf(rng.randf_range(0.15, 0.7), 0.01)
	# Cloud colour tinted toward the atmosphere hue.
	data.cloud_color = Color.from_hsv(fmod(hue + rng.randf_range(-0.05, 0.05), 1.0), 0.08, 1.0)
	# Gravity: bigger planets pull harder.
	data.gravity_mass = snappedf(rng.randf_range(2.0, 40.0 if gas else 20.0), 0.5)
	data.ring_enabled = rng.randf() < (0.5 if gas else 0.18)
	if data.ring_enabled:
		data.ring_inner_radius = snappedf(rng.randf_range(1.3, 1.8), 0.01)
		data.ring_outer_radius = data.ring_inner_radius + snappedf(rng.randf_range(0.4, 1.4), 0.01)
		data.ring_dust_density = snappedf(rng.randf_range(0.6, 1.6), 0.01)
		data.ring_opacity = snappedf(rng.randf_range(0.4, 0.9), 0.01)
		data.ring_bands = rng.randi_range(4, 20)
		data.ring_color_a = Color.from_hsv(hue, rng.randf_range(0.1, 0.3), rng.randf_range(0.6, 0.85))
		data.ring_color_b = data.ring_color_a.darkened(rng.randf_range(0.2, 0.45))

	_sync_widgets()
	_touch_structure()
	_frame_planet(false)
	_notify("Rolled %s — %s" % [data.planet_name, data.type_label()])


func _random_name(rng: RandomNumberGenerator) -> String:
	return "%s%s%s" % [
		NAME_HEAD[rng.randi() % NAME_HEAD.size()],
		NAME_TAIL[rng.randi() % NAME_TAIL.size()],
		NAME_SUFFIX[rng.randi() % NAME_SUFFIX.size()],
	]


# --- Syncing widgets from data --------------------------------------------

## Push every value in [member data] back into the widgets. Guarded, because
## assigning to a slider fires value_changed and the handler would write the same
## value straight back — harmless, except it would also queue a mesh rebuild per
## control on every load.
func _sync_widgets() -> void:
	_syncing = true
	for row: Dictionary in _rows:
		(row["slider"] as HSlider).value = float(data.get(String(row["prop"])))
	for prop: String in _widgets:
		var widget: Control = _widgets[prop]
		if widget is ColorPickerButton:
			(widget as ColorPickerButton).color = data.get(prop)
		elif widget is CheckBox:
			(widget as CheckBox).button_pressed = bool(data.get(prop))
		elif widget is LineEdit:
			(widget as LineEdit).text = String(data.get(prop))
		elif widget is SpinBox:
			(widget as SpinBox).value = float(data.get(prop))
		elif widget is OptionButton:
			var option := widget as OptionButton
			option.selected = option.get_item_index(int(data.get(prop)))
	_syncing = false
	_update_summaries()


func _sync_readouts() -> void:
	for row: Dictionary in _rows:
		var value := float(data.get(String(row["prop"])))
		var decimals := int(row["decimals"])
		(row["readout"] as Label).text = String.num(value, decimals) + String(row["suffix"])


func _update_status() -> void:
	# Vertex count from the parameters rather than read back off the mesh: reading
	# it means Mesh.get_faces(), which copies out every triangle, and this line
	# updates on every slider tick.
	var verts := data.sphere_resolution * data.sphere_resolution * 6
	# Short form when the window is narrow. Not only because the keys are useless
	# on a handset: the overlay grows in both directions when its content does not
	# fit, so one line too long for the window pushes the view bar off one edge and
	# the drawer button off the other.
	var hint := (
		"Drag to orbit · pinch to zoom" if _narrow
		else "Drag to orbit · wheel or pinch to zoom · F fits · ] toggles the panel"
	)
	(%StatusLabel as Label).text = hint + "      %s · %s · r %.1f · %d verts" % [
		data.planet_name, data.type_label(), _planet.outer_radius(), verts,
	]


# --- Accessors ------------------------------------------------------------

## The widget bound to a [PlanetData] property, or null.
##
## Rows are built in code rather than in the scene, so there is no node path a
## tool or a test can reach a particular slider by. This is that path.
func widget_for(prop: String) -> Control:
	return _widgets.get(prop, null) as Control


## Apply a pending geometry change now instead of on the debounce.
##
## For anything that needs the mesh to agree with the sliders before the next
## frame — a screenshot tool, a test — rather than a fraction of a second later.
func flush_pending() -> void:
	if _geometry_dirty:
		_geometry_dirty = false
		_apply_geometry()


# --- Layout ---------------------------------------------------------------

func _on_window_resized() -> void:
	# Re-derive the density scale first: on a handset a rotation changes the
	# window size, which changes the stretch factor the correction divides by.
	BuilderTheme.apply_density_scale(get_window())
	var narrow := size.x < NARROW_WIDTH
	if narrow == _narrow and _framed_radius > 0.0:
		return
	_narrow = narrow
	if narrow:
		# A drawer wide enough to read, narrow enough to leave a strip of planet
		# visible behind it so the player keeps their bearings.
		_panel.custom_minimum_size.x = clampf(size.x * 0.82, 260.0, 360.0)
		_panel.visible = false
	else:
		_panel.custom_minimum_size.x = 320.0
		_panel.visible = true
	(%PanelToggle as Button).visible = true
	_update_status()
	# The stage just gained or lost most of the window; framing computed for the
	# old rectangle leaves the planet a thumbnail. Deferred, because the
	# containers have not relaid out at the moment the size changed.
	call_deferred("_frame_planet", false)


## Show or hide the controls. In narrow layout this is the only way to see the
## whole planet, so the button stays visible in both layouts.
func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	call_deferred("_frame_planet", false)


# --- Stage input ----------------------------------------------------------

func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_stage_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_stage_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_on_stage_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_stage_drag(event as InputEventScreenDrag)


func _on_stage_mouse_button(mb: InputEventMouseButton) -> void:
	_mark_active()
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_camera.zoom(1.0)
				_stage.accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_camera.zoom(-1.0)
				_stage.accept_event()
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			_pressed = mb.pressed
			_press_button = mb.button_index
			if mb.pressed:
				_press_pos = mb.position
				_dragging = false
				_stage.grab_focus()
			_stage.accept_event()


func _on_stage_mouse_motion(mm: InputEventMouseMotion) -> void:
	if not _pressed:
		return
	_mark_active()
	if not _dragging:
		if mm.position.distance_to(_press_pos) < DRAG_THRESHOLD:
			return
		_dragging = true
	# Left orbits; middle and right pan, which is the convention every 3D tool
	# the player has already used shares.
	if _press_button == MOUSE_BUTTON_LEFT:
		_camera.orbit(mm.relative)
	else:
		_camera.pan(mm.relative, _stage.size.y)
	_stage.accept_event()


func _on_stage_touch(touch: InputEventScreenTouch) -> void:
	_mark_active()
	if touch.pressed:
		_touches[touch.index] = touch.position
		if _touches.size() == 1:
			_stage.grab_focus()
			_pressed = true
			_press_button = MOUSE_BUTTON_LEFT
			_press_pos = touch.position
			_dragging = false
		elif _touches.size() == 2:
			# A second finger cancels the orbit the first started and begins a
			# pinch, so the planet does not lurch as the gesture changes meaning.
			_pressed = false
			_dragging = false
			var keys := _touches.keys()
			_pinch_distance = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
	else:
		_touches.erase(touch.index)
		if _touches.is_empty():
			_pressed = false
			_dragging = false
			_pinch_distance = 0.0
	_stage.accept_event()


func _on_stage_drag(drag: InputEventScreenDrag) -> void:
	_mark_active()
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		var keys := _touches.keys()
		var a := _touches[keys[0]] as Vector2
		var b := _touches[keys[1]] as Vector2
		var dist := a.distance_to(b)
		if _pinch_distance > 0.0:
			# Pinch zooms and the midpoint's motion pans, so both happen in one
			# gesture the way they do in a map app. The log converts a distance
			# ratio into the zoom steps OrbitCamera counts in.
			var ratio := dist / maxf(_pinch_distance, 1.0)
			_camera.zoom(log(maxf(ratio, 0.01)) / log(0.88) * -1.0)
			_camera.pan(drag.relative * 0.5, _stage.size.y)
		_pinch_distance = dist
		_stage.accept_event()
		return
	if not _pressed:
		return
	if not _dragging:
		if drag.position.distance_to(_press_pos) < DRAG_THRESHOLD:
			return
		_dragging = true
	_camera.orbit(drag.relative)
	_stage.accept_event()


# --- Shortcuts ------------------------------------------------------------

func _shortcut_input(event: InputEvent) -> void:
	# Here rather than in _input because _shortcut_input runs after the focused
	# control's _gui_input: typing "r" into the name field must not roll a new
	# planet out from under the name being typed.
	if event.is_action_pressed("build_frame_ship"):
		_mark_active()
		_frame_planet(false)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_BRACKETRIGHT:
				toggle_panel()
				accept_event()
			KEY_R:
				_randomise()
				accept_event()
