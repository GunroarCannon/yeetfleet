## The controls card: everything you can press, and what the words mean.
##
## Opened with `?`, F1, or the ☰ menu. Two jobs, in this order of importance:
## teach the four ideas the builder is built on (mounts, size classes, mirroring and
## joints) and list the shortcuts. A shortcut nobody can find is a shortcut nobody
## uses, and the concepts are what make the shortcuts worth finding.
class_name HelpOverlay
extends Control

const SECTIONS: Array[Dictionary] = [
	{
		"title": "Building",
		"rows": [
			["Drag a card", "From the palette onto a glowing mount"],
			["Tap a mount", "Then tap a card — the no-drag route"],
			["Drag a part", "In Move mode, to a different mount"],
			["Delete", "Remove the selected part and anything on it"],
			["M", "Break or restore mirror symmetry"],
			["\\", "Select the part this one is mounted on"],
			[", .", "Step through empty mounts"],
			["Ctrl+Z / Ctrl+Y", "Undo / redo — drags count as one step"],
			["☰ menu", "Hull, example ships, saving, JSON, contrast"],
			["☰ ▸ Test flight", "Fly what you built, in empty space"],
			["☰ ▸ Walkthrough", "Replay the introduction popups"],
		],
	},
	{
		"title": "Camera and view",
		"rows": [
			["Drag", "Orbit (in Look mode)"],
			["Wheel / pinch", "Zoom"],
			["Middle-drag / two-finger", "Pan"],
			["1 2 3 4 5", "Front, side, top, back, bottom"],
			["F", "Frame the whole ship"],
			["G", "Show every empty mount"],
			["L", "Label the mounts"],
			["P", "Cycle Look → Pose → Move"],
			["[ ]", "Collapse the parts or stats panel"],
			["View menu", "Mounts, mount names and camera angles, under the ship"],
			["? or F1", "This card"],
		],
	},
	{
		"title": "What the words mean",
		"rows": [
			["Mount", "A typed socket. It states which categories and size classes it takes, and refuses anything else with a reason. While you are carrying a part, only the mounts that will accept it are drawn at all — so an unlit hull means this ship has nowhere to put it."],
			["Size class", "Fighter, corvette, hauler, capital. A hauler engine will not bolt into a fighter mount, however much you want it to."],
			["Mirrored", "Fitting one side fills both. Break symmetry when you want an asymmetric build; the pair stays posable within the same limits."],
			["Joint", "Some mounts swivel, tilt, slide or scale within authored limits. Pose mode drags them; the inspector gives you exact numbers."],
			["Required", "The hull will not fly without it. Missing ones are listed in red under the stats."],
			["Channels", "Every part is painted from three ship-wide colours. Change one and the whole fleet livery changes with it."],
		],
	},
	{
		"title": "Does it work?",
		"rows": [
			["Throttle", "Spools the engines you actually fitted. Plumes grow, heat rises."],
			["Hold to fire", "Fires every fitted gun at its own rate, from its own muzzle, spending real capacitor charge."],
			["Brown-out", "Guns that outrun the generator stop firing. That is the trade-off, not a bug."],
		],
	},
]

var _panel: PanelContainer
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# grab_focus() is a no-op without a focus mode, and without focus the Close
	# button cannot be reached by keyboard at all.
	focus_mode = Control.FOCUS_ALL
	_build_ui()
	resized.connect(_fit_to_screen)
	_fit_to_screen()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.accent(), 8, 2)
	)
	_panel.custom_minimum_size = Vector2(0, 0)
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", BuilderTheme.GAP)
	_panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Controls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(80, BuilderTheme.TOUCH_MIN)
	close.tooltip_text = "Esc, ?, or F1"
	close.pressed.connect(close_overlay)
	header.add_child(close)

	# A scroller rather than a fixed card: on a 640px-tall phone in landscape the
	# concept section alone is taller than the screen.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var scroll := _scroll

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 12)
	scroll.add_child(flow)
	for section in SECTIONS:
		flow.add_child(_make_section(section))

	var footer := Label.new()
	footer.text = "Every design autosaves. ☰ ▸ Copy JSON hands the whole ship to anyone as text."
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", BuilderTheme.text_dim())
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)


func _make_section(section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 258
	box.add_theme_constant_override("separation", 3)

	var heading := Label.new()
	heading.text = String(section["title"]).to_upper()
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", BuilderTheme.accent())
	box.add_child(heading)

	for row: Array in section["rows"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)

		var keys := Label.new()
		keys.text = String(row[0])
		keys.custom_minimum_size.x = 104
		keys.add_theme_font_size_override("font_size", 11)
		keys.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
		keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		keys.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(keys)

		var text := Label.new()
		text.text = String(row[1])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 11)
		text.add_theme_color_override("font_color", BuilderTheme.text_dim())
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(text)

	return box


## Size the card to the window rather than to a fixed 560x340. That constant was
## wider than a phone in portrait and taller than one in landscape, which on a
## small screen made the help card the one thing in the builder you could not
## read.
func _fit_to_screen() -> void:
	if _scroll == null:
		return
	var margin := 48.0
	_scroll.custom_minimum_size = Vector2(
		clampf(size.x - margin * 2.0, 240.0, 560.0),
		clampf(size.y - 150.0, 160.0, 380.0)
	)


func toggle() -> void:
	if visible:
		close_overlay()
	else:
		open()


func open() -> void:
	visible = true
	_fit_to_screen()
	# Restyle on open rather than on theme change: the overlay is closed almost all
	# of the time, so there is nothing to repaint until it is asked for.
	_panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.accent(), 8, 2)
	)
	grab_focus()


func close_overlay() -> void:
	visible = false


func _gui_input(event: InputEvent) -> void:
	# Clicking the dim background closes the card — the standard expectation, and on
	# a phone it is a far bigger target than the Close button.
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		close_overlay()
		accept_event()
		return


## Escape is handled here rather than in _gui_input so it works whichever control
## inside the card happens to hold focus.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close_overlay()
		accept_event()
