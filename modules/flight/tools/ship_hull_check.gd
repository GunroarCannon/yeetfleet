## Verifies the flight scene binds real compound collision hulls, not just a
## bounding sphere: the player's body and a spawned AI ship's body each carry a
## chain of hull spheres in the right space (see [method
## ShipView.collision_hull], [method PhysBody.set_hull]).
##
## Exists because the wiring is invisible when it breaks: a hull that never got
## passed, or one built in the wrong space, still produces a body that collides
## — just as a fat ball again, which is exactly the behaviour this replaced and
## which nothing else in the suite would notice.
##
##     godot --path . --headless --script modules/flight/tools/ship_hull_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _sat: AiShip = null
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_root.spawn_satellite()
		for s in _root._ai_spawner._ships:
			if is_instance_valid(s) and s.is_satellite:
				_sat = s
				break
		return false
	if _frames < 40:
		return false
	_check_player_hull()
	_check_ai_hull()
	return _finish()


## The flown ship's body must collide as a chain of hull sections. The three
## things worth asserting are that the hull exists, that it is a chain rather
## than one ball, and that every sphere sits inside the assembled ship's own
## bounds — which is what a space mismatch (ship space vs model space) would
## break, and nothing else would.
func _check_player_hull() -> void:
	print("── player hull ─────────────────────────────────")
	var body := _root.model._phys
	var view := _root.view
	if body == null or view == null:
		_check(false, "the player's ship has no physics body or no assembled view")
		return
	_check(body.has_hull(), "the player's ship collides as a single sphere, not a hull")
	if not body.has_hull():
		return
	var hull := body.hull
	print("  %d hull sections, enclosing radius %.2f m, widest section %.2f m"
		% [hull.size(), body.radius, _widest(hull)])
	print("  design bounds %s" % view.aabb)
	_check(hull.size() > 1, "the hull is a single sphere in disguise (%d sections)" % hull.size())
	_check(_widest(hull) < body.radius,
		"the widest hull section (%.2f m) is as big as the whole ship (%.2f m)" % [_widest(hull), body.radius])
	# A sphere centre outside the ship's bounds means the offsets are not in the
	# space the body reads them in.
	var outside := view.aabb.grow(0.05)
	for i in hull.size():
		var offset := hull[i]["offset"] as Vector3
		_check(outside.has_point(offset),
			"hull section %d sits at %s, outside the ship's own bounds %s" % [i, offset, view.aabb])


## Every AI ship binds its hull through the spawner, the same way the player's
## ship does through [FlightRoot] — a different call site, so it needs its own
## proof.
func _check_ai_hull() -> void:
	print("── AI ship hull ────────────────────────────────")
	if _sat == null or not is_instance_valid(_sat):
		_check(false, "the satellite was not spawned")
		return
	var body: PhysBody = _sat.model._phys
	if body == null:
		_check(false, "the spawned AI ship has no physics body")
		return
	_check(body.has_hull(), "the AI ship collides as a single sphere, not a hull")
	if body.has_hull():
		print("  %d hull sections, enclosing radius %.2f m, widest section %.2f m"
			% [body.hull.size(), body.radius, _widest(body.hull)])


func _widest(hull: Array[Dictionary]) -> float:
	var widest := 0.0
	for sphere in hull:
		widest = maxf(widest, float(sphere["radius"]))
	return widest


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
