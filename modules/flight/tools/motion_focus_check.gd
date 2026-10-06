## Headless check for the chase camera's motion focus: in high motion the view
## leans at where the ship is heading (a yeet) or, once thrown back, at the foe
## that did it — and never while the player is turning the view by hand, and
## never with a jump. A fast run with the nose turned away from the flight (a
## sling launch the hull hasn't turned onto yet) is still a yeet, not a
## knock-back: the view must keep leaning the way the ship flies.
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/motion_focus_check.gd
##     godot --path . --headless --fixed-fps 144 --audio-driver Dummy --script modules/flight/tools/motion_focus_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []
var _foe := Vector3(0.0, 0.0, 900.0)


func _initialize() -> void:
	# In memory only: the player's saved dials stay as they are.
	JuiceSettings.cam_motion_focus = 1.0
	print("── motion focus check ────────────────────────────────────")
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	for i in 10:
		await process_frame
	_root.get_node("Ui/Coach").visible = false
	JuiceSettings.cam_motion_focus = 1.0
	var rig := _root.camera_rig
	rig.foe_focus = func() -> Vector3: return _foe
	var model := _root.model
	# Off to the side, so "leans at the foe" and "leans along the flight"
	# point different ways.
	_foe = model.global_position + model.global_transform.basis.x * 900.0
	await _hold(model, Vector3.ZERO, 0.5)
	var calm: float = rig.motion_focus_amount
	_report("cruising at rest: no motion focus", calm == 0.0)

	# A yeet: far past top speed, straight on.
	var dir := (-model.global_transform.basis.z).normalized()
	var worst_step := 0.0
	var last := Vector3.ZERO
	var t := 0.0
	while t < 3.0:
		model.velocity = dir * model.top_speed * 2.2
		await process_frame
		t += rig._dt
		var now: Vector3 = rig._motion_focus
		worst_step = maxf(worst_step, (now - last).length())
		last = now
	var f: Vector3 = rig._motion_focus
	_report("a yeet leans the view into the way it flies", rig.motion_focus_amount > 0.5 and f.normalized().dot(dir) > 0.9)
	_report("the lean eases in (no frame jumps more than 10% of its reach)", worst_step < f.length() * 0.1 + 0.001)

	# Hands on the view: it lets go.
	rig.user_yaw = 40.0
	await _hold(model, dir * model.top_speed * 2.2, 3.0)
	_report("turning the view by hand switches it off", rig.motion_focus_amount == 0.0 and rig._motion_focus.length() < 0.05)
	rig.user_yaw = 0.0
	rig.set_looking(true)
	await _hold(model, dir * model.top_speed * 2.2, 1.5)
	_report("free-look does too", rig.motion_focus_amount == 0.0)
	rig.set_looking(false)

	# Flying tail-first but in control (a launch the hull hasn't turned onto):
	# still a yeet — the view leans the way it flies, never back at a foe.
	await _hold(model, -dir * model.top_speed * 2.2, 3.0)
	var back: Vector3 = rig._motion_focus
	_report("tail-first in control still leans along the flight", rig.motion_focus_amount > 0.5 and back.normalized().dot(-dir) > 0.9)

	# Thrown back (really tumbling): look at the foe instead.
	model.out_of_control = true
	await _hold(model, -dir * model.top_speed * 2.2, 3.0)
	var g: Vector3 = rig._motion_focus
	var to_foe := (_foe - model.global_position).normalized()
	_report("thrown back, the view leans at the foe", rig.motion_focus_amount > 0.5 and g.normalized().dot(to_foe) > 0.9)

	# Nobody around to look at: leave it be.
	_foe = Vector3.INF
	await _hold(model, -dir * model.top_speed * 2.2, 3.5)
	_report("thrown back with no foe near: no lean", rig.motion_focus_amount == 0.0 and rig._motion_focus.length() < 0.05)
	model.out_of_control = false

	# The dial at zero turns it all off.
	JuiceSettings.cam_motion_focus = 0.0
	await _hold(model, dir * model.top_speed * 2.2, 3.5)
	_report("the dial at zero is off", rig._motion_focus.length() < 0.05)
	JuiceSettings.cam_motion_focus = 1.0
	_finish()


## Hold the ship at [param vel] for [param seconds] of the camera's own time
## (its per-frame step, so the wait means the same at any frame rate).
func _hold(model: FlightModel, vel: Vector3, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		model.velocity = vel
		await process_frame
		t += _root.camera_rig._dt


func _report(label: String, ok: bool) -> void:
	print("  %-60s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	print("── %s ─────────────────────────────────────────" % ("PASS" if _failures.is_empty() else "FAIL (%d)" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)
