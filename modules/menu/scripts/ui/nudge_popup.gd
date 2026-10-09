## NudgePopup: a one-time hint card over a dimmed screen. The dim blocks every
## other control (they read as greyed out) and one big button is the only way
## on; a cartoon hand bobs at it so the pilot cannot miss where to go.
class_name NudgePopup
extends Control

signal chosen

var _button: SlabButton
var _head: Label
var _text: Label
var _hand := Control.new()
var _t := 0.0


## [param title] / [param body] are the card's words, [param action] the button's.
## [param point] shows the hand at the button.
static func make(title: String, body: String, action: String, point: bool) -> NudgePopup:
	var p := NudgePopup.new()
	p._build(title, body, action, point)
	return p


func _build(title: String, body: String, action: String, point: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	_head = GraffitiStyle.label(title, 44, GraffitiStyle.SUN)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_head)
	_text = GraffitiStyle.label(body, 26)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible = body != ""
	box.add_child(_text)
	_button = SlabButton.new()
	_button.text = action
	_button.fill = GraffitiStyle.LIME
	_button.text_color = GraffitiStyle.INK
	_button.skew = 9.0
	_button.custom_minimum_size = Vector2(300, 84)
	_button.pressed.connect(func() -> void:
		chosen.emit()
		queue_free())
	box.add_child(_button)
	if point:
		_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hand.draw.connect(_draw_hand)
		add_child(_hand)
	_button.grab_focus.call_deferred()


func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)


## Size the card to the screen: a portrait phone is narrower than the card's
## natural 560 px of text.
func _fit() -> void:
	var vp := get_viewport_rect().size
	var w := minf(560.0, vp.x - 48.0)
	var k := clampf(w / 560.0, 0.6, 1.0)
	_head.custom_minimum_size.x = w
	_head.add_theme_font_size_override("font_size", int(44 * k))
	_text.custom_minimum_size.x = w
	_text.add_theme_font_size_override("font_size", int(26 * maxf(k, 0.75)))
	_button.custom_minimum_size = Vector2(minf(300.0, w), 84.0 * maxf(k, 0.8))


func _process(delta: float) -> void:
	_t += delta
	if _hand.get_parent() != null and _button != null:
		var r := _button.get_global_rect()
		# Below the button, bobbing up at it.
		_hand.position = Vector2(r.get_center().x - 30.0, r.end.y + 6.0 + sin(_t * 6.0) * 8.0)
		_hand.queue_redraw()


## The pointing hand: assets/hand.png with its fingertip at the control's origin.
func _draw_hand() -> void:
	var tex := load("res://assets/hand.png") as Texture2D
	if tex == null:
		return
	var h := 96.0
	var w := h * float(tex.get_width()) / float(tex.get_height())
	_hand.draw_texture_rect(tex, Rect2(-Vector2(w, h) * Vector2(0.2, 0.02), Vector2(w, h)), false)
