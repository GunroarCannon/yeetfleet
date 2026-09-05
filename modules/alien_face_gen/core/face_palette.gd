class_name FacePalette extends Resource

@export var id: StringName = &""
@export var is_emissive_palette: bool = false

@export var skin_base: Color = Color.WHITE
@export var skin_shade: Color = Color.WHITE
@export var skin_light: Color = Color.WHITE
@export var skin_deep: Color = Color.WHITE
@export var eye_sclera: Color = Color.WHITE
@export var eye_iris: Color = Color.WHITE
@export var eye_pupil: Color = Color.WHITE
@export var eye_glow: Color = Color.WHITE
@export var mouth_inner: Color = Color.WHITE
@export var tooth: Color = Color.WHITE
@export var marking_a: Color = Color.WHITE
@export var marking_b: Color = Color.WHITE
@export var crest: Color = Color.WHITE
@export var garment: Color = Color.WHITE
@export var garment_trim: Color = Color.WHITE
@export var background: Color = Color.WHITE
@export var outline: Color = Color.WHITE

func get_all_colors() -> Array[Color]:
	return [
		skin_base, skin_shade, skin_light, skin_deep,
		eye_sclera, eye_iris, eye_pupil, eye_glow,
		mouth_inner, tooth, marking_a, marking_b,
		crest, garment, garment_trim, background, outline
	]

func resolve(genome: FaceGenome) -> FacePalette:
	var resolved: FacePalette = FacePalette.new()
	resolved.id = id
	resolved.is_emissive_palette = is_emissive_palette
	
	# Copy background and outline unchanged (never perturbed)
	resolved.background = background
	resolved.outline = outline
	
	# Perturb other colors
	var h_shift := (genome.hue_shift - 0.5) * 0.08
	var s_scale := 0.75 + genome.sat_scale * 0.5
	var v_scale := 0.85 + genome.val_scale * 0.3
	
	resolved.skin_base = _perturb(skin_base, h_shift, s_scale, v_scale)
	resolved.skin_shade = _perturb(skin_shade, h_shift, s_scale, v_scale)
	resolved.skin_light = _perturb(skin_light, h_shift, s_scale, v_scale)
	resolved.skin_deep = _perturb(skin_deep, h_shift, s_scale, v_scale)
	resolved.eye_sclera = _perturb(eye_sclera, h_shift, s_scale, v_scale)
	resolved.eye_iris = _perturb(eye_iris, h_shift, s_scale, v_scale)
	resolved.eye_pupil = _perturb(eye_pupil, h_shift, s_scale, v_scale)
	resolved.eye_glow = _perturb(eye_glow, h_shift, s_scale, v_scale)
	resolved.mouth_inner = _perturb(mouth_inner, h_shift, s_scale, v_scale)
	resolved.tooth = _perturb(tooth, h_shift, s_scale, v_scale)
	resolved.marking_a = _perturb(marking_a, h_shift, s_scale, v_scale)
	resolved.marking_b = _perturb(marking_b, h_shift, s_scale, v_scale)
	resolved.crest = _perturb(crest, h_shift, s_scale, v_scale)
	resolved.garment = _perturb(garment, h_shift, s_scale, v_scale)
	resolved.garment_trim = _perturb(garment_trim, h_shift, s_scale, v_scale)
	
	return resolved

func _perturb(c: Color, h_shift: float, s_scale: float, v_scale: float) -> Color:
	var hsv := Vector3(c.h, c.s, c.v)
	hsv.x = fmod(hsv.x + h_shift + 1.0, 1.0)
	hsv.y = clampf(hsv.y * s_scale, 0.0, 1.0)
	hsv.z = clampf(hsv.z * v_scale, 0.0, 1.0)
	return Color.from_hsv(hsv.x, hsv.y, hsv.z)
