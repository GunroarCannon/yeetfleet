## Verifies the standalone AI test arena: the box + two opposed teams exist and
## fight, ships are confined to the bounding box, the camera can focus a ship,
## and take-control routes the player's inputs to the chosen ship.
##
##     godot --path . --rendering-driver opengl3 --script modules/arena/tools/arena_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/arena/arena.tscn"

var _root: ArenaRoot
var _frames := 0
var _phase := 0
var _failures: Array[String] = []
var _focus_ship: AiShip = null
var _combat_observed := false
var _box_ship: AiShip = null


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as ArenaRoot
	root.add_child(_root)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _ships() -> Array:
	if _root._ai_spawner == null:
		return []
	return _root._ai_spawner.ship_snapshot()


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames >= 120:
		_check_arena()
		_phase = 1
		_frames = 0
	elif _phase == 1:
		# Sample combat every frame — by the end of 10 s most armed ships may have
		# been destroyed, so track whether any ship was ever damaged.
		if not _combat_observed:
			for s in _ships():
				if float(s["hp"]) < float(s["max_hp"]) - 1.0:
					_combat_observed = true
					break
		if _frames >= 600:
			_check_combat()
			_phase = 2
			_frames = 0
	elif _phase == 2 and _frames >= 1:
		_beg_bounding_box_test()
		_phase = 3
		_frames = 0
	elif _phase == 3 and _frames >= 60:
		_check_bounding_box()
		_phase = 4
		_frames = 0
	elif _phase == 4 and _frames >= 1:
		var ships := _ships()
		if not ships.is_empty():
			_focus_ship = ships[0]["node"]
			_root.camera_rig.set_focus(_focus_ship)
		_phase = 5
		_frames = 0
	elif _phase == 5 and _frames >= 30:
		_check_focus()
		_phase = 6
		_frames = 0
	elif _phase == 6 and _frames >= 1:
		_check_take_control()
		return _finish()
	return false


func _check_arena() -> void:
	print("── arena ─────────────────────────────────────────")
	_check(_root.arena != null, "no AiTestArena node")
	_check(_root.camera_rig != null, "no camera rig")
	var ships := _ships()
	_check(ships.size() >= 4, "expected the two opening squads (got %d ships)" % ships.size())
	var has_red := false
	var has_blue := false
	for s in ships:
		if int(s["team"]) == 1:
			has_red = true
		if int(s["team"]) == 2:
			has_blue = true
	_check(has_red and has_blue, "opening squads are not on two teams (red=%s blue=%s)" % [has_red, has_blue])
	print("  ships=%d red=%s blue=%s" % [ships.size(), has_red, has_blue])
	# Roster snapshot carries team + aggression.
	if ships.size() > 0:
		var aggro: Array = ships[0]["aggro"]
		_check(not aggro.is_empty(), "spawned ship has no aggression set")
		print("  first ship aggro: %s" % str(aggro))


func _check_combat() -> void:
	print("── combat ─────────────────────────────────────────")
	print("  any ship damaged during the fight: %s" % _combat_observed)
	_check(_combat_observed, "no AI ship took damage — team combat is not happening")


## Teleport one live ship well outside the box and give it outward velocity;
## the per-frame bound must pull it back inside.
func _beg_bounding_box_test() -> void:
	var ships := _ships()
	if ships.is_empty():
		return
	_box_ship = ships[0]["node"]
	if _box_ship != null and is_instance_valid(_box_ship) and _box_ship.model != null:
		_box_ship.model.global_position = Vector3(12000.0, 6000.0, 12000.0)
		_box_ship.model.velocity = Vector3(500.0, 300.0, 500.0)


func _check_bounding_box() -> void:
	print("── bounding box ───────────────────────────────────")
	if _box_ship == null or not is_instance_valid(_box_ship) or _box_ship.model == null:
		_check(false, "no ship to test the bounding box with")
		return
	var p := _box_ship.model.global_position
	var half := AiTestArena.ARENA_HALF
	var inside := absf(p.x) <= half.x + 1.0 and absf(p.y) <= half.y + 1.0 and absf(p.z) <= half.z + 1.0
	print("  ship after teleport+drift: %s (inside=%s)" % [p, inside])
	_check(inside, "AI ship escaped the arena box (%.0f, %.0f, %.0f)" % [p.x, p.y, p.z])


func _check_focus() -> void:
	print("── focus ──────────────────────────────────────────")
	if _focus_ship == null or not is_instance_valid(_focus_ship):
		_check(false, "no ship to focus")
		return
	_check(_root.camera_rig.mode == FlightCamera.Mode.TARGET, "focus did not enter TARGET mode")
	_check(_root.camera_rig.focus_node == _focus_ship, "camera is not focused on the chosen ship")
	var cam_dist := _root.camera_rig.camera.global_position.distance_to(_focus_ship.global_position)
	print("  camera %.0f m from focused ship" % cam_dist)
	_check(cam_dist < 1500.0, "focus camera is not near the ship")


func _check_take_control() -> void:
	print("── take control ───────────────────────────────────")
	var ships := _ships()
	if ships.is_empty():
		_check(false, "no ships to control")
		return
	var ship: AiShip = ships[0]["node"]
	_root.take_control(ship)
	_check(_root.controlled_ai == ship, "take_control did not set controlled_ai")
	_check(ship._ai_paused, "controlled ship's AI was not paused")
	_check(_root.camera_rig.mode == FlightCamera.Mode.CHASE, "camera did not move to chase on take_control")
	_root.set_throttle(0.7)
	_check(ship.model.command.throttle > 0.5, "throttle did not route to the controlled ship")
	print("  throttle routed to controlled ship: %.2f" % ship.model.command.throttle)
	_root.leave_control()
	_check(_root.controlled_ai == null, "leave_control did not clear controlled_ai")
	_check(not ship._ai_paused, "controlled ship's AI did not resume")
	_check(_root.camera_rig.mode == FlightCamera.Mode.TARGET, "camera did not return to free pan on leave_control")


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
