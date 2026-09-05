## Makes fitted systems actually do something.
##
## The GDD asks for parts that work, not parts that only add numbers, so this node
## reads the functional markers the assembler hoisted into ship space and drives
## them: exhausts light up and grow with the throttle, guns fire real projectiles
## from their muzzles at their own rates, the capacitor drains and recharges, and
## heat builds until the radiators catch up. It is deliberately a *test* rig rather
## than a game loop — nothing moves the ship — but every number it uses comes from
## the same [ShipPart.func_data] and [ShipStats] the flight module will read, so a
## gun that feels wrong here will feel wrong there.
class_name SystemsSim
extends Node3D

## Capacitor and heat changed; the readout redraws.
signal state_changed(energy_fraction: float, heat_fraction: float, notes: String)

## Fired when a shot could not be taken, so the UI can explain why once rather
## than spamming.
signal fire_blocked(reason: String)

## Seconds a projectile lives if its part does not say.
const DEFAULT_SHOT_LIFE := 1.5
## Cap on live projectiles. A 20-weapon capital ship at 8 rounds a second would
## otherwise bury a phone.
const MAX_PROJECTILES := 220
## Heat added per unit of energy spent. Firing is the main heat source in a
## builder with no engines actually pushing anything.
const HEAT_PER_ENERGY := 1.7
## Heat added per second at full throttle, per unit of thrust.
const HEAT_PER_THRUST := 0.012

const PLUME_SHADER_PATH := "res://modules/common/juice/shaders/plume.gdshader"
const TRACER_SHADER_PATH := "res://modules/common/juice/shaders/tracer.gdshader"

## Boost spool time, seconds — the plume stretches and whitens over this window
## rather than snapping, so the throttle has a sound-shaped visual even with no
## sound yet. See `juice-and-more.md` §3.3.
const BOOST_SPOOL := 0.12
## How much longer the plume gets at full boost, eased over [constant
## BOOST_SPOOL]. See [member _plume_eased] for why this used to compound into a
## runaway feedback loop that eventually pushed the plume through the chase
## camera — now fixed, this can safely be the plan's intended figure.
const BOOST_STRETCH := 1.6
## Seconds between ember-trickle bursts while boosting, per exhaust.
const BOOST_SPARK_INTERVAL := 0.12
## How often the largest nozzle refreshes its [FxLight] pop. Longer than a
## single frame on purpose: [FxLight] round-robins a four-light budget shared
## with muzzle flashes and impacts, and refreshing every frame would mean the
## engine claims a new slot sixty times a second and never lets a gunshot keep
## one. Shorter than the pop's own decay, so the light never visibly gaps.
const ENGINE_LIGHT_INTERVAL := 0.1

var throttle := 0.0
var firing := false
var running := true
var boosting := false

var energy := 0.0
var heat := 0.0
var _boost_level := 0.0

## Projectiles spawned since the current design was bound. Monotonic, so a
## readout can tell "fired once" apart from "never fired" — which a snapshot of
## the in-flight list cannot, since tracers expire.
var shots_fired := 0

var _view: ShipView
var _root: Node
var _stats: ShipStats

## Per-muzzle cooldown timers, parallel to [member ShipView.muzzles].
var _cooldowns: PackedFloat32Array = PackedFloat32Array()
## Stable per-muzzle shot colour (see [method _build_muzzle_colors]).
var _muzzle_colors: Array[Color] = []
## The ship's current target, for guided shots to home on. Set externally: the
## player's ship from FlightRoot's lock-on, an AI ship from its current enemy.
var target_ref: Node3D = null
## How fast guided shots accelerate toward their target, m/s².
const GUIDED_ACCEL := 700.0
## Live projectiles: {node, velocity, life, beam}.
var _shots: Array[Dictionary] = []
## Plume meshes, parallel to [member ShipView.exhausts].
var _plumes: Array[MeshInstance3D] = []
var _plume_bases: PackedFloat32Array = PackedFloat32Array()
var _plume_mats: Array[ShaderMaterial] = []
var _plume_halos: Array[MeshInstance3D] = []
var _plume_colors: Array[Color] = []
var _plume_was_lit: Array[bool] = []
var _plume_spark_timer: PackedFloat32Array = PackedFloat32Array()
## The throttle-spool ease, kept separately from [member Node3D.scale] because
## reading a node's own already-boost-stretched scale back as next frame's
## starting point compounds the stretch every frame — an exponential feedback
## loop that was the actual cause of a boost plume eventually swallowing the
## camera. This array is always the clean, unstretched value.
var _plume_eased: PackedFloat32Array = PackedFloat32Array()
var _largest_plume_index := -1
var _engine_light_timer := 0.0

var _fx_root: Node3D
var _shot_root: Node3D
var _shot_mesh: ArrayMesh
var _tracer_shader: Shader
var _last_note := ""

## Summed and clamped shake per frame — see [method _spawn_shot] — so a
## twenty-gun broadside is emphatic rather than unusable.
const SHOT_SHAKE := 0.08
const SHOT_KICK := 0.45


func _ready() -> void:
	_fx_root = Node3D.new()
	_fx_root.name = "Plumes"
	add_child(_fx_root)
	_shot_root = Node3D.new()
	_shot_root.name = "Shots"
	# Projectiles live in world space, not ship space: a shot leaves the gun and
	# stops caring where the ship goes. Harmless in the builder, where this node
	# sits at the origin anyway, and essential in flight, where it does not.
	_shot_root.top_level = true
	add_child(_shot_root)
	# One shared mesh for every projectile: a stubby tracer that reads at speed.
	_shot_mesh = _make_tracer_mesh()
	_tracer_shader = load(TRACER_SHADER_PATH) as Shader


func bind(view: ShipView, root: Node) -> void:
	_view = view
	_root = root
	_stats = view.resolution.stats
	_clear_shots()
	_rebuild_plumes()
	_cooldowns.resize(view.muzzles.size())
	_cooldowns.fill(0.0)
	_build_muzzle_colors()
	# Refill on rebuild: the capacitor is a property of the design, and a design
	# that just gained a reactor should not start empty.
	energy = _capacity()
	heat = 0.0
	shots_fired = 0
	_emit_state()


## A distinct, stable colour per muzzle so a design's guns read as red / green /
## blue lasers rather than all one default cyan. Parts that declare their own
## shot_color keep it; the rest draw from a small palette by muzzle index.
func _build_muzzle_colors() -> void:
	_muzzle_colors.resize(_view.muzzles.size())
	var palette: Array[Color] = [
		Color("ff4b4b"),  # red
		Color("4bff6a"),  # green
		Color("4b8dff"),  # blue
		Color("8ef0ff"),  # cyan
		Color("ffb24b"),  # amber
		Color("ff4bd8"),  # magenta
	]
	for i in _view.muzzles.size():
		var entry := _view.muzzles[i]
		var func_data: Dictionary = entry.get("func", {})
		var declared := String(func_data.get("shot_color", ""))
		if declared != "" and declared != "8ef0ff":
			_muzzle_colors[i] = Color.from_string(declared, palette[i % palette.size()])
		else:
			_muzzle_colors[i] = palette[i % palette.size()]


func _capacity() -> float:
	return maxf(_stats.get_stat("energy_capacity"), 1.0) if _stats != null else 1.0


func _heat_ceiling() -> float:
	# Dissipation doubles as the thermal envelope: a ship that sheds 100 units a
	# second can hold about a hundred before it is in trouble.
	return maxf(_stats.get_stat("heat_dissipation"), 1.0) if _stats != null else 1.0


# --- Plumes ----------------------------------------------------------------

func _rebuild_plumes() -> void:
	for p in _plumes:
		p.queue_free()
	_plumes.clear()
	_plume_bases.clear()
	_plume_mats.clear()
	_plume_halos.clear()
	_plume_colors.clear()
	_plume_was_lit.clear()
	_plume_spark_timer.clear()
	_plume_eased.clear()
	_largest_plume_index = -1
	if _view == null:
		return
	var shader := load(PLUME_SHADER_PATH) as Shader
	var largest_radius := -1.0
	for entry in _view.exhausts:
		var radius := float(entry.get("radius", 0.3))
		if radius > largest_radius:
			largest_radius = radius
			_largest_plume_index = _plumes.size()
		var func_data: Dictionary = entry.get("func", {})
		var plume_scale := float(func_data.get("plume", 1.0))
		var color := Color.from_string(String(func_data.get("exhaust_color", "6fd8ff")), ShipMaterials.COL_BEAM)

		var inst := MeshInstance3D.new()
		inst.name = "Plume"
		inst.mesh = _make_plume_mesh(radius, radius * 4.2 * plume_scale)
		var mat := ShaderMaterial.new()
		if shader != null:
			mat.shader = shader
		mat.set_shader_parameter("core_color", Color(1.0, 0.95, 0.85))
		mat.set_shader_parameter("exhaust_color", color)
		mat.set_shader_parameter("throttle", 0.0)
		mat.set_shader_parameter("boost", 0.0)
		mat.set_shader_parameter("time_offset", randf() * 20.0)
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.transform = entry["xform"] as Transform3D
		inst.visible = false
		_fx_root.add_child(inst)

		# The layer that reads as "bright" when there is no bloom: a billboarded
		# additive glow sitting right at the nozzle, the ref-4 detail of a hull lit
		# by its own engines carried into 2D as well as via the light pop below.
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		var halo_mesh := QuadMesh.new()
		halo_mesh.size = Vector2.ONE * radius * 2.2
		halo.mesh = halo_mesh
		var halo_mat := ShipMaterials.glow_material(
			Color(color.r, color.g, color.b, 0.9), true
		)
		halo.material_override = halo_mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.visible = false
		# A billboard needs a uniform scale to face the camera correctly; the plume
		# it sits on deliberately does not have one (see [constant BOOST_STRETCH]),
		# so the halo is positioned explicitly every frame in [method
		# _update_plumes] instead of inheriting the cone's anisotropic transform,
		# which drove the billboard shader singular and blew the whole screen out
		# to white under boost.
		halo.top_level = true
		inst.add_child(halo)

		_plumes.append(inst)
		_plume_bases.append(plume_scale)
		_plume_mats.append(mat)
		_plume_halos.append(halo)
		_plume_colors.append(color)
		_plume_was_lit.append(false)
		_plume_spark_timer.append(randf() * BOOST_SPARK_INTERVAL)
		_plume_eased.append(0.0)


## A cone built with a triangle fan: round from every angle, unlike the old
## crossed-quads trick. UVs run U across the circumference and V from nozzle (0)
## to tail (1) so `plume.gdshader` still samples the hot core at U = 0.5.
func _make_plume_mesh(radius: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	var tip_radius := radius * 0.08
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var u0 := float(s) / float(segs)
		var u1 := float(s + 1) / float(segs)
		# Base triangle (nozzle end)
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, 0.0))
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, 0.0))
		st.set_uv(Vector2((u0 + u1) * 0.5, 1.0))
		st.add_vertex(Vector3(cos((a0 + a1) * 0.5) * tip_radius, sin((a0 + a1) * 0.5) * tip_radius, -length))
	st.generate_normals()
	return st.commit()


## A cylinder rather than crossed quads: round from every angle, which is what a
## tracer needs. V runs 0 at the tail (+Z, local) to 1 at the head (-Z, the
## direction [method _spawn_shot] fires along) so `tracer.gdshader` still reads
## correctly.
func _make_tracer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := 0.06
	var half_l := 0.55
	var segs := 6
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var u0 := float(s) / float(segs)
		var u1 := float(s + 1) / float(segs)
		var cos0 := cos(a0) * half_w
		var sin0 := sin(a0) * half_w
		var cos1 := cos(a1) * half_w
		var sin1 := sin(a1) * half_w
		# Two triangles per quad segment along the length.
		# Tail ring at +Z, head ring at -Z.
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(Vector3(cos0, sin0, half_l))
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(cos1, sin1, half_l))
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(Vector3(cos1, sin1, -half_l))

		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(Vector3(cos0, sin0, half_l))
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(Vector3(cos1, sin1, -half_l))
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(Vector3(cos0, sin0, -half_l))
	st.generate_normals()
	return st.commit()


# --- Simulation ------------------------------------------------------------

func _process(delta: float) -> void:
	if _view == null or _stats == null:
		return
	if not running:
		_boost_level = 0.0
		_update_plumes(0.0, delta)
		return
	var boost_target := 1.0 if boosting and throttle > 0.01 else 0.0
	_boost_level = move_toward(_boost_level, boost_target, delta / BOOST_SPOOL)
	_update_power(delta)
	_update_plumes(throttle, delta)
	if firing:
		_try_fire(delta)
	_advance_shots(delta)
	_emit_state()


func _update_power(delta: float) -> void:
	var capacity := _capacity()
	# Surplus generation charges the capacitor; a deficit drains it, which is what
	# makes an under-powered build fail visibly instead of just showing a red number.
	var balance := _stats.power_balance
	var boost_draw := 0.0
	if throttle > 0.01:
		for entry in _view.exhausts:
			var func_data: Dictionary = entry.get("func", {})
			boost_draw += float(func_data.get("boost_draw", 0.0)) * throttle * 0.25
	energy = clampf(energy + (balance - boost_draw) * delta, 0.0, capacity)

	var thrust_heat := 0.0
	if throttle > 0.01:
		thrust_heat = _stats.get_stat("thrust") * HEAT_PER_THRUST * throttle
	heat = maxf(heat + (thrust_heat - _stats.get_stat("heat_dissipation") * 0.35) * delta, 0.0)


func _update_plumes(level: float, delta: float) -> void:
	for i in _plumes.size():
		var inst := _plumes[i]
		var target := clampf(level, 0.0, 1.0)
		var lit := target > 0.01
		if not lit:
			inst.visible = false
			if _plume_halos.size() > i:
				_plume_halos[i].visible = false
			_plume_was_lit[i] = false
			continue
		inst.visible = true
		if not _plume_was_lit[i]:
			# Ignition, not just "on again after a frame at zero": a puff from
			# nothing is what makes throttle-up read as an event.
			Juice.burst(BurstPresets.Preset.VAPOUR, inst.global_transform, _plume_bases[i])
		_plume_was_lit[i] = true

		# Spool: the plume eases towards the throttle instead of snapping, and a
		# little flicker keeps it from looking like a static cone.
		var flicker := 1.0 + sin(float(Time.get_ticks_msec()) * 0.03 + float(i)) * 0.06
		var wanted := target * flicker
		_plume_eased[i] = lerpf(_plume_eased[i], wanted, clampf(delta * 9.0, 0.0, 1.0))
		var eased := _plume_eased[i]
		# Clamped, not just eased: the plume points the same direction the chase
		# camera sits in, and on a small enough hull even a bug-free 1.6x stretch
		# can put the tail uncomfortably close to the lens. 1.4 is the margin that
		# held up under a stress render (full boost, turning hard, guns firing).
		var stretch := clampf(lerpf(1.0, BOOST_STRETCH, _boost_level), 1.0, 1.4)
		inst.scale = Vector3(
			lerpf(0.75, 1.0, eased), lerpf(0.75, 1.0, eased), maxf(eased, 0.02) * stretch
		)

		var mat := _plume_mats[i]
		if mat != null:
			mat.set_shader_parameter("throttle", target)
			mat.set_shader_parameter("boost", _boost_level)
		if _plume_halos.size() > i:
			var halo := _plume_halos[i]
			halo.visible = true
			halo.global_transform = Transform3D(
				Basis().scaled(
					Vector3.ONE * lerpf(0.6, 1.0, target) * lerpf(1.0, 1.3, _boost_level)
				),
				inst.global_transform.origin
			)

		if _boost_level > 0.05:
			_plume_spark_timer[i] -= delta
			if _plume_spark_timer[i] <= 0.0:
				_plume_spark_timer[i] = BOOST_SPARK_INTERVAL * 2.0
				Juice.burst(BurstPresets.Preset.EMBERS, inst.global_transform, 0.35)

		if i == _largest_plume_index:
			_engine_light_timer -= delta
			if _engine_light_timer <= 0.0:
				_engine_light_timer = ENGINE_LIGHT_INTERVAL
				Juice.light_pop(
					inst.global_transform.origin, _plume_colors[i], lerpf(1.5, 4.0, target), 0.16
				)


func _try_fire(delta: float) -> void:
	if _view.muzzles.is_empty():
		_note("No weapons fitted")
		return
	if _cooldowns.size() != _view.muzzles.size():
		_cooldowns.resize(_view.muzzles.size())
	var browned_out := false
	for i in _view.muzzles.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		if _cooldowns[i] > 0.0:
			continue
		var entry := _view.muzzles[i]
		var func_data: Dictionary = entry.get("func", {})
		var rate := maxf(float(func_data.get("fire_rate", 1.0)), 0.05)
		var cost := float(func_data.get("shot_energy", 0.0))
		if cost > energy:
			browned_out = true
			continue
		energy -= cost
		heat += cost * HEAT_PER_ENERGY
		_cooldowns[i] = 1.0 / rate
		_spawn_shot(entry, func_data, i)
	if browned_out:
		_note("Capacitor empty — fit a reactor or a bigger cell")
	elif _shots.size() >= MAX_PROJECTILES:
		_note("Projectile limit reached")
	else:
		_note("")


func _spawn_shot(entry: Dictionary, func_data: Dictionary, muzzle_index: int) -> void:
	if _shots.size() >= MAX_PROJECTILES:
		return
	shots_fired += 1
	var xform := entry["xform"] as Transform3D
	# The muzzle's own stable colour — a part-declared shot_color, else the
	# red/green/blue palette colour assigned at bind.
	var color := _muzzle_colors[muzzle_index] if muzzle_index < _muzzle_colors.size() else ShipMaterials.COL_BEAM
	var is_beam: bool = bool(func_data.get("beam", false))
	var speed := float(func_data.get("shot_speed", 700.0))
	var life := float(func_data.get("shot_life", DEFAULT_SHOT_LIFE))
	var world := global_transform * xform
	var dir := -world.basis.z

	_muzzle_fx(world, dir, color)

	var inst := MeshInstance3D.new()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	if _tracer_shader != null:
		mat.shader = _tracer_shader
	mat.set_shader_parameter("beam_color", color)
	if is_beam:
		# A beam is drawn as a long thin shaft that dies almost immediately, so
		# holding fire looks like a continuous lance rather than a bead of shots.
		# Length scales with shot_speed, so a slug reads as a bolt and a beam
		# reads as a lance — see `juice-and-more.md` §3.4.
		mat.set_shader_parameter("head_position", 0.0)
		inst.mesh = _shot_mesh
		inst.material_override = mat
		var length := speed * life * 0.5
		var beam_x := world
		beam_x.origin += -beam_x.basis.z.normalized() * length
		# Scale goes into the basis rather than onto `scale`, because assigning
		# `transform` afterwards would throw a separately-set scale away.
		inst.transform = beam_x.scaled_local(Vector3(0.5, 0.5, maxf(length, 1.0)))
		_shot_root.add_child(inst)
		var beam_life := 0.09
		_shots.append({
			"node": inst, "velocity": Vector3.ZERO, "life": beam_life,
			"life_total": beam_life, "beam": true, "mat": mat,
			"guided": false,
		})
		return

	# Already at its head, unlike a beam: a bolt's own motion is what sells its
	# travel, so the shader's bright point sits at the front from frame one.
	mat.set_shader_parameter("head_position", 1.0)
	inst.mesh = _shot_mesh
	inst.material_override = mat
	# Spread is in degrees; scatter within a cone so an autocannon reads as
	# inaccurate rather than as a laser.
	var spread := deg_to_rad(float(func_data.get("spread", 0.0)))
	if spread > 0.0:
		dir = dir.rotated(world.basis.x.normalized(), randf_range(-spread, spread))
		dir = dir.rotated(world.basis.y.normalized(), randf_range(-spread, spread))
	inst.transform = world
	_shot_root.add_child(inst)
	_shots.append({
		"node": inst,
		"velocity": dir * speed,
		"life": life,
		"beam": false,
		"guided": bool(func_data.get("guided", false)),
	})


## Everything that fires at the muzzle rather than travels down the barrel:
## sparks, a light pop, the recoil kick and its share of screen shake. Runs for
## every shot, beam or bolt — see `juice-and-more.md` §3.4.
func _muzzle_fx(world: Transform3D, dir: Vector3, color: Color) -> void:
	Juice.burst(BurstPresets.Preset.SPARKS, world, 0.8, color)
	Juice.burst(BurstPresets.Preset.EMBERS, world, 0.4, color)
	Juice.light_pop(world.origin, color, 4.0, 0.15)
	Juice.kick(dir, SHOT_KICK)
	Juice.shake(SHOT_SHAKE)


func _advance_shots(delta: float) -> void:
	var survivors: Array[Dictionary] = []
	for shot in _shots:
		var life := float(shot["life"]) - delta
		var node := shot["node"] as MeshInstance3D
		if life <= 0.0 or node == null:
			if node != null:
				node.queue_free()
			continue
		shot["life"] = life
		if bool(shot["beam"]):
			var total := float(shot.get("life_total", life))
			var mat := shot.get("mat") as ShaderMaterial
			if mat != null and total > 0.0:
				mat.set_shader_parameter("head_position", clampf(1.0 - life / total, 0.0, 1.0))
		else:
			var vel := shot["velocity"] as Vector3
			# Guided shots home: steer toward the owner's target, accelerating so a
			# missile catches a fleeing ship instead of trailing it.
			if bool(shot["guided"]) and target_ref != null and is_instance_valid(target_ref):
				var to_target := target_ref.global_position - node.global_position
				var tdist := to_target.length()
				if tdist > 1.0:
					var desired := to_target / tdist * maxf(vel.length(), 1.0)
					vel = vel.move_toward(desired, GUIDED_ACCEL * delta)
					shot["velocity"] = vel
					node.look_at(node.global_position + vel, Vector3.UP)
			node.position += vel * delta
		survivors.append(shot)
	_shots = survivors


func _clear_shots() -> void:
	for shot in _shots:
		var node := shot["node"] as MeshInstance3D
		if node != null:
			node.queue_free()
	_shots.clear()


func _note(text: String) -> void:
	if text == _last_note:
		return
	_last_note = text
	if text != "":
		fire_blocked.emit(text)


func _emit_state() -> void:
	state_changed.emit(
		energy / _capacity(),
		clampf(heat / _heat_ceiling(), 0.0, 1.0),
		_last_note
	)


# --- Controls --------------------------------------------------------------

func set_throttle(value: float) -> void:
	throttle = clampf(value, 0.0, 1.0)


func set_boost(value: bool) -> void:
	boosting = value


func set_firing(value: bool) -> void:
	if value and _view != null and _view.muzzles.is_empty():
		fire_blocked.emit("No weapons fitted")
		return
	firing = value
	if not value:
		_last_note = ""


func stop_all() -> void:
	firing = false
	throttle = 0.0
	boosting = false
	_boost_level = 0.0
	_clear_shots()
	for i in _plumes.size():
		_plumes[i].visible = false
		if _plume_halos.size() > i:
			_plume_halos[i].visible = false
		_plume_was_lit[i] = false


## Projectiles alive right now.
func shots_in_flight() -> int:
	return _shots.size()


## Exhaust plumes currently lit. Zero at idle, one per fitted engine at throttle.
func plumes_lit() -> int:
	var count := 0
	for inst in _plumes:
		if inst.visible:
			count += 1
	return count


## Human-readable summary for the systems readout.
func describe() -> String:
	if _view == null or _stats == null:
		return ""
	return "%d muzzle(s) · %d exhaust(s) · %.0f MJ cell · %.0f MW balance" % [
		_view.muzzles.size(),
		_view.exhausts.size(),
		_stats.get_stat("energy_capacity"),
		_stats.power_balance,
	]
