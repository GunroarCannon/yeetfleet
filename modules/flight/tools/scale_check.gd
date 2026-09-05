## Verifies the planet size/spacing settings flow through to the scene, gravity
## and spawn: bigger radii, wider gaps, and a spawn orbit that still holds.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/scale_check.gd
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0
var _phase := 0
var _failures: Array[String] = []


func _initialize() -> void:
	# Set a dramatic scale BEFORE the scene builds.
	Session.planet_scale = 3.0
	Session.planet_spacing = 2.0
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames >= 30:
		_phase = 1
	if _phase == 1:
		return _finish()
	return false


func _finish() -> bool:
	var space := _root.space
	var planet := space.get_node_or_null("Planet/Body") as Planet
	print("── scale check ────────────────────────────────────")
	print("  planet_radius = %.0f (expected 4200 = 1400×3)" % space.planet_radius)
	print("  planet2 dist  = %.0f (expected ~%.0f = 10033×2)" % [
		space.planet2_centre.length(), Vector3(9000.0, -1200.0, 3600.0).length() * 2.0,
	])
	_check(absf(space.planet_radius - 1400.0 * 3.0) < 1.0, "planet radius did not scale (%.0f)" % space.planet_radius)
	_check(planet != null and absf(planet.data.planet_radius - 4200.0) < 1.0, "planet body radius did not scale")
	_check(absf(space.planet2_centre.length() - Vector3(9000.0, -1200.0, 3600.0).length() * 2.0) < 100.0, "planet spacing did not scale")
	if planet != null:
		print("  planet.data.planet_radius = %.0f" % planet.data.planet_radius)

	# Gravity should have registered the scaled body (radius 4200).
	var body := _root.gravity.nearest_body(space.planet_centre)
	_check(body != null and absf(body.radius - 4200.0) < 1.0, "gravity body radius did not scale")

	# The spawn orbit should still hold at the scaled distance (~3×4000). The
	# ship is already flying its orbit, so a few percent of orbital drift is fine.
	var d := _root.model.global_position.distance_to(space.planet_centre)
	print("  spawn orbit dist = %.0f (expected ~%.0f)" % [d, 4200.0 * 2.857])
	_check(absf(d - 4200.0 * 2.857) < 800.0, "spawn did not orbit the scaled planet (%.0f m)" % d)

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
