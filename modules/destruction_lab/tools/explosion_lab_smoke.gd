extends SceneTree

func _init() -> void:
	_run()

func _run() -> void:
	print("--- Running Destruction & Explosion Lab Smoke Test ---")
	var scene: PackedScene = load("res://modules/destruction_lab/destruction_lab.tscn")
	if scene == null:
		print("FAIL: Could not load destruction_lab.tscn")
		quit(1)
		return
	
	var lab = scene.instantiate() as DestructionLabRoot
	root.add_child(lab)
	
	await process_frame
	await process_frame

	print("1. Testing DestructionLabRoot initialization...")
	assert(lab != null, "Lab root instantiated")
	
	print("2. Testing Explosion Studio modal...")
	lab.toggle_explosion_studio()
	assert(lab._studio_modal != null, "Studio modal exists")
	assert(lab._studio_modal.visible == true, "Studio modal is visible")
	
	print("3. Testing Slot selection and switching...")
	lab._studio_slot_picker.selected = 1 # Capital Ship Death
	lab._on_studio_slot_selected()
	var current_slot = lab._get_current_selected_slot()
	assert(current_slot == ExplosionRegistry.SLOT_CAPITAL_DEATH, "Slot correctly selected")
	
	print("4. Testing Live Parameter Tuning...")
	lab._studio_scale_slider.value = 4.2
	lab._on_studio_scale_changed(4.2)
	var assign = ExplosionRegistry.get_slot_assignment(ExplosionRegistry.SLOT_CAPITAL_DEATH)
	assert(is_equal_approx(assign["scale"], 4.2), "Scale assignment updated live")
	
	print("5. Testing Detonation Trigger in 3D scene...")
	lab._test_detonate_current_slot()
	await process_frame
	
	print("6. Testing Saving Assignments to JSON...")
	var ok = ExplosionRegistry.save_assignments()
	assert(ok, "Assignments saved to disk successfully")
	
	print("7. Testing Loading Preset Template...")
	ExplosionRegistry.apply_preset_template("retro_vector")
	lab._refresh_studio_fields()
	var rv_assign = ExplosionRegistry.get_slot_assignment(ExplosionRegistry.SLOT_SHIP_DEATH)
	assert(rv_assign["effect_id"] == "vector_shatter", "Preset template applied correctly")

	# Restore default preset and save
	ExplosionRegistry.apply_preset_template("default")
	ExplosionRegistry.save_assignments()

	lab.toggle_explosion_studio()
	assert(lab._studio_modal.visible == false, "Studio modal toggled closed")
	
	print("PASS: Explosion Studio & Destruction Lab Smoke Test passed 100%!")
	quit(0)
