extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _sat: AiShip = null
var _ship_pos0 := Vector3.ZERO
var _sat_pos0 := Vector3.ZERO


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _process(_d: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames == 10:
		print("gravity mode=", _root.gravity.mode, " pull=", _root.gravity.pull_enabled,
			" Session.gravity_pull=", Session.gravity_pull)
		print("Engine.time_scale=", Engine.time_scale, " root _time_scale=", _root._time_scale)
		print("player pos=", _root.model.global_position, " vel=", _root.model.velocity)
		print("assist_mode=", _root.model.assist_mode, " lockout=", _root.model._assist_lockout,
			" fast=", Session.fast_orbits, " factor=", _root.model._fast_orbit_factor())
		print("model process=", _root.model.is_processing(), " phys=", _root.model.is_physics_processing())
		_ship_pos0 = _root.model.global_position
		_root.spawn_satellite()
		for s in _root._ai_spawner._ships:
			if is_instance_valid(s) and s.is_satellite:
				_sat = s
				_sat_pos0 = s.global_position
				print("sat found: pos=", s.global_position, " model=", s.model,
					" model_vel=", (s.model.velocity if s.model != null else Vector3.ZERO),
					" model_phys=", (s.model.is_physics_processing() if s.model != null else false),
					" ai_paused=", s._ai_paused)
				break
		if _sat == null:
			print("NO SATELLITE FOUND; ships=", _root._ai_spawner._ships.size())
		_frames = 0
		_phase = 1
	elif _phase == 1 and _frames >= 300:
		print("after 300f: player moved ", _ship_pos0.distance_to(_root.model.global_position), " m; vel=", _root.model.velocity)
		if _sat != null:
			print("after 300f: sat moved ", _sat_pos0.distance_to(_sat.global_position), " m; vel=",
				(_sat.model.velocity if _sat.model != null else Vector3.ZERO))
		_frames = 0
		_phase = 2
	elif _phase == 2 and _frames >= 120:
		print("after 120 more: player moved ", _ship_pos0.distance_to(_root.model.global_position), " m")
		if _sat != null:
			print("after 120 more: sat moved ", _sat_pos0.distance_to(_sat.global_position), " m; pos=", _sat.global_position)
		print("engine time_scale now=", Engine.time_scale, " root=", _root._time_scale)
		quit(0)
	return false
