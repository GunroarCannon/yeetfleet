## Bakes the level cards' pictures ([PicSet]) from the live game code:
## planets, suns, belts and nebulae as backgrounds; cartoon blasts, ship
## formations, cargo pods, race rings and carriers as transparent subjects;
## and a portrait of every catalogue ship. Rerun it whenever the game's look
## changes and every card in the campaign updates.
##
##     godot --path . --audio-driver Dummy --script modules/menu/tools/picset_bake.gd
##
## Windowed (the headless renderer draws nothing). Writes small lossy WebPs
## into res://assets/picset/ plus manifest.json, then open the editor (or run
## `--headless --editor --quit`) once so they are imported.
extends SceneTree

const OUT := "res://assets/picset"
const BG_SIZE := Vector2i(320, 240)
const FG_SIZE := Vector2i(256, 256)
const SHIP_SIZE := Vector2i(256, 192)
const QUALITY := 0.78

var _manifest := {}
var _sky_env: Environment


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _run() -> void:
	# One baked nebula sky, shared by every background shot.
	_sky_env = MenuProps.environment()
	var host := Node.new()
	root.add_child(host)
	await MenuProps.bake_sky(host, _sky_env, 2048, 11.0)
	# `-- icons` rebakes only the token icons (quick).
	var only_icons := "icons" in OS.get_cmdline_user_args()
	if not only_icons:
		await _backgrounds()
		await _subjects()
		await _ships()
	else:
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/manifest.json"))
	await _icons()
	var f := FileAccess.open(OUT + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_manifest, "\t", true))
	f.close()
	print("[picset] done: ", _manifest)
	quit()


# --- Stage ------------------------------------------------------------------------

## A private little world to photograph: its own viewport, environment,
## lights and camera. [param transparent] shots get no sky and no glow.
func _stage(px: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	if transparent:
		var env := MenuProps.environment(false)
		env.background_mode = Environment.BG_CLEAR_COLOR
		we.environment = env
	else:
		we.environment = _sky_env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe1c2")
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-35, -40, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("7fb2ff")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(15, 150, 0)
	vp.add_child(rim)
	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 45.0
	cam.far = 20000.0
	vp.add_child(cam)
	return vp


func _world(vp: SubViewport) -> Node3D:
	return vp.get_node("World") as Node3D


func _cam(vp: SubViewport) -> Camera3D:
	return vp.get_node("Cam") as Camera3D


func _snap(vp: SubViewport, file: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := OUT + "/" + file + ".webp"
	img.save_webp(path, true, QUALITY)
	print("[picset] ", path)
	vp.queue_free()
	await process_frame


func _count(key: String) -> void:
	_manifest[key] = int(_manifest.get(key, 0)) + 1


# --- Backgrounds ------------------------------------------------------------------

func _backgrounds() -> void:
	var lib := PlanetLibrary.instance()
	var n := 0
	for id in ["tarn_iv", "new_world", "tarn_iv_moon", "ashara", "glacius"]:
		var data := lib.get_data(id)
		if data != null:
			await _planet_shot(data, "bg_planet_%d" % n, Vector3(-0.35, -0.25, 0.0) if n % 2 == 0 else Vector3(0.3, -0.35, 0.0), n % 2 == 1)
			_count("bg_planet")
			n += 1
	# The same worlds again, repainted: a red desert, a violet one, a toxic one.
	var repaint := [[Color("d9623b"), Color("7a2a1c")], [Color("9d6bff"), Color("2f1a66")], [Color("8be04a"), Color("2a5a1c")]]
	for i in repaint.size():
		var d := lib.get_data(["tarn_iv", "new_world", "tarn_iv"][i])
		if d == null:
			break
		d = d.duplicate(true) as PlanetData
		d.primary_color = repaint[i][0]
		d.secondary_color = repaint[i][1]
		await _planet_shot(d, "bg_planet_%d" % n, Vector3(0.3 - i * 0.3, 0.25 - i * 0.2, 0.0), i != 1)
		_count("bg_planet")
		n += 1
	# Gas giants: a planet recoloured, ringed.
	var gas_cols := [[Color("ff7ad0"), Color("7a2fb8")], [Color("4fe3d0"), Color("1d4f8a")],
		[Color("ffb347"), Color("8a3b12")], [Color("b6f0ff"), Color("3a4fb8")]]
	for i in gas_cols.size():
		var g := lib.get_data("tarn_iv")
		if g == null:
			break
		g = g.duplicate(true) as PlanetData
		g.planet_type = PlanetData.PlanetType.GAS_GIANT
		g.primary_color = gas_cols[i][0]
		g.secondary_color = gas_cols[i][1]
		g.ring_enabled = true
		await _planet_shot(g, "bg_gas_%d" % i, Vector3(0.25 if i % 2 == 0 else -0.25, -0.15 + i * 0.1, 0.0), i >= 2)
		_count("bg_gas")
	# Ice: the moon, frosted.
	var ice_cols := [Color("cfeeff"), Color("a9d8ff"), Color("e6d4ff")]
	for i in ice_cols.size():
		var ice := lib.get_data("tarn_iv_moon")
		if ice == null:
			break
		ice = ice.duplicate(true) as PlanetData
		ice.primary_color = ice_cols[i]
		ice.secondary_color = Color("6fa9d6")
		ice.ice_amount = 0.9
		await _planet_shot(ice, "bg_ice_%d" % i, Vector3(-0.3 + i * 0.3, 0.2 - i * 0.15, 0.0), i == 2)
		_count("bg_ice")
	# Suns: a white-hot ball and a real glare ([LensGlare]) — no stacked halo
	# shells (their edges showed as rings) and no hard ray lines. Each its own
	# colour, size, ray count and streak.
	var suns := [
		[Color(2.4, 1.6, 0.6), 0.08, 6, 0.6, 0.35],
		[Color(2.6, 0.9, 0.4), 0.02, 8, 0.4, 0.45],
		[Color(1.2, 1.7, 2.8), 0.6, 4, 0.9, 0.3],
		[Color(2.8, 0.6, 0.9), 0.9, 12, 0.2, 0.5],
		[Color(2.8, 2.4, 1.6), 0.13, 0, 1.0, 0.25],
		[Color(1.6, 2.6, 1.2), 0.3, 16, 0.5, 0.4],
	]
	for i in suns.size():
		var spec: Array = suns[i]
		var vp := _stage(BG_SIZE, false)
		var sun := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 40.0
		sm.height = 80.0
		sun.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = spec[0]
		sun.material_override = mat
		vp.add_child(sun)
		var cam := _cam(vp)
		cam.position = Vector3(40.0 - (i % 3) * 40.0, 20.0 - (i % 2) * 30.0, 150.0 + i * 25.0)
		cam.look_at(Vector3(0, 0, 0))
		_glare(vp, cam.unproject_position(Vector3.ZERO), float(spec[1]), int(spec[2]), float(spec[3]), float(spec[4]))
		await _snap(vp, "bg_sun_%d" % i)
		_count("bg_sun")
	# Belts: a band of rocks across the frame, tinted per belt, some lit
	# by a sun glaring in from the side.
	var rock_cols := [Color(0.42, 0.36, 0.46), Color(0.5, 0.38, 0.3), Color(0.32, 0.4, 0.5), Color(0.45, 0.3, 0.45)]
	for i in rock_cols.size():
		var vp2 := _stage(BG_SIZE, false)
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + i
		for k in 70:
			var rk := MenuProps.rock(rng.randf_range(0.4, 2.6), rng, rock_cols[i])
			rk.position = Vector3(rng.randf_range(-40, 40), rng.randf_range(-6, 6) + rng.randf_range(-1, 1) * 4.0, rng.randf_range(-40, 10))
			vp2.add_child(rk)
		var cam2 := _cam(vp2)
		cam2.position = Vector3(0, 8.0 + (i % 2) * 6.0, 36.0)
		cam2.look_at(Vector3(0, 0, -10))
		cam2.rotate_object_local(Vector3.FORWARD, deg_to_rad(-12.0 + i * 8.0))
		if i >= 2:
			_glare(vp2, Vector2(BG_SIZE) * Vector2(0.85 if i == 2 else 0.15, 0.15), rng.randf(), 6, 0.7, 0.35)
		await _snap(vp2, "bg_belt_%d" % i)
		_count("bg_belt")
	# Nebula: just the sky, from five sides.
	for i in 5:
		var vp3 := _stage(BG_SIZE, false)
		var cam3 := _cam(vp3)
		# Toward the bright gas (up and ahead of -Z, where the sky's core is).
		cam3.fov = 60.0 + i * 6.0
		cam3.rotation_degrees = Vector3(18 + i * 7, -30 + i * 19, (i - 2) * 6.0)
		await _snap(vp3, "bg_nebula_%d" % i)
		_count("bg_nebula")


## A sun's glare over a shot ([LensGlare]), at [param at] pixels, tinted by
## [param hue], with [param rays] rays, a [param streak] and a [param bloom].
func _glare(vp: SubViewport, at: Vector2, hue: float, rays: int, streak: float, bloom: float) -> void:
	var g := LensGlare.new()
	g.size = Vector2(vp.size)
	g.sun = at
	g.tint = Color.from_hsv(hue, 0.5, 1.0)
	g.rays = rays
	g.streak = streak
	g.bloom_size = bloom
	g.ghosts = 3
	vp.add_child(g)


func _planet_shot(data: PlanetData, file: String, frame_off: Vector3, glare := false) -> void:
	var vp := _stage(BG_SIZE, false)
	if glare:
		# A sun just off the planet's shoulder.
		_glare(vp, Vector2(BG_SIZE) * Vector2(0.12 if frame_off.x > 0.0 else 0.88, 0.14), 0.1, 6, 0.6, 0.35)
	var planet := Planet.new()
	vp.add_child(planet)
	planet.configure(data)
	await planet.wait_for_build()
	var r := maxf(planet.outer_radius(), 1.0)
	var cam := _cam(vp)
	# Close, off-centre: a planet filling most of a polaroid, not a dot.
	cam.position = Vector3(0, r * 0.35, r * 2.6) + frame_off * r * 2.0
	cam.look_at(frame_off * r * 1.2)
	await _snap(vp, file)


# --- Subjects ---------------------------------------------------------------------

func _subjects() -> void:
	# Blasts: every palette [CartoonBlast] has, a nuke's mushroom, a wreck
	# blown open inside one, and clusters of small ones. [kind, wreck, extra].
	var booms := [
		["fire", false, 0], ["plasma", false, 0], ["fire", true, 0], ["toxic", false, 2],
		["candy", false, 0], ["nuke", false, 0], ["plasma", true, 3], ["candy", false, 4],
		["toxic", true, 0], ["fire", false, 5],
	]
	for i in booms.size():
		var spec: Array = booms[i]
		var kind := String(spec[0])
		var vp := _stage(FG_SIZE, true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 300 + i
		if bool(spec[1]):
			var views: Array = []
			var s := MenuProps.ship(["bulwark", "mule", "digger"][i % 3], views)
			vp.add_child(s)
			s.scale = Vector3.ONE * (6.0 / MenuProps.radius_of(s))
			s.rotation_degrees = Vector3(15, 40 + i * 30, -20)
			if not views.is_empty():
				MenuProps.break_open(views[0] as ShipView, s, 4, rng)
		if kind == "nuke":
			CartoonBlast.mushroom(_world(vp), Vector3(0, -4, 0), 6.0, Vector3.UP, true)
		else:
			CartoonBlast.build(_world(vp), Vector3(0, -2, 0), 5.0 if bool(spec[1]) else 7.0, Vector3(rng.randf_range(-0.3, 0.3), 1.0, 0.3), rng, rng.randf_range(0.3, 0.6), 1.0, kind)
		for k in int(spec[2]):
			var at := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-0.6, 0.6)).normalized() * rng.randf_range(5.0, 8.0)
			CartoonBlast.build(_world(vp), at, rng.randf_range(1.4, 2.6), at.normalized(), rng, rng.randf_range(0.25, 0.7), 1.0, kind)
		var cam := _cam(vp)
		cam.position = Vector3(7 - (i % 3) * 7, 4 - (i % 2) * 5, 17 + (4 if kind == "nuke" else 0))
		cam.look_at(Vector3(0, 1.5 if kind != "nuke" else 2.5, 0))
		await _snap(vp, "fg_boom_%d" % i)
		_count("fg_boom")
	# Ship formations.
	var crews := [["lance", "stinger", "hotrod"], ["zipper", "kestrel"], ["bulwark", "lance", "lance"],
		["privateer", "zipper", "zipper"], ["hotrod", "kestrel", "stinger", "lance"], ["digger", "mule"]]
	for i in crews.size():
		var vp2 := _stage(FG_SIZE, true)
		var ids: Array = crews[i]
		var crew := Node3D.new()
		_world(vp2).add_child(crew)
		for k in ids.size():
			var sh := MenuProps.ship(String(ids[k]))
			if sh == null:
				continue
			crew.add_child(sh)
			sh.scale = Vector3.ONE * ((4.5 if k == 0 else 3.2) / MenuProps.radius_of(sh))
			sh.position = Vector3(-k * 6.0 + (k % 2) * 12.0 - 3.0, -k * 2.5, -k * 7.0)
			sh.rotation_degrees = Vector3(-8, 150 + i * 20, 12 - k * 8)
		# Framed on the whole crew, however many ships and wherever they sit:
		# from their places and sizes (a hull's mesh bounds include helper
		# meshes far bigger than the ship).
		var c := Vector3.ZERO
		for sh: Node3D in crew.get_children():
			c += sh.position / crew.get_child_count()
		var reach := 4.5
		for sh: Node3D in crew.get_children():
			reach = maxf(reach, sh.position.distance_to(c) + 3.2)
		var cam2 := _cam(vp2)
		# Close in: the crew fills the photo, the far ships may crop at its edge.
		cam2.position = c + Vector3(0.25, 0.3, 1.0).normalized() * reach / sin(deg_to_rad(cam2.fov * 0.5)) * 0.55
		cam2.look_at(c)
		await _snap(vp2, "fg_ships_%d" % i)
		_count("fg_ships")
	# Cargo pods: banded gold canisters tumbling ([CargoPod], as in flight).
	for i in 3:
		var vp3 := _stage(FG_SIZE, true)
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 500 + i
		for k in 4 + i * 2:
			var pod := CargoPod.build(rng2.randf_range(3.4, 4.6))
			pod.position = Vector3(rng2.randf_range(-6, 6), rng2.randf_range(-5, 5), rng2.randf_range(-6, 2))
			pod.rotation = Vector3(rng2.randf() * TAU, rng2.randf() * TAU, 0)
			vp3.add_child(pod)
		var cam3 := _cam(vp3)
		cam3.position = Vector3(0, 0, 13)
		await _snap(vp3, "fg_pods_%d" % i)
		_count("fg_pods")
	# Race rings receding.
	var ring_cols := [[Color(0.4, 0.8, 2.0), Color(2.0, 0.5, 1.2)], [Color(2.0, 1.6, 0.3), Color(0.6, 2.0, 0.6)], [Color(1.4, 0.6, 2.2), Color(0.4, 2.0, 1.8)]]
	for i in ring_cols.size():
		var vp4 := _stage(FG_SIZE, true)
		for k in 5:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 3.4
			tm.outer_radius = 4.0
			ring.mesh = tm
			var rm := StandardMaterial3D.new()
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.albedo_color = ring_cols[i][k % 2]
			ring.material_override = rm
			ring.position = Vector3(sin(k * 0.9 + i) * 5.0, cos(k * 0.7) * 2.0, -k * 12.0)
			ring.rotation_degrees = Vector3(90, 0, 0)
			vp4.add_child(ring)
		var cam4 := _cam(vp4)
		cam4.position = Vector3(2, 1.5, 17)
		cam4.look_at(Vector3(0, 0, -20))
		await _snap(vp4, "fg_rings_%d" % i)
		_count("fg_rings")
	# Carriers: a titan from below with escorts.
	for i in 3:
		var vp5 := _stage(FG_SIZE, true)
		var big := MenuProps.ship("bigboy" if i == 1 else "keel")
		if big != null:
			vp5.add_child(big)
			big.scale = Vector3.ONE * (12.0 / MenuProps.radius_of(big))
			big.rotation_degrees = Vector3(0, 120 + i * 60, 8 - i * 6)
		for k in 2 + i:
			var esc := MenuProps.ship("lance")
			if esc != null:
				vp5.add_child(esc)
				esc.scale = Vector3.ONE * (2.2 / MenuProps.radius_of(esc))
				esc.position = Vector3(-9 + k * 9, -7 + k * 3, 8 - k * 2)
				esc.rotation_degrees = Vector3(0, 160, 0)
		var cam5 := _cam(vp5)
		cam5.position = Vector3(5, -7, 22)
		cam5.look_at(Vector3(0, 0, 0))
		await _snap(vp5, "fg_carrier_%d" % i)
		_count("fg_carrier")


# --- Token icons -----------------------------------------------------------------

## The coin and the stars as little 3D objects, shot on transparent: the UI
## draws these wherever a coin or a star shows ([GraffitiIcons]).
func _icons() -> void:
	var gold := _metal(Color("ffc21a"), 0.35, 0.32)
	# Coin: a thick gold disc, a rim, a raised star on the face, tilted.
	var vp := _stage(Vector2i(128, 128), true)
	var coin := Node3D.new()
	_world(vp).add_child(coin)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.26
	cyl.radial_segments = 40
	disc.mesh = cyl
	disc.material_override = gold
	coin.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 1.04
	tm.rings = 40
	rim.mesh = tm
	rim.material_override = _metal(Color("ffd84a"), 0.4, 0.25)
	coin.add_child(rim)
	var emblem := MeshInstance3D.new()
	emblem.mesh = _star_mesh(0.55, 0.24, 0.12)
	var em := _metal(Color("fff0a0"), 0.3, 0.2)
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	emblem.material_override = em
	emblem.position = Vector3(0, 0.13, 0)
	coin.add_child(emblem)
	# Face up toward the camera, tipped back and turned a little.
	coin.rotation_degrees = Vector3(62, 0, 0)
	coin.rotate_object_local(Vector3.UP, deg_to_rad(18.0))
	_cam(vp).position = Vector3(0, 0, 3.1)
	await _snap(vp, "icon_coin")
	# Stars: glossy gold for earned, dark for not yet, violet for the pilot badge.
	for spec in [["icon_star", Color("ffc61a")], ["icon_star_empty", Color("6b6480")], ["icon_badge", Color("9d6bff")]]:
		var vp2 := _stage(Vector2i(128, 128), true)
		# The earned star keeps the model's own painted texture.
		var mat := _metal(spec[1] as Color, 0.35, 0.22)
		if String(spec[0]) == "icon_star":
			var tex := load("res://assets/star_0.png") as Texture2D
			if tex != null:
				mat = _metal(Color(1.05, 1.0, 0.9), 0.15, 0.35)
				mat.albedo_texture = tex
		var star := _star_model(mat)
		_world(vp2).add_child(star)
		# Face-on to the camera: turn the model's thinnest axis onto Z,
		# whichever way it was authored (the current one lies flat on Y).
		var raw := _bounds(star)
		if raw.size.y < raw.size.z and raw.size.y < raw.size.x:
			star.rotation_degrees.x = 90.0
		elif raw.size.x < raw.size.z and raw.size.x < raw.size.y:
			star.rotation_degrees.y = 90.0
		var turned := Node3D.new()
		_world(vp2).add_child(turned)
		star.reparent(turned)
		star = turned
		# Stand it upright: roll the point furthest from the middle to 12
		# o'clock (the model is authored at whatever angle it came in).
		var tip := _tip_dir(star)
		if tip != Vector2.ZERO:
			var upright := Node3D.new()
			_world(vp2).add_child(upright)
			star.reparent(upright)
			# Y is up here, so a +Z roll turns the tip counter-clockwise.
			upright.rotation.z = tip.angle_to(Vector2(0.0, 1.0))
			star = upright
		# Framed on its own bounds, whatever size the model was authored at.
		var box := _bounds(star)
		var fit := 1.9 / maxf(maxf(box.size.x, box.size.y), 0.001)
		star.scale = Vector3.ONE * fit
		star.position = -box.get_center() * fit
		var pivot := Node3D.new()
		_world(vp2).add_child(pivot)
		star.reparent(pivot)
		# A little turn for depth, but no roll: ranking stars stand up straight.
		pivot.rotation_degrees = Vector3(-10, 16, 0)
		_cam(vp2).position = Vector3(0, 0, 3.0)
		await _snap(vp2, String(spec[0]))


## The star model the icons are made from (assets/star.glb, "Star Shape" by
## Suphanee, with its texture assets/star_0.png), every mesh in it wearing
## [param mat]. Falls back to a built
## star prism if the file is missing.
func _star_model(mat: Material) -> Node3D:
	var packed := load("res://assets/star.glb") as PackedScene
	var node: Node3D = packed.instantiate() as Node3D if packed != null else null
	if node == null:
		var mi := MeshInstance3D.new()
		mi.mesh = _star_mesh(1.0, 0.45, 0.34)
		mi.rotation_degrees = Vector3(80, 0, 0)
		node = mi
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).material_override = mat
		stack.append_array(n.get_children())
	return node


## The XY direction (Y up) from the middle of [param root]'s meshes to the
## vertex furthest from it — a star's tip — in [param root]'s space.
func _tip_dir(root: Node3D) -> Vector2:
	var box := _bounds(root)
	var mid := Vector2(box.get_center().x, box.get_center().y)
	var best := Vector2.ZERO
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var xf := root.global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					var p := xf * v
					var d := Vector2(p.x, p.y) - mid
					if d.length_squared() > best.length_squared():
						best = d
		stack.append_array(n.get_children())
	return best


## The combined bounds of every mesh under [param root], in its space.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var xf := root.global_transform.affine_inverse() * (n as MeshInstance3D).global_transform
			var b := xf * (n as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	return box


func _metal(col: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.4
	return m


## A star prism: [param points] 5, lying in the XZ plane, [param depth]
## thick, with a pointed top so light catches its facets.
func _star_mesh(outer: float, inner: float, depth: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector3] = []
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		var r := outer if i % 2 == 0 else inner
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var top := Vector3(0, depth, 0)
	var bottom := Vector3(0, -depth * 0.35, 0)
	for i in 10:
		var p := ring[i]
		var q := ring[(i + 1) % 10]
		# Faceted top (a low pyramid) and a flat-ish back.
		st.add_vertex(top)
		st.add_vertex(q)
		st.add_vertex(p)
		st.add_vertex(bottom)
		st.add_vertex(p)
		st.add_vertex(q)
	st.generate_normals()
	return st.commit()


# --- Ship portraits ---------------------------------------------------------------

func _ships() -> void:
	for id in ShipCatalog.ids():
		var vp := _stage(SHIP_SIZE, true)
		var s := MenuProps.ship(id)
		if s == null:
			vp.queue_free()
			continue
		vp.add_child(s)
		s.scale = Vector3.ONE * (5.0 / MenuProps.radius_of(s))
		s.rotation_degrees = Vector3(0, 145, 0)
		var cam := _cam(vp)
		cam.position = Vector3(0, 3.2, 8.2)
		cam.look_at(Vector3(0, 0, 0))
		await _snap(vp, "ship_" + id)
