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
## Swap the face every [constant CYCLE_TIME] seconds (the home screen does).
@export var cycle := false
## The largest type size (store art wants it huge).
@export var max_size := 260

## The graffiti faces the title cycles through: the default spray face, the
## Graffiti face and everything in the graffiti folder.
const FACES: Array[String] = [
	"res://assets/fonts/From Street Art.ttf",
	"res://assets/fonts/Graffiti.ttf",
]
const FACE_DIR := "res://assets/fonts/graffiti"
const CYCLE_TIME := 1.2#4.5
## A face may come back only after this many others have been shown.
const NO_REPEAT := 2

## The face in use (null: the default title face).
var font: Font = null
## Faces shown most recently, newest last (shared, so a trip back to the home
## screen carries on the cycle).
static var _recent: Array[String] = []
static var _faces: Array[String] = []
var _cycle_t := 0.0

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
	if cycle:
		_cycle_t += delta
		if _cycle_t >= CYCLE_TIME:
			_cycle_t = 0.0
			next_face()
	_halo.bob = sin(_t * 1.6) * 0.06
	_halo.queue_redraw()


func _refresh() -> void:
	pivot_offset = size * 0.5
	rotation = deg_to_rad(TILT)
	queue_redraw()
	if _fill != null:
		var m := font_size()
		var base := baseline()
		(_fill.material as ShaderMaterial).set_shader_parameter("y_top", base - m * 0.78)
		(_fill.material as ShaderMaterial).set_shader_parameter("y_bottom", base + m * 0.05)
		_fill.queue_redraw()


func title_font() -> Font:
	return font if font != null else GraffitiStyle.title_font()


## Every face that can spell [member text] (checked once per text).
static func faces(for_text: String) -> Array[String]:
	if not _faces.is_empty():
		return _faces
	var all: Array[String] = FACES.duplicate()
	for f in DirAccess.get_files_at(FACE_DIR):
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in ["ttf", "otf"] and not (FACE_DIR.path_join(name) in all):
			all.append(FACE_DIR.path_join(name))
	for path in all:
		var ft := load(path) as Font if ResourceLoader.exists(path) else null
		if ft == null:
			continue
		var ok := true
		for ch in for_text:
			if not ft.has_char(ch.unicode_at(0)):
				ok = false
		if ok:
			_faces.append(path)
	return _faces


## Spray the title again in another face: a random one not among the last
## [constant NO_REPEAT] shown, with a squash-and-pop.
func next_face() -> void:
	var all := faces(text)
	if all.size() < 2:
		return
	if _recent.is_empty():
		_recent.append(all[0])
	var keep := mini(NO_REPEAT, all.size() - 1)
	var fresh := all.filter(func(p: String) -> bool: return not (p in _recent.slice(-keep)))
	var path: String = fresh[randi() % fresh.size()]
	_recent.append(path)
	if _recent.size() > all.size():
		_recent.pop_front()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.08, 0.6), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		font = load(path) as Font
		_refresh()
		_fill.queue_redraw()
		_halo.queue_redraw())
	tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The type size that fits [member text] into the control's width.
func font_size() -> int:
	var f := title_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var by_width := int(100.0 * (size.x * 0.86) / maxf(w, 1.0))
	return clampi(mini(by_width, int(size.y * 0.72)), 24, max_size)


## Where the text's left end starts (centred in the control).
func text_origin() -> Vector2:
	var f := title_font()
	var fs := font_size()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Vector2((size.x - w) * 0.5, baseline())


func baseline() -> float:
	return size.y * 0.72


## Degrees the whole tag leans (up to the right), so it never reads as a
## ruler-straight line of type.
const TILT := -3.5


## Each letter placed by hand: [char, baseline position, size]. Letters bob
## up and down a little and swell or shrink a touch, like a tag sprayed in
## one go — the same every run (seeded by the text).
func glyphs() -> Array:
	var f := title_font()
	var fs := font_size()
	var o := text_origin()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) + 3
	var out := []
	var x := o.x
	for i in text.length():
		var ch := text.substr(i, 1)
		var k := 1.0 + rng.randf_range(-0.07, 0.08)
		if i == 0:
			k = 1.12
		var gs := int(fs * k)
		var dy := sin(i * 1.9 + 0.6) * fs * 0.045 + rng.randf_range(-0.03, 0.03) * fs
		out.append([ch, Vector2(x, o.y + dy), gs])
		# Advance by the letter at the base size, so the width stays what
		# [method font_size] fitted.
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return out


func _draw() -> void:
	var f := title_font()
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
	var gl := glyphs()
	for g in gl:
		draw_string_outline(f, g[1] + Vector2(fs * 0.05, fs * 0.07), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, g[2], ow, Color(0, 0, 0, 0.6))
	for g in gl:
		draw_string_outline(f, g[1], g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, g[2], ow, GraffitiStyle.INK)
	# A thin cream rim inside the ink, like a sprayed edge.
	for g in gl:
		draw_string_outline(f, g[1], g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, g[2], maxi(2, int(ow * 0.35)), GraffitiStyle.PAPER)
	# Drips: running down from the baseline, ink edged, bulb at the end.
	#Disabled, they don't fit for some fonts
	var n := 0 # int(text.length() * drips)
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
		var f := title.title_font()
		for g in title.glyphs():
			draw_string(f, g[1], g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, g[2], Color.WHITE)


## The halo over the first letter: a tilted glowing ring that floats.
class _Halo:
	extends Control
	var title: GraffitiTitle
	var bob := 0.0

	func _draw() -> void:
		var f := title.title_font()
		var g0: Array = title.glyphs()[0]
		var fs: int = g0[2]
		var gw := f.get_string_size(String(g0[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var o: Vector2 = g0[1]
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
