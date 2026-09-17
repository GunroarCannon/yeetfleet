## Verifies the floating aggro indicators: a ship that has picked the player and
## is steering at them gets a billboarded icon above its hull, a ship that is
## minding its own business does not, and the icon goes away when the ship stops
## being interested — the marker set is rebuilt every frame and must not leak
## nodes as a furball churns.
##
##     godot --path . --headless --script modules/flight/tools/aggro_indicator_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
## The scene's spawner fills its roster over a couple of frames.
const SETTLE_FRAMES := 30

var _root: FlightRoot
var _frames := 0
var _failures: Array[String] = []
var _ship: AiShip = null


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
	if _frames > SETTLE_FRAMES and _ship == null:
		for ship in _root._ai_spawner.ships():
			if is_instance_valid(ship) and ship._alive:
				_ship = ship
				break
	return _run()


func _run() -> bool:
	if _ship == null:
		if _frames < SETTLE_FRAMES + 60:
			return false
		_check(false, "the spawner produced no ships to test against")
		return _finish()

	_check_predicate()
	_check_marker_appears()
	_check_marker_clears()
	return _finish()


## The predicate itself: after the player, and steering at them. Pursuit and
## investigate both count; patrol and everything else do not.
func _check_predicate() -> void:
	_ship.current_target = null
	_ship.behaviour.state = AiBehaviour.State.PURSUIT
	_check(not _ship.is_aggroed_to_player(), "a ship with no target read as aggroed")

	_ship.current_target = _root.model
	_ship.behaviour.state = AiBehaviour.State.PATROL
	_check(not _ship.is_aggroed_to_player(), "a patrolling ship read as aggroed")

	for state: int in [AiBehaviour.State.PURSUIT, AiBehaviour.State.INVESTIGATE]:
		_ship.behaviour.state = state
		_check(_ship.is_aggroed_to_player(), "a ship targeting the player was not aggroed")

	_ship.behaviour.state = AiBehaviour.State.FLEE
	_check(not _ship.is_aggroed_to_player(), "a fleeing ship read as aggroed")


## The marker: created, parented into the scene, and floating above the hull
## rather than inside it.
func _check_marker_appears() -> void:
	_ship.current_target = _root.model
	_ship.behaviour.state = AiBehaviour.State.PURSUIT
	_root._update_aggro_indicators()
	var marker := _root._aggro_markers.get(_ship) as Sprite3D
	if marker == null:
		_check(false, "no indicator appeared over a ship chasing the player")
		return
	_check(marker.get_parent() == _root, "the indicator is not in the scene")
	_check(marker.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "the indicator does not billboard")
	# The icon art is white; the marker has to carry the threat colour itself, or
	# it reads as a smudge of scenery over a dark hull.
	_check(marker.texture != null, "the indicator has no icon texture")
	_check(marker.modulate.r > 0.7 and marker.modulate.g < 0.7 and marker.modulate.b < 0.7,
		"the indicator is not red (modulate %s)" % marker.modulate)

	var ship_pos := _ship.model.global_position
	var up: Vector3 = _ship.model.global_transform.basis.y
	var offset := marker.global_position - ship_pos
	var along_up := offset.dot(up)
	var hull_top := _root.AGGRO_MARKER_MARGIN + (_ship._view.aabb.end.y if _ship._view != null else 0.0)
	print("  indicator %.1f m above the hull along its own up (hull top %.1f m), %.1f m off-axis"
		% [along_up, hull_top, offset.dot(_ship.model.global_transform.basis.x)])
	_check(along_up > 0.0, "the indicator is not above the ship (%.1f m along its up)" % along_up)
	_check(along_up > hull_top * 0.5, "the indicator is buried in the hull (%.1f m, hull top %.1f m)" % [along_up, hull_top])
	_check(absf(offset.dot(_ship.model.global_transform.basis.x)) < 1.0,
		"the indicator drifted off the ship's axis")

	# A second frame must reuse the node, not stack a new one on top of it.
	_root._update_aggro_indicators()
	_check(_root._aggro_markers.get(_ship) == marker, "the indicator was rebuilt instead of reused")


## Losing interest must take the icon with it, and must not leave the node behind.
func _check_marker_clears() -> void:
	_ship.behaviour.state = AiBehaviour.State.PATROL
	_root._update_aggro_indicators()
	_check(not _root._aggro_markers.has(_ship), "the indicator stayed after the ship lost interest")

	# Markers off entirely: a ship chasing the player gets nothing.
	_ship.behaviour.state = AiBehaviour.State.PURSUIT
	Session.hud_markers = false
	_root._update_aggro_indicators()
	_check(not _root._aggro_markers.has(_ship), "an indicator appeared with the Markers toggle off")
	Session.hud_markers = true


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
