## A one-shot party popper: smiley stars, hearts and candy from the sprite sheet,
## plus a flutter of rainbow paper. Frees itself when the last piece fades.
##
## CPU particles rather than GPU: they run identically on every renderer
## including the phone GL path, and a burst this size costs nothing on the CPU.
extends Node3D

const SHEET_PATH := "res://modules/whimsy/assets/confetti_sheet.png"
const SHEET_FRAMES := 4
const LIFETIME := 1.8

static var _sprite_mat: StandardMaterial3D = null
static var _paper_mat: StandardMaterial3D = null


## [param size] scales spread, speed and sprite size together: 1.0 suits a
## fighter-sized pop, a mother ship wants 4 or 5.
func setup(size: float) -> void:
	var mobile := OS.has_feature("mobile")
	add_child(_sprites(size, 10 if mobile else 18))
	add_child(_paper(size, 16 if mobile else 36))
	get_tree().create_timer(LIFETIME + 0.3, false).timeout.connect(queue_free)


func _sprites(size: float, count: int) -> CPUParticles3D:
	var p := _base_emitter(count, size)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 0.9 * size
	p.mesh = mesh
	p.material_override = _sprite_material()
	# Each particle holds one random cell of the sheet for its whole life.
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.angle_min = -30.0
	p.angle_max = 30.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.initial_velocity_min = 5.0 * size
	p.initial_velocity_max = 11.0 * size
	return p


func _paper(size: float, count: int) -> CPUParticles3D:
	var p := _base_emitter(count, size)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.28, 0.16) * size
	p.mesh = mesh
	p.material_override = _paper_material()
	# Not billboarded: flat paper spinning about its own axis flickers edge-on
	# and face-on, which is exactly how real confetti catches the light.
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.initial_velocity_min = 6.0 * size
	p.initial_velocity_max = 15.0 * size
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color("ff5d8f"), Color("ffd23f"), Color("7ee0ff"),
		Color("8cff7a"), Color("b58cff"), Color("ff9f43"),
	])
	p.color_initial_ramp = ramp
	return p


func _base_emitter(count: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = LIFETIME
	p.randomness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * size
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0 * size
	p.damping_max = 6.0 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.12, 1.15))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.local_coords = false
	p.emitting = true
	return p


static func _sprite_material() -> StandardMaterial3D:
	if _sprite_mat == null:
		_sprite_mat = StandardMaterial3D.new()
		_sprite_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sprite_mat.albedo_texture = load(SHEET_PATH) as Texture2D
		_sprite_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sprite_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_sprite_mat.particles_anim_h_frames = SHEET_FRAMES
		_sprite_mat.particles_anim_v_frames = 1
		_sprite_mat.particles_anim_loop = false
		_sprite_mat.vertex_color_use_as_albedo = true
		_sprite_mat.disable_receive_shadows = true
	return _sprite_mat


static func _paper_material() -> StandardMaterial3D:
	if _paper_mat == null:
		_paper_mat = StandardMaterial3D.new()
		_paper_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_paper_mat.vertex_color_use_as_albedo = true
		_paper_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_paper_mat.disable_receive_shadows = true
	return _paper_mat
