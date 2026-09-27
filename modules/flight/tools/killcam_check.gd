## Checks the newer juice end to end in the real flight scene: the visual
## knockback springs home without touching velocity, a freeze really stops
## time and lets go, a player kill runs the kill cam (game paused under it,
## camera on the wreck, then back and resumed), and the mobile HUD swaps in
## and F1 swaps it back out.
##
##     godot --path . --headless --fixed-fps 144 --audio-driver Dummy --script modules/flight/tools/killcam_check.gd
##
## Run at 60 too. Dials are set on [JuiceSettings] directly (not saved), so the
## result doesn't depend on whatever the Juice panel was last left at.
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frame := 0
var _frame_dt := 0.0
var _phase := "settle"
var _phase_frame := 0
var _phase_ms := 0
var _failures: Array[String] = []
var _done := false

var _rest := Vector3.ZERO
var _peak := 0.0
var _vel_before := Vector3.ZERO
var _min_ts := 1.0
var _victim_pos := Vector3.ZERO
var _cam_start_d := 0.0
var _cam_min_d := INF
## The distance the kill cam frames this wreck from (it scales with hull size).
var _cam_goal_d := 0.0


class LateSampler extends Node:
	var callback: Callable

	func _ready() -> void:
		process_priority = 100000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		callback.call(delta)


func _initialize() -> void:
	# The shipped defaults, not the player's saved dials.
	JuiceSettings._loaded = true
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	var sampler := LateSampler.new()
	sampler.callback = _tick
	root.add_child(sampler)
	JuiceSettings.reduce_motion = false
	JuiceSettings.knockback_visual = true
	JuiceSettings.hit_knockback_strength = 0.5
	JuiceSettings.knockback_return_time = 0.3
	JuiceSettings.kill_freeze_frame = true
	JuiceSettings.freeze_on_kill = false
	JuiceSettings.kill_cam = true
	JuiceSettings.kill_cam_chance = 1.0
	JuiceSettings.kill_cam_hold = 0.6
	JuiceSettings.kill_cam_blend = 0.3
	JuiceSettings.kill_cam_time_scale = 0.04
	JuiceSettings.kill_cam_cooldown = 0.0
	JuiceSettings.player_invulnerable = true
	print("── kill cam / freeze / knockback / mobile HUD check ──────")


func _process(_delta: float) -> bool:
	return _done


func _check(ok: bool, what: String) -> void:
	print("  %-58s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(what)


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0
	_phase_ms = Time.get_ticks_msec()


func _secs(seconds: float) -> int:
	return int(seconds / maxf(_frame_dt, 0.001))


func _tick(delta: float) -> void:
	if _done:
		return
	# Keep re-reading the frame time for the first few frames: the first one
	# carries the scene load, and sizing every window from it collapsed them
	# to a couple of frames.
	if _frame_dt <= 0.0 or _frame < 6:
		_frame_dt = delta
	_frame += 1
	_phase_frame += 1
	# Normal speed, whatever time warp the last session saved (restored a
	# frame late, so set after it).
	if _frame == 3 and not is_equal_approx(_root.time_scale(), 1.0):
		_root.set_time_scale(1.0)
	# The classic controls, whatever movement profile the last session saved
	# (a slingshot pilot would hold the throttle and steer the camera).
	if _frame == 3 and _root.move_profile != FlightRoot.MoveProfile.CLASSIC:
		_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	var model := _root.model
	var rig := _root.camera_rig
	if model == null or rig == null:
		return
	if _frame == 3 and _root._ai_spawner != null:
		_root._ai_spawner.teardown()
		_root._ai_spawner.set_process(false)
	match _phase:
		"settle":
			model.command.throttle = 0.0
			if _phase_frame > _secs(2.0):
				_rest = model._visual.position
				_vel_before = model.velocity
				model.apply_knockback(model.global_transform.basis.x, 18.0)
				_next("knock")
		"knock":
			var off := model._visual.position.distance_to(_rest)
			_peak = maxf(_peak, off)
			if _phase_frame > _secs(1.2):
				print("  visual knockback peak %.2f m, left over %.3f m" % [_peak, off])
				_check(_peak > 0.4, "knockback visibly moves the hull (> 0.4 m)")
				_check(off < 0.03, "and springs all the way home within 1.2 s")
				_check(model.velocity.distance_to(_vel_before) < 0.5, "visual knockback leaves velocity alone")
				Juice.freeze(0.25, 1.0)
				_min_ts = 1.0
				_next("freeze")
		"freeze":
			_min_ts = minf(_min_ts, Engine.time_scale)
			if Time.get_ticks_msec() - _phase_ms > 600 and _phase_frame > 10:
				print("  freeze: slowest time scale %.4f, now %.2f" % [_min_ts, Engine.time_scale])
				_check(_min_ts < 0.01, "a freeze really stops time (< 1% speed)")
				_check(is_equal_approx(Engine.time_scale, 1.0), "and lets go afterwards")
				_spawn_victim()
		"spawned":
			if _phase_frame > 3:
				_kill_victim()
		"killcam":
			_min_ts = minf(_min_ts, Engine.time_scale)
			_cam_min_d = minf(_cam_min_d, rig.global_position.distance_to(_victim_pos))
			if not rig.kill_cam_active() or _phase_frame > _secs(6.0):
				print("  kill cam: slowest time %.3f, camera %.0f m → %.0f m from the wreck (framing %.0f m)" % [
					_min_ts, _cam_start_d, _cam_min_d, _cam_goal_d,
				])
				_check(_min_ts < 0.1, "the game pauses under the kill cam")
				_check(_cam_min_d < _cam_goal_d * 1.25, "the camera swoops in to its framing on the wreck")
				_check(not rig.kill_cam_active(), "the kill cam ends by itself")
				_next("resume")
		"resume":
			if _phase_frame > 5:
				_check(is_equal_approx(Engine.time_scale, 1.0), "play resumes at full speed")
				var d := rig.global_position.distance_to(model.global_position)
				_check(d < rig.hull_radius * 30.0, "the camera is back on the player's ship")
				_root._hud.set_mobile_layout(true)
				_next("mobile")
		"mobile":
			if _phase_frame > 3:
				var hud := _root._hud
				var mob := hud.get_node_or_null("MobileHud") as Control
				var bar := hud.get_node_or_null("TopBar") as Control
				_check(mob != null and mob.visible, "the mobile HUD is up")
				_check(bar != null and not bar.visible, "the desktop top bar is hidden under it")
				var f1 := InputEventKey.new()
				f1.keycode = KEY_F1
				f1.pressed = true
				Input.parse_input_event(f1)
				_next("f1")
		"f1":
			if _phase_frame > 3:
				var hud := _root._hud
				var bar := hud.get_node_or_null("TopBar") as Control
				_check(not hud.mobile_layout_active(), "F1 leaves the mobile HUD")
				_check(bar != null and bar.visible, "and the desktop top bar is back")
				_finish()


func _spawn_victim() -> void:
	var spawner := _root._ai_spawner
	spawner.spawn_near_player(1)
	_next("spawned")


func _kill_victim() -> void:
	var ships := _root.live_enemies()
	if ships.is_empty():
		_check(false, "an AI ship spawned to be killed")
		_finish()
		return
	var victim := ships[0]
	# Park it in front of the player so the swoop has a known distance.
	var model := _root.model
	victim.model.global_position = model.global_position - model.global_transform.basis.z * 150.0
	victim.global_position = victim.model.global_position
	_victim_pos = victim.global_position
	_cam_start_d = _root.camera_rig.global_position.distance_to(_victim_pos)
	_min_ts = 1.0
	victim.take_damage(victim.hp + 10.0, true)
	_check(victim.killed_by_player, "a kill by the player's hit counts as the player's")
	_check(_root.camera_rig.kill_cam_active(), "the player's kill starts the kill cam")
	_cam_goal_d = _root.camera_rig._kc_dist
	_next("killcam")


func _finish() -> void:
	JuiceSettings.load_from_disk()
	Session.prefs["mobile_layout"] = false
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
	else:
		print("── FAIL: %s" % ", ".join(_failures))
	_done = true
	quit(0 if _failures.is_empty() else 1)
