## GraffitiIcons: the token icons — the coin and the stars — as baked 3D
## renders (made by the menu's picture baker, modules/menu/tools/
## picset_bake.gd, from real meshes).
##
## The coin is drawn (a bold gold token, see [method _draw_coin]); the stars are baked.
## Only tokens get a picture. Everything else on the front end is said in
## words: hand-drawn symbols read as clip art, and the user wants any other
## icon to come from assets/icons. An id with no baked picture draws nothing.
class_name GraffitiIcons
extends RefCounted

const BAKED_DIR := "res://assets/picset/icon_%s.webp"
const BAKED := ["star", "star_empty"]

static var _baked := {}


## The baked picture for [param id], or null.
static func baked(id: String) -> Texture2D:
	if not id in BAKED:
		return null
	if not _baked.has(id):
		var path := BAKED_DIR % id
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		_baked[id] = tex
	return _baked[id]


## Draw token [param id] centred on [param c], about [param s] pixels across.
## [param _color] is kept for call-site symmetry; the renders carry their own.
static func draw(ci: CanvasItem, id: String, c: Vector2, s: float, _color := Color.WHITE) -> void:
	if id == "coin":
		_draw_coin(ci, c, s * 1.2)
		return
	var tex := baked(id)
	if tex == null:
		return
	var d := s * 1.2
	ci.draw_texture_rect(tex, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false)


## A bold cartoon coin: ink outline, deep-gold rim, bright face, a raised star
## and a glint, readable at 20 px and still pretty at 200.
static func _draw_coin(ci: CanvasItem, c: Vector2, d: float) -> void:
	var r := d * 0.5
	var ink := Color("2a1636")
	ci.draw_circle(c + Vector2(0.0, r * 0.07), r, Color(0, 0, 0, 0.3))
	ci.draw_circle(c, r, ink)
	ci.draw_circle(c, r * 0.9, Color("d98a00"))
	ci.draw_circle(c, r * 0.76, Color("ffcf2e"))
	ci.draw_arc(c, r * 0.76, 0.0, TAU, 32, Color("b36b00"), maxf(r * 0.06, 1.0), true)
	# The star, debossed: a dark copy below, the bright one over it.
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(Vector2(cos(a), sin(a)) * r * (0.5 if i % 2 == 0 else 0.22))
	var shade := PackedVector2Array()
	var lit := PackedVector2Array()
	for p in pts:
		shade.append(c + p + Vector2(0.0, r * 0.06))
		lit.append(c + p)
	ci.draw_colored_polygon(shade, Color("b36b00"))
	ci.draw_colored_polygon(lit, Color("fff3a8"))
	# The glint on the upper left of the rim.
	ci.draw_arc(c, r * 0.83, PI * 1.05, PI * 1.45, 10, Color(1, 1, 1, 0.85), maxf(r * 0.1, 1.2), true)
