## GestureReader: one finger (or the left mouse button) turned into taps,
## swipes, holds and drags for the one-thumb movement profiles.
##
## Fed by [method feed] from [method FlightRoot._unhandled_input], so a touch
## that lands on a HUD button never reaches it; ticked by [method tick] for the
## hold timers. Positions are viewport (logical) pixels.
##
## A press that ends quickly without moving far is a [signal tap]. One that
## moves far enough is a [signal swipe] on release, with [signal dragged] on the
## way. One that stays put becomes a hold ([signal hold_started] after
## [member hold_time], [signal hold_long] after [member long_hold_time]),
## ended by [signal hold_ended].
##
## A second finger turns it into a two-finger gesture: whatever the first
## finger was doing is dropped ([signal cancelled]) and [signal two_finger]
## reports the pinch, twist and pan until both are up — unless [member
## keep_primary] is on (a slingshot pull under way): then the first finger
## carries on and the second one only looks around ([signal look_dragged]). On PC the mouse wheel
## and a right-drag stand in ([signal wheel], [signal alt_dragged]).
class_name GestureReader
extends RefCounted

signal pressed(pos: Vector2)
signal tap(pos: Vector2)
signal dragged(pos: Vector2, start: Vector2)
signal swipe(start: Vector2, end: Vector2, seconds: float)
signal hold_started(pos: Vector2)
signal hold_long(pos: Vector2)
signal hold_ended(pos: Vector2)
## Any release, after whichever of the above it produced.
signal released(pos: Vector2)
## The one-finger gesture was dropped (a second finger landed); no tap, swipe
## or release follows for it.
signal cancelled
## Two fingers moved: [param scale] is the spread since the last report (>1 =
## spreading), [param twist] the turn in radians, [param pan] the midpoint's
## move in pixels.
signal two_finger(scale: float, twist: float, pan: Vector2)
## Mouse wheel: +1 per notch toward the screen (zoom in), -1 away.
signal wheel(steps: float)
## Right-button drag on PC, relative pixels.
signal alt_dragged(relative: Vector2)
## A second finger dragging while [member keep_primary] holds the first one,
## relative pixels.
signal look_dragged(relative: Vector2)

## Movement (px) past which a press is a swipe/drag, not a tap or hold.
var move_threshold := 18.0
## Longest press (s) that still counts as a tap.
var tap_time := 0.28
var hold_time := 0.32
var long_hold_time := 1.4
## Set by a profile while the first finger's gesture must not be dropped by a
## second finger (the slingshot's pull): the second one looks around instead.
var keep_primary := false

var _pointer := -1
var _start := Vector2.ZERO
var _pos := Vector2.ZERO
var _held_for := 0.0
## Seconds since the press, moving or not (a swipe's duration).
var _elapsed := 0.0
var _moved := false
var _holding := false
var _long := false
## Every finger down, index → position (for two-finger gestures).
var _touches := {}
## Two fingers are (or were, until all lift) in a pinch.
var _two := false
var _pinch_dist := 0.0
var _pinch_angle := 0.0
var _pinch_mid := Vector2.ZERO
## A real touchscreen: the mouse events it emulates are ignored.
var _touch_device := false
var _alt_drag := false
## The looking-around finger while [member keep_primary] holds (-1 = none).
var _look_index := -1


## True while a finger is down.
func is_down() -> bool:
	return _pointer != -1


func current_position() -> Vector2:
	return _pos


func start_position() -> Vector2:
	return _start


## Returns true when the event was a gesture event this reader consumed.
func feed(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		_touch_device = true
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if keep_primary and _pointer != -1 and _look_index == -1 and not _two:
				_look_index = st.index
				return true
			if _touches.size() == 2:
				_begin_two()
				return true
			if _two or _touches.size() > 2:
				return true
			return _down(st.index, st.position)
		_touches.erase(st.index)
		if st.index == _look_index:
			_look_index = -1
			return true
		if _two:
			# The pinch holds until every finger is up, so the one left behind
			# doesn't turn into a swipe.
			if _touches.is_empty():
				_two = false
			elif _touches.size() == 2:
				_begin_two()
			return true
		return _up(st.index, st.position)
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.has(sd.index):
			_touches[sd.index] = sd.position
		if sd.index == _look_index:
			look_dragged.emit(sd.relative)
			return true
		if _two:
			_move_two()
			return true
		return _move(sd.index, sd.position)
	if _touch_device:
		# Emulated from a touch that was already read above.
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					wheel.emit(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
				return true
			MOUSE_BUTTON_RIGHT:
				_alt_drag = mb.pressed
				return true
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					return _down(100, mb.position)
				return _up(100, mb.position)
		return false
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# A button let go over a HUD control is eaten by the GUI and never
		# reaches this reader, which then thought it was still held: every
		# move of the mouse or trackpad swung the camera and pulled the ship
		# off centre. The motion's own button mask is the truth.
		if _alt_drag and mm.button_mask & MOUSE_BUTTON_MASK_RIGHT == 0:
			_alt_drag = false
		if _pointer == 100 and mm.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_up(100, mm.position)
			return true
		if _alt_drag:
			alt_dragged.emit(mm.relative)
			return true
		return _move(100, mm.position)
	return false


func tick(delta: float) -> void:
	if _pointer == -1:
		return
	_elapsed += delta
	if _moved:
		return
	_held_for += delta
	if not _holding and _held_for >= hold_time:
		_holding = true
		hold_started.emit(_pos)
	if _holding and not _long and _held_for >= long_hold_time:
		_long = true
		hold_long.emit(_pos)


## Forget the finger (profile switched mid-press).
func reset() -> void:
	if _holding:
		hold_ended.emit(_pos)
	_pointer = -1
	_holding = false
	_long = false
	_touches.clear()
	_two = false
	_alt_drag = false
	_look_index = -1


## True while two fingers are pinching (or the last of them is still down).
func is_two_finger() -> bool:
	return _two


# --- Internals ---

func _begin_two() -> void:
	if _pointer != -1:
		# Drop the one-finger gesture without a tap, swipe or release.
		if _holding:
			hold_ended.emit(_pos)
		_pointer = -1
		_holding = false
		_long = false
		cancelled.emit()
	_two = true
	var pts := _two_points()
	_pinch_dist = maxf(pts[0].distance_to(pts[1]), 1.0)
	_pinch_angle = (pts[1] - pts[0]).angle()
	_pinch_mid = (pts[0] + pts[1]) * 0.5


func _move_two() -> void:
	if _touches.size() < 2:
		return
	var pts := _two_points()
	var d := maxf(pts[0].distance_to(pts[1]), 1.0)
	var a := (pts[1] - pts[0]).angle()
	var mid := (pts[0] + pts[1]) * 0.5
	two_finger.emit(d / _pinch_dist, wrapf(a - _pinch_angle, -PI, PI), mid - _pinch_mid)
	_pinch_dist = d
	_pinch_angle = a
	_pinch_mid = mid


## The two lowest-indexed fingers, in a stable order.
func _two_points() -> Array[Vector2]:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _down(index: int, pos: Vector2) -> bool:
	if _pointer != -1:
		return false
	_pointer = index
	_start = pos
	_pos = pos
	_held_for = 0.0
	_elapsed = 0.0
	_moved = false
	_holding = false
	_long = false
	pressed.emit(pos)
	return true


func _move(index: int, pos: Vector2) -> bool:
	if index != _pointer:
		return false
	_pos = pos
	if not _moved and pos.distance_to(_start) > move_threshold:
		_moved = true
		if _holding:
			_holding = false
			hold_ended.emit(pos)
	if _moved:
		dragged.emit(pos, _start)
	return true


func _up(index: int, pos: Vector2) -> bool:
	if index != _pointer:
		return false
	_pos = pos
	_pointer = -1
	if _holding:
		hold_ended.emit(pos)
	elif _moved or pos.distance_to(_start) > move_threshold:
		swipe.emit(_start, pos, maxf(_elapsed, 0.016))
	elif _elapsed <= tap_time:
		tap.emit(pos)
	_holding = false
	_long = false
	released.emit(pos)
	return true
