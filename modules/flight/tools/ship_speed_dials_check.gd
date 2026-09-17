## Verifies the two ship-speed dials are genuinely independent: turning the
## player's down must not slow the AI, and turning the AI's down must not slow
## the player. That separation is the entire point of splitting one dial into
## two, and it is invisible when it breaks — a shared multiplier looks correct
## until someone tries to slow a fight down without changing their own ship.
##
##     godot --path . --headless --script modules/flight/tools/ship_speed_dials_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const SETTLE_FRAMES := 30

var _root: FlightRoot
var _frames := 0
var _failures: Array[String] = []
var _npc: AiShip = null


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
	if _frames < SETTLE_FRAMES:
		return false
	if _npc == null:
		for ship in _root._ai_spawner.ships():
			if is_instance_valid(ship) and ship._alive and ship.model != null:
				_npc = ship
				break
	if _npc == null:
		if _frames > SETTLE_FRAMES + 120:
			_check(false, "the spawner produced no ships to test against")
			return _finish()
		return false
	return _run()


func _run() -> bool:
	var player := _root.model
	var player_top := player.top_speed
	var npc_top := _npc.model.top_speed
	print("── ship speed dials ───────────────────────────────")
	print("  before: player %.0f m/s (scale %.2f), other ship %.0f m/s (scale %.2f)" % [
		player_top, player.speed_scale, npc_top, _npc.model.speed_scale,
	])

	# The player's dial: halves the player's ship, and must not touch the AI.
	_root.set_player_speed_scale(0.5)
	print("  player ×0.5: player %.0f m/s, other ship %.0f m/s" % [
		player.top_speed, _npc.model.top_speed,
	])
	_check(is_equal_approx(player.top_speed, player_top * 0.5),
		"the player's dial did not halve the player's ship (%.0f -> %.0f)" % [player_top, player.top_speed])
	_check(is_equal_approx(_npc.model.top_speed, npc_top),
		"the player's dial moved an AI ship (%.0f -> %.0f)" % [npc_top, _npc.model.top_speed])
	_check(is_equal_approx(_npc.model.speed_scale, 1.0),
		"the player's dial changed an AI ship's own scale (%.2f)" % _npc.model.speed_scale)

	# The AI dial: doubles every other ship, and must not touch the player's —
	# which is still where the player's own dial left it.
	_root.set_npc_speed_scale(2.0)
	print("  others ×2.0: player %.0f m/s, other ship %.0f m/s" % [
		player.top_speed, _npc.model.top_speed,
	])
	_check(is_equal_approx(_npc.model.top_speed, npc_top * 2.0),
		"the AI dial did not double an AI ship (%.0f -> %.0f)" % [npc_top, _npc.model.top_speed])
	_check(is_equal_approx(player.top_speed, player_top * 0.5),
		"the AI dial moved the player's ship (%.0f, expected %.0f)" % [player.top_speed, player_top * 0.5])

	# Back to neutral: both dials must land exactly where they started, or every
	# drag of a slider would ratchet the ship's speed.
	_root.set_player_speed_scale(1.0)
	_root.set_npc_speed_scale(1.0)
	print("  reset: player %.0f m/s, other ship %.0f m/s" % [player.top_speed, _npc.model.top_speed])
	_check(is_equal_approx(player.top_speed, player_top),
		"the player's dial did not restore (%.0f, expected %.0f)" % [player.top_speed, player_top])
	_check(is_equal_approx(_npc.model.top_speed, npc_top),
		"the AI dial did not restore (%.0f, expected %.0f)" % [_npc.model.top_speed, npc_top])

	return _finish()


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
