## CargoIndicators: edge-of-screen chevrons for cargo pods and packages that are
## out of view, like the markers on enemies. Each gold chevron sits on the
## screen edge toward its pod and shows the distance; pods still in view get none.
class_name CargoIndicators
extends Control

const GOLD := Color("ffd24a")
const EDGE_INSET := 40.0

## Pods to point at (freed or hidden ones are skipped).
var targets: Array[Node3D] = []
var camera: Camera3D = null
var origin_node: Node3D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-EDGE_INSET)
	var centre := size * 0.5
	var font := ThemeDB.fallback_font
	for t in targets:
		if not is_instance_valid(t) or not t.visible:
			continue
		var wp := t.global_position
		var behind := camera.is_position_behind(wp)
		var sp := camera.unproject_position(wp)
		if not behind and Rect2(Vector2.ZERO, size).grow(-8.0).has_point(sp):
			continue
		var dir := sp - centre
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		dir = dir.normalized()
		# Where the ray from the centre leaves the inset rectangle.
		var k := INF
		if absf(dir.x) > 0.001:
			k = minf(k, (rect.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			k = minf(k, (rect.size.y * 0.5) / absf(dir.y))
		var at := centre + dir * k
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([at + dir * 14.0, at - dir * 8.0 + side * 11.0, at - dir * 8.0 - side * 11.0])
		draw_colored_polygon(pts, GOLD)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.8), 2.0)
		var dist := camera.global_position.distance_to(wp)
		var label := "%dm" % roundi(dist)
		var lp := at - dir * 30.0 - Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, -5.0)
		draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
