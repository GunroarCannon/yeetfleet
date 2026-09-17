## Perf of the solar-system-gen -> flight handoff, measured two ways: the raw
## [SolarSystemGenerator] cost in isolation, and the real [code]flight_test.tscn[/code]
## scene booted into [constant FlightRoot.Location.GENERATED_SYSTEM] the way the
## lab's "Enter flight test" button boots it.
##
## Exists because the handoff used to inherit the lab's time_scale and to promote
## its belts to LIVE bodies: one frame could cost ~170 ms. Keep it runnable — a
## regression here is invisible until someone flies a big system.
##
##     godot --path . --headless --script modules/flight/tools/generated_system_perf.gd
extends SceneTree

const FRAME := 1.0 / 60.0
const SCENE_PATH := "res://modules/flight/flight_test.tscn"
const BUDGET_MS := 16.6
## Frames discarded before timing (scene build, first physics passes, JIT-ish warm-up).
const WARMUP_FRAMES := 90
const MEASURED_FRAMES := 300

var _root: FlightRoot
var _frames := 0
var _last_usec := 0
var _worst_ms := 0.0
var _total_ms := 0.0
var _measured := 0
var _failures: Array[String] = []


func _ms_per_call(calls: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in calls:
		fn.call()
	return float(Time.get_ticks_usec() - t0) / float(calls) / 1000.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## The worst case a player can hand this scene: the lab left on maximum
## fast-forward, with belts spawned by hand, then "Enter flight test".
func _worst_case_generator() -> SolarSystemGenerator:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 55
	gen.planet_count = 6
	gen.planet_belt_chance = 1.0
	gen.wide_belt_chance = 1.0
	gen.generate_system()
	gen.spawn_asteroid_belt(Vector3.ZERO, 5000.0, 70, 250.0, "", true)
	gen.spawn_asteroid_belt(Vector3.ZERO, 3000.0, 24, 60.0, "", true)
	return gen


func _initialize() -> void:
	print("── generator in isolation ──────────────────────────────")
	var gen := _worst_case_generator()
	print("  bodies %d, belts %d (all LIVE, as the lab leaves them)" % [gen.bodies.size(), gen.belts.size()])
	print("  generate_system()  [scene-change hitch] %8.3f ms" % _ms_per_call(3, gen.generate_system))
	print("  _physics_process   [@1x, lab default]   %8.3f ms" % _ms_per_call(20, func() -> void: gen._physics_process(FRAME)))
	gen.time_scale = 60.0
	print("  _physics_process   [@60x fast-forward]  %8.3f ms" % _ms_per_call(10, func() -> void: gen._physics_process(FRAME)))
	print("")

	print("── live flight scene, GENERATED_SYSTEM ─────────────────")
	var handed_off := _worst_case_generator()
	var planets := handed_off.bodies.filter(
		func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET
	)
	Session.pending_solar_system = SolarSystemData.from_generator(handed_off)
	Session.pending_spawn_body_name = String(planets[0]["name"]) if not planets.is_empty() else ""
	Session.flight_location = FlightRoot.Location.GENERATED_SYSTEM
	Session.solar_time_scale = 60.0

	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	# The scene's own checks wait for _finish: a node added under SceneTree.root
	# is not in the tree until the loop runs, so _ready (and everything it builds)
	# has not happened yet here.


## Time each frame from the previous callback's stamp: the gap is the work the
## engine just did, which is the number that decides whether flying stutters.
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_usec != 0 and _frames > WARMUP_FRAMES:
		var ms := float(now - _last_usec) / 1000.0
		_total_ms += ms
		_worst_ms = maxf(_worst_ms, ms)
		_measured += 1
	_last_usec = now
	_frames += 1
	if _measured >= MEASURED_FRAMES:
		return _finish()
	return false


func _finish() -> bool:
	var avg := _total_ms / float(_measured)
	print("")
	print("  %d frames after %d warm-up:" % [_measured, WARMUP_FRAMES])
	print("    mean frame %8.3f ms   (%.0f fps)" % [avg, 1000.0 / maxf(avg, 0.001)])
	print("    worst frame %7.3f ms" % _worst_ms)

	if _root.generated_system != null:
		_check(
			is_equal_approx(_root.generated_system.time_scale, 1.0),
			"the lab's fast-forward leaked into the flight scene (time_scale %.1f)" % _root.generated_system.time_scale
		)
		_check(not _root.generated_system.belts_simulate, "the flight scene is simulating belt rock bodies")
		var live := 0
		for belt in _root.generated_system.belts:
			if int(belt["state"]) == SolarSystemGenerator.BeltState.LIVE:
				live += 1
		print("    simulated bodies %d, belts %d (LIVE %d)"
			% [_root.generated_system.bodies.size(), _root.generated_system.belts.size(), live])
		_check(live == 0, "%d belt(s) promoted to LIVE in the flight scene" % live)
	else:
		_check(false, "no generated_system was built")

	_check(avg < BUDGET_MS, "mean frame %.1f ms is over the 60fps budget" % avg)
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
