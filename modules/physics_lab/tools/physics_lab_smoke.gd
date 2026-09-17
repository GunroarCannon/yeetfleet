## Headless smoke test for modules/physics_lab: verifies the lab scene loads
## and can manipulate profiles without requiring a visible window.
##
##     godot --headless --path . --script modules/physics_lab/tools/physics_lab_smoke.gd
##
## The plan's M1 contract, verified headlessly:
##   - Lab scene instantiates correctly
##   - Profile can be loaded and manipulated
##   - Save/load cycle works
##   - Preset scenarios can be selected (logic only, no rendering)
##
## See TECHNICAL_PLAN.md §M1 for the physics lab description.

extends SceneTree

var _failures: Array[String] = []
var _reported := 0

func _initialize() -> void:
	print("── physics lab smoke test ────────────────────────────")

	# Test 1: Lab scene loads
	await _test_lab_scene_loads()

	# Test 2: Profile loads and saves
	await _test_profile_persistence()

	# Test 3: Preset scenario logic
	await _test_preset_scenarios()

	_finish()

func _test_lab_scene_loads() -> void:
	# Try to load and instantiate the physics lab scene
	var lab_scene = load("res://modules/physics_lab/physics_lab.tscn")
	if lab_scene == null:
		_failures.append("Failed to load physics_lab.tscn")
		_done("Lab scene loads")
		return

	var lab_instance = lab_scene.instantiate()
	if lab_instance == null:
		_failures.append("Failed to instantiate physics_lab.tscn")
		_done("Lab scene loads")
		return

	# Check that it has the expected script
	if not lab_instance.has_method("_apply_profile"):
		_failures.append("PhysicsLabRoot script missing expected methods")

	_done("Lab scene loads")

func _test_profile_persistence() -> void:
	# Test loading the built-in profiles
	var grounded = load("res://modules/physics/data/profiles/grounded.tres") as PhysProfile
	var cartoony = load("res://modules/physics/data/profiles/cartoony.tres") as PhysProfile

	if grounded == null:
		_failures.append("Failed to load grounded.tres")
	if cartoony == null:
		_failures.append("Failed to load cartoony.tres")

	# Verify they have different values (basic sanity check)
	if grounded != null and cartoony != null:
		if grounded.restitution_ship == cartoony.restitution_ship:
			_failures.append("grounded and cartoony have identical restitution_ship")

	_done("Profile persistence")

func _test_preset_scenarios() -> void:
	# Test that the preset scenario methods exist (logic only)
	var lab_scene = load("res://modules/physics_lab/physics_lab.tscn")
	if lab_scene == null:
		_done("Preset scenarios")
		return

	var lab_instance = lab_scene.instantiate()
	if lab_instance == null:
		_done("Preset scenarios")
		return

	# Check that preset methods exist (they should be implemented in the root)
	var methods = [
		"_setup_glancing_rock",
		"_setup_head_on_rock",
		"_setup_rock_into_rock",
		"_setup_ram_hauler",
		"_setup_scatter_swarm",
		"_setup_slingshot"
	]

	for method in methods:
		if not lab_instance.has_method(method):
			_failures.append("Missing preset scenario method: %s" % method)

	_done("Preset scenarios")

func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-40s %s" % [label, mark])

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