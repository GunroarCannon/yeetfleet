## Whimsy: faces on things, emotes for ships, and confetti when they pop.
##
## The module's façade. Everything that puts a smile somewhere goes through
## here. Scenery and the star wear a persistent [code]FaceSticker[/code] with
## [code]react()[/code] / [code]set_base()[/code] / [code]freeze()[/code]; a
## ship instead gets a one-shot [method emote] that pops out, fades, and frees
## itself -- see that method's doc for why ships don't get a resting face.
##
## Face art is a set of [constant FACE_SIZE]-square PNGs in [constant FACE_DIR],
## one per expression (see [constant EXPRESSIONS]). They are placeholders drawn
## by [code]tools/make_faces.gd[/code]; redraw any of them at the same size and
## the game uses the new art as is.
##
## Emits: nothing -- faces and emotes are driven by the caller's own events.
class_name Whimsy
extends RefCounted

const FACE_DIR := "res://modules/whimsy/assets/faces"
const FACE_SIZE := 256
const EXPRESSIONS := ["happy", "blink", "grin", "wink", "ouch", "dizzy", "focused", "sleepy"]
const SHADER_PATH := "res://modules/whimsy/assets/face.gdshader"

const FaceSticker := preload("res://modules/whimsy/scripts/face_sticker.gd")
const ConfettiBurst := preload("res://modules/whimsy/scripts/confetti_burst.gd")
const EmotePopup := preload("res://modules/whimsy/scripts/emote_popup.gd")

## Global switch for every face, emote and confetti pop. Read at attach time;
## flipping it does not strip faces already placed.
static var enabled := true

static var _textures := {}
static var _shader: Shader = null


# --- Art --------------------------------------------------------------------

## The texture for [param expression], or null when the art is missing (so a
## stripped build or a typo shows no face rather than erroring every frame).
static func face_texture(expression: String) -> Texture2D:
	if _textures.has(expression):
		return _textures[expression]
	var path := "%s/%s.png" % [FACE_DIR, expression]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[expression] = tex
	return tex


static func face_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


# --- Scenery faces ------------------------------------------------------------

## A face that turns to watch the camera from the surface of a roundish thing
## of radius [param radius], added under [param host] at its origin.
static func attach_billboard_face(host: Node3D, radius: float, expression := "sleepy") -> Node3D:
	if not enabled or host == null:
		return null
	var face: Node3D = FaceSticker.new()
	face.name = "WhimsyFace"
	face.base = expression
	face.scale = Vector3.ONE * radius
	host.add_child(face)
	face.make_billboard(0.92)
	return face


## A big unlit face for a star, blinking like the rest: [param radius] is the
## star disc's. Drawn in warm ink, pushed just outside the disc toward the
## camera so the glow sphere does not bury it.
static func make_sun_face(radius: float) -> Node3D:
	if not enabled:
		return null
	var face: Node3D = FaceSticker.new()
	face.name = "SunFace"
	face.base = "happy"
	# Well past the disc: a star is a few dozen pixels across and sits inside
	# its own bloom, so a face the size of the disc is washed out entirely.
	face.scale = Vector3.ONE * radius * 3.2
	face.make_billboard(0.4)
	# The ink is near-black; tinted toward burnt orange it reads as part of
	# the star rather than a hole punched through it.
	face.make_unlit(Color(1.5, 0.72, 0.36))
	return face


# --- Ship emotes ---------------------------------------------------------------

## Pop a reaction icon out at [param position] under [param host] (anything in
## the world; like [method confetti] the popup is world-space, not parented to
## the ship, so it is left behind as the ship keeps flying) and let it shoot
## off along [param launch_dir], fade, and free itself.
##
## Replaces the old always-on hull-mounted face for ships: a ship gets a
## reaction to a moment, not a permanent expression. [param expression] reuses
## the same art [method face_texture] serves everything else with; nothing
## here assumes it is a face specifically, so a future non-face icon (an
## exclamation mark, say) drops in the same way.
## [param follow]: the ship the emote belongs to. The popup keeps riding along
## with it (position only) instead of being left behind at [param position]
## by a fast ship. Pass null for something that doesn't move.
static func emote(
	host: Node, position: Vector3, expression: String, launch_dir: Vector3,
	size := 1.0, lifetime := 1.0, follow: Node3D = null
) -> void:
	if not enabled or host == null or not host.is_inside_tree():
		return
	var popup: Node3D = EmotePopup.new()
	popup.name = "Emote"
	host.add_child(popup)
	popup.global_position = position
	if follow != null:
		popup.ride_along(follow)
	popup.launch(expression, launch_dir, size, lifetime)


# --- Confetti -----------------------------------------------------------------

## Pop a burst of smiley stars, hearts, candy and paper at [param position]
## under [param host] (anything in the world; the burst is world-space).
static func confetti(host: Node, position: Vector3, size := 1.0) -> void:
	if not enabled or host == null or not host.is_inside_tree():
		return
	var burst: Node3D = ConfettiBurst.new()
	burst.name = "Confetti"
	host.add_child(burst)
	burst.global_position = position
	burst.setup(size)
