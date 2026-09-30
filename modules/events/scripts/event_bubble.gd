## A brief, non-blocking HUD bloom that announces an event for ~1.5 seconds.
##
## In accordance with GAMEDOC.md §8 and §9: "A signal appears for ~1.5s, then the
## actual event is visible in the world. If you are interested, fly there. If
## not, keep going. Nothing waits for you."
##
## Drawn in the game's graffiti style: a slanted slab in the event's colour
## with an ink face, a tilted word sticker on its nose (SOS, FIGHT, CARGO —
## [method WorldMarker.word_for], never an emoji), the title in the spray
## face and a short line under it. Slams in, holds, squashes away.
##
## Never captures clicks, pauses gameplay, or opens a quest log.
class_name EventBubble
extends Control

# --- Constants --------------------------------------------------------------

const DURATION_TOTAL := 1.5
const DURATION_IN := 0.2
const DURATION_HOLD := 0.9
const DURATION_OUT := 0.4

# --- Properties -------------------------------------------------------------

## The event's icon key from the incident ("🚨", "🎯"…): shown as its word.
var symbol: String = "🚨"
var title: String = "DISTRESS SIGNAL"
var subtitle: String = ""
var bubble_color: Color = Color(1.0, 0.2, 0.27)

var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	# Drawn over the HUD's panels rather than tucked behind them.
	z_index = 50
	_animate_bloom()


# --- UI Construction --------------------------------------------------------

func _build_ui() -> void:
	var u := _unit()
	var head := GraffitiStyle.head_font()
	var tw := head.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * u)).x
	var sw := head.get_string_size(subtitle.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * u)).x
	custom_minimum_size = Vector2(maxf(tw, sw) + 150.0 * u, 76.0 * u)
	size = custom_minimum_size
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _unit() -> float:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	return clampf(minf(vp.x, vp.y) / 720.0, 0.7, 1.8)


func _draw() -> void:
	var u := _unit()
	var r := Rect2(Vector2(10.0 * u, 8.0 * u), size - Vector2(20.0, 16.0) * u)
	GraffitiStyle.draw_slab(self, r, bubble_color, 16.0 * u, 3.0, Vector2(6, 7) * u)
	var face := r.grow(-5.0 * u)
	face.position.x += 4.0 * u
	GraffitiStyle.draw_slab(self, face, Color(GraffitiStyle.INK, 0.94), 13.0 * u, 0.0, Vector2.ZERO)
	# The word sticker on the nose, tilted.
	var head := GraffitiStyle.head_font()
	var word := WorldMarker.word_for(symbol)
	var wfs := int(17 * u)
	var ww := head.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x + 16.0 * u
	var at := Vector2(r.position.x + 12.0 * u + ww * 0.5, r.get_center().y)
	draw_set_transform(at, -0.14)
	var chip := Rect2(Vector2(-ww * 0.5, -wfs * 0.85), Vector2(ww, wfs * 1.7))
	draw_rect(chip.grow(2.0 * u), GraffitiStyle.INK)
	draw_rect(chip, bubble_color)
	draw_string(head, Vector2(-ww * 0.5 + 8.0 * u, wfs * 0.36), word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs, GraffitiStyle.INK)
	draw_set_transform(Vector2.ZERO)
	# Title and line.
	var tx := at.x + ww * 0.5 + 16.0 * u
	var ty := r.get_center().y + (0.0 if subtitle.is_empty() else -4.0 * u)
	var tfs := int(26 * u)
	draw_string_outline(head, Vector2(tx, ty + tfs * 0.36), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, int(5 * u), GraffitiStyle.INK)
	draw_string(head, Vector2(tx, ty + tfs * 0.36), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color.WHITE)
	if not subtitle.is_empty():
		draw_string(head, Vector2(tx, ty + tfs * 0.36 + 18.0 * u), subtitle.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * u), bubble_color.lightened(0.3))


func _animate_bloom() -> void:
	# Slams in from oversize, holds, squashes away.
	modulate.a = 0.0
	scale = Vector2(1.5, 1.5)
	pivot_offset = size * 0.5

	if not is_inside_tree():
		return

	_tween = create_tween()
	if _tween == null:
		modulate.a = 1.0
		scale = Vector2.ONE
		return

	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, DURATION_IN * 0.6)
	_tween.tween_property(self, "scale", Vector2.ONE, DURATION_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_tween.chain().tween_interval(DURATION_HOLD)
	_tween.chain().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, DURATION_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Scale, not position: the HUD's container owns where it sits.
	_tween.tween_property(self, "scale", Vector2(1.15, 0.6), DURATION_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_tween.chain().tween_callback(queue_free)


# --- Configuration ----------------------------------------------------------

## Configure the bubble with specific icon, title, subtitle and color.
static func create(icon: String, text_title: String, text_sub: String = "", col: Color = Color.WHITE) -> EventBubble:
	var bubble := EventBubble.new()
	bubble.symbol = icon
	bubble.title = text_title
	bubble.subtitle = text_sub
	bubble.bubble_color = col
	return bubble
