## Central source of every material and affordance colour the builder uses.
##
## Keeping the palette in one place matters for accessibility: the valid/invalid
## pair is cyan/amber rather than green/red so it survives the common forms of
## colour blindness, and a high-contrast mode can lift every affordance at once
## instead of hunting through scene files.
class_name ShipMaterials
extends RefCounted

const PART_SHADER_PATH := "res://modules/ship_builder/assets/ship_part.gdshader"
const GHOST_SHADER_PATH := "res://modules/ship_builder/assets/ghost.gdshader"

# --- Affordance colours -----------------------------------------------------
const COL_VALID := Color("39c0ff")
const COL_INVALID := Color("ff8a3d")
const COL_SELECTED := Color("ffd84d")
const COL_HOVER := Color("8fe3ff")
const COL_SOCKET := Color("7d8b9c")
const COL_SOCKET_REQUIRED := Color("ff8a3d")
const COL_GRID := Color(0.30, 0.36, 0.44, 0.35)
const COL_BEAM := Color("6ff0d0")

# High-contrast substitutes, used when the accessibility toggle is on.
const HC_VALID := Color("00e5ff")
const HC_INVALID := Color("ffb000")
const HC_SELECTED := Color("ffffff")
const HC_SOCKET := Color("c8d4e0")
const HC_GRID := Color(0.6, 0.68, 0.78, 0.6)

static var high_contrast := false

static var _part_shader: Shader = null
static var _ghost_shader: Shader = null


static func valid_color() -> Color:
	return HC_VALID if high_contrast else COL_VALID


static func invalid_color() -> Color:
	return HC_INVALID if high_contrast else COL_INVALID


static func selected_color() -> Color:
	return HC_SELECTED if high_contrast else COL_SELECTED


static func socket_color(required: bool) -> Color:
	if required:
		return HC_INVALID if high_contrast else COL_SOCKET_REQUIRED
	return HC_SOCKET if high_contrast else COL_SOCKET


static func grid_color() -> Color:
	return HC_GRID if high_contrast else COL_GRID


static func part_shader() -> Shader:
	if _part_shader == null:
		_part_shader = load(PART_SHADER_PATH) as Shader
	return _part_shader


static func ghost_shader() -> Shader:
	if _ghost_shader == null:
		_ghost_shader = load(GHOST_SHADER_PATH) as Shader
	return _ghost_shader


## One material per placed part. Cheap because they all share a single shader
## program and differ only in uniform values, but it gives every part independent
## colour overrides and its own highlight state.
static func make_part_material(design: ShipDesign, overrides: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = part_shader()
	apply_palette(mat, design, overrides)
	return mat


static func apply_palette(mat: ShaderMaterial, design: ShipDesign, overrides: Dictionary) -> void:
	if mat == null or design == null:
		return
	for channel in ShipDesign.CHANNELS:
		var color: Color = overrides.get(channel, design.get_color(channel))
		mat.set_shader_parameter(channel + "_color", color)
	var params := design.material_params()
	mat.set_shader_parameter("roughness_amount", float(params.get("roughness", 0.88)))
	mat.set_shader_parameter("metallic_amount", float(params.get("metallic", 0.0)))
	mat.set_shader_parameter("specular_amount", float(params.get("specular", 0.2)))
	mat.set_shader_parameter("weathering", float(params.get("weathering", 0.0)))
	# The rim is silhouette definition, not a look. High contrast mode is allowed
	# a brighter edge because separating parts from the background matters more
	# there than the hull reading as solid metal.
	mat.set_shader_parameter("rim_strength", 0.34 if high_contrast else 0.16)
	# Occlusion and the self-lit floor are two halves of one decision. Crushing
	# the down-facing plates to black against a black stage is what made the
	# ships read as see-through, so the occlusion is gentler than it was and the
	# floor guarantees the darkest facet still out-values the void behind it.
	mat.set_shader_parameter("ao_strength", 0.24 if high_contrast else 0.32)
	mat.set_shader_parameter("solidity", 0.24 if high_contrast else 0.17)


static func set_highlight(mat: ShaderMaterial, amount: float, color := Color.TRANSPARENT) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("highlight", clampf(amount, 0.0, 1.0))
	if color.a > 0.0:
		mat.set_shader_parameter("highlight_color", color)


static func set_dim(mat: ShaderMaterial, amount: float) -> void:
	if mat != null:
		mat.set_shader_parameter("dim", clampf(amount, 0.0, 1.0))


static func make_ghost_material(valid := true) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ghost_shader()
	mat.set_shader_parameter("ghost_color", valid_color() if valid else invalid_color())
	return mat


## Unshaded material for line meshes: sockets, brackets, the grid.
##
## [param fadeable] forces the alpha path on even when the starting colour is
## opaque. Socket markers need it: they are recoloured in place to signal "this
## mount cannot take what you are holding", and a material built opaque ignores
## every alpha written to it afterwards -- which is how dimmed markers ended up
## just as bright as live ones.
static func line_material(color: Color, fadeable := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = false
	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if fadeable or color.a < 0.99
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	return mat


## Emissive flat material for projectiles, beams and exhaust sprites.
static func glow_material(color: Color, transparent := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	return mat
