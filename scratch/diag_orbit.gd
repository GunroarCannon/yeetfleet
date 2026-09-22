extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const ORBIT_WINDOW := 240

var _root: FlightRoot
var _frames := 0
var _phase := 0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _dump(tag: String) -> void:
	var m := _root.model
	var d := m.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	var v := m.velocity
	var g := _root.gravity
	var body := g.find_dominant_body(m.global_position)
	var gates := "no_body"
	if body != null:
		var dist := m.global_position.distance_to(body.position)
		var min_r := body.radius * FlightModel.ORBITAL_ASSIST_MIN_R
		var max_r := body.relevant_range * maxf(g.range_multiplier, 0.1)
		gates = "%s dist=%.0f min=%.0f max=%.0f (r=%.0f range=%.0f)" % [
			body.name, dist, min_r, max_r, body.radius, body.relevant_range]
	print("%s d=%.0f speed=%.1f hold=%.2f lockout=%.2f assist=%d mode=%d pull=%s | %s" % [
		tag, d, v.length(), m._orbital_hold_boost, m._assist_lockout, m.assist_mode,
		g.mode, str(g.pull_enabled), gates])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_root.gravity.pull_enabled = true
		Session.gravity_pull = true
		print("pull set -> ", _root.gravity.pull_enabled)
	match _phase:
		0:
			if _frames == ORBIT_WINDOW:
				_dump("coast ")
			if _frames == ORBIT_WINDOW * 2:
				_dump("coast.end")
				_frames = 0
				_phase = 1
		1:
			if _frames == 1:
				Session.fast_orbits = true
				Session.orbit_speed_scale = 4.0
				_dump("fast.on")
			if _frames % 30 == 0:
				_dump("fast f=%d" % _frames)
			if _frames >= ORBIT_WINDOW * 2:
				Session.fast_orbits = false
				quit(0)
	return false
