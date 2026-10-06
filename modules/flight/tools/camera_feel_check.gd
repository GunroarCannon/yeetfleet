## Measures how the chase camera reacts to being hit, frame by frame.
##
##     godot --path . --headless --fixed-fps 144 --audio-driver Dummy --script modules/flight/tools/camera_feel_check.gd
##
## Run it at a render rate above the 60 Hz physics tick (144 here) as well as
## at 60: frame/tick mismatch is where follow-camera shudder comes from, and
## at exactly 60 fps it cannot show up.
##
## "Smooth" can't be judged from a screenshot, but its failures can be measured:
## a zoom that never visibly happens, a jump to the zoomed position in one frame,
## a snap back, the camera lurching when the ship is knocked, and the ship leaving
## the frame. Each of those is a number here. --fixed-fps keeps the frame deltas
## identical, so the per-frame limits mean the same thing on every machine.
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
## Phase lengths in seconds, turned into frame counts by [method _frames] so
## the check means the same thing at any --fixed-fps.
const SETTLE_TIME := 2.5
const HIT_TIME := 5.0
const KNOCK_TIME := 2.0
const CRUISE_SETTLE_TIME := 6.0
const CRUISE_TIME := 4.0
const WEAVE_TIME := 5.0
const VIEW_TIME := 2.5

var _old_weave := 0.0
var _view_i := 0
var _rng := RandomNumberGenerator.new()
var _saved_feel := {}

var _root: FlightRoot
var _frame := 0
## Seconds per rendered frame, read from the first frame (before any hitstop
## can scale it).
var _frame_dt := 0.0
var _phase := "settle"
var _phase_frame := 0
var _failures: Array[String] = []

var _base_dist := 0.0
var _dists: Array[float] = []
var _positions: Array[Vector3] = []
var _baseline_jerk := 0.0
## Camera-local ship positions through the hit: where it sits on screen.
var _screen: Array[Vector3] = []
var _out_of_view := 0


## Runs [member callback] after every other node's _process, so each sample
## sees the camera already placed for the frame. The SceneTree's own _process
## runs before the nodes; sampling there compared this tick's ship against
## last frame's camera and reported shudder that was never on screen.
class LateSampler extends Node:
	var callback: Callable

	func _ready() -> void:
		process_priority = 100000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		callback.call(delta)


var _done := false


func _initialize() -> void:
	# The shipped defaults, not the player's saved dials: this measures the
	# feel the game ships with, whatever someone has tuned on this machine.
	JuiceSettings._loaded = true
	# `-- --no-interp` runs with physics interpolation off (not saved), to see
	# the 60 Hz stepping the toggle removes.
	if "--no-interp" in OS.get_cmdline_user_args():
		PerformanceSettings.ensure_loaded()
		PerformanceSettings.physics_interpolation = false
		print("  (physics interpolation OFF for this run)")
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	var sampler := LateSampler.new()
	sampler.callback = _tick
	root.add_child(sampler)
	print("── camera feel check ─────────────────────────────────────")


func _frames(seconds: float) -> int:
	return int(seconds / maxf(_frame_dt, 0.001))


func _process(_delta: float) -> bool:
	return _done


func _tick(delta: float) -> void:
	if _done:
		return
	if _frame_dt <= 0.0:
		_frame_dt = delta
	_frame += 1
	_phase_frame += 1
	var rig := _root.camera_rig
	var model := _root.model
	if rig == null or model == null:
		return
	# AI fire mid-measurement adds its own hits and zooms, and kill_all's
	# wreckage rams the player, so clear the fleet quietly and stop the spawner
	# refilling it.
	# Normal speed, whatever time warp the last session saved (restored a
	# frame late, so set after it).
	if _frame == 3 and not is_equal_approx(_root.time_scale(), 1.0):
		_root.set_time_scale(1.0)
	# The classic controls, whatever movement profile the last session saved
	# (a slingshot pilot would hold the throttle and steer the camera).
	if _frame == 3 and _root.move_profile != FlightRoot.MoveProfile.CLASSIC:
		_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	if _frame == 3 and _root._ai_spawner != null:
		_root._ai_spawner.teardown()
		_root._ai_spawner.set_process(false)
	var cam := rig.camera
	# What is actually drawn: with physics interpolation on, the hull is shown
	# between physics ticks, not at the latest one.
	var ship_pos := model.get_global_transform_interpolated().origin
	var dist := cam.global_position.distance_to(ship_pos)
	match _phase:
		"settle":
			model.command.throttle = 0.0
			if _phase_frame >= _frames(SETTLE_TIME):
				_base_dist = dist
				_root.player_hp = _root.player_max_hp
				_root.player_shield = 0.0
				# A heavy hit from the side: triggers the zoom, the hitstop and a
				# sideways knockback, the case that read as a jerk/teleport.
				_root.take_damage(
					_root.player_max_hp * 0.3, model.global_position + model.global_transform.basis.x * 60.0
				)
				_next("hit")
		"hit":
			_dists.append(dist)
			_screen.append(cam.global_transform.affine_inverse() * ship_pos)
			_track_view(cam, model)
			# The last second of steady flight: the baseline path roughness
			# the knockback is compared against.
			if _phase_frame > _frames(HIT_TIME - 1.0):
				_positions.append(cam.global_position)
			if _phase_frame >= _frames(HIT_TIME):
				_judge_zoom()
				_baseline_jerk = _worst_jerk(_positions)
				_positions.clear()
				model.apply_knockback(model.global_transform.basis.x, 18.0)
				_next("knock")
		"knock":
			_positions.append(cam.global_position)
			_track_view(cam, model)
			if _phase_frame >= _frames(KNOCK_TIME):
				_judge_knock()
				_positions.clear()
				model.command.throttle = 0.5
				_next("cruise")
		"cruise":
			# Where the ship sits on screen (camera-local). At a steady speed it
			# should barely move; a follow point out of step with the physics
			# ticks makes it shudder forward and back instead.
			if _phase_frame > _frames(CRUISE_SETTLE_TIME):
				_positions.append(cam.global_transform.affine_inverse() * ship_pos)
			# An emote popped at speed must ride along with the ship, not be
			# left behind at the spot it spawned.
			if _phase_frame == _frames(CRUISE_SETTLE_TIME):
				_root._next_emote_ms = 0
				_root._emote("happy", 2.0)
			if _phase_frame == _frames(CRUISE_SETTLE_TIME + 0.6):
				_judge_emote(cam, model, ship_pos)
			if _phase_frame >= _frames(CRUISE_SETTLE_TIME + CRUISE_TIME):
				_judge_cruise()
				_positions.clear()
				_out_of_view = 0
				_use_old_feel(true)
				_next("weave_old")
		"weave_old", "weave":
			# A twitchy thumb weaving the ship left and right: where the hull
			# sits on screen should flow, not buzz, and it must stay in view.
			_weave(model)
			if _phase_frame > _frames(1.0):
				_positions.append(cam.global_transform.affine_inverse() * ship_pos)
				_track_view(cam, model)
			if _phase_frame >= _frames(WEAVE_TIME):
				var worst := _worst_jerk(_positions)
				_positions.clear()
				if _phase == "weave_old":
					_old_weave = worst
					print("  weave (old camera feel): on-screen ship jerk %.4f m/frame²" % worst)
					_use_old_feel(false)
					_out_of_view = 0
					_next("weave")
				else:
					print("  weave (new camera feel): on-screen ship jerk %.4f m/frame²" % worst)
					# The new frame lets the hull swing in view on purpose, so a
					# little more on-screen motion is expected; buzzing is not.
					_report("weaving no rougher than the old rigid follow (+25%)", worst <= _old_weave * 1.25 + 0.001)
					_report("ship stayed in view through the weave", _out_of_view == 0)
					_view_i = 0
					_root.camera_rig.set_mode(FlightCamera.CYCLE[0])
					_next("views")
		"views":
			_weave(model)
			if _phase_frame > _frames(0.6):
				_track_view(cam, model)
			if _phase_frame >= _frames(VIEW_TIME):
				var label := _root.camera_rig.mode_label()
				var mode := _root.camera_rig.mode
				var should_see := mode != FlightCamera.Mode.COCKPIT and mode != FlightCamera.Mode.PLANET 					and mode != FlightCamera.Mode.FAR
				if should_see:
					_report("%s view keeps the ship in frame" % label, _out_of_view == 0)
				_out_of_view = 0
				_view_i += 1
				if _view_i >= FlightCamera.CYCLE.size():
					_finish()
				else:
					_root.camera_rig.cycle_mode()
					_next("views")


## Stick input for the weave phases: a slow S-turn plus per-frame thumb noise.
func _weave(model: FlightModel) -> void:
	var t := float(_phase_frame) * _frame_dt
	var noise := Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.15, 0.15))
	_root.set_stick(Vector2(sin(t * 1.7) * 0.8, sin(t * 0.9) * 0.3) + noise)
	model.command.throttle = 0.6


## Swap the chase dials to the pre-rework rigid follow (true) or back.
func _use_old_feel(on: bool) -> void:
	var old := {
		"cam_follow_rate": 40.0, "cam_position_smooth": 6.0, "cam_aim_smooth": 11.0,
		"cam_turn_lead": 0.0, "cam_speed_fov": 0.0, "cam_turn_swing": 0.0, "cam_motion_focus": 0.0,
	}
	_rng.seed = 7
	for k: String in old:
		if on:
			_saved_feel[k] = JuiceSettings.get_float(k)
			JuiceSettings._load_float(k, old[k])
		else:
			JuiceSettings._load_float(k, _saved_feel[k])


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0


func _track_view(cam: Camera3D, model: Node3D) -> void:
	if not cam.is_position_in_frustum(model.global_position):
		_out_of_view += 1


func _judge_zoom() -> void:
	var peak := _base_dist
	var peak_i := 0
	for i in _dists.size():
		if _dists[i] > peak:
			peak = _dists[i]
			peak_i = i
	var rise := peak - _base_dist
	var biggest_step := 0.0
	var regrowth := 0.0
	for i in range(1, _dists.size()):
		biggest_step = maxf(biggest_step, absf(_dists[i] - _dists[i - 1]))
		if i > peak_i + 10:
			regrowth = maxf(regrowth, _dists[i] - _dists[i - 1])
	var end_dist: float = _dists[_dists.size() - 1]
	print("  base %.2f m  peak %.2f m (+%.0f%%) at frame %d  end %.2f m" % [
		_base_dist, peak, rise / maxf(_base_dist, 0.01) * 100.0, peak_i, end_dist
	])
	print("  largest one-frame distance change %.3f m (%.1f%% of the zoom)" % [
		biggest_step, biggest_step / maxf(rise, 0.001) * 100.0
	])
	_report("zooms out visibly (at least +25%)", rise > _base_dist * 0.25)
	_report("eases out rather than jumping (no frame > 12% of the zoom)", biggest_step < rise * 0.12)
	_report("takes its time to get there (peak after 0.12 s+)", peak_i * _frame_dt >= 0.12)
	_report("returns in one smooth ease (no re-growth after peak)", regrowth < rise * 0.01)
	_report("back to normal framing within 5 s", absf(end_dist - _base_dist) < _base_dist * 0.05)
	_report("ship stayed in view throughout the hit", _out_of_view == 0)
	# Sideways only (x/y): the zoom legitimately moves the ship in depth.
	var worst_side := 0.0
	for i in range(2, _screen.size()):
		var j := _screen[i] - _screen[i - 1] * 2.0 + _screen[i - 2]
		worst_side = maxf(worst_side, Vector2(j.x, j.y).length())
	print("  hit from the side: worst on-screen sideways jerk %.4f m/frame²" % worst_side)
	_report("no sideways jerk/teleport on a hit (< 0.05 m/frame²)", worst_side < 0.05)


## Largest second difference along a sampled path: its sharpest per-frame
## change of velocity.
func _worst_jerk(path: Array[Vector3]) -> float:
	var worst := 0.0
	for i in range(2, path.size()):
		worst = maxf(worst, (path[i] - path[i - 1] * 2.0 + path[i - 2]).length())
	return worst


func _judge_knock() -> void:
	# A camera bolted to the hull shows the whole knockback as one lurch in its
	# path. Measured as excess over the steady-flight baseline: with no physics
	# interpolation, above 60 fps every path is stepped at the physics rate and
	# that stepping is not the knockback's doing.
	var worst := _worst_jerk(_positions)
	var excess := worst - _baseline_jerk
	print("  knockback: worst camera lurch %.3f m/frame² (steady baseline %.3f)" % [worst, _baseline_jerk])
	_report("knockback is absorbed, not a lurch (< 0.15 m/frame² extra)", excess < 0.15)
	_report("ship stayed in view through the knockback", _out_of_view == 0)


func _judge_emote(cam: Camera3D, model: FlightModel, ship_pos: Vector3) -> void:
	var emote: Node3D = null
	for c in _root.get_children():
		# By what it is, not its name: with an older emote still alive, Godot
		# renames the new one to "@Node3D@<n>". The newest wins.
		if c.has_method("ride_along") and c.has_method("launch"):
			emote = c
	if emote == null:
		_report("an emote pops while cruising", false)
		return
	var gap := emote.global_position.distance_to(ship_pos)
	print("  emote at %.0f m/s: %.1f m from the hull, on screen: %s" % [
		model.velocity.length(), gap, cam.is_position_in_frustum(emote.global_position)])
	_report("emote rides along with the ship at speed", gap < _root.camera_rig.hull_radius * 4.0)
	_report("emote is on screen", cam.is_position_in_frustum(emote.global_position))


func _judge_cruise() -> void:
	var worst := _worst_jerk(_positions)
	print("  cruise: worst on-screen ship shudder %.4f m/frame²" % worst)
	_report("ship holds still in frame at speed (no shudder)", worst < 0.03)


func _report(label: String, ok: bool) -> void:
	print("  %-58s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	_done = true
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		quit(1)
