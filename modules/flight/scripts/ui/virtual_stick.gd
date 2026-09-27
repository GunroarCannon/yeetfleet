## An on-screen analogue stick, drawn rather than textured.
##
## Present on desktop as well as on a phone, and not as a concession: it is the
## only readout that shows what the flight computer thinks you are asking for. A
## pilot fighting a design with too little control authority can see the stick
## pinned at full deflection while the ship barely turns, which is the moment the
## builder's "turn rate" number stops being abstract.
##
## Keyboard and mouse write into it through [method set_external], so the same
## widget shows keyboard input, mouse input and thumb input identically.
class_name VirtualStick
extends Control

## Emitted whenever the deflection changes. Right and down are positive, matching
## screen axes; the caller maps them onto flight axes.
signal moved(value: Vector2)
## A pointer went down on (true) or came off (false) the stick.
signal held(on: bool)

const RING_WIDTH := 2.0
const KNOB_RATIO := 0.34
## Deflection below this is treated as centred, so a resting thumb does not creep.
const DEADZONE := 0.06

## Current deflection, -1..1 on each axis.
var value := Vector2.ZERO

## Where the ring is drawn. Follows the touch on press so a thumb that lands
## slightly off-centre does not start the ship in a turn.
var _origin := Vector2.ZERO
var _dragging := false
var _pointer := -1
## Set when something other than a pointer (a key, the mouse) owns the stick, so
## the widget draws that input instead of fighting it.
var _external := false
## A fixed ring radius, px. 0 = fill the widget. Set with a large widget to
## make a floating stick: the whole area takes a thumb, the ring spawns under it.
var ring_radius := 0.0
## Where the ring rests when not held, in local px; (-1, -1) = the centre.
var rest_point := Vector2(-1.0, -1.0)


func _ready() -> void:
	custom_minimum_size = Vector2(132, 132)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Steer — drag, or use the arrow keys"
	resized.connect(func() -> void: _origin = rest_centre())
	_origin = rest_centre()


func radius() -> float:
	if ring_radius > 0.0:
		return ring_radius
	return minf(size.x, size.y) * 0.5 - RING_WIDTH


## Where the ring sits while nothing holds it: [member rest_point] if set,
## else the widget's centre.
func rest_centre() -> Vector2:
	return rest_point if rest_point.x >= 0.0 else size * 0.5


func is_held() -> bool:
	return _dragging


## Drive the stick from somewhere else — the keyboard, or a mouse drag on the
## viewport. Ignored while a finger is actually on the widget, because the thing
## the player is touching should always win.
func set_external(v: Vector2) -> void:
	if _dragging:
		return
	_external = v.length() > 0.001
	# Display only: echoing it back through [signal moved] fed the ship's own
	# command (with the aim assist mixed in) back in as fresh stick input,
	# every frame, and the two fought.
	_set_value(v, false)


func _set_value(v: Vector2, emit := true) -> void:
	var clamped := v.limit_length(1.0)
	if clamped.length() < DEADZONE:
		clamped = Vector2.ZERO
	if clamped.is_equal_approx(value):
		return
	value = clamped
	queue_redraw()
	if emit:
		moved.emit(value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin(mb.position)
		else:
			_end()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_pointer = st.index
			_begin(st.position)
		elif st.index == _pointer:
			_end()
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _pointer:
			_drag(sd.position)
			accept_event()


func _begin(at: Vector2) -> void:
	_dragging = true
	held.emit(true)
	_external = false
	# Re-centre on the press, but keep the ring fully inside the widget so it
	# never draws half off the edge of the screen.
	var r := radius()
	_origin = Vector2(clampf(at.x, r, size.x - r), clampf(at.y, r, size.y - r))
	_drag(at)


func _drag(at: Vector2) -> void:
	_set_value((at - _origin) / maxf(radius(), 1.0))


func _end() -> void:
	if _dragging:
		held.emit(false)
	_dragging = false
	_pointer = -1
	_origin = rest_centre()
	_set_value(Vector2.ZERO)


func _draw() -> void:
	var r := radius()
	var centre := _origin if _dragging else rest_centre()
	var live := _dragging or _external
	var ring := BuilderTheme.accent() if live else BuilderTheme.border_strong()
	draw_circle(centre, r, Color(BuilderTheme.bg_deep(), 0.34))
	draw_arc(centre, r, 0.0, TAU, 40, ring, RING_WIDTH, true)
	# Cross hairs at rest position: without them a centred stick is a blank disc
	# and gives no sense of which way it will move.
	var tick := r * 0.16
	var guide := Color(ring, 0.5)
	draw_line(centre - Vector2(tick, 0), centre + Vector2(tick, 0), guide, 1.0, true)
	draw_line(centre - Vector2(0, tick), centre + Vector2(0, tick), guide, 1.0, true)

	var knob := centre + value * r
	var knob_r := r * KNOB_RATIO
	draw_circle(knob, knob_r, Color(BuilderTheme.accent(), 0.28 if not live else 0.5))
	draw_arc(knob, knob_r, 0.0, TAU, 26, BuilderTheme.accent() if live else ring, 2.0, true)
