## LargeCraftGenLabRoot: a standalone dev scene for watching [LargeCraftGenerator]
## structures generate, shooting parts off them, and flying a small physics
## test-craft into a [DockingPad] to see the magnetize/park behaviour work.
##
## Not in [ModuleRegistry] and never will be reached through the launcher —
## same "opened directly in the editor (F6)" contract as
## [code]solar_system_gen_lab_root.gd[/code] documents for its own lab, until
## a later pass wires spawning into flight test / the solar-system menus.
##
## One camera mode only (orbit — drag to rotate, wheel to zoom): unlike the
## solar-system lab there is no free-fly, since WASD/QE instead drive the test
## craft's thrust so the docking behaviour can actually be exercised.
class_name LargeCraftGenLabRoot
extends Node3D

const ZOOM_STEP := 0.88
const DIST_MIN := 10.0
## Generous enough to frame a death-star/ship-city scale structure at the top
## of [constant LargeCraftGenerator.RANDOMIZABLE]'s ranges, not just a modest
## mothership.
const DIST_MAX := 40000.0
const TEST_CRAFT_THRUST := 26.0
const READOUT_INTERVAL := 0.3

var generator: LargeCraftGenerator
var _test_craft: RigidBody3D

var _cam: Camera3D
var _orbit_yaw := 35.0
var _orbit_pitch := 20.0
var _orbit_dist := 90.0

var _readout: Label
var _readout_timer := 0.0

# Generation-options rows (LargeCraftGenerator.RANDOMIZABLE), key -> control.
var _param_sliders: Dictionary = {}
var _param_value_labels: Dictionary = {}

var _save_name_edit: LineEdit
var _load_option: OptionButton
var _save_status: Label
var _archetype_option: OptionButton


func _ready() -> void:
	get_window().theme = BuilderTheme.build()
	_build_generator()
	_build_environment()
	_build_camera()
	_build_test_craft()
	_build_ui()
	_frame_camera_to_craft()


func _build_generator() -> void:
	generator = LargeCraftGenerator.new()
	generator.name = "Generator"
	add_child(generator)
	generator.generated.connect(_on_generated)
	generator.part_detached.connect(_on_part_detached)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("03050a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2a3448")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	add_child(holder)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.4
	key.light_color = Color("fff2dd")
	key.shadow_enabled = false
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -0.6, -0.4), Vector3.UP)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.4
	fill.light_color = Color("5f7fbf")
	fill.shadow_enabled = false
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.5, 0.4, 0.5), Vector3.UP)
	add_child(fill)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "OverviewCamera"
	_cam.current = true
	_cam.near = 0.2
	_cam.far = 80000.0
	_cam.fov = 55.0
	add_child(_cam)


func _frame_camera_to_craft() -> void:
	var extent := 40.0
	if generator != null:
		extent = generator.approx_extent()
	_orbit_dist = clampf(extent * 2.2, DIST_MIN, DIST_MAX)


## A small flyable box so the docking pad's magnetize/park behaviour is
## something you can actually fly into and watch, not just read numbers for.
func _build_test_craft() -> void:
	_test_craft = RigidBody3D.new()
	_test_craft.name = "TestCraft"
	_test_craft.gravity_scale = 0.0
	_test_craft.linear_damp = 0.4
	_test_craft.angular_damp = 2.0

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.8, 2.2)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffd84d")
	mesh_inst.material_override = mat
	_test_craft.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	_test_craft.add_child(shape)

	add_child(_test_craft)
	_test_craft.global_position = Vector3(0, 0, 60)


func _process(delta: float) -> void:
	_update_camera_transform()
	_readout_timer += delta
	if _readout_timer >= READOUT_INTERVAL:
		_readout_timer = 0.0
		_refresh_readout()


func _physics_process(delta: float) -> void:
	if _test_craft == null:
		return
	var thrust := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		thrust.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		thrust.z += 1.0
	if Input.is_key_pressed(KEY_A):
		thrust.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		thrust.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		thrust.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		thrust.y += 1.0
	if thrust != Vector3.ZERO:
		_test_craft.apply_central_force(thrust.normalized() * TEST_CRAFT_THRUST)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var rel := (event as InputEventMouseMotion).relative
		_orbit_yaw -= rel.x * 0.25
		_orbit_pitch = clampf(_orbit_pitch - rel.y * 0.25, -85.0, 85.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_dist = clampf(_orbit_dist * ZOOM_STEP, DIST_MIN, DIST_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_dist = clampf(_orbit_dist / ZOOM_STEP, DIST_MIN, DIST_MAX)
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F:
		_shoot_from_camera()


func _update_camera_transform() -> void:
	if _cam == null:
		return
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * _orbit_dist
	_cam.global_position = offset
	_cam.look_at(Vector3.ZERO, Vector3.UP)


## Raycasts from the camera along its own forward — a crosshair shot, not a
## mouse-position one, so it never fights the orbit-drag left-click binding.
func _shoot_from_camera() -> void:
	if generator == null or _cam == null:
		return
	# max_dist defaults to 200m in [method LargeCraftGenerator.shoot_at] —
	# nowhere near enough once [member LargeCraftGenerator.scale_mult] has
	# pushed the camera's own orbit distance past that to frame the craft.
	generator.shoot_at(_cam.global_position, -_cam.global_transform.basis.z, _orbit_dist * 1.5)


func _on_archetype_selected(index: int) -> void:
	generator.archetype = _archetype_option.get_item_id(index)
	generator.generate()
	_frame_camera_to_craft()


## Keeps the dropdown's own displayed text in sync when the archetype
## changes from somewhere other than a direct click on it — Load, currently
## the only such path (see [method LargeCraftData.apply_to]).
func _sync_archetype_option() -> void:
	if _archetype_option != null:
		_archetype_option.select(_archetype_option.get_item_index(generator.archetype))


func _on_generated() -> void:
	_refresh_param_rows()
	_refresh_readout()


func _on_part_detached(kind: String, _node: Node3D) -> void:
	if _save_status != null:
		_save_status.text = "Detached: %s" % kind


# --- UI -----------------------------------------------------------------

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Ui"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = BuilderTheme.PAD
	panel.offset_top = BuilderTheme.PAD
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.border(), 6)
	)
	canvas.add_child(panel)

	var outer_scroll := ScrollContainer.new()
	outer_scroll.custom_minimum_size = Vector2(0, 720)
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(outer_scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", BuilderTheme.GAP)
	outer_scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Large Craft Gen Lab"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(title)

	var help := Label.new()
	help.text = "Drag: orbit camera. Wheel: zoom. WASD/QE: fly the test craft. F: shoot the part under the crosshair."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(help)

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 10)
	_readout.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(_readout)

	var archetype_row := HBoxContainer.new()
	archetype_row.add_theme_constant_override("separation", BuilderTheme.GAP)
	var archetype_lbl := Label.new()
	archetype_lbl.text = "Archetype"
	archetype_lbl.add_theme_font_size_override("font_size", 10)
	archetype_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	archetype_row.add_child(archetype_lbl)
	_archetype_option = OptionButton.new()
	_archetype_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for archetype: int in LargeCraftGenerator.ARCHETYPE_NAMES.keys():
		_archetype_option.add_item(String(LargeCraftGenerator.ARCHETYPE_NAMES[archetype]), archetype)
	_archetype_option.select(_archetype_option.get_item_index(generator.archetype))
	_archetype_option.item_selected.connect(_on_archetype_selected)
	archetype_row.add_child(_archetype_option)
	vbox.add_child(archetype_row)

	_add_button(vbox, "Regenerate (same seed)", func() -> void: generator.generate())
	_add_button(vbox, "Randomize + reseed", func() -> void: generator.randomize_unlocked_params(randi()))
	_add_separator(vbox)

	var header := Label.new()
	header.text = "Generation options — lock (checkbox) to hold across reseed"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(header)
	for schema_entry in LargeCraftGenerator.RANDOMIZABLE:
		_add_param_row(vbox, schema_entry)

	_add_separator(vbox)
	_build_save_load_section(vbox)


func _build_save_load_section(vbox: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Save / load recipe"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(header)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "craft name"
	vbox.add_child(_save_name_edit)
	_add_button(vbox, "Save", _on_save_pressed)

	_load_option = OptionButton.new()
	_refresh_load_options()
	vbox.add_child(_load_option)
	_add_button(vbox, "Load", _on_load_pressed)

	_save_status = Label.new()
	_save_status.add_theme_font_size_override("font_size", 10)
	_save_status.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(_save_status)


func _refresh_load_options() -> void:
	_load_option.clear()
	for id in LargeCraftData.list_ids():
		_load_option.add_item(id)


func _on_save_pressed() -> void:
	var data := LargeCraftData.from_generator(generator, _save_name_edit.text)
	var result := data.save_to_disk()
	_save_status.text = "Saved: %s" % result["path"] if result["ok"] else "Save failed: %s" % result["error"]
	_refresh_load_options()


func _on_load_pressed() -> void:
	if _load_option.item_count == 0:
		return
	var id := _load_option.get_item_text(_load_option.selected)
	var data := LargeCraftData.load_from_disk(id)
	if data == null:
		_save_status.text = "Load failed: %s" % id
		return
	data.apply_to(generator)
	_sync_archetype_option()
	_frame_camera_to_craft()
	_save_status.text = "Loaded: %s" % id


func _add_param_row(parent: VBoxContainer, schema_entry: Dictionary) -> void:
	var key: String = schema_entry["key"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lock_cb := CheckButton.new()
	lock_cb.button_pressed = bool(generator.locked.get(key, false))
	lock_cb.focus_mode = Control.FOCUS_NONE
	lock_cb.tooltip_text = "Lock: hold this value across Randomize + reseed"
	lock_cb.toggled.connect(func(enabled: bool) -> void: generator.locked[key] = enabled)
	row.add_child(lock_cb)

	var name_lbl := Label.new()
	name_lbl.text = String(schema_entry["label"])
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(name_lbl)

	var slider := HSlider.new()
	slider.min_value = float(schema_entry["min"])
	slider.max_value = float(schema_entry["max"])
	slider.step = float(schema_entry["step"])
	slider.value = float(generator.get(key))
	slider.custom_minimum_size = Vector2(64, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(34, 0)
	value_lbl.add_theme_font_size_override("font_size", 10)
	value_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
	value_lbl.text = _format_param_value(schema_entry, slider.value)
	row.add_child(value_lbl)

	slider.value_changed.connect(_on_param_slider_changed.bind(schema_entry, value_lbl))
	parent.add_child(row)
	_param_sliders[key] = slider
	_param_value_labels[key] = value_lbl


func _format_param_value(schema_entry: Dictionary, value: float) -> String:
	return "%d" % int(value) if schema_entry.get("is_int", false) else "%.2f" % value


func _on_param_slider_changed(value: float, schema_entry: Dictionary, value_lbl: Label) -> void:
	var key: String = schema_entry["key"]
	generator.set(key, int(value) if schema_entry.get("is_int", false) else value)
	value_lbl.text = _format_param_value(schema_entry, value)
	generator.generate()


func _refresh_param_rows() -> void:
	for schema_entry in LargeCraftGenerator.RANDOMIZABLE:
		var key: String = schema_entry["key"]
		var slider: HSlider = _param_sliders.get(key)
		if slider == null:
			continue
		var v: float = float(generator.get(key))
		slider.set_value_no_signal(v)
		var lbl: Label = _param_value_labels.get(key)
		if lbl != null:
			lbl.text = _format_param_value(schema_entry, v)


func _add_button(parent: VBoxContainer, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.modulate.a = 0.4
	parent.add_child(sep)


func _refresh_readout() -> void:
	if _readout == null or generator == null:
		return
	_readout.text = "Parts: %d   Dock pads: %d   Debris: %d   Test craft: %s" % [
		generator.part_count(), generator.dock_pad_count(), generator.debris_count(),
		"DOCKED" if generator.is_body_docked(_test_craft) else "free",
	]
