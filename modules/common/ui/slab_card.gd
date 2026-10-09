## SlabCard: the painted plate behind a popup's words. The same leaning slab,
## ink border and drop shadow as the menu's buttons, plus a coloured stripe
## along the top and halftone in the far corner, so a card's text sits on
## something instead of floating over the dimmed screen.
class_name SlabCard
extends MarginContainer

var fill := Color("2b2140")
var accent := GraffitiStyle.SUN
var skew := 18.0
var pad := 28.0


## [param content] inside a new card. [param u] is the screen's UI scale.
static func wrap(content: Control, accent_color: Color, u := 1.0) -> SlabCard:
	var c := SlabCard.new()
	c.accent = accent_color
	c.skew = 18.0 * u
	c.pad = 28.0 * u
	c.add_child(content)
	return c


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The slab leans by half the skew at its top and bottom edges: keep the
	# words clear of the slanted sides.
	var side := int(pad + skew * 0.5)
	add_theme_constant_override("margin_left", side)
	add_theme_constant_override("margin_right", side)
	add_theme_constant_override("margin_top", int(pad + 8.0))
	add_theme_constant_override("margin_bottom", int(pad))


## Width the card adds around its content (both sides).
func frame_width() -> float:
	return 2.0 * (pad + skew * 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	GraffitiStyle.draw_slab(self, r, fill, skew, 4.0, Vector2(9, 10))
	GraffitiStyle.draw_halftone(self, r.grow(-6), Color(accent, 0.13), 11.0, true, skew)
	var pts := GraffitiStyle.slab_points(r, skew)
	var t := clampf(10.0 / maxf(size.y, 1.0), 0.0, 0.5)
	var band := PackedVector2Array([pts[0], pts[1], pts[1].lerp(pts[2], t), pts[0].lerp(pts[3], t)])
	draw_colored_polygon(band, accent)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, GraffitiStyle.INK, 4.0, true)
