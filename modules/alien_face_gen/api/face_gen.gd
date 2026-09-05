extends Node

const LOD_CINEMATIC := 0
const LOD_STANDARD := 1
const LOD_COMPACT := 2
const LOD_GLYPH := 3

var _cache := PortraitCache.new(64)

const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"
const _PALETTE_DIR := "res://modules/alien_face_gen/data/palettes"


func make_portrait(species_id: StringName, seed_value: int, lod := LOD_STANDARD,
		style := &"", expression := &"neutral") -> Control:
	var g := make_genome(species_id, seed_value)
	var lm := LandmarkSolver.solve(g, lod)
	var resolved_style := _resolve_style_2d(species_id, style)
	var p := _resolve_palette(species_id, g)
	var dl := Face2DRenderer.render(g, lm, p, resolved_style, lod, expression)
	
	var portrait := FacePortrait.new()
	portrait.set_draw_list(dl)
	return portrait


func make_head_3d(species_id: StringName, seed_value: int, lod := LOD_STANDARD,
		style := &"") -> Node3D:
	var g := make_genome(species_id, seed_value)
	var lm := LandmarkSolver.solve(g, 0)
	var resolved_style := _resolve_style_3d(species_id, style)
	var p := _resolve_palette(species_id, g)
	var md := Face3DBuilder.build(g, lm, p, resolved_style, lod)
	
	var head := FaceHead3D.new()
	head.set_mesh_data(md, resolved_style, p, g)
	return head


func make_genome(species_id: StringName, seed_value: int) -> FaceGenome:
	var sp := _load_species(species_id)
	return GenomeGenerator.generate(sp, seed_value)


func portrait_texture(species_id: StringName, seed_value: int, lod := LOD_STANDARD) -> Texture2D:
	# Check cache
	var style_id := &"flat_vector"
	var cached := _cache.find(species_id, seed_value, lod, style_id)
	if cached:
		return cached
	
	# Generate
	var g := make_genome(species_id, seed_value)
	var lm := LandmarkSolver.solve(g, lod)
	var p := _resolve_palette(species_id, g)
	var style := StyleFlatVector.new()
	var dl := Face2DRenderer.render(g, lm, p, style, lod)
	
	# For now, return null (actual texture rendering requires viewport)
	# In-game, this would use a SubViewport to rasterise
	return null


func species_list() -> Array[StringName]:
	var result: Array[StringName] = []
	var dir := DirAccess.open(_SPECIES_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var id := fname.get_basename().to_upper()
				result.append(StringName(id))
			fname = dir.get_next()
	return result


func random_seed_for(species_id: StringName) -> int:
	return randi()


func clear_cache() -> void:
	_cache.clear()


func export_svg(species_id: StringName, seed_value: int, path: String, lod := LOD_CINEMATIC) -> Error:
	var g := make_genome(species_id, seed_value)
	var lm := LandmarkSolver.solve(g, lod)
	var p := _resolve_palette(species_id, g)
	var style := StyleFlatVector.new()
	var dl := Face2DRenderer.render(g, lm, p, style, lod)
	return SvgExporter.save(dl, path, Lod.px_size(lod))


func export_obj(species_id: StringName, seed_value: int, path: String, lod := LOD_STANDARD) -> Error:
	var g := make_genome(species_id, seed_value)
	var lm := LandmarkSolver.solve(g, 0)
	var p := _resolve_palette(species_id, g)
	var style := StyleFaceted.new()
	var md := Face3DBuilder.build(g, lm, p, style, lod)
	return ObjExporter.save(md, path)


func _resolve_style_2d(species_id: StringName, style_id: StringName) -> StyleBase2D:
	if style_id == &"":
		var sp := _load_species(species_id)
		return Face2DRenderer.get_style(sp.default_style_2d)
	return Face2DRenderer.get_style(style_id)


func _resolve_style_3d(species_id: StringName, style_id: StringName) -> StyleBase3D:
	if style_id == &"":
		var sp := _load_species(species_id)
		match sp.default_style_3d:
			&"faceted": return StyleFaceted.new()
			&"toon": return StyleToon.new()
			&"painted_decal": return StylePaintedDecal.new()
			_: return StyleFaceted.new()
	match style_id:
		&"faceted": return StyleFaceted.new()
		&"toon": return StyleToon.new()
		&"painted_decal": return StylePaintedDecal.new()
		_: return StyleFaceted.new()


func _resolve_palette(species_id: StringName, g: FaceGenome) -> FacePalette:
	if g.palette_id != &"":
		var path := _PALETTE_DIR + "/" + String(g.palette_id) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
	# Fallback to species default
	var sp := _load_species(species_id)
	if sp.allowed_palettes.size() > 0:
		var pid: StringName = sp.allowed_palettes[0]
		var path := _PALETTE_DIR + "/" + String(pid) + ".tres"
		var p = load(path)
		if p is FacePalette:
			return p.resolve(g)
	
	return _make_fallback_palette()


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
