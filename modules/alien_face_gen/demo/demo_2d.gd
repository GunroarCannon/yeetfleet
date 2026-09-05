extends Control

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

var grid_container: GridContainer
var species_option: OptionButton
var style_option: OptionButton
var lod_option: OptionButton
var expr_option: OptionButton


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# Controls
	var controls := HBoxContainer.new()
	vbox.add_child(controls)
	
	species_option = OptionButton.new()
	species_option.add_item("ALL")
	for sid in _SPECIES_IDS:
		species_option.add_item(String(sid))
	controls.add_child(species_option)
	
	style_option = OptionButton.new()
	for s in ["flat_vector", "pixel_art", "ink_outline"]:
		style_option.add_item(s)
	controls.add_child(style_option)
	
	lod_option = OptionButton.new()
	for l in ["Cinematic", "Standard", "Compact", "Glyph"]:
		lod_option.add_item(l)
	controls.add_child(lod_option)
	
	expr_option = OptionButton.new()
	for e in ["neutral", "happy", "angry", "sad", "surprised", "suspicious"]:
		expr_option.add_item(e)
	controls.add_child(expr_option)
	
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh)
	controls.add_child(refresh_btn)
	
	# Grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	grid_container = GridContainer.new()
	grid_container.columns = 6
	scroll.add_child(grid_container)
	
	_refresh()


func _refresh() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	
	var species_idx := species_option.get_selected_id()
	var style_text := style_option.get_item_text(style_option.get_item_index(style_option.get_selected_id()))
	var lod_idx := lod_option.get_item_index(lod_option.get_selected_id())
	var expr_text := expr_option.get_item_text(expr_option.get_item_index(expr_option.get_selected_id()))
	
	var style := Face2DRenderer.get_style(StringName(style_text))
	
	if species_idx == 0:
		# Show all species
		for sid in _SPECIES_IDS:
			_add_portrait(sid, 42, style, lod_idx, StringName(expr_text))
	else:
		var sid: StringName = _SPECIES_IDS[mini(species_idx - 1, _SPECIES_IDS.size() - 1)]
		for i in range(24):
			_add_portrait(sid, 42 + i, style, lod_idx, StringName(expr_text))


func _add_portrait(species_id: StringName, seed_val: int, style: StyleBase2D, lod: int, expr: StringName) -> void:
	var g := GenomeGenerator.generate(_load_species(species_id), seed_val)
	var lm := LandmarkSolver.solve(g, lod)
	var p := _resolve_palette(species_id, g)
	var dl := Face2DRenderer.render(g, lm, p, style, lod, expr)
	
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(128, 140)
	
	var drawer := CanvasDrawer.new()
	drawer.draw_list = dl
	drawer.custom_minimum_size = Vector2(128, 128)
	drawer.size = Vector2(128, 128)
	container.add_child(drawer)
	
	var label := Label.new()
	label.text = "%s\n%d" % [String(species_id), seed_val]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	container.add_child(label)
	
	grid_container.add_child(container)
	drawer.queue_redraw()


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


func _resolve_palette(species_id: StringName, g: FaceGenome) -> FacePalette:
	if g.palette_id != &"":
		var path := "res://modules/alien_face_gen/data/palettes/" + String(g.palette_id) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
	var sp := _load_species(species_id)
	if sp.allowed_palettes.size() > 0:
		var path := "res://modules/alien_face_gen/data/palettes/" + String(sp.allowed_palettes[0]) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
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
