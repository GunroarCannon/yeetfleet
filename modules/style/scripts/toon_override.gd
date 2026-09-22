## One switch that forces every element into toon shading.
##
## The project already has a toon path built into its own shaders — the
## [StyleProfile] band dial steps the light in [code]ship_part.gdshader[/code]
## and flattens the planet bands — because those shaders carry per-part vertex
## masks and procedural planet surfaces that a general-purpose toon shader
## cannot reproduce. This toggle drives that path globally instead of per
## profile, so "toon on" is one click and reaches hulls, rocks, stations and
## planets at once.
##
## [method shader] exposes the UltimateToonSource addon's
## [code]stylized.gdshader[/code] for anything that wants a conventional toon
## material (a flat-shaded prop with its own textures, say). It is not forced
## onto the project's own surfaces, because dropping a texture-driven toon
## shader over a vertex-colour hull would lose the hull's paint.
##
## The setting lives in [StyleSettings] so it persists and so [StyleManager] can
## push it with the same [method StyleManager.apply] pass the profile and
## palette use.
class_name ToonOverride
extends RefCounted

const SHADER_PATH := "res://addons/UltimateToonSource/shader/stylized.gdshader"

static var _shader: Shader = null


## Whether toon shading is forced on.
static func enabled() -> bool:
	return StyleSettings.toon_shading


## Turn it on or off and push the change through the live style pass, so every
## material that reads [method enabled] picks it up this frame.
static func set_enabled(value: bool) -> void:
	StyleManager.instance().set_toon_shading(value)


## The addon's toon shader, loaded once, or null when the addon is missing.
static func shader() -> Shader:
	if _shader == null and ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH) as Shader
	return _shader


## A ready-to-use toon material for [param albedo], with the addon shader's
## texture-driven features (pattern, normal map) switched off so it renders
## correctly on a mesh that has neither.
static func make_material(albedo: Color, steps := 3.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var s := shader()
	if s == null:
		return null
	mat.shader = s
	mat.set_shader_parameter("albedo_color", albedo)
	mat.set_shader_parameter("albedo_affect", 0.0)
	mat.set_shader_parameter("use_stepped", true)
	mat.set_shader_parameter("steps", steps)
	mat.set_shader_parameter("use_pattern", false)
	mat.set_shader_parameter("use_rim", true)
	mat.set_shader_parameter("specular", 0.0)
	return mat
