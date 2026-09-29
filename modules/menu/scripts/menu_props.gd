## MenuProps: the 3D set dressing the front end is built from — catalogue
## ships as real hulls, an explosion frozen mid-blast, a hull broken open,
## space rocks, a baked nebula sky and a lit environment.
##
## Shared by the home screen's stage ([MenuStage]) and the picture baker
## (tools/picset_bake.gd), so a level card's picture and the home screen are
## made of the same pieces and a visual update reaches both.
class_name MenuProps
extends RefCounted

const GROUND_BLAST := "res://addons/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"
const AIR_BLAST := "res://addons/BinbunVFX_Vol2/ExplosionFX/effects/air/vfx_air_explosion_01.tscn"
const NEBULA_SHADER := "res://modules/common/juice/shaders/nebula_panorama.gdshader"


## A catalogue ship ([ShipCatalog] id) as a node: the preset hull in its
## paint, centred on its own bounds. Returns null when the id or hull is
## unknown. [param out_view] (optional, an empty Array) receives the
## [ShipView] for callers that want its parts.
static func ship(id: String, out_view: Array = []) -> Node3D:
	var row := ShipCatalog.get_ship(id)
	if row.is_empty():
		return null
	return hull(String(row["preset"]), String(row["paint"]), out_view)


## A preset hull in a faction paint, re-centred so its middle sits on the
## node's origin (a turntable spins round the middle, not the cockpit).
static func hull(preset: String, paint: String, out_view: Array = []) -> Node3D:
	var lib := PartLibrary.instance()
	var design := lib.build_preset_design(preset)
	if design == null:
		return null
	if paint != "":
		lib.apply_faction(design, paint)
	var view := ShipAssembler.assemble(design, lib, 0.0, false, false)
	if view == null or view.root == null:
		return null
	var holder := Node3D.new()
	holder.name = "Ship_" + preset
	holder.add_child(view.root)
	view.root.position = -view.aabb.get_center()
	holder.set_meta("radius", maxf(view.aabb.size.length() * 0.5, 1.0))
	out_view.append(view)
	return holder


## The radius a [method ship] / [method hull] node was sized to.
static func radius_of(node: Node3D) -> float:
	return float(node.get_meta("radius", 5.0)) if node != null else 5.0


## An explosion scene started and then frozen [param at] seconds in — a
## paused frame of the blast. [param crawl] > 0 lets it run on that slowly
## instead, but its particles then burn out after a few minutes on screen,
## so the home screen holds it at a true pause.
static func frozen_blast(parent: Node3D, path: String, pos: Vector3, scale: float, at := 0.42, crawl := 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	# The Binbun effects' controller plays its "main" animation from
	# _enter_tree when autoplay is set — the same way [AddonVfx] starts them.
	node.set("one_shot", true)
	node.set("autoplay", true)
	node.scale = Vector3.ONE * scale
	parent.add_child(node)
	node.global_position = pos
	for c in _all(node):
		if c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).volume_db = -80.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(at, true, false, true).timeout.connect(_freeze.bind(node, crawl))
	return node


## A cartoon explosion frozen [param age] of the way in (see [CartoonBlast],
## which the flight scene also plays for kills).
static func cartoon_blast(parent: Node3D, pos: Vector3, radius: float, dir: Vector3, rng: RandomNumberGenerator, age := 0.45) -> Node3D:
	return CartoonBlast.build(parent, pos, radius, dir, rng, age)


static func _freeze(node: Node3D, crawl: float) -> void:
	if not is_instance_valid(node):
		return
	if "speed_scale" in node:
		node.set("speed_scale", crawl)
	for c in _all(node):
		if c is GPUParticles3D:
			(c as GPUParticles3D).speed_scale = crawl
		elif c is CPUParticles3D:
			(c as CPUParticles3D).speed_scale = crawl
		elif c is AnimationPlayer:
			(c as AnimationPlayer).speed_scale = crawl


## Break a hull open: [param count] of its parts flung outward and tumbled,
## frozen mid-flight like the rest of the scene. Works on the [ShipView]
## [method ship] handed back.
static func break_open(view: ShipView, holder: Node3D, count: int, rng: RandomNumberGenerator) -> void:
	if view == null:
		return
	var paths: Array = view.part_nodes.keys()
	paths.sort()
	var flung := 0
	var reach := radius_of(holder)
	for path in paths:
		if flung >= count:
			break
		var part := view.part_nodes[path] as Node3D
		# The root part is the hull everything hangs off; keep it.
		if part == null or String(path).count("/") == 0:
			continue
		if rng.randf() < 0.45:
			continue
		var xf := part.global_transform
		part.get_parent().remove_child(part)
		holder.add_child(part)
		part.global_transform = xf
		var out := (xf.origin - holder.global_position)
		if out.length() < 0.1:
			out = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1))
		part.global_position += out.normalized() * reach * rng.randf_range(0.5, 1.1)
		part.rotate_object_local(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf_range(0.6, 2.2))
		flung += 1


## A lumpy space rock: one of a few cached low-poly shapes, scaled and
## turned, sharing one material per colour — dozens of rocks cost a handful
## of meshes, not one each.
static func rock(radius: float, rng: RandomNumberGenerator, color := Color(0.46, 0.4, 0.5)) -> MeshInstance3D:
	if _rock_meshes.is_empty():
		var shape_rng := RandomNumberGenerator.new()
		shape_rng.seed = 4242
		for k in ROCK_SHAPES:
			_rock_meshes.append(_rock_mesh(shape_rng))
	var mat: StandardMaterial3D = _rock_mats.get(color, null)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.95
		_rock_mats[color] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_meshes[rng.randi_range(0, ROCK_SHAPES - 1)]
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * radius
	mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	return mi


const ROCK_SHAPES := 6
static var _rock_meshes: Array[Mesh] = []
static var _rock_mats := {}


static func _rock_mesh(rng: RandomNumberGenerator) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	for i in verts.size():
		verts[i] = verts[i] * (1.0 + noise.get_noise_3dv(verts[i]) * 0.45)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	return st.commit()


## A lit environment for a front-end set: dark violet ambient, glow, filmic.
static func environment(glow := true) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0716")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("4a3a78")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = glow
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	return env


## Bake the nebula panorama into [param env]'s sky, the way the flight sky
## does (render the shader once into a SubViewport, then show the image), at
## [param width] pixels. Awaitable; leaves the flat colour when rendering is
## unavailable (headless).
static func bake_sky(host: Node, env: Environment, width := 2048, sky_seed := 7.0) -> void:
	var shader := load(NEBULA_SHADER) as Shader
	if shader == null or DisplayServer.get_name() == "headless":
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(width, width / 2)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("bg_color", Vector3(0.03, 0.02, 0.07))
	mat.set_shader_parameter("neb_a", Vector3(0.55, 0.16, 0.62))
	mat.set_shader_parameter("neb_b", Vector3(0.1, 0.38, 0.78))
	mat.set_shader_parameter("neb_c", Vector3(1.0, 0.4, 0.3))
	mat.set_shader_parameter("seed", sky_seed)
	mat.set_shader_parameter("res_scale", float(width) / 4096.0)
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = ImageTexture.create_from_image(img)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY


## A dark silhouette over every mesh under [param node]: locked ships in the
## garage are shown as a shape, not a paint job. Pass false to lift it.
static func silhouette(node: Node, on: bool) -> void:
	var mat: StandardMaterial3D = null
	if on:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("1c1530")
	for c in _all(node):
		if c is GeometryInstance3D:
			var g := c as GeometryInstance3D
			# Hulls paint through material_override too: keep the paint aside.
			if on and not g.has_meta("paint"):
				g.set_meta("paint", g.material_override)
			if on:
				g.material_override = mat
			elif g.has_meta("paint"):
				g.material_override = g.get_meta("paint") as Material


static func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
