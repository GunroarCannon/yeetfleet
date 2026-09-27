## Assembles a complete planet from a [PlanetData] resource: a displaced
## cube-sphere with a procedural surface shader, an optional ring disc, and an
## optional atmospheric glow layer.
##
## The body mesh comes from [PlanetGenerator] (addons/celestial_bodies), which
## threads the generation across a [WorkerThreadPool] and displaces the sphere
## with two [FastNoiseLite] layers seeded from [member PlanetData.seed_value].
## That is what makes the seed mean something: it picks the coastlines and the
## mountain ranges, not just the palette.
##
## Three levels of update, cheapest first, because a slider drag should not pay
## for a mesh rebuild:
## [br]• [method refresh_appearance] — shader uniforms only. No allocation.
## [br]• [method refresh_geometry] — re-displaces the mesh and resizes the ring.
## [br]• [method configure] — full teardown, for when the set of nodes changes.
##
## Generation is asynchronous. Anything that needs the surfaces to exist right
## now (a test, a screenshot tool) should await [method wait_for_build].
##
## Meant to be a child of [SpaceScene] or a standalone node for the editor
## preview — both use this, so a planet saved in the editor is the planet flown
## past in the flight scene. Does not extend [CelestialBody3D] because neither
## needs physics from it: the flight scene's planet collision is a distance check
## against [constant SpaceScene.PLANET_RADIUS] in [FlightModel], and the editor
## preview is only ever looked at.
class_name Planet
extends Node3D

const SURFACE_SHADER_PATH := "res://modules/common/planets/shaders/planet_surface.gdshader"
## Alternative surface technique — real per-pixel bump instead of one manual
## unshaded sun term. See [method swap_all_surface_shaders] and that
## shader's own header comment.
const SURFACE_SHADER_ALT_PATH := "res://modules/common/planets/shaders/planet_surface_textured.gdshader"
## Third technique: cel-shaded bands, tinted shade, rim light and halftone —
## adapted from the UltimateToonSource addon but self-contained.
const SURFACE_SHADER_TOON_PATH := "res://modules/common/planets/shaders/planet_surface_toon.gdshader"
## Every surface technique the Planet look picker offers, in menu order. Each
## honours the same uniform set ([method _write_surface_params]), so a planet
## can switch between them live. Deleting a technique's shader file leaves its
## entry falling back to the painted look — see [method set_surface_style].
const SURFACE_STYLES: Array[Dictionary] = [
	{"name": "Painted (flat, sun-shaded)", "path": SURFACE_SHADER_PATH},
	{"name": "Textured (real bump lighting)", "path": SURFACE_SHADER_ALT_PATH},
	{"name": "Toon (cel bands, rim, halftone)", "path": SURFACE_SHADER_TOON_PATH},
]
const RING_SHADER_PATH := "res://modules/common/planets/shaders/planet_rings.gdshader"
const CLOUD_SHADER_PATH := "res://modules/common/planets/shaders/planet_clouds.gdshader"
const LIMB_SHADER_PATH := "res://modules/common/juice/shaders/limb_glow.gdshader"
const ATMOSPHERE_SAFE_PATH := "res://modules/common/juice/shaders/atmosphere_safe.gdshader"

## World-space direction the light arrives from. The surface shader lights from
## this rather than from a real [DirectionalLight3D] because it renders
## unshaded — set it to match whatever sun the scene shows.
@export var sun_direction := Vector3(0.42, 0.28, 0.86)

## High-detail rebuild: SpaceScene sets this when the player toggles high-res, so
## the atmosphere shell is built with a denser sphere (less visibly faceted)
## instead of the low-poly default.
static var high_detail := false

var data: PlanetData

var _body: PlanetGenerator
var _ring: MeshInstance3D
var _atmosphere: MeshInstance3D
## Translucent cloud layer, above the surface and inside/around the atmosphere.
var _clouds: MeshInstance3D
## The billboard face rocks already wear (see [method Whimsy.attach_billboard_face]);
## null when whimsy is off. Stars skip this — they get [method Whimsy.make_sun_face]
## from whoever builds them, since [Planet] only ever sees planets and moons (see
## [method SolarSystemGenerator._make_planet_node]'s doc).
var _face: Node3D = null

# What the current noise layers were built from. Assigning a Noise makes the
# generator regenerate, and a freshly constructed FastNoiseLite never compares
# equal to the old one, so without this a nudge of the ring width would re-noise
# all six faces of the sphere for nothing.
var _noise_signature := ""

## How hard a palette switch pulls this planet's colours toward the palette's
## planet roles. Not 1.0 on purpose: a palette has one pair of planet hues, and
## matching it exactly would make every world in a system the same colour. The
## remainder keeps the authored per-planet character.
const PALETTE_MIX := 0.7

## The colours as authored, captured the first time [method apply_palette] runs
## so repeated palette switches blend from the original rather than compounding
## lerp on top of lerp.
var _base_colors := {}


## Which atmosphere shader to use. Set from FlightRoot debug menu.
static var atmosphere_shader_path := ATMOSPHERE_SAFE_PATH

## Swap the atmosphere shader on ALL existing planets. Called from the
## debug menu when the player toggles between safe and original.
static func swap_all_atmosphere_shaders(use_safe: bool) -> void:
	atmosphere_shader_path = ATMOSPHERE_SAFE_PATH if use_safe else LIMB_SHADER_PATH
	var shader := load(atmosphere_shader_path) as Shader
	# Walk the scene tree to find all Planet nodes.
	for node in Engine.get_main_loop().get_nodes_in_group("planets"):
		if node is Planet and node._atmosphere != null:
			var mat := node._atmosphere.material_override as ShaderMaterial
			if mat != null:
				mat.shader = shader


## Which surface shader technique to use. Set from the debug menu ("AltSurface")
## and the flight-test planet-look picker — see [member Session.planet_surface_alt].
static var surface_shader_path := SURFACE_SHADER_PATH

## Swap the surface shader technique on ALL existing planets — same group-walk
## pattern as [method swap_all_atmosphere_shaders]. [method _write_surface_params]
## sets the same uniform set on either shader (see [constant
## SURFACE_SHADER_ALT_PATH]'s own note), so no other change is needed.
static func swap_all_surface_shaders(use_alt: bool) -> void:
	set_surface_style(1 if use_alt else 0)


## Switch every planet (and the ones built from now on) to technique
## [param style], an index into [constant SURFACE_STYLES]. A technique whose
## shader file has been removed falls back to the painted one.
static func set_surface_style(style: int) -> void:
	style = clampi(style, 0, SURFACE_STYLES.size() - 1)
	var path: String = SURFACE_STYLES[style]["path"]
	if not ResourceLoader.exists(path):
		path = SURFACE_SHADER_PATH
	surface_shader_path = path
	var shader := load(surface_shader_path) as Shader
	for node in Engine.get_main_loop().get_nodes_in_group("planets"):
		if node is Planet and node._body != null:
			var mat := node._body.material_override as ShaderMaterial
			if mat != null:
				mat.shader = shader


## Bind a [PlanetData] and build the meshes. Safe to call again — tears
## down the previous build first.
func configure(new_data: PlanetData) -> void:
	data = new_data
	if not is_in_group("planets"):
		add_to_group("planets")
	_teardown()
	if data == null:
		return
	_build_body()
	if data.ring_enabled:
		_build_ring()
	if data.atmosphere_density > 0.0:
		_build_atmosphere()
	if data.cloud_density > 0.0:
		_build_clouds()
	# Recolour to the live palette if one is active. With no palette (the
	# default) this is a no-op, so an authored planet keeps exactly the colours
	# the editor gave it.
	apply_palette()
	_build_face()


## Pull this planet's colours toward the active palette's planet roles, keeping
## the distance between them loose enough that a generated system's worlds still
## read as individuals.
##
## Anchored to a snapshot of the authored colours taken on first call, so
## switching palettes twice does not darken or desaturate anything — the blend is
## always palette-from-authored, never palette-from-last-palette. A no-op when no
## palette is active, which is what keeps the palette rollout invisible until a
## palette is actually chosen.
func apply_palette(mix := PALETTE_MIX) -> void:
	if data == null:
		return
	var manager := StyleManager.instance()
	if manager == null or manager.current_palette == null:
		return
	if _base_colors.is_empty():
		_base_colors = {
			"primary": data.primary_color,
			"secondary": data.secondary_color,
			"water": data.water_color,
			"ring_a": data.ring_color_a,
			"ring_b": data.ring_color_b,
			"atmosphere": data.atmosphere_color,
			"cloud": data.cloud_color,
		}
	var primary: Color = _base_colors["primary"]
	var secondary: Color = _base_colors["secondary"]
	data.primary_color = primary.lerp(Palette.color("planet_primary"), mix)
	data.secondary_color = secondary.lerp(Palette.color("planet_secondary"), mix)
	data.water_color = (_base_colors["water"] as Color).lerp(
		Palette.planet_sea(data.primary_color, 0.25), mix
	)
	data.ring_color_a = (_base_colors["ring_a"] as Color).lerp(Palette.color("planet_ring"), mix)
	data.ring_color_b = (_base_colors["ring_b"] as Color).lerp(
		Palette.color("planet_ring").darkened(0.3), mix
	)
	data.atmosphere_color = (_base_colors["atmosphere"] as Color).lerp(
		Palette.planet_sky(data.primary_color, 0.0, 0.2), mix
	)
	data.cloud_color = (_base_colors["cloud"] as Color).lerp(Palette.color("planet_cloud"), mix)
	refresh_appearance()


## Push colours and shader parameters at the existing materials. Nothing is
## rebuilt, so this is what colour pickers and the swirl/detail sliders call.
func refresh_appearance() -> void:
	if data == null:
		return
	if _body != null:
		_write_surface_params(_body.material_override as ShaderMaterial)
	if _ring != null:
		var ring_mat := _ring.material_override as ShaderMaterial
		if ring_mat != null:
			ring_mat.set_shader_parameter("ring_color_a", data.ring_color_a)
			ring_mat.set_shader_parameter("ring_color_b", data.ring_color_b)
			ring_mat.set_shader_parameter("dust_density", data.ring_dust_density)
			ring_mat.set_shader_parameter("ring_opacity", data.ring_opacity)
			ring_mat.set_shader_parameter("band_frequency", float(data.ring_bands))
	if _atmosphere != null:
		var atmo_mat := _atmosphere.material_override as ShaderMaterial
		if atmo_mat != null:
			atmo_mat.set_shader_parameter("glow_color", data.atmosphere_color)
			# A rim glow, not a hazy ball: 1.2× density reads as a clear limb.
			atmo_mat.set_shader_parameter("glow_strength", data.atmosphere_density * 1.2)
	if _clouds != null:
		var cloud_mat := _clouds.material_override as ShaderMaterial
		if cloud_mat != null:
			cloud_mat.set_shader_parameter("cloud_color", data.cloud_color)
			cloud_mat.set_shader_parameter("cloud_density", data.cloud_density)


## Re-displace the body and resize the ring and atmosphere in place. Handles
## everything the terrain, radius and resolution sliders can change.
##
## Returns false if the change needs different [i]nodes[/i] rather than
## different numbers — a ring switched on, an atmosphere faded in from zero, the
## type flipped — in which case the caller should [method configure] instead.
func refresh_geometry() -> bool:
	if data == null or _body == null:
		return false
	if (_ring != null) != data.ring_enabled:
		return false
	if (_atmosphere != null) != (data.atmosphere_density > 0.0):
		return false
	if (_clouds != null) != (data.cloud_density > 0.0):
		return false
	if _body.generate_normals != (not data.is_gas_giant()):
		return false

	_body.radius = data.planet_radius
	_body.resolution = data.sphere_resolution
	_body.terrain_height = data.effective_terrain_height()
	_body.ridge_strength = data.ridge_strength
	_body.sea_level = data.sea_level
	_apply_noise(_body)
	_body.extra_cull_margin = max_radius()

	if _ring != null:
		var inner := data.planet_radius * data.ring_inner_radius
		var outer := data.planet_radius * data.ring_outer_radius
		_ring.mesh = _make_ring_mesh(inner, outer, data.ring_segments, data.ring_radial_segments)
		_ring.extra_cull_margin = outer
	if _atmosphere != null:
		_size_atmosphere()
	if _clouds != null:
		_size_clouds()
	refresh_appearance()
	return true


## Block until the body mesh has surfaces. Generation runs on a worker pool and
## commits its surfaces deferred, so both the threads and the deferred queue
## have to drain before the mesh is readable.
func wait_for_build() -> void:
	if _body == null:
		return
	_body.wait_for_generation()
	if is_inside_tree():
		# One frame for the queued add_surface_from_arrays calls to land, one
		# more so the mesh AABB is up to date for anything framing a camera.
		await get_tree().process_frame
		await get_tree().process_frame


## Furthest a surface vertex can sit from the centre. Both noise layers peak at
## about 1.0 and the ridges stack on top of the continents, so this is the bound
## the atmosphere shell and the cull margin are sized against.
func max_radius() -> float:
	if data == null:
		return 0.0
	var swell := data.effective_terrain_height() * (1.0 + data.ridge_strength)
	return data.planet_radius * (1.0 + swell)


## Radius that contains the whole planet, rings included. What a camera should
## frame against.
func outer_radius() -> float:
	if data == null:
		return 0.0
	var r := maxf(max_radius(), _atmosphere_radius())
	if data.ring_enabled:
		r = maxf(r, data.planet_radius * data.ring_outer_radius)
	return r


# --- Mesh construction ----------------------------------------------------

func _build_body() -> void:
	# Every property is assigned before add_child on purpose. PlanetGenerator
	# regenerates the mesh from each setter, but only once the node is ready, so
	# setting up first collapses what would be eight regenerations into the
	# single one its _ready() kicks off.
	_body = PlanetGenerator.new()
	_body.name = "Body"
	_body.radius = data.planet_radius
	_body.resolution = data.sphere_resolution
	_body.terrain_height = data.effective_terrain_height()
	_body.ridge_strength = data.ridge_strength
	# The generator leaves everything under the waterline on the sphere, so the
	# ocean is round and only continents rise out of it.
	_body.sea_level = data.sea_level
	# Left null deliberately: with no gradient the generator bakes raw elevation
	# into the vertex colours, which is what the surface shader colours from.
	_body.planet_colors = null
	# Displaced normals are what make mountains read as raised. A gas giant has
	# no displacement, so generating them would only cost time.
	_body.generate_normals = not data.is_gas_giant()
	_apply_noise(_body)

	var mat := ShaderMaterial.new()
	mat.shader = load(surface_shader_path) as Shader
	_write_surface_params(mat)
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.extra_cull_margin = max_radius()
	add_child(_body)


func _build_ring() -> void:
	var inner := data.planet_radius * data.ring_inner_radius
	var outer := data.planet_radius * data.ring_outer_radius
	var mesh := _make_ring_mesh(inner, outer, data.ring_segments, data.ring_radial_segments)
	_ring = MeshInstance3D.new()
	_ring.name = "Rings"
	_ring.mesh = mesh

	var mat := ShaderMaterial.new()
	mat.shader = load(RING_SHADER_PATH) as Shader
	mat.set_shader_parameter("ring_color_a", data.ring_color_a)
	mat.set_shader_parameter("ring_color_b", data.ring_color_b)
	mat.set_shader_parameter("dust_density", data.ring_dust_density)
	mat.set_shader_parameter("ring_opacity", data.ring_opacity)
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.extra_cull_margin = outer
	add_child(_ring)


func _build_atmosphere() -> void:
	_atmosphere = MeshInstance3D.new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.mesh = SphereMesh.new()

	var mat := ShaderMaterial.new()
	mat.shader = load(atmosphere_shader_path) as Shader
	mat.set_shader_parameter("glow_color", data.atmosphere_color)
	mat.set_shader_parameter("glow_power", 2.6)
	# A rim glow, not a hazy ball: 1.2× density reads as a clear limb.
	mat.set_shader_parameter("glow_strength", data.atmosphere_density * 1.2)
	_atmosphere.material_override = mat
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_size_atmosphere()
	add_child(_atmosphere)


## Shell radius: clear of the tallest peak, plus the same 6% of the planet the
## glow always had. Sizing it off planet_radius alone let mountains poke through
## the atmosphere on a high-terrain world.
func _atmosphere_radius() -> float:
	return max_radius() + data.planet_radius * 0.06


func _size_atmosphere() -> void:
	var r := _atmosphere_radius()
	var mesh := _atmosphere.mesh as SphereMesh
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 32 * (2 if high_detail else 1)
	mesh.rings = 16 * (2 if high_detail else 1)
	_atmosphere.extra_cull_margin = r


## A translucent cloud shell just above the surface (clear of the tallest peak,
## well inside the atmosphere). The shader draws animated, sun-lit noise, so the
## coverage reads as weather over the terrain rather than a painted band.
func _build_clouds() -> void:
	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.mesh = SphereMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(CLOUD_SHADER_PATH) as Shader
	mat.set_shader_parameter("cloud_color", data.cloud_color)
	mat.set_shader_parameter("cloud_density", data.cloud_density)
	mat.set_shader_parameter("sun_direction", sun_direction.normalized())
	_clouds.material_override = mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_size_clouds()
	add_child(_clouds)


## Just above the highest terrain, but inside the atmosphere shell.
func _cloud_radius() -> float:
	return max_radius() + data.planet_radius * 0.012


func _size_clouds() -> void:
	if _clouds == null:
		return
	var r := _cloud_radius()
	var mesh := _clouds.mesh as SphereMesh
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 40 * (2 if high_detail else 1)
	mesh.rings = 20 * (2 if high_detail else 1)
	_clouds.extra_cull_margin = r


## Axial spin, as a multiplier on [member PlanetData.rotation_speed]. The stored
## values (~0.006 rad/s) are imperceptible as a mesh rotation — a revolution
## every seventeen minutes — so this scales them up to a visible but stately
## spin. The surface shader's own scroll is disabled (see refresh_appearance) so
## the two don't double-count.
const SPIN_MULT := 20.0


## The planet turns on its own axis at [member PlanetData.rotation_speed] ×
## [constant SPIN_MULT]. The moon is a Planet too, so it spins on its axis while
## SpaceScene carries it around Tarn — "things in orbit spin".
func _process(delta: float) -> void:
	# Guarded because a Planet is in the tree between add_child and configure,
	# which is exactly how the editor and the smokes build one. Without this the
	# spin reads a null [member data] every frame a half-built planet exists.
	if data == null:
		return
	rotate_y(data.rotation_speed * SPIN_MULT * delta)


func _teardown() -> void:
	for child: Node in [_body, _ring, _atmosphere, _clouds, _face]:
		if child != null:
			# Removed before freeing so the rebuild can reuse the names. A
			# freed-next-frame node is still a child right now, and add_child
			# would rename the new "Body" around it.
			remove_child(child)
			child.queue_free()
	_body = null
	_ring = null
	_atmosphere = null
	_clouds = null
	_face = null
	_noise_signature = ""


## A face on the globe, same idea as the ones scattered rocks already wear —
## see [member _face]'s doc for why stars never reach this. [method
## configure] calls this on every (re)build, guarded like the rest of that
## pipeline so a bare preview with no data placed yet just has nothing to draw.
func _build_face() -> void:
	if data == null:
		return
	_face = Whimsy.attach_billboard_face(self, data.planet_radius * 0.42, "happy")


## Show [param expression] for a beat, same contract as [method
## FaceSticker.react] — a no-op when whimsy found nowhere to put a face (or
## is off). Called on a weapon hit that didn't finish the planet off.
func react_face(expression: String, hold := 0.8) -> void:
	if _face != null and is_instance_valid(_face):
		_face.react(expression, hold)


## Give the face to the caller instead of letting it go down with this node —
## for planet destruction, which hides the whole planet in the same tick it
## detonates (see [member _face]'s doc on the ship-debris equivalent). Global
## position is preserved so the caller can re-parent it elsewhere and it does
## not visibly jump; returns null when there was never a face to give.
func detach_face() -> Node3D:
	if _face == null or not is_instance_valid(_face):
		return null
	var face := _face
	remove_child(face)
	_face = null
	return face


## Freeze the face on [param expression] for good — the beat right before
## whoever is destroying this planet hides the whole node, same "wear the
## last look" contract ship death uses ([code]_face.freeze("dizzy")[/code] in
## both [method AiShip._destroy] and [method FlightRoot.game_over]).
func freeze_face(expression: String) -> void:
	if _face != null and is_instance_valid(_face):
		_face.freeze(expression)


# --- Terrain --------------------------------------------------------------

## Seeded noise layers, or none at all for a gas giant — it has no solid
## surface, and sampling noise across six 48x48 grids for a mesh that will not
## be displaced is pure cost.
func _apply_noise(gen: PlanetGenerator) -> void:
	# Only the seed and the two frequencies shape the noise; amplitude, radius and
	# resolution are the generator's own properties and change nothing here.
	var signature := "gas" if data.is_gas_giant() else "%d|%f|%f" % [
		data.seed_value, data.continent_scale, data.mountain_scale
	]
	# The second half catches a generator that has just been built and so has no
	# layers yet, whatever the signature says.
	if signature == _noise_signature and (gen.continent_noise == null) == data.is_gas_giant():
		return
	_noise_signature = signature

	if data.is_gas_giant():
		gen.continent_noise = null
		gen.rigdes_noise = null
		return
	# Two draws from one seeded stream, so one seed_value fixes both layers and
	# neighbouring seeds do not produce near-identical worlds.
	var rng := data.seeded_rng()
	var continent_seed := rng.randi()
	var ridge_seed := rng.randi()
	gen.continent_noise = _make_noise(continent_seed, data.continent_scale, false)
	gen.rigdes_noise = _make_noise(ridge_seed, data.continent_scale * data.mountain_scale, true)


## Noise sampled on the unit sphere, so its coordinates span -1..1 on each axis
## and a frequency of 1 means roughly one feature across the planet whatever the
## radius. Ridged fractal for the mountains — that is the fractal type that
## gives creased ranges rather than rolling lumps.
static func _make_noise(noise_seed: int, frequency: float, ridged: bool) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = noise_seed
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4 if ridged else 5
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


func _write_surface_params(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("primary_color", data.primary_color)
	mat.set_shader_parameter("secondary_color", data.secondary_color)
	mat.set_shader_parameter("water_color", data.water_color)
	mat.set_shader_parameter("ice_amount", data.ice_amount)
	mat.set_shader_parameter("planet_type", 0.0 if data.is_gas_giant() else 1.0)
	mat.set_shader_parameter("swirl_speed", data.swirl_speed)
	mat.set_shader_parameter("swirl_scale", data.swirl_scale)
	mat.set_shader_parameter("band_count", data.band_count)
	mat.set_shader_parameter("detail_strength", data.detail_strength)
	# The mesh itself spins on its axis (see _process), so the shader's old fake
	# scroll is disabled — otherwise the surface features would move twice.
	mat.set_shader_parameter("rotation_speed", 0.0)
	mat.set_shader_parameter("sea_level", data.sea_level)
	# Gas giants have no displaced normals to shade, so relief would only add
	# noise to a smooth ball.
	mat.set_shader_parameter("relief", 0.0 if data.is_gas_giant() else 1.0)
	mat.set_shader_parameter("sun_direction", sun_direction.normalized())
	mat.set_shader_parameter("wireframe_mode", 1.0 if StyleManager.instance().is_wireframe() else 0.0)


# --- Accessors ------------------------------------------------------------

func body() -> MeshInstance3D:
	return _body


func ring() -> MeshInstance3D:
	return _ring


func atmosphere() -> MeshInstance3D:
	return _atmosphere


func clouds() -> MeshInstance3D:
	return _clouds


# --- Mesh builders --------------------------------------------------------

## Flat ring annulus. UV.x = radial position (0 at inner, 1 at outer),
## UV.y = angular position (0..1 around the ring). The ring shader reads
## UV.x for its concentric bands and gap.
static func _make_ring_mesh(
	inner_radius: float, outer_radius: float,
	angular_segments: int, radial_segments: int
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var ring_count := radial_segments + 1
	var vert_count := angular_segments * ring_count
	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)

	for seg in angular_segments:
		var angle := TAU * float(seg) / float(angular_segments)
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		for ring_i in ring_count:
			var t := float(ring_i) / float(radial_segments)
			var r := lerpf(inner_radius, outer_radius, t)
			var idx := seg * ring_count + ring_i
			vertices[idx] = Vector3(cos_a * r, 0.0, sin_a * r)
			normals[idx] = Vector3.UP
			uvs[idx] = Vector2(t, float(seg) / float(angular_segments))

	# Triangles.
	var tri_count := angular_segments * radial_segments * 2
	indices.resize(tri_count * 3)
	var ti := 0
	for seg in angular_segments:
		var next_seg := (seg + 1) % angular_segments
		for ring_i in radial_segments:
			var a := seg * ring_count + ring_i
			var b := next_seg * ring_count + ring_i
			indices[ti] = a
			indices[ti + 1] = b
			indices[ti + 2] = a + 1
			indices[ti + 3] = a + 1
			indices[ti + 4] = b
			indices[ti + 5] = b + 1
			ti += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
