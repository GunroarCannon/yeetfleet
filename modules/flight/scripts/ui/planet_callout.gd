## PlanetCallout: the player's planet pointer. Near a world it rings the
## planet's disc in its colour and sprays its name over it; with the planet
## off screen, a chunky arrow at the screen edge points the way, name beside
## it. Fades in as the ship closes in and out as it leaves, and pops the
## first time each world comes into range.
##
## Replaces the developer's small landmark labels (name + range in 11 px
## type), which only show with debug mode on. Reads the landmarks through
## [member landmarks_source] and the view through [member camera_source].
class_name PlanetCallout
extends Control

## () -> Array[Dictionary]: {name, position, radius, color}.
var landmarks_source := Callable()
## () -> Camera3D.
var camera_source := Callable()

## Shown within this many radii of a world's surface (at least
## [constant MIN_RANGE] metres).
const RANGE_RADII := 2.2
const MIN_RANGE := 1800.0

var _shown := 0.0
var _name := ""
var _pop := 0.0
var _seen := {}
var _target := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var near := _nearest()
	if not near.is_empty():
		_target = near
		var n := String(near["name"])
		if n != _name:
			_name = n
			if not _seen.has(n):
				_seen[n] = true
				_pop = 1.0
	_shown = move_toward(_shown, 1.0 if not near.is_empty() else 0.0, delta / 0.4)
	_pop = maxf(_pop - delta * 2.5, 0.0)
	queue_redraw()


## The world whose surface is nearest, if it is within range; else {}.
func _nearest() -> Dictionary:
	if not landmarks_source.is_valid() or not camera_source.is_valid():
		return {}
	var cam := camera_source.call() as Camera3D
	if cam == null:
		return {}
	var best := {}
	var best_gap := INF
	for lm: Dictionary in landmarks_source.call():
		var r := float(lm.get("radius", 0.0))
		# Planets and moons only: the station is a dot.
		if r < 150.0:
			continue
		var gap := cam.global_position.distance_to(lm["position"]) - r
		if gap < maxf(r * RANGE_RADII, MIN_RANGE) and gap < best_gap:
			best_gap = gap
			best = lm
	return best


func _draw() -> void:
	if _shown <= 0.01 or _target.is_empty() or not camera_source.is_valid():
		return
	var cam := camera_source.call() as Camera3D
	if cam == null:
		return
	var vp := size
	if vp.x < 300.0 or vp.y < 200.0:
		return
	var world: Vector3 = _target["position"]
	var radius := float(_target.get("radius", 100.0))
	var col: Color = _target.get("color", GraffitiStyle.CYAN)
	col = col.lightened(0.25)
	var a := smoothstep(0.0, 1.0, _shown)
	var fs := GraffitiStyle.fit(34, vp)
	var text := String(_target["name"]).to_upper()
	var s := 1.0 + 0.35 * _pop * _pop
	var behind := cam.is_position_behind(world)
	var p := cam.unproject_position(world)
	var margin := 70.0
	var on_screen := not behind and Rect2(Vector2.ZERO, vp).grow(-margin).has_point(p)
	if on_screen:
		# A dashed ring round the disc: its edge projected through the camera.
		var edge := cam.unproject_position(world + cam.global_transform.basis.x * radius)
		var r := clampf(p.distance_to(edge) * 1.04, 40.0, vp.length())
		var dashes := 28
		var spin := Time.get_ticks_msec() * 0.00012
		for i in dashes:
			var a0 := spin + TAU * float(i) / float(dashes)
			draw_arc(p, r, a0, a0 + TAU / float(dashes) * 0.55, 6, Color(GraffitiStyle.INK, 0.6 * a), 7.0, true)
			draw_arc(p, r, a0, a0 + TAU / float(dashes) * 0.55, 6, Color(col, 0.85 * a), 3.5, true)
		# The name over the top of the ring, held on screen.
		var at := Vector2(p.x, clampf(p.y - r - fs * 0.9, fs * 1.6, vp.y - fs))
		at.x = clampf(at.x, fs * 4.0, vp.x - fs * 4.0)
		GraffitiStyle.draw_text(self, text, at, int(fs * s), Color(col, a), 8)
		return
	# Off screen: an arrow on the edge, pointing the way, the name beside it.
	var c := vp * 0.5
	var dir := (p - c)
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := vp * 0.5 - Vector2(margin, margin)
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := c + dir * k
	var side := Vector2(-dir.y, dir.x)
	var arm := fs * 1.1 * s
	var pts := PackedVector2Array([at + dir * arm, at - dir * arm * 0.4 + side * arm * 0.75, at - dir * arm * 0.1, at - dir * arm * 0.4 - side * arm * 0.75])
	draw_colored_polygon(pts, Color(col, a))
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(GraffitiStyle.INK, a), 4.0, true)
	var label_at := at - dir * fs * 2.4
	label_at.x = clampf(label_at.x, fs * 4.0, vp.x - fs * 4.0)
	label_at.y = clampf(label_at.y, fs * 1.6, vp.y - fs)
	GraffitiStyle.draw_text(self, text, label_at, int(fs * 0.8 * s), Color(col, a), 7)
