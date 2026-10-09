## WalletChip: the pilot's name, stars and coins on one dark slanted slab —
## the top-right strip. Rolls the number when coins change.
##
## Tap the name to rename the pilot (a card with a text box pops over
## everything); tap the coins (the + on the end) to open the store.
class_name WalletChip
extends Control

var _shown := -1.0
var _target := 0.0
var _flash := 0.0
## The three parts' shares of the width: name, stars, coins (and its +).
const WIDTHS: Array[float] = [0.4, 0.24, 0.36]
## The store's + is its own button past the slab's end: this many chip
## heights wide, after a gap of [constant PLUS_GAP] heights.
const PLUS_W := 0.78
const PLUS_GAP := 0.22
## What the coins' + does: set once by [MenuRoot] (open the store).
static var on_store := Callable()
## The rename card, while it is up.
var _rename: CanvasLayer = null
var _name_box: LineEdit = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Campaign.notifier.changed.connect(_refresh)
	_refresh()
	_shown = _target


func _refresh() -> void:
	var before := _target
	_target = float(Campaign.coins())
	if _shown >= 0.0 and _target != before:
		_flash = 1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	accept_event()
	# The three parts, as drawn: name | stars | coins (+).
	if mb.position.x < _slab_width() * WIDTHS[0]:
		GameAudio.ui(&"open")
		_ask_name()
	elif mb.position.x > _slab_width() * (WIDTHS[0] + WIDTHS[1]) and on_store.is_valid():
		GameAudio.ui(&"tap")
		on_store.call()


## The rename card: over everything (its own canvas layer), a text box
## with the name in it, and OK. Enter also takes it; a tap outside cancels.
func _ask_name() -> void:
	if _rename != null and is_instance_valid(_rename):
		return
	var vp := get_viewport_rect().size
	var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
	_rename = CanvasLayer.new()
	_rename.layer = 90
	get_tree().root.add_child(_rename)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.07, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		var b := e as InputEventMouseButton
		if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
			_close_name())
	_rename.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(22 * u))
	var plate := SlabCard.wrap(box, GraffitiStyle.LIME, u)
	# Up the screen, clear of a phone's keyboard.
	plate.position = Vector2(vp.x * 0.5 - 260.0 * u - plate.frame_width() * 0.5, vp.y * 0.08)
	_rename.add_child(plate)
	var head := GraffitiStyle.label("YOUR NAME", int(64 * u), GraffitiStyle.SUN, int(12 * u))
	head.add_theme_font_override("font", GraffitiStyle.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	_name_box = LineEdit.new()
	_name_box.text = Campaign.pilot_name()
	_name_box.max_length = Campaign.NAME_MAX
	_name_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_box.custom_minimum_size = Vector2(520, 76) * u
	_name_box.add_theme_font_override("font", GraffitiStyle.head_font())
	_name_box.add_theme_font_size_override("font_size", int(40 * u))
	_name_box.add_theme_color_override("font_color", GraffitiStyle.LIME)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2b2140")
	sb.border_color = GraffitiStyle.LIME
	sb.set_border_width_all(4)
	sb.set_content_margin_all(10)
	_name_box.add_theme_stylebox_override("normal", sb)
	_name_box.add_theme_stylebox_override("focus", sb)
	_name_box.text_submitted.connect(func(_t: String) -> void: _take_name())
	box.add_child(_name_box)
	var ok := SlabButton.new()
	ok.text = "OK"
	ok.fill = GraffitiStyle.LIME
	ok.text_color = GraffitiStyle.INK
	ok.custom_minimum_size = Vector2(200, 72) * u
	ok.font_size = int(32 * u)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_take_name)
	box.add_child(ok)
	_name_box.grab_focus.call_deferred()
	_name_box.select_all.call_deferred()


func _take_name() -> void:
	if _name_box != null and is_instance_valid(_name_box):
		Campaign.set_pilot_name(_name_box.text)
	GameAudio.ui(&"tap")
	_close_name()


func _close_name() -> void:
	if _rename != null and is_instance_valid(_rename):
		_rename.queue_free()
	_rename = null
	_name_box = null
	queue_redraw()


func _exit_tree() -> void:
	_close_name()


func _process(delta: float) -> void:
	if absf(_shown - _target) > 0.5 or _flash > 0.0:
		_shown = move_toward(_shown, _target, maxf(absf(_target - _shown) * 5.0, 30.0) * delta)
		_flash = maxf(_flash - delta * 1.5, 0.0)
		queue_redraw()


func _draw() -> void:
	# One dark slanted slab, split into three by slanted paint strokes (no
	# boxes): the pilot's tag, the stars, the coins. Numbers in Orange Juice.
	var h := size.y
	var slab_w := _slab_width()
	var r := Rect2(Vector2.ZERO, Vector2(slab_w, h))
	var lean := size.y * 0.3
	GraffitiStyle.draw_slab(self, r, Color("2b2140"), lean, 3.0, Vector2(4, 5))
	var widths := WIDTHS
	var cuts: Array[float] = [0.0]
	for wf in widths:
		cuts.append(cuts[-1] + slab_w * float(wf))
	for k in range(1, 3):
		var cx := cuts[k]
		draw_line(Vector2(cx + lean * 0.35, h * 0.16), Vector2(cx - lean * 0.35, h * 0.84), GraffitiStyle.HOT if k == 1 else GraffitiStyle.CYAN, maxf(3.0, h * 0.07))
	var fs := int(h * 0.44)
	var nf := GraffitiStyle.number_font()
	# A long name shrinks to fit its part rather than spilling out.
	var name := Campaign.pilot_name()
	var nfs := int(h * 0.4)
	var f := GraffitiStyle.head_font()
	var name_w := cuts[1] - cuts[0] - lean - 10.0
	while nfs > 8 and f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > name_w:
		nfs -= 1
	GraffitiStyle.draw_text(self, name, Vector2((cuts[0] + cuts[1]) * 0.5 + lean * 0.1, h * 0.5), nfs, GraffitiStyle.LIME, 5)
	var mid1 := (cuts[1] + cuts[2]) * 0.5
	GraffitiIcons.draw(self, "star", Vector2(mid1 - h * 0.3, h * 0.5), h * 0.62)
	GraffitiStyle.draw_text(self, str(Campaign.total_stars()), Vector2(mid1 + h * 0.3, h * 0.52), fs, GraffitiStyle.SUN, 5, nf)
	# The coins, and past the slab's end a + button that opens the store.
	var coin_x := cuts[2] + h * 0.5
	GraffitiIcons.draw(self, "coin", Vector2(coin_x, h * 0.5), h * 0.62)
	var col := GraffitiStyle.SUN.lerp(GraffitiStyle.LIME, _flash)
	# The number sits between the coin and the +, shrunk to fit if it must.
	var num := str(int(round(_shown)))
	var left := coin_x + h * 0.34
	var right := slab_w - lean * 0.5
	var cfs := fs
	while cfs > 8 and nf.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x > right - left:
		cfs -= 1
	GraffitiStyle.draw_text(self, num, Vector2((left + right) * 0.5, h * 0.52), cfs, col, 5, nf)
	if slab_w < size.x:
		var pr := Rect2(Vector2(size.x - h * PLUS_W, h * 0.06), Vector2(h * PLUS_W, h * 0.88))
		GraffitiStyle.draw_slab(self, pr, GraffitiStyle.LIME, h * 0.16, 3.0, Vector2(3, 4))
		GraffitiStyle.draw_text(self, "+", pr.get_center() + Vector2(0, h * 0.03), int(h * 0.7), GraffitiStyle.INK, 0, nf)


## The slab's width: all of the chip, less the + button and its gap.
func _slab_width() -> float:
	return size.x - size.y * (PLUS_W + PLUS_GAP) if on_store.is_valid() else size.x
