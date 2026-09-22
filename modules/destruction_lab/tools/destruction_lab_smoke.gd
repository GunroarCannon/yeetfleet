## Headless smoke test for DestructionLab:
## Validates scene boot, camera controls, object spawning, raycast selection,
## explosion effects, shockwaves, impacts, and physical shatter/destruction.
##
##     godot --headless --path . --script modules/destruction_lab/tools/destruction_lab_smoke.gd
extends SceneTree

const DestructionLabRoot = preload("res://modules/destruction_lab/scripts/destruction_lab_root.gd")

var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── Destruction Lab smoke test ─────────────────────────")
	_run_tests()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-48s %s" % [label, mark])


func _run_tests() -> void:
	var scene_path := "res://modules/destruction_lab/destruction_lab.tscn"
	_check(FileAccess.file_exists(scene_path), "scene file exists: %s" % scene_path)
	
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "packed scene loads")
	_done("Scene resource loading")

	var lab: DestructionLabRoot = packed.instantiate() as DestructionLabRoot
	_check(lab != null, "instantiates DestructionLabRoot")
	root.add_child(lab)
	_done("Scene instantiation and tree add")

	# Wait 2 frames for _ready() to complete
	await process_frame
	await process_frame

	# Check initial scene contents
	_check(lab._objects_root != null, "_objects_root created")
	_check(lab._debris_root != null, "_debris_root created")
	_check(lab._effects_root != null, "_effects_root created")
	_check(lab._cam != null, "camera initialized")
	_check(lab._objects_root.get_child_count() > 0, "default objects spawned")
	_done("Scene setup and default targets")

	# Test camera mode toggling and movement
	_check(lab._cam_mode == DestructionLabRoot.CamMode.FREE_FLY, "starts in FREE_FLY mode")
	lab.toggle_camera_mode()
	_check(lab._cam_mode == DestructionLabRoot.CamMode.ORBIT, "switches to ORBIT mode")
	lab.toggle_camera_mode()
	_check(lab._cam_mode == DestructionLabRoot.CamMode.FREE_FLY, "switches back to FREE_FLY mode")
	lab._process_free_fly_movement(0.016)
	_done("Camera modes & movement")

	# Test object spawning
	var initial_obj_count := lab._objects_root.get_child_count()
	var mega := lab._spawn_mega_ship(LargeCraftGenerator.Archetype.MOTHERSHIP, Vector3(0.0, 50.0, 0.0))
	_check(mega != null and is_instance_valid(mega), "mega ship spawned")
	
	var fighter := lab._spawn_fighter_ship(Vector3(30.0, 30.0, 0.0))
	_check(fighter != null and is_instance_valid(fighter), "fighter ship spawned")

	var planet := lab._spawn_planet_target(Vector3(-100.0, 0.0, -100.0))
	_check(planet != null and is_instance_valid(planet), "planet spawned")

	var prev_deb := lab._debris_root.get_child_count()
	lab._spawn_asteroid_cluster(Vector3(60.0, 0.0, 0.0), 6)
	_check(lab._debris_root.get_child_count() > prev_deb, "asteroid cluster spawned")

	prev_deb = lab._debris_root.get_child_count()
	lab._spawn_fuel_tanks(Vector3(-40.0, -20.0, 0.0))
	_check(lab._debris_root.get_child_count() > prev_deb, "fuel tanks spawned")

	_check(lab._objects_root.get_child_count() >= initial_obj_count + 3, "objects registered in tree")
	_done("Object spawner suite")

	# Test selection
	lab.select_object(mega, Vector3(0.0, 50.0, 0.0), Vector3.UP)
	_check(lab._selected_node == mega, "object selection binds target")
	_check(lab._reticle_node.visible, "selection reticle active")
	lab.frame_selected_target()
	_done("3D object selection & focus")

	# Test explosions
	lab.trigger_heavy_explosion()
	lab.trigger_plasma_bomb()
	lab.trigger_antimatter_core()
	lab.trigger_cascade_detonation()
	lab.trigger_supernova()
	_check(lab._effects_root.get_child_count() > 0, "explosion effects spawned into scene")
	_done("Explosion effects suite")

	# Test waves
	lab.trigger_shockwave_ring()
	lab.trigger_spherical_blast_wave()
	lab.trigger_gravitational_implosion()
	lab.trigger_emp_wave()
	_done("Wave & shock pulse suite")

	# Test impacts
	lab.trigger_railgun_strike()
	lab.trigger_thermal_lance()
	lab.trigger_meteor_strike()
	lab.trigger_missile_salvo()
	_done("Impacts & strike suite")

	# Test destruction and fracture
	lab.select_object(mega, Vector3(0.0, 50.0, 0.0), Vector3.UP)
	lab.trigger_shatter_radius()
	_check(lab._debris_root.get_child_count() > 0, "shatter creates physics debris")

	lab.select_object(planet, planet.global_position, Vector3.UP)
	lab.trigger_planetary_annihilation()
	_check(not planet.visible, "planet annihilated and hidden")
	_done("Destruction & shatter mechanics")

	# Test the comparison machinery: the catalog drives the picker, a single effect
	# can be aimed at an arbitrary point, and the row spawns the centred ones.
	_check(lab._effects.size() > 10, "effect catalog is suspiciously short (%d)" % lab._effects.size())
	var centred := 0
	var has_strike := false
	for entry: Dictionary in lab._effects:
		if bool(entry.get("centered", false)):
			centred += 1
		else:
			has_strike = true
	_check(centred > 0, "no effect is flagged as position-centred, so a row would be empty")
	_check(has_strike, "no camera-origin strike is flagged, so the row filter is untested")
	_check(lab._effect_picker != null, "the effect picker was not built")
	_check(
		lab._effect_picker != null and lab._effect_picker.item_count == lab._effects.size(),
		"the picker does not list every catalog entry"
	)

	# Aiming one trigger at an arbitrary point is what makes the row possible.
	var probe := Vector3(1234.0, 5.0, -678.0)
	lab.spawn_effect_at(0, probe)
	_check(not lab._has_action_override, "the action override was not cleared after a spawn")

	lab.select_object(null, probe, Vector3.UP)
	lab.compare_effects_row()
	_check(lab._effects_root.get_child_count() > 0, "the comparison row spawned nothing")
	_check(not lab._has_action_override, "the action override leaked out of the comparison row")
	_done("Effect catalog, picker and comparison row")

	# Test cleanup and reset
	lab.clear_all_debris()
	_check(lab._debris_root.get_child_count() == 0, "clear_all_debris empties debris root")

	lab.reset_scene()
	_check(lab._objects_root.get_child_count() == 1, "reset_scene restores single fresh target")
	_done("Debris cleanup and scene reset")

	_finish(lab)


func _finish(lab: Node) -> void:
	if lab != null and is_instance_valid(lab):
		lab.queue_free()

	print("")
	if _failures.is_empty():
		print("── PASS ───────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ──────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ %s" % f)
		quit(1)
