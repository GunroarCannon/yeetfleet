@tool
extends VBoxContainer

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

const _STYLE_IDS := [&"flat_vector", &"pixel_art", &"ink_outline"]
const _LOD_NAMES := ["Cinematic", "Standard", "Compact", "Glyph"]
const _EXPRESSION_NAMES := ["neutral", "happy", "angry", "sad", "surprised",
	"suspicious", "talking_a", "talking_b", "talking_c"]

var species_option: OptionButton
var style_option: OptionButton
var lod_option: OptionButton
var expr_option: OptionButton
var palette_option: OptionButton
var seed_spin: SpinBox
var roll_button: Button
var export_button: Button
var preview_grid: GridContainer


func _ready() -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return
	
	_build_ui()


func _build_ui() -> void:
	# Title
	var title := Label.new()
	title.text = "Alien Face Gallery"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	
	# Species selector
	var species_hbox := HBoxContainer.new()
	add_child(species_hbox)
	var species_label := Label.new()
	species_label.text = "Species: "
	species_hbox.add_child(species_label)
	species_option = OptionButton.new()
	for sid in _SPECIES_IDS:
		species_option.add_item(String(sid))
	species_option.item_selected.connect(_on_species_changed)
	species_hbox.add_child(species_option)
	
	# Style selector
	var style_hbox := HBoxContainer.new()
	add_child(style_hbox)
	var style_label := Label.new()
	style_label.text = "Style: "
	style_hbox.add_child(style_label)
	style_option = OptionButton.new()
	for sid in _STYLE_IDS:
		style_option.add_item(String(sid))
	style_hbox.add_child(style_option)
	
	# LOD selector
	var lod_hbox := HBoxContainer.new()
	add_child(lod_hbox)
	var lod_label := Label.new()
	lod_label.text = "LOD: "
	lod_hbox.add_child(lod_label)
	lod_option = OptionButton.new()
	for name in _LOD_NAMES:
		lod_option.add_item(name)
	lod_hbox.add_child(lod_option)
	
	# Expression selector
	var expr_hbox := HBoxContainer.new()
	add_child(expr_hbox)
	var expr_label := Label.new()
	expr_label.text = "Expression: "
	expr_hbox.add_child(expr_label)
	expr_option = OptionButton.new()
	for name in _EXPRESSION_NAMES:
		expr_option.add_item(name)
	expr_hbox.add_child(expr_option)
	
	# Palette selector
	var palette_hbox := HBoxContainer.new()
	add_child(palette_hbox)
	var palette_label := Label.new()
	palette_label.text = "Palette: "
	palette_hbox.add_child(palette_label)
	palette_option = OptionButton.new()
	palette_option.add_item("<species default>")
	palette_hbox.add_child(palette_option)
	
	# Seed spinner
	var seed_hbox := HBoxContainer.new()
	add_child(seed_hbox)
	var seed_label := Label.new()
	seed_label.text = "Seed: "
	seed_hbox.add_child(seed_label)
	seed_spin = SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 999999
	seed_spin.value = 42
	seed_hbox.add_child(seed_spin)
	
	# Buttons
	var btn_hbox := HBoxContainer.new()
	add_child(btn_hbox)
	roll_button = Button.new()
	roll_button.text = "Roll 24"
	roll_button.pressed.connect(_on_roll)
	btn_hbox.add_child(roll_button)
	export_button = Button.new()
	export_button.text = "Export SVG Grid"
	export_button.pressed.connect(_on_export)
	btn_hbox.add_child(export_button)
	
	# Preview grid
	preview_grid = GridContainer.new()
	preview_grid.columns = 6
	add_child(preview_grid)
	
	# Populate palette options when species changes
	_on_species_changed(0)


func _on_species_changed(idx: int) -> void:
	if palette_option == null:
		return
	palette_option.clear()
	palette_option.add_item("<species default>")
	
	if idx < _SPECIES_IDS.size():
		var path := "res://modules/alien_face_gen/data/species/" + String(_SPECIES_IDS[idx]).to_lower() + ".tres"
		var sp = load(path)
		if sp is SpeciesDef:
			for pid in sp.allowed_palettes:
				palette_option.add_item(String(pid))


func _on_roll() -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return
	
	# Clear existing previews
	for child in preview_grid.get_children():
		child.queue_free()
	
	var species_idx := species_option.get_item_index(species_option.get_selected_id())
	var style_idx := style_option.get_item_index(style_option.get_selected_id())
	var lod_idx := lod_option.get_item_index(lod_option.get_selected_id())
	var expr_idx := expr_option.get_item_index(expr_option.get_selected_id())
	var base_seed := int(seed_spin.value)

	var species_id: StringName = _SPECIES_IDS[mini(species_idx, _SPECIES_IDS.size() - 1)]
	var style_id: StringName = _STYLE_IDS[mini(style_idx, _STYLE_IDS.size() - 1)]
	var lod: int = mini(lod_idx, 3)
	var expr: StringName = StringName(_EXPRESSION_NAMES[mini(expr_idx, _EXPRESSION_NAMES.size() - 1)])
	
	var style := Face2DRenderer.get_style(style_id)
	
	for i in range(24):
		var seed_val := base_seed + i
		var g := _generate_or_placeholder(species_id, seed_val)
		var lm := LandmarkSolver.solve(g, lod)
		var p := _get_palette(species_id, g)
		var dl := Face2DRenderer.render(g, lm, p, style, lod, expr)
		
		# Create a CanvasDrawer preview
		var preview := CanvasDrawer.new()
		preview.draw_list = dl
		preview.custom_minimum_size = Vector2(100, 100)
		preview.size = Vector2(100, 100)
		preview_grid.add_child(preview)
		preview.queue_redraw()
		
		# Click to copy seed
		var btn := Button.new()
		btn.text = str(seed_val)
		btn.pressed.connect(func(): DisplayServer.clipboard_set(str(seed_val)))
		preview_grid.add_child(btn)


func _on_export() -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return
	
	var species_idx := species_option.get_item_index(species_option.get_selected_id())
	var style_idx := style_option.get_item_index(style_option.get_selected_id())
	var lod_idx := lod_option.get_item_index(lod_option.get_selected_id())
	var expr_idx := expr_option.get_item_index(expr_option.get_selected_id())
	var base_seed := int(seed_spin.value)
	
	var species_id: StringName = _SPECIES_IDS[mini(species_idx, _SPECIES_IDS.size() - 1)]
	var style_id: StringName = _STYLE_IDS[mini(style_idx, _STYLE_IDS.size() - 1)]
	var lod: int = mini(lod_idx, 3)
	var expr: StringName = StringName(_EXPRESSION_NAMES[mini(expr_idx, _EXPRESSION_NAMES.size() - 1)])
	
	var style := Face2DRenderer.get_style(style_id)
	var lists: Array[DrawList] = []
	
	for i in range(24):
		var seed_val := base_seed + i
		var g := _generate_or_placeholder(species_id, seed_val)
		var lm := LandmarkSolver.solve(g, lod)
		var p := _get_palette(species_id, g)
		var dl := Face2DRenderer.render(g, lm, p, style, lod, expr)
		lists.append(dl)
	
	var path := "res://out/gallery_export.svg"
	SvgExporter.grid(lists, 6, 256, path)
	print("Exported to: ", path)


func _generate_or_placeholder(species_id: StringName, seed_val: int) -> FaceGenome:
	var sp := _load_species(species_id)
	return GenomeGenerator.generate(sp, seed_val)


func _get_palette(species_id: StringName, g: FaceGenome) -> FacePalette:
	var palette_text := palette_option.get_item_text(palette_option.get_item_index(palette_option.get_selected_id()))
	if palette_text == "<species default>" or palette_text.is_empty():
		# Load species default palette
		var sp := _load_species(species_id)
		if sp.allowed_palettes.size() > 0:
			var pid: StringName = sp.allowed_palettes[0]
			var path := "res://modules/alien_face_gen/data/palettes/" + String(pid) + ".tres"
			var p = load(path)
			if p is FacePalette:
				return p.resolve(g)
	
	# Load specific palette
	var path := "res://modules/alien_face_gen/data/palettes/" + palette_text + ".tres"
	var p = load(path)
	if p is FacePalette:
		return p.resolve(g)
	
	# Fallback
	return _make_fallback_palette()


func _load_species(id: StringName) -> SpeciesDef:
	var path := "res://modules/alien_face_gen/data/species/" + String(id).to_lower() + ".tres"
	var s = load(path)
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


func _make_fallback_palette() -> FacePalette:
	var p := FacePalette.new()
	p.id = &"fallback"
	p.background = Color(0.2, 0.2, 0.2)
	p.outline = Color(0, 0, 0, 1)
	p.skin_base = Color(0.7, 0.7, 0.7)
	p.skin_shade = Color(0.5, 0.5, 0.5)
	p.skin_light = Color(0.9, 0.9, 0.9)
	p.skin_deep = Color(0.3, 0.3, 0.3)
	p.eye_sclera = Color(1, 1, 1)
	p.eye_iris = Color(0.2, 0.2, 0.2)
	p.eye_pupil = Color(0, 0, 0)
	p.eye_glow = Color(0.8, 0.8, 0.3)
	p.mouth_inner = Color(0.5, 0.2, 0.2)
	p.tooth = Color(1, 1, 1)
	p.marking_a = Color(0.8, 0.6, 0.2)
	p.marking_b = Color(0.2, 0.6, 0.8)
	p.crest = Color(0.3, 0.3, 0.3)
	p.garment = Color(0.2, 0.2, 0.2)
	p.garment_trim = Color(0.4, 0.4, 0.4)
	return p
