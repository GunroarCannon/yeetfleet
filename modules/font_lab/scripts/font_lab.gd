## FontLab (modules/font_lab/font_lab.tscn): try the game's fonts on a mock
## of its UI to see how they feel.
##
## Left: a mock screen — the title, menu slabs, a HUD speed readout, a
## callout, the level report's rows, a tip line. Tap any piece of text and a
## list of every font pops up, each name drawn in its own face; pick one and
## that text switches to it. Right: a scrolling sheet of every font in
## assets/fonts, each showing the same sample line in itself. RESET puts the
## mock back to the game's own fonts.
##
## A dev lab: registered in [ModuleRegistry] as "font_lab", reached from the
## home screen's DEBUG chip (debug builds) or the workbench.
class_name FontLab
extends Control

const FONT_DIR := "res://assets/fonts"
const SAMPLE := "YEETFLEET 2403 KMH — Wreck the mothership!"

## [label text, size, colour, default font ("title", "head" or "")].
const MOCK := [
	["YEETFLEET", 88, "b6ff3a", "title"],
	["CAMPAIGN", 44, "ffffff", "head"],
	["SANDBOX", 40, "15101f", "head"],
	["2403", 64, "ffffff", "head"],
	["KMH", 22, "c8c0dc", "head"],
	["RADAR DOWN!", 38, "ff3a6e", "head"],
	["LEVEL 3  ·  RUSTY HEIST", 30, "ffc61a", "head"],
	["TRIES 4    WINS 2    BEST 1:12", 24, "f3ead6", "head"],
	["TIP: DRAG FROM YOUR SHIP TO SLING IT", 20, "f3ead6", ""],
]

var _fonts: Array[Dictionary] = []
var _mock: VBoxContainer
var _picker: PanelContainer
var _picker_list: VBoxContainer
var _target: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fonts = _load_fonts()
	var bg := ColorRect.new()
	bg.color = Color("1a1030")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 16)
	add_child(split)
	# The mock screen.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	split.add_child(left)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	left.add_child(bar)
	var back := _flat("BACK", 22, GraffitiStyle.SUN, GraffitiStyle.head_font())
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(ModuleRegistry.scene_path("menu")))
	bar.add_child(back)
	var reset := _flat("RESET", 22, GraffitiStyle.CYAN, GraffitiStyle.head_font())
	reset.pressed.connect(_reset)
	bar.add_child(reset)
	bar.add_child(GraffitiStyle.label("TAP ANY TEXT TO CHANGE ITS FONT", 18, GraffitiStyle.DIM, 3))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_mock = VBoxContainer.new()
	_mock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mock.add_theme_constant_override("separation", 10)
	scroll.add_child(_mock)
	_build_mock()
	# Every font in its own face.
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GraffitiStyle.INK, 0.9)
	sb.border_color = GraffitiStyle.HOT
	sb.border_width_left = 4
	sb.set_content_margin_all(12)
	right.add_theme_stylebox_override("panel", sb)
	split.add_child(right)
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	var sheet := VBoxContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("separation", 18)
	rscroll.add_child(sheet)
	for f in _fonts:
		var name := Label.new()
		name.text = String(f["name"])
		name.add_theme_font_override("font", f["font"])
		name.add_theme_font_size_override("font_size", 30)
		name.add_theme_color_override("font_color", GraffitiStyle.LIME)
		sheet.add_child(name)
		var line := Label.new()
		line.text = SAMPLE
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_override("font", f["font"])
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", GraffitiStyle.PAPER)
		sheet.add_child(line)
	# The picker, hidden until a text is tapped.
	_picker = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.05, 0.02, 0.1, 0.97)
	psb.border_color = GraffitiStyle.SUN
	psb.set_border_width_all(4)
	psb.set_content_margin_all(12)
	_picker.add_theme_stylebox_override("panel", psb)
	_picker.visible = false
	add_child(_picker)
	var pscroll := ScrollContainer.new()
	pscroll.custom_minimum_size = Vector2(380, 460)
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker.add_child(pscroll)
	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 6)
	pscroll.add_child(_picker_list)
	for f in _fonts:
		var b := _flat(String(f["name"]), 28, Color.WHITE, f["font"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_apply.bind(f["font"]))
		_picker_list.add_child(b)
	var cancel := _flat("CANCEL", 22, GraffitiStyle.HOT, GraffitiStyle.head_font())
	cancel.pressed.connect(func() -> void: _picker.visible = false)
	_picker_list.add_child(cancel)


## Every .ttf/.otf in [constant FONT_DIR] (exported builds list their
## .import stubs, so those are read back to the font's own name), plus the
## engine's default.
static func _load_fonts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for file in DirAccess.get_files_at(FONT_DIR):
		var f := file.trim_suffix(".import")
		var ext := f.get_extension().to_lower()
		if ext not in ["ttf", "otf"] or seen.has(f):
			continue
		seen[f] = true
		var font := load(FONT_DIR.path_join(f)) as Font
		if font != null:
			out.append({"name": f.get_basename(), "font": font})
	out.append({"name": "Engine default", "font": ThemeDB.fallback_font})
	return out


func _build_mock() -> void:
	for c in _mock.get_children():
		c.queue_free()
	for row in MOCK:
		var kind := String(row[3])
		var font: Font = GraffitiStyle.title_font() if kind == "title" else (GraffitiStyle.head_font() if kind == "head" else ThemeDB.fallback_font)
		var b := _flat(String(row[0]), int(row[1]), Color(String(row[2])), font)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_open_picker.bind(b))
		# The slabs sit on their colour, like the real menu.
		if String(row[0]) in ["CAMPAIGN", "SANDBOX"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = GraffitiStyle.HOT if String(row[0]) == "CAMPAIGN" else GraffitiStyle.CYAN
			sb.skew = Vector2(0.2, 0.0)
			sb.set_content_margin_all(12)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_stylebox_override("pressed", sb)
			b.flat = false
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.custom_minimum_size = Vector2(360, 0)
		_mock.add_child(b)


func _open_picker(target: Button) -> void:
	_target = target
	_picker.visible = true
	_picker.reset_size()
	var vp := get_viewport_rect().size
	_picker.position = ((vp - _picker.get_combined_minimum_size()) * 0.5).max(Vector2.ZERO)


func _apply(font: Font) -> void:
	if _target != null and is_instance_valid(_target):
		_target.add_theme_font_override("font", font)
	_picker.visible = false


func _reset() -> void:
	_picker.visible = false
	_build_mock()


## A text button with no box: tapping the text is the whole point.
func _flat(text: String, size: int, col: Color, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", col)
	b.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	b.add_theme_constant_override("outline_size", maxi(2, size / 8))
	return b
