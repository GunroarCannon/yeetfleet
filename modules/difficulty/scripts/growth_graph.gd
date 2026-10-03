## GrowthGraph: a small line chart of one or more value-by-level series, with
## era boundaries, a movable "this level" marker and a hover read-out.
##
## Each series is `{label, color, fn}` where `fn` is a Callable taking a level
## number and returning the value. Pure drawing, no dependency on the game.
class_name GrowthGraph
extends Control

signal level_picked(level: int)

var series: Array[Dictionary] = []
var max_level := 80
## Level to mark (0 = none).
var marker_level := 0
## First level of each era to draw as a dashed line.
var era_marks: Array[int] = []
## Draw the y axis on a log scale (growth that spans orders of magnitude).
var log_scale := false
var title := ""

var _hover := 0


func _init() -> void:
	custom_minimum_size = Vector2(480.0, 220.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Redraw after changing the series or any value they read.
func refresh() -> void:
	queue_redraw()


func _plot_rect() -> Rect2:
	return Rect2(Vector2(46.0, 22.0), size - Vector2(58.0, 52.0))


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouseMotion
	var b := event as InputEventMouseButton
	var pos := Vector2.ZERO
	if m != null:
		pos = m.position
	elif b != null and b.pressed:
		pos = b.position
	else:
		return
	var r := _plot_rect()
	_hover = clampi(1 + roundi((pos.x - r.position.x) / maxf(r.size.x, 1.0) * float(max_level - 1)), 1, max_level)
	if b != null:
		level_picked.emit(_hover)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = 0
		queue_redraw()


func _draw() -> void:
	var r := _plot_rect()
	var font := ThemeDB.fallback_font
	draw_rect(r, Color(0, 0, 0, 0.35))
	if series.is_empty():
		return
	# Value range over every series.
	var lo := INF
	var hi := -INF
	for s in series:
		for n in range(1, max_level + 1):
			var y := float((s["fn"] as Callable).call(n))
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if log_scale:
		lo = maxf(lo, 0.01)
		hi = maxf(hi, lo * 1.01)
	else:
		lo = minf(lo, 0.0) if lo > 0.0 and lo < hi * 0.5 else lo
		if hi - lo < 0.0001:
			hi = lo + 1.0
	# Grid and axis labels.
	for i in 5:
		var f := float(i) / 4.0
		var gy := r.end.y - f * r.size.y
		draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.08))
		var val := exp(lerpf(log(lo), log(hi), f)) if log_scale else lerpf(lo, hi, f)
		draw_string(font, Vector2(2.0, gy + 4.0), str(snappedf(val, 0.01 if absf(val) < 100.0 else 1.0)), HORIZONTAL_ALIGNMENT_LEFT, 42.0, 11, Color(1, 1, 1, 0.6))
	var step := 10 if max_level <= 100 else 20
	for n in range(step, max_level + 1, step):
		var gx := _x(r, n)
		draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(gx - 8.0, r.end.y + 14.0), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	draw_string(font, Vector2(r.position.x - 4.0, r.end.y + 14.0), "level", HORIZONTAL_ALIGNMENT_RIGHT, 46.0, 11, Color(1, 1, 1, 0.4))
	# Eras.
	for e in era_marks:
		if e <= max_level:
			var ex := _x(r, e)
			var y := r.position.y
			while y < r.end.y:
				draw_line(Vector2(ex, y), Vector2(ex, minf(y + 4.0, r.end.y)), Color(1, 0.8, 0.3, 0.35))
				y += 8.0
	# Series.
	var legend_x := r.position.x + 4.0
	for s in series:
		var pts := PackedVector2Array()
		for n in range(1, max_level + 1):
			pts.append(Vector2(_x(r, n), _y(r, float((s["fn"] as Callable).call(n)), lo, hi)))
		draw_polyline(pts, s["color"], 2.0, true)
		var label := String(s["label"])
		draw_string(font, Vector2(legend_x, 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, s["color"])
		legend_x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	if marker_level > 0:
		var mx := _x(r, marker_level)
		draw_line(Vector2(mx, r.position.y), Vector2(mx, r.end.y), Color(1, 1, 1, 0.5), 1.5)
	if _hover > 0:
		var hx := _x(r, _hover)
		draw_line(Vector2(hx, r.position.y), Vector2(hx, r.end.y), Color(1, 1, 1, 0.25))
		var text := "L%d" % _hover
		var py := r.position.y + 14.0
		for s in series:
			text += "   " + str(snappedf(float((s["fn"] as Callable).call(_hover)), 0.01))
		draw_string(font, Vector2(minf(hx + 6.0, r.end.x - 120.0), py + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _x(r: Rect2, level: int) -> float:
	return r.position.x + float(level - 1) / float(maxi(max_level - 1, 1)) * r.size.x


func _y(r: Rect2, value: float, lo: float, hi: float) -> float:
	var f := (log(maxf(value, 0.0001)) - log(lo)) / (log(hi) - log(lo)) if log_scale else (value - lo) / (hi - lo)
	return r.end.y - clampf(f, 0.0, 1.0) * r.size.y
