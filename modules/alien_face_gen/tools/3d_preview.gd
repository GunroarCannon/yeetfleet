extends Node

## Renders 6 species' 3D heads (faceted style) as front and side contact sheets
## into res://out/previews/, so material/geometry changes can be eyeballed.
## Run with a real window (not --headless):
##   godot --path . res://modules/alien_face_gen/tools/3d_preview.tscn

const _SPECIES_IDS := [
	&"NORDIC", &"VOID_GREY", &"DRACONIAN", &"MANTID", &"BRUTE", &"AVIARN",
]
const _COLS := 3
const _CELL := 360

const _SPECIES_DIR := "res://modules/alien_face_gen/data/species"
const _PALETTE_DIR := "res://modules/alien_face_gen/data/palettes"

var _species: Array = []


func _ready() -> void:
	for sid in _SPECIES_IDS:
		var sp := _load_species(sid)
		var g := GenomeGenerator.generate(sp, 42)
		var lm := LandmarkSolver.solve(g, Lod.LOD_STANDARD)
		var p := _resolve_palette(sid, g)
		var md := Face3DBuilder.build(g, lm, p, StyleFaceted.new(), Lod.LOD_STANDARD)
		_species.append({"id": sid, "md": md, "palette": p, "genome": g})

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out/previews"))
	await _render_view("front")
	await _render_view("side")
	print("3D previews written to res://out/previews/")
	get_tree().quit()


func _render_view(view: String) -> void:
	var rows := ceili(float(_species.size()) / _COLS)
	var vp_w := _COLS * _CELL
	var vp_h := rows * _CELL

	var vp := SubViewport.new()
	vp.size = Vector2i(vp_w, vp_h)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	# Subtle scene environment so unshaded/baked materials read correctly.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# Heads laid out in a grid facing +Z (toward the front camera). For the side
	# camera the columns must spread along Z (depth) so heads don't overlap.
	var spacing_x := 1.7
	var spacing_y := 1.9
	for i in range(_species.size()):
		var col := i % _COLS
		var row := i / _COLS
		var gx := (col - (_COLS - 1) * 0.5) * spacing_x
		var gy := ((rows - 1) * 0.5 - row) * spacing_y
		var head := FaceHead3D.new()
		vp.add_child(head)
		if view == "front":
			head.position = Vector3(gx, gy, 0)
		else:
			# +X camera: screen x ~ world z, so spread columns in z.
			head.position = Vector3(0, gy, gx)
		var item: Dictionary = _species[i]
		head.set_mesh_data(item["md"], StyleFaceted.new(), item["palette"], item["genome"])

	# Lights
	for dir in [Vector3(2, 3, 4), Vector3(-3, -1, 2)]:
		var light := DirectionalLight3D.new()
		light.light_energy = 1.2
		vp.add_child(light)
		light.look_at_from_position(dir, Vector3.ZERO)

	# Camera
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = spacing_y * rows + 1.4
	cam.far = 50.0
	if view == "front":
		cam.look_at_from_position(Vector3(0, 0, 8), Vector3.ZERO)
	elif view == "side":
		cam.look_at_from_position(Vector3(8, 0, 0), Vector3.ZERO)
	vp.add_child(cam)

	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	if img:
		var path := "res://out/previews/%s.png" % view
		img.save_png(path)
		print("Saved: ", path)
	vp.queue_free()
	await get_tree().process_frame


func _load_species(id: StringName) -> SpeciesDef:
	var s = load(_SPECIES_DIR + "/" + String(id).to_lower() + ".tres")
	if s == null:
		var sd := SpeciesDef.new()
		sd.id = id
		sd.allowed_palettes = [&"void_grey"]
		return sd
	return s


func _resolve_palette(species_id: StringName, g: FaceGenome) -> FacePalette:
	var sp := _load_species(species_id)
	if sp.allowed_palettes.size() > 0:
		var p = load(_PALETTE_DIR + "/" + String(sp.allowed_palettes[0]) + ".tres")
		if p is FacePalette:
			return p.resolve(g)
	var p := FacePalette.new()
	p.skin_base = Color(0.7, 0.7, 0.7)
	p.skin_shade = Color(0.5, 0.5, 0.5)
	p.skin_light = Color(0.9, 0.9, 0.9)
	p.skin_deep = Color(0.3, 0.3, 0.3)
	p.eye_sclera = Color(1, 1, 1)
	p.eye_iris = Color(0.2, 0.2, 0.2)
	p.eye_pupil = Color(0, 0, 0)
	p.eye_glow = Color(0.8, 0.8, 0.3)
	p.mouth_inner = Color(0.5, 0.2, 0.2)
	p.crest = Color(0.3, 0.3, 0.3)
	p.background = Color(0.2, 0.2, 0.2)
	p.outline = Color(0, 0, 0)
	return p
