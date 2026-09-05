## Full-screen colour flash, damage vignette and the continuous speed-line ramp,
## all as uniforms on one [ColorRect] running `flash_overlay.gdshader` — so a
## boost frame flare and a low-capacitor pulse never cost a second draw.
class_name ScreenFlash
extends CanvasLayer

const SHADER_PATH := "res://modules/common/juice/shaders/flash_overlay.gdshader"

var _rect: ColorRect
var _material: ShaderMaterial

var _flash_color := Color.TRANSPARENT
var _flash_strength := 0.0
var _flash_decay := 0.25

var _vignette_color := Color.TRANSPARENT
var _vignette_strength := 0.0
var _vignette_decay := 0.25


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Overlay"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	var shader := load(SHADER_PATH) as Shader
	if shader != null:
		_material.shader = shader
	_rect.material = _material
	add_child(_rect)
	set_process(true)


## A new flash raises the current one rather than replacing it, so a rapid
## second hit reads as brighter instead of resetting the fade already in flight.
func flash(color: Color, strength: float, decay: float) -> void:
	_flash_color = color
	_flash_strength = maxf(_flash_strength, strength)
	_flash_decay = maxf(decay, 0.01)


func vignette(color: Color, strength: float, decay: float) -> void:
	_vignette_color = color
	_vignette_strength = maxf(_vignette_strength, strength)
	_vignette_decay = maxf(decay, 0.01)


func set_speed_lines(fraction: float) -> void:
	if _material != null:
		_material.set_shader_parameter("speed_fraction", fraction)


func _process(delta: float) -> void:
	if _flash_strength > 0.0:
		_flash_strength = maxf(_flash_strength - delta / _flash_decay, 0.0)
	if _vignette_strength > 0.0:
		_vignette_strength = maxf(_vignette_strength - delta / _vignette_decay, 0.0)
	if _material == null:
		return
	_material.set_shader_parameter("flash_color", _flash_color)
	_material.set_shader_parameter("flash_strength", _flash_strength)
	_material.set_shader_parameter("vignette_color", _vignette_color)
	_material.set_shader_parameter("vignette_strength", _vignette_strength)
