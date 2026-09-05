## Verifies the high-res toggle rebuilds geometry denser instead of zooming.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/high_res_check.gd
##
## Instantiates the flight test bed twice — once with high-res off, once with it
## on — and compares the procedural geometry: starfield density, planet surface
## resolution, atmosphere sphere segments, plus the window size (which must NOT
## change; that was the "zoom") and the 3D render scale.
##
## Stepped from _process like the flight smoke test: awaiting process_frame from
## _initialize proved fragile, and this is the pattern the repo's other SceneTree
## tools already use.
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const FRAMES_PER_STEP := 15

enum { PH_MEASURE_NORMAL, PH_MEASURE_HIGH, PH_DONE }

var _root: FlightRoot
var _phase := PH_MEASURE_NORMAL
var _frames := 0
var _settle := 0
var _normal: Dictionary
var _high: Dictionary


func _initialize() -> void:
	# Straight into the first measurement on the first processed frame.
	pass


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAMES_PER_STEP:
		return false
	_frames = 0
	match _phase:
		PH_MEASURE_NORMAL:
			_normal = _measure(false)
			_report("normal", _normal)
			_phase = PH_MEASURE_HIGH
		PH_MEASURE_HIGH:
			_high = _measure(true)
			_report("high", _high)
			_phase = PH_DONE
		PH_DONE:
			return _finish(_normal, _high)
	return false


func _measure(high_res: bool) -> Dictionary:
	if _root != null:
		_root.queue_free()
		_root = null
	# One extra beat so the previous root is gone before the next builds.
	# FRAMES_PER_STEP covers it; the settle frames are spent across the step.
	var packed := load(SCENE_PATH) as PackedScene
	FlightRoot._high_res_on = high_res
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false

	var out := {
		"window_size": Vector2i(root.size),
		"render_scale": root.scaling_3d_scale,
	}

	var space := _root.space
	print("  space=%s stars=%s nebula=%s body=%s" % [
		space, space.get_node_or_null("Sky/Stars"),
		space.get_node_or_null("Sky/Nebula"), space.get_node_or_null("Planet/Body"),
	])
	if space == null:
		return out
	var stars := space.get_node_or_null("Sky/Stars").mesh as ArrayMesh
	if stars != null:
		out["stars_vertices"] = stars.surface_get_array_len(0)

	var nebula := space.get_node_or_null("Sky/Nebula").mesh as ArrayMesh
	if nebula != null:
		out["nebula_vertices"] = nebula.surface_get_array_len(0)

	# "Planet" is a Node3D pivot; the actual Planet instance is its "Body" child.
	var planet := space.get_node_or_null("Planet/Body")
	if planet != null and planet is Planet:
		out["planet_resolution"] = (planet as Planet).data.sphere_resolution

	# The atmosphere is the Planet's only SphereMesh child (the body is a
	# PlanetGenerator's ArrayMesh, the ring is a disc).
	if planet != null:
		var atmosphere: SphereMesh = null
		for child in planet.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.mesh is SphereMesh:
				atmosphere = mi.mesh as SphereMesh
				break
		if atmosphere != null:
			out["atmosphere_radial"] = atmosphere.radial_segments
			out["atmosphere_rings"] = atmosphere.rings
	return out


func _report(tag: String, m: Dictionary) -> void:
	print("── %s ─────────────────────────────────────────" % tag)
	for key: String in m:
		print("  %-20s %s" % [key, m[key]])


func _finish(normal: Dictionary, high: Dictionary) -> bool:
	var problems: Array[String] = []
	var n_size: Vector2i = normal.get("window_size", Vector2i.ZERO)
	var h_size: Vector2i = high.get("window_size", Vector2i.ZERO)
	if h_size != n_size:
		problems.append("the window resized — that is the zoom bug: %s -> %s" % [n_size, h_size])
	if float(high.get("render_scale", 1.0)) <= 1.0:
		problems.append("high res did not raise the 3D render scale")
	for key: String in ["stars_vertices", "nebula_vertices", "planet_resolution", "atmosphere_radial", "atmosphere_rings"]:
		if int(high.get(key, 0)) <= int(normal.get(key, 0)):
			problems.append("%s did not get denser (%s -> %s)" % [key, normal.get(key, 0), high.get(key, 0)])

	print("")
	if problems.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
		return true
	print("── FAIL (%d) ─────────────────────────────────────────────" % problems.size())
	for p in problems:
		print("  · " + p)
	quit(1)
	return true
