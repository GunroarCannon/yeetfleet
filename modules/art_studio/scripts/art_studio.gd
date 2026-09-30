## ArtStudio (modules/art_studio/art_studio.tscn): make store art by hand —
## the Play Store feature graphic (1024×500), the app icon (512×512), or a
## screenshot-sized scene (phone landscape / portrait, tablet) — with every
## part of the picture on a dial: how many fighters, big ships, blasts and
## rocks, which blast, the planet, the sun and its glare, the camera, the
## title.
##
## The module's façade. The picture is built by [code]art_scene.gd[/code]
## (shared with `launch/tools/banner_gen.gd`) in a SubViewport at its real
## size and shown scaled to fit on the left; the panel on the right edits the
## settings and the picture rebuilds a moment after each change. SAVE writes
## a PNG to launch/studio/ (user://studio/ outside the editor); USE AS STORE
## ART also copies it over launch/feature_graphic.png or launch/icon_512.png.
## Reached from the home screen's DEBUG list (MODULES).
##
## Windowed only: the headless renderer draws nothing.
class_name ArtStudio
extends Control

const ArtScene := preload("res://modules/art_studio/scripts/art_scene.gd")
## Seconds after the last change before the picture rebuilds.
const REBUILD_DELAY := 0.35

## The panel: [key, label, kind, a, b, step]. kind is "int"/"float" (a..b in
## steps), "bool", "pick" (a = the options) or "text".
const SPEC := [
	["mode", "Picture", "pick", ["feature", "icon", "landscape", "portrait", "tablet"]],
	["seed", "Seed", "int", 1, 99999, 1],
	["sky_seed", "Sky (-1 = seed)", "float", -1.0, 50.0, 0.5],
	["__", "THE BANG"],
	["victim", "Wreck in the middle", "bool"],
	["victim_ship", "Wreck ship", "pick", ["random", "bulwark", "mule", "digger", "privateer"]],
	["victim_parts", "Parts blown off", "int", 0, 10, 1],
	["blast", "Main blast", "pick", ["random", "fire", "plasma", "toxic", "candy", "nuke", "none"]],
	["blast_size", "Main blast size", "float", 1.0, 14.0, 0.5],
	["small_blasts", "Small blasts", "int", 0, 16, 1],
	["small_blast_kind", "Small blast kind", "pick", ["mixed", "fire", "plasma", "toxic", "candy"]],
	["addon_booms", "Particle explosions", "int", 0, 16, 1],
	["addon_nuke", "Particle nuke", "pick", ["random", true, false]],
	["__", "SHIPS & ROCKS"],
	["fighters", "Fighters", "int", 0, 14, 1],
	["fighter_ring", "Fighter spread", "float", 8.0, 40.0, 1.0],
	["bolts", "Bolts in the air", "bool"],
	["big_ships", "Big ships", "int", 0, 3, 1],
	["rocks", "Rocks", "int", 0, 120, 2],
	["__", "SKY"],
	["planet", "Planet", "bool"],
	["planet_id", "Which planet", "pick", ["random", "tarn_iv", "ashara", "glacius", "new_world"]],
	["planet_size", "Planet size", "float", 0.05, 0.8, 0.01],
	["planet_left", "Planet side", "pick", ["random", true, false]],
	["sun", "Sun", "bool"],
	["sun_y", "Sun height (0 top, 1 bottom)", "float", 0.05, 0.9, 0.01],
	["key_light", "Sunlight", "float", 0.3, 4.0, 0.1],
	["glare", "Glare strength", "float", 0.0, 2.0, 0.05],
	["glare_bloom", "Glare size", "float", 0.05, 1.5, 0.05],
	["glare_rays", "Glare rays", "int", 0, 24, 1],
	["glare_ray_length", "Ray length", "float", 0.0, 1.5, 0.02],
	["glare_streak", "Streak", "float", 0.0, 1.0, 0.05],
	["glare_ghosts", "Ghosts", "int", 0, 8, 1],
	["glare_hue", "Glare colour", "float", 0.0, 1.0, 0.01],
	["__", "CAMERA (-1 / -100 = seed)"],
	["cam_yaw", "Angle round", "float", -1.0, 360.0, 5.0],
	["cam_height", "Height", "float", -100.0, 40.0, 1.0],
	["cam_distance", "Distance", "float", -1.0, 80.0, 1.0],
	["cam_fov", "Field of view", "float", -1.0, 100.0, 1.0],
	["cam_roll", "Roll", "float", -100.0, 30.0, 1.0],
	["cam_lift", "Lift the view", "float", -100.0, 20.0, 0.5],
	["__", "WORDS"],
	["title", "Title / mark", "bool"],
	["title_text", "Title", "text"],
	["icon_mark", "Icon mark", "text"],
	["title_size", "Title size", "int", 80, 600, 10],
	["title_tilt", "Tilt", "float", -20.0, 20.0, 0.5],
	["title_drips", "Drips", "float", 0.0, 1.0, 0.05],
	["title_y", "Title height", "float", 0.0, 0.6, 0.01],
]

var params := ArtScene.settings()
var _vp: SubViewport
var _preview: TextureRect
var _status: Label
var _world: Node3D = null
var _inputs := {}
var _rebuild_at := -1.0
var _building := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("120b1f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_preview = TextureRect.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(_preview)
	_status = Label.new()
	_status.text = "…"
	left.add_child(_status)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	_button(buttons, "BACK", _back)
	_button(buttons, "NEW SEED", func() -> void: set_param("seed", randi_range(1, 99999)))
	_button(buttons, "RANDOMISE ALL", _randomise)
	_button(buttons, "REPLAY BLASTS", func() -> void: _rebuild_now())
	_button(buttons, "SAVE PNG", func() -> void: _save(false))
	_button(buttons, "USE AS STORE ART", func() -> void: _save(true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	for spec: Array in SPEC:
		_row(panel, spec)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_preview.texture = _vp.get_texture()
	_rebuild_now()


func _process(_delta: float) -> void:
	if _rebuild_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _rebuild_at:
		_rebuild_at = -1.0
		_rebuild_now()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


# --- The panel -------------------------------------------------------------------

func _button(parent: Node, text: String, on: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on)
	parent.add_child(b)


func _row(panel: VBoxContainer, spec: Array) -> void:
	var key := String(spec[0])
	if key == "__":
		var head := Label.new()
		head.text = String(spec[1])
		head.add_theme_color_override("font_color", GraffitiStyle.LIME)
		panel.add_child(head)
		return
	var line := HBoxContainer.new()
	panel.add_child(line)
	var label := Label.new()
	label.text = String(spec[1])
	label.custom_minimum_size = Vector2(170, 0)
	label.clip_text = true
	line.add_child(label)
	var kind := String(spec[2])
	var input: Control
	match kind:
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(params[key])
			cb.toggled.connect(func(on: bool) -> void: set_param(key, on))
			input = cb
		"pick":
			var ob := OptionButton.new()
			var opts: Array = spec[3]
			for o in opts:
				ob.add_item(str(o))
			ob.selected = maxi(opts.find(params[key]), 0)
			ob.item_selected.connect(func(i: int) -> void: set_param(key, opts[i]))
			input = ob
		"text":
			var le := LineEdit.new()
			le.text = str(params[key])
			le.text_submitted.connect(func(t: String) -> void: set_param(key, t))
			le.focus_exited.connect(func() -> void: set_param(key, le.text))
			input = le
		_:
			var sb := SpinBox.new()
			sb.min_value = float(spec[3])
			sb.max_value = float(spec[4])
			sb.step = float(spec[5])
			sb.value = float(params[key])
			sb.value_changed.connect(func(v: float) -> void: set_param(key, int(v) if kind == "int" else v))
			input = sb
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(input)
	_inputs[key] = input


## Change one setting (and the panel's input for it) and rebuild soon.
func set_param(key: String, value: Variant) -> void:
	var old: Variant = params.get(key)
	if typeof(old) == typeof(value) and old == value:
		return
	params[key] = value
	# The panel follows a change made in code (NEW SEED, a tool) too.
	_refresh_inputs()
	_rebuild_at = Time.get_ticks_msec() / 1000.0 + REBUILD_DELAY


## Every number and choice to something random inside its range (the words
## and the picture kind stay).
func _randomise() -> void:
	for spec: Array in SPEC:
		var key := String(spec[0])
		if key in ["__", "mode", "title_text", "icon_mark"]:
			continue
		match String(spec[2]):
			"bool":
				params[key] = randf() < 0.75
			"pick":
				var opts: Array = spec[3]
				params[key] = opts[randi() % opts.size()]
			"int":
				params[key] = randi_range(int(spec[3]), int(spec[4]))
			"float":
				params[key] = snappedf(randf_range(float(spec[3]), float(spec[4])), float(spec[5]))
	# The camera dials' "let the seed pick" ends are the usual best.
	for key in ["cam_yaw", "cam_height", "cam_distance", "cam_fov", "cam_roll", "cam_lift"]:
		params[key] = ArtScene.DEFAULTS[key]
	params["title"] = true
	params["glare"] = maxf(float(params["glare"]), 0.5)
	_refresh_inputs()
	_rebuild_now()


func _refresh_inputs() -> void:
	for spec: Array in SPEC:
		var key := String(spec[0])
		var input: Control = _inputs.get(key)
		if input is SpinBox:
			(input as SpinBox).set_value_no_signal(float(params[key]))
		elif input is CheckBox:
			(input as CheckBox).set_pressed_no_signal(bool(params[key]))
		elif input is OptionButton:
			(input as OptionButton).selected = maxi((spec[3] as Array).find(params[key]), 0)
		elif input is LineEdit:
			(input as LineEdit).text = str(params[key])


# --- The picture -----------------------------------------------------------------

func _rebuild_now() -> void:
	if _building:
		_rebuild_at = Time.get_ticks_msec() / 1000.0 + REBUILD_DELAY
		return
	_building = true
	_status.text = "building…"
	for c in _vp.get_children():
		c.queue_free()
	await get_tree().process_frame
	var size := ArtScene.size_of(params)
	_vp.size = size
	_world = Node3D.new()
	_vp.add_child(_world)
	var built := ArtScene.build(_world, Vector2(size), params)
	var over := Control.new()
	over.size = Vector2(size)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(over)
	ArtScene.overlay(over, Vector2(size), params, built["sun_screen"])
	for i in 8:
		await get_tree().process_frame
	await ArtScene.booms(get_tree(), _world, params)
	_status.text = "%s %d×%d · seed %d" % [str(params["mode"]).to_upper(), size.x, size.y, int(params["seed"])]
	_building = false


func _save(store: bool) -> void:
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var dir := "res://launch/studio" if OS.has_feature("editor") else "user://studio"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var mode := str(params["mode"])
	var path := dir.path_join("%s_%d.png" % [mode, int(params["seed"])])
	img.save_png(ProjectSettings.globalize_path(path))
	var msg := "saved " + path
	if store and mode in ["feature", "icon"] and OS.has_feature("editor"):
		var main := "res://launch/feature_graphic.png" if mode == "feature" else "res://launch/icon_512.png"
		img.save_png(ProjectSettings.globalize_path(main))
		msg += " and " + main
	_status.text = msg
	print("[art studio] ", msg)


func _back() -> void:
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("menu"))
