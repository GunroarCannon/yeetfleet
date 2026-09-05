extends Node

## Renders real contact-sheet grids to res://out/*.png.
## Run with a real window (not --headless) or the PNGs come out blank:
##   godot --path . res://modules/alien_face_gen/demo/contact_sheet.tscn
## Quits by itself once every sheet is saved.

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]
const _STYLES := [&"flat_vector", &"pixel_art", &"ink_outline"]

const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"
const _PALETTE_DIR := "res://modules/alien_face_gen/data/palettes"

var _sheets: Array = []
var _sheet_index := 0


func _ready() -> void:
	# 1. 12 species × 8 seeds, flat_vector, LOD cinematic.
	var sheet_2d := {"path": "res://out/contact_sheet_2d.png", "cols": 8, "cell": 128, "cells": []}
	for sid in _SPECIES_IDS:
		for i in range(8):
			sheet_2d["cells"].append(_render_face(sid, i * 13 + 1, Lod.LOD_CINEMATIC, &"flat_vector"))
	_sheets.append(sheet_2d)

	# 2. First 6 species × 3 styles, one seed, LOD cinematic.
	var sheet_styles := {"path": "res://out/contact_sheet_styles.png", "cols": 3, "cell": 256, "cells": []}
	for i in range(6):
		for style_id in _STYLES:
			sheet_styles["cells"].append(_render_face(_SPECIES_IDS[i], 42, Lod.LOD_CINEMATIC, style_id))
	_sheets.append(sheet_styles)

	# 3. First 6 species × 4 LODs, flat_vector, one seed.
	var sheet_lod := {"path": "res://out/contact_sheet_lod.png", "cols": 4, "cell": 256, "cells": []}
	for i in range(6):
		for lod in range(4):
			sheet_lod["cells"].append(_render_face(_SPECIES_IDS[i], 42, lod, &"flat_vector"))
	_sheets.append(sheet_lod)

	_render_next_sheet()


func _render_face(species_id: StringName, seed_value: int, lod: int, style_id: StringName) -> DrawList:
	var g := GenomeGenerator.generate(_load_species(species_id), seed_value)
	var lm := LandmarkSolver.solve(g, lod)
	var p := _resolve_palette(species_id, g)
	var style := Face2DRenderer.get_style(style_id)
	return Face2DRenderer.render(g, lm, p, style, lod)


func _render_next_sheet() -> void:
	if _sheet_index >= _sheets.size():
		print("All contact sheets rendered.")
		get_tree().quit()
		return

	var sheet: Dictionary = _sheets[_sheet_index]
	_sheet_index += 1
	await _render_sheet_to_file(sheet)
	_render_next_sheet()


func _render_sheet_to_file(sheet: Dictionary) -> void:
	var cols: int = sheet["cols"]
	var cell: int = sheet["cell"]
	var cells: Array = sheet["cells"]
	var path: String = sheet["path"]
	var rows := ceili(float(cells.size()) / cols)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(cols * cell, rows * cell)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	# Backdrop behind the face tiles.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.09, 0.09, 0.11)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(backdrop)

	for i in range(cells.size()):
		var drawer := CanvasDrawer.new()
		drawer.position = Vector2(i % cols * cell, i / cols * cell)
		drawer.size = Vector2(cell, cell)
		drawer.draw_list = cells[i]
		viewport.add_child(drawer)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var img := viewport.get_texture().get_image()
	if img:
		img.save_png(path)
		print("Saved: ", path, " (", cols * cell, "x", rows * cell, ")")
	viewport.queue_free()


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
