## ArtScene: builds a frozen fight for store art — the Play Store feature
## graphic, the app icon, or any screenshot-sized scene — from a dictionary
## of settings ([constant DEFAULTS]). The [ArtStudio] edits the settings live;
## `launch/tools/banner_gen.gd` builds with them from the command line.
##
## A scene: a baked nebula sky, a wreck blown open inside a sculpted blast
## ([CartoonBlast]: fire, plasma, toxic, candy, or a nuke's mushroom), smaller
## blasts round it, a ring of fighters with bolts in the air, big ships
## behind, rocks caught mid-flight, a planet and the sun (with its
## [LensGlare]), and — on top — the sprayed YEETFLEET title or the icon's
## mark. Every "random" setting is drawn from [code]seed[/code], so one seed
## gives the same picture again.
extends RefCounted

const SHIPS: Array[String] = ["lance", "stinger", "zipper", "hotrod", "kestrel", "privateer", "digger", "mule"]
const BIG: Array[String] = ["keel", "bigboy"]
const VICTIMS: Array[String] = ["bulwark", "mule", "digger", "privateer"]
const BLASTS: Array[String] = ["fire", "plasma", "toxic", "candy", "nuke"]
const PLANETS: Array[String] = ["tarn_iv", "ashara", "glacius", "new_world"]
const SIZES := {
	"feature": Vector2i(1024, 500),
	"icon": Vector2i(512, 512),
	"landscape": Vector2i(1920, 1080),
	"portrait": Vector2i(1080, 1920),
	"tablet": Vector2i(2560, 1600),
}

## Every setting. "random" (or -1 for a choice) means: let the seed pick.
const DEFAULTS := {
	"mode": "feature",
	"seed": 1,
	"sky_seed": -1.0,
	# The wreck and the bang.
	"victim": true,
	"victim_ship": "random",
	"victim_parts": 5,
	"blast": "random",
	"blast_size": 6.0,
	"small_blasts": 4,
	"small_blast_kind": "mixed",
	"addon_booms": 6,
	"addon_nuke": "random",
	# Ships and scenery.
	"fighters": 5,
	"fighter_ring": 16.0,
	"bolts": true,
	"big_ships": 1,
	"rocks": 22,
	# Sky bodies.
	"planet": true,
	"planet_id": "random",
	"planet_size": 0.3,
	"planet_left": "random",
	"sun": true,
	"sun_y": 0.5,
	"glare": 1.0,
	"glare_rays": 6,
	"glare_ray_length": 0.32,
	"glare_streak": 0.6,
	"glare_ghosts": 4,
	"glare_bloom": 0.55,
	"glare_hue": 0.1,
	"key_light": 2.3,
	# Camera: -1 = the seed's pick.
	"cam_yaw": -1.0,
	"cam_height": -100.0,
	"cam_distance": -1.0,
	"cam_fov": -1.0,
	"cam_roll": -100.0,
	"cam_lift": -100.0,
	# Words on top.
	"title": true,
	"title_text": "YEETFLEET",
	"title_tilt": 0.0,
	"title_drips": 0.8,
	"title_size": 400,
	"title_y": 0.03,
	"icon_mark": "Y",
}


## The settings with [param over] on top of [constant DEFAULTS].
static func settings(over: Dictionary = {}) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(over, true)
	return p


static func size_of(p: Dictionary) -> Vector2i:
	return SIZES.get(str(p["mode"]), SIZES["feature"])


## Build the 3D fight under [param world] for a view [param view] pixels big.
## Returns {camera, sun_screen (Vector2, or INF with no sun)}.
static func build(world: Node3D, view: Vector2, p: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var icon := str(p["mode"]) == "icon"
	var env := MenuProps.environment()
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sky := float(p["sky_seed"])
	MenuProps.bake_sky(world, env, 2048, sky if sky >= 0.0 else rng.randf_range(1.0, 50.0))
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe1c2")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, rng.randf_range(-70, -10), 0)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("7fb2ff")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(20, 140, 0)
	world.add_child(rim)
	# The wreck and the bang.
	if bool(p["victim"]):
		var views: Array = []
		var vid := _pick(p["victim_ship"], VICTIMS, rng)
		var victim := _ship(world, vid, Vector3.ZERO, 7.0, views)
		if victim != null:
			victim.rotation_degrees = Vector3(rng.randf_range(-25, 25), rng.randf_range(0, 360), rng.randf_range(-30, 30))
			if not views.is_empty() and int(p["victim_parts"]) > 0:
				MenuProps.break_open(views[0] as ShipView, victim, int(p["victim_parts"]), rng)
	var kind := _pick(p["blast"], BLASTS, rng)
	var bs := float(p["blast_size"])
	if kind == "nuke":
		CartoonBlast.mushroom(world, Vector3(0.5, -1.0, 0.3), bs * 1.15, Vector3.UP, true)
	elif kind != "none":
		CartoonBlast.build(world, Vector3(0.5, 2.5, 0.3), bs, Vector3(rng.randf_range(-0.4, 0.4), 1.0, 0.35), rng, rng.randf_range(0.3, 0.6), 1.0, kind)
	for i in int(p["small_blasts"]):
		var at := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(6.0, 14.0)
		var sk := str(p["small_blast_kind"])
		if sk == "mixed":
			sk = BLASTS[rng.randi() % 4]
		CartoonBlast.build(world, at, rng.randf_range(1.2, 2.8), at.normalized(), rng, rng.randf_range(0.25, 0.7), 1.0, sk)
	# The crew: fighters in a loose ring, big ships behind.
	var n := int(p["fighters"])
	for i in n:
		var ang := TAU * i / maxf(n, 1) + rng.randf_range(-0.3, 0.3)
		var d := float(p["fighter_ring"]) * rng.randf_range(0.8, 1.25)
		var pos := Vector3(cos(ang) * d, rng.randf_range(-6, 9), sin(ang) * d)
		var s := _ship(world, SHIPS[rng.randi() % SHIPS.size()], pos, rng.randf_range(3.6, 4.8), [])
		if s != null:
			s.look_at(Vector3.ZERO, Vector3.UP)
			s.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.6, 0.6))
			if bool(p["bolts"]):
				_bolt(world, s, rng)
	for i in int(p["big_ships"]):
		_ship(world, BIG[rng.randi() % BIG.size()], Vector3(rng.randf_range(20, 34) * (1 if i % 2 == 0 else -1), -8 + i * 6, -34 - i * 10), 13.0, [])
	for i in int(p["rocks"]):
		var rk := MenuProps.rock(rng.randf_range(0.2, 0.9), rng, Color(0.3, 0.26, 0.34))
		rk.position = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(10.0, 30.0)
		world.add_child(rk)
	# The camera round the wreck; the fight sits a little low under a title.
	var cam := Camera3D.new()
	cam.far = 20000.0
	var fov := float(p["cam_fov"])
	cam.fov = fov if fov > 0.0 else rng.randf_range(50.0, 62.0)
	world.add_child(cam)
	cam.make_current()
	var yaw := deg_to_rad(float(p["cam_yaw"])) if float(p["cam_yaw"]) >= 0.0 else rng.randf_range(0.0, TAU)
	var dist := float(p["cam_distance"])
	if dist <= 0.0:
		dist = rng.randf_range(24.0, 28.0) if icon else rng.randf_range(30.0, 38.0)
	var height := float(p["cam_height"])
	if height <= -100.0:
		height = rng.randf_range(-4.0, 14.0)
	cam.position = Vector3(cos(yaw) * dist, height, sin(yaw) * dist)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	var roll := float(p["cam_roll"])
	cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(roll if roll > -100.0 else rng.randf_range(-9.0, 9.0)))
	var lift := float(p["cam_lift"])
	cam.v_offset = lift if lift > -100.0 else (5.0 if bool(p["title"]) and not icon else 0.0)
	var sun_screen := _sky_bodies(world, cam, key, view, p, rng)
	return {"camera": cam, "sun_screen": sun_screen}


## The 2D layer on top, under [param parent] (a Control-capable node in the
## same viewport): the glare, then the title or the icon's mark.
static func overlay(parent: Node, view: Vector2, p: Dictionary, sun_screen: Vector2) -> void:
	if sun_screen != Vector2.INF and float(p["glare"]) > 0.0:
		var g := LensGlare.new()
		g.sun = sun_screen
		g.size = view
		g.strength = float(p["glare"])
		g.rays = int(p["glare_rays"])
		g.ray_length = float(p["glare_ray_length"])
		g.streak = float(p["glare_streak"])
		g.ghosts = int(p["glare_ghosts"])
		g.bloom_size = float(p["glare_bloom"])
		g.tint = Color.from_hsv(float(p["glare_hue"]), 0.45, 1.0)
		parent.add_child(g)
	if not bool(p["title"]):
		return
	var t := GraffitiTitle.new()
	if str(p["mode"]) == "icon":
		t.text = str(p["icon_mark"])
		t.max_size = int(view.y * 0.6)
		t.position = Vector2(-view.x * 0.06, view.y * 0.2)
		t.size = Vector2(view.x, view.y * 0.92)
		t.rotation = deg_to_rad(-6.0 + float(p["title_tilt"]))
	else:
		t.text = str(p["title_text"])
		t.drips = float(p["title_drips"])
		t.max_size = int(p["title_size"])
		t.position = Vector2(view.x * 0.03, view.y * float(p["title_y"]))
		t.size = Vector2(view.x * 0.94, view.y * 0.47)
		t.rotation = deg_to_rad(GraffitiTitle.TILT + float(p["title_tilt"]))
	parent.add_child(t)


## The addon explosions, set off a beat apart so the picture catches each at
## a different stage. Awaitable: [param tree] times the beats.
static func booms(tree: SceneTree, world: Node3D, p: Dictionary) -> void:
	var count := int(p["addon_booms"])
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"]) + 7
	FxSettings.ensure_loaded()
	FxSettings.addon_vfx = true
	var kinds := [AddonVfx.Kind.EXPLOSION_AIR, AddonVfx.Kind.EXPLOSION_GROUND, AddonVfx.Kind.BIG_IMPACT, AddonVfx.Kind.EXPLOSION_AIR]
	var nuke: Variant = p["addon_nuke"]
	if (nuke is bool and nuke) or (str(nuke) == "random" and rng.randf() < 0.5):
		AddonVfx.spawn(world, AddonVfx.Kind.NUKE, Vector3(rng.randf_range(-14, 14), -6, rng.randf_range(-14, -6)), Vector3.UP, rng.randf_range(2.0, 3.0), Color.TRANSPARENT, true)
		await _beat(tree, 0.12)
	AddonVfx.spawn(world, AddonVfx.Kind.EXPLOSION_AIR, Vector3(0.5, 1.5, 0.3), Vector3.UP, rng.randf_range(4.5, 6.0), Color.TRANSPARENT, true)
	var left := count - 1
	while left > 0:
		await _beat(tree, rng.randf_range(0.08, 0.16))
		for i in mini(rng.randi_range(2, 3), left):
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.9), rng.randf_range(-1, 1)).normalized()
			AddonVfx.spawn(world, kinds[rng.randi() % kinds.size()], dir * rng.randf_range(5.0, 15.0), dir, rng.randf_range(2.0, 4.5), Color.TRANSPARENT, true)
			left -= 1
	await _beat(tree, 0.22)


static func _beat(tree: SceneTree, sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await tree.process_frame


## The planet (in shot, low on one side) and the sun (in frame, on the other,
## lighting the hulls from its side). Returns the sun's screen position, or
## INF with no sun.
static func _sky_bodies(world: Node3D, cam: Camera3D, key: DirectionalLight3D, view: Vector2, p: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var icon := str(p["mode"]) == "icon"
	var lf: Variant = p["planet_left"]
	var left := rng.randf() < 0.5 if str(lf) == "random" else bool(lf)
	var side := -1.0 if left else 1.0
	if bool(p["planet"]):
		var pdata := PlanetLibrary.instance().get_data(_pick(p["planet_id"], PLANETS, rng))
		if pdata == null:
			pdata = PlanetLibrary.instance().get_data("tarn_iv")
		if pdata != null:
			var planet := Planet.new()
			world.add_child(planet)
			planet.configure(pdata)
			var far := 900.0
			planet.scale = Vector3.ONE * (far * float(p["planet_size"]) / maxf(planet.max_radius(), 1.0))
			var px := view * Vector2(0.14 if side < 0.0 else 0.86, 0.78 if icon else 0.72)
			planet.global_position = cam.project_position(px, far)
	if not bool(p["sun"]):
		return Vector2.INF
	var sx := view * Vector2(0.84 if side < 0.0 else 0.16, 0.14 if icon else float(p["sun_y"]))
	var sun_dir := cam.project_ray_normal(sx)
	key.look_at_from_position(cam.global_position + sun_dir * 100.0, cam.global_position, cam.global_basis.y)
	key.light_color = Color("fff0d0")
	key.light_energy = float(p["key_light"])
	key.light_specular = 1.6
	var sun := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 40.0
	m.height = 80.0
	sun.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(4.0, 3.4, 2.4)
	sun.material_override = mat
	world.add_child(sun)
	sun.global_position = cam.global_position + sun_dir * 3000.0
	cam.far = maxf(cam.far, 6000.0)
	return sx


## [param choice] from [param from], or the seed's pick when it is "random".
static func _pick(choice: Variant, from: Array, rng: RandomNumberGenerator) -> String:
	var c := str(choice)
	return from[rng.randi() % from.size()] if c == "random" or c == "" else c


static func _ship(world: Node3D, id: String, pos: Vector3, radius: float, views: Array) -> Node3D:
	var s := MenuProps.ship(id, views)
	if s == null:
		return null
	world.add_child(s)
	s.scale = Vector3.ONE * (radius / MenuProps.radius_of(s))
	s.position = pos
	return s


## A bolt hanging in the air in front of a gun ship.
static func _bolt(world: Node3D, ship: Node3D, rng: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.18
	m.height = 2.4
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.0, 1.4, 0.4) if rng.randf() < 0.5 else Color(0.6, 1.6, 2.2)
	mi.material_override = mat
	world.add_child(mi)
	var fwd := -ship.global_basis.z
	mi.global_position = ship.global_position + fwd * 5.0
	mi.look_at(mi.global_position + fwd, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
