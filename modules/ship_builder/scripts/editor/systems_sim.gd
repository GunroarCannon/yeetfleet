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

## Fired when the active weapon is switched.
signal weapon_switched(weapon: Dictionary)

const PhysicalShockwave = preload("res://modules/physics/scripts/physical_shockwave.gd")
const PlanetDebrisBuilder = preload("res://modules/common/planets/planet_debris_builder.gd")

## The comprehensive weapon arsenal available on any ship.
const WEAPONS: Array[Dictionary] = [
	{
		"id": "pulse_laser",
		"name": "Pulse Laser",
		"desc": "High-velocity coherent energy bolts. Fast, reliable, versatile.",
		"type": "bolt",
		"damage": 28.0,
		"fire_rate": 4.5,
		"cost": 1.2,
		"speed": 1100.0,
		"life": 2.2,
		"spread": 0.3,
		"color": Color(0.15, 0.9, 1.0),
		"recoil": 1.0,
		"shake": 0.12,
		"kick": 0.5,
		"light_radius": 8.0,
		"light_duration": 0.12,
		"spark_scale": 0.8,
		"thickness": 0.22,
		"length": 5.5,
		"guided": false,
		"beam": false,
	},
	{
		"id": "sustained_laser",
		"name": "Sustained Blaster Laser",
		"desc": "Luminous incandescent laser beam — hold to carve through hulls and melt rock. Blasts intense emerald light along its whole length.",
		"type": "beam",
		"damage": 60.0,
		"fire_rate": 4.5,
		"cost": 2.2,
		"speed": 18000.0,
		"life": 0.40,
		"spread": 0.0,
		"color": Color(0.2, 1.0, 0.45),
		"recoil": 0.4,
		"shake": 0.15,
		"kick": 0.25,
		"light_radius": 26.0,
		"light_duration": 0.25,
		"spark_scale": 1.4,
		"thickness": 0.42,
		"length": 2500.0,
		"guided": false,
		"beam": true,
	},
	{
		"id": "heavy_pulse_blaster",
		"name": "Blaster Laser (Extended Light)",
		"desc": "High-velocity light bolts that blast in bright rapid streams and persist across long distances, illuminating deep space.",
		"type": "bolt",
		"damage": 48.0,
		"fire_rate": 6.0,
		"cost": 1.1,
		"speed": 1850.0,
		"life": 4.5,
		"spread": 0.25,
		"color": Color(0.25, 0.88, 1.0),
		"recoil": 1.2,
		"shake": 0.16,
		"kick": 0.6,
		"light_radius": 18.0,
		"light_duration": 0.20,
		"spark_scale": 1.3,
		"thickness": 0.35,
		"length": 12.0,
		"guided": false,
		"beam": false,
	},
	{
		"id": "hyper_beam",
		"name": "Hyperion Death Beam",
		"desc": "Massive continuous solar-gold beam blast that lasts for extended duration, tearing through anything in its line of sight.",
		"type": "beam",
		"damage": 180.0,
		"fire_rate": 1.2,
		"cost": 16.0,
		"speed": 22000.0,
		"life": 0.80,
		"spread": 0.0,
		"color": Color(1.0, 0.82, 0.2),
		"recoil": 3.0,
		"shake": 0.45,
		"kick": 1.2,
		"light_radius": 42.0,
		"light_duration": 0.45,
		"spark_scale": 2.2,
		"thickness": 0.85,
		"length": 3500.0,
		"guided": false,
		"beam": true,
	},
	{
		"id": "twin_autocannon",
		"name": "Twin Autocannon",
		"desc": "Heavy kinetic tungsten rounds. High fire rate, aggressive recoil chatter.",
		"type": "kinetic",
		"damage": 20.0,
		"fire_rate": 9.5,
		"cost": 0.5,
		"speed": 1350.0,
		"life": 1.8,
		"spread": 1.0,
		"color": Color(1.0, 0.72, 0.18),
		"recoil": 1.8,
		"shake": 0.22,
		"kick": 0.85,
		"light_radius": 10.0,
		"light_duration": 0.10,
		"spark_scale": 1.2,
		"thickness": 0.20,
		"length": 7.0,
		"guided": false,
		"beam": false,
	},
	{
		"id": "gauss_slugger",
		"name": "Mass Driver Gauss Cannon",
		"desc": "Magnetically accelerated 12-tonne tungsten flechette. Punches clean through multiple hulls; brutal kinetic knockback.",
		"type": "kinetic",
		"damage": 320.0,
		"fire_rate": 0.85,
		"cost": 4.0,
		"speed": 2400.0,
		"life": 3.5,
		"spread": 0.04,
		"color": Color(0.95, 0.85, 0.55),
		"recoil": 9.0,
		"shake": 1.1,
		"kick": 4.0,
		"light_radius": 22.0,
		"light_duration": 0.35,
		"spark_scale": 2.4,
		"thickness": 0.65,
		"length": 20.0,
		"guided": false,
		"beam": false,
	},
	{
		"id": "plasma_annihilator",
		"name": "Plasma Annihilator",
		"desc": "Magnetically bottled plasma spheres. Heavy splash blast that knocks targets.",
		"type": "plasma",
		"damage": 95.0,
		"fire_rate": 2.0,
		"cost": 5.0,
		"speed": 750.0,
		"life": 2.8,
		"spread": 0.1,
		"color": Color(0.85, 0.25, 1.0),
		"recoil": 4.0,
		"shake": 0.45,
		"kick": 1.8,
		"light_radius": 16.0,
		"light_duration": 0.22,
		"spark_scale": 1.5,
		"thickness": 0.55,
		"length": 1.5,
		"guided": false,
		"beam": false,
	},
	{
		"id": "gamma_burst",
		"name": "Gamma-Ray Burst Cannon",
		"desc": "Wide-angle short-range gamma detonation. Vaporises everything in a cone — point blank devastation.",
		"type": "plasma",
		"damage": 220.0,
		"fire_rate": 0.55,
		"cost": 12.0,
		"speed": 500.0,
		"life": 1.2,
		"spread": 8.0,
		"color": Color(0.6, 1.0, 0.9),
		"recoil": 9.0,
		"shake": 1.2,
		"kick": 4.0,
		"light_radius": 40.0,
		"light_duration": 0.5,
		"spark_scale": 3.5,
		"thickness": 0.9,
		"length": 1.8,
		"guided": false,
		"beam": false,
	},
	{
		"id": "seeker_missiles",
		"name": "Seeker Swarm Missiles",
		"desc": "Guided micro-missiles that lock and home aggressively on hostile craft.",
		"type": "missile",
		"damage": 150.0,
		"fire_rate": 1.4,
		"cost": 2.5,
		"speed": 550.0,
		"life": 4.5,
		"spread": 0.2,
		"color": Color(1.0, 0.48, 0.1),
		"recoil": 2.5,
		"shake": 0.35,
		"kick": 1.2,
		"light_radius": 12.0,
		"light_duration": 0.18,
		"spark_scale": 1.0,
		"thickness": 0.38,
		"length": 3.2,
		"guided": true,
		"beam": false,
	},
	{
		"id": "hellfire_missiles",
		"name": "Hellfire Heavy Missiles",
		"desc": "Large dual-stage heavy missiles with smoke and fire trails. Heavy armor-penetrating warhead.",
		"type": "missile",
		"damage": 340.0,
		"fire_rate": 1.0,
		"cost": 4.5,
		"speed": 460.0,
		"life": 6.5,
		"spread": 0.1,
		"color": Color(1.0, 0.55, 0.1),
		"recoil": 4.5,
		"shake": 0.55,
		"kick": 2.0,
		"light_radius": 20.0,
		"light_duration": 0.28,
		"spark_scale": 1.8,
		"thickness": 0.85,
		"length": 6.8,
		"guided": true,
		"beam": false,
		"is_heavy_missile": true,
	},
	{
		"id": "nova_torpedo",
		"name": "Titan Nova Torpedo",
		"desc": "Enormous capital warhead with 6 stabilizing fins. Slow but devastating — cracks planetary crust and obliterates fleets.",
		"type": "missile",
		"damage": 800.0,
		"fire_rate": 0.35,
		"cost": 10.0,
		"speed": 280.0,
		"life": 10.0,
		"spread": 0.04,
		"color": Color(1.0, 0.32, 0.05),
		"recoil": 7.0,
		"shake": 1.2,
		"kick": 3.0,
		"light_radius": 35.0,
		"light_duration": 0.5,
		"spark_scale": 3.0,
		"thickness": 1.6,
		"length": 11.0,
		"guided": true,
		"beam": false,
		"is_nova": true,
	},
	{
		"id": "antimatter_railgun",
		"name": "Antimatter Spinal Railgun",
		"desc": "Relativistic antimatter slug. Heavy whole-ship kickback; punches through mega ships and shatters planetary crust.",
		"type": "railgun",
		"damage": 850.0,
		"fire_rate": 0.6,
		"cost": 25.0,
		"speed": 3800.0,
		"life": 2.5,
		"spread": 0.02,
		"color": Color(0.85, 0.95, 1.0),
		"recoil": 12.5,
		"shake": 1.6,
		"kick": 4.5,
		"light_radius": 28.0,
		"light_duration": 0.35,
		"spark_scale": 2.5,
		"thickness": 0.45,
		"length": 28.0,
		"guided": false,
		"beam": false,
	},
	{
		"id": "planet_buster_beam",
		"name": "Planet-Buster Tachyon Lance",
		"desc": "Continuous focused death ray. Melts mega ships and annihilates entire planets if held on target.",
		"type": "beam",
		"damage": 50.0,
		"fire_rate": 20.0,
		"cost": 1.6,
		"speed": 18000.0,
		"life": 0.09,
		"spread": 0.0,
		"color": Color(1.0, 0.22, 0.38),
		"recoil": 0.8,
		"shake": 0.25,
		"kick": 0.4,
		"light_radius": 22.0,
		"light_duration": 0.15,
		"spark_scale": 1.8,
		"thickness": 0.40,
		"length": 1500.0,
		"guided": false,
		"beam": true,
	},
	{
		"id": "singularity_vortex",
		"name": "Event Horizon Singularity Cannon",
		"desc": "Launches a micro-singularity with an accretion disk. Exerts intense gravitational suction on nearby debris and crafts, then collapses in a violet implosion.",
		"type": "singularity",
		"damage": 650.0,
		"fire_rate": 0.5,
		"cost": 16.0,
		"speed": 420.0,
		"life": 4.0,
		"spread": 0.04,
		"color": Color(0.80, 0.25, 1.0),
		"recoil": 7.0,
		"shake": 0.9,
		"kick": 2.5,
		"light_radius": 36.0,
		"light_duration": 0.6,
		"spark_scale": 2.8,
		"thickness": 1.2,
		"length": 1.2,
		"guided": false,
		"beam": false,
		"is_singularity": true,
	},
	{
		"id": "flak_scatter",
		"name": "Shredder Flak Array",
		"desc": "Multi-barrel kinetic flak battery. Discharges a dense 10-pellet tungsten flechette spread that shreds debris fields, incoming torpedoes, and fighter formations.",
		"type": "flak",
		"damage": 42.0,
		"fire_rate": 2.2,
		"cost": 1.5,
		"speed": 1750.0,
		"life": 1.5,
		"spread": 4.5,
		"color": Color(1.0, 0.68, 0.18),
		"recoil": 3.0,
		"shake": 0.35,
		"kick": 1.2,
		"light_radius": 14.0,
		"light_duration": 0.15,
		"spark_scale": 1.5,
		"thickness": 0.24,
		"length": 5.0,
		"guided": false,
		"beam": false,
		"pellets": 10,
	},
	{
		"id": "cryo_lance",
		"name": "Zero-Kelvin Cryo Lance",
		"desc": "Sustained sub-zero beam of coherent cryo-photons. Drains target thermal energy, freezing angular tumble and locking thrusters while shattering brittle asteroid crusts.",
		"type": "beam",
		"damage": 95.0,
		"fire_rate": 3.2,
		"cost": 3.2,
		"speed": 25000.0,
		"life": 0.35,
		"spread": 0.0,
		"color": Color(0.25, 0.88, 1.0),
		"recoil": 0.5,
		"shake": 0.18,
		"kick": 0.3,
		"light_radius": 24.0,
		"light_duration": 0.22,
		"spark_scale": 1.6,
		"thickness": 0.45,
		"length": 2200.0,
		"guided": false,
		"beam": true,
		"is_cryo": true,
	},
	{
		"id": "solar_flamer",
		"name": "Helios Solar Flamer",
		"desc": "Projects an ultra-dense torrent of incandescent solar coronal plasma. Engulfs targets in churning solar fire, melting through armor plates and vaporizing rocky fragments.",
		"type": "plasma",
		"damage": 52.0,
		"fire_rate": 11.0,
		"cost": 0.75,
		"speed": 720.0,
		"life": 1.2,
		"spread": 2.2,
		"color": Color(1.0, 0.45, 0.08),
		"recoil": 1.0,
		"shake": 0.14,
		"kick": 0.4,
		"light_radius": 18.0,
		"light_duration": 0.15,
		"spark_scale": 1.8,
		"thickness": 0.75,
		"length": 1.8,
		"guided": false,
		"beam": false,
		"is_solar_flame": true,
	},
]

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
var _cached_planets: Array = []
var _planet_cache_timer := 0.0
var _planet_hit_cooldown := 0.0
var _crater_rocks: Array[Node] = []
const MAX_CRATER_ROCKS := 18
static var _cached_ray_query: PhysicsRayQueryParameters3D = null
static var _shared_fb_mesh: SphereMesh = null
static var _shared_corona_mesh: SphereMesh = null

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
		var color := Color.from_string(String(func_data.get("exhaust_color", "6fd8ff")), ShipMaterials.beam_color())

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


static var _glow_head_tex: Texture2D = null

static func _get_glow_head_texture() -> Texture2D:
	if _glow_head_tex == null:
		var grad := GradientTexture2D.new()
		grad.fill = GradientTexture2D.FILL_RADIAL
		grad.fill_from = Vector2(0.5, 0.5)
		grad.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		grad.gradient = g
		grad.width = 64
		grad.height = 64
		_glow_head_tex = grad
	return _glow_head_tex


## Sleek aerodynamic 6-fin tapered needle tracer mesh.
## Sharp needle tip at the head, smooth expansion at mid, aerodynamic taper at tail.
func _make_tracer_mesh(radius: float = 0.22, length: float = 6.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_l := length * 0.5
	var r_tip := radius * 0.04
	var r_mid := radius
	var r_tail := radius * 0.32
	var z_head := -half_l
	var z_mid := -half_l * 0.35
	var z_tail := half_l

	var angles := [0.0, PI / 3.0, 2.0 * PI / 3.0]
	for a in angles:
		var v_dir := Vector3(cos(a), sin(a), 0.0)
		var p0 := -v_dir * r_tip + Vector3(0.0, 0.0, z_head)
		var p1 := v_dir * r_tip + Vector3(0.0, 0.0, z_head)
		var p2 := -v_dir * r_mid + Vector3(0.0, 0.0, z_mid)
		var p3 := v_dir * r_mid + Vector3(0.0, 0.0, z_mid)
		var p4 := -v_dir * r_tail + Vector3(0.0, 0.0, z_tail)
		var p5 := v_dir * r_tail + Vector3(0.0, 0.0, z_tail)

		# Segment 1: Head needle to mid (UV.y from 1.0 down to 0.65)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)

		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)

		# Reverse side
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)

		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)

		# Segment 2: Mid to tail (UV.y from 0.65 down to 0.0)
		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p5)

		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p5)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p4)

		# Reverse side
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p5)
		st.set_uv(Vector2(1.0, 0.65)); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)

		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p4)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p5)
		st.set_uv(Vector2(0.0, 0.65)); st.add_vertex(p2)

	st.generate_normals()
	return st.commit()


## A continuous cylindrical beam shaft built with 4 radial planes for round 360-degree profile.
func _make_beam_mesh(radius: float = 0.40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := radius
	var l := 0.5

	var angles := [0.0, PI * 0.25, PI * 0.5, PI * 0.75]
	for a in angles:
		var v_dir := Vector3(cos(a), sin(a), 0.0)
		var p0 := -v_dir * r + Vector3(0.0, 0.0, -l)
		var p1 := v_dir * r + Vector3(0.0, 0.0, -l)
		var p2 := -v_dir * r + Vector3(0.0, 0.0, l)
		var p3 := v_dir * r + Vector3(0.0, 0.0, l)

		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p3)

		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p2)

		# Reverse side
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p3)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)

		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p2)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)

	st.generate_normals()
	return st.commit()


## Dedicated aerodynamic missile models: sleek cruise missile, dual-stage heavy missile, and massive 6-fin nova capital torpedo.
func _make_missile_node(color: Color, thickness: float, length: float, is_nova: bool = false, is_heavy: bool = false) -> Node3D:
	var root := Node3D.new()
	var body_len := length * (0.55 if is_heavy else (0.60 if not is_nova else 0.50))
	var nose_len := length * (0.35 if is_heavy else (0.30 if not is_nova else 0.35))
	var tail_len := length * 0.15
	var segs: int = 18 if is_nova else (16 if is_heavy else 12)

	# Body material (dark metallic military finish)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.14, 0.16, 0.18) if is_nova else (Color(0.20, 0.22, 0.25) if is_heavy else Color(0.25, 0.27, 0.30))
	body_mat.roughness = 0.35
	body_mat.metallic = 0.85

	# Main fuselage cylinder
	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = thickness * 0.90
	cyl.bottom_radius = thickness
	cyl.height = body_len
	cyl.radial_segments = segs
	body_mesh.mesh = cyl
	body_mesh.material_override = body_mat
	body_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	body_mesh.position = Vector3(0.0, 0.0, tail_len * 0.4)
	root.add_child(body_mesh)

	# Nose cone — aerodynamic pointed ogive
	var nose_mat := StandardMaterial3D.new()
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nose_mat.albedo_color = color
	nose_mat.emission_enabled = true
	nose_mat.emission = color
	nose_mat.emission_energy_multiplier = 5.0 if is_nova else 3.5
	var nose_mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = thickness * 0.88
	cone.height = nose_len
	cone.radial_segments = segs
	nose_mesh.mesh = cone
	nose_mesh.material_override = nose_mat
	nose_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	nose_mesh.position = Vector3(0.0, 0.0, -(body_len * 0.5 + nose_len * 0.5))
	root.add_child(nose_mesh)

	# Superheated glowing sensor dome at nose tip
	var tip := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = thickness * 0.65
	ts.height  = thickness * 1.3
	ts.radial_segments = 12
	ts.rings   = 8
	tip.mesh = ts
	var tip_mat := StandardMaterial3D.new()
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mat.albedo_color = Color.WHITE
	tip_mat.emission_enabled = true
	tip_mat.emission = color
	tip_mat.emission_energy_multiplier = 9.0
	tip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tip_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tip.material_override = tip_mat
	tip.position = Vector3(0.0, 0.0, -(body_len * 0.5 + nose_len))
	root.add_child(tip)

	# Fins configuration:
	if is_nova:
		# 6 heavy swept delta fins with reinforced roots
		for fin_idx in 6:
			var fin := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(thickness * 3.8, thickness * 0.22, length * 0.32)
			fin.mesh = fm
			fin.material_override = body_mat
			fin.rotation = Vector3(PI * 0.5, 0.0, float(fin_idx) / 6.0 * TAU)
			fin.position = Vector3(0.0, 0.0, body_len * 0.45)
			root.add_child(fin)

		# Massive nuclear reactor containment sphere in mid-fuselage
		var bulge := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = thickness * 1.65
		bs.height  = thickness * 2.6
		bs.radial_segments = 16
		bs.rings   = 10
		bulge.mesh = bs
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.55, 0.12, 0.05)
		b_mat.roughness = 0.4
		b_mat.metallic = 0.8
		b_mat.emission_enabled = true
		b_mat.emission = Color(1.0, 0.3, 0.05)
		b_mat.emission_energy_multiplier = 2.5
		bulge.material_override = b_mat
		root.add_child(bulge)

	elif is_heavy:
		# Heavy dual-stage: 4 forward steering canards + 4 rear stabilizing delta fins
		for fin_idx in 4:
			var canard := MeshInstance3D.new()
			var cm := PrismMesh.new()
			cm.size = Vector3(thickness * 1.8, thickness * 0.12, length * 0.18)
			canard.mesh = cm
			canard.material_override = body_mat
			canard.rotation = Vector3(PI * 0.5, 0.0, float(fin_idx) * PI * 0.5)
			canard.position = Vector3(0.0, 0.0, -body_len * 0.2)
			root.add_child(canard)

			var rear_fin := MeshInstance3D.new()
			var rfm := PrismMesh.new()
			rfm.size = Vector3(thickness * 3.0, thickness * 0.16, length * 0.26)
			rear_fin.mesh = rfm
			rear_fin.material_override = body_mat
			rear_fin.rotation = Vector3(PI * 0.5, 0.0, float(fin_idx) * PI * 0.5 + PI * 0.25)
			rear_fin.position = Vector3(0.0, 0.0, body_len * 0.45)
			root.add_child(rear_fin)

		# Interstage decoupling band
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = thickness * 1.05
		bm.bottom_radius = thickness * 1.05
		bm.height = length * 0.08
		bm.radial_segments = segs
		band.mesh = bm
		var band_mat := StandardMaterial3D.new()
		band_mat.albedo_color = Color(0.85, 0.55, 0.2)
		band_mat.metallic = 0.95
		band_mat.roughness = 0.2
		band.material_override = band_mat
		band.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		band.position = Vector3(0.0, 0.0, 0.0)
		root.add_child(band)

	else:
		# Standard seeker: 4 agile delta fins
		for fin_idx in 4:
			var fin := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(thickness * 2.4, thickness * 0.14, length * 0.26)
			fin.mesh = fm
			fin.material_override = body_mat
			fin.rotation = Vector3(PI * 0.5, 0.0, float(fin_idx) * PI * 0.5)
			fin.position = Vector3(0.0, 0.0, body_len * 0.4)
			root.add_child(fin)

	# Rocket thruster nozzle flame at the tail
	var thruster := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius    = thickness * (0.80 if is_nova else (0.65 if is_heavy else 0.50))
	tm.bottom_radius = 0.0
	tm.height = length * (0.65 if is_nova else (0.50 if is_heavy else 0.40))
	tm.radial_segments = 12
	thruster.mesh = tm
	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.albedo_color = Color(1.0, 0.7, 0.2)
	t_mat.emission_enabled = true
	t_mat.emission = Color(1.0, 0.5, 0.05)
	t_mat.emission_energy_multiplier = 7.0
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	thruster.material_override = t_mat
	thruster.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	thruster.position = Vector3(0.0, 0.0, body_len * 0.5 + tail_len + tm.height * 0.5)
	root.add_child(thruster)

	# Wide glow aura billboard at the nozzle
	var flare := MeshInstance3D.new()
	var fq := QuadMesh.new()
	var fsize := thickness * (7.0 if is_nova else (5.0 if is_heavy else 4.0))
	fq.size = Vector2(fsize, fsize)
	flare.mesh = fq
	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	f_mat.albedo_color = Color(1.0, 0.65, 0.2)
	f_mat.albedo_texture = _get_glow_head_texture()
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare.material_override = f_mat
	flare.position = Vector3(0.0, 0.0, body_len * 0.5 + tail_len)
	root.add_child(flare)

	return root


## High-impact visual explosion with multi-sphere expanding fireball, shockwave rings, and particle bursts.
func _spawn_impact_explosion(hit_pos: Vector3, normal: Vector3, weapon: Dictionary) -> void:
	var w_type: String = weapon.get("type", "bolt")
	var is_nova: bool = bool(weapon.get("is_nova", false))
	var is_heavy: bool = bool(weapon.get("is_heavy_missile", false))
	var col: Color = weapon.get("color", Color("ff8833"))
	var base_radius: float = float(weapon.get("light_radius", 14.0))
	var spark_s: float = float(weapon.get("spark_scale", 1.0))
	var shake_amt: float = float(weapon.get("shake", 0.25)) * 1.6

	# Screen shake and light pop
	Juice.shake(shake_amt)
	Juice.light_pop(hit_pos, col, base_radius * (2.8 if is_nova else (1.8 if is_heavy else 1.4)), 0.35 if is_nova else 0.22)

	# Shockwave ring expanding along impact plane
	var norm := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var up := norm
	var right := Vector3.UP.cross(up)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT.cross(up)
	right = right.normalized()
	var fwd := up.cross(right).normalized()
	var ring_basis := Basis(right, up, fwd)
	var ring_radius := base_radius * (2.6 if is_nova else (1.8 if is_heavy else 1.4))
	var is_sing: bool = bool(weapon.get("is_singularity", false))
	var is_cryo: bool = bool(weapon.get("is_cryo", false))
	var is_flame: bool = bool(weapon.get("is_solar_flame", false))
	var w_id: String = String(weapon.get("id", ""))
	var xform := Transform3D(ring_basis, hit_pos)

	if is_cryo:
		Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius * 1.5, Color(0.65, 0.92, 1.0), 0.35)
		Juice.burst(BurstPresets.Preset.SPARKS, xform, spark_s * 1.8, Color(0.8, 0.95, 1.0))
		Juice.burst(BurstPresets.Preset.RING_SPARK, xform, spark_s * 1.5, Color(0.4, 0.85, 1.0))
	elif is_flame:
		Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius * 1.3, Color(1.0, 0.5, 0.1), 0.35)
		Juice.burst(BurstPresets.Preset.EMBERS, xform, spark_s * 2.5, Color(1.0, 0.45, 0.08))
		Juice.burst(BurstPresets.Preset.VAPOUR, xform, spark_s * 1.8, Color(0.35, 0.15, 0.05, 0.7))
	elif w_id == "gauss_slugger" or w_id == "antimatter_railgun":
		Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius * 2.0, Color(0.85, 0.95, 1.0), 0.4)
		Juice.burst(BurstPresets.Preset.SPARKS, xform, spark_s * 2.8, Color.WHITE)
		Juice.burst(BurstPresets.Preset.DEBRIS, xform, spark_s * 1.8)
	else:
		Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius, col, 0.45 if is_nova else 0.3)
		if is_nova:
			Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius * 1.6, Color.WHITE, 0.6)
			Juice.flash(Color(1.0, 0.85, 0.6), 0.4, 1.5)
		elif is_sing:
			Juice.ring(Transform3D(ring_basis, hit_pos), ring_radius * 2.4, Color(0.9, 0.4, 1.0), 0.6)
			Juice.flash(Color(0.80, 0.25, 1.0), 0.45, 1.8)

		Juice.burst(BurstPresets.Preset.SPARKS, xform, spark_s * (2.5 if is_nova else 1.5), Color.WHITE)
		Juice.burst(BurstPresets.Preset.EMBERS, xform, spark_s * (2.0 if is_nova else 1.2), col)
		Juice.burst(BurstPresets.Preset.RING_SPARK, xform, spark_s * (2.0 if is_nova else 1.0), col)
		if w_type == "missile" or w_type == "plasma" or is_nova or is_heavy:
			Juice.burst(BurstPresets.Preset.VAPOUR, xform, spark_s * 1.5, Color(0.3, 0.3, 0.35, 0.6))
			Juice.burst(BurstPresets.Preset.DEBRIS, xform, spark_s * 1.2)

	# Audio: play impact explosion sounds (spatial 3D)
	var audio := SpaceAudio.instance()
	if audio != null:
		if is_sing:
			audio.play_singularity_pulse(hit_pos)
		elif w_type == "flak":
			audio.play_flak_detonation(hit_pos)
		else:
			audio.play_explosion(hit_pos, is_nova or is_heavy)

	# BinbunVFX layer on top of the Juice one-shots, plus the sprite hit flash.
	# No sound from the addon here: the SpaceAudio call above already carries the
	# impact, and two copies of the same explosion is just volume. Both are off
	# when [FxSettings.addon_vfx] is false, which is the A/B switch.
	var vfx_parent: Node = _shot_root.get_parent() if _shot_root != null else self
	var vfx_kind := AddonVfx.Kind.HIT
	if is_sing or is_nova:
		vfx_kind = AddonVfx.Kind.NUKE
	elif is_heavy or w_id == "gauss_slugger" or w_id == "antimatter_railgun" or w_type == "railgun":
		vfx_kind = AddonVfx.Kind.BIG_IMPACT
	elif is_cryo or w_id.contains("ion") or w_id.contains("emp"):
		vfx_kind = AddonVfx.Kind.BALL
	elif w_id.contains("lightning") or is_flame:
		vfx_kind = AddonVfx.Kind.ZAP
	elif w_type == "missile" or w_type == "flak":
		vfx_kind = AddonVfx.Kind.EXPLOSION_AIR
	elif w_type == "plasma":
		vfx_kind = AddonVfx.Kind.IMPACT
	var vfx_scale := maxf(0.6, spark_s)
	AddonVfx.spawn(vfx_parent, vfx_kind, hit_pos, norm, vfx_scale, col)
	AddonVfx.spawn_sprite_hit(vfx_parent, hit_pos, norm, vfx_scale)

	# ExplosionRegistry event slot mapping:
	var slot := ExplosionRegistry.SLOT_PLANET_IMPACT
	if is_nova:
		slot = ExplosionRegistry.SLOT_NOVA_NUKE
	elif is_sing:
		slot = ExplosionRegistry.SLOT_SINGULARITY
	elif w_type == "plasma":
		slot = ExplosionRegistry.SLOT_PLASMA_BURST
	elif w_type == "missile" or is_heavy:
		slot = ExplosionRegistry.SLOT_MISSILE_BLAST
	var reg := ExplosionRegistry.new()
	reg.spawn_event(vfx_parent, slot, hit_pos, norm, vfx_scale, col)

	# Dynamic expanding spherical fireball mesh with additive glow (explosive and heavy weapons only)
	var is_explosive: bool = is_nova or is_heavy or is_sing or w_type == "missile" or w_type == "flak" or w_type == "railgun" or w_type == "plasma"
	if is_explosive:
		if _shared_fb_mesh == null:
			_shared_fb_mesh = SphereMesh.new()
			_shared_fb_mesh.radius = 1.0
			_shared_fb_mesh.height = 2.0
			_shared_fb_mesh.radial_segments = 12
			_shared_fb_mesh.rings = 6
		if _shared_corona_mesh == null:
			_shared_corona_mesh = SphereMesh.new()
			_shared_corona_mesh.radius = 1.35
			_shared_corona_mesh.height = 2.7
			_shared_corona_mesh.radial_segments = 10
			_shared_corona_mesh.rings = 5

		var fb := MeshInstance3D.new()
		fb.mesh = _shared_fb_mesh
		var fb_mat := StandardMaterial3D.new()
		fb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fb_mat.albedo_color = Color.WHITE
		fb_mat.emission_enabled = true
		fb_mat.emission = col
		fb_mat.emission_energy_multiplier = 2.2
		fb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fb.material_override = fb_mat
		_shot_root.add_child(fb)
		fb.top_level = true
		fb.global_position = hit_pos

		# Outer fiery corona sphere
		var corona := MeshInstance3D.new()
		corona.mesh = _shared_corona_mesh
		var c_mat := StandardMaterial3D.new()
		c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		c_mat.albedo_color = Color(col.r, col.g, col.b, 0.4)
		c_mat.emission_enabled = true
		c_mat.emission = col
		c_mat.emission_energy_multiplier = 1.6
		c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		c_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		corona.material_override = c_mat
		fb.add_child(corona)

		var target_scale: float = 24.0 if is_nova else (13.0 if is_heavy else (8.5 if w_type == "plasma" or w_type == "missile" else 5.0))
		var expand_time: float = 0.55 if is_nova else (0.42 if is_heavy else 0.30)
		var tw := fb.create_tween()
		tw.tween_property(fb, "scale", Vector3.ONE * target_scale, expand_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(fb_mat, "albedo_color:a", 0.0, expand_time).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c_mat, "albedo_color:a", 0.0, expand_time).set_ease(Tween.EASE_IN)
		tw.tween_callback(fb.queue_free)

	# Actual physical multilayer shockwave pushing bodies, ships, and debris with distance falloff:
	if is_sing or is_nova or is_heavy or w_type == "missile" or w_type == "plasma" or weapon.get("shockwave", false):
		var phys_rad: float = base_radius * (5.5 if is_sing else (4.5 if is_nova else (3.2 if is_heavy else 2.2)))
		var phys_force: float = float(weapon.get("damage", 25.0)) * (12.0 if is_sing else (10.0 if is_nova else 6.5))
		var phys_torque: float = 20.0 if is_sing else (14.0 if is_nova else 8.0)
		var phys_dmg: float = float(weapon.get("damage", 25.0)) * 0.45
		var shock_dur: float = 0.85 if is_sing else (0.7 if is_nova else 0.4)
		PhysicalShockwave.create(_shot_root, hit_pos, phys_rad, phys_force, phys_torque, phys_dmg, col, shock_dur)



# --- Simulation ------------------------------------------------------------

func _process(delta: float) -> void:
	if _view == null or _stats == null:
		return
	if not running:
		_boost_level = 0.0
		_update_plumes(0.0, delta)
		return
	_planet_cache_timer -= delta
	if _planet_hit_cooldown > 0.0:
		_planet_hit_cooldown = maxf(0.0, _planet_hit_cooldown - delta)
	var boost_target := 1.0 if boosting and throttle > 0.01 else 0.0
	_boost_level = move_toward(_boost_level, boost_target, delta / BOOST_SPOOL)
	var plume_level := throttle * (1.0 + _boost_level * 0.4)
	_update_plumes(plume_level, delta)
	_update_power(delta)
	var active_w: Dictionary = get_active_weapon()
	var is_beam_weapon: bool = bool(active_w.get("beam", false))
	if firing:
		_try_fire(delta)
		if is_beam_weapon and energy > float(active_w.get("cost", 1.0)):
			var audio := SpaceAudio.instance()
			if audio != null:
				var is_p: bool = (_root != null and _root.get("systems") == self)
				audio.start_beam_loop(String(active_w.get("id", "")), is_p, global_position)
		elif is_beam_weapon:
			var audio := SpaceAudio.instance()
			if audio != null:
				audio.stop_beam_loop(String(active_w.get("id", "")))
	else:
		if is_beam_weapon:
			var audio := SpaceAudio.instance()
			if audio != null:
				audio.stop_beam_loop(String(active_w.get("id", "")))
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
		if not lit or not inst.is_inside_tree():
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


var active_weapon_index: int = 0
var _planet_melt_timer := 0.0

func get_active_weapon() -> Dictionary:
	return WEAPONS[active_weapon_index % WEAPONS.size()]


func cycle_weapon() -> Dictionary:
	active_weapon_index = (active_weapon_index + 1) % WEAPONS.size()
	var w: Dictionary = get_active_weapon()
	_cooldowns.fill(0.0)
	weapon_switched.emit(w)
	return w


func set_weapon_index(idx: int) -> Dictionary:
	active_weapon_index = clampi(idx, 0, WEAPONS.size() - 1)
	var w: Dictionary = get_active_weapon()
	_cooldowns.fill(0.0)
	weapon_switched.emit(w)
	return w


func _get_effective_muzzles() -> Array:
	if _view != null:
		if not _view.muzzles.is_empty():
			_view.set_meta("had_weapons", true)
			return _view.muzzles
		elif _view.get_meta("had_weapons", false):
			# All weapons were destroyed or detached by modular damage
			return []
	# Synthesize default forward muzzles on port and starboard flanks for any hull without weapon mounts
	var left_xform := Transform3D(Basis(), Vector3(-1.6, -0.2, -2.2))
	var right_xform := Transform3D(Basis(), Vector3(1.6, -0.2, -2.2))
	return [
		{"xform": left_xform, "func": {}},
		{"xform": right_xform, "func": {}}
	]


func _try_fire(delta: float) -> void:
	var muzzles: Array = _get_effective_muzzles()
	if muzzles.is_empty():
		_note("All weapon mounts destroyed or offline")
		return
	if _cooldowns.size() != muzzles.size():
		_cooldowns.resize(muzzles.size())
		_cooldowns.fill(0.0)
	var browned_out := false
	var active_w: Dictionary = get_active_weapon()
	var rate: float = maxf(float(active_w.get("fire_rate", 2.0)), 0.05)
	var cost: float = float(active_w.get("cost", 1.0))
	
	for i in muzzles.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		if _cooldowns[i] > 0.0:
			continue
		var entry: Dictionary = muzzles[i]
		if cost > energy:
			browned_out = true
			continue
		energy -= cost
		heat += cost * HEAT_PER_ENERGY
		_cooldowns[i] = 1.0 / rate
		_spawn_shot(entry, active_w, i)
	
	if browned_out:
		_note("Capacitor empty — recharge required")
	elif _shots.size() >= MAX_PROJECTILES:
		_note("Projectile limit reached")
	else:
		_note("")


func _spawn_shot(entry: Dictionary, weapon_data: Dictionary, muzzle_index: int) -> void:
	if _shots.size() >= MAX_PROJECTILES:
		return
	shots_fired += 1
	var xform := entry["xform"] as Transform3D
	var color: Color = weapon_data.get("color", Color.CYAN)
	var is_beam: bool = bool(weapon_data.get("beam", false))
	var speed: float = float(weapon_data.get("speed", 900.0))
	var life: float = float(weapon_data.get("life", DEFAULT_SHOT_LIFE))
	var thickness: float = float(weapon_data.get("thickness", 0.22))
	var length: float = float(weapon_data.get("length", 6.0))
	# Use the true visual hull transform if available, accounting for scaling,
	# visual roll banking, and part mount placement.
	var root_node: Node3D = null
	if _view != null and _view.root != null and is_instance_valid(_view.root):
		root_node = _view.root
	else:
		root_node = self
	var muzzle := root_node.global_transform * xform

	# Calculate convergence: aim towards the reticle sightline or locked target
	var aim_point := Vector3.ZERO
	if target_ref != null and is_instance_valid(target_ref):
		aim_point = target_ref.global_position
	else:
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null and is_instance_valid(cam):
			var cam_fwd := -cam.global_transform.basis.z
			var max_dist := 1200.0
			var w3d := get_world_3d()
			var hit_found := false
			if w3d != null and w3d.direct_space_state != null:
				var ray := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + cam_fwd * max_dist)
				if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_rid"):
					ray.exclude = [_root.model.get_rid()]
				var r_hit := w3d.direct_space_state.intersect_ray(ray)
				if not r_hit.is_empty():
					aim_point = r_hit["position"]
					hit_found = true
			if not hit_found:
				aim_point = cam.global_position + cam_fwd * max_dist
		else:
			aim_point = muzzle.origin - root_node.global_transform.basis.z * 1000.0

	var dir := (aim_point - muzzle.origin).normalized()
	# Guard against reverse firing if the aim point ends up behind the muzzle
	if dir.dot(-root_node.global_transform.basis.z) < 0.25:
		dir = -muzzle.basis.z

	# Apply spread if defined
	var spread := deg_to_rad(float(weapon_data.get("spread", 0.0)))
	if spread > 0.0:
		dir = dir.rotated(muzzle.basis.x.normalized(), randf_range(-spread, spread))
		dir = dir.rotated(muzzle.basis.y.normalized(), randf_range(-spread, spread))

	# Muzzle light flash, sparks, and kickback, at the barrel tip.
	_muzzle_fx(muzzle, dir, color, weapon_data)

	# Audio: play weapon sound (cockpit punch for player, spatial 3D for AI)
	var audio := SpaceAudio.instance()
	if audio != null:
		var is_p: bool = (_root != null and _root.get("systems") == self)
		audio.play_weapon_fire(String(weapon_data.get("type", "laser")), muzzle.origin, is_p, String(weapon_data.get("id", "")))

	# Spawn projectile directly at muzzle tip so lasers emerge directly from gun barrels
	var world := muzzle
	world.origin = muzzle.origin + dir * 0.45



	# Inherit ship's velocity so shooting always goes ahead of the ship
	var ship_vel := Vector3.ZERO
	if _root != null and _root.get("model") != null:
		var m = _root.model
		if m != null and m.get("velocity") != null:
			ship_vel = m.velocity
			# Physical recoil impulse on player ship
			var recoil: float = float(weapon_data.get("recoil", 1.0))
			m.velocity -= dir * recoil

	# Guarantee bullet velocity always exceeds forward ship velocity:
	var forward_ship_speed := maxf(0.0, ship_vel.dot(dir))
	var eff_speed := maxf(speed, forward_ship_speed + 350.0)

	if weapon_data.get("type", "") == "flak":
		var pellet_count: int = int(weapon_data.get("pellets", 10))
		Juice.burst(BurstPresets.Preset.VAPOUR, Transform3D(Basis(), world.origin), 1.6, Color(0.45, 0.45, 0.5, 0.5))
		for p in pellet_count:
			if _shots.size() >= MAX_PROJECTILES:
				break
			var p_spread := deg_to_rad(float(weapon_data.get("spread", 4.5)))
			var p_dir := dir
			p_dir = p_dir.rotated(world.basis.x.normalized(), randf_range(-p_spread, p_spread))
			p_dir = p_dir.rotated(world.basis.y.normalized(), randf_range(-p_spread, p_spread))
			var p_speed := eff_speed * randf_range(0.88, 1.12)
			var p_vel := p_dir * p_speed + ship_vel * 0.35

			var p_inst := MeshInstance3D.new()
			p_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p_inst.mesh = _make_tracer_mesh(thickness, length * randf_range(0.8, 1.25))
			var p_mat := ShaderMaterial.new()
			if _tracer_shader != null:
				p_mat.shader = _tracer_shader
			p_mat.set_shader_parameter("beam_color", color)
			p_mat.set_shader_parameter("head_position", 1.0)
			p_inst.material_override = p_mat

			_shot_root.add_child(p_inst)
			p_inst.global_position = world.origin + p_dir * randf_range(0.0, 2.5)
			if p_dir.length_squared() > 0.001:
				p_inst.look_at(p_inst.global_position + p_dir, Vector3.UP)

			_shots.append({
				"node": p_inst, "velocity": p_vel, "life": life * randf_range(0.85, 1.15),
				"guided": false, "trail_timer": 0.0, "weapon": weapon_data,
				"beam": false
			})
		return

	if is_beam:
		var inst := MeshInstance3D.new()
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.mesh = _make_beam_mesh(thickness)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		inst.material_override = mat

		# Inner white-hot laser core
		var core := MeshInstance3D.new()
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.mesh = _make_beam_mesh(thickness * 0.40)
		var core_mat := StandardMaterial3D.new()
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
		core_mat.emission_enabled = true
		core_mat.emission = Color.WHITE
		core_mat.emission_energy_multiplier = 8.0
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		core.material_override = core_mat
		inst.add_child(core)

		var w3d := get_world_3d()
		if w3d == null:
			return
		var beam_len := 50000.0
		var space_state := w3d.direct_space_state
		var query := PhysicsRayQueryParameters3D.create(world.origin, world.origin + dir * beam_len)
		if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_rid"):
			query.exclude = [_root.model.get_rid()]
		var b_hit := space_state.intersect_ray(query)
		var hit_target: Object = null
		var hit_pos := world.origin + dir * beam_len
		if not b_hit.is_empty():
			beam_len = world.origin.distance_to(b_hit["position"])
			hit_pos = b_hit["position"]
			hit_target = b_hit["collider"]

		# Check planets too
		var p_hit := _check_planet_intersect(world.origin, dir, beam_len)
		if p_hit.has("planet"):
			beam_len = world.origin.distance_to(p_hit["point"])
			hit_pos = p_hit["point"]
			hit_target = p_hit["planet"]

		inst.global_position = world.origin + dir * (beam_len * 0.5)
		if dir.length_squared() > 0.001:
			inst.look_at(inst.global_position + dir, Vector3.UP)
		inst.scale = Vector3(1.0, 1.0, beam_len)

		# Impact flare at hit point
		var hit_flare := MeshInstance3D.new()
		var hq := QuadMesh.new()
		var hf_sz: float = maxf(thickness * 8.0, 3.5)
		hq.size = Vector2(hf_sz, hf_sz)
		hit_flare.mesh = hq
		var hf_mat := StandardMaterial3D.new()
		hf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hf_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		hf_mat.albedo_color = color
		hf_mat.albedo_texture = _get_glow_head_texture()
		hf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hf_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hit_flare.material_override = hf_mat
		hit_flare.position = Vector3(0.0, 0.0, -beam_len * 0.5)
		inst.add_child(hit_flare)

		_shot_root.add_child(inst)

		_shots.append({
			"node": inst, "velocity": ship_vel, "life": life,
			"life_total": life, "beam": true, "weapon": weapon_data,
			"hit_target": hit_target, "hit_pos": hit_pos, "dir": dir,
			"ship_vel": ship_vel, "core_mat": core_mat, "hit_flare_mat": hf_mat,
			"hit_flare": hit_flare, "entry": entry, "spread": spread,
		})
		return

	# Bolt / projectile
	var inst := MeshInstance3D.new()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if weapon_data["type"] == "plasma":
		# Dense white-hot inner core
		var s := SphereMesh.new()
		s.radius = thickness * 0.8
		s.height = thickness * 1.6
		s.radial_segments = 16
		s.rings = 12
		inst.mesh = s
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 6.0
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		inst.material_override = mat

		# Outer soft corona sphere
		var corona := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = thickness * 1.45
		cs.height = thickness * 2.9
		cs.radial_segments = 16
		cs.rings = 12
		corona.mesh = cs
		var c_mat := StandardMaterial3D.new()
		c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		c_mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		c_mat.emission_enabled = true
		c_mat.emission = color
		c_mat.emission_energy_multiplier = 3.5
		c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		c_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		corona.material_override = c_mat
		inst.add_child(corona)

		# Circular radial aura billboard
		var aura := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var q_size: float = thickness * 4.2
		qm.size = Vector2(q_size, q_size)
		aura.mesh = qm
		var a_mat := StandardMaterial3D.new()
		a_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		a_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		a_mat.albedo_color = color
		a_mat.albedo_texture = _get_glow_head_texture()
		a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		a_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		aura.material_override = a_mat
		inst.add_child(aura)

	elif weapon_data["type"] == "missile":
		var is_nova_m: bool = bool(weapon_data.get("is_nova", false))
		var is_heavy_m: bool = bool(weapon_data.get("is_heavy_missile", false))
		var m_root := _make_missile_node(color, thickness, length, is_nova_m, is_heavy_m)
		inst.add_child(m_root)

	elif weapon_data["type"] == "singularity":
		# Micro-black hole core
		var s := SphereMesh.new()
		s.radius = thickness * 0.95
		s.height = thickness * 1.9
		s.radial_segments = 24
		s.rings = 16
		inst.mesh = s
		var s_mat := StandardMaterial3D.new()
		s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s_mat.albedo_color = Color(0.02, 0.01, 0.04) # Deep black void
		inst.material_override = s_mat

		# Luminous spinning accretion disk
		var disk := MeshInstance3D.new()
		disk.name = "AccretionDisk"
		var tm := TorusMesh.new()
		tm.inner_radius = thickness * 1.2
		tm.outer_radius = thickness * 3.0
		tm.rings = 36
		tm.ring_segments = 16
		disk.mesh = tm
		var d_mat := StandardMaterial3D.new()
		d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		d_mat.albedo_color = color
		d_mat.emission_enabled = true
		d_mat.emission = color
		d_mat.emission_energy_multiplier = 8.5
		d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		disk.material_override = d_mat
		inst.add_child(disk)

		# Gravitational lensing Einstein ring distortion halo
		var aura := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var q_size: float = thickness * 8.0
		qm.size = Vector2(q_size, q_size)
		aura.mesh = qm
		var lens_shader := load("res://modules/common/juice/shaders/singularity_lens.gdshader") as Shader
		if lens_shader != null:
			var l_mat := ShaderMaterial.new()
			l_mat.shader = lens_shader
			l_mat.set_shader_parameter("distortion_strength", 0.35)
			l_mat.set_shader_parameter("photon_ring_color", color)
			l_mat.set_shader_parameter("accretion_color", Color(color.r * 1.2, color.g * 0.8, color.b * 0.4, 1.0))
			aura.material_override = l_mat
		else:
			var a_mat := StandardMaterial3D.new()
			a_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			a_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			a_mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
			a_mat.albedo_texture = _get_glow_head_texture()
			a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			a_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			aura.material_override = a_mat
		inst.add_child(aura)


	else:
		inst.mesh = _make_tracer_mesh(thickness, length)
		var mat := ShaderMaterial.new()
		if _tracer_shader != null:
			mat.shader = _tracer_shader
		mat.set_shader_parameter("beam_color", color)
		mat.set_shader_parameter("head_position", 1.0)
		inst.material_override = mat

		# Soft circular head glow billboard
		var head := MeshInstance3D.new()
		head.name = "GlowHead"
		var quad := QuadMesh.new()
		var head_size: float = maxf(thickness * 4.5, 1.2)
		quad.size = Vector2(head_size, head_size)
		head.mesh = quad
		var head_mat := StandardMaterial3D.new()
		head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		head_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		head_mat.albedo_color = color
		head_mat.albedo_texture = _get_glow_head_texture()
		head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		head_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		head.material_override = head_mat
		head.position = Vector3(0.0, 0.0, -length * 0.5)
		inst.add_child(head)

	inst.transform = world
	_shot_root.add_child(inst)

	# BinbunVFX magic projectile visual layer for exotic/heavy weapons
	if AddonVfx.enabled():
		var w_id_shot: String = String(weapon_data.get("id", ""))
		var w_type_shot: String = String(weapon_data.get("type", "bolt"))
		if w_id_shot == "antimatter_railgun" or w_id_shot == "gauss_slugger":
			AddonVfx.projectile_fx(inst, world.origin, dir, AddonVfx.Kind.PROJECTILE_JAVELIN, thickness * 2.5, color)
		elif w_id_shot == "gamma_burst" or bool(weapon_data.get("is_solar_flame", false)):
			AddonVfx.projectile_fx(inst, world.origin, dir, AddonVfx.Kind.PROJECTILE_WAVE, thickness * 2.5, color)
		elif w_type_shot == "plasma":
			AddonVfx.projectile_fx(inst, world.origin, dir, AddonVfx.Kind.PROJECTILE_BOLT, thickness * 2.0, color)

	_shots.append({
		"node": inst,
		"velocity": dir * eff_speed + ship_vel,
		"life": life,
		"beam": false,
		"guided": bool(weapon_data.get("guided", false)),
		"weapon": weapon_data,
		"trail_timer": 0.0,
	})


func _muzzle_fx(world: Transform3D, dir: Vector3, color: Color, weapon_data: Dictionary) -> void:
	var spark_s: float = float(weapon_data.get("spark_scale", 1.0))
	var l_radius: float = float(weapon_data.get("light_radius", 10.0))
	var l_dur: float = float(weapon_data.get("light_duration", 0.15))
	var kick: float = float(weapon_data.get("kick", SHOT_KICK))
	var shake: float = float(weapon_data.get("shake", SHOT_SHAKE))
	var w_id: String = String(weapon_data.get("id", ""))
	var is_cryo: bool = bool(weapon_data.get("is_cryo", false))
	var is_flame: bool = bool(weapon_data.get("is_solar_flame", false))
	var w_type: String = String(weapon_data.get("type", "bolt"))

	if is_cryo:
		Juice.burst(BurstPresets.Preset.SPARKS, world, spark_s * 1.3, Color(0.6, 0.92, 1.0))
		Juice.ring(world, spark_s * 1.4, Color(0.3, 0.85, 1.0), 0.18)
	elif is_flame:
		Juice.burst(BurstPresets.Preset.EMBERS, world, spark_s * 1.8, Color(1.0, 0.45, 0.1))
		Juice.burst(BurstPresets.Preset.VAPOUR, world, spark_s * 0.9, Color(0.9, 0.35, 0.05, 0.5))
	elif w_id == "gauss_slugger" or w_id == "antimatter_railgun":
		Juice.burst(BurstPresets.Preset.SPARKS, world, spark_s * 2.2, Color.WHITE)
		Juice.ring(world, spark_s * 2.2, Color(0.75, 0.9, 1.0), 0.22)
	elif w_id == "gamma_burst":
		Juice.burst(BurstPresets.Preset.SPARKS, world, spark_s * 2.4, Color(0.7, 1.0, 0.85))
		Juice.ring(world, spark_s * 2.5, Color(0.5, 1.0, 0.9), 0.25)
	else:
		Juice.burst(BurstPresets.Preset.SPARKS, world, spark_s, color)
		if w_type == "kinetic" or w_type == "plasma":
			Juice.burst(BurstPresets.Preset.EMBERS, world, spark_s * 0.7, color)

	Juice.light_pop(world.origin, color, l_radius, l_dur)
	Juice.kick(dir, kick)
	Juice.shake(shake)


func _advance_shots(delta: float) -> void:
	var survivors: Array[Dictionary] = []
	for shot in _shots:
		var life: float = float(shot["life"]) - delta
		var node := shot["node"] as MeshInstance3D
		if life <= 0.0 or node == null or not is_instance_valid(node):
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		if not is_inside_tree() or not node.is_inside_tree():
			continue
		shot["life"] = life
		var is_beam: bool = bool(shot["beam"])
		var weapon: Dictionary = shot.get("weapon", get_active_weapon())
		
		if is_beam:
			# Continuously attach beam to the visual hull muzzle transform with convergence
			var b_entry: Dictionary = shot.get("entry", {})
			var xf: Transform3D = b_entry.get("xform", Transform3D())
			var root_node: Node3D = null
			if _view != null and _view.root != null and is_instance_valid(_view.root):
				root_node = _view.root
			else:
				root_node = self
			var b_world := root_node.global_transform * xf
			var b_origin := b_world.origin

			# Aim convergence towards sightline/target
			var b_aim := Vector3.ZERO
			if target_ref != null and is_instance_valid(target_ref):
				b_aim = target_ref.global_position
			else:
				var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
				if cam != null and is_instance_valid(cam):
					var cam_fwd := -cam.global_transform.basis.z
					b_aim = cam.global_position + cam_fwd * 1200.0
				else:
					b_aim = b_origin - root_node.global_transform.basis.z * 1000.0

			var b_dir := (b_aim - b_origin).normalized()
			if b_dir.dot(-root_node.global_transform.basis.z) < 0.25:
				b_dir = -b_world.basis.z

			var w3d := get_world_3d()
			var b_len := 50000.0
			var b_target: Object = null
			var b_hit_pos := b_origin + b_dir * b_len
			if w3d != null:
				var s_state := w3d.direct_space_state
				var q := PhysicsRayQueryParameters3D.create(b_origin, b_origin + b_dir * b_len)
				if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_rid"):
					q.exclude = [_root.model.get_rid()]
				var b_hit := s_state.intersect_ray(q)
				if not b_hit.is_empty():
					b_len = b_origin.distance_to(b_hit["position"])
					b_hit_pos = b_hit["position"]
					b_target = b_hit["collider"]
				var p_hit := _check_planet_intersect(b_origin, b_dir, b_len)
				if p_hit.has("planet"):
					b_len = b_origin.distance_to(p_hit["point"])
					b_hit_pos = p_hit["point"]
					b_target = p_hit["planet"]

			# Keep continuous beam locked to the visual gun barrel and converged forward:
			node.global_position = b_origin + b_dir * (b_len * 0.5)
			if b_dir.length_squared() > 0.001:
				node.look_at(node.global_position + b_dir, Vector3.UP)
			node.scale = Vector3(1.0, 1.0, b_len)

			if shot.has("hit_flare") and is_instance_valid(shot["hit_flare"]):
				shot["hit_flare"].position = Vector3(0.0, 0.0, -0.5)

			shot["hit_target"] = b_target
			shot["hit_pos"] = b_hit_pos
			shot["dir"] = b_dir

			# Smooth fade over beam lifetime
			var life_total: float = maxf(float(shot.get("life_total", 0.1)), 0.001)
			var alpha: float = clampf(life / life_total, 0.0, 1.0)
			var b_mat := node.material_override as StandardMaterial3D
			if b_mat != null:
				b_mat.albedo_color.a = alpha
				b_mat.emission_energy_multiplier = 4.5 * alpha
			if shot.has("core_mat") and shot["core_mat"] != null:
				(shot["core_mat"] as StandardMaterial3D).albedo_color.a = alpha
			if shot.has("hit_flare_mat") and shot["hit_flare_mat"] != null:
				(shot["hit_flare_mat"] as StandardMaterial3D).albedo_color.a = alpha
			# Beam hit processing
			if shot.has("hit_target") and shot["hit_target"] != null:
				var target: Object = shot["hit_target"]
				var h_pos: Vector3 = shot["hit_pos"]
				_process_beam_hit(target, h_pos, b_dir, weapon, delta)
			survivors.append(shot)
			continue

		var vel: Vector3 = shot.get("velocity", Vector3.ZERO) as Vector3

		# Rocket smoke & sparks trail for missiles
		if weapon.get("type") == "missile":
			var tr_timer: float = float(shot.get("trail_timer", 0.0)) - delta
			if tr_timer <= 0.0:
				tr_timer = 0.045
				var m_col: Color = weapon.get("color", Color("ff8822"))
				var is_n: bool = bool(weapon.get("is_nova", false))
				var is_h: bool = bool(weapon.get("is_heavy_missile", false))
				var trail_scale: float = 0.8 if is_n else (0.5 if is_h else 0.3)
				var v_dir: Vector3 = vel.normalized() if vel.length_squared() > 0.01 else Vector3.FORWARD
				var flare_pos: Vector3 = node.global_position - v_dir * (float(weapon.get("length", 3.0)) * 0.45)
				var tr_xform := Transform3D(Basis(), flare_pos)
				Juice.burst(BurstPresets.Preset.EMBERS, tr_xform, trail_scale, m_col)
				Juice.burst(BurstPresets.Preset.SPARKS, tr_xform, trail_scale * 0.8, Color.WHITE)
				if is_n or is_h:
					Juice.burst(BurstPresets.Preset.VAPOUR, tr_xform, trail_scale * 0.7, Color(0.4, 0.4, 0.45, 0.4))
			shot["trail_timer"] = tr_timer

		# Singularity gravitational vortex suction & accretion disk spin
		if bool(weapon.get("is_singularity", false)):
			var s_pos: Vector3 = node.global_position
			var disk := node.get_node_or_null("AccretionDisk") as Node3D
			if disk != null:
				disk.rotate_object_local(Vector3.UP, 15.0 * delta)
			var phys: PhysWorld = _root.get("phys_world") if _root != null and _root.get("phys_world") is PhysWorld else null
			if phys != null:
				for b in phys.bodies:
					if b.node != null and not b.kinematic and is_instance_valid(b.node) and b.node.is_inside_tree():
						var to_sing := s_pos - b.position()
						var s_dist := to_sing.length()
						if s_dist > 1.0 and s_dist < 350.0:
							var pull_f := (1.0 - s_dist / 350.0) * 260.0
							b.velocity += to_sing.normalized() * (pull_f * delta)
			var tr_timer: float = float(shot.get("trail_timer", 0.0)) - delta
			if tr_timer <= 0.0:
				tr_timer = 0.045
				Juice.burst(BurstPresets.Preset.EMBERS, Transform3D(Basis(), s_pos), 1.6, Color(0.85, 0.3, 1.0))
			shot["trail_timer"] = tr_timer

		# Solar flamer particle stream
		if bool(weapon.get("is_solar_flame", false)):
			var tr_timer: float = float(shot.get("trail_timer", 0.0)) - delta
			if tr_timer <= 0.0:
				tr_timer = 0.035
				var fl_pos: Vector3 = node.global_position
				Juice.burst(BurstPresets.Preset.EMBERS, Transform3D(Basis(), fl_pos), 1.3, Color(1.0, 0.45, 0.08))
				Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), fl_pos), 0.9, Color(1.0, 0.85, 0.3))
			shot["trail_timer"] = tr_timer

		# Guided shots home on locked target
		if bool(shot["guided"]) and target_ref != null and is_instance_valid(target_ref):
			var to_target := target_ref.global_position - node.global_position
			var tdist := to_target.length()
			if tdist > 1.0:
				var desired := to_target / tdist * maxf(vel.length(), 1.0)
				vel = vel.move_toward(desired, GUIDED_ACCEL * delta)
				shot["velocity"] = vel
				node.look_at(node.global_position + vel, Vector3.UP)
		
		var prev_pos: Vector3 = node.global_position
		var next_pos: Vector3 = prev_pos + vel * delta
		node.global_position = next_pos
		
		# Check raycast hit along path
		var hit_happened := _check_shot_hit(shot, prev_pos, next_pos)
		if hit_happened:
			node.queue_free()
			continue
			
		survivors.append(shot)
	_shots = survivors


func _process_beam_hit(target: Object, hit_pos: Vector3, dir: Vector3, weapon: Dictionary, delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	var col: Color = weapon.get("color", Color.CYAN)
	Juice.light_pop(hit_pos, col, 20.0, 0.1)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), hit_pos), 1.2, col)
	
	if target is Planet:
		_planet_melt_timer += delta
		Juice.shake(clampf(0.25 + _planet_melt_timer * 0.45, 0.0, 1.0))
		Juice.light_pop(hit_pos, Color(1.0, 0.4, 0.1), 140.0, 0.2)
		var pct := int(clampf(_planet_melt_timer / 1.5 * 100.0, 0.0, 100.0))
		_note("⚠️ TACHYON DRILL: PLANETARY CORE OVERLOAD %d%%" % pct)
		if _planet_melt_timer >= 1.5:
			_planet_melt_timer = 0.0
			_note("")
			_destroy_planet(target as Planet, hit_pos)
	elif target is LargeCraftGenerator:
		(target as LargeCraftGenerator).shatter_at(hit_pos, 18.0, dir * 25.0)
	elif target is StaticBody3D:
		var gen := _find_large_craft_gen(target as Node3D)
		if gen != null:
			gen.shatter_at(hit_pos, 18.0, dir * 25.0)
	elif target is AiShip:
		(target as AiShip).take_damage(float(weapon.get("damage", 30.0)) * delta * 15.0)
	elif target is RigidBody3D:
		var rb := target as RigidBody3D
		var dmg: float = float(weapon.get("damage", 30.0))
		var is_cryo: bool = bool(weapon.get("is_cryo", false))
		if is_cryo:
			rb.angular_velocity = rb.angular_velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			rb.linear_velocity = rb.linear_velocity.move_toward(Vector3.ZERO, 45.0 * delta)
			Juice.burst(BurstPresets.Preset.VAPOUR, Transform3D(Basis(), hit_pos), 1.5, Color(0.5, 0.9, 1.0, 0.75))
			Juice.light_pop(hit_pos, Color(0.2, 0.8, 1.0), 28.0, 0.12)
		else:
			rb.apply_impulse(dir * (dmg * 2.2 * delta), hit_pos - rb.global_position)
		var phys: PhysWorld = _root.get("phys_world") if _root != null and _root.get("phys_world") is PhysWorld else null
		if phys != null:
			for pb in phys.bodies:
				if pb.node == rb:
					if is_cryo:
						pb.angular = pb.angular.move_toward(Vector3.ZERO, 12.0 * delta)
						pb.velocity = pb.velocity.move_toward(Vector3.ZERO, 45.0 * delta)
					else:
						pb.velocity += dir * ((dmg * 2.2 * delta) / maxf(pb.mass, 1.0))
					break


func _check_shot_hit(shot: Dictionary, from: Vector3, to: Vector3) -> bool:
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	if dist < 0.001:
		return false
	
	var w3d := get_world_3d()
	if w3d == null:
		return false
	var space_state := w3d.direct_space_state
	if _cached_ray_query == null:
		_cached_ray_query = PhysicsRayQueryParameters3D.new()
	_cached_ray_query.from = from
	_cached_ray_query.to = to
	if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_rid"):
		_cached_ray_query.exclude = [_root.model.get_rid()]
	else:
		_cached_ray_query.exclude = []
	var hit := space_state.intersect_ray(_cached_ray_query)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		_on_hit_target(shot, collider, hit_pos, dir)
		return true
	
	var planet_hit := _check_planet_intersect(from, dir, dist)
	if planet_hit.has("planet"):
		_on_hit_planet(shot, planet_hit["planet"], planet_hit["point"], dir)
		return true
	
	return false


func _on_hit_target(shot: Dictionary, collider: Object, hit_pos: Vector3, dir: Vector3) -> void:
	var w: Dictionary = shot.get("weapon", get_active_weapon())
	var dmg: float = float(w.get("damage", 25.0))
	var col: Color = w.get("color", Color.CYAN)
	
	_spawn_impact_explosion(hit_pos, -dir, w)
	
	# Walk parent chain to identify target
	var target_node = collider
	while target_node != null:
		if target_node is AiShip:
			(target_node as AiShip).take_damage(dmg)
			if target_node.get("model") != null:
				target_node.model.velocity += dir * (dmg * 0.15)
			return
		if target_node is LargeCraftGenerator:
			_hit_large_craft(target_node as LargeCraftGenerator, collider, hit_pos, dir, w)
			return
		target_node = target_node.get_parent()
	
	if collider is StaticBody3D:
		var gen := _find_large_craft_gen(collider as Node3D)
		if gen != null:
			_hit_large_craft(gen, collider, hit_pos, dir, w)
	elif collider is RigidBody3D:
		var rb := collider as RigidBody3D
		var is_sing: bool = bool(w.get("is_singularity", false))
		var push_force: float = dmg * (5.5 if is_sing else 2.0)
		rb.apply_impulse(dir * push_force, hit_pos - rb.global_position)
		rb.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * push_force * 0.15)
		Juice.burst(BurstPresets.Preset.DEBRIS, Transform3D(Basis(), hit_pos), 1.4)
		Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), hit_pos), 1.8, Color(1.0, 0.8, 0.4))
		var phys: PhysWorld = _root.get("phys_world") if _root != null and _root.get("phys_world") is PhysWorld else null
		if phys != null:
			for pb in phys.bodies:
				if pb.node == rb:
					pb.velocity += dir * (push_force / maxf(pb.mass, 1.0))
					pb.angular += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (push_force / maxf(pb.mass, 1.0)) * 0.4
					break


func _hit_large_craft(gen: LargeCraftGenerator, collider: Object, hit_pos: Vector3, dir: Vector3, weapon: Dictionary) -> void:
	var w_type: String = weapon.get("type", "bolt")
	var is_nova: bool = bool(weapon.get("is_nova", false))
	var is_heavy: bool = bool(weapon.get("is_heavy_missile", false))
	var wid: String = weapon.get("id", "")
	var blast_radius := 12.0
	var impulse := dir * 20.0
	
	match w_type:
		"railgun":
			blast_radius = 55.0
			impulse = dir * 90.0
		"plasma":
			blast_radius = 28.0
			impulse = dir * 45.0
		"missile":
			blast_radius = 50.0 if is_nova else (32.0 if is_heavy else 20.0)
			impulse = dir * (90.0 if is_nova else (45.0 if is_heavy else 30.0))
		"beam":
			blast_radius = 35.0 if wid == "hyper_beam" else 20.0
			impulse = dir * (40.0 if wid == "hyper_beam" else 25.0)
		"kinetic":
			blast_radius = 32.0 if wid == "gauss_slugger" else 12.0
			impulse = dir * (65.0 if wid == "gauss_slugger" else 20.0)
		_:
			blast_radius = 12.0
			impulse = dir * 20.0
	
	var col: Color = weapon.get("color", Color("ff8833"))
	AddonVfx.ground_explosion(gen, hit_pos, -dir, maxf(1.5, blast_radius * 0.08), col)
	var detached := gen.shatter_at(hit_pos, blast_radius, impulse)
	if detached.is_empty():
		gen.shoot_at(hit_pos - dir * 5.0, dir, 10.0)


func _find_large_craft_gen(node: Node3D) -> LargeCraftGenerator:
	var cur: Node = node
	while cur != null:
		if cur is LargeCraftGenerator:
			return cur as LargeCraftGenerator
		cur = cur.get_parent()
	return null


func _get_candidate_planets() -> Array:
	if _cached_planets.is_empty() or _planet_cache_timer <= 0.0:
		_planet_cache_timer = 0.5
		var list: Array = []
		if _root != null and _root.get_tree() != null:
			list = _root.get_tree().get_nodes_in_group("planets")
		if list.is_empty() and _root != null and _root.get("space") != null and _root.space != null:
			list = _root.space.find_children("", "Planet", true, false)
		_cached_planets = list
	return _cached_planets


func _check_planet_intersect(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var candidate_planets := _get_candidate_planets()
	
	var closest_planet: Planet = null
	var closest_t := max_dist
	var hit_point := Vector3.ZERO
	
	for p in candidate_planets:
		if not is_instance_valid(p) or not (p is Planet):
			continue
		var planet := p as Planet
		if not planet.visible or planet.data == null:
			continue
		var center := planet.global_position
		var radius: float = planet.data.planet_radius
		var L := center - from
		var tca := L.dot(dir)
		var d2 := L.length_squared() - tca * tca
		var r2 := radius * radius
		if d2 > r2:
			continue
		var thc := sqrt(maxf(0.0, r2 - d2))
		var t0 := tca - thc
		var t1 := tca + thc
		var t_hit := -1.0
		if t0 > 0.0:
			t_hit = t0
		elif t1 > 0.0:
			t_hit = t1
		if t_hit > 0.0 and t_hit < closest_t:
			closest_t = t_hit
			closest_planet = planet
			hit_point = from + dir * t_hit
				
	if closest_planet != null:
		return {"planet": closest_planet, "point": hit_point}
	return {}


func _on_hit_planet(shot: Dictionary, planet: Planet, hit_pos: Vector3, dir: Vector3) -> void:
	var w: Dictionary = shot.get("weapon", get_active_weapon())
	var col: Color = w.get("color", Color.CYAN)
	var dmg: float = float(w.get("damage", 30.0))
	var wid: String = w.get("id", "")
	var is_nova: bool = bool(w.get("is_nova", false))
	
	_spawn_impact_explosion(hit_pos, -dir, w)
	if is_nova or wid == "antimatter_railgun":
		AddonVfx.nuke(planet, hit_pos, 4.0, col)
	else:
		AddonVfx.ground_explosion(planet, hit_pos, -dir, 3.0, col)
	
	# Progressive WMD damage:
	var base_hp: float = 6000.0
	var cur_hp: float = planet.get_meta("planet_hp", base_hp)
	var effective_damage: float = dmg
	if wid == "antimatter_railgun":
		effective_damage = 2200.0
	elif is_nova:
		effective_damage = 3200.0
	elif wid == "hyper_beam":
		effective_damage = 900.0

	cur_hp -= effective_damage
	planet.set_meta("planet_hp", cur_hp)

	var pct: int = clampi(roundi(cur_hp / base_hp * 100.0), 0, 100)
	if cur_hp > 0.0:
		if _planet_hit_cooldown <= 0.0:
			_planet_hit_cooldown = 0.22
			_spawn_planet_crater_blast(planet, hit_pos, dir)
			PhysicalShockwave.create(_shot_root, hit_pos, 380.0, 260.0, 9.0, 65.0, Color(1.0, 0.5, 0.1), 1.1)
		_note("⚠️ SEISMIC INTEGRITY AT %d%% — TECTONIC FISSURES FORMING" % pct)
	else:
		_destroy_planet(planet, hit_pos)


func _spawn_planet_crater_blast(planet: Planet, hit_pos: Vector3, dir: Vector3) -> void:
	Juice.flash(Color(1.0, 0.85, 0.6), 0.20, 1.1)
	Juice.shake(0.6)
	Juice.light_pop(hit_pos, Color(1.0, 0.5, 0.1), 320.0, 1.2)
	
	# Cap active crater rocks and discard oldest
	while _crater_rocks.size() >= MAX_CRATER_ROCKS:
		var old_rock = _crater_rocks.pop_front()
		if is_instance_valid(old_rock):
			old_rock.queue_free()

	for i in 6:
		var rock := RigidBody3D.new()
		rock.top_level = true
		rock.global_position = hit_pos + Vector3(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := randf_range(20.0, 50.0)
		bm.size = Vector3(sz, sz, sz)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.22, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.1)
		mat.emission_energy_multiplier = 2.5
		mi.material_override = mat
		rock.add_child(mi)
		
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		rock.add_child(cs)
		rock.add_to_group("rigid_bodies")
		
		_shot_root.add_child(rock)
		_crater_rocks.append(rock)
		var eject_dir := (-dir + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))).normalized()
		rock.linear_velocity = eject_dir * randf_range(160.0, 420.0)
		rock.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

		# Auto-fade and clean up
		var tw := rock.create_tween()
		tw.tween_interval(2.5 + randf() * 0.8)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.5)
		tw.tween_callback(func() -> void:
			_crater_rocks.erase(rock)
			if is_instance_valid(rock):
				rock.queue_free()
		)


func _destroy_planet(planet: Planet, epicentre: Vector3) -> void:
	if planet == null or not is_instance_valid(planet):
		return
	if planet.has_meta("shattered"):
		return
	planet.set_meta("shattered", true)
	
	var p_name: String = planet.data.planet_name if planet.data != null else "Planet"
	var radius: float = planet.data.planet_radius if planet.data != null else 1000.0
	var p_pos: Vector3 = planet.global_position
	
	Juice.flash(Color(1.0, 0.95, 0.85), 1.0, 3.8)
	Juice.shake(1.0)
	Juice.light_pop(p_pos, Color(1.0, 0.55, 0.15), radius * 8.0, 6.0)
	AddonVfx.nuke(_shot_root, epicentre, 8.0, Color(1.0, 0.65, 0.25))

	var audio := SpaceAudio.instance()
	if audio != null:
		audio.play_planet_destruction(epicentre)

	# Actual expanding physical multilayer shockwave:
	PhysicalShockwave.create(_shot_root, p_pos, radius * 6.5, 850.0, 18.0, 450.0, Color(1.0, 0.65, 0.25), 3.2)
	
	# Spawn 3D pyramids, irregular polyhedra, deep slabs + asteroids + core breakup:
	var phys: PhysWorld = _root.get("phys_world") if _root != null and _root.get("phys_world") is PhysWorld else null
	PlanetDebrisBuilder.shatter_planet(planet, epicentre, _shot_root, 420.0, Session.planet_break_fineness, phys)

	# Hide and disable planet completely
	planet.visible = false
	planet.process_mode = Node.PROCESS_MODE_DISABLED
	for child in planet.get_children():
		if child is Node3D:
			child.visible = false
	
	if _root != null and _root.has_method("on_planet_destroyed"):
		_root.on_planet_destroyed(planet)
	
	_note("💥 PLANET OBLITERATED: %s was completely destroyed!" % p_name)


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
