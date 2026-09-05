## Transient notices: what just happened, and why something did not.
##
## Every refusal in the builder arrives here with a reason attached — "Talon mount
## takes engine, this is a weapon" rather than a silent no-op — because the socket
## rules are only fair if they explain themselves. The toasts sit over the viewport
## with mouse input passed straight through, so a notice never costs a click.
##
## Repeats coalesce into a counter instead of stacking: dragging a part at a mount
## that will not take it is a thing players do four times in a row, and four
## identical banners is noise where one banner reading "×4" is information.
class_name Toast
extends VBoxContainer

## Beyond this, the oldest notice is retired early — a wall of banners hides the
## ship, which is the thing the player is actually trying to look at.
const MAX_VISIBLE := 4

const DWELL_MIN := 2.2
const DWELL_PER_CHAR := 0.035
const DWELL_MAX := 6.0
## Errors linger: they carry a reason that takes longer to read than "Saved".
const DWELL_ERROR_BONUS := 1.5

const FADE_IN := 0.12
const FADE_OUT := 0.35

var _live: Array[Dictionary] = []


func _ready() -> void:
	# Notices must never intercept a click meant for the ship behind them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 4)
	var root := owner as BuilderRoot
	if root != null:
		root.notice.connect(show_notice)


func show_notice(text: String, kind := "info") -> void:
	if text.strip_edges() == "":
		return
	for entry in _live:
		if String(entry["text"]) == text:
			entry["count"] = int(entry["count"]) + 1
			(entry["label"] as Label).text = "%s %s  ×%d" % [
				_glyph(kind), text, int(entry["count"])
			]
			_arm(entry, kind)
			return

	while _live.size() >= MAX_VISIBLE:
		_retire(_live[0])

	var color := _color(kind)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	panel.add_theme_stylebox_override("panel", _style(color))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(panel)

	var label := Label.new()
	# The glyph is always drawn, not just in high-contrast mode: it costs one
	# character and it is the only part of the styling a colour-blind player can read.
	label.text = "%s %s" % [_glyph(kind), text]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label inside a shrink-to-fit panel has a minimum width of one
	# character, so without a floor here the banner collapses into a one-letter-
	# per-line sliver against the right edge instead of reading as a sentence.
	label.custom_minimum_size.x = clampf(size.x - 16.0, 150.0, 320.0)
	label.max_lines_visible = 3
	panel.add_child(label)

	var entry := {"panel": panel, "label": label, "text": text, "count": 1, "tween": null}
	_live.append(entry)
	_arm(entry, kind)


## (Re)start the dwell-then-fade chain for one notice. A coalesced repeat lands here
## again, which is what makes the timer restart rather than the banner vanish
## mid-sentence.
func _arm(entry: Dictionary, kind: String) -> void:
	var panel := entry["panel"] as PanelContainer
	if panel == null or not is_instance_valid(panel):
		return
	var previous := entry["tween"] as Tween
	if previous != null and previous.is_valid():
		previous.kill()

	var dwell := clampf(DWELL_MIN + String(entry["text"]).length() * DWELL_PER_CHAR, DWELL_MIN, DWELL_MAX)
	if kind == "error":
		dwell += DWELL_ERROR_BONUS

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(dwell)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(func() -> void: _retire(entry))
	entry["tween"] = tween


func _retire(entry: Dictionary) -> void:
	var index := _live.find(entry)
	if index >= 0:
		_live.remove_at(index)
	var tween := entry["tween"] as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	var panel := entry["panel"] as PanelContainer
	if panel != null and is_instance_valid(panel):
		panel.queue_free()


func clear_all() -> void:
	for entry in _live.duplicate():
		_retire(entry)


static func _glyph(kind: String) -> String:
	match kind:
		"good": return "✓"
		"error": return "✗"
		_: return "·"


static func _color(kind: String) -> Color:
	match kind:
		"good": return BuilderTheme.good()
		"error": return BuilderTheme.bad()
		_: return BuilderTheme.text()


static func _style(accent: Color) -> StyleBoxFlat:
	var style := BuilderTheme.flat(BuilderTheme.panel_bg(), accent, 4, 1)
	# A thick left edge in the notice's own colour: readable at a glance from the
	# corner of the eye without needing the text to be coloured strongly enough to
	# hurt legibility.
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.bg_color.a = 0.94
	return style
