extends Control

## Face Lab 3D — live-editable alien heads.
## Every slider/option rebuilds the mesh immediately so you can tune the skull,
## features, palette and style and watch the head change in real time.
## Run:  godot --path . res://modules/alien_face_gen/demo/face_lab_3d.tscn
## Drag on the 3D view to orbit. Species + "Face shape" preset set the identity;
## sliders override individual skull/feature fields from there.

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL",
]
const _STYLES := [&"faceted", &"toon", &"painted_decal"]
const _LOD_NAMES := ["Cinematic", "Standard", "Compact", "Glyph"]
const _EXPRESSIONS := ["neutral", "happy", "angry", "sad", "surprised",
	"suspicious", "talking_a", "talking_b", "talking_c"]
const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"
const _PALETTE_DIR := "res://modules/alien_face_gen/data/palettes"

# Continuous skull + feature fields (0..1), grouped for the UI.
const _FLOAT_GROUPS := {
	"Skull": ["age", "dimorph_axis", "cranium_width", "cranium_height", "cranium_bulge",
		"brow_ridge", "temple_pinch", "jaw_width", "jaw_length", "chin_taper",
		"chin_point", "cheek_prominence", "occipital_extend", "neck_width", "skull_asymmetry"],
	"Eyes": ["eye_size", "eye_spacing", "eye_line_height", "eye_tilt", "pupil_size",
		"iris_ratio", "lid_upper", "lid_lower", "eye_glow"],
	"Nose": ["nose_length", "nose_width", "nose_bridge", "nostril_flare"],
	"Mouth": ["mouth_width", "mouth_height", "mouth_curve", "lip_thickness",
		"teeth_amount", "mandible_length"],
	"Brows / Ears": ["brow_thickness", "brow_angle", "ear_size", "ear_angle", "ear_height"],
	"Crest": ["crest_length", "crest_spread", "crest_curve", "crest_thickness"],
	"Surface": ["marking_coverage", "marking_symmetry", "plate_seams", "wrinkle_amount"],
	"Gear / Colour": ["collar_height", "gear_bulk", "hue_shift", "sat_scale",
		"val_scale", "marking_hue", "emissive_amount", "asymmetry_amount"],
}

# Integer (count) fields: {field: [min, max]}
const _INT_FIELDS := {
	"eye_count": [1, 8], "eye_rows": [1, 3], "radial_count": [1, 8],
	"mandible_count": [0, 4], "crest_count": [0, 12], "marking_count": [0, 8],
	"scar_count": [0, 5],
}

# Enum fields: {field: [label, ...]} — index == enum value.
const _ENUM_FIELDS := {
	"eye_shape": ["Round", "Almond", "Slit V", "Slit H", "Compound", "Triangle", "Hex", "Void"],
	"pupil_shape": ["Round", "Slit V", "Slit H", "Goat", "Multi", "Star", "None"],
	"nose_type": ["None", "Nub", "Human", "Snout", "Beak", "Slit", "Trunk", "Plate"],
	"mouth_type": ["None", "Lips", "Thin", "Beak", "Mandible", "Vent", "Sucker", "Stitched", "Tusked"],
	"ear_type": ["None", "Lobe", "Point", "Fin", "Frill", "Hole", "Antenna"],
	"crest_type": ["None", "Hair", "Horn", "Antenna", "Frill", "Spine", "Tendril", "Fin", "Plume"],
	"skin_texture": ["Smooth", "Scale", "Chitin", "Fur", "Plate", "Crystal", "Bark", "Membrane"],
	"marking_type": ["None", "Stripe", "Spot", "Warpaint", "Circuit", "Scar", "Glyph", "Gradient"],
	"collar_type": ["None", "Shoulders", "High collar", "Hood", "Plate rig", "Robe"],
	"headgear_type": ["None", "Cap", "Helm", "Band", "Crown", "Breather", "Wrap"],
	"ocular_gear": ["None", "Visor", "Goggles", "Mono lens", "Implant"],
	"condition": ["Healthy", "Scarred", "Withered", "Augmented"],
	"symmetry_mode": ["Bilateral", "Radial", "Asymmetric"],
}

# Face-shape presets bias the skull fields toward a silhouette/character.
const _SHAPES := {
	"Balanced": {},
	"Round / soft": {
		"cranium_width": 0.72, "cranium_height": 0.55, "cranium_bulge": 0.8,
		"brow_ridge": 0.25, "temple_pinch": 0.45, "jaw_width": 0.8, "jaw_length": 0.4,
		"chin_taper": 0.2, "chin_point": 0.3, "cheek_prominence": 0.85,
		"occipital_extend": 0.6, "neck_width": 0.75, "skull_asymmetry": 0.3,
	},
	"Angular / reptilian": {
		"cranium_width": 0.6, "cranium_height": 0.85, "cranium_bulge": 0.25,
		"brow_ridge": 0.9, "temple_pinch": 0.1, "jaw_width": 0.3, "jaw_length": 0.75,
		"chin_taper": 0.95, "chin_point": 0.9, "cheek_prominence": 0.2,
		"occipital_extend": 0.4, "neck_width": 0.4, "skull_asymmetry": 0.25,
	},
	"Brute / wide jaw": {
		"cranium_width": 0.9, "cranium_height": 0.8, "cranium_bulge": 0.5,
		"brow_ridge": 0.8, "temple_pinch": 0.25, "jaw_width": 1.0, "jaw_length": 0.5,
		"chin_taper": 0.45, "chin_point": 0.6, "cheek_prominence": 0.9,
		"occipital_extend": 0.5, "neck_width": 0.9, "skull_asymmetry": 0.35,
	},
	"Elongated / gracile": {
		"cranium_width": 0.35, "cranium_height": 0.95, "cranium_bulge": 0.5,
		"brow_ridge": 0.5, "temple_pinch": 0.5, "jaw_width": 0.4, "jaw_length": 0.8,
		"chin_taper": 0.8, "chin_point": 0.7, "cheek_prominence": 0.4,
		"occipital_extend": 0.7, "neck_width": 0.3, "skull_asymmetry": 0.4,
	},
}

var _species_id: StringName = &"NORDIC"
var _seed := 42
var _palette_ids: Array = []

var _g: FaceGenome
var _head: FaceHead3D
var _pivot: Node3D
var _cam: Camera3D
var _vp: SubViewport

var _float_sliders: Dictionary = {}  # field -> Range
var _enum_buttons: Dictionary = {}   # field -> OptionButton
var _int_spins: Dictionary = {}      # field -> SpinBox
var _field_override: Dictionary = {} # float field currently overridden by user
var _syncing := false

var _yaw := 0.0
var _pitch := 0.15
var _dragging := false
var _drag_last := Vector2.ZERO

var _species_btn: OptionButton
var _seed_spin: SpinBox
var _shape_btn: OptionButton
var _style_btn: OptionButton
var _lod_btn: OptionButton
var _palette_btn: OptionButton
var _expr_btn: OptionButton
var _status: Label
var _panel: VBoxContainer


func _ready() -> void:
	_themeize()
	_gather_palettes()
	_build_layout()
	_set_species(&"NORDIC", 42)
	set_process(true)


func _process(delta: float) -> void:
	if not _dragging:
		_yaw += delta * 0.25
	if _pivot:
		_pivot.rotation = Vector3(_pitch, _yaw, 0)


# ---------------------------------------------------------------- UI building

func _themeize() -> void:
	var t := Theme.new()
	var def := ThemeDB.fallback_font
	t.default_font = def
	t.set_font_size("font", "Label", 13)
	t.set_font_size("font", "Button", 13)
	t.set_font_size("font", "OptionButton", 13)
	t.set_color("font_color", "Label", Color(0.86, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.86, 0.9, 0.95))
	theme = t


func _build_layout() -> void:
	var hs := HSplitContainer.new()
	hs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hs)

	# --- left: controls ---------------------------------------------------
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	hs.add_child(side)
	_panel = VBoxContainer.new()
	side.add_child(_panel)

	var title := Label.new()
	title.text = "Alien Face Lab 3D"
	title.add_theme_font_size_override("font_size", 20)
	_panel.add_child(title)

	# Row: species / seed
	var row := HBoxContainer.new()
	_panel.add_child(row)
	_species_btn = OptionButton.new()
	for sid in _SPECIES_IDS:
		_species_btn.add_item(String(sid))
	_species_btn.item_selected.connect(_on_species_selected)
	row.add_child(_species_btn)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 99999
	_seed_spin.value = 42
	_seed_spin.value_changed.connect(func(v): _set_species(_species_id, int(v)))
	row.add_child(_seed_spin)

	var rand_btn := Button.new()
	rand_btn.text = "Roll"
	rand_btn.pressed.connect(func():
		var s := randi() % 100000
		_seed_spin.set_value_no_signal(s)
		_set_species(_species_id, s))
	row.add_child(rand_btn)

	# Row: shape preset / style
	var row2 := HBoxContainer.new()
	_panel.add_child(row2)
	_shape_btn = OptionButton.new()
	for name in _SHAPES.keys():
		_shape_btn.add_item(name)
	_shape_btn.item_selected.connect(_on_shape_selected)
	row2.add_child(_shape_btn)
	_style_btn = OptionButton.new()
	for s in _STYLES:
		_style_btn.add_item(String(s))
	_style_btn.item_selected.connect(func(_i): _rebuild())
	row2.add_child(_style_btn)

	# Row: LOD / palette / expression
	var row3 := HBoxContainer.new()
	_panel.add_child(row3)
	_lod_btn = OptionButton.new()
	for n in _LOD_NAMES:
		_lod_btn.add_item(n)
	_lod_btn.select(1)
	_lod_btn.item_selected.connect(func(_i): _rebuild())
	row3.add_child(_lod_btn)
	_palette_btn = OptionButton.new()
	_palette_btn.add_item("<species>")
	for pid in _palette_ids:
		_palette_btn.add_item(String(pid))
	_palette_btn.item_selected.connect(func(_i): _rebuild())
	row3.add_child(_palette_btn)
	_expr_btn = OptionButton.new()
	for e in _EXPRESSIONS:
		_expr_btn.add_item(e)
	_expr_btn.item_selected.connect(func(_i): _rebuild())
	row3.add_child(_expr_btn)

	var sep := HSeparator.new()
	_panel.add_child(sep)

	# Scrollable parameter sections
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	for group in _FLOAT_GROUPS:
		var box := VBoxContainer.new()
		var hd := Label.new()
		hd.text = group
		hd.add_theme_font_size_override("font_size", 16)
		hd.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
		box.add_child(hd)
		for field in _FLOAT_GROUPS[group]:
			_add_float_slider(box, field)
		body.add_child(box)

	var enum_head := _group_header("Types")
	body.add_child(enum_head)
	for field in _ENUM_FIELDS:
		var hb := HBoxContainer.new()
		var lb := Label.new()
		lb.text = _pretty(field)
		lb.custom_minimum_size.x = 150
		hb.add_child(lb)
		var ob := OptionButton.new()
		for label in _ENUM_FIELDS[field]:
			ob.add_item(label)
		ob.item_selected.connect(_enum_selected.bind(field))
		hb.add_child(ob)
		_enum_buttons[field] = ob
		body.add_child(hb)

	var int_head := _group_header("Counts")
	body.add_child(int_head)
	for field in _INT_FIELDS:
		var hb := HBoxContainer.new()
		var lb := Label.new()
		lb.text = _pretty(field)
		lb.custom_minimum_size.x = 150
		hb.add_child(lb)
		var sp := SpinBox.new()
		var bounds: Array = _INT_FIELDS[field]
		sp.min_value = int(bounds[0])
		sp.max_value = int(bounds[1])
		sp.value_changed.connect(_int_changed.bind(field))
		hb.add_child(sp)
		_int_spins[field] = sp
		body.add_child(hb)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_panel.add_child(_status)

	# --- right: 3D viewport ----------------------------------------------
	var vpc := SubViewportContainer.new()
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.stretch = true
	hs.add_child(vpc)
	vpc.gui_input.connect(_on_view_input)

	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	for dir in [Vector3(1.5, 3, 3.5), Vector3(-2.5, -1, 2)]:
		var light := DirectionalLight3D.new()
		light.light_energy = 1.1
		world.add_child(light)
		light.look_at_from_position(dir, Vector3.ZERO)

	_pivot = Node3D.new()
	world.add_child(_pivot)

	var head := FaceHead3D.new()
	_pivot.add_child(head)
	_head = head

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3.4)
	cam.current = true
	_pivot.add_child(cam)
	_cam = cam


func _group_header(text: String) -> Label:
	var hd := Label.new()
	hd.text = text
	hd.add_theme_font_size_override("font_size", 16)
	hd.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	return hd


func _add_float_slider(box: VBoxContainer, field: String) -> void:
	var hb := HBoxContainer.new()
	var lb := Label.new()
	lb.text = _pretty(field)
	lb.custom_minimum_size.x = 150
	hb.add_child(lb)
	var r := HSlider.new()
	r.min_value = 0.0
	r.max_value = 1.0
	r.step = 0.01
	r.custom_minimum_size.x = 150
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.value_changed.connect(_float_changed.bind(field))
	hb.add_child(r)
	var val := Label.new()
	val.custom_minimum_size.x = 36
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	_float_sliders[field] = r
	box.add_child(hb)


func _pretty(field: String) -> String:
	var spaced := field.replace("_", " ")
	return spaced.capitalize()


# ---------------------------------------------------------------- event handlers

func _float_changed(v: float, field: String) -> void:
	if _syncing or _g == null:
		return
	_g.set(field, v)
	_field_override[field] = true
	_rebuild()


func _int_changed(v: float, field: String) -> void:
	if _syncing or _g == null:
		return
	_g.set(field, int(v))
	_rebuild()


func _enum_selected(idx: int, field: String) -> void:
	if _syncing or _g == null:
		return
	_g.set(field, idx)
	_rebuild()


func _on_species_selected(idx: int) -> void:
	_set_species(_SPECIES_IDS[idx], int(_seed_spin.value))


func _on_shape_selected(idx: int) -> void:
	var name: String = _SHAPES.keys()[idx]
	if name == "Balanced" or name == "":
		return
	var bias: Dictionary = _SHAPES[name]
	for field in bias:
		_g.set(field, bias[field])
		if field in _float_sliders:
			_field_override[field] = true
	_sync_sliders_from_genome()
	_rebuild()


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam.position.z = clampf(_cam.position.z - 0.2, 1.4, 6.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam.position.z = clampf(_cam.position.z + 0.2, 1.4, 6.0)
	elif ev is InputEventMouseMotion and _dragging:
		var mm := ev as InputEventMouseMotion
		var d: Vector2 = mm.position - _drag_last
		_drag_last = mm.position
		_yaw -= d.x * 0.008
		_pitch = clampf(_pitch - d.y * 0.008, -1.0, 1.0)


# ---------------------------------------------------------------- genome / rebuild

func _set_species(id: StringName, seed_val: int) -> void:
	_species_id = id
	_seed = seed_val
	_seed_spin.value = seed_val
	var sp := _load_species(id)
	_g = GenomeGenerator.generate(sp, seed_val)
	_field_override.clear()
	if not _species_btn.is_queued_for_deletion():
		_species_btn.select(_SPECIES_IDS.find(id))
	_sync_sliders_from_genome()
	_rebuild()


func _sync_sliders_from_genome() -> void:
	_syncing = true
	for field in _float_sliders:
		_float_sliders[field].value = _g.get(field)
	for field in _enum_buttons:
		var v: int = _g.get(field)
		_enum_buttons[field].select(clampi(v, 0, _enum_buttons[field].item_count - 1))
	for field in _int_spins:
		_int_spins[field].value = _g.get(field)
	_syncing = false


func _rebuild() -> void:
	if _g == null or _head == null:
		return
	var lod: int = clampi(_lod_btn.get_selected_id(), 0, 3)
	var expr_name: StringName = StringName(_EXPRESSIONS[clampi(_expr_btn.get_selected_id(), 0, _EXPRESSIONS.size() - 1)])
	var style_name: StringName = _STYLES[clampi(_style_btn.get_selected_id(), 0, _STYLES.size() - 1)]

	var display := FaceExpression.apply(_g, expr_name)
	var lm := LandmarkSolver.solve(display, lod)
	var p := _resolve_palette(display)
	var style := _make_style(style_name)
	var md := Face3DBuilder.build(display, lm, p, style, lod)
	_head.set_mesh_data(md, style, p, display)

	if _status:
		_status.text = "%s  seed %d  ·  %d tris · %s" % [
			String(_species_id), _seed, md.tri_count(), String(style_name)]


func _make_style(id: StringName) -> StyleBase3D:
	match id:
		&"toon": return StyleToon.new()
		&"painted_decal": return StylePaintedDecal.new()
		_: return StyleFaceted.new()


func _resolve_palette(g: FaceGenome) -> FacePalette:
	var chosen := _palette_btn.get_selected_id()
	if chosen > 0 and chosen - 1 < _palette_ids.size():
		var p = load(_PALETTE_DIR + "/" + String(_palette_ids[chosen - 1]) + ".tres")
		if p is FacePalette:
			return p.resolve(g)
	# Species default
	var sp := _load_species(_species_id)
	if sp.allowed_palettes.size() > 0:
		var p = load(_PALETTE_DIR + "/" + String(sp.allowed_palettes[0]) + ".tres")
		if p is FacePalette:
			return p.resolve(g)
	return _fallback_palette()


func _fallback_palette() -> FacePalette:
	var p := FacePalette.new()
	p.skin_base = Color(0.7, 0.7, 0.7)
	p.skin_shade = Color(0.5, 0.5, 0.5)
	p.skin_light = Color(0.9, 0.9, 0.9)
	p.skin_deep = Color(0.3, 0.3, 0.3)
	p.eye_sclera = Color(1, 1, 1)
	p.eye_pupil = Color(0, 0, 0)
	p.eye_glow = Color(0.8, 0.8, 0.3)
	p.mouth_inner = Color(0.5, 0.2, 0.2)
	p.crest = Color(0.3, 0.3, 0.3)
	p.garment = Color(0.2, 0.2, 0.2)
	p.garment_trim = Color(0.4, 0.4, 0.4)
	p.background = Color(0.2, 0.2, 0.2)
	p.outline = Color(0, 0, 0)
	return p


func _gather_palettes() -> void:
	_palette_ids.clear()
	var dir := DirAccess.open(_PALETTE_DIR)
	if dir:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				_palette_ids.append(StringName(fn.get_basename()))
			fn = dir.get_next()


func _load_species(id: StringName) -> SpeciesDef:
	var s = load(_SPECIES_DIR + "/" + String(id).to_lower() + ".tres")
	if s == null:
		var sd := SpeciesDef.new()
		sd.id = id
		sd.allowed_palettes = [&"void_grey"]
		sd.ranges = {}
		sd.enum_weights = {}
		sd.presence = {}
		sd.symmetry_mode = FaceEnums.SymmetryMode.BILATERAL
		return sd
	return s
