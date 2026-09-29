## MenuStage: the 3D world behind the front end.
##
## Home: a battle frozen at its loudest frame — a hull blown open inside a
## ground-explosion blast, bits of it tumbling off, the ships that did it and
## their laser bolts hanging in the air — in front of a planet and the nebula,
## while the camera drifts slowly round it all.
##
## Garage: a hex landing pad lit by neon, far off to one side of the same
## world, with the ship being looked at turning slowly on it. The UI switches
## between the two with [method set_mode] (behind a wipe, so the camera never
## visibly jumps).
class_name MenuStage
extends Node3D

enum Mode { HOME, GARAGE }

## Degrees per second the home camera drifts round the wreck.
const ORBIT_SPEED := 2.4
const ORBIT_RADIUS := 34.0
const ORBIT_HEIGHT := 7.0
## Where the garage pad is: far enough that nothing from home is in shot.
const PAD_AT := Vector3(4000.0, 0.0, 0.0)
## Every garage ship is scaled to this radius, so a titan and a scout both
## fill the frame.
const PAD_SHIP_RADIUS := 9.5
const TURNTABLE_SPEED := 0.35

## The home camera's path: waypoints it swoops between and settles on, in
## order, looping. Each is {yaw, dist, height, fov, roll, secs} round the
## wreck — yaw in degrees (kept increasing so the loop never unwinds), roll a
## Dutch tilt, secs how long the swoop *into* it takes.
const HOME_SHOTS: Array[Dictionary] = [
	{"yaw": 200.0, "dist": 40.0, "height": 8.0, "fov": 55.0, "roll": 0.0, "secs": 7.0},
	{"yaw": 250.0, "dist": 21.0, "height": -4.0, "fov": 48.0, "roll": 11.0, "secs": 6.0},
	{"yaw": 318.0, "dist": 31.0, "height": 22.0, "fov": 60.0, "roll": -6.0, "secs": 6.5},
	{"yaw": 382.0, "dist": 23.0, "height": 5.0, "fov": 74.0, "roll": -13.0, "secs": 5.0},
	{"yaw": 450.0, "dist": 58.0, "height": 13.0, "fov": 50.0, "roll": 3.0, "secs": 7.0},
	{"yaw": 512.0, "dist": 26.0, "height": -12.0, "fov": 58.0, "roll": 8.0, "secs": 6.0},
]
## The garage's: low hero angles round the pad.
const PAD_SHOTS: Array[Dictionary] = [
	{"yaw": -60.0, "dist": 30.0, "height": 10.0, "fov": 50.0, "roll": 0.0, "secs": 6.0},
	{"yaw": -20.0, "dist": 24.0, "height": 3.0, "fov": 56.0, "roll": 6.0, "secs": 6.0},
	{"yaw": 30.0, "dist": 28.0, "height": 16.0, "fov": 48.0, "roll": -4.0, "secs": 6.5},
	{"yaw": 80.0, "dist": 22.0, "height": 1.5, "fov": 62.0, "roll": -7.0, "secs": 6.0},
	{"yaw": 150.0, "dist": 32.0, "height": 8.0, "fov": 50.0, "roll": 3.0, "secs": 7.0},
]
## A new ship on the pad: the camera punches in and whips round, then eases
## back out onto its path.
const PAD_KICK_TIME := 0.9

var mode: int = Mode.HOME
var camera: Camera3D
var env: Environment

## Progress along the current shot list: whole part = waypoint index,
## fraction = how far through the swoop into the next one.
var _path_t := 0.0
## 1 → 0 after a ship change on the pad (see [constant PAD_KICK_TIME]).
var _kick := 0.0
var _pad_ship: Node3D = null
var _pad_ship_id := ""
var _time := 0.0
## Frozen props that bob a hair so the paused frame still feels alive.
var _bobbers: Array[Node3D] = []
## Where the camera leans the subject: the home frame keeps the wreck left
## of the buttons (landscape) or above them (portrait).
var _portrait := false


func _ready() -> void:
	env = MenuProps.environment()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	MenuProps.bake_sky(self, env, 1024 if OS.has_feature("mobile") else 2048)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe1c2")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, -40, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("7fb2ff")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(20, 140, 0)
	add_child(rim)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.far = 20000.0
	add_child(camera)
	camera.make_current()
	_build_home()
	_build_pad()
	_place_camera(0.0)


func set_mode(m: int) -> void:
	if m != mode:
		_path_t = 0.0
	mode = m
	_place_camera(0.0)


## The frame follows the window's shape; the UI calls this on resize.
func set_portrait(on: bool) -> void:
	_portrait = on
	_place_camera(0.0)


func _process(delta: float) -> void:
	_time += delta
	_place_camera(delta)
	for i in _bobbers.size():
		var b := _bobbers[i]
		if is_instance_valid(b):
			b.position.y = float(b.get_meta("y0", 0.0)) + sin(_time * 0.6 + i * 1.7) * 0.25
	if _pad_ship != null and is_instance_valid(_pad_ship):
		_pad_ship.rotation.y += TURNTABLE_SPEED * delta


func _place_camera(delta: float) -> void:
	if camera == null:
		return
	var home := mode == Mode.HOME
	var shots := HOME_SHOTS if home else PAD_SHOTS
	var centre := Vector3(0, 1.0, 0) if home else PAD_AT + Vector3(0, 4.0, 0)
	var pose: Dictionary
	if Juice.reduce_motion():
		# Shake less: a calm orbit, no swoops or tilts.
		_path_t += delta * 0.02
		pose = shots[0].duplicate()
		pose["yaw"] = float(pose["yaw"]) + _path_t * 360.0
	else:
		var i := int(_path_t) % shots.size()
		var into := float(shots[(i + 1) % shots.size()]["secs"])
		_path_t += delta / into
		pose = _pose_on(shots, _path_t)
	_kick = move_toward(_kick, 0.0, delta / PAD_KICK_TIME)
	var k := ease(_kick, 2.0)
	var dist := float(pose["dist"]) * (1.0 - 0.28 * k) * (1.3 if _portrait else 1.0)
	var yaw := deg_to_rad(float(pose["yaw"]) + 45.0 * k)
	# Handheld drift: slow, small, never a snap.
	var drift := Vector3(sin(_time * 0.37), sin(_time * 0.29 + 1.0), 0.0) * 0.35
	camera.position = centre + Vector3(cos(yaw) * dist, float(pose["height"]), sin(yaw) * dist) + drift
	camera.look_at(centre, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(float(pose["roll"])))
	camera.fov = float(pose["fov"]) + 6.0 * k
	# Shift the frame so the subject sits clear of the UI: left of the buttons
	# or the stats panel in landscape, above them in portrait. Scaled with
	# distance, so a close shot is not shoved off screen.
	var lean := dist / 34.0
	camera.h_offset = 0.0 if _portrait else (7.5 if home else 8.0) * lean
	camera.v_offset = ((-6.0 if home else -9.0) * lean) if _portrait else (0.0 if home else -1.0)


## The camera pose at [param t] along [param shots]: a Catmull-Rom spline
## through the waypoints (smooth, no corners), with the time eased inside each
## swoop so the camera leaves a waypoint gently, sweeps, and settles into the
## next — "chill until it is done being dynamic".
func _pose_on(shots: Array[Dictionary], t: float) -> Dictionary:
	var i := int(floor(t))
	var f := smoothstep(0.0, 1.0, t - i)
	var out := {}
	for key in ["yaw", "dist", "height", "fov", "roll"]:
		var p0 := _shot_val(shots, i - 1, key)
		var p1 := _shot_val(shots, i, key)
		var p2 := _shot_val(shots, i + 1, key)
		var p3 := _shot_val(shots, i + 2, key)
		out[key] = _catmull(p0, p1, p2, p3, f)
	return out


## A waypoint's value, with yaw unwrapped across loops so it only ever grows.
func _shot_val(shots: Array[Dictionary], i: int, key: String) -> float:
	var n := shots.size()
	var v := float(shots[posmod(i, n)][key])
	if key == "yaw":
		# Whole turns per lap, so waypoint yaws keep their meaning.
		var lap := 360.0 * ceilf((float(shots[n - 1]["yaw"]) - float(shots[0]["yaw"]) + 30.0) / 360.0)
		v += floor(float(i) / n) * lap
	return v


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# --- Home: the frozen fight ------------------------------------------------------

func _build_home() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LevelGen.seed_of("menu/home")
	# The planet, big and far behind.
	var pdata := PlanetLibrary.instance().get_data("tarn_iv")
	if pdata != null:
		var planet := Planet.new()
		planet.name = "Planet"
		add_child(planet)
		planet.configure(pdata)
		var pr := maxf(planet.max_radius(), 1.0)
		planet.scale = Vector3.ONE * (260.0 / pr)
		planet.position = Vector3(-420.0, -140.0, -620.0)
	# The victim: blown open at the heart of the blast.
	var views: Array = []
	var victim := _ship_at("bulwark", Vector3(0, 0, 0), 7.0, views)
	if victim != null:
		victim.rotation_degrees = Vector3(18, 35, -24)
		if not views.is_empty():
			MenuProps.break_open(views[0] as ShipView, victim, 5, rng)
	# The blast itself: bursting up out of the hull, and a smaller secondary
	# pop off one end.
	# A different kind of bang each visit: fire, plasma, toxic, candy, or a
	# nuke's mushroom cloud standing over the wreck.
	var styles := ["fire", "plasma", "toxic", "candy", "nuke"]
	var style: String = styles[randi() % styles.size()]
	if style == "nuke":
		CartoonBlast.mushroom(self, Vector3(0.5, -1.0, 0.3), 7.0, Vector3.UP, true)
		CartoonBlast.build(self, Vector3(-6.5, 1.0, 3.0), 2.6, Vector3(-1.0, 0.4, 0.5), rng, 0.45, 1.0, "fire")
	else:
		CartoonBlast.build(self, Vector3(0.5, 2.5, 0.3), 6.0, Vector3(0.25, 1.0, 0.35), rng, 0.45, 1.0, style)
		CartoonBlast.build(self, Vector3(-6.5, 1.0, 3.0), 2.6, Vector3(-1.0, 0.4, 0.5), rng, 0.45, 1.0, style)
	# The ships that did it, round the wreck.
	var crew := [
		["lance", Vector3(16, 4, 9), Vector3(0, 125, 20), 4.5],
		["stinger", Vector3(-15, 7, 12), Vector3(-10, 230, -30), 4.0],
		["zipper", Vector3(-6, -5, -18), Vector3(8, 330, 15), 3.6],
		["keel", Vector3(30, -8, -34), Vector3(0, 250, 0), 13.0],
		["hotrod", Vector3(12, 9, -14), Vector3(-15, 20, 35), 4.2],
	]
	for c in crew:
		var s := _ship_at(String(c[0]), c[1], float(c[3]), [])
		if s != null:
			s.rotation_degrees = c[2]
			s.set_meta("y0", s.position.y)
			_bobbers.append(s)
			# A bolt hanging in the air in front of each gun ship.
			if String(c[0]) != "keel":
				_bolt(s)
	# Rocks and shrapnel caught mid-flight.
	for i in 18:
		var rk := MenuProps.rock(rng.randf_range(0.2, 0.9), rng, Color(0.3, 0.26, 0.34))
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		rk.position = dir * rng.randf_range(10.0, 30.0)
		add_child(rk)
	for i in 40:
		var far := MenuProps.rock(rng.randf_range(1.5, 5.0), rng, Color(0.36, 0.3, 0.42))
		var ang := rng.randf() * TAU
		far.position = Vector3(cos(ang) * rng.randf_range(90, 220), rng.randf_range(-40, 30), sin(ang) * rng.randf_range(90, 220))
		add_child(far)


## A catalogue ship at [param pos], scaled to [param radius].
func _ship_at(id: String, pos: Vector3, radius: float, views: Array) -> Node3D:
	var s := MenuProps.ship(id, views)
	if s == null:
		return null
	add_child(s)
	s.scale = Vector3.ONE * (radius / MenuProps.radius_of(s))
	s.position = pos
	return s


## A glowing laser bolt a little ahead of [param ship]'s nose, frozen.
func _bolt(ship: Node3D) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.12
	mesh.height = 3.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.2, 0.6, 1.4)
	mesh.material = mat
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		var fwd := -ship.global_transform.basis.z.normalized()
		mi.global_position = ship.global_position + fwd * (6.0 + i * 5.0) + ship.global_transform.basis.x.normalized() * (0.8 if i == 0 else -0.8)
		mi.look_at(mi.global_position + fwd, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)


# --- Garage: the pad --------------------------------------------------------------

func _build_pad() -> void:
	var pad := MeshInstance3D.new()
	var hex := CylinderMesh.new()
	hex.top_radius = 13.0
	hex.bottom_radius = 13.5
	hex.height = 1.2
	hex.radial_segments = 6
	pad.mesh = hex
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("1d1a28")
	metal.metallic = 0.3
	metal.roughness = 0.7
	pad.material_override = metal
	pad.position = PAD_AT
	add_child(pad)
	# Hazard ring: yellow and ink segments round the rim.
	for i in 24:
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.1, 0.2, 0.9)
		seg.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = GraffitiStyle.SUN if i % 2 == 0 else GraffitiStyle.INK
		m.emission_enabled = i % 2 == 0
		m.emission = GraffitiStyle.SUN * 0.4
		seg.material_override = m
		var a := TAU * i / 24.0
		seg.position = PAD_AT + Vector3(cos(a) * 11.4, 0.66, sin(a) * 11.4)
		seg.rotation.y = -a + PI * 0.5
		add_child(seg)
	# Neon rings above the pad, cyan and hot pink.
	for ring in [[GraffitiStyle.CYAN, 14.5, 0.8], [GraffitiStyle.HOT, 16.0, 2.2]]:
		var t := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = float(ring[1]) - 0.18
		torus.outer_radius = float(ring[1])
		torus.rings = 48
		t.mesh = torus
		var nm := StandardMaterial3D.new()
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nm.albedo_color = (ring[0] as Color) * 2.4
		t.material_override = nm
		t.position = PAD_AT + Vector3(0, float(ring[2]), 0)
		add_child(t)
	for spot in [[Vector3(-14, 22, 10), GraffitiStyle.CYAN], [Vector3(14, 22, -10), GraffitiStyle.HOT], [Vector3(0, 26, 18), Color("fff1dc")]]:
		var l := SpotLight3D.new()
		l.light_color = spot[1]
		l.light_energy = 4.0
		l.spot_range = 60.0
		l.spot_angle = 32.0
		add_child(l)
		l.global_position = PAD_AT + (spot[0] as Vector3)
		l.look_at(PAD_AT + Vector3(0, 3, 0), Vector3.UP)


## Put catalogue ship [param id] on the pad; [param locked] shows it as a
## dark silhouette.
func show_pad_ship(id: String, locked: bool) -> void:
	if id == _pad_ship_id and _pad_ship != null and is_instance_valid(_pad_ship):
		MenuProps.silhouette(_pad_ship, locked)
		return
	var spin := 0.6
	# A new ship: punch in on it.
	_kick = 1.0
	if _pad_ship != null and is_instance_valid(_pad_ship):
		spin = _pad_ship.rotation.y
		_pad_ship.queue_free()
	_pad_ship = MenuProps.ship(id)
	_pad_ship_id = id
	if _pad_ship == null:
		return
	add_child(_pad_ship)
	_pad_ship.scale = Vector3.ONE * (PAD_SHIP_RADIUS / MenuProps.radius_of(_pad_ship))
	_pad_ship.position = PAD_AT + Vector3(0, 4.5, 0)
	_pad_ship.rotation.y = spin
	MenuProps.silhouette(_pad_ship, locked)
	# A little drop-in: land from above.
	_pad_ship.position.y += 4.0
	create_tween().tween_property(_pad_ship, "position:y", PAD_AT.y + 4.5, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
