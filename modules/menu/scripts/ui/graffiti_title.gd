## GraffitiTitle: the game's name as a spray-painted tag — a mist of paint
## behind, a thick ink outline and drop shadow, a glossy gradient fill,
## paint drips running off the letters, and a halo floating over the first
## letter.
##
## Three layers, back to front: this node (mist, shadow, outline, drips), a
## fill child with the gradient shader, and a halo child. The size follows
## the control's width, so the same node titles a phone and a monitor.
class_name GraffitiTitle
extends Control

const FILL_SHADER := "res://modules/menu/shaders/title_fill.gdshader"

@export var text := "YEETFLEET"
## Paint drips per letter, on average.
@export var drips := 0.8

var _fill: _Fill
var _halo: _Halo
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = _Fill.new()
	_fill.title = self
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(FILL_SHADER) as Shader
	_fill.material = mat
	add_child(_fill)
	_halo = _Halo.new()
	_halo.title = self
	# Behind the letters: drawn before this node's outline and fill.
	_halo.show_behind_parent = true
	_halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_halo)
	resized.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_halo.bob = sin(_t * 1.6) * 0.06
	_halo.queue_redraw()


func _refresh() -> void:
	queue_redraw()
	if _fill != null:
		var m := font_size()
		var base := baseline()
		(_fill.material as ShaderMaterial).set_shader_parameter("y_top", base - m * 0.78)
		(_fill.material as ShaderMaterial).set_shader_parameter("y_bottom", base + m * 0.05)
		_fill.queue_redraw()


## The type size that fits [member text] into the control's width.
func font_size() -> int:
	var f := GraffitiStyle.title_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var by_width := int(100.0 * (size.x * 0.86) / maxf(w, 1.0))
	return clampi(mini(by_width, int(size.y * 0.72)), 24, 260)


## Where the text's left end starts (centred in the control).
func text_origin() -> Vector2:
	var f := GraffitiStyle.title_font()
	var fs := font_size()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Vector2((size.x - w) * 0.5, baseline())


func baseline() -> float:
	return size.y * 0.72


func _draw() -> void:
	var f := GraffitiStyle.title_font()
	var fs := font_size()
	var o := text_origin()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	# Paint mist: soft hot-pink and violet blooms behind the letters.
	for i in 22:
		var p := o + Vector2(rng.randf_range(-0.05, 1.05) * w, -fs * rng.randf_range(0.0, 0.8))
		var col := GraffitiStyle.HOT if i % 3 != 0 else GraffitiStyle.VIOLET
		col.a = 0.13
		draw_circle(p, fs * rng.randf_range(0.18, 0.42), col)
	for i in 60:
		var p2 := o + Vector2(rng.randf_range(-0.08, 1.08) * w, -fs * rng.randf_range(-0.25, 1.0))
		var c2 := GraffitiStyle.HOT
		c2.a = 0.55
		draw_circle(p2, rng.randf_range(1.0, 3.2), c2)
	var ow := maxi(6, int(fs * 0.16))
	draw_string_outline(f, o + Vector2(fs * 0.05, fs * 0.07), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, Color(0, 0, 0, 0.6))
	draw_string_outline(f, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, GraffitiStyle.INK)
	# A thin cream rim inside the ink, like a sprayed edge.
	draw_string_outline(f, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(ow * 0.35)), GraffitiStyle.PAPER)
	# Drips: running down from the baseline, ink edged, bulb at the end.
	var n := int(text.length() * drips)
	for i in n:
		var x := o.x + rng.randf_range(0.04, 0.96) * w
		var len := fs * rng.randf_range(0.12, 0.42)
		var dw := fs * rng.randf_range(0.035, 0.06)
		var top := o.y - fs * 0.12
		var dcol := Color("21c79e")
		draw_rect(Rect2(x - dw * 0.5 - 3, top, dw + 6, len), GraffitiStyle.INK)
		draw_circle(Vector2(x, top + len), dw * 0.85 + 3, GraffitiStyle.INK)
		draw_rect(Rect2(x - dw * 0.5, top, dw, len), dcol)
		draw_circle(Vector2(x, top + len), dw * 0.85, dcol)
		draw_circle(Vector2(x - dw * 0.2, top + len - dw * 0.2), dw * 0.25, Color(1, 1, 1, 0.6))


## The glyph fill, drawn through the gradient shader.
class _Fill:
	extends Control
	var title: GraffitiTitle

	func _draw() -> void:
		var f := GraffitiStyle.title_font()
		draw_string(f, title.text_origin(), title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.font_size(), Color.WHITE)


## The halo over the first letter: a tilted glowing ring that floats.
class _Halo:
	extends Control
	var title: GraffitiTitle
	var bob := 0.0

	func _draw() -> void:
		var f := GraffitiStyle.title_font()
		var fs := title.font_size()
		var first := title.text.substr(0, 1)
		var gw := f.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var o := title.text_origin()
		var c := Vector2(o.x + gw * 0.55, o.y - fs * (0.98 + bob))
		var rx := gw * 0.62
		var ry := fs * 0.12
		var pts := PackedVector2Array()
		var tilt := deg_to_rad(-10.0)
		for i in 49:
			var a := TAU * i / 48.0
			var p := Vector2(cos(a) * rx, sin(a) * ry).rotated(tilt)
			pts.append(c + p)
		var glow := GraffitiStyle.LIME
		glow.a = 0.18
		draw_polyline(pts, glow, fs * 0.2, true)
		draw_polyline(pts, GraffitiStyle.INK, fs * 0.1, true)
		draw_polyline(pts, GraffitiStyle.LIME, fs * 0.055, true)
		var hi := PackedVector2Array()
		for i in 13:
			var a2 := PI + PI * 0.15 + (PI * 0.5) * i / 12.0
			hi.append(c + Vector2(cos(a2) * rx, sin(a2) * ry).rotated(tilt))
		draw_polyline(hi, Color(1, 1, 1, 0.85), fs * 0.018, true)
