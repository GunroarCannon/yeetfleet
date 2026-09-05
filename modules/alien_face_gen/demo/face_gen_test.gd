extends Control

## Standalone test scene — generates 12 species × 2 seeds = 24 alien faces.
## Run: godot --path . res://modules/alien_face_gen/demo/face_gen_test.tscn

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"
const _PALETTE_DIR := "res://modules/alien_face_gen/data/palettes"

var color

func _ready() -> void:
	# Dark background
	color = Color(0.12, 0.12, 0.14)
	
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	
	var style := StyleFlatVector.new()
	
	for sid in _SPECIES_IDS:
		for seed_val in [42, 99]:
			var sp := _load_species(sid)
			var g := GenomeGenerator.generate(sp, seed_val)
			var lm := LandmarkSolver.solve(g, Lod.LOD_CINEMATIC)
			var p := _resolve_palette(sid, g)
			var dl := Face2DRenderer.render(g, lm, p, style, Lod.LOD_CINEMATIC)
			
			var container := VBoxContainer.new()
			container.custom_minimum_size = Vector2(160, 178)

			var drawer := CanvasDrawer.new()
			drawer.custom_minimum_size = Vector2(160, 160)
			drawer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			drawer.draw_list = dl
			container.add_child(drawer)

			# Label
			var label := Label.new()
			label.text = "%s  seed:%d" % [String(sid), seed_val]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 11)
			container.add_child(label)
			
			grid.add_child(container)
	
	# Force redraw after tree enters
	await get_tree().process_frame
	for child in grid.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is CanvasDrawer:
					sub.queue_redraw()


func _load_species(id: StringName) -> SpeciesDef:
	var path := _SPECIES_DIR + "/" + String(id).to_lower() + ".tres"
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
		var path := _PALETTE_DIR + "/" + String(g.palette_id) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
	var sp := _load_species(species_id)
	if sp.allowed_palettes.size() > 0:
		var path := _PALETTE_DIR + "/" + String(sp.allowed_palettes[0]) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
	# Fallback
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
