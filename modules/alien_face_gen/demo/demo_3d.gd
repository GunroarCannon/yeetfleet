extends Node3D

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

var _rotation_angle: float = 0.0


func _ready() -> void:
	# Create 12 heads on a turntable
	var count := _SPECIES_IDS.size()
	for i in range(count):
		var sid: StringName = _SPECIES_IDS[i]
		var angle := TAU * i / count
		var radius := 3.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		
		var g := GenomeGenerator.generate(_load_species(sid), 42)
		var lm := LandmarkSolver.solve(g, 0)
		var p := _resolve_palette(sid, g)
		var style := StyleFaceted.new()
		var md := Face3DBuilder.build(g, lm, p, style, Lod.LOD_STANDARD)
		
		var head := FaceHead3D.new()
		head.position = pos
		add_child(head)  # Must be in the tree before look_at()/set_mesh_data()
		head.look_at(Vector3.ZERO)
		head.set_mesh_data(md, style, p, g)
	
	# Add camera
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2, 6)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))

	# Add light
	var light := DirectionalLight3D.new()
	light.position = Vector3(2, 3, 1)
	add_child(light)
	light.look_at(Vector3.ZERO)


func _process(delta: float) -> void:
	_rotation_angle += delta * 0.3
	rotation.y = _rotation_angle


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
