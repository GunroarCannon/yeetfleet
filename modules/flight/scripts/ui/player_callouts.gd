## PlayerCallouts: Persona-style shout-outs from the player's own ship.
##
## Events that happen *to* the player — a part torn off, a power-up picked
## up, the shield bubble popping, the hull running low — come out of the
## ship as a ransom-note shout: every letter cut out on its own tilted chip,
## white on ink and ink on white by turns, the first letter big, on an ink
## slab over a jagged burst of the callout's colour, hanging off a tail that
## points at the hull. Two short words at most ([constant MAX_WORDS]). Each one zooms in while it
## fades in, holds, then zooms on further while it fades out. At most
## [constant MAX_SHOWN] at once: a new one pushes the older ones up, and the
## same line twice within [constant REPEAT_MS] is dropped.
##
## Kept in both HUD layouts (see [method FlightHud.set_mobile_layout]); fed
## through [method FlightRoot.player_callout].
class_name PlayerCallouts
extends Control

## Seconds: zoom/fade in, hold, zoom/fade out.
const IN_TIME := 0.18
const HOLD_TIME := 1.4
const OUT_TIME := 0.28
const MAX_SHOWN := 3
## Callouts are shouts, not sentences: longer text is cut to this many words.
const MAX_WORDS := 2
const REPEAT_MS := 1200

## Live callouts: {text, col, t, seed}. Newest last.
var _shown: Array[Dictionary] = []
var _cam_source: Callable
var _ship_source: Callable
var _last_text := ""
var _last_ms := -100000


## [param camera_source]: () -> Camera3D; [param ship_source]: () -> Vector3,
## the point on the ship the tail points at (INF = none).
func setup(camera_source: Callable, ship_source: Callable) -> void:
	_cam_source = camera_source
	_ship_source = ship_source


func _ready() -> void:
	name = "PlayerCallouts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func say(text: String, col := Color("ff2a4a")) -> void:
	var now := Time.get_ticks_msec()
	if text == _last_text and now - _last_ms < REPEAT_MS:
		return
	_last_text = text
	_last_ms = now
	_shown.append({"text": shorten(text), "col": col, "t": 0.0, "seed": randi()})
	while _shown.size() > MAX_SHOWN:
		_shown.pop_front()
	set_process(true)


## [param text] as a shout: upper case, dashes and filler dropped, at most
## [constant MAX_WORDS] words (the "!" is kept).
static func shorten(text: String) -> String:
	var bang := text.ends_with("!")
	var words: Array[String] = []
	for w in text.to_upper().replace("—", " ").replace("-", " ").replace("!", "").split(" ", false):
		if w in ["THE", "A", "AN", "IS", "YOUR"]:
			continue
		words.append(w)
		if words.size() >= MAX_WORDS:
			break
	return " ".join(words) + ("!" if bang else "")


## How many are on screen (for checks).
func shown_count() -> int:
	return _shown.size()


func _life() -> float:
	return IN_TIME + HOLD_TIME + OUT_TIME


func _process(delta: float) -> void:
	# Real time: a callout during a freeze or the kill cam still plays out.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	for c in _shown:
		c["t"] = float(c["t"]) + dt
	_shown = _shown.filter(func(c: Dictionary) -> bool: return float(c["t"]) < _life())
	queue_redraw()
	if _shown.is_empty():
		set_process(false)


func _draw() -> void:
	if _shown.is_empty():
		return
	var u := maxf(minf(size.x, size.y), 200.0)
	# Anchor: up and to the left of the ship, else the upper middle.
	var ship_px := Vector2(size.x * 0.5, size.y * 0.55)
	var cam: Camera3D = _cam_source.call() if _cam_source.is_valid() else null
	var ship: Vector3 = _ship_source.call() if _ship_source.is_valid() else Vector3.INF
	var has_ship := cam != null and ship != Vector3.INF and not cam.is_position_behind(ship)
	if has_ship:
		ship_px = cam.unproject_position(ship)
	var base := ship_px + Vector2(-u * 0.12, -u * 0.2)
	base.x = clampf(base.x, u * 0.3, size.x - u * 0.3)
	base.y = clampf(base.y, u * 0.28, size.y - u * 0.1)
	var font := MobileHudProfiles.font("title")
	if font == null:
		font = get_theme_default_font()
	var n := _shown.size()
	for i in n:
		var c: Dictionary = _shown[i]
		# Newest at the bottom, older ones stacked above it.
		var slot := float(n - 1 - i)
		var at := base - Vector2(-slot * u * 0.03, slot * u * 0.11)
		_draw_callout(c, at, ship_px if (has_ship and i == n - 1) else Vector2.INF, u, font)


func _draw_callout(c: Dictionary, at: Vector2, tail_to: Vector2, u: float, font: Font) -> void:
	var t := float(c["t"])
	var zoom := 1.0
	var alpha := 1.0
	if t < IN_TIME:
		var k := t / IN_TIME
		zoom = lerpf(1.7, 1.0, MobileHud._ease_back(k) if k < 1.0 else 1.0)
		alpha = k
	elif t > IN_TIME + HOLD_TIME:
		var k := clampf((t - IN_TIME - HOLD_TIME) / OUT_TIME, 0.0, 1.0)
		zoom = lerpf(1.0, 1.6, k * k)
		alpha = 1.0 - k
	if alpha <= 0.01:
		return
	var text := String(c["text"])
	var fs := maxi(roundi(u * 0.046 * MobileHudProfiles.style("size_title")), 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["seed"])
	# Lay the letters out first: each on its own chip, jittered.
	var chips: Array[Dictionary] = []
	var x := 0.0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == " ":
			x += fs * 0.45
			continue
		var big := 1.35 if i == 0 else rng.randf_range(0.88, 1.12)
		var cfs := int(fs * big)
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x + fs * 0.24
		chips.append({"ch": ch, "fs": cfs, "x": x, "w": cw, "tilt": rng.randf_range(-0.2, 0.2),
			"dy": rng.randf_range(-0.12, 0.12) * fs, "white": (i + int(c["seed"])) % 2 == 0})
		x += cw * 0.9
	var w := x + fs * 0.4
	var h := fs * 1.7
	var col: Color = c["col"]
	var ink := Color(0.03, 0.02, 0.05)
	# The tail first, under everything, from the slab to the ship.
	if tail_to != Vector2.INF and alpha > 0.2:
		var root_a := at + Vector2(-w * 0.2, h * 0.3)
		var root_b := at + Vector2(-w * 0.05, h * 0.3)
		var tip := at.lerp(tail_to, 0.75)
		draw_colored_polygon(PackedVector2Array([root_a, root_b, tip]), Color(col, alpha * 0.9))
		draw_colored_polygon(PackedVector2Array([root_a + Vector2(3, 0), root_b - Vector2(3, 0), tip.lerp(at, 0.08)]), Color(ink, alpha))
	draw_set_transform_matrix(Transform2D(deg_to_rad(-6.0), Vector2(zoom, zoom), 0.0, at))
	# A jagged burst of the callout's colour, bigger and tilted the other way.
	var burst := PackedVector2Array()
	var spikes := 14
	for k in spikes * 2:
		var a := TAU * k / (spikes * 2)
		var r := (1.0 if k % 2 == 0 else 0.78) * rng.randf_range(0.92, 1.08)
		burst.append(Vector2(cos(a) * (w * 0.62) * r, sin(a) * (h * 0.95) * r) + Vector2(u * 0.01, u * 0.012))
	draw_colored_polygon(burst, Color(col, alpha))
	# The ink slab with a white rim.
	var slab := _jag_quad(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h), int(c["seed"]), u)
	draw_colored_polygon(slab, Color(ink, alpha))
	var edge := slab.duplicate()
	edge.append(slab[0])
	draw_polyline(edge, Color(Color.WHITE, alpha), maxf(2.5, u * 0.006), true)
	# The letters, each on its chip.
	for chip in chips:
		var cx := -w * 0.5 + fs * 0.3 + float(chip["x"])
		var cfs := int(chip["fs"])
		var cw := float(chip["w"])
		var ch_h := cfs * 1.15
		var white := bool(chip["white"])
		var xf := Transform2D(deg_to_rad(-6.0), Vector2(zoom, zoom), 0.0, at) * Transform2D(float(chip["tilt"]), Vector2(cx + cw * 0.5, float(chip["dy"])))
		draw_set_transform_matrix(xf)
		var box := Rect2(Vector2(-cw * 0.5, -ch_h * 0.55), Vector2(cw, ch_h))
		draw_rect(box, Color(Color.WHITE if white else ink, alpha))
		if not white:
			draw_rect(box, Color(Color.WHITE, alpha), false, 2.0)
		var gw := font.get_string_size(String(chip["ch"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var pos := Vector2(-gw * 0.5, cfs * 0.34)
		draw_string(font, pos, String(chip["ch"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(ink if white else Color.WHITE, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A slanted slab with slightly jagged corners, seeded so it doesn't shimmer.
func _jag_quad(p: Vector2, s: Vector2, seed_val: int, u: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var j := u * 0.008
	var lean := s.y * 0.35
	return PackedVector2Array([
		p + Vector2(lean + rng.randf_range(-j, j), rng.randf_range(-j, j)),
		p + Vector2(s.x + rng.randf_range(-j, j), rng.randf_range(-j, 0.0)),
		p + Vector2(s.x - lean + rng.randf_range(-j, j), s.y + rng.randf_range(-j, j)),
		p + Vector2(rng.randf_range(-j, 0.0), s.y + rng.randf_range(0.0, j)),
	])
