## FlightTutorial: a short, interactive first-flight tutorial.
##
## One instruction at a time — a few words in the arcade ka1 face on a
## sprayed slab near the top — while a neon cartoon hand ([constant HAND])
## acts the move out on the screen: it presses on the ship and pulls back,
## swipes, taps, or points at the ship to wreck and the orb to grab. Each step
## waits for the player to actually do it (reported through [method note] by
## the pilots, the power-ups and the kill handler), ticks, and moves on. The
## steps follow the movement profile being flown: slingshot teaches the pull
## and the tap-to-shoot, swipe the dash, the stick profiles the fire button.
## Every profile ends the same way: destroy a ship, then fly into a power-up
## (one is floated just ahead of the ship when that step starts, so it never
## hangs on a lucky drop, and it never fades while the tutorial runs). The
## one-thumb profiles first learn to look round and zoom. Until the "wreck a
## ship" step every ship is unhurtable ([method guards_enemies]), so a stray
## shot never ends the lesson early. A few story cards (event "story", a
## NEXT button or a timer moves on) say who the player is flying for.
## Skippable; finishing or skipping marks it done in
## [member Session.prefs] ("tutorial_done", never baked into the shipped
## defaults) so it runs once on its own. The campaign map's TUTORIAL and the
## debug button replay it.
class_name FlightTutorial
extends Control

signal finished

## Seconds the NICE! shows before the next step.
const TICK_TIME := 0.9
## The hand: a cartoon hand pointing up and to the left, the fingertip at
## [constant HAND_TIP] (fractions of the picture).
const HAND := "res://assets/hand.png"
const HAND_TIP := Vector2(0.2, 0.02)
## The neon colours the hand cycles through.
const NEON: Array[Color] = [Color("b6ff3a"), Color("35e0ff"), Color("ff3a9e"), Color("ffe13a")]
## Seconds per loop of a hand gesture.
const LOOP := 2.2
## How much looking round (screen widths dragged) and zooming (log of the
## zoom change) a step wants before it ticks.
const LOOK_NEED := 0.8
const ZOOM_NEED := 0.35
## A story card moves on by itself after this long plus a beat per word.
const STORY_TIME := 2.5
const STORY_PER_WORD := 0.28

var _root: FlightRoot = null
## {text, event} per step.
var _steps: Array[Dictionary] = []
var _i := 0
var _tick := 0.0
var _card: _Card
## Fades the hand where it passes over a HUD control (see [method _find_holes]).
const HOLES_SHADER := "res://modules/flight/shaders/hud_holes.gdshader"
const MAX_HOLES := 24
## Seconds between re-reading where the HUD's controls are.
const HOLES_EVERY := 0.3
var _holes_clock := 0.0
var _skip: SlabButton
var _next: SlabButton
var _hand: Texture2D = null
var _start_ms := 0
## How much of the current gesture step the player has done so far.
var _progress := 0.0
var _story_left := 0.0


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	name = "FlightTutorial"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_steps = _steps_for(_root.move_profile if _root != null else 0)
	_hand = load(HAND) as Texture2D
	# Only this node's own drawing (the hand, bands, rings) takes the fade:
	# the card and the buttons are children with their own materials.
	var mat := ShaderMaterial.new()
	mat.shader = load(HOLES_SHADER) as Shader
	material = mat
	_card = _Card.new()
	add_child(_card)
	_skip = SlabButton.new()
	_skip.text = "SKIP"
	_skip.fill = Color("3a3150")
	_skip.skew = 8.0
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(stop.bind(true))
	add_child(_skip)
	_next = SlabButton.new()
	_next.text = "NEXT"
	_next.fill = GraffitiStyle.LIME
	_next.skew = -8.0
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(func() -> void: note("story"))
	add_child(_next)
	resized.connect(_layout)
	_show_step()


## The steps for [param profile] ([enum FlightRoot.MoveProfile]). A few words
## each, no dashes: the hand shows the rest.
static func _steps_for(profile: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var touch := DisplayServer.is_touchscreen_available()
	out.append(_story("WELCOME, RECRUIT", "The Union of Peace keeps the space lanes safe. Mostly."))
	out.append(_story("YOU FLY FOR THE YEETFLEET", "Its vigilantes. We sort out trouble by flinging ourselves at it."))
	match profile:
		FlightRoot.MoveProfile.SLINGSHOT, FlightRoot.MoveProfile.SWIPE:
			# Look round first: on a phone the view is the thing that goes
			# wrong, and a yeet aimed at nothing teaches nothing.
			out.append({"text": "DRAG AWAY FROM YOUR SHIP TO LOOK" if touch else "DRAG TO LOOK AROUND", "event": "look"})
			out.append({"text": "PINCH TO ZOOM" if touch else "SCROLL TO ZOOM", "event": "zoom"})
	match profile:
		FlightRoot.MoveProfile.SLINGSHOT:
			out.append({"text": "PULL BACK FROM YOUR SHIP", "event": "launch"})
			out.append({"text": "TAP TO SHOOT", "event": "tap_fire"})
		FlightRoot.MoveProfile.SWIPE:
			out.append({"text": "SWIPE TO DASH", "event": "swipe"})
			out.append({"text": "TAP TO SHOOT", "event": "tap_fire"})
		_:
			out.append({"text": "STEER AND HOLD FIRE", "event": "fire"})
	out.append(_story("DRONE SHIELDS ARE DOWN", "Those drones shrugged off everything so far. Not any more."))
	out.append({"text": "WRECK A SHIP", "event": "kill"})
	out.append({"text": "GRAB THE ORB", "event": "powerup"})
	out.append(_story("YOU ARE YEETFLEET NOW", "Go keep the peace. Loudly."))
	return out


## A story card: a headline and a line under it.
static func _story(head: String, line: String) -> Dictionary:
	return {"text": head, "line": line, "event": "story"}


## Whether every ship should still shrug off damage: true until the step
## that asks the player to wreck one.
func guards_enemies() -> bool:
	for j in range(_i + 1, _steps.size()):
		if String(_steps[j]["event"]) == "kill":
			return true
	return false


## Something happened that a step may be waiting for ("story", "look",
## "zoom", "launch", "swipe", "tap_fire", "fire", "kill", "powerup").
## [param amount] adds up for "look" and "zoom" (see [constant LOOK_NEED]).
func note(event: String, amount := 1.0) -> void:
	if _tick > 0.0 or _i >= _steps.size():
		return
	if String(_steps[_i]["event"]) != event:
		return
	var need := LOOK_NEED if event == "look" else (ZOOM_NEED if event == "zoom" else 0.0)
	_progress += amount
	_card.progress = clampf(_progress / need, 0.0, 1.0) if need > 0.0 else 0.0
	_card.queue_redraw()
	if _progress >= need and event == "story":
		# A story card just moves on: no NICE! for reading.
		_tick = 0.05
	elif _progress >= need:
		_tick = TICK_TIME
		_card.done = true
		_card.queue_redraw()
		Juice.pop(_card, 0.15)


func current_event() -> String:
	return String(_steps[_i]["event"]) if _i < _steps.size() else ""


## End it: [param skipped] or done, remembered either way.
func stop(skipped := false) -> void:
	if _root != null and _root.power_ups != null:
		_root.power_ups.hold = false
	Session.prefs["tutorial_done"] = true
	Session.save_to_disk()
	if not skipped and _root != null:
		_root.player_callout("Ready to fly!", Color("46ff9b"))
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	# Real time: a freeze or the kill cam must not stall the banner.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	_holes_clock -= dt
	if _holes_clock <= 0.0:
		_holes_clock = HOLES_EVERY
		_find_holes()
	if current_event() == "story" and _tick <= 0.0:
		_story_left -= dt
		if _story_left <= 0.0:
			note("story")
	if _tick > 0.0:
		_tick -= dt
		if _tick <= 0.0:
			_i += 1
			if _i >= _steps.size():
				stop()
				return
			_show_step()
	queue_redraw()


func _show_step() -> void:
	_card.step = "%d/%d" % [_i + 1, _steps.size()]
	_card.text = String(_steps[_i]["text"])
	_card.line = String(_steps[_i].get("line", ""))
	_card.story = current_event() == "story"
	_card.done = false
	_card.progress = 0.0
	_card.queue_redraw()
	_progress = 0.0
	_next.visible = _card.story
	if _card.story:
		_story_left = STORY_TIME + STORY_PER_WORD * float((_card.text + " " + _card.line).split(" ").size())
	_start_ms = Time.get_ticks_msec()
	if current_event() == "powerup" and _root != null and _root.power_ups != null:
		var ship := _root.active_ship_node()
		if ship != null:
			var ahead := -ship.global_transform.basis.z
			var r := _root.camera_rig.hull_radius if _root.camera_rig != null else 3.0
			_root.power_ups.drop(PowerUps.Kind.SHIELD, ship.global_position + ahead * maxf(r * 10.0, 40.0))
	_layout()


func _layout() -> void:
	if _card == null:
		return
	var u := maxf(minf(size.x, size.y) / 720.0, 0.5)
	var fs := int(30 * u)
	var tw := GraffitiStyle.tip_font().get_string_size(_card.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_card.font_size = fs
	_card.size = Vector2(minf(tw + 150.0 * u, size.x - 24.0), fs * 2.6)
	if _card.story:
		# A story card is wider and taller: the line under the headline wraps.
		_card.size = Vector2(minf(maxf(tw + 150.0 * u, 620.0 * u), size.x - 24.0), fs * 4.6)
	# Under the phone HUD's health panel (and, in portrait, the speed gauge),
	# clear of the thumb controls at the bottom.
	var top := minf(size.x, size.y) * 0.66 if size.y > size.x else size.y * 0.33
	_card.position = Vector2((size.x - _card.size.x) * 0.5, top)
	_card.pivot_offset = _card.size * 0.5
	_card.rotation = -0.03
	_skip.custom_minimum_size = Vector2(96, 44) * u
	_skip.size = _skip.custom_minimum_size
	_skip.font_size = int(20 * u)
	_skip.position = Vector2(_card.position.x + _card.size.x - _skip.size.x * 0.7, _card.position.y + _card.size.y - 6.0 * u)
	_next.custom_minimum_size = Vector2(110, 44) * u
	_next.size = _next.custom_minimum_size
	_next.font_size = int(20 * u)
	_next.position = Vector2(_skip.position.x - _next.size.x - 10.0 * u, _skip.position.y)


# --- The hand -------------------------------------------------------------------

## Where the HUD's controls are, for the shader to fade the hand over them:
## every visible control that takes touches and is button-sized (not a
## full-screen layer), outside this tutorial, as screen-UV rects.
func _find_holes() -> void:
	var mat := material as ShaderMaterial
	if mat == null or _root == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var rects: Array[Vector4] = []
	var stack: Array[Node] = [_root]
	while not stack.is_empty() and rects.size() < MAX_HOLES:
		var n: Node = stack.pop_back()
		if n == self:
			continue
		var c := n as Control
		if c != null:
			if not c.is_visible_in_tree():
				continue
			var r := c.get_global_rect()
			if c.mouse_filter == Control.MOUSE_FILTER_STOP and r.size.x > 4.0 and r.size.y > 4.0 					and r.size.x < vp.x * 0.5 and r.size.y < vp.y * 0.5:
				rects.append(Vector4(r.position.x / vp.x, r.position.y / vp.y, r.end.x / vp.x, r.end.y / vp.y))
				continue
		for child in n.get_children():
			stack.append(child)
	var packed: Array[Vector4] = rects.duplicate()
	packed.resize(MAX_HOLES)
	mat.set_shader_parameter("holes", packed)
	mat.set_shader_parameter("hole_count", rects.size())


func _draw() -> void:
	if _hand == null or _i >= _steps.size() or _tick > 0.0 or _root == null:
		return
	var t := fmod((Time.get_ticks_msec() - _start_ms) / 1000.0, LOOP) / LOOP
	var short := minf(size.x, size.y)
	var col := NEON[int((Time.get_ticks_msec() - _start_ms) / 700) % NEON.size()]
	var ship := _ship_screen()
	match current_event():
		"launch":
			# Press on the ship, pull back (down the screen), hold, let go.
			var pull := Vector2(-0.08, 0.2) * short
			var k := smoothstep(0.15, 0.55, t)
			var tip := ship + pull * k
			var down := t > 0.08 and t < 0.75
			if down:
				_band(ship, tip, col)
			_draw_hand(tip, col, 1.0 if t < 0.8 else 1.0 - (t - 0.8) / 0.2, down)
		"swipe":
			var from := Vector2(size.x * 0.3, size.y * 0.55)
			var to := Vector2(size.x * 0.7, size.y * 0.45)
			var k2 := smoothstep(0.2, 0.6, t)
			var tip2 := from.lerp(to, k2)
			if t > 0.2 and t < 0.7:
				_band(from, tip2, col)
			_draw_hand(tip2, col, 1.0 if t < 0.8 else 1.0 - (t - 0.8) / 0.2, t > 0.15 and t < 0.65)
		"tap_fire", "fire":
			var at := _enemy_screen()
			if at == Vector2.INF or not Rect2(Vector2.ZERO, size).grow(-short * 0.1).has_point(at):
				# Nothing to shoot on screen: tap a clear spot up and right.
				at = Vector2(size.x * 0.66, size.y * 0.3)
			var tap := t > 0.3 and t < 0.42
			if t > 0.3:
				var ring := clampf((t - 0.3) / 0.4, 0.0, 1.0)
				var rc := col
				rc.a = 1.0 - ring
				draw_arc(at, short * (0.02 + 0.07 * ring), 0.0, TAU, 32, rc, 5.0, true)
			var lift := 0.0 if tap else short * 0.04 * (1.0 - absf(t - 0.36) * 2.0)
			_draw_hand(at + Vector2(lift, lift), col, 1.0, tap)
		"look":
			# A drag across an empty patch of sky, away from the ship.
			var ship2 := _ship_screen()
			var from2 := Vector2(size.x * (0.22 if ship2.x > size.x * 0.5 else 0.62), size.y * 0.35)
			var to2 := from2 + Vector2(size.x * 0.18, 0.0)
			var k3 := smoothstep(0.15, 0.7, t) * (1.0 - smoothstep(0.75, 1.0, t))
			var tip3 := from2.lerp(to2, k3)
			if t > 0.12 and t < 0.8:
				_band(from2, tip3, col)
			_draw_hand(tip3, col, 1.0, t > 0.12 and t < 0.8)
		"zoom":
			# Two fingers spreading apart round the middle of the screen.
			var mid := size * 0.5
			var spread := short * (0.05 + 0.12 * smoothstep(0.15, 0.7, t))
			var down2 := t > 0.1 and t < 0.8
			var a := mid + Vector2(-spread, spread * 0.6)
			var b := mid + Vector2(spread, -spread * 0.6)
			if down2:
				_band(a, b, col)
			_draw_hand(a, col, 1.0, down2)
			_draw_hand(b, col, 1.0, down2)
		"kill":
			_point_at(_enemy_screen(), col, t, short)
		"powerup":
			_point_at(_orb_screen(), col, t, short)


## The hand bobbing at [param at] (held at the screen edge when it is off
## screen), with a pulsing neon ring round the thing.
func _point_at(at: Vector2, col: Color, t: float, short: float) -> void:
	if at == Vector2.INF:
		return
	var inner := Rect2(Vector2.ZERO, size).grow(-short * 0.12)
	var on := inner.has_point(at)
	if not on:
		at = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
	else:
		var rc := col
		rc.a = 0.9
		draw_arc(at, short * (0.06 + 0.012 * sin(t * TAU * 2.0)), 0.0, TAU, 40, rc, 6.0, true)
	var bob := sin(t * TAU * 2.0) * short * 0.015
	_draw_hand(at + Vector2(short * 0.03 + bob, short * 0.03 + bob), col, 1.0, false)


## The pull line between the press and the fingertip: a neon rubber band.
func _band(from: Vector2, to: Vector2, col: Color) -> void:
	draw_line(from, to, Color(0, 0, 0, 0.5), 12.0, true)
	draw_line(from, to, col, 6.0, true)
	draw_circle(from, 12.0, col)


## The hand with its fingertip on [param tip]; [param pressed] squashes it a touch.
func _draw_hand(tip: Vector2, col: Color, alpha: float, pressed: bool) -> void:
	if alpha <= 0.0:
		return
	var h := minf(size.x, size.y) * 0.2 * (0.92 if pressed else 1.0)
	var w := h * float(_hand.get_width()) / float(_hand.get_height())
	var at := tip - Vector2(w, h) * HAND_TIP
	# The picture as it is (assets/hand.png): no neon tint, no glow.
	draw_texture_rect(_hand, Rect2(at, Vector2(w, h)), false, Color(1, 1, 1, alpha))


func _ship_screen() -> Vector2:
	var p := _root.pilot()
	if p != null:
		var s := p.ship_screen_pos()
		if s != Vector2.INF:
			return s
	return size * 0.5


func _enemy_screen() -> Vector2:
	var cam := _root.camera_node()
	var ship := _root.active_ship_node()
	if cam == null or ship == null:
		return Vector2.INF
	var best: AiShip = null
	var bd := INF
	for s in _root.live_enemies():
		if s == _root.controlled_ai:
			continue
		var d := s.global_position.distance_to(ship.global_position)
		if d < bd:
			bd = d
			best = s
	return _project(cam, best.global_position) if best != null else Vector2.INF


func _orb_screen() -> Vector2:
	var cam := _root.camera_node()
	if cam == null or _root.power_ups == null:
		return Vector2.INF
	var spots := _root.power_ups.orb_positions()
	return _project(cam, spots[0]) if not spots.is_empty() else Vector2.INF


## A world point on screen; behind the camera it is mirrored to the far edge
## (so the hand still points the right way round).
func _project(cam: Camera3D, p: Vector3) -> Vector2:
	var s := cam.unproject_position(p)
	if cam.is_position_behind(p):
		s = size - s
		s = size * 0.5 + (s - size * 0.5) * 10.0
	return s


## The instruction slab: the step count, the words in ka1, and NICE! when done.
class _Card:
	extends Control
	var text := ""
	## The story card's line under the headline.
	var line := ""
	var story := false
	var step := ""
	var done := false
	var font_size := 30
	## 0..1 of a gesture step done so far (a bar under the words).
	var progress := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var fill := GraffitiStyle.LIME if done else GraffitiStyle.INK
		GraffitiStyle.draw_slab(self, r, fill, 18.0, 4.0, Vector2(6, 7))
		var kf := GraffitiStyle.tip_font()
		var words := "NICE!" if done else text
		if story and not done:
			var fill2 := GraffitiStyle.VIOLET
			GraffitiStyle.draw_slab(self, r, fill2, 18.0, 4.0, Vector2(6, 7))
			GraffitiStyle.draw_text(self, words, Vector2(size.x * 0.5, font_size * 1.1), font_size, GraffitiStyle.SUN, 6, kf)
			var lf := GraffitiStyle.head_font()
			var ls := int(font_size * 0.72)
			draw_multiline_string(lf, Vector2(24, font_size * 2.3), line, HORIZONTAL_ALIGNMENT_CENTER,
				size.x - 48.0, ls, 3, Color.WHITE)
			return
		GraffitiStyle.draw_text(self, words, size * 0.5 + Vector2(0, 2), font_size, GraffitiStyle.INK if done else GraffitiStyle.SUN, 0 if done else 6, kf)
		if progress > 0.0 and not done:
			var bar := Rect2(Vector2(size.x * 0.15, size.y - 12.0), Vector2(size.x * 0.7, 6.0))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), GraffitiStyle.LIME)
		if not done:
			var chip := Rect2(Vector2(10, -font_size * 0.55), Vector2(font_size * 2.2, font_size * 1.0))
			GraffitiStyle.draw_slab(self, chip, GraffitiStyle.HOT, 6.0, 2.0, Vector2(3, 3))
			GraffitiStyle.draw_text(self, step, chip.get_center(), int(font_size * 0.6), Color.WHITE, 0, GraffitiStyle.number_font())
