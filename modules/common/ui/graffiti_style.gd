## GraffitiStyle: the game's front-end look — sci-fi graffiti. Spray-paint
## title face, chunky comic headings, loud flat colours, thick ink outlines,
## slanted slabs with an offset shadow.
##
## Shared by the menu module and the flight scene's level overlay, so the
## game reads as one thing on either side of the scene change. Statics only;
## fonts are loaded once and cached.
class_name GraffitiStyle
extends RefCounted

## Raymond Larabie's Graffiti Treat (CC0, no rights reserved).
const TITLE_FONT_PATH := "res://assets/fonts/graffiti/Graffiti Treat.otf"
const HEAD_FONT_PATH := "res://assets/fonts/FOO.ttf"
## Numbers (coins, stars, scores) and level names: a bouncy marker face.
const NUMBER_FONT_PATH := "res://assets/fonts/orange juice 2.0.ttf"
## Tips and how-to lines: a chunky arcade face.
const TIP_FONT_PATH := "res://assets/fonts/ka1.ttf"
## Radio/terminal text (NO SIGNAL): a bitmap terminal face.
const TERMINAL_FONT_PATH := "res://assets/fonts/Terminus.ttf"

const INK := Color("15101f")
const PAPER := Color("f3ead6")
const HOT := Color("ff3a6e")
const LIME := Color("b6ff3a")
const CYAN := Color("35e0ff")
const SUN := Color("ffc61a")
const VIOLET := Color("9d6bff")
const ORANGE := Color("ff8a1f")
const DIM := Color("8f86a8")
## The drop shadow every slab and title throws, down-right.
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)

static var _title_font: Font = null
static var _head_font: Font = null
static var _fonts := {}


static func title_font() -> Font:
	if _title_font == null:
		_title_font = load(TITLE_FONT_PATH) as Font
		if _title_font == null:
			_title_font = ThemeDB.fallback_font
	return _title_font


static func head_font() -> Font:
	if _head_font == null:
		_head_font = load(HEAD_FONT_PATH) as Font
		if _head_font == null:
			_head_font = ThemeDB.fallback_font
	return _head_font


## The Orange Juice face, for numbers and level names.
static func number_font() -> Font:
	return _font(NUMBER_FONT_PATH)


## The ka1 face, for tips.
static func tip_font() -> Font:
	return _font(TIP_FONT_PATH)


## The Terminus face, for radio/terminal text.
static func terminal_font() -> Font:
	return _font(TERMINAL_FONT_PATH)


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		var f := load(path) as Font
		_fonts[path] = f if f != null else head_font()
	return _fonts[path]


## A label in the heading face with an ink outline — the one text style used
## for every word on the front end.
static func label(text: String, size: int, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", head_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


## The four corners of a slab leaning right by [param skew] pixels, inside
## [param r]. Top edge shifted right, bottom edge left — a forward lean.
static func slab_points(r: Rect2, skew: float) -> PackedVector2Array:
	var k := skew * 0.5
	return PackedVector2Array([
		Vector2(r.position.x + k, r.position.y),
		Vector2(r.end.x + k, r.position.y),
		Vector2(r.end.x - k, r.end.y),
		Vector2(r.position.x - k, r.end.y),
	])


## Draw a slab: offset shadow, fill, ink border, and a lighter lip along the
## top so it reads as a painted plate rather than a flat box.
static func draw_slab(ci: CanvasItem, r: Rect2, fill: Color, skew := 14.0, border := 4.0, shadow := Vector2(6, 7)) -> void:
	var pts := slab_points(r, skew)
	if shadow != Vector2.ZERO:
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + shadow)
		ci.draw_colored_polygon(sh, SHADOW)
	ci.draw_colored_polygon(pts, fill)
	var lip := PackedVector2Array([
		pts[0], pts[1],
		pts[1].lerp(pts[2], 0.18), pts[0].lerp(pts[3], 0.18),
	])
	ci.draw_colored_polygon(lip, fill.lightened(0.22))
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, INK, border, true)


## Halftone dots over part of a rect — the comic-print texture on slabs.
## [param skew] is the slab's lean: every dot is kept wholly inside the
## slanted outline (dots poking past the ink edge looked like a misprint).
static func draw_halftone(ci: CanvasItem, r: Rect2, color: Color, step := 9.0, from_right := true, skew := 0.0) -> void:
	var clip := slab_points(r.grow(-step * 0.5), skew)
	var y := r.position.y + step * 0.5
	while y < r.end.y:
		var x := r.position.x + step * 0.5
		while x < r.end.x:
			var t := (x - r.position.x) / maxf(r.size.x, 1.0)
			if not from_right:
				t = 1.0 - t
			var rad := step * 0.42 * clampf((t - 0.45) * 2.0, 0.0, 1.0)
			if rad > 0.4 and Geometry2D.is_point_in_polygon(Vector2(x, y), clip):
				ci.draw_circle(Vector2(x, y), rad, color)
			x += step
		y += step


## Text centred on [param at] in the heading face with an ink outline. Dark
## text (ink on a bright slab) gets a thin light rim instead: an ink outline
## round ink letters fills their gaps and the word turns into a blob.
static func draw_text(ci: CanvasItem, text: String, at: Vector2, size: int, color: Color, outline := 6, font: Font = null) -> void:
	var f := font if font != null else head_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base := at + Vector2(-w * 0.5, f.get_ascent(size) * 0.5 - f.get_descent(size) * 0.35)
	if outline > 0 and color.get_luminance() < 0.3:
		ci.draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, outline / 2), Color(1, 1, 1, 0.8))
	elif outline > 0:
		ci.draw_string_outline(f, base + Vector2(2, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, SHADOW)
		ci.draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	ci.draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A readable size for the current window: phones in portrait get smaller
## type so a line still fits.
static func fit(size: int, viewport: Vector2) -> int:
	var short_side := minf(viewport.x, viewport.y)
	var k := clampf(short_side / 720.0, 0.62, 1.25)
	if viewport.x < viewport.y:
		k = clampf(viewport.x / 620.0, 0.55, 1.0)
	return maxi(10, int(round(size * k)))
