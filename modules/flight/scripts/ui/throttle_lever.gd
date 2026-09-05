## The throttle: a vertical lever from full reverse to full ahead.
##
## Drawn as a tape rather than a slider because it has to show two numbers at
## once — where the lever is, and how fast the ship actually is. With flight
## assist off those diverge constantly, and a plain slider hides exactly the
## information that makes Newtonian flight readable.
class_name ThrottleLever
extends Control

signal changed(value: float)

## Lowest position of the lever. Reverse exists for docking, so it is a small
## part of the travel rather than a mirror of the forward half.
const MIN_VALUE := -0.35
const TRACK_WIDTH := 26.0
## Steps the keyboard and the mouse wheel move the lever by.
const STEP := 0.1
## Snap radius around zero and one, so a thumb can find "stopped" and "full".
const DETENT := 0.045

## Lever position, [constant MIN_VALUE]..1.
var value := 0.0
## Actual speed as a fraction of top speed, for the second needle. Signed.
var actual := 0.0

var _dragging := false
var _pointer := -1


func _ready() -> void:
	custom_minimum_size = Vector2(64, 168)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Throttle — drag, or W and S"


func set_value_from(v: float, notify := true) -> void:
	var next := _snap(clampf(v, MIN_VALUE, 1.0))
	if is_equal_approx(next, value):
		return
	value = next
	queue_redraw()
	if notify:
		changed.emit(value)


func nudge(amount: float) -> void:
	set_value_from(value + amount)


## Called every frame with the ship's real speed fraction. Cheap: a redraw only
## happens when the needle would visibly move.
func set_actual(fraction: float) -> void:
	if absf(fraction - actual) < 0.004:
		return
	actual = fraction
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					nudge(STEP)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					nudge(-STEP)
					accept_event()
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed:
					_apply_from_y(mb.position.y)
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_apply_from_y((event as InputEventMouseMotion).position.y)
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_pointer = st.index
			_apply_from_y(st.position.y)
		elif st.index == _pointer:
			_pointer = -1
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _pointer:
			_apply_from_y(sd.position.y)
			accept_event()


func _apply_from_y(y: float) -> void:
	var t := 1.0 - clampf(y / maxf(size.y, 1.0), 0.0, 1.0)
	set_value_from(lerpf(MIN_VALUE, 1.0, t))


## Pull the lever onto stop and full when it lands close, so those two positions
## can be hit without looking at the widget.
func _snap(v: float) -> float:
	if absf(v) < DETENT:
		return 0.0
	if absf(v - 1.0) < DETENT:
		return 1.0
	return v


func _y_for(v: float) -> float:
	var t := inverse_lerp(MIN_VALUE, 1.0, clampf(v, MIN_VALUE, 1.0))
	return size.y * (1.0 - t)


func _draw() -> void:
	var x := (size.x - TRACK_WIDTH) * 0.5
	var track := Rect2(x, 0.0, TRACK_WIDTH, size.y)
	draw_rect(track, Color(BuilderTheme.BG_DEEP, 0.5), true)
	draw_rect(track, BuilderTheme.border(), false, 1.0)

	var zero_y := _y_for(0.0)
	# Fill from the stop mark to the lever: up for ahead, down for reverse, so
	# reverse never looks like a small amount of forward.
	var lever_y := _y_for(value)
	var fill_top := minf(zero_y, lever_y)
	var fill_colour := BuilderTheme.accent() if value >= 0.0 else BuilderTheme.warn()
	draw_rect(
		Rect2(x + 2.0, fill_top, TRACK_WIDTH - 4.0, absf(lever_y - zero_y)),
		Color(fill_colour, 0.42),
		true
	)

	draw_line(Vector2(x - 4, zero_y), Vector2(x + TRACK_WIDTH + 4, zero_y), BuilderTheme.border_strong(), 1.0)

	# The speed needle, on the right of the track. Drawn even when it agrees with
	# the lever, because a needle that only appears when things go wrong is a
	# needle nobody learns to read.
	var speed_y := _y_for(clampf(actual, MIN_VALUE, 1.0))
	var needle := BuilderTheme.good() if absf(actual - value) < 0.06 else BuilderTheme.warn()
	draw_line(
		Vector2(x + TRACK_WIDTH + 1, speed_y),
		Vector2(x + TRACK_WIDTH + 8, speed_y),
		needle, 2.0
	)

	# The lever itself.
	var grip := Rect2(x - 5, lever_y - 4, TRACK_WIDTH + 10, 8)
	draw_rect(grip, fill_colour, true)
	draw_rect(grip, BuilderTheme.text_strong_color(), false, 1.0)
