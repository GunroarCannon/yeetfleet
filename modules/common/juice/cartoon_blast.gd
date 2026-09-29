## CartoonBlast: a toy explosion sculpted from puffs — a white-hot core,
## orange and red billows bursting out along a direction, dark smoke on the
## rim, a shock ring, spark streaks and flying bits.
##
## Why it exists: the BinbunVFX addon blasts are GPU particles, and under the
## Compatibility renderer (this project's) they draw nothing on some GPUs —
## the game's own `whimsy_shot boom` view shows an empty frame. A kill then
## looked like confetti and emotes popping out of nowhere. These are plain
## meshes, so they render everywhere.
##
## Two uses. [method build] poses a frozen frame [param age] of the way in
## (the menu's home scene and its level pictures). [method spawn] plays it:
## pops in, billows out, then each puff shrinks away — on game time, so a
## kill-freeze holds the blast on screen mid-bang instead of hiding it.
## Materials are shared across every blast, so many at once batch cheaply.
class_name CartoonBlast
extends Node3D

## Seconds the played version lives.
const LIFE := 1.15
## Inside out: [count, distance along dir, spread, size, colour, glow].
const LAYERS := [
	[5, 0.05, 0.12, 0.28, Color(1.0, 0.98, 0.85), 3.2],
	[9, 0.22, 0.3, 0.26, Color(1.0, 0.82, 0.25), 2.0],
	[12, 0.42, 0.42, 0.24, Color(1.0, 0.5, 0.12), 1.1],
	[10, 0.62, 0.5, 0.22, Color(0.9, 0.24, 0.1), 0.35],
	[9, 0.82, 0.55, 0.2, Color(0.28, 0.22, 0.3), 0.0],
]

## Colour sets, inside out (core, hot, fire, rim, smoke) — the same shape
## reads as a different kind of bang.
const PALETTES := {
	"fire": [Color(1.0, 0.98, 0.85), Color(1.0, 0.82, 0.25), Color(1.0, 0.5, 0.12), Color(0.9, 0.24, 0.1), Color(0.28, 0.22, 0.3)],
	"plasma": [Color(0.9, 1.0, 1.0), Color(0.45, 0.9, 1.0), Color(0.3, 0.5, 1.0), Color(0.55, 0.25, 0.95), Color(0.2, 0.15, 0.35)],
	"toxic": [Color(0.95, 1.0, 0.8), Color(0.75, 1.0, 0.25), Color(0.35, 0.9, 0.2), Color(0.1, 0.55, 0.3), Color(0.18, 0.26, 0.2)],
	"candy": [Color(1.0, 0.95, 1.0), Color(1.0, 0.6, 0.85), Color(1.0, 0.35, 0.6), Color(0.65, 0.3, 0.95), Color(0.3, 0.2, 0.35)],
}

static var _sphere: SphereMesh = null
static var _streak: BoxMesh = null
static var _bit: BoxMesh = null
static var _mats := {}

var _animated := false
var _palette: Array = PALETTES["fire"]
## Mushroom clouds run on the wall clock (see [method mushroom]).
var _real := false
var _life := LIFE
var _t := 0.0
var _puffs: Array[Node3D] = []
var _puff_scale: Array[Vector3] = []
var _light: OmniLight3D = null


## A frozen blast, posed [param age] (0..1) of the way in: at 0 a tight
## white-hot ball; further in the core shrinks, the billows spread and break
## apart, smoke takes the rim, the rings grow and the bits fly further out.
static func build(parent: Node3D, pos: Vector3, radius: float, dir: Vector3, rng: RandomNumberGenerator, age := 0.45, detail := 1.0, palette := "fire") -> CartoonBlast:
	var b := CartoonBlast.new()
	b.name = "CartoonBlast"
	b._palette = PALETTES.get(palette, PALETTES["fire"])
	parent.add_child(b)
	b.global_position = pos
	b._sculpt(radius, dir, rng, clampf(age, 0.0, 1.0), detail)
	return b


## A blast that plays out and frees itself — for kills and big hits.
## [param detail] thins the puff count (phones, or many blasts at once).
static func spawn(parent: Node, pos: Vector3, radius: float, dir := Vector3.UP, detail := 0.7) -> CartoonBlast:
	var host := parent as Node3D
	if host == null or not host.is_inside_tree():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := dir + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.4, 0.4))
	var b := build(host, pos, radius, d, rng, 0.25, detail)
	b._animated = true
	b.scale = Vector3.ONE * 0.35
	return b


## A nuke's mushroom cloud standing along [param up]: a glowing stem, a
## billowing cap, a skirt of dust round the foot and a wide shock ring. It
## punches up, rises, hangs, then puffs away — on real time, so it plays out
## while the game is frozen on it (a planet kill's pause).
static func mushroom(parent: Node, pos: Vector3, radius: float, up := Vector3.UP, frozen := false) -> CartoonBlast:
	var host := parent as Node3D
	if host == null or not host.is_inside_tree():
		return null
	var b := CartoonBlast.new()
	b.name = "Mushroom"
	host.add_child(b)
	b.global_position = pos
	b._sculpt_mushroom(radius, up.normalized())
	# Frozen: a paused frame at full height (the menu's home scene).
	if frozen:
		return b
	b._animated = true
	b._real = true
	b._life = 4.2
	b.scale = Vector3.ONE * 0.2
	return b


func _sculpt_mushroom(radius: float, up: Vector3) -> void:
	_sculpt(radius * 0.01, up, RandomNumberGenerator.new(), 0.0, 0.0)
	for p in _puffs:
		p.queue_free()
	_puffs.clear()
	_puff_scale.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := up.cross(side).normalized()
	var hot := _mat(Color(1.0, 0.82, 0.3), 2.2)
	var fire := _mat(Color(1.0, 0.5, 0.12), 1.1)
	var red := _mat(Color(0.9, 0.26, 0.1), 0.35)
	var smoke := _mat(Color(0.3, 0.24, 0.32), 0.0)
	# [height, ring radius, count, puff size, material]
	var rings := [
		[0.0, 0.75, 14, 0.2, smoke], [0.05, 0.45, 10, 0.22, red],
		[0.3, 0.1, 4, 0.2, hot], [0.55, 0.1, 4, 0.19, hot], [0.8, 0.12, 5, 0.2, fire], [1.0, 0.16, 6, 0.22, fire],
		[1.2, 0.5, 14, 0.3, fire], [1.32, 0.34, 10, 0.3, red], [1.45, 0.62, 16, 0.26, smoke], [1.52, 0.15, 5, 0.32, red],
	]
	for rg in rings:
		for i in int(rg[2]):
			var a := TAU * i / float(rg[2]) + rng.randf() * 0.4
			var mi := MeshInstance3D.new()
			mi.mesh = _sphere
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.material_override = rg[4]
			var off := up * float(rg[0]) + (side * cos(a) + side2 * sin(a)) * float(rg[1]) * rng.randf_range(0.85, 1.1)
			mi.position = off * radius
			var s := float(rg[3]) * rng.randf_range(0.8, 1.2) * radius
			mi.scale = Vector3.ONE * s
			add_child(mi)
			_puffs.append(mi)
			_puff_scale.append(mi.scale)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 1.35
	torus.outer_radius = radius * 1.5
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _mat(Color(1.0, 0.75, 0.45, 0.6), 1.6, true)
	add_child(ring)
	ring.look_at(global_position + up, side)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_puffs.append(ring)
	_puff_scale.append(ring.scale)
	_light.omni_range = radius * 4.0
	_light.light_energy = 12.0


func _sculpt(radius: float, dir: Vector3, rng: RandomNumberGenerator, a: float, detail: float) -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
		_streak = BoxMesh.new()
		_streak.size = Vector3(0.05, 0.05, 1.0)
		_bit = BoxMesh.new()
		_bit.size = Vector3.ONE
	var up := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := up.cross(side).normalized()
	var grow := 1.0 + a * 0.7
	# Age thins the hot core and fattens the smoke.
	var size_k := [1.0 - a * 0.55, 1.0 - a * 0.3, 1.0, 1.0 + a * 0.2, 1.0 + a * 0.5]
	for li in LAYERS.size():
		var layer: Array = LAYERS[li]
		var mat := _mat(_palette[li] as Color, float(layer[5]))
		var count := int(layer[0]) + (int(a * 10.0) if li == LAYERS.size() - 1 else 0)
		count = maxi(2, int(round(count * detail)))
		for i in count:
			var mi := MeshInstance3D.new()
			mi.mesh = _sphere
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var along := (float(layer[1]) + rng.randf_range(-0.06, 0.08)) * grow
			var ang := rng.randf() * TAU
			# Further in, the billows break apart: more scatter, wider spread.
			var spread := float(layer[2]) * rng.randf_range(0.5, 1.0) * (1.0 + a * 0.55)
			var off := up * along + (side * cos(ang) + side2 * sin(ang)) * spread
			off += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * a * 0.12
			mi.position = off * radius
			var s := float(layer[3]) * float(size_k[li]) * rng.randf_range(0.7, 1.25) * radius
			mi.scale = Vector3(s, s * rng.randf_range(0.8, 1.15), s)
			mi.material_override = mat
			add_child(mi)
			_puffs.append(mi)
			_puff_scale.append(mi.scale)
	# The shock ring round the base, and a fainter second one.
	for k in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * (0.72 + k * 0.35) * grow
		torus.outer_radius = radius * (0.78 + k * 0.35) * grow
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = _mat(Color(1.0, 0.75, 0.45, 0.8 - k * 0.35), 1.6, true)
		add_child(ring)
		ring.look_at(global_position + up, side)
		ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		ring.position = up * radius * 0.08
		_puffs.append(ring)
		_puff_scale.append(ring.scale)
	# Spark streaks shooting out, and dark bits tumbling away.
	var spark := _mat(Color(1.0, 0.9, 0.5), 3.0)
	var soot := _mat(Color(0.18, 0.15, 0.2), 0.0)
	for i in int(16 * detail):
		var d := (up * rng.randf_range(0.2, 1.0) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
		var st := MeshInstance3D.new()
		st.mesh = _streak
		st.material_override = spark
		add_child(st)
		st.position = d * radius * rng.randf_range(0.9, 1.6) * grow
		st.scale = Vector3.ONE * radius * rng.randf_range(0.25, 0.5)
		st.look_at(global_position + d * radius * 3.0, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		_puffs.append(st)
		_puff_scale.append(st.scale)
	for i in int(10 * detail):
		var bit := MeshInstance3D.new()
		bit.mesh = _bit
		bit.material_override = soot
		var d2 := (up * 0.6 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1))).normalized()
		bit.position = d2 * radius * rng.randf_range(1.0, 1.8) * grow
		bit.scale = Vector3.ONE * radius * rng.randf_range(0.04, 0.09)
		bit.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		add_child(bit)
		_puffs.append(bit)
		_puff_scale.append(bit.scale)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = 8.0
	_light.omni_range = radius * 5.0
	_light.position = up * radius * 0.3
	add_child(_light)


func _process(delta: float) -> void:
	if not _animated:
		return
	# Game time: a hitstop or kill-freeze holds the blast where it is. A
	# mushroom uses the wall clock instead.
	_t += minf(delta / maxf(Engine.time_scale, 0.001), 0.1) if _real else delta
	var k := _t / _life
	if k < 0.12:
		scale = Vector3.ONE * lerpf(0.35, 1.0, ease(k / 0.12, 0.35))
	else:
		scale = Vector3.ONE * lerpf(1.0, 1.35, (k - 0.12) / 0.88)
	# The last third: each puff shrinks away, staggered, cartoon-style.
	if k > 0.62:
		var n := _puffs.size()
		for i in n:
			var start := 0.62 + 0.25 * float(i % 7) / 7.0
			var f := clampf((k - start) / 0.14, 0.0, 1.0)
			_puffs[i].scale = _puff_scale[i] * (1.0 - ease(f, 2.0))
	if _light != null:
		_light.light_energy = 8.0 * (1.0 - clampf(k, 0.0, 1.0))
	if k >= 1.0:
		queue_free()


## One shared material per look: glowing puffs are unshaded and over 1.0 so
## the bloom catches them; the outer ones are toon-lit so they read as volume.
static func _mat(col: Color, glow: float, transparent := false) -> StandardMaterial3D:
	var key := "%s/%.2f/%s" % [col.to_html(), glow, transparent]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if glow >= 1.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(col.r * glow, col.g * glow, col.b * glow, col.a)
	else:
		m.albedo_color = col
		m.roughness = 1.0
		m.emission_enabled = glow > 0.0
		m.emission = col * glow
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m
