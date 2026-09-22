extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _phase := 0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0:
		if _frames < 15:
			return false
		_frames = 0
		_phase = 1
		return false
	if _phase == 1:
		if _frames == 1:
			print("assist=", _root.assist_enabled(), " mode=", _root.model.assist_mode,
				" phys=", _root.model._phys, " gravity_mode=", _root.gravity.mode,
				" pull=", _root.gravity.pull_enabled)
			if _root.gravity != null:
				_root.gravity.mode = GravitySystem.GravityMode.OFF
			_root.model.velocity = Vector3(0.0, 0.0, -420.0)
			print("set velocity -> ", _root.model.velocity, " phys.vel=",
				(_root.model._phys.velocity if _root.model._phys != null else Vector3.ZERO))
			return false
		var sp := _root.model.velocity.length()
		var pv := _root.model._phys.velocity if _root.model._phys != null else Vector3.ZERO
		print("f=%2d v=%7.1f phys=%7.1f stretch=%.3f pos=%s ts=%.2f" % [_frames, sp, pv.length(),
			_root._mote_stretch, _root.model.global_position, Engine.time_scale])
		if _frames >= 20:
			quit(0)
		return false
	return false
