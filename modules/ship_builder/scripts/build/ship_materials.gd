## Central source of every material and affordance colour the builder uses.
##
## Affordance colours are read from the active [Palette]'s "Affordance" roles
## rather than declared here, so a palette switch reaches the drop targets, the
## grid and the sockets along with everything else. Turned into calls rather than
## constants because a constant cannot follow the live palette.
##
## The valid/invalid pair stays cyan/amber rather than green/red so it survives
## the common forms of colour blindness, and the high-contrast substitutes below
## override the palette outright — accessibility is not something a palette gets
## to have an opinion about.
class_name ShipMaterials
extends RefCounted

const PART_SHADER_PATH := "res://modules/ship_builder/assets/ship_part.gdshader"
const GHOST_SHADER_PATH := "res://modules/ship_builder/assets/ghost.gdshader"
const OUTLINE_SHADER_PATH := "res://modules/ship_builder/assets/outline.gdshader"

# --- High-contrast substitutes ----------------------------------------------
# Used when the accessibility toggle is on, in place of whatever the palette says.
const HC_VALID := Color("00e5ff")
const HC_INVALID := Color("ffb000")
const HC_SELECTED := Color("ffffff")
const HC_SOCKET := Color("c8d4e0")
const HC_GRID := Color(0.6, 0.68, 0.78, 0.6)

static var high_contrast := false

static var _part_shader: Shader = null
static var _ghost_shader: Shader = null
static var _outline_shader: Shader = null


static func valid_color() -> Color:
	return HC_VALID if high_contrast else Palette.color("valid")


static func invalid_color() -> Color:
	return HC_INVALID if high_contrast else Palette.color("invalid")


## Colour for the thing under the cursor. Distinct from [method valid_color]: a
## hover is "the pointer is here", a valid drop is "this would work".
static func hover_color() -> Color:
	return Palette.color("hover")


## The current part selection. Shares the interface's select role because it is
## the same colour and the same idea — "this is the one you picked".
static func selected_color() -> Color:
	return HC_SELECTED if high_contrast else Palette.color("ui_select")


static func socket_color(required: bool) -> Color:
	if required:
		return invalid_color()
	return HC_SOCKET if high_contrast else Palette.color("socket")


static func grid_color() -> Color:
	return HC_GRID if high_contrast else Palette.color("grid")


## Projectiles, beams and exhaust. Public because [code]systems_sim.gd[/code]
## uses it as the fallback for a part that names no exhaust colour of its own.
static func beam_color() -> Color:
	return Palette.color("beam")


static func part_shader() -> Shader:
	if _part_shader == null:
		_part_shader = load(PART_SHADER_PATH) as Shader
	return _part_shader


static func ghost_shader() -> Shader:
	if _ghost_shader == null:
		_ghost_shader = load(GHOST_SHADER_PATH) as Shader
	return _ghost_shader


static func outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = load(OUTLINE_SHADER_PATH) as Shader
	return _outline_shader


## One material per placed part. Cheap because they all share a single shader
## program and differ only in uniform values, but it gives every part independent
## colour overrides and its own highlight state.
static func make_part_material(design: ShipDesign, overrides: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = part_shader()
	apply_palette(mat, design, overrides)
	apply_outline(mat)
	return mat


static func apply_palette(mat: ShaderMaterial, design: ShipDesign, overrides: Dictionary) -> void:
	if mat == null or design == null:
		return
	for channel in ShipDesign.CHANNELS:
		var color: Color = overrides.get(channel, design.get_color(channel))
		mat.set_shader_parameter(channel + "_color", Palette.get_sat_lifted_color(color))
	var params := design.material_params()
	mat.set_shader_parameter("roughness_amount", float(params.get("roughness", 0.88)))
	mat.set_shader_parameter("metallic_amount", float(params.get("metallic", 0.0)))
	var spec := float(params.get("specular", 0.2))
	if Session.cinematic_lighting:
		spec *= 1.35
	mat.set_shader_parameter("specular_amount", spec)
	mat.set_shader_parameter("weathering", float(params.get("weathering", 0.0)))
	# The rim is silhouette definition, not a look. High contrast mode is allowed
	# a brighter edge because separating parts from the background matters more
	# there than the hull reading as solid metal.
	var rim := 0.34 if high_contrast else 0.16
	if Session.enhanced_lighting:
		rim += 0.25
	if Session.cinematic_lighting:
		rim += 0.35
	mat.set_shader_parameter("rim_strength", rim)
	# Occlusion and the self-lit floor are two halves of one decision. Crushing
	# the down-facing plates to black against a black stage is what made the
	# ships read as see-through, so the occlusion is gentler than it was and the
	# floor guarantees the darkest facet still out-values the void behind it.
	mat.set_shader_parameter("ao_strength", 0.24 if high_contrast else 0.32)
	mat.set_shader_parameter("solidity", 0.80 if high_contrast else 0.72)
	apply_style_dials(mat)


## Pushes the *shading* (live-apply) style dials onto any part-shader material —
## ship hulls and asteroid rocks alike, since both share [member PART_SHADER_PATH].
## Kept separate from [method apply_palette] so [code]space_scene.gd[/code]'s rock
## material builder can call it without needing a [ShipDesign].
static func apply_style_dials(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	# The global toon override is set first and independently of the profile: it
	# has to survive a profile being absent, and it is the one flag that reaches
	# every surface sharing this shader (hulls, asteroids, station shells).
	mat.set_shader_parameter("toon_override", 1.0 if ToonOverride.enabled() else 0.0)
	var is_wf: bool = StyleManager.instance().is_wireframe()
	mat.set_shader_parameter("wireframe_mode", 1.0 if is_wf else 0.0)
	if is_wf:
		mat.set_shader_parameter("wireframe_color", Color(1.0, 0.88, 0.18, 1.0))
	var style := StyleManager.instance().current_profile
	if not style:
		return
	mat.set_shader_parameter("shading_bands", float(style.shading_bands))
	mat.set_shader_parameter("spec_mult", style.spec_amount)
	mat.set_shader_parameter("rim_mult", style.rim_amount)



## Attaches the ink-outline pass (see outline.gdshader) as [member Material.next_pass]
## when the current style calls for one, and strips it back off when it doesn't —
## so re-applying a style with outline_width back at 0 actually removes the line
## rather than leaving a stale pass at its last width.
static func apply_outline(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var style := StyleManager.instance().current_profile
	var width := style.outline_width if style != null else 0.0
	var col := style.outline_color if style != null else Color.BLACK
	if width <= 0.0:
		mat.next_pass = null
		return
	var outline := ShaderMaterial.new()
	outline.shader = outline_shader()
	outline.set_shader_parameter("outline_color", col)
	outline.set_shader_parameter("outline_width", width)
	mat.next_pass = outline


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
