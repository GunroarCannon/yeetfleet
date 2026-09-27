## Spray-painted targets over every ship the player has tangled with.
##
## A ship the player shot, was shot by, locked, or that came after them — and
## any ship that shoots on sight, the moment it is on screen — gets a
## graffiti target — a wobbly double-stroked ring, tick marks, speckle and a
## paint drip — in its attitude colour: red hostile, orange wary (armed, may
## turn), green friendly, yellow harmless. Drawn on the HUD, so a ship two
## kilometres off is still findable, and held at the screen edge (with the
## distance) when it is out of view. Nearer ships get bigger targets, between
## [member JuiceSettings.marker_min_scale] (at [constant FAR_DIST]) and
## [member JuiceSettings.marker_max_scale] (at [constant NEAR_DIST]).
##
## Each target tweens in from twice its size at zero alpha, and fades out when
## the ship dies or the player has left it alone for [member
## JuiceSettings.interaction_memory] seconds. Every stroke's wobble is seeded
## from the ship, so a target is the same hand-drawn shape frame to frame —
## built once per target at unit size, then only moved and scaled.
class_name InteractionMarkers
extends Control

const COLORS := {
	AiShip.Attitude.HOSTILE: Color("ff3b3b"),
	AiShip.Attitude.WARY: Color("ff9a2e"),
	AiShip.Attitude.FRIENDLY: Color("46e05a"),
	AiShip.Attitude.HARMLESS: Color("ffe14a"),
}
## Target radius on screen, in pixels (scaled with the HUD).
const BASE_RADIUS := 30.0
## Pixels kept clear of the screen edge by a target held there.
const EDGE_INSET := 46.0
const APPEAR_TIME := 0.35
const VANISH_TIME := 0.25
## Distances (metres) at which a target reaches its largest and smallest size.
const NEAR_DIST := 150.0
const FAR_DIST := 2500.0

## One live target. Tweened, so it is an Object with plain properties.
class Marker:
	extends RefCounted
	var ship: AiShip
	var seed := 0
	var scale := 2.0
	var alpha := 0.0
	var color := Color.WHITE
	var leaving := false
	## The sprayed shape at radius 1 round the origin — see [method _build_shape].
	var shape := {}


## Supplies the ships to consider — the flight root's spawner roster.
var ships_source: Callable = Callable()
## Skipped: the ship the player is flying right now.
var exclude_source: Callable = Callable()

var _markers: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var wanted: Dictionary = {}
	if JuiceSettings.interaction_markers and ships_source.is_valid():
		var skip: Variant = exclude_source.call() if exclude_source.is_valid() else null
		# Untyped: the roster can hold a ship freed this frame, and a typed
		# loop variable errors on assignment before the validity test runs.
		var cam := get_viewport().get_camera_3d()
		for ship in ships_source.call():
			if not is_instance_valid(ship) or ship == skip:
				continue
			if not (ship as AiShip).interacted_recently() and not _shoots_on_sight(ship as AiShip, cam):
				continue
			wanted[ship] = true
			if not _markers.has(ship):
				_add(ship)
	for ship: Variant in _markers.keys():
		var m: Marker = _markers[ship]
		if not wanted.has(ship) and not m.leaving:
			_remove(m)
		elif wanted.has(ship) and is_instance_valid(m.ship):
			# Attitude can change (a wary ship opens fire): ease into the colour.
			var target: Color = COLORS.get(m.ship.attitude_to_player(), Color.WHITE)
			m.color = m.color.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	queue_redraw()


## A ship that will open fire on the player unprovoked, in view (or already
## marked, so it doesn't flicker at the screen edge) and within
## [constant FAR_DIST]: marked red at once, before it has done anything.
func _shoots_on_sight(ship: AiShip, cam: Camera3D) -> bool:
	if not JuiceSettings.markers_show_hostile or not ship._alive or not ship.is_inside_tree():
		return false
	if ship.attitude_to_player() != AiShip.Attitude.HOSTILE:
		return false
	if cam == null:
		return true
	if cam.global_position.distance_to(ship.global_position) > FAR_DIST:
		return false
	var marked: bool = _markers.has(ship) and not (_markers[ship] as Marker).leaving
	return marked or cam.is_position_in_frustum(ship.global_position)


func _add(ship: AiShip) -> void:
	var m := Marker.new()
	m.ship = ship
	m.seed = ship.get_instance_id()
	m.shape = _build_shape(m.seed)
	m.color = COLORS.get(ship.attitude_to_player(), Color.WHITE)
	_markers[ship] = m
	# The entrance: from twice the size, invisible, to its own size, solid.
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(m, "scale", 1.0, APPEAR_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "alpha", 1.0, APPEAR_TIME * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _remove(m: Marker) -> void:
	m.leaving = true
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(m, "alpha", 0.0, VANISH_TIME)
	tw.tween_property(m, "scale", 1.4, VANISH_TIME)
	tw.chain().tween_callback(_forget.bind(m))


func _forget(m: Marker) -> void:
	for key: Variant in _markers.keys():
		if _markers[key] == m:
			_markers.erase(key)
			return


## Every live target, for tests: ship -> {alpha, scale, color}.
func snapshot() -> Dictionary:
	var out := {}
	for key: Variant in _markers.keys():
		var m: Marker = _markers[key]
		out[key] = {"alpha": m.alpha, "scale": m.scale, "color": m.color, "leaving": m.leaving}
	return out


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := get_viewport_rect()
	var ui_scale := clampf(rect.size.y / 720.0, 0.7, 2.0)
	for key: Variant in _markers.keys():
		var m: Marker = _markers[key]
		if m.alpha <= 0.01 or not is_instance_valid(m.ship) or not m.ship.is_inside_tree():
			continue
		var world := m.ship.global_position
		var behind := cam.is_position_behind(world)
		var p := cam.unproject_position(world)
		var inner := rect.grow(-EDGE_INSET * ui_scale)
		var on_screen := not behind and inner.has_point(p)
		if not on_screen:
			p = _edge_point(p, behind, inner)
		var dist := cam.global_position.distance_to(world)
		var r := BASE_RADIUS * ui_scale * m.scale * (distance_scale(dist) if on_screen else JuiceSettings.marker_min_scale)
		_draw_graffiti(p, r, m.color, m.alpha, m.shape)
		if not on_screen or dist > 600.0:
			_draw_distance(p + Vector2(0.0, r + 14.0 * ui_scale), dist, m.color, m.alpha, ui_scale)


## Where an off-screen target is held: along the line from the screen centre
## toward it, stopped at [param inner]. A point behind the camera is mirrored,
## since its projection lands on the wrong side.
func _edge_point(p: Vector2, behind: bool, inner: Rect2) -> Vector2:
	var c := inner.get_center()
	var d := p - c
	if behind:
		d = -d
	if d.length_squared() < 1.0:
		d = Vector2(0.0, 1.0)
	var sx := (inner.size.x * 0.5) / maxf(absf(d.x), 0.001)
	var sy := (inner.size.y * 0.5) / maxf(absf(d.y), 0.001)
	return c + d * minf(sx, sy)


## A target's size factor at [param dist] metres: [member
## JuiceSettings.marker_max_scale] at [constant NEAR_DIST] and nearer, easing
## down to [member JuiceSettings.marker_min_scale] at [constant FAR_DIST].
static func distance_scale(dist: float) -> float:
	var t := clampf(inverse_lerp(NEAR_DIST, FAR_DIST, dist), 0.0, 1.0)
	return lerpf(JuiceSettings.marker_max_scale, JuiceSettings.marker_min_scale, sqrt(t))


## The spray-painted target at radius 1, from [param seed_val]: two loose ring
## passes, four crooked ticks, a drip and overspray speckle. Everything wobbles
## by the seeded noise, so it looks hand-sprayed yet holds still.
static func _build_shape(seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var rings: Array[PackedVector2Array] = []
	# Two loose passes of the ring, the second offset — how a can goes round.
	for pass_i in 2:
		var pts := PackedVector2Array()
		var n := 26
		var start := rng.randf() * TAU
		var sweep := TAU * (1.04 if pass_i == 0 else 0.86)
		for i in n + 1:
			var a := start + sweep * float(i) / float(n)
			var rr := (1.0 + rng.randf_range(-0.07, 0.07)) * (1.0 if pass_i == 0 else 0.9)
			pts.append(Vector2(cos(a), sin(a)) * rr)
		rings.append(pts)
	# Crosshair ticks, each slightly off-true.
	var ticks := PackedVector2Array()
	var tilt := rng.randf_range(-0.25, 0.25)
	for k in 4:
		var a := tilt + PI * 0.5 * float(k) + rng.randf_range(-0.08, 0.08)
		var dir := Vector2(cos(a), sin(a))
		ticks.append(dir * rng.randf_range(0.45, 0.6))
		ticks.append(dir * rng.randf_range(1.25, 1.45))
	# A paint drip off the bottom of the ring.
	var drip_x := rng.randf_range(-0.5, 0.5)
	var drip_top := Vector2(drip_x, sqrt(maxf(1.0 - drip_x * drip_x, 0.0)))
	var drip_end := drip_top + Vector2(0.0, rng.randf_range(0.35, 0.8))
	# Overspray speckle: position and dot radius (pixels, not scaled).
	var speckle := PackedVector3Array()
	for i in 12:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.8, 1.35)
		speckle.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.8, 1.9)))
	return {"rings": rings, "ticks": ticks, "drip": PackedVector2Array([drip_top, drip_end]), "speckle": speckle}


## Draw [param shape] (see [method _build_shape]) at [param c], radius [param
## r]. A dark under-stroke keeps it readable on a bright nebula or a sunlit hull.
func _draw_graffiti(c: Vector2, r: float, col: Color, alpha: float, shape: Dictionary) -> void:
	if shape.is_empty():
		return
	var ink := Color(col.r, col.g, col.b, alpha)
	var shade := Color(0.05, 0.03, 0.08, 0.55 * alpha)
	var w := maxf(r * 0.14, 2.5)
	var xf := Transform2D(0.0, Vector2(r, r), 0.0, c)
	var rings: Array = shape["rings"]
	for pass_i in rings.size():
		var pts: PackedVector2Array = xf * (rings[pass_i] as PackedVector2Array)
		draw_polyline(pts, shade, w + 3.0, true)
		draw_polyline(pts, ink, w if pass_i == 0 else w * 0.6, true)
	var ticks: PackedVector2Array = xf * (shape["ticks"] as PackedVector2Array)
	draw_multiline(ticks, shade, w + 3.0, true)
	draw_multiline(ticks, ink, w, true)
	var drip: PackedVector2Array = xf * (shape["drip"] as PackedVector2Array)
	draw_line(drip[0], drip[1], ink, w * 0.7, true)
	draw_circle(drip[1], w * 0.6, ink)
	var fleck := Color(ink, ink.a * 0.7)
	for sp: Vector3 in shape["speckle"]:
		draw_circle(c + Vector2(sp.x, sp.y) * r, sp.z, fleck)
	draw_circle(c, w * 0.55, ink)


func _draw_distance(at: Vector2, dist: float, col: Color, alpha: float, ui_scale: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "%d m" % int(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
	var size := int(13.0 * ui_scale)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	var pos := at + Vector2(-w * 0.5, 0.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.6 * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, alpha))
