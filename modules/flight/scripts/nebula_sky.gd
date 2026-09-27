## Bakes the flight sky's nebula panorama once and hangs it on the
## environment as its sky — see nebula_panorama.gdshader for what is drawn.
##
## The noise is far too rich to run per pixel every frame on a phone, so it
## runs once: a [SubViewport] renders the shader into an equirectangular image
## on the first frame, the image is copied into an [ImageTexture], the viewport
## is freed, and a [PanoramaSkyMaterial] shows the texture from then on — one
## texture lookup per background pixel. Rebaked when the palette changes.
##
## Until the bake lands (and wherever it cannot run: the headless dummy
## renderer returns no image) the environment keeps its flat background
## colour, so nothing depends on it. Turned off by [member
## Session.nebula_sky], which puts that flat colour back.
class_name NebulaSky
extends Node

const SHADER_PATH := "res://modules/common/juice/shaders/nebula_panorama.gdshader"

var _env: Environment = null
var _baking := false
var _rebake := false


## Bake for [param env] with the live palette. Safe to call again (a palette
## change): a bake already running finishes, then one more follows.
func bake(env: Environment) -> void:
	_env = env
	if not Session.nebula_sky:
		clear()
		return
	if _baking:
		_rebake = true
		return
	_bake_now()


## Back to the flat background colour.
func clear() -> void:
	if _env != null:
		_env.background_mode = Environment.BG_COLOR
		_env.sky = null


func _bake_now() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null or not is_inside_tree():
		return
	_baking = true
	# A phone gets half the resolution: a quarter of the memory, still far
	# sharper than the flat colour it replaces.
	var width := 2048 if OS.has_feature("mobile") else 4096
	var vp := SubViewport.new()
	vp.size = Vector2i(width, width / 2)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var wash0 := Palette.nebula_wash(0)
	var wash1 := Palette.nebula_wash(1)
	mat.set_shader_parameter("bg_color", _rgb(Palette.color("background")))
	mat.set_shader_parameter("neb_a", _rgb((wash0["core"] as Color)))
	mat.set_shader_parameter("neb_b", _rgb((wash1["core"] as Color)))
	mat.set_shader_parameter("neb_c", _rgb((wash0["edge"] as Color).lightened(0.25)))
	mat.set_shader_parameter("star_color", _rgb(Palette.color("star").lerp(Color.WHITE, 0.5)))
	mat.set_shader_parameter("seed", float(posmod(Session.seed, 997)))
	mat.set_shader_parameter("res_scale", float(width) / 4096.0)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	# Drawn on the next frame; read back once it has been presented.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image() if is_instance_valid(vp) else null
	if is_instance_valid(vp):
		vp.queue_free()
	_baking = false
	if img != null and not img.is_empty() and _env != null and Session.nebula_sky:
		img.generate_mipmaps()
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = ImageTexture.create_from_image(img)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		# The sky only paints the background: the ambient light stays the
		# palette colour the environment already sets, and its radiance map is
		# kept tiny.
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		_env.sky = sky
		_env.background_mode = Environment.BG_SKY
	if _rebake:
		_rebake = false
		_bake_now()


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
