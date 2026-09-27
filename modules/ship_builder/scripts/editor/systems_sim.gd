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
		"size_class": "fighter",
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
		"hitscan": true,
	},
	{
		"id": "sustained_laser",
		"size_class": "corvette",
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
		"size_class": "fighter",
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
		"hitscan": true,
	},
	{
		"id": "hyper_beam",
		"size_class": "capital",
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
		"size_class": "fighter",
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
		"size_class": "hauler",
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
		"size_class": "corvette",
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
		"size_class": "hauler",
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
		"size_class": "corvette",
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
		"size_class": "hauler",
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
		"size_class": "capital",
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
		"size_class": "capital",
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
		"size_class": "capital",
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
		"size_class": "hauler",
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
		"size_class": "fighter",
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
		"size_class": "corvette",
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
		"size_class": "fighter",
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
## Maximum angle a shot may bend from its own muzzle's facing to converge on
## the reticle/target. A centreline gun is already pointed near the crosshair
## so it converges precisely; a wingtip or canted mount is clamped to this
## cone instead of being yanked the rest of the way, so its shots visibly
## leave along the barrel they came out of rather than snapping to the
## crosshair regardless of where the gun actually points.
const MUZZLE_CONVERGENCE_CONE := deg_to_rad(12.0)
## Heat added per unit of energy spent. Firing is the main heat source in a
## builder with no engines actually pushing anything.
const HEAT_PER_ENERGY := 1.7
## Heat added per second at full throttle, per unit of thrust.
const HEAT_PER_THRUST := 0.012

const PLUME_SHADER_PATH := "res://modules/common/juice/shaders/plume.gdshader"
const TRACER_SHADER_PATH := "res://modules/common/juice/shaders/tracer.gdshader"
const BEAM_SHADER_PATH := "res://modules/common/juice/shaders/beam.gdshader"
## Weapon ids that get the "mega beam" treatment (see beam.gdshader's
## mega_boost) — the two continuous beams built to melt capital ships and
## crack planets, not the everyday sustained/cryo lasers.
const MEGA_BEAM_IDS := ["hyper_beam", "planet_buster_beam"]

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
## Set by flight (the player's ship and every AI ship): the capacitor gets the
## [member JuiceSettings.weapon_sustain] recharge floor. Off in the builder,
## which should show a design's real power budget.
var sustain_fire := false
## Set by flight on the player's own ship only. (Checking the bound root's
## `systems` can't tell: an AI ship's root is the AiShip, whose `systems` is
## this sim too.) The player's bolts are drawn as bold streaks and keep only a
## trace of their spread.
var is_player_rig := false
## Set by flight while the player flies this (AI) ship ("fly as"). The player's
## shots are never slowed by a firing style (see [method _spawn_shot]).
var player_flown := false
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
## A world point every gun aims at when there is no [member target_ref]
## (Vector3.INF = none, aim down the nose). While set, every gun turns fully
## onto it and side/rear guns fire too: the slingshot profile's tap-to-shoot,
## where the hull tumbles and "the nose" means nothing.
var aim_override := Vector3.INF
## How this rig uses its weapon — a bullet-hell firing style rolled by the AI
## (see [AiFirePatterns.make] for the keys). Empty = the weapon's own cadence,
## one straight shot per gun. The player's rig never has one.
var fire_pattern: Dictionary = {}
## The fan's current turn, advanced by the pattern's spiral_deg each volley.
var _spiral_angle := 0.0
## Optional listener for every shot this and every other rig fires, for the
## flight test's "shots not straight" recorder ([ShotBugHunt]). Called with
## (rig, muzzle_origin, shot_dir, ideal_dir, weapon_id, is_beam). Unset in play.
static var shot_probe: Callable = Callable()
## Built tracer meshes by snapped (radius, length): a bullet-hell volley would
## otherwise run a SurfaceTool build for every single shot.
static var _tracer_mesh_cache: Dictionary = {}
static var _orb_core_mesh: SphereMesh = null
## Shared tracer and glow-head materials by colour, and head quads by size: a
## stream of shots used to build two fresh materials and a mesh per shot.
static var _tracer_mats: Dictionary = {}
static var _head_mats: Dictionary = {}
static var _head_meshes: Dictionary = {}
## Every live rig, for the whole-game enemy shot count ([method
## enemy_shots_live]). Untyped: it can briefly hold a freed rig.
static var _all_sims: Array = []
static var _enemy_live_frame := -1
static var _enemy_live_count := 0
## Hidden tracer nodes waiting to be reused (see [member
## JuiceSettings.shot_pooling]).
var _tracer_pool: Array[MeshInstance3D] = []
## As many as this rig can have in the air, so a long burst reaches a steady
## state and builds nothing new. Hidden nodes cost no drawing.
const TRACER_POOL_MAX := MAX_PROJECTILES
## Asked before this rig fires (once per frame that a gun is ready); false
## holds fire. An AI ship sets it to its off-screen rule ([method
## AiShip.fire_gate]). Never asked for the player's own guns.
var fire_gate: Callable = Callable()
## Whether the guns firing this frame are the player's — whichever ship they
## are flying. Set by [method _try_fire]; read by the shot builders below.
var _shooting_for_player := false
## [method boresight_point] for this frame (it is a ray cast, and a volley
## asked for it once per gun).
var _boresight_frame := -1
var _boresight_cached := Vector3.ZERO
## How fast guided shots accelerate toward their target, m/s².
const GUIDED_ACCEL := 700.0
## Live projectiles: {node, velocity, life, beam}.
var _shots: Array[Dictionary] = []
## Muzzle index -> its still-live beam entry from [member _shots], so a
## sustained/beam weapon's repeat-fire cooldown ticks top up one persistent
## beam instead of stacking a fresh [MeshInstance3D] (with its own
## independently re-rolled spread) on top of one still fading out — see
## [method _try_fire] and the beam branch of [method _spawn_shot].
var _active_beam_shot: Dictionary = {}
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
var _beam_shader: Shader
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
	_beam_shader = load(BEAM_SHADER_PATH) as Shader
	_all_sims.append(self)


func _exit_tree() -> void:
	_all_sims.erase(self)


## Enemy projectiles in flight across the whole game, for [member
## JuiceSettings.max_enemy_shots]. Counted once per frame and kept up to date
## by [method _launch] in between.
static func enemy_shots_live() -> int:
	var f := Engine.get_process_frames()
	if f != _enemy_live_frame:
		_enemy_live_frame = f
		var n := 0
		for sim: Variant in _all_sims:
			if is_instance_valid(sim) and not (sim as SystemsSim)._shooting_for_player:
				n += (sim as SystemsSim)._shots.size()
		_enemy_live_count = n
	return _enemy_live_count


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


## [method _make_tracer_mesh] through [member _tracer_mesh_cache]: sizes are
## snapped so a jittered flak pellet lands on one of a handful of meshes.
func _tracer_mesh_cached(radius: float, length: float) -> ArrayMesh:
	var r := snappedf(radius, 0.05)
	var l := snappedf(length, 0.5 if length < 20.0 else 4.0)
	var key := Vector2(r, l)
	var mesh := _tracer_mesh_cache.get(key) as ArrayMesh
	if mesh == null:
		mesh = _make_tracer_mesh(maxf(r, 0.02), maxf(l, 0.5))
		_tracer_mesh_cache[key] = mesh
	return mesh


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

	# Nothing to see (out of view or far off): the work below is the heaviest
	# per-hit cost in a fight — rings, bursts, an addon scene, a registry
	# blast, a sound — and ran for every hit anywhere.
	if not AddonVfx.worth_spawning(hit_pos, 2500.0):
		return
	# Screen shake only for the player's own hits, and less the further off
	# they land. Every hit by anyone used to shake the player's camera (a hit
	# on the player's own hull shakes it in [method FlightRoot.take_damage]).
	if _shooting_for_player:
		Juice.shake(shake_amt * AddonVfx.camera_falloff(hit_pos, 700.0))
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
	if sustain_fire:
		# Flight's combat floor (see [member JuiceSettings.weapon_sustain]).
		var w := get_active_weapon()
		var drain := float(w.get("cost", 1.0)) * float(w.get("fire_rate", 1.0)) \
			* maxf(float(_get_effective_muzzles().size()), 1.0)
		balance = maxf(balance, drain * JuiceSettings.weapon_sustain)
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


## The [member ShipPart.size_class] vocabulary, in ascending order, so a bigger
## ship can be handed a weapon at or below its own tier — see
## [method weapon_index_for_size].
const WEAPON_SIZE_TIERS := ["fighter", "corvette", "hauler", "capital"]

## An index into [constant WEAPONS] appropriate for a ship of [param
## size_class] (one of [constant WEAPON_SIZE_TIERS]) — the AI equivalent of a
## player picking a weapon that actually fits their hardpoints. A ship never
## gets something above its own tier (a fighter cannot roll antimatter_railgun).
## Below capital, the pool is biased toward the ship's own tier and the one
## below for variety; a capital-class ship's pool is capital weapons only —
## planet-buster beams, torpedoes, railguns — because "a mega ship *might* get
## a real planet destroyer" reads as a bug the first ten times it does not.
## See [AiShip._weapon_size_class] for how a ship's tier is chosen.
static func weapon_index_for_size(size_class: String, rng: RandomNumberGenerator) -> int:
	var max_tier := WEAPON_SIZE_TIERS.find(size_class)
	if max_tier < 0:
		max_tier = 0
	var top_tier := WEAPON_SIZE_TIERS.size() - 1
	var min_preferred_tier := max_tier if max_tier >= top_tier else max_tier - 1
	var candidates: Array[int] = []
	var preferred: Array[int] = []
	for i in WEAPONS.size():
		var w_tier := WEAPON_SIZE_TIERS.find(String(WEAPONS[i].get("size_class", "fighter")))
		if w_tier > max_tier:
			continue
		candidates.append(i)
		if w_tier >= min_preferred_tier:
			preferred.append(i)
	var pool := preferred if not preferred.is_empty() else candidates
	if pool.is_empty():
		return 0
	return pool[rng.randi() % pool.size()]


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
	var is_beam_weapon: bool = bool(active_w.get("beam", false))
	# A firing style's cadence. Not for beams: their interval is tuned against
	# their own life so a held beam never gaps (see the jitter note below).
	if not is_beam_weapon and not fire_pattern.is_empty():
		rate *= float(fire_pattern.get("rate_mult", 1.0))
	var beam_life: float = float(active_w.get("life", DEFAULT_SHOT_LIFE))
	_shooting_for_player = _fired_by_player()
	# The player's guns cycle faster than the same gun on an enemy (see
	# [member JuiceSettings.player_cooldown_mult]).
	if _shooting_for_player:
		rate /= maxf(JuiceSettings.player_cooldown_mult, 0.05)
	var gate_asked := false
	var gate_open := true

	# A fan or spiral comes out of at most two guns: from every barrel of a
	# 30-gun hull it is not a pattern to read and weave through, it is a wall.
	var fan_step := 1
	if not is_beam_weapon and int(fire_pattern.get("fan", 1)) > 1:
		fan_step = maxi(ceili(float(muzzles.size()) / 2.0), 1)

	for i in muzzles.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		if _cooldowns[i] > 0.0:
			continue
		if i % fan_step != 0:
			continue
		var entry: Dictionary = muzzles[i]
		if JuiceSettings.offaxis_guns_hold and aim_override == Vector3.INF and _is_offaxis(entry):
			continue
		# Asked once, at the first gun ready this frame: the whole-game enemy
		# shot cap and the ship's own rule (see [member fire_gate]).
		if not gate_asked:
			gate_asked = true
			gate_open = _gate_open()
		if not gate_open:
			continue
		if cost > energy:
			browned_out = true
			continue
		energy -= cost
		heat += cost * HEAT_PER_ENERGY
		# A little per-shot jitter so rapid weapons don't fire on a perfectly
		# metronomic beat. Beam weapons are excluded: their cooldown interval
		# is tuned close to (sometimes tighter than) their beam "life" so the
		# repeat-fire top-up below never gaps — see the beam branch — and
		# jitter could occasionally push the interval past that life.
		_cooldowns[i] = (1.0 / rate) if is_beam_weapon else (1.0 / rate) * randf_range(0.9, 1.1)
		# A sustained beam re-fires every cooldown tick while the trigger is
		# held; if the previous tick's beam instance is still alive, top up
		# its life instead of spawning a second overlapping instance (that
		# used to stack up to ~2 independently-aimed beams per muzzle and
		# read as scattered disconnected lines — see class doc).
		var live_beam: Dictionary = _active_beam_shot.get(i, {})
		# Untyped on purpose: the beam's node is queue_free'd in _advance_shots
		# without clearing this dict, so this can hold a stale ref to a freed
		# instance. Assigning that into a typed (Object) var throws "Trying to
		# assign invalid previously freed instance" before is_instance_valid
		# below ever runs.
		var live_node = live_beam.get("node")
		if is_beam_weapon and live_node != null and is_instance_valid(live_node):
			live_beam["life"] = beam_life
			live_beam["life_total"] = beam_life
			continue
		_spawn_shot(entry, active_w, i)
	
	if browned_out:
		_note("Capacitor empty — recharge required")
	elif _shots.size() >= MAX_PROJECTILES:
		_note("Projectile limit reached")
	else:
		_note("")


## How far the guns are through their cooldown: 0 just fired, 1 ready. The
## soonest gun counts, so a ship whose guns take turns reads ready whenever
## one of them is. Drawn round the HUD's gunsight.
func reload_progress() -> float:
	if _cooldowns.is_empty():
		return 1.0
	var w := get_active_weapon()
	var rate := maxf(float(w.get("fire_rate", 2.0)), 0.05)
	if not bool(w.get("beam", false)) and not fire_pattern.is_empty():
		rate *= float(fire_pattern.get("rate_mult", 1.0))
	if _shooting_for_player:
		rate /= maxf(JuiceSettings.player_cooldown_mult, 0.05)
	var soonest := INF
	for c: float in _cooldowns:
		soonest = minf(soonest, c)
	return clampf(1.0 - soonest * rate, 0.0, 1.0)


## Whether the capacitor holds enough for one more shot of the active weapon.
func has_energy_for_shot() -> bool:
	return energy >= float(get_active_weapon().get("cost", 1.0))


## Whether an enemy rig may fire this frame: under the whole-game shot cap and
## allowed by its ship ([member fire_gate]). Always true for the player's guns.
func _gate_open() -> bool:
	if _shooting_for_player:
		return true
	if enemy_shots_live() >= int(JuiceSettings.max_enemy_shots):
		return false
	return not fire_gate.is_valid() or bool(fire_gate.call())


## Aim direction for a shot leaving [param muzzle] toward [param aim_point],
## clamped to [constant MUZZLE_CONVERGENCE_CONE] of the muzzle's own facing —
## see that constant's doc. Also doubles as the old "don't fire backwards"
## guard: the result can never be more than the cone angle from the muzzle's
## own forward, so an aim point behind the ship cannot yank a shot around.
## Distance down the nose where the guns converge with nothing in the way.
const BORESIGHT_DISTANCE := 900.0


## Where the guns converge when nothing is locked: straight down the ship's
## nose, stopped at the first thing in the way within
## [constant BORESIGHT_DISTANCE]. The HUD draws its gunsight here.
func boresight_point() -> Vector3:
	var frame := Engine.get_process_frames()
	if frame == _boresight_frame:
		return _boresight_cached
	_boresight_frame = frame
	_boresight_cached = _boresight_uncached()
	return _boresight_cached


func _boresight_uncached() -> Vector3:
	var xf := _muzzle_frame()
	var from := xf.origin
	var fwd := -xf.basis.z.normalized()
	var far := from + fwd * BORESIGHT_DISTANCE
	var w3d := get_world_3d() if is_inside_tree() else null
	if w3d == null or w3d.direct_space_state == null:
		return far
	var ray := PhysicsRayQueryParameters3D.create(from + fwd * 2.0, far)
	if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_collider_rid"):
		ray.exclude = [_root.model.get_collider_rid()]
	var hit := w3d.direct_space_state.intersect_ray(ray)
	# Never converge closer than a few hull lengths: a rock grazing the nose
	# would otherwise cross the guns into an X right in front of the camera.
	if not hit.is_empty() and from.distance_to(hit["position"]) > 60.0:
		return hit["position"]
	return far


func _converge_dir(muzzle: Transform3D, aim_point: Vector3) -> Vector3:
	var muzzle_fwd := -muzzle.basis.z.normalized()
	var to_aim := aim_point - muzzle.origin
	if to_aim.length_squared() < 0.0001:
		return muzzle_fwd
	to_aim = to_aim.normalized()
	# The cone is a dial now (see [member JuiceSettings.muzzle_convergence_deg]);
	# the constant is only the historical default.
	var cone := deg_to_rad(JuiceSettings.muzzle_convergence_deg)
	if aim_override != Vector3.INF:
		cone = PI
	if muzzle_fwd.angle_to(to_aim) <= cone:
		return to_aim
	var axis := muzzle_fwd.cross(to_aim)
	if axis.length_squared() < 0.0001:
		# aim_point is directly ahead or behind the muzzle: any perpendicular
		# axis works as the rotation plane.
		axis = muzzle_fwd.cross(Vector3.UP if absf(muzzle_fwd.y) < 0.95 else Vector3.RIGHT)
	return muzzle_fwd.rotated(axis.normalized(), cone)


## A side or rear mount: its barrel points more than [constant
## JuiceSettings.OFFAXIS_HOLD_DEG] away from the ship's nose (both in hull
## space, so no world transform is needed).
static func _is_offaxis(entry: Dictionary) -> bool:
	var xf: Transform3D = entry.get("xform", Transform3D())
	var fwd := -xf.basis.z
	if fwd.length_squared() < 1e-6:
		return false
	return rad_to_deg(fwd.normalized().angle_to(Vector3.FORWARD)) > JuiceSettings.OFFAXIS_HOLD_DEG


## The frame the guns hang off, in world space. With
## [member JuiceSettings.shot_stable_frame] on this is the flight model's own
## transform carried down to the hull root's rest placement — the drawn hull
## squashes non-uniformly and springs about on hits, and reading the muzzles off
## it sheared every canted gun off its line mid-fight. Off (or with no flight
## model, as in the builder) it is the drawn hull root, the old behaviour.
func _muzzle_frame() -> Transform3D:
	var root_node: Node3D = _view.root if _view != null and _view.root != null and is_instance_valid(_view.root) else self
	if not JuiceSettings.shot_stable_frame or root_node == self:
		return root_node.global_transform
	var m: Variant = _root.get("model") if _root != null else null
	if not (m is FlightModel) or not is_instance_valid(m):
		return root_node.global_transform
	return _stable_frame_of(m as FlightModel, root_node)


## Where a perfect gun at mount [param xform] would send its shot: from its
## barrel in the ship's steady frame to [param aim] (a target's lead point), or
## with [code]Vector3.INF[/code], straight down the steady nose line. Fixed
## whatever the aim switches say, so [member shot_probe] measures every
## suspect against the same yardstick.
func _ideal_dir(xform: Transform3D, aim: Vector3) -> Vector3:
	var frame := _muzzle_frame()
	var m: Variant = _root.get("model") if _root != null else null
	var root_node: Node3D = _view.root if _view != null and _view.root != null and is_instance_valid(_view.root) else null
	if m is FlightModel and is_instance_valid(m) and root_node != null:
		frame = _stable_frame_of(m as FlightModel, root_node)
	var origin := (frame * xform).origin
	if aim == Vector3.INF:
		aim = frame.origin - frame.basis.z.normalized() * BORESIGHT_DISTANCE
	var to := aim - origin
	return to.normalized() if to.length_squared() > 0.0001 else -frame.basis.z.normalized()


## The hull root's placement relative to the flight model with every visual
## wobble (squash scale, knockback offset) taken out. The holder between them
## is the model's squash visual; its rest position is all that is kept.
static func _stable_frame_of(m: FlightModel, root_node: Node3D) -> Transform3D:
	var chain := Transform3D()
	var n: Node = root_node
	var guard := 0
	while n != null and n != m and guard < 8:
		var n3 := n as Node3D
		if n3 != null:
			var local := n3.transform
			if n3 == m._visual:
				local = Transform3D(Basis(), m._visual_rest_pos)
			chain = local * chain
		n = n.get_parent()
		guard += 1
	if n != m:
		return root_node.global_transform
	return m.global_transform * chain


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
	# A firing style reshapes the shot itself: slower, bigger, longer-lived.
	var pat := fire_pattern
	var players := is_player_rig or player_flown
	if not pat.is_empty() and not is_beam:
		# A style's slow shots are for enemies to dodge; the player flying that
		# style keeps its look (size, life) but shoots at full speed.
		var mult := float(pat.get("speed_mult", 1.0))
		speed *= maxf(mult, 1.0) if players else mult
		life *= float(pat.get("life_mult", 1.0))
		thickness *= float(pat.get("size_mult", 1.0))
		length *= lerpf(1.0, float(pat.get("size_mult", 1.0)), 0.5)
	# The gun frame — see [method _muzzle_frame] for why it is not simply the
	# drawn hull any more.
	var muzzle := _muzzle_frame() * xform

	# Converge every gun on one point: the locked target's lead point, or
	# down the ship's own nose line (what the HUD's gunsight marks). Aiming
	# down the camera's centre instead made every volley wander with the chase
	# camera's lag and lead, and a sightline that flicked between near debris
	# and the 1200 m fallback scattered shots from one frame to the next.
	var aim_point := boresight_point() if aim_override == Vector3.INF else aim_override
	if target_ref != null and is_instance_valid(target_ref):
		var t_vel := Vector3.ZERO
		if target_ref.get("velocity") != null:
			t_vel = target_ref.get("velocity")
		elif target_ref.get("model") != null and target_ref.get("model") is FlightModel:
			t_vel = (target_ref.get("model") as FlightModel).velocity
		var own_vel := Vector3.ZERO
		if _root != null and _root.get("model") != null and _root.model != null:
			own_vel = _root.model.velocity
		aim_point = target_ref.global_position
		# Instant-hit guns land where the target is now; travelling shots lead
		# it by their flight time (two refinement passes are plenty).
		var instant := bool(weapon_data.get("beam", false)) or bool(weapon_data.get("hitscan", false))
		if not instant and speed > 1.0:
			var rel := t_vel - own_vel
			for _i in 2:
				aim_point = target_ref.global_position + rel * (muzzle.origin.distance_to(aim_point) / speed)

	var dir := _converge_dir(muzzle, aim_point)
	# What a perfect gun would do — straight from its barrel tip to the aim
	# point, through the ship's steady frame. Only for [member shot_probe].
	var ideal_dir := dir
	if shot_probe.is_valid():
		var has_t := target_ref != null and is_instance_valid(target_ref)
		ideal_dir = _ideal_dir(xform, aim_point if has_t else Vector3.INF)

	# Apply spread if defined. The player's guns keep only a trace of it: a
	# full random cone read as sloppy, not as spray.
	var spread := deg_to_rad(float(weapon_data.get("spread", 0.0)))
	if String(weapon_data.get("type", "")) != "flak":
		spread *= JuiceSettings.player_spread_mult if _shooting_for_player else JuiceSettings.enemy_spread_mult
	if spread > 0.0:
		dir = dir.rotated(muzzle.basis.x.normalized(), randf_range(-spread, spread))
		dir = dir.rotated(muzzle.basis.y.normalized(), randf_range(-spread, spread))
	# A style's own aim wobble, so a stream sprays a little instead of every
	# shot threading the same needle.
	if not pat.is_empty() and not is_beam:
		var err := deg_to_rad(float(pat.get("aim_error_deg", 0.0)))
		if err > 0.0:
			dir = dir.rotated(muzzle.basis.x.normalized(), randf_range(-err, err))
			dir = dir.rotated(muzzle.basis.y.normalized(), randf_range(-err, err))

	if shot_probe.is_valid():
		shot_probe.call(self, muzzle.origin, dir, ideal_dir, String(weapon_data.get("id", "")), is_beam)

	# Muzzle light flash, sparks, and kickback, at the barrel tip.
	_muzzle_fx(muzzle, dir, color, weapon_data)

	# Audio: play weapon sound (cockpit punch for player, spatial 3D for AI).
	# A style spaces its sounds out (a stream is a hiss, not a machine gun)
	# and pitches them, so a fight is a mix of voices.
	var audio := SpaceAudio.instance()
	if audio != null:
		var is_p: bool = (_root != null and _root.get("systems") == self)
		audio.play_weapon_fire(
			String(weapon_data.get("type", "laser")), muzzle.origin, is_p,
			String(weapon_data.get("id", "")), get_instance_id(),
			float(pat.get("sound_gap_mult", 1.0)), float(pat.get("pitch_mult", 1.0))
		)

	# Inherit ship's velocity so shooting always goes ahead of the ship
	var ship_vel := Vector3.ZERO
	if _root != null and _root.get("model") != null:
		var m = _root.model
		if m != null and m.get("velocity") != null:
			ship_vel = m.velocity
			# Physical recoil impulse on the ship, spread over its muzzles so a
			# many-gun design isn't braked by every volley (see
			# [member JuiceSettings.player_recoil]).
			var recoil: float = float(weapon_data.get("recoil", 1.0))
			var muzzle_n := maxf(float(_get_effective_muzzles().size()), 1.0)
			m.velocity -= dir * recoil * JuiceSettings.player_recoil / sqrt(muzzle_n)

	# Guarantee bullet velocity always exceeds forward ship velocity — except
	# for a style's deliberately slow shots, which only need to clear the hull
	# (they already carry the ship's own velocity).
	var forward_ship_speed := maxf(0.0, ship_vel.dot(dir))
	var eff_speed := maxf(speed, forward_ship_speed + 350.0)
	if float(pat.get("speed_mult", 1.0)) < 1.0 and not players:
		eff_speed = maxf(speed, 60.0)
	if players:
		eff_speed = maxf(eff_speed, JuiceSettings.player_min_shot_speed)

	# One trigger, one or many shots: a style's fan lays several out in an arc
	# (side to side, or round the aim line and turning each volley for a
	# spiral). Beams, flak and the heavy one-offs stay single.
	var fan := int(pat.get("fan", 1))
	var w_type := String(weapon_data.get("type", ""))
	if is_beam or w_type == "flak" or w_type == "singularity" or bool(weapon_data.get("is_nova", false)):
		fan = 1
	if fan <= 1:
		_launch(muzzle, dir, weapon_data, muzzle_index, entry, spread, ship_vel, eff_speed,
			life, thickness, length, color, bool(pat.get("orb", false)))
		return
	var arc := deg_to_rad(float(pat.get("fan_deg", 30.0)))
	var ring := bool(pat.get("ring", false))
	_spiral_angle = fmod(_spiral_angle + deg_to_rad(float(pat.get("spiral_deg", 0.0))), TAU)
	var side := muzzle.basis.x.normalized()
	var up := muzzle.basis.y.normalized()
	for k in fan:
		var k_dir := dir
		if ring:
			var a := _spiral_angle + TAU * float(k) / float(fan)
			var axis := (side * cos(a) + up * sin(a)).normalized()
			k_dir = dir.rotated(axis, arc * 0.5)
		else:
			var t := (float(k) / float(fan - 1)) - 0.5
			k_dir = dir.rotated(up.rotated(dir, _spiral_angle), arc * t)
		_launch(muzzle, k_dir, weapon_data, muzzle_index, entry, spread, ship_vel, eff_speed,
			life, thickness, length, color, bool(pat.get("orb", false)))


## Put one shot in the world along [param dir] from [param muzzle]. Split out of
## [method _spawn_shot] so a fan can launch several per trigger; everything
## about aiming, sound and recoil happened once, there.
func _launch(muzzle: Transform3D, dir: Vector3, weapon_data: Dictionary, muzzle_index: int,
		entry: Dictionary, spread: float, ship_vel: Vector3, eff_speed: float,
		life: float, thickness: float, length: float, color: Color, as_orb: bool) -> void:
	if _shots.size() >= MAX_PROJECTILES:
		return
	# The whole-game enemy cap is per shot too: a 60-gun volley checked once
	# at the trigger went 60 past it.
	if not _shooting_for_player and _enemy_live_count >= int(JuiceSettings.max_enemy_shots):
		return
	var is_beam: bool = bool(weapon_data.get("beam", false))
	# Spawn projectile directly at muzzle tip so lasers emerge directly from gun barrels
	var world := muzzle
	world.origin = muzzle.origin + dir * 0.45
	# Drawn along its flight, not along the barrel: a canted gun's shot is
	# turned onto the gunsight line (see [method _converge_dir]), and a tracer
	# left pointing down the barrel flew visibly crooked — sideways through
	# the air at the barrel's angle. The hull's scale is kept.
	if dir.length_squared() > 1e-6:
		var up := muzzle.basis.y.normalized()
		if absf(up.dot(dir.normalized())) > 0.98:
			up = muzzle.basis.x.normalized()
		world.basis = Basis.looking_at(dir, up) * Basis.from_scale(muzzle.basis.get_scale())
	if not _shooting_for_player:
		_enemy_live_count += 1

	# Hitscan weapons land the instant they fire, exactly like a beam's own
	# raycast does — this is what makes a fast weapon actually connect from a
	# ship moving quickly instead of depending on its travelling tracer
	# catching up to (or outrunning) the target. The tracer spawned below for
	# these is purely cosmetic: the hit already happened.
	# Enemy guns with real projectiles on are never instant: a shot the player
	# cannot see coming cannot be dodged (see [member
	# JuiceSettings.ai_real_projectiles]).
	var is_hitscan: bool = bool(weapon_data.get("hitscan", false)) and not is_beam
	if is_hitscan and JuiceSettings.ai_real_projectiles and not _shooting_for_player:
		is_hitscan = false
	if is_hitscan:
		_check_shot_hit({"weapon": weapon_data}, world.origin, world.origin + dir * 50000.0)

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
			p_inst.mesh = _tracer_mesh_cached(thickness, length * randf_range(0.8, 1.25))
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
		var is_mega: bool = MEGA_BEAM_IDS.has(String(weapon_data.get("id", "")))
		var inst := MeshInstance3D.new()
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Wider than the old outer tube: the shader now paints its own bright
		# core and soft glow falloff on this one mesh instead of needing a
		# second, narrower mesh layered inside it for the core.
		inst.mesh = _make_beam_mesh(thickness * (2.0 if is_mega else 1.5))
		var mat := ShaderMaterial.new()
		if _beam_shader != null:
			mat.shader = _beam_shader
		mat.set_shader_parameter("beam_color", color)
		mat.set_shader_parameter("mega_boost", 1.0 if is_mega else 0.0)
		inst.material_override = mat
		# No separate inner "white-hot core" mesh any more: beam.gdshader paints
		# its own bright centre and soft falloff on this one mesh (see its
		# core_color/radial blend), which was doing the same job as a second,
		# narrower _make_beam_mesh layered inside — one draw call instead of two.
		# Added to the tree here, before global_position/look_at touch it below:
		# a beam that never misses (no cell_size guard, fires every frame it is
		# held) hit this node's look_at() outside the tree constantly once
		# something actually made it reach a target — see the same fix in
		# _spawn_planet_crater_blast.
		_shot_root.add_child(inst)

		var w3d := get_world_3d()
		if w3d == null:
			return
		var beam_len := 50000.0
		var space_state := w3d.direct_space_state
		var query := PhysicsRayQueryParameters3D.create(world.origin, world.origin + dir * beam_len)
		if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_collider_rid"):
			query.exclude = [_root.model.get_collider_rid()]
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

		var beam_shot := {
			"node": inst, "velocity": ship_vel, "life": life,
			"life_total": life, "beam": true, "weapon": weapon_data,
			"hit_target": hit_target, "hit_pos": hit_pos, "dir": dir,
			"ship_vel": ship_vel, "hit_flare_mat": hf_mat,
			"hit_flare": hit_flare, "entry": entry, "spread": spread,
		}
		_shots.append(beam_shot)
		_active_beam_shot[muzzle_index] = beam_shot
		return

	# Bolt / projectile
	var w_kind := String(weapon_data["type"])
	var orb_shot := as_orb and w_kind != "missile" and w_kind != "singularity"
	var plain := not orb_shot and w_kind != "plasma" and w_kind != "missile" and w_kind != "singularity"
	if plain and _shooting_for_player:
		# A streak the eye can follow: long enough for its speed to read
		# (about a thirtieth of a second of travel) and thick enough to see
		# from the chase camera. The raw 5 m sliver at 1100 m/s was gone
		# before it registered, so the guns looked like they fired nothing.
		length = maxf(length, eff_speed * 0.03)
		thickness = maxf(thickness * 2.4, 0.55)
	var inst: MeshInstance3D = _tracer_node(thickness, length, color) if plain else MeshInstance3D.new()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if plain:
		pass  # Built (or taken from the pool) by [method _tracer_node] above.
	elif orb_shot:
		# A bullet-hell shot: a hot core in a wide soft halo, readable at any
		# angle and plainly slower than a tracer — the thing to weave through.
		_build_orb(inst, maxf(thickness * 1.3, 0.8), color)
	elif weapon_data["type"] == "plasma":
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


	inst.transform = world
	if inst.get_parent() == null:
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
	# A tracer that picked up an addon layer is not reused: the layer would
	# ride along on its next shot.
	if inst.get_child_count() > 1:
		inst.remove_meta("pooled")

	_shots.append({
		"node": inst,
		"velocity": dir * eff_speed + ship_vel,
		"life": life,
		"beam": false,
		"guided": bool(weapon_data.get("guided", false)),
		"weapon": weapon_data,
		"trail_timer": 0.0,
		"hitscan_resolved": is_hitscan,
		# Only a fat shot gets a body: a thin ray is exact enough for a tracer,
		# but an orb visibly touching a hull and passing through it reads as a
		# cheat against the player.
		"radius": maxf(thickness * 1.3, 0.8) if as_orb else 0.0,
	})


static var _orb_mats: Dictionary = {}


## Dress [param inst] as a glowing orb of [param radius] metres: one shared
## unit sphere for the core and a billboard halo, both with materials cached
## per colour so a screen full of them is a handful of materials.
func _build_orb(inst: MeshInstance3D, radius: float, color: Color) -> void:
	if _orb_core_mesh == null:
		_orb_core_mesh = SphereMesh.new()
		_orb_core_mesh.radius = 0.5
		_orb_core_mesh.height = 1.0
		_orb_core_mesh.radial_segments = 12
		_orb_core_mesh.rings = 8
	var key := color.to_html()
	var mats: Array = _orb_mats.get(key, [])
	if mats.is_empty():
		var core_mat := StandardMaterial3D.new()
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_mat.albedo_color = color.lerp(Color.WHITE, 0.75)
		var halo_mat := StandardMaterial3D.new()
		halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		halo_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		halo_mat.albedo_texture = _get_glow_head_texture()
		halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mats = [core_mat, halo_mat]
		_orb_mats[key] = mats
	var core := MeshInstance3D.new()
	core.mesh = _orb_core_mesh
	core.material_override = mats[0]
	core.scale = Vector3.ONE * radius * 1.2
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.add_child(core)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 5.0
	halo.mesh = q
	halo.material_override = mats[1]
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.add_child(halo)


func _muzzle_fx(world: Transform3D, dir: Vector3, color: Color, weapon_data: Dictionary) -> void:
	var spark_s: float = float(weapon_data.get("spark_scale", 1.0))
	var l_radius: float = float(weapon_data.get("light_radius", 10.0))
	var l_dur: float = float(weapon_data.get("light_duration", 0.15))
	var kick: float = float(weapon_data.get("kick", SHOT_KICK))
	var shake: float = float(weapon_data.get("shake", SHOT_SHAKE))
	var w_id: String = String(weapon_data.get("id", ""))
	var is_cryo: bool = bool(weapon_data.get("is_cryo", false))
	var is_flame: bool = bool(weapon_data.get("is_solar_flame", false))

	# Per-shot muzzle sparks used to fire a full particle burst on every single
	# shot from every weapon — the highest-frequency VFX call in the game
	# (up to ~9-10/sec per muzzle) for a flourish nobody asked for; the light
	# pop + kick + shake below already sell the muzzle flash. Each weapon's
	# other signature flourish (a ring, embers, vapour) stays — those are
	# rarer (only a handful of exotic, slow-firing weapons) and visually
	# distinct from a plain spark.
	if is_cryo:
		Juice.ring(world, spark_s * 1.4, Color(0.3, 0.85, 1.0), 0.18)
	elif is_flame:
		Juice.burst(BurstPresets.Preset.EMBERS, world, spark_s * 1.8, Color(1.0, 0.45, 0.1))
		Juice.burst(BurstPresets.Preset.VAPOUR, world, spark_s * 0.9, Color(0.9, 0.35, 0.05, 0.5))
	elif w_id == "gauss_slugger" or w_id == "antimatter_railgun":
		Juice.ring(world, spark_s * 2.2, Color(0.75, 0.9, 1.0), 0.22)
	elif w_id == "gamma_burst":
		Juice.ring(world, spark_s * 2.5, Color(0.5, 1.0, 0.9), 0.25)

	# The camera is the player's: only their own guns kick and shake it. Every
	# enemy shot anywhere used to kick it too, so the view swung about the
	# moment a few ships opened fire on the player.
	if _shooting_for_player:
		Juice.light_pop(world.origin, color, l_radius, l_dur)
		Juice.kick(dir, kick)
		Juice.shake(shake)
	elif AddonVfx.worth_spawning(world.origin, 900.0):
		Juice.light_pop(world.origin, color, l_radius, l_dur)


## World-space position of every currently live shot this rig has fired.
## Used by [FlightRoot] to detect near-misses for the near-miss slowmo juice
## effect — it has no other way to see into another ship's private [member
## _shots].
func live_shot_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for shot in _shots:
		var node := shot.get("node") as Node3D
		if node != null and is_instance_valid(node):
			out.append(node.global_position)
	return out


func _advance_shots(delta: float) -> void:
	var survivors: Array[Dictionary] = []
	for shot in _shots:
		var life: float = float(shot["life"]) - delta
		var node := shot["node"] as MeshInstance3D
		if life <= 0.0 or node == null or not is_instance_valid(node):
			if node != null and is_instance_valid(node):
				_retire_shot_node(node)
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
			var b_world := _muzzle_frame() * xf
			var b_origin := b_world.origin

			# Aim convergence towards the target, or the gunsight — the same
			# point the beam was spawned at. It used to re-aim every frame along
			# the *camera's* centre line instead, so a held beam flicked between
			# two aims (spawn: gunsight, then: camera) and an AI ship's beam
			# followed the player's camera. Kept behind a switch to reproduce.
			var b_aim := Vector3.ZERO
			if target_ref != null and is_instance_valid(target_ref):
				b_aim = target_ref.global_position
			elif aim_override != Vector3.INF:
				b_aim = aim_override
			elif JuiceSettings.beam_camera_aim:
				var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
				if cam != null and is_instance_valid(cam):
					b_aim = cam.global_position - cam.global_transform.basis.z * 1200.0
				else:
					b_aim = boresight_point()
			else:
				b_aim = boresight_point()

			var b_dir := _converge_dir(b_world, b_aim)
			if shot_probe.is_valid():
				var has_t := target_ref != null and is_instance_valid(target_ref)
				shot_probe.call(self, b_origin, b_dir, _ideal_dir(xf, b_aim if has_t else Vector3.INF),
					String(weapon.get("id", "")), true)

			var w3d := get_world_3d()
			var b_len := 50000.0
			var b_target: Object = null
			var b_hit_pos := b_origin + b_dir * b_len
			if w3d != null:
				var s_state := w3d.direct_space_state
				var q := PhysicsRayQueryParameters3D.create(b_origin, b_origin + b_dir * b_len)
				if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_collider_rid"):
					q.exclude = [_root.model.get_collider_rid()]
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
			var b_mat := node.material_override as ShaderMaterial
			if b_mat != null:
				b_mat.set_shader_parameter("opacity", alpha)
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
		
		# Check raycast hit along path — skipped for a hitscan shot, which
		# already resolved its hit at the muzzle the instant it fired; its
		# tracer here is purely cosmetic and must not land (or deal damage) a
		# second time when it visually reaches something.
		var hit_happened := false
		if not bool(shot.get("hitscan_resolved", false)):
			hit_happened = _check_shot_hit(shot, prev_pos, next_pos)
			if not hit_happened and float(shot.get("radius", 0.0)) > 0.0:
				hit_happened = _check_orb_graze(shot, prev_pos, next_pos)
		if hit_happened:
			_retire_shot_node(node)
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
	elif target is Node and _ai_ship_of(target as Node) != null:
		# Resolved through the parents: what the ray strikes is a ship's
		# collider body (a StaticBody3D), never the AiShip itself, so testing
		# the collider's own class let a beam pass through ships unharmed.
		_ai_ship_of(target as Node).take_damage(float(weapon.get("damage", 30.0)) * delta * 15.0, _fired_by_player(), self)
	elif target is Node and _enemy_fire_sink(target as Node) != null:
		# An enemy beam held on the player's hull: a steady burn, far gentler
		# per second than on a ship (the player cannot shrug off 15x).
		if JuiceSettings.ai_real_projectiles:
			_enemy_fire_sink(target as Node).take_enemy_fire(
				float(weapon.get("damage", 30.0)) * delta * 4.0 * JuiceSettings.enemy_shot_damage_scale, hit_pos, self)
	elif target is StaticBody3D:
		var gen := _find_large_craft_gen(target as Node3D)
		if gen != null:
			gen.shatter_at(hit_pos, 18.0, dir * 25.0)
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
	if _root != null and _root.get("model") != null and _root.model != null and _root.model.has_method("get_collider_rid"):
		_cached_ray_query.exclude = [_root.model.get_collider_rid()]
	else:
		_cached_ray_query.exclude = []
	var hit := space_state.intersect_ray(_cached_ray_query)
	var by_player := _fired_by_player()
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		# An enemy shot has to pass near the middle of the player's hull: a
		# clip of a wingtip flies on as a near miss.
		if by_player or not _grazes_only_player(collider, from, to, float(shot.get("radius", 0.0))):
			_on_hit_target(shot, collider, hit_pos, dir)
			return true
	elif by_player and _player_shot_graze(shot, from, to):
		return true
	
	var planet_hit := _check_planet_intersect(from, dir, dist)
	if planet_hit.has("planet"):
		_on_hit_planet(shot, planet_hit["planet"], planet_hit["point"], dir)
		return true
	
	return false


## Whether [param collider] is the player's hull and the segment misses its
## [member JuiceSettings.enemy_shot_hit_scale] core — an enemy shot that only
## clipped the player's outline.
func _grazes_only_player(collider: Object, from: Vector3, to: Vector3, shot_radius: float) -> bool:
	if not (collider is Node) or _enemy_fire_sink(collider as Node) == null:
		return false
	var n := collider as Node
	while n != null and not (n is FlightModel):
		n = n.get_parent()
	if n == null:
		return false
	var c := (n as FlightModel).global_position
	var core := _body_radius(n) * JuiceSettings.enemy_shot_hit_scale + shot_radius * 0.5
	return _segment_distance(from, to, c) > core


## The player's shot passing within [member JuiceSettings.player_shot_hit_scale]
## × a ship's radius counts as a hit on it (the nearest along the shot). Only
## ships that aren't friendly to the player, and never the hull firing.
func _player_shot_graze(shot: Dictionary, from: Vector3, to: Vector3) -> bool:
	var scale := JuiceSettings.player_shot_hit_scale
	if scale <= 0.0 or not is_inside_tree():
		return false
	var seg := to - from
	var len_sq := maxf(seg.length_squared(), 1e-6)
	var best: AiShip = null
	var best_t := INF
	var extra := float(shot.get("radius", 0.0))
	for node in get_tree().get_nodes_in_group("ai_ships"):
		var ship := node as AiShip
		if ship == null or not ship._alive or ship.systems == self or not ship.is_inside_tree():
			continue
		if ship.attitude_to_player() == AiShip.Attitude.FRIENDLY:
			continue
		var c := ship.global_position
		var t := clampf((c - from).dot(seg) / len_sq, 0.0, 1.0)
		if t >= best_t:
			continue
		if (from + seg * t).distance_to(c) <= _body_radius(ship) * scale + extra:
			best = ship
			best_t = t
	if best == null:
		return false
	_on_hit_target(shot, best, from + seg * best_t, seg.normalized())
	return true


static func _segment_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var seg := to - from
	var t := clampf((point - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	return (from + seg * t).distance_to(point)


## A fat shot (an orb) touching its target's hull without the thin centre ray
## striking it: the segment's closest approach to the target centre against
## the orb's radius plus about half the hull's. Only the rig's own target is
## tested — a stray orb grazing a bystander is left to the ray.
func _check_orb_graze(shot: Dictionary, from: Vector3, to: Vector3) -> bool:
	if target_ref == null or not is_instance_valid(target_ref) or not target_ref.is_inside_tree():
		return false
	var c := target_ref.global_position
	var seg := to - from
	var t := clampf((c - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	var closest := from + seg * t
	var reach := float(shot.get("radius", 0.0)) + _body_radius(target_ref) * 0.55
	if not (target_ref is AiShip) and not _fired_by_player():
		# At the player: the smaller enemy hitbox.
		reach = float(shot.get("radius", 0.0)) * 0.5 + _body_radius(target_ref) * JuiceSettings.enemy_shot_hit_scale
	if closest.distance_to(c) > reach:
		return false
	_on_hit_target(shot, target_ref, closest, seg.normalized())
	return true


## Whoever takes enemy fire for the player's own hull (the flight root) when
## [param node] is that hull or part of it, else null. The walk must pass
## through the player's [FlightModel] first: rocks and planets live under the
## flight root too, and a shot hitting one of those is not a hit on the player.
## Stops at an [AiShip] — a ship the player is piloting takes hits as itself.
static func _enemy_fire_sink(node: Node) -> Node:
	var n := node
	var through_hull := false
	while n != null:
		if n is AiShip:
			return null
		if n is FlightModel:
			through_hull = (n as FlightModel).is_player()
			if not through_hull:
				return null
		elif through_hull and n.has_method("take_enemy_fire"):
			return n
		n = n.get_parent()
	return null


static func _ai_ship_of(node: Node) -> AiShip:
	var n := node
	var guard := 0
	while n != null and guard < 10:
		if n is AiShip:
			return n as AiShip
		n = n.get_parent()
		guard += 1
	return null


static func _body_radius(node: Node) -> float:
	var m: Variant = node if node is FlightModel else node.get("model")
	if m is FlightModel and is_instance_valid(m) and (m as FlightModel)._phys != null:
		return (m as FlightModel)._phys.radius
	return 3.0


func _on_hit_target(shot: Dictionary, collider: Object, hit_pos: Vector3, dir: Vector3) -> void:
	var w: Dictionary = shot.get("weapon", get_active_weapon())
	var dmg: float = float(w.get("damage", 25.0))
	var col: Color = w.get("color", Color.CYAN)

	_spawn_impact_explosion(hit_pos, -dir, w)

	# Walk parent chain to identify target
	var target_node = collider
	while target_node != null:
		if target_node is AiShip:
			(target_node as AiShip).take_damage(dmg, _fired_by_player(), self)
			if target_node.get("model") != null:
				target_node.model.velocity += dir * (dmg * 0.15)
			return
		# The player's own hull (the flight root owns its hit points). It
		# decides what counts — friendly fire, the off-screen mercy — so the
		# shot only reports it. Scaled down: the player's guns deal the full
		# per-shot damage, an enemy's are tuned by their own dial.
		if target_node is FlightModel:
			var sink := _enemy_fire_sink(target_node)
			if sink != null:
				if JuiceSettings.ai_real_projectiles:
					sink.take_enemy_fire(dmg * JuiceSettings.enemy_shot_damage_scale, hit_pos, self)
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


## Whether these are the guns the player is firing: the player's own ship, or
## an AI ship they have taken control of. Hits from them count as the
## player's (kill cam, debugger damage dials).
func _fired_by_player() -> bool:
	# An AI ship's sim is bound to the AiShip itself, whose `systems` is this
	# very sim — so walk up to whatever owns the "which guns are the player's"
	# answer (the flight root) instead of trusting the bound root.
	var n: Node = _root
	while n != null:
		if n.has_method("active_systems"):
			return n.active_systems() == self
		n = n.get_parent()
	return false


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
			planet.react_face("ouch", 0.5)
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
		# Added to the tree before global_position is touched: top_level's
		# global_position setter resolves through the tree, and setting it on
		# a not-yet-parented node was a latent "!is_inside_tree()" warning that
		# planet hits simply never used to reach.
		_shot_root.add_child(rock)
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

	# The face rides out the same way a destroyed ship's does (see
	# [member AiShip._face]'s doc): freed from the planet before it hides, so
	# the "dizzy" look and the confetti pop actually get a frame on screen
	# instead of vanishing with the rest of the node in the same tick.
	var dying_face := planet.detach_face()
	if dying_face != null:
		_shot_root.add_child(dying_face)
		dying_face.global_position = p_pos
		dying_face.freeze("dizzy")
		get_tree().create_timer(1.8).timeout.connect(dying_face.queue_free)
	Whimsy.confetti(_shot_root, p_pos, 5.0)

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
		if node != null and is_instance_valid(node):
			_retire_shot_node(node)
	_shots.clear()


## A plain tracer, ready to place: a hidden one from [member _tracer_pool] when
## there is one, else a new one. Its mesh and materials are shared (by size and
## colour), so a shot costs no new resources either way.
func _tracer_node(thickness: float, length: float, color: Color) -> MeshInstance3D:
	var inst: MeshInstance3D = null
	while inst == null and not _tracer_pool.is_empty():
		var cand: MeshInstance3D = _tracer_pool.pop_back()
		if is_instance_valid(cand):
			inst = cand
	if inst == null:
		inst = MeshInstance3D.new()
		var head := MeshInstance3D.new()
		head.name = "GlowHead"
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.add_child(head)
	inst.mesh = _tracer_mesh_cached(thickness, length)
	var mat := _tracer_mats.get(color) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		if _tracer_shader != null:
			mat.shader = _tracer_shader
		mat.set_shader_parameter("beam_color", color)
		mat.set_shader_parameter("head_position", 1.0)
		_tracer_mats[color] = mat
	inst.material_override = mat
	# Soft circular head glow billboard.
	var head_node := inst.get_child(0) as MeshInstance3D
	var head_size := snappedf(maxf(thickness * 4.5, 1.2), 0.1)
	var quad := _head_meshes.get(head_size) as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		quad.size = Vector2(head_size, head_size)
		_head_meshes[head_size] = quad
	head_node.mesh = quad
	var head_mat := _head_mats.get(color) as StandardMaterial3D
	if head_mat == null:
		head_mat = StandardMaterial3D.new()
		head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		head_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		head_mat.albedo_color = color
		head_mat.albedo_texture = _get_glow_head_texture()
		head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		head_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_head_mats[color] = head_mat
	head_node.material_override = head_mat
	head_node.position = Vector3(0.0, 0.0, -length * 0.5)
	inst.visible = true
	if JuiceSettings.shot_pooling:
		inst.set_meta("pooled", true)
	return inst


## Done with a shot's node: back into [member _tracer_pool] (hidden) if it is a
## reusable tracer and the pool has room, else freed.
func _retire_shot_node(node: MeshInstance3D) -> void:
	if node.has_meta("pooled") and JuiceSettings.shot_pooling \
			and _tracer_pool.size() < TRACER_POOL_MAX and node.get_parent() == _shot_root:
		node.visible = false
		_tracer_pool.append(node)
		return
	node.queue_free()


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
