## PicSet: the level cards' pictures — small baked shots of the game's own
## things (planets, suns, belts, frozen explosions, ships, rings, cargo),
## mixed and matched per level.
##
## A card is two layers: a background by tag (planet, sun, belt, gas, ice,
## nebula) and a subject by tag (boom, ships, pods, rings, carrier) with
## alpha, picked by the level's seeded roll and maybe mirrored. A few dozen
## small pictures make thousands of distinct cards, and every player sees the
## same card for the same level.
##
## The pictures are made by `modules/menu/tools/picset_bake.gd`, which renders
## them from the live game code — rerun it whenever the visuals change and the
## whole campaign's cards update. It writes `manifest.json` listing how many
## of each tag exist; a missing picture falls back to a painted gradient, so
## the map works before the first bake.
class_name PicSet
extends RefCounted

const DIR := "res://assets/picset"
const MANIFEST := DIR + "/manifest.json"

const BG_TAGS: Array[String] = ["planet", "sun", "belt", "gas", "ice", "nebula"]
const FG_TAGS: Array[String] = ["boom", "ships", "pods", "rings", "carrier"]

static var _manifest := {}
static var _manifest_read := false
static var _cache := {}


## The background for [param tag] at [param roll], or a painted fallback.
static func bg(tag: String, roll: int) -> Texture2D:
	var n := count("bg_" + tag)
	if n > 0:
		var t := _load("%s/bg_%s_%d.webp" % [DIR, tag, posmod(roll, n)])
		if t != null:
			return t
	return _fallback_bg(tag, roll)


## The subject layer for [param tag] at [param roll], or null (the card then
## shows only its background).
static func fg(tag: String, roll: int) -> Texture2D:
	var n := count("fg_" + tag)
	if n <= 0:
		return null
	return _load("%s/fg_%s_%d.webp" % [DIR, tag, posmod(int(roll / 7.0), n)])


## A catalogue ship's portrait (three-quarter view, transparent), or null.
static func ship(id: String) -> Texture2D:
	return _load("%s/ship_%s.webp" % [DIR, id])


## How many pictures the manifest lists for a key like "bg_planet".
static func count(key: String) -> int:
	if not _manifest_read:
		_manifest_read = true
		if FileAccess.file_exists(MANIFEST):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if parsed is Dictionary:
				_manifest = parsed
	return int(_manifest.get(key, 0))


## Forget loaded pictures (after a rebake in the same run).
static func reset() -> void:
	_manifest = {}
	_manifest_read = false
	_cache.clear()


## Imported resource first (exports), then the raw file (a fresh bake the
## editor has not imported yet).
static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


const _FALLBACK_COLORS := {
	"planet": [Color("1d3b7a"), Color("58b0ff")],
	"sun": [Color("5a1a08"), Color("ffb13a")],
	"belt": [Color("1c1426"), Color("7d6a8f")],
	"gas": [Color("3a1452"), Color("ff7ad0")],
	"ice": [Color("123447"), Color("c8f4ff")],
	"nebula": [Color("16082e"), Color("9d6bff")],
}


static func _fallback_bg(tag: String, roll: int) -> Texture2D:
	var key := "fallback/%s/%d" % [tag, posmod(roll, 3)]
	if _cache.has(key):
		return _cache[key]
	var cols: Array = _FALLBACK_COLORS.get(tag, _FALLBACK_COLORS["nebula"])
	var g := Gradient.new()
	g.set_color(0, cols[1])
	g.set_color(1, cols[0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.3 + 0.2 * posmod(roll, 3), 0.35)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 128
	tex.height = 96
	_cache[key] = tex
	return tex
