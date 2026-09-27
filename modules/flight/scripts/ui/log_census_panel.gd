## LogCensusPanel: the Log census chip's panel — the live ranking from
## [LogCensus] of what writes to the log the most.
##
## Opening it the first time installs the census, so it counts from then on.
## Refreshes twice a second while open. Reset starts the count again (to
## measure one fight, say); Copy puts the plain-text report on the clipboard.
class_name LogCensusPanel
extends PanelContainer

const REFRESH := 0.5

var _census: LogCensus = null
var _summary: Label
var _list: Label
var _timer := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(620.0, 420.0)
	_census = LogCensus.install()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Log census"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	var note := Label.new()
	note.text = "What writes to the log the most since the count started: lines, " \
		+ "lines per second and size. Errors are grouped by script line, prints by " \
		+ "their text with numbers taken out."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label needs a width, or it wraps at every letter and grows
	# taller than the screen.
	note.custom_minimum_size.x = 580.0
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vbox.add_child(note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vbox.add_child(row)
	var reset := Button.new()
	reset.text = "Reset"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		_census.reset()
		_refresh()
	)
	row.add_child(reset)
	var copy := Button.new()
	copy.text = "Copy report"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_census.report(30)))
	row.add_child(copy)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(580.0, 280.0)
	vbox.add_child(scroll)
	# One row per line, unwrapped: long keys scroll sideways instead.
	_list = Label.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 11)
	var mono := load(MobileHudProfiles.FONT_DIR + "Terminus.ttf") as Font
	if mono != null:
		_list.add_theme_font_override("font", mono)
	scroll.add_child(_list)
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()


func _refresh() -> void:
	if _census == null:
		return
	var t := _census.totals()
	_summary.text = "%d lines · %.1f KB · %.0f s" % [t["lines"], float(t["bytes"]) / 1024.0, t["seconds"]]
	var lines := PackedStringArray()
	for r: Dictionary in _census.top(20):
		lines.append("%5d  %5.1f/s  %5.1f KB   %s" % [r["count"], r["per_sec"], float(r["bytes"]) / 1024.0, r["key"]])
	_list.text = "\n".join(lines) if not lines.is_empty() else "Nothing logged yet."
