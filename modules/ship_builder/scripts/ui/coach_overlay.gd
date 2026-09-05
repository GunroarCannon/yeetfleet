## Popup instructions: the walkthrough on first run, and one-shot tips after it.
##
## Separate from [HelpOverlay] because they answer different questions.
## [HelpOverlay] is a reference card — every key, every word, opened deliberately
## by somebody who already knows what they are looking for. This is the thing that
## talks to a player who has just arrived, does not know a mount from a size
## class, and will not press `?` to find out. It appears without being asked for,
## says one idea at a time, and gets out of the way.
##
## The tips work the same way and are the reason this class exists at all rather
## than a static card: the moments where the builder is genuinely confusing are
## *situational* — the first refused drop, the first time Pose mode does nothing
## because the mount is rigid — and a tip that fires exactly then is worth ten
## paragraphs read in advance. Each tip fires once ever and is remembered across
## sessions, so the builder teaches and then shuts up.
class_name CoachOverlay
extends Control

## Where "seen this already" lives. A plain config file rather than the design
## autosave: forgetting your walkthrough progress because you pasted in a new
## ship would be absurd.
const SETTINGS_PATH := "user://ship_builder_ui.cfg"
const SECTION := "coach"

## The first-run walkthrough. Four steps because there are exactly four things
## you must know before the builder makes sense, and a fifth page is a page
## nobody reads.
const STEPS: Array[Dictionary] = [
	{
		"title": "This is your ship",
		"body": "Drag anywhere in the dark area to spin the hull around. "
			+ "Pinch, or roll the wheel, to zoom. Tap a piece to select it — "
			+ "what you tap shows up in the panel on the right.",
		"tip": "Lost the ship off the edge of the screen? Press F, or View ▸ Fit ship in view.",
	},
	{
		"title": "Mounts are the only place parts go",
		"body": "A hull is not a blank canvas. It carries a fixed set of mounts, "
			+ "and each mount states what it takes: a wing mount takes wings, a "
			+ "small gun mount takes small guns. Pick up a part and only the "
			+ "mounts that will actually accept it light up.",
		"tip": "Nothing lit up? That hull has no free mount for the part you are holding — the line under the ship says which of those it is.",
	},
	{
		"title": "Two ways to fit a part",
		"body": "Drag a card from the parts list onto a glowing mount. Or — easier "
			+ "with one thumb — tap a mount first, which cuts the parts list down "
			+ "to just what fits there, then tap the card you want.",
		"tip": "Dropping a part onto a part that is already fitted swaps it out.",
	},
	{
		"title": "Look, Pose, Move",
		"body": "The three buttons under the ship decide what dragging a part does. "
			+ "Look spins the camera. Pose swings a part inside whatever travel "
			+ "its mount allows. Move lifts a fitted part to a different mount.",
		"tip": "Fitting one wing fits both. Press M on a mirrored part to let the two sides differ.",
		"done": "Start building",
	},
]

## Fired when the walkthrough is dismissed, so the caller can resume whatever it
## was going to say.
signal closed

var _title: Label
var _body: RichTextLabel
var _tip: Label
var _progress: Label
var _back: Button
var _next: Button
var _panel: PanelContainer
var _dim: ColorRect

## The pages [method start] shows. Defaults to the builder's own walkthrough;
## the flight module swaps in its own set, because "popup instructions the first
## time you arrive" is the same mechanism in both places and only the words
## differ.
var steps: Array[Dictionary] = STEPS
## Key this walkthrough is remembered under. Separate per module, so seeing the
## builder's introduction does not suppress the flight one.
var walkthrough_id := "walkthrough"

var _step := 0
## "" while the walkthrough is showing; otherwise the id of the live one-shot tip.
var _tip_id := ""
var _seen: Dictionary = {}


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load_seen()
	_build_ui()
	resized.connect(_fit_to_screen)


# --- Persistence ------------------------------------------------------------

func _load_seen() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in cfg.get_section_keys(SECTION) if cfg.has_section(SECTION) else []:
		_seen[String(key)] = true


func _mark_seen(id: String) -> void:
	if _seen.has(id):
		return
	_seen[id] = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, id, true)
	cfg.save(SETTINGS_PATH)


func has_seen(id: String) -> bool:
	return _seen.has(id)


## Forget everything, so the walkthrough and every tip come back. Wired to the
## menu, because "show me that again" is a thing people want and hunting down a
## config file is not an answer.
func reset_all() -> void:
	_seen.clear()
	var cfg := ConfigFile.new()
	cfg.save(SETTINGS_PATH)


# --- Layout -----------------------------------------------------------------

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.accent(), 10, 2)
	)
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", BuilderTheme.GAP + 2)
	_panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)

	# RichTextLabel rather than Label: the body has to reflow inside a card whose
	# width is decided by the screen, and fit_content lets the card be as tall as
	# the words need instead of a guessed minimum.
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = false
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.add_theme_color_override("default_color", BuilderTheme.text())
	column.add_child(_body)

	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 12)
	_tip.add_theme_color_override("font_color", BuilderTheme.accent())
	column.add_child(_tip)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", BuilderTheme.GAP)
	column.add_child(footer)

	_progress = Label.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress.add_theme_font_size_override("font_size", 12)
	_progress.add_theme_color_override("font_color", BuilderTheme.text_dim())
	footer.add_child(_progress)

	_back = _make_button("Back", func() -> void: _go(-1))
	footer.add_child(_back)
	_next = _make_button("Next", func() -> void: _go(1))
	footer.add_child(_next)


## Every button here is a full touch target. This card is the first thing a new
## player touches, and missing the button on a phone is a bad first impression.
func _make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(88, BuilderTheme.TOUCH_MIN)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


## Cap the card to the screen it is on. Sized from the *shorter* of the two
## dimensions as well as the width, so a phone in landscape gets a card that fits
## between the top bar and the thumb controls instead of one that runs off both.
func _fit_to_screen() -> void:
	if _panel == null:
		return
	var pad := float(BuilderTheme.PAD) * 2.0
	_panel.custom_minimum_size = Vector2(
		clampf(size.x - pad * 2.0, 240.0, 520.0), 0.0
	)
	_body.custom_minimum_size = Vector2(0.0, 0.0)
	_panel.size = Vector2.ZERO


# --- The walkthrough --------------------------------------------------------

## Show the walkthrough from the top. [param only_once] makes this a no-op after
## the player has been through it, which is how the automatic first-run call
## avoids being an every-launch nag.
func start(only_once := true) -> void:
	if steps.is_empty():
		return
	if only_once and has_seen(walkthrough_id):
		return
	_tip_id = ""
	_step = 0
	_show_step()
	_open()


func _go(direction: int) -> void:
	if _tip_id != "":
		_dismiss()
		return
	var next := _step + direction
	if next < 0:
		return
	if next >= steps.size():
		_mark_seen(walkthrough_id)
		_dismiss()
		return
	_step = next
	_show_step()


func _show_step() -> void:
	var step: Dictionary = steps[_step]
	_title.text = String(step["title"])
	_body.text = String(step["body"])
	_tip.text = String(step.get("tip", ""))
	_tip.visible = _tip.text != ""
	_progress.text = "%d of %d" % [_step + 1, steps.size()]
	_back.disabled = _step == 0
	_next.text = String(step.get("done", "Next")) if _step == steps.size() - 1 else "Next"


# --- One-shot tips ----------------------------------------------------------

## Pop a single instruction the first time a situation comes up, and never again.
## Returns true if it was actually shown.
func show_tip(id: String, title: String, body: String, tip := "") -> bool:
	if has_seen(id) or visible:
		return false
	_mark_seen(id)
	_tip_id = id
	_title.text = title
	_body.text = body
	_tip.text = tip
	_tip.visible = tip != ""
	_progress.text = ""
	_back.disabled = true
	_next.text = "Got it"
	_open()
	return true


# --- Open / close -----------------------------------------------------------

func _open() -> void:
	# Restyled on open rather than on the theme change, because the card is closed
	# almost all of the time and there is nothing to repaint until it is asked for.
	_panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.accent(), 10, 2)
	)
	visible = true
	_fit_to_screen()
	_next.grab_focus()


func _dismiss() -> void:
	visible = false
	_tip_id = ""
	closed.emit()


func close_overlay() -> void:
	# Dismissing the walkthrough part-way still counts as having seen it. Forcing
	# somebody through four pages they are trying to skip teaches them to skip.
	if _tip_id == "":
		_mark_seen(walkthrough_id)
	_dismiss()


func _gui_input(event: InputEvent) -> void:
	# Tapping the dimmed background closes the card. On a phone it is by far the
	# biggest target on screen.
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		close_overlay()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			close_overlay()
			accept_event()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_RIGHT:
			_go(1)
			accept_event()
		KEY_LEFT:
			_go(-1)
			accept_event()
