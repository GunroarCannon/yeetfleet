## A brief, non-blocking HUD bloom that announces an event for ~1.5 seconds.
##
## In accordance with GAMEDOC.md §8 and §9: "A signal appears for ~1.5s, then the
## actual event is visible in the world. If you are interested, fly there. If
## not, keep going. Nothing waits for you."
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

var symbol: String = "🚨"
var title: String = "DISTRESS SIGNAL"
var subtitle: String = ""
var bubble_color: Color = Color(1.0, 0.2, 0.27)

# --- Internal Nodes ---------------------------------------------------------

var _panel: PanelContainer
var _icon_label: Label
var _title_label: Label
var _subtitle_label: Label
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_animate_bloom()


# --- UI Construction --------------------------------------------------------

func _build_ui() -> void:
	if _panel != null:
		return

	custom_minimum_size = Vector2(320.0, 50.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_panel = PanelContainer.new()
	_panel.name = "BubblePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Style panel box
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.88)
	style.border_color = bubble_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 20.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	_panel.add_child(hbox)

	_icon_label = Label.new()
	_icon_label.name = "Icon"
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_label.text = symbol
	_icon_label.add_theme_font_size_override("font_size", 28)
	_icon_label.add_theme_color_override("font_color", bubble_color)
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(_icon_label)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.text = title.to_upper()
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "Subtitle"
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.text = subtitle
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	_subtitle_label.visible = not subtitle.is_empty()
	vbox.add_child(_subtitle_label)


func _animate_bloom() -> void:
	# Initial appearance
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	pivot_offset = size * 0.5

	if not is_inside_tree():
		return

	_tween = create_tween()
	if _tween == null:
		modulate.a = 1.0
		scale = Vector2.ONE
		return

	_tween.set_parallel(true)
	# Fade in & scale punch
	_tween.tween_property(self, "modulate:a", 1.0, DURATION_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2(1.05, 1.05), DURATION_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Settle back to 1.0 scale
	_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.1)

	# Hold, then fade out
	_tween.chain().tween_interval(DURATION_HOLD)
	_tween.chain().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, DURATION_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "position:y", position.y - 12.0, DURATION_OUT)

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
