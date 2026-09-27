## Draws the built-in face stickers and the confetti sprite sheet as PNGs.
##
## The faces are *placeholder art with a contract*: every face is a
## [constant Whimsy.FACE_SIZE]-square RGBA PNG, transparent outside the
## features, face centred, eyes on the upper-middle line. Redraw any of them in
## a paint program at the same size and the game picks the new art up with no
## code change -- this tool only exists so there is something charming there
## until then. Re-running it overwrites the files, so skip it once they have
## been hand-drawn.
##
## Shapes are rendered as signed distances with a one-pixel smoothstep, so the
## edges are anti-aliased without supersampling.
##
## Run:  "$GD" --path . --headless --script modules/whimsy/tools/make_faces.gd
extends SceneTree

const S := 256
const INK := Color("2b1d3a")
const SHINE := Color(1, 1, 1, 1)
const BLUSH := Color(1.0, 0.45, 0.58, 0.55)
const MOUTH := Color("5a1f3a")
const TONGUE := Color("ff7a8f")

## One layer of a drawing: a distance function and the colour it fills with.
var _layers: Array = []


func _init() -> void:
	var dir := "res://modules/whimsy/assets/faces"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var faces := {
		"happy": _happy, "blink": _blink, "grin": _grin, "wink": _wink,
		"ouch": _ouch, "dizzy": _dizzy, "focused": _focused, "sleepy": _sleepy,
	}
	for face_name: String in faces:
		_layers.clear()
		(faces[face_name] as Callable).call()
		var img := _render(S, S, Vector2.ZERO)
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, face_name]))
		print("face: %s" % face_name)
	_confetti_sheet("res://modules/whimsy/assets/confetti_sheet.png")
	quit()


# --- Faces ------------------------------------------------------------------
# Coordinates are in the 256 square. Eyes sit on y≈112, mouth on y≈160.

func _happy() -> void:
	_eye(Vector2(92, 112))
	_eye(Vector2(164, 112))
	_blush()
	_smile(Vector2(128, 150), 30.0, 7.0)


func _blink() -> void:
	_closed_eye(Vector2(92, 116), false)
	_closed_eye(Vector2(164, 116), false)
	_blush()
	_smile(Vector2(128, 150), 30.0, 7.0)


func _grin() -> void:
	_closed_eye(Vector2(92, 112), true)
	_closed_eye(Vector2(164, 112), true)
	_blush()
	_open_mouth(Vector2(128, 152), Vector2(34, 30))


func _wink() -> void:
	_eye(Vector2(92, 112))
	_closed_eye(Vector2(164, 114), true)
	_blush()
	_smile(Vector2(128, 148), 30.0, 7.0)


func _ouch() -> void:
	# >  < squeezed eyes and a small round "oof".
	_chevron(Vector2(92, 112), 1.0)
	_chevron(Vector2(164, 112), -1.0)
	_blush()
	_ellipse(Vector2(128, 166), Vector2(15, 18), MOUTH)
	_ellipse(Vector2(128, 174), Vector2(9, 7), TONGUE)


func _dizzy() -> void:
	_cross(Vector2(92, 112))
	_cross(Vector2(164, 112))
	_wave(Vector2(128, 162), 44.0, 6.0)


func _focused() -> void:
	# Determined: eyes with a slanted brow, a flat brave little smile.
	_eye(Vector2(92, 116))
	_eye(Vector2(164, 116))
	_segment(Vector2(72, 84), Vector2(110, 94), 6.0, INK)
	_segment(Vector2(146, 94), Vector2(184, 84), 6.0, INK)
	_blush()
	_smile(Vector2(128, 146), 20.0, 6.5)


func _sleepy() -> void:
	_closed_eye(Vector2(92, 118), false)
	_closed_eye(Vector2(164, 118), false)
	_blush()
	_ellipse(Vector2(128, 160), Vector2(8, 6), MOUTH)


# --- Features ---------------------------------------------------------------

func _eye(c: Vector2) -> void:
	_ellipse(c, Vector2(15, 21), INK)
	_ellipse(c + Vector2(5, -8), Vector2(5.5, 6.5), SHINE)
	_ellipse(c + Vector2(-5, 9), Vector2(2.5, 2.5), Color(1, 1, 1, 0.8))


## A closed eye: a curve. [param happy] bends it up (^), otherwise down (‿).
func _closed_eye(c: Vector2, happy: bool) -> void:
	if happy:
		_arc(c + Vector2(0, 10), 16.0, deg_to_rad(200.0), deg_to_rad(340.0), 6.5, INK)
	else:
		_arc(c + Vector2(0, -8), 15.0, deg_to_rad(20.0), deg_to_rad(160.0), 6.0, INK)


func _chevron(c: Vector2, facing: float) -> void:
	var tip := c + Vector2(10.0 * facing, 0)
	_segment(c + Vector2(-10.0 * facing, -14), tip, 6.5, INK)
	_segment(c + Vector2(-10.0 * facing, 14), tip, 6.5, INK)


func _cross(c: Vector2) -> void:
	_segment(c + Vector2(-13, -13), c + Vector2(13, 13), 6.0, INK)
	_segment(c + Vector2(-13, 13), c + Vector2(13, -13), 6.0, INK)


func _blush() -> void:
	_ellipse(Vector2(62, 146), Vector2(17, 10), BLUSH)
	_ellipse(Vector2(194, 146), Vector2(17, 10), BLUSH)


func _smile(c: Vector2, radius: float, width: float) -> void:
	_arc(c - Vector2(0, radius * 0.35), radius, deg_to_rad(25.0), deg_to_rad(155.0), width, INK)


func _open_mouth(c: Vector2, r: Vector2) -> void:
	# A "D" on its back: the lower half of an ellipse, flat top.
	var mouth := func(p: Vector2) -> float:
		var d := (p - c) / r
		var ell := (d.length() - 1.0) * minf(r.x, r.y)
		return maxf(ell, c.y - p.y)
	_layers.append([mouth, MOUTH])
	_layers.append([func(p: Vector2) -> float:
		return maxf(_sd_ellipse(p, c + Vector2(0, r.y * 0.62), Vector2(r.x * 0.55, r.y * 0.38)), mouth.call(p)),
		TONGUE])


func _wave(c: Vector2, half_w: float, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		pts.append(c + Vector2(lerpf(-half_w, half_w, t), sin(t * TAU * 1.5) * 7.0))
	_polyline(pts, width, INK)


# --- Primitives ------------------------------------------------------------

func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	_layers.append([func(p: Vector2) -> float: return _sd_ellipse(p, c, r), col])


func _segment(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	_layers.append([func(p: Vector2) -> float: return _sd_segment(p, a, b) - width * 0.5, col])


func _arc(c: Vector2, radius: float, from: float, to: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := lerpf(from, to, float(i) / 16.0)
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	_polyline(pts, width, col)


func _polyline(pts: PackedVector2Array, width: float, col: Color) -> void:
	_layers.append([func(p: Vector2) -> float:
		var best := INF
		for i in pts.size() - 1:
			best = minf(best, _sd_segment(p, pts[i], pts[i + 1]))
		return best - width * 0.5,
		col])


static func _sd_ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	return ((p - c) / r).length() * minf(r.x, r.y) - minf(r.x, r.y)


static func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 0.0001), 0.0, 1.0)
	return (pa - ba * h).length()


## Composite every layer, in order, into a transparent image. [param offset]
## shifts the drawing inside the image, for building sprite sheets.
func _render(w: int, h: int, offset: Vector2, into: Image = null) -> Image:
	var img := into if into != null else Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var p := Vector2(x + 0.5, y + 0.5)
			var px := Vector2i(x + int(offset.x), y + int(offset.y))
			var dst := img.get_pixelv(px)
			for layer: Array in _layers:
				var d: float = (layer[0] as Callable).call(p)
				if d > 1.0:
					continue
				var src: Color = layer[1]
				var a := src.a * clampf(0.5 - d, 0.0, 1.0)
				if a <= 0.0:
					continue
				var out_a := a + dst.a * (1.0 - a)
				var rgb := (Color(src.r, src.g, src.b) * a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - a)) / maxf(out_a, 0.0001)
				dst = Color(rgb.r, rgb.g, rgb.b, out_a)
			img.set_pixelv(px, dst)
	return img


# --- Confetti ---------------------------------------------------------------

## Four 256-square cells in a row: star, heart, smiley ball, wrapped candy.
## Drawn white-ish with their own colours; the particle system tints on top.
func _confetti_sheet(path: String) -> void:
	var img := Image.create(S * 4, S, false, Image.FORMAT_RGBA8)
	# Star.
	_layers.clear()
	var star := func(p: Vector2) -> float:
		var d := p - Vector2(128, 136)
		var ang := atan2(d.y, d.x) + PI * 0.5
		var k := cos(ang * 5.0) * 0.5 + 0.5
		var rad := lerpf(52.0, 104.0, pow(k, 1.6))
		return d.length() - rad
	_layers.append([star, Color("ffd23f")])
	_layers.append([func(p: Vector2) -> float: return star.call(p) + 12.0, Color("ffe680")])
	_eye(Vector2(106, 128))
	_eye(Vector2(150, 128))
	_smile(Vector2(128, 166), 16.0, 6.0)
	_render(S * 4, S, Vector2(0, 0), img)
	# Heart.
	_layers.clear()
	# Inigo Quilez's exact heart distance, origin at the bottom tip, y up.
	var heart := func(p: Vector2) -> float:
		var unit := 200.0
		var q := Vector2(absf(p.x - 128.0), 236.0 - p.y) / unit
		if q.y + q.x > 1.0:
			return ((q - Vector2(0.25, 0.75)).length() - sqrt(2.0) / 4.0) * unit
		var a := (q - Vector2(0.0, 1.0)).length_squared()
		var b := (q - Vector2.ONE * 0.5 * maxf(q.x + q.y, 0.0)).length_squared()
		return sqrt(minf(a, b)) * signf(q.x - q.y) * unit
	_layers.append([heart, Color("ff5d8f")])
	_ellipse(Vector2(96, 104), Vector2(14, 10), Color(1, 1, 1, 0.7))
	_render(S * 4, S, Vector2(S, 0), img)
	# Smiley ball.
	_layers.clear()
	_ellipse(Vector2(128, 128), Vector2(100, 100), Color("ffc93c"))
	_ellipse(Vector2(104, 96), Vector2(26, 18), Color(1, 1, 1, 0.45))
	_eye(Vector2(100, 116))
	_eye(Vector2(156, 116))
	_blush()
	_smile(Vector2(128, 158), 30.0, 8.0)
	_render(S * 4, S, Vector2(S * 2, 0), img)
	# Candy.
	_layers.clear()
	_layers.append([func(p: Vector2) -> float:
		var d := p - Vector2(128, 128)
		var tri := maxf(absf(d.y) - (absf(d.x) - 40.0) * 0.9, 40.0 - absf(d.x))
		return maxf(tri, absf(d.x) - 112.0),
		Color("7ee0ff")])
	_ellipse(Vector2(128, 128), Vector2(58, 58), Color("ff6fb5"))
	_segment(Vector2(92, 104), Vector2(160, 160), 14.0, Color(1, 1, 1, 0.75))
	_render(S * 4, S, Vector2(S * 3, 0), img)
	img.save_png(ProjectSettings.globalize_path(path))
	print("confetti sheet")
