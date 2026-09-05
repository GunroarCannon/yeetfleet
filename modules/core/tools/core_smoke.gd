## Headless smoke test for modules/core: the registry, session parsing and the
## deterministic context RNG. No scene, no window, no other module.
##
##     godot --headless --path . --script modules/core/tools/core_smoke.gd
extends SceneTree

var _failures: Array[String] = []
# Failures already reported by an earlier section, so each line can say whether
# its own checks passed rather than whether the run as a whole has.
var _reported := 0


func _initialize() -> void:
	print("── core module smoke test ──────────────────────────────")
	_check_default_session()
	_check_session_parsing()
	_check_registry()
	_check_context_determinism()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Close one section of the report. Prints ok only if nothing failed inside it —
## a line that says ok next to a failure is worse than no line at all.
func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


## A process that never ran the launcher must still have sane Session state —
## deterministically unseeded, not random.
func _check_default_session() -> void:
	_check(Session.seed == 0, "default seed is not 0 (was %d)" % Session.seed)
	_check(not Session.seed_forced, "default seed is marked forced")
	_check(Session.boot_module == "", "default boot_module is not empty")
	_check(not Session.boot_requested, "default boot is requested")
	_check(Session.mode == Session.Mode.SANDBOX, "default mode is not SANDBOX")
	_done("Session defaults before start()")


func _check_session_parsing() -> void:
	Session.read_cmdline(PackedStringArray(["--module=flight", "--seed=99", "--mode=career"]))
	_check(Session.boot_requested, "--module= did not request a boot")
	_check(Session.boot_module == "flight", "boot_module is %s, expected flight" % Session.boot_module)
	_check(Session.seed == 99, "seed is %d, expected 99" % Session.seed)
	_check(Session.seed_forced, "--seed=99 was not recorded as forced")
	_check(Session.mode == Session.Mode.CAREER, "--mode=career was not parsed")

	# A later argument wins; a bad seed warns and leaves the good one alone.
	Session.read_cmdline(PackedStringArray(["--seed=banana", "--module=arena"]))
	_check(Session.seed == 99, "a bad --seed clobbered the good seed")
	_check(Session.seed_forced, "bad --seed cleared the forced flag")
	_check(Session.boot_module == "arena", "second --module= did not override the first")
	Session.read_cmdline(PackedStringArray(["--mode=SANDBOX"]))
	_check(Session.mode == Session.Mode.SANDBOX, "--mode= is not case-insensitive")

	# Non-argument tokens are engine noise and must be ignored.
	Session.read_cmdline(PackedStringArray(["res://something.tscn", "--headless"]))
	_check(Session.boot_module == "arena", "a plain arg disturbed the parsed boot module")
	_done("--module= / --seed= / --mode= parsing")


## The registry must answer both directions — a module id to its scene, and the
## answer to "is this module real" — and every scene it points at must exist.
func _check_registry() -> void:
	var expected := ["ship_builder", "flight", "arena"]
	_check(ModuleRegistry.ids() == expected, "ids() is %s, expected %s" % [
		ModuleRegistry.ids(), expected,
	])
	_check(ModuleRegistry.has("ship_builder"), "registry does not know ship_builder")

	# Anti-regression: the paths the scene roots used to hardcode, verbatim.
	var known := {
		"ship_builder": "res://modules/ship_builder/ship_builder.tscn",
		"flight": "res://modules/flight/flight_test.tscn",
		"arena": "res://modules/arena/arena.tscn",
	}
	for id in expected:
		var path := ModuleRegistry.scene_path(id)
		_check(path == known[id], "%s resolves to %s, expected %s" % [id, path, known[id]])
		_check(path != "" and FileAccess.file_exists(path), "%s scene missing: %s" % [id, path])
		if path != "" and FileAccess.file_exists(path):
			# Loads the .tscn, which parses the root script and every class it
			# names — the cheapest end-to-end check that the registered module
			# still compiles against this registry.
			var packed := load(path)
			_check(packed is PackedScene, "%s is not a loadable PackedScene" % path)

	_check(ModuleRegistry.scene_path("nope") == "", "unknown id resolved to a scene")
	_check(not ModuleRegistry.has("nope"), "has() says yes to an unknown id")
	_check(ModuleRegistry.display_name("nope") == "nope", "display_name does not degrade to the id")
	_check(ModuleRegistry.tagline("flight") != "", "known module has no picker tagline")
	_done("ModuleRegistry id <-> scene")


## The plan's determinism promise (§0.3) starts here: a context built after a
## seeded session must roll the same stream as another context built from the
## same seed — otherwise "identical seed, identical inputs" is uncheckable.
func _check_context_determinism() -> void:
	Session.seed = 123456
	var a := NebulaContext.new()
	var b := NebulaContext.new()
	_check(a.rng != null, "context has no rng")
	_check(a.rng.seed == 123456, "context rng did not take the session seed")
	_check(a.gravity == null, "a fresh context should have no gravity yet")
	var a_roll := a.rng.randi()
	var b_roll := b.rng.randi()
	_check(a_roll == b_roll, "two same-seed contexts rolled different streams")
	_check(a.rng.randi() == b.rng.randi(), "same-seed contexts diverged after the first roll")
	_done("NebulaContext deterministic RNG")


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ " + f)
		quit(1)
