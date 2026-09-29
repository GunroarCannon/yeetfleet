## GraffitiIcons: the token icons — the coin and the stars — as baked 3D
## renders (made by the menu's picture baker, modules/menu/tools/
## picset_bake.gd, from real meshes).
##
## Only tokens get a picture. Everything else on the front end is said in
## words: hand-drawn symbols read as clip art, and the user wants any other
## icon to come from assets/icons. An id with no baked picture draws nothing.
class_name GraffitiIcons
extends RefCounted

const BAKED_DIR := "res://assets/picset/icon_%s.webp"
const BAKED := ["coin", "star", "star_empty"]

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
	var tex := baked(id)
	if tex == null:
		return
	var d := s * 1.2
	ci.draw_texture_rect(tex, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false)
