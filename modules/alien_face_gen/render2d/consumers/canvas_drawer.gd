class_name CanvasDrawer extends Control

## Renders a DrawList (normalised face-space geometry) scaled and centred to fit
## this control's rectangle. The geometry that the styles emit spans roughly
## [-0.6, 0.6] units, so drawing it 1:1 (as a plain Node2D) lands it in a
## sub-pixel dot; every raster consumer goes through this fit.

var draw_list: DrawList = null

## Fraction of the rect left as empty margin around the fitted face.
var padding := 0.06

## Minimum on-screen (pixel) thickness for outline/hairline strokes, so fine
## unit-space widths don't vanish when a face is shrunk into a small cell.
const _MIN_STROKE_PX := 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if draw_list == null or draw_list.cmds.is_empty():
		return
	if size.x < 2.0 or size.y < 2.0:
		return

	var bounds := draw_list.bounds()
	if bounds.size.x < 0.001 or bounds.size.y < 0.001:
		return

	# Fit the whole face (including ears/neck/crest that poke past the bg block)
	# into the rect with `padding` margin on every side, preserving aspect.
	var pad := size * padding
	var avail := size - pad * 2.0
	var scale := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	var origin := pad + (avail - bounds.size * scale) * 0.5
	draw_set_transform(origin - bounds.position * scale, 0.0, Vector2(scale, scale))

	for c in draw_list.cmds:
		match c["type"]:
			&"poly":
				_poly_safe(c["points"], c["color"])
			&"line":
				_draw_line(c["points"], c["color"], float(c["width"]), scale)


func _draw_line(pts: PackedVector2Array, col: Color, width: float, scale: float) -> void:
	if pts.size() < 2:
		return
	# The canvas transform scales line width too; keep hairline strokes from
	# collapsing below ~1 px on screen at whatever fit we landed on.
	var local_width := maxf(width, _MIN_STROKE_PX / scale)
	draw_polyline(pts, col, local_width, false)


func _poly_safe(pts: PackedVector2Array, col: Color) -> void:
	# Always triangulate for safe concave polygon rendering
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return  # Degenerate; skip rather than draw garbage
	for i in range(0, idx.size(), 3):
		draw_colored_polygon(
			PackedVector2Array(
				[pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]
			), col)
