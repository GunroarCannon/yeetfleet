## HitWords: comic shouts (POW!, BAM!, x3! …) pinned to where they happened.
##
## Each word remembers a world point and is re-projected through the camera
## every frame, so it rides on the hull that was hit or the spot a ship blew
## up instead of sitting over the HUD's health panel. A starburst in the
## mobile HUD's comic style ([MobileHudProfiles]) pops in with an overshoot,
## drifts up a little and fades. Words whose point is behind the camera are
## skipped for that frame.
##
## Marks ([method mark]: an enemy's "!" or "?") use the same layer but a
## speech bubble instead of the starburst, and ride on the ship they belong
## to rather than staying where they popped.
##
## Kept in both HUD layouts (see [method FlightHud.set_mobile_layout]); fed
## through [method FlightRoot.hit_word].
class_name HitWords
extends Control

## Seconds a word lives.
const LIFE := 0.9
## Seconds a mark lives.
const MARK_LIFE := 1.3
## Most words on screen at once; the oldest goes first.
const MAX_WORDS := 6

## Live words: {world, t, word, rot, size, col, seed, life, follow, mark}.
var _words: Array[Dictionary] = []
var _cam_source: Callable


## [param camera_source]: () -> Camera3D, the camera to project through.
func setup(camera_source: Callable) -> void:
	_cam_source = camera_source


func _ready() -> void:
	name = "HitWords"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func pop(word: String, world_pos: Vector3, col: Color, scale := 1.0) -> void:
	_words.append({
		"world": world_pos, "t": 0.0, "word": word, "rot": randf_range(-0.35, 0.35),
		"size": scale, "col": col, "seed": randi(), "life": LIFE, "follow": null, "mark": false,
	})
	if _words.size() > MAX_WORDS:
		_words.pop_front()
	set_process(true)


## A comic [param glyph] ("!" / "?") in a speech bubble over [param node],
## [param height] metres above its origin, riding along with it.
func mark(glyph: String, node: Node3D, height: float, col: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	_words.append({
		"world": node.global_position, "t": 0.0, "word": glyph, "rot": randf_range(-0.25, 0.25),
		"size": 1.0, "col": col, "seed": randi(), "life": MARK_LIFE,
		"follow": weakref(node), "offset": Vector3.UP * height, "mark": true,
	})
	if _words.size() > MAX_WORDS:
		_words.pop_front()
	set_process(true)


func _process(delta: float) -> void:
	# Real time: a word that lands with a freeze or the kill cam still plays.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	for w in _words:
		w["t"] = float(w["t"]) + dt
		var ref: Variant = w.get("follow")
		if ref is WeakRef:
			var n := (ref as WeakRef).get_ref() as Node3D
			if n != null and n.is_inside_tree():
				w["world"] = n.global_position + (w["offset"] as Vector3)
	_words = _words.filter(func(w: Dictionary) -> bool: return float(w["t"]) < float(w["life"]))
	queue_redraw()
	if _words.is_empty():
		set_process(false)


func _draw() -> void:
	if _words.is_empty() or not _cam_source.is_valid():
		return
	var cam := _cam_source.call() as Camera3D
	if cam == null:
		return
	var P := MobileHudProfiles.profile()
	var u := maxf(minf(size.x, size.y), 200.0)
	for w in _words:
		var at: Vector3 = w["world"]
		if cam.is_position_behind(at):
			continue
		if bool(w["mark"]):
			_draw_mark(cam.unproject_position(at), w, P, u)
		else:
			_draw_word(cam.unproject_position(at), w, P, u)


func _draw_word(screen: Vector2, w: Dictionary, P: Dictionary, u: float) -> void:
	var t := float(w["t"]) / LIFE
	var grow := MobileHud._ease_back(clampf(t * 5.0, 0.0, 1.0))
	var alpha := 1.0 - smoothstep(0.65, 1.0, t)
	var r := u * 0.06 * float(w["size"]) * grow
	if r <= 0.5:
		return
	var pos := screen - Vector2(0.0, u * 0.03 + t * u * 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(w["seed"])
	var rot := float(w["rot"])
	var pts := PackedVector2Array()
	var spikes := 14
	for i in spikes * 2:
		var a := rot + TAU * float(i) / float(spikes * 2)
		var k := 1.0 if i % 2 == 0 else 0.6
		pts.append(pos + Vector2.from_angle(a) * r * k * rng.randf_range(0.85, 1.15) * Vector2(1.35, 1.0))
	var edge: Color = P["panel_edge"]
	if edge.a <= 0.0:
		edge = Color(0.05, 0.03, 0.09)
	var shadow := pts.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(u * 0.006, u * 0.006)
	draw_colored_polygon(shadow, Color(edge, 0.9 * alpha))
	draw_colored_polygon(pts, Color(Color("ffe23d"), alpha))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(pos + (p - pos) * 0.72)
	draw_colored_polygon(inner, Color(Color.WHITE, alpha * 0.9))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(edge, alpha), maxf(1.5, u * 0.005), true)
	# The word, centred and turned with the burst.
	var font := MobileHudProfiles.font("title")
	if font == null:
		font = get_theme_default_font()
	var fs := maxi(roundi(r * 0.72 * MobileHudProfiles.style("size_title")), 8)
	var word := String(w["word"])
	var width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := Vector2(width * 0.5, -fs * 0.35)
	draw_set_transform_matrix(Transform2D(rot * 0.5, pos + Vector2(0.0, r * 0.28)) * Transform2D(0.0, -mid))
	var ol := maxi(roundi(u / 180.0), 2)
	draw_string_outline(font, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(edge, alpha))
	draw_string(font, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(w["col"] as Color, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A mark: a white comic speech bubble with a tail down to the ship and the
## glyph in it, bouncing in, wobbling, then shrinking away.
func _draw_mark(screen: Vector2, w: Dictionary, P: Dictionary, u: float) -> void:
	var t := float(w["t"]) / MARK_LIFE
	var grow := MobileHud._ease_back(clampf(t * 4.0, 0.0, 1.0))
	var shrink := 1.0 - smoothstep(0.8, 1.0, t)
	var alpha := 1.0 - smoothstep(0.85, 1.0, t)
	var r := u * 0.038 * grow * lerpf(0.6, 1.0, shrink)
	if r <= 0.5:
		return
	var rot := float(w["rot"]) * sin(float(w["t"]) * 9.0) * 0.6
	var pos := screen - Vector2(0.0, u * 0.05)
	var edge: Color = P["panel_edge"]
	if edge.a <= 0.0:
		edge = Color(0.05, 0.03, 0.09)
	# The bubble: a squashed circle with a wedge tail toward the ship.
	var pts := PackedVector2Array()
	for i in 20:
		var a := rot + TAU * float(i) / 20.0
		pts.append(pos + Vector2(cos(a) * 1.1, sin(a)) * r)
	var tail := PackedVector2Array([
		pos + Vector2(-r * 0.3, r * 0.7), pos + Vector2(r * 0.25, r * 0.75), screen + Vector2(0.0, -u * 0.004),
	])
	var off := Vector2(u * 0.005, u * 0.005)
	var shadow := pts.duplicate()
	for i in shadow.size():
		shadow[i] += off
	draw_colored_polygon(shadow, Color(edge, 0.9 * alpha))
	draw_colored_polygon(tail, Color(edge, alpha))
	draw_colored_polygon(pts, Color(Color.WHITE, alpha))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(edge, alpha), maxf(1.5, u * 0.005), true)
	var font := MobileHudProfiles.font("title")
	if font == null:
		font = get_theme_default_font()
	var fs := maxi(roundi(r * 1.35 * MobileHudProfiles.style("size_title")), 8)
	var glyph := String(w["word"])
	var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform_matrix(Transform2D(rot, pos) * Transform2D(0.0, Vector2(-width * 0.5, fs * 0.35)))
	var ol := maxi(roundi(u / 160.0), 2)
	draw_string_outline(font, Vector2.ZERO, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(edge, alpha))
	draw_string(font, Vector2.ZERO, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(w["col"] as Color, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)
