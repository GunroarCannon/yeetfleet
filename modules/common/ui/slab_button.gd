## SlabButton: the front end's button — a slanted painted slab with an ink
## border, an offset shadow, halftone dots and an optional icon, that leans
## further and pops when touched.
##
## A [Control], not a [Button]: a Button paints its own text in its native
## draw, which a script's slab would have to be layered under by hand. This
## draws everything itself and handles mouse, touch and keyboard/gamepad
## ([code]ui_accept[/code] with focus) the same way a Button would.
class_name SlabButton
extends Control

signal pressed

@export var text := "":
	set(v):
		text = v
		queue_redraw()
## A smaller second line under [member text] (a price, a hint), or "".
@export var sub := "":
	set(v):
		sub = v
		queue_redraw()
@export var fill := GraffitiStyle.HOT:
	set(v):
		fill = v
		queue_redraw()
@export var text_color := Color.WHITE
## A token id from [GraffitiIcons] (coin, star) drawn at the left end, or "".
@export var icon := "":
	set(v):
		icon = v
		queue_redraw()
@export var icon_color := Color.WHITE
@export var font_size := 30
@export var skew := 18.0
@export var disabled := false:
	set(v):
		disabled = v
		mouse_default_cursor_shape = CURSOR_ARROW if v else CURSOR_POINTING_HAND
		queue_redraw()
## Centre the label (true) or push it right of the icon (false).
@export var centered := true
## A small ink chip over the top-left corner ("MISSION 1" on a comic panel),
## or "".
@export var tag := "":
	set(v):
		tag = v
		queue_redraw()
## Full graffiti dress for the big panels: a two-tone band, a highlight
## streak, paint drips off the bottom, spray speckle and a stacked colour
## shadow on the word. Off for small buttons, where it would be noise.
@export var rich := false:
	set(v):
		rich = v
		queue_redraw()

## Inside a [ScrollContainer]: let the press through so a drag scrolls the
## list (a drag past a few pixels cancels the tap).
@export var pass_drag := false:
	set(v):
		pass_drag = v
		mouse_filter = Control.MOUSE_FILTER_PASS if v else Control.MOUSE_FILTER_STOP

## The [GameAudio] one-shot a press plays (empty: silent).
@export var tap_sound := &"tap"
## Button words that mean "go back": they play [code]back[/code], not [code]tap[/code].
const BACK_WORDS: Array[String] = ["BACK", "CLOSE", "CANCEL", "NO", "SKIP", "✕"]

var _hover := false
var _down := false
var _down_at := Vector2.ZERO
## 0 → 1: eased hover/focus emphasis, animated in [method _process].
var _emph := 0.0
var _pop := 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(220, 64)


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		_wake())
	mouse_exited.connect(func() -> void:
		_hover = false
		_down = false
		_wake()
	)
	focus_entered.connect(_wake)
	focus_exited.connect(_wake)


func _process(delta: float) -> void:
	var want := 1.0 if (_hover or has_focus()) and not disabled else 0.0
	var before := _emph + _pop
	_emph = move_toward(_emph, want, delta * 6.0)
	_pop = move_toward(_pop, 0.0, delta * 4.0)
	if not is_equal_approx(before, _emph + _pop):
		queue_redraw()
	elif is_equal_approx(_emph, want) and _pop <= 0.0:
		# Settled: sleep until hover, focus or a press wakes it.
		set_process(false)


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	var tap := event as InputEventMouseButton
	if tap != null and tap.button_index == MOUSE_BUTTON_LEFT:
		if tap.pressed:
			_down = true
			_down_at = tap.global_position
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			if Rect2(Vector2.ZERO, size).has_point(tap.position):
				_fire()
		if not pass_drag:
			accept_event()
		return
	var drag := event as InputEventMouseMotion
	if drag != null and _down and pass_drag and drag.global_position.distance_to(_down_at) > 14.0:
		# A scroll, not a tap.
		_down = false
		queue_redraw()
	# Touch arrives as the emulated mouse above (the project default), so a
	# ScreenTouch branch here would fire every tap twice.
	if event.is_action_pressed("ui_accept"):
		_fire()
		accept_event()


## The rich dress (see [member rich]), drawn over the fill, under the text.
func _draw_rich(r: Rect2, col: Color, lean: float) -> void:
	# (A darker band across the left end and a dashed light streak along the
	# top used to sit here; they read as stray boxes and marks, so the slab
	# stays one clean colour.)
	# Drips off the bottom edge, in the slab's colour with an ink rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	for i in 3:
		var dx := r.position.x + r.size.x * rng.randf_range(0.3, 0.9)
		var dl := r.size.y * rng.randf_range(0.18, 0.38)
		var dw := r.size.y * 0.07
		draw_rect(Rect2(dx - dw * 0.5 - 2, r.end.y - 3, dw + 4, dl + 2), GraffitiStyle.INK)
		draw_circle(Vector2(dx, r.end.y + dl), dw * 0.7 + 2, GraffitiStyle.INK)
		draw_rect(Rect2(dx - dw * 0.5, r.end.y - 4, dw, dl), col)
		draw_circle(Vector2(dx, r.end.y + dl), dw * 0.7, col)
	# Overspray: a scatter of specks past the right end.
	for i in 14:
		var p := Vector2(r.end.x + rng.randf_range(-lean, lean * 0.4 + 14.0), r.position.y + rng.randf() * r.size.y)
		draw_circle(p, rng.randf_range(1.0, 3.0), col)


func _fire() -> void:
	_pop = 1.0
	_wake()
	if tap_sound != &"":
		# A back or close button left on the default plays the back tones.
		var id := tap_sound
		if id == &"tap" and text.strip_edges().to_upper() in BACK_WORDS:
			id = &"back"
		GameAudio.ui(id)
	pressed.emit()


func _draw() -> void:
	var grow := 3.0 * _emph + 5.0 * _pop - (3.0 if _down else 0.0)
	var r := Rect2(Vector2.ZERO, size).grow(grow)
	var col := fill
	if disabled:
		col = fill.lerp(Color(0.3, 0.28, 0.36), 0.7)
	elif _down:
		col = fill.darkened(0.15)
	var lean := skew + 6.0 * _emph
	GraffitiStyle.draw_slab(self, r, col, lean, 4.0 if not has_focus() else 6.0,
		Vector2(4, 5) if _down else Vector2(7, 8))
	var inner := r.grow(-6.0)
	if rich:
		_draw_rich(r, col, lean)
	GraffitiStyle.draw_halftone(self, inner, col.lightened(0.18), 8.0, true, lean)
	var h := size.y
	var x0 := size.x * 0.5
	if GraffitiIcons.baked(icon) != null:
		GraffitiIcons.draw(self, icon, Vector2(h * 0.55, h * 0.5), h * 0.5)
		if not centered:
			x0 = h * 1.05 + (size.x - h * 1.05) * 0.5
	var tc := text_color if not disabled else Color(0.75, 0.72, 0.8)
	if rich and sub == "":
		# A stacked shadow in the slab's darker tone under the ink shadow.
		var f := GraffitiStyle.head_font()
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var base := Vector2(x0 - w * 0.5, h * 0.5 + f.get_ascent(font_size) * 0.5 - f.get_descent(font_size) * 0.35)
		for k in range(3, 0, -1):
			draw_string_outline(f, base + Vector2(k * 2.5, k * 2.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, col.darkened(0.55))
	if sub == "" and rich:
		# The big panels: a fat ink outline so the word reads on any slab colour.
		GraffitiStyle.draw_text(self, text, Vector2(x0, h * 0.5), font_size, tc, maxi(8, int(font_size * 0.2)))
	elif sub == "":
		GraffitiStyle.draw_text(self, text, Vector2(x0, h * 0.5), font_size, tc)
	else:
		GraffitiStyle.draw_text(self, text, Vector2(x0, h * 0.38), font_size, tc)
		# Sun-yellow reads on dark slabs; on light ones it vanishes, so white.
		var sub_col := GraffitiStyle.SUN if col.get_luminance() < 0.55 else Color.WHITE
		GraffitiStyle.draw_text(self, sub, Vector2(x0, h * 0.76), int(font_size * 0.55), sub_col, 4)
	if tag != "":
		var ts := maxi(11, int(font_size * 0.42))
		var tw := GraffitiStyle.head_font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		var chip := Rect2(Vector2(r.position.x + skew * 0.4, r.position.y - ts * 0.75), Vector2(tw + 18, ts + 10))
		GraffitiStyle.draw_slab(self, chip, GraffitiStyle.INK, 6.0, 2.0, Vector2(3, 3))
		GraffitiStyle.draw_text(self, tag, chip.get_center(), ts, Color.WHITE, 0)
