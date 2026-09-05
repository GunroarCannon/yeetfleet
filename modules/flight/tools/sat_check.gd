## Verifies the satellite / orbit-debug / lock-on / cloud batch:
##  - a spawned satellite stays in a stable orbit;
##  - time-scale ×4 moves it ~4× faster per wall-clock frame;
##  - Enter-orbit debug holds the player's orbit;
##  - lock-on acquires a target;
##  - a planet with cloud_density builds a cloud layer and the atmosphere glow is
##    the lower (×1.2) strength.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/sat_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _failures: Array[String] = []
var _sat: AiShip = null
var _sat_dist0 := 0.0
var _angle_1 := 0.0
var _angle_4 := 0.0
var _angle_t0 := 0.0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _sat_angle() -> float:
	if _sat == null or not is_instance_valid(_sat):
		return 0.0
	var d := _sat.global_position - SpaceScene.PLANET_CENTRE
	return atan2(d.z, d.x)


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames == 10:
		_root.spawn_satellite()
		# Grab the satellite from the spawner's list.
		for s in _root._ai_spawner._ships:
			if is_instance_valid(s) and s.is_satellite:
				_sat = s
				_sat_dist0 = s.global_position.distance_to(SpaceScene.PLANET_CENTRE)
				break
		_frames = 0
		_phase = 1
	elif _phase == 1 and _frames >= 300:
		# ×1: measure angular travel over the next 60 frames.
		_angle_t0 = _sat_angle()
		_frames = 0
		_phase = 2
	elif _phase == 2 and _frames >= 60:
		var a1 := wrapf(_sat_angle() - _angle_t0, -PI, PI)
		_angle_1 = absf(a1)
		_root.set_time_scale(4.0)
		_angle_t0 = _sat_angle()
		_frames = 0
		_phase = 3
	elif _phase == 3 and _frames >= 60:
		var a4 := wrapf(_sat_angle() - _angle_t0, -PI, PI)
		_angle_4 = absf(a4)
		_root.set_time_scale(1.0)
		_check_orbit()
		_frames = 0
		_phase = 4
	elif _phase == 4 and _frames >= 300:
		_check_lock()
		_check_clouds()
		return _finish()
	return false


func _check_orbit() -> void:
	print("── satellite orbit + time-scale ─────────────────")
	var sat := _sat
	if sat == null or not is_instance_valid(sat):
		_check(false, "satellite was not spawned")
		return
	var d := sat.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	# The satellite was placed just outside the player's orbit and should still be
	# orbiting there.
	_check(absf(d - _sat_dist0) < 600.0, "satellite drifted from %.0f to %.0f m — orbit did not hold" % [_sat_dist0, d])
	print("  satellite %.0f m from Tarn (spawned at %.0f)" % [d, _sat_dist0])
	print("  angular travel ×1: %.3f rad, ×4: %.3f rad" % [_angle_1, _angle_4])
	_check(_angle_4 > _angle_1 * 2.5, "×4 time-scale did not speed up the orbit (%.2f vs %.2f)" % [_angle_1, _angle_4])
	_check(_angle_1 > 0.01, "satellite barely moved at ×1 — not orbiting")

	# Enter-orbit debug: the player ship should hold a stable orbit after it.
	_root.enter_orbit()
	var p0 := _root.model.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	print("  enter-orbit distance %.0f" % p0)
	_check(absf(p0 - 4000.0) < 900.0, "enter-orbit put the ship somewhere unexpected (%.0f m)" % p0)


func _check_lock() -> void:
	print("── lock-on ─────────────────────────────────────")
	_root.toggle_lock()
	_check(_root.locked_target != null, "lock-on did not acquire a target")
	if _root.locked_target != null:
		var lt := _root.locked_target as AiShip
		print("  locked: %s" % (lt.preset_name if lt != null else "unknown"))
	_root.toggle_lock()
	_check(_root.locked_target == null, "lock-on did not release")


func _check_clouds() -> void:
	print("── clouds + atmosphere ─────────────────────────")
	var p := Planet.new()
	var d := PlanetData.new()
	d.planet_radius = 5.0
	d.atmosphere_density = 0.5
	d.cloud_density = 0.6
	add_root_child(p)
	p.configure(d)
	_check(p.clouds() != null, "planet with cloud_density > 0 has no cloud layer")
	if p.clouds() != null:
		print("  cloud layer present")
	var atmo := p.atmosphere()
	_check(atmo != null, "planet with atmosphere_density > 0 has no atmosphere")
	if atmo != null:
		var mat := atmo.material_override as ShaderMaterial
		var gs: float = mat.get_shader_parameter("glow_strength")
		print("  atmosphere glow_strength = %.2f (expect 0.60)" % gs)
		_check(absf(gs - 0.6) < 0.01, "atmosphere glow strength is %.2f, not the reduced 0.60" % gs)


func add_root_child(node: Node) -> void:
	root.add_child(node)


func _finish() -> bool:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
		return true
	print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
	for f in _failures:
		print("  · " + f)
	quit(1)
	return true
