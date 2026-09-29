## FlightTutorial: a short, interactive first-flight tutorial.
##
## One instruction at a time in a banner under the HUD's health panel; each step
## waits for the player to actually do it (reported through [method note] by
## the pilots, the power-ups and the kill handler), ticks, and moves on. The
## steps follow the movement profile being flown: slingshot teaches the pull
## and the tap-to-shoot, swipe the dash, the stick profiles the fire button.
## Every profile ends the same way: destroy a ship, then fly into a power-up
## (one is floated just ahead of the ship when that step starts, so it never
## hangs on a lucky drop). Skippable; finishing or skipping marks it done in
## [member Session.prefs] ("tutorial_done", never baked into the shipped
## defaults) so it runs once. The 🎓 debug button restarts it.
class_name FlightTutorial
extends Control

signal finished

## Seconds the ✓ shows before the next step.
const TICK_TIME := 0.9

var _root: FlightRoot = null
## {text, event} per step.
var _steps: Array[Dictionary] = []
var _i := 0
var _tick := 0.0
var _panel: PanelContainer
var _count: Label
var _text: Label
var _pop := 0.0


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	name = "FlightTutorial"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_steps = _steps_for(_root.move_profile if _root != null else 0)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	PopupSkin.skin(_panel, Color("3fa9ff"))
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_count = Label.new()
	PopupSkin.style_heading(_count)
	col.add_child(_count)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	var skip := Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(stop.bind(true))
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(skip)
	resized.connect(_layout)
	_show_step()


## The steps for [param profile] ([enum FlightRoot.MoveProfile]).
static func _steps_for(profile: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match profile:
		FlightRoot.MoveProfile.SLINGSHOT:
			out.append({"text": "Put your thumb on your ship, pull back and let go to launch.", "event": "launch"})
			out.append({"text": "Tap anywhere to shoot — it aims at the nearest enemy for you.", "event": "tap_fire"})
		FlightRoot.MoveProfile.SWIPE:
			out.append({"text": "Swipe across the screen to dash that way.", "event": "swipe"})
			out.append({"text": "Tap anywhere to shoot — it aims at the best target for you.", "event": "tap_fire"})
		_:
			out.append({"text": "Steer with the stick (or the arrow keys) and hold FIRE to shoot.", "event": "fire"})
	out.append({"text": "Destroy an enemy ship. Kills can drop power-ups.", "event": "kill"})
	out.append({"text": "Fly into the blue orb to grab the power-up.", "event": "powerup"})
	return out


## Something happened that a step may be waiting for ("launch", "swipe",
## "tap_fire", "fire", "kill", "powerup").
func note(event: String) -> void:
	if _tick > 0.0 or _i >= _steps.size():
		return
	if String(_steps[_i]["event"]) == event:
		_tick = TICK_TIME
		_pop = 1.0
		_count.text = "✓ NICE!"
		Juice.pop(_panel, 0.15)


func current_event() -> String:
	return String(_steps[_i]["event"]) if _i < _steps.size() else ""


## End it: [param skipped] or done, remembered either way.
func stop(skipped := false) -> void:
	Session.prefs["tutorial_done"] = true
	Session.save_to_disk()
	if not skipped and _root != null:
		_root.player_callout("Ready to fly!", Color("46ff9b"))
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	# Real time: a freeze or the kill cam must not stall the banner.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	_pop = move_toward(_pop, 0.0, dt * 3.0)
	if _tick > 0.0:
		_tick -= dt
		if _tick <= 0.0:
			_i += 1
			if _i >= _steps.size():
				stop()
				return
			_show_step()


func _show_step() -> void:
	_count.text = "TUTORIAL %d/%d" % [_i + 1, _steps.size()]
	_text.text = String(_steps[_i]["text"])
	if current_event() == "powerup" and _root != null and _root.power_ups != null:
		var ship := _root.active_ship_node()
		if ship != null:
			var ahead := -ship.global_transform.basis.z
			var r := _root.camera_rig.hull_radius if _root.camera_rig != null else 3.0
			_root.power_ups.drop(PowerUps.Kind.SHIELD, ship.global_position + ahead * maxf(r * 10.0, 40.0))
	_layout()


func _layout() -> void:
	if _panel == null:
		return
	var u := maxf(minf(size.x, size.y), 200.0)
	var w := minf(size.x - u * 0.08, u * 1.1)
	# An autowrapping label asks for its height at whatever width it has when
	# it measures; give it the real one, then let the panel shrink to fit.
	_text.custom_minimum_size = Vector2(w - u * 0.3, 0.0)
	_panel.custom_minimum_size = Vector2(w, 0.0)
	# A container only ever grows to its minimum; asking for zero height
	# shrinks it back to fit, once the label has re-wrapped at its width.
	_panel.size = Vector2(w, 0.0)
	_shrink.call_deferred(w)
	# Under the phone HUD's health panel (and, in portrait, the speed gauge),
	# clear of the thumb controls at the bottom.
	_panel.position = Vector2((size.x - w) * 0.5, u * (0.66 if size.y > size.x else 0.33))


func _shrink(w: float) -> void:
	if _panel != null:
		_panel.size = Vector2(w, 0.0)
