## The advanced-lighting post pass: light shafts from the star, a warm/cool
## colour grade and a vignette, drawn as one full-screen quad over the 3D view.
##
## A [CanvasLayer] below the HUD rather than an [Environment] feature because
## the GL Compatibility renderer has no volumetric fog or compositor: the shafts
## are a screen-space radial march (see [code]light_shafts.gdshader[/code]), and
## a canvas layer is the one place a compat-renderer shader can read the frame.
##
## Owns no settings. The caller flips [member enabled] from whatever toggle it
## already has (flight uses [member Session.cinematic_lighting]), and hands in a
## camera and a star direction; the pass follows the star's screen position
## every frame and fades out when the star is behind the camera.
class_name AdvancedLighting
extends CanvasLayer

const SHADER_PATH := "res://modules/style/assets/light_shafts.gdshader"

## Draw order: below the HUD's default layer so buttons are not graded or
## vignetted, above the 3D view it post-processes.
const LAYER := -10

## Whether the pass draws at all. Off means zero cost: the quad is hidden and
## the per-frame star projection is skipped.
var enabled := true:
	set(value):
		enabled = value
		visible = value
		set_process(value)

## The camera whose view the star is projected into.
var camera: Camera3D = null
## World direction *toward* the star (not the direction its light travels).
var sun_direction := Vector3(0.42, 0.28, 0.86)

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
## Smoothed on-screen factor, so the shafts ease in and out as the star crosses
## the frame edge instead of popping.
var _visible_amount := 0.0


## A ready-to-add pass for [param cam], lighting from [param sun_dir].
static func create(cam: Camera3D, sun_dir: Vector3) -> AdvancedLighting:
	var pass_node := AdvancedLighting.new()
	pass_node.name = "AdvancedLighting"
	pass_node.camera = cam
	pass_node.sun_direction = sun_dir.normalized()
	return pass_node


func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.name = "Post"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_rect.material = _mat
	add_child(_rect)
	# Phones get fewer march steps: the beams soften, the frame time does not.
	if OS.has_feature("mobile"):
		_mat.set_shader_parameter("samples", 16)
	visible = enabled
	set_process(enabled)


## Tint the shafts, usually to the star's own colour pulled toward white.
func set_shaft_color(color: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("shaft_color", color)


## Any other shader dial by name, for labs and tuning tools.
func set_param(param: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(param, value)


func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera) or _mat == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var far_point := camera.global_position + sun_direction * 10000.0
	var target := 0.0
	var sun_uv := Vector2(0.5, -2.0)
	# Only project a point in front of the camera: unproject_position mirrors a
	# point behind the lens back onto the screen.
	if camera.global_basis.z.dot(sun_direction) < -0.05:
		var px := camera.unproject_position(far_point)
		# A camera mid-snap can project to inf/NaN for a frame. One NaN written
		# into the smoothed value below would stick there for good -- lerp of NaN
		# is NaN -- and the shader would turn the whole screen black.
		if px.is_finite():
			sun_uv = (px / vp_size).clamp(Vector2(-3.0, -3.0), Vector2(4.0, 4.0))
			# Full strength on screen, fading out over one screen-width beyond it.
			var off := maxf(absf(sun_uv.x - 0.5) - 0.5, absf(sun_uv.y - 0.5) - 0.5)
			target = 1.0 - clampf(off / 0.8, 0.0, 1.0)
	_visible_amount = lerpf(_visible_amount, target, clampf(delta * 6.0, 0.0, 1.0))
	if not is_finite(_visible_amount):
		_visible_amount = 0.0
	_mat.set_shader_parameter("sun_uv", sun_uv)
	_mat.set_shader_parameter("sun_visible", _visible_amount)
