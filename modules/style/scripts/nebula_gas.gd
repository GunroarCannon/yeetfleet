## Layered, procedurally-shaded gas-cloud billboards — real volumetric-looking
## nebula wisps, plus (see [method build_streaks]) the same crossed
## colour-wash streaks [SpaceScene]'s sky uses. No image assets: [constant
## SHADER_PATH] renders a soft radial+fbm-noise alpha mask per quad (see
## modules/style/assets/nebula_gas.gdshader), consistent with this project's
## shader-driven, asset-free visual style (ship_part.gdshader,
## outline.gdshader).
##
## [method build] returns a plain [Node3D] holding several big, jittered,
## billboarded quads grouped into clusters — cheap (one draw call per quad, no
## particle system) and good enough at the distance a backdrop is always
## viewed from. Layer [method build_streaks] alongside it for a backdrop that
## reads as depth (blobby wisps) plus the linear "glare" the puffs alone don't
## give — puffs by themselves read as flat, uniform patches.
class_name NebulaGas
extends RefCounted

const SHADER_PATH := "res://modules/style/assets/nebula_gas.gdshader"


## Builds [param cluster_count] gas clusters of [param puffs_per_cluster] quads
## each, scattered just inside a sphere of [param radius], seeded from
## [param seed] so the same seed always proposes the same nebula. Higher
## [param cluster_count]/[param puffs_per_cluster] is the HD path — see
## [SolarSystemGenLabRoot]'s high-res toggle.
static func build(seed: int, radius: float, cluster_count: int = 3, puffs_per_cluster: int = 5) -> Node3D:
	var shader := load(SHADER_PATH) as Shader
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var root := Node3D.new()
	root.name = "NebulaGas"
	for c in cluster_count:
		var palette := Palette.nebula_wash(c)
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.4), rng.randf_range(-1.0, 1.0)
		)
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var centre := dir * radius * rng.randf_range(0.7, 0.95)
		for p in puffs_per_cluster:
			var offset := Vector3(
				rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
			) * radius * 0.16
			var quad := _make_quad(shader, palette, rng, radius)
			quad.position = centre + offset
			root.add_child(quad)
	return root


static func _make_quad(shader: Shader, palette: Dictionary, rng: RandomNumberGenerator, radius: float) -> MeshInstance3D:
	var size := radius * rng.randf_range(0.32, 0.7)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("core_color", palette["core"])
	mat.set_shader_parameter("edge_color", palette["edge"])
	mat.set_shader_parameter("density", rng.randf_range(0.5, 1.0))
	mat.set_shader_parameter("noise_scale", rng.randf_range(2.0, 5.0))
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 100.0))
	mat.set_shader_parameter("rotation", rng.randf_range(0.0, TAU))
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = size
	return inst


## Three crossed, softly wobbling colour-wash streaks — the same per-vertex
## [SurfaceTool] technique [SpaceScene] uses for its sky (`_add_nebula_ribbon`),
## extracted here so any nebula backdrop can layer this "glare lines" wash
## under/over [method build]'s blobby puffs rather than reading as puffs alone.
## Tilts, colours and wobble are all drawn from [param seed], so a caller that
## reseeds gets a genuinely different streak pattern, not the same three lines
## in different puff colours.
static func build_streaks(seed: int, radius: float, detail: int = 1) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 747
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var palette := Palette.nebula_wash(i + rng.randi_range(0, Palette.NEBULA_WASHES - 1))
		var edge: Color = (palette["edge"] as Color)
		edge.a = 0.0
		var core: Color = (palette["core"] as Color)
		core.a = rng.randf_range(0.12, 0.22)
		var tilt := Basis(
			Vector3(rng.randf_range(-1.0, 1.0), 0.15, rng.randf_range(-1.0, 1.0)).normalized(),
			rng.randf_range(0.0, TAU)
		)
		_add_streak(st, radius, tilt, edge, core, 64 * detail, rng.randf_range(0.0, TAU))
	var inst := MeshInstance3D.new()
	inst.name = "NebulaStreaks"
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -11
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = radius
	return inst


## Symmetric fade — transparent at both edges, peaking at the centreline —
## rather than a one-sided ramp: a ribbon that goes straight from nothing to
## fully saturated has a hard mesh-boundary line on its bright side, which
## reads as a glass panel rather than a wash of gas.
static func _add_streak(
	st: SurfaceTool, radius: float, tilt: Basis, edge_color: Color, core_color: Color,
	segments: int, wobble_seed: float
) -> void:
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		# A third of the frame, not a stripe. The second sine makes the width
		# wobble, so the edge isn't a smooth circle.
		var width := 0.32 + 0.12 * sin(a0 * 3.0 + wobble_seed) + 0.06 * sin(a0 * 7.0 + wobble_seed)
		var lo0 := tilt * _band_point(a0, -width, radius)
		var mid0 := tilt * _band_point(a0, 0.0, radius)
		var hi0 := tilt * _band_point(a0, width, radius)
		var lo1 := tilt * _band_point(a1, -width, radius)
		var mid1 := tilt * _band_point(a1, 0.0, radius)
		var hi1 := tilt * _band_point(a1, width, radius)
		_tri(st, lo0, edge_color, lo1, edge_color, mid1, core_color)
		_tri(st, lo0, edge_color, mid1, core_color, mid0, core_color)
		_tri(st, mid0, core_color, mid1, core_color, hi1, edge_color)
		_tri(st, mid0, core_color, hi1, edge_color, hi0, edge_color)


static func _tri(
	st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color
) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


static func _band_point(angle: float, height: float, radius: float) -> Vector3:
	return Vector3(cos(angle), height, sin(angle)).normalized() * (radius * 0.98)
