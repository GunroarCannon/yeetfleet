## Procedural solar system generator: stars, planets, moons and asteroid belts
## that actually orbit under [GravitySystem]'s real Newtonian gravity, not
## scripted circular motion.
##
## Every non-star body is placed near a candidate parent and given the true
## circular-orbit velocity for the *actual local field* at that point (see
## [method _orbit_velocity_at] — blended across every nearby source, not just
## an isolated two-body formula against whatever [GravitySystem] currently
## calls dominant). From then on gravity alone drives it, so "what orbits what"
## is discovered, not declared: a planet close enough and heavy enough steals
## its own moon's orbit away from the star, and an asteroid ring reads as
## "around a planet" or "around the system" purely from where it was dropped
## relative to every body's pull.
##
## Planets and moons are real [Planet] bodies built from randomised
## [PlanetData], the same procedural-surface pipeline the flight scene flies
## past — this generator is a producer of that content, not a placeholder
## sphere factory. Only asteroids stay as plain low-poly spheres: a belt can
## run to a hundred rocks, and a full displaced-mesh planet per rock would be
## pure waste for something that reads as a speck.
##
## Distances: [member distance_scale] keeps every orbit inside a ship's
## practical flight range at 1.0 and spreads bodies out by their true relative
## gaps toward the higher presets, so the dial demonstrates exactly how much the
## game's normal distances are shortened for playability.
class_name SolarSystemGenerator
extends Node3D

enum BodyKind { STAR, PLANET, MOON, ASTEROID }

@export var star_count: int = 1
@export var planet_count: int = 6
@export var system_seed: int = 12345
## Orbit-gap multiplier. 1.0 is the game's normal, compact spacing; presets in
## [constant DISTANCE_PRESETS] range from tighter-than-normal up to the true
## relative scale of a real system. See the class doc for why gravity itself is
## rescaled alongside this rather than only the positions.
@export var distance_scale: float = 1.0
## Simulation speed multiplier. Sub-stepped (see [method _physics_process]) so
## a fast-forwarded system stays numerically stable instead of orbits gaining
## energy from an oversized integration step. Substeps are capped at
## [constant MAX_SUBSTEPS] — past that the sim trades a little accuracy for
## staying responsive at very high multipliers rather than substepping without
## bound.
@export var time_scale: float = 1.0
## Denser sphere geometry for freshly generated bodies. A plain bool, not a
## read of [Session] directly — this script stays dependency-free of any
## other module (see the class doc's module-isolation contract); the lab sets
## this from [member Session.high_res] the same way it already forwards
## [member Session.solar_time_scale] into [member time_scale].
@export var high_res_geometry: bool = false

## --- Randomizable generation dials -------------------------------------------
## Every var in this block is also a [constant RANDOMIZABLE] entry: the lab UI
## builds a slider + lock row for each from that schema instead of one
## hand-built row per dial, and [method randomize_unlocked_params] rerolls
## whichever of them aren't locked. Defaults reproduce this generator's
## previous hardcoded behaviour exactly, so nothing that constructs a
## generator and never touches these (every existing smoke test) sees any
## change.
@export var gravity_strength_mult: float = 1.0
@export var gravity_falloff: float = 2.0
## Symmetric spread around 1.0 that [method _random_planet_data] draws
## [member PlanetData.orbit_speed] from — a fresh circular-orbit speed
## scaled by this reads as eccentricity once the orbit settles.
@export var orbit_eccentricity: float = 0.1
## Fractional jitter on each planet's orbit-gap distance, 0 = perfectly even
## spacing (today's default), higher = gaps stop reading as evenly spaced
## multiples of [constant PLANET_GAP].
@export var planet_gap_jitter: float = 0.0
@export var star_mass_mult: float = 1.0
@export var star_radius_mult: float = 1.0
@export var planet_radius_mult: float = 1.0
@export var max_moons_per_planet: int = MAX_MOONS_PER_PLANET
## Chance, independently per moon slot up to [member max_moons_per_planet],
## that the slot actually spawns a moon — average moon count is
## `max_moons_per_planet * moon_chance`. Replaces the old flat
## `randi_range(0, MAX_MOONS_PER_PLANET)` with a continuously tunable "avg
## moons" dial; 0.5 at the default max of 3 reproduces the old average of 1.5.
@export var moon_chance: float = 0.5
@export var gas_giant_chance: float = 0.3
@export var ring_chance: float = 0.35
@export var atmosphere_chance: float = 0.5
@export var cloud_chance: float = 0.4
## Chance, per spawned planet, of an automatic belt ringing it at spawn time.
@export var planet_belt_chance: float = 0.0
## Chance of an automatic system-wide belt just past the outermost planet.
@export var wide_belt_chance: float = 0.0

## Every knob [method randomize_unlocked_params] can touch, and what the lab
## UI builds a slider + lock row for. `is_int` rounds the rerolled value and
## writes the property as an int; everything else is a float. Both read and
## write the named property via GDScript's [method Object.set]/[method
## Object.get] reflection, so adding a dial here plus one exported var above
## is the whole cost of a new one.
const RANDOMIZABLE: Array[Dictionary] = [
	{"key": "star_count", "label": "Star count", "min": 1.0, "max": 3.0, "step": 1.0, "is_int": true},
	{"key": "planet_count", "label": "Planet count", "min": 1.0, "max": 10.0, "step": 1.0, "is_int": true},
	{"key": "gravity_strength_mult", "label": "Gravity strength", "min": 0.4, "max": 2.5, "step": 0.05},
	{"key": "gravity_falloff", "label": "Gravity falloff", "min": 1.5, "max": 3.0, "step": 0.05},
	{"key": "orbit_eccentricity", "label": "Orbit eccentricity", "min": 0.0, "max": 0.4, "step": 0.01},
	{"key": "planet_gap_jitter", "label": "Orbit spacing jitter", "min": 0.0, "max": 0.5, "step": 0.02},
	{"key": "star_mass_mult", "label": "Star mass", "min": 0.5, "max": 2.5, "step": 0.05},
	{"key": "star_radius_mult", "label": "Star radius", "min": 0.5, "max": 10.0, "step": 0.1},
	{"key": "planet_radius_mult", "label": "Planet size", "min": 0.5, "max": 1.8, "step": 0.05},
	{"key": "max_moons_per_planet", "label": "Max moons/planet", "min": 0.0, "max": 6.0, "step": 1.0, "is_int": true},
	{"key": "moon_chance", "label": "Moon frequency", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "gas_giant_chance", "label": "Gas giant chance", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "ring_chance", "label": "Ring chance", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "atmosphere_chance", "label": "Atmosphere chance", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "cloud_chance", "label": "Cloud chance", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "planet_belt_chance", "label": "Per-planet belt chance", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "wide_belt_chance", "label": "System belt chance", "min": 0.0, "max": 1.0, "step": 0.05},
]

## Per-[constant RANDOMIZABLE] key -> whether [method randomize_unlocked_params]
## should leave it alone. Missing key means unlocked (reshuffles on reseed
## until the user locks it down to isolate it) — set from the lab's per-dial
## lock checkboxes.
var locked: Dictionary = {}

## Named [member distance_scale] presets for a UI dropdown: label + multiplier.
## More graduated than the original binary compressed/realistic choice — some
## tighter than the default, some looser, one at the true relative scale.
const DISTANCE_PRESETS := [
	{"label": "Tight", "scale": 0.4},
	{"label": "Compact", "scale": 1.0},
	{"label": "Balanced", "scale": 3.0},
	{"label": "Spread", "scale": 7.0},
	{"label": "Realistic", "scale": 14.0},
	{"label": "Vast", "scale": 30.0},
]

## Gap between successive planet orbits, compressed scale (metres).
const PLANET_GAP := 900.0
const STAR_RADIUS := 220.0
const STAR_MASS := 26000.0
const PLANET_RADIUS_MIN := 45.0
const PLANET_RADIUS_MAX := 130.0
## Planet mass scales with radius cubed (constant density) then gets knocked
## down hard: a planet-mass body at planet_radius using the star's density
## would out-gravitate the star at close range. This constant is the density
## fudge, tuned so the heaviest possible planet (even after [member
## PlanetData.orbit_strength]'s own multiplier, capped below at 1.35×) still
## stays well under STAR_MASS — a planet must never be able to out-pull the
## star for a sibling planet sitting at the same distance (the worst case two
## orbiting rings can put a body at) — while still comfortably holding a moon
## out to MOON_GAP_MAX at the innermost orbit (see [method _hill_radius],
## which _spawn_moons clamps against so this stays true for every roll, not
## just the average one).
const PLANET_DENSITY := 0.007

## How far a generated planet's hue may stray from its palette anchor, in turns.
## About 25° either way: wide enough that a system's worlds are visibly different
## colours, narrow enough that they still read as belonging to the same palette.
const PLANET_HUE_JITTER := 0.07

const MOON_RADIUS_MIN := 8.0
const MOON_RADIUS_MAX := 28.0
const MOON_GAP_MIN := 60.0
const MOON_GAP_MAX := 220.0
const MAX_MOONS_PER_PLANET := 3
## Nominal densities for bodies that don't gravitate anything (moons, rocks) but
## still need a mass for collision response — see [method _resolve_collisions].
const MOON_DENSITY := 0.01
const ROCK_DENSITY := 0.02
## Rock counts for the automatic belts [member planet_belt_chance] and
## [member wide_belt_chance] roll — same scale as the lab's own manual belt
## buttons (see [constant SolarSystemGenLabRoot.NEAR_BELT_COUNT] /
## [constant SolarSystemGenLabRoot.WIDE_BELT_COUNT]).
const PLANET_BELT_AUTO_COUNT := 18
const WIDE_BELT_AUTO_COUNT := 60

## Whether belt rocks are simulated as real bodies at all. True is the lab's
## behaviour: a belt promotes to LIVE (see [enum BeltState]) as the focus closes
## on it and demotes again as it leaves. The generated-system flight scene turns
## it off, because there LIVE buys nothing and costs a great deal — that scene
## builds no [PhysWorld] (see [method FlightRoot._build_phys_world]), so a live
## rock cannot be collided with by anything, while promoting a wide belt and the
## belts of six planets takes the body count from 14 to 182 and the per-frame
## cost from ~8 ms to ~170 ms: every rock joins the N-body integration *and* the
## O(n²) pair sweep in [method _resolve_collisions]. Off, rocks keep their
## analytic LUMPED orbits and tumble, so a belt looks the same and costs a
## [MultiMesh] instance write.
var belts_simulate := true

## Hard ceiling on integration substeps per physics frame. Without this a large
## [member time_scale] (hundreds or thousands ×) would substep proportionally
## and stall the frame; past this cap the sim accepts a slightly larger
## integration error in exchange for staying real-time, which is the right
## trade for a "fast forward and watch" lab feature.
const MAX_SUBSTEPS := 48

## Bounce restitution for body-body collisions. A cartoony "sort of bounce", not
## a real-materials value — see [method _resolve_collisions]'s doc for where a
## proper explosion mechanic would replace this later.
const COLLISION_RESTITUTION := 0.5

## Debug orbit-path drawing. Two independent overlays, because they answer two
## different questions: [member show_predicted_orbits] is "where the maths says
## this body's ellipse is *right now*" (recomputed periodically, since a
## multi-body field keeps nudging it); [member show_actual_trails] is "where
## the body has actually been" (a recorded breadcrumb trail, which is what
## reveals a genuinely broken orbit — drift the maths overlay alone would hide
## between refreshes).
var show_predicted_orbits := false
var show_actual_trails := false
const TRAIL_MAX_POINTS := 220
const TRAIL_SAMPLE_INTERVAL := 0.15
const PREDICTED_ORBIT_REFRESH_INTERVAL := 1.0
const PREDICTED_ORBIT_SEGMENTS := 96

## Debug-overlay-only hysteresis for [method predicted_orbit_points]: without
## this, the predicted ellipse would redraw against whichever body [method
## GravitySystem.find_dominant_body] picks *this instant*, which flips
## discretely near a Hill-radius boundary even though the real physics blend
## (top-2 softmax, see [method GravitySystem.find_dominant_bodies]) is
## continuous — the overlay would flicker between a tight loop and a huge
## stellar ellipse for a body that is genuinely just orbiting normally. A
## candidate only takes over once it out-pulls the current reference by this
## margin, not the instant it's merely ahead. Real integration never reads
## [member _predicted_ref] — only the debug overlay does.
const PREDICTED_REF_SWITCH_MARGIN := 1.25
## body name -> [GravitySystem.GravityBody] last used as that body's
## predicted-orbit reference. See [constant PREDICTED_REF_SWITCH_MARGIN].
var _predicted_ref: Dictionary = {}

## Debug: stream discrete simulation events (dominant-body switches, actual
## reparenting, collisions, a body going unbound) to an in-memory ring buffer
## and the console. Off by default -- see the class doc's sibling debug
## overlays for why this exists as its own opt-in rather than always-on: it
## answers "what actually happened" when an orbit looks glitchy, which the
## visual overlays alone can't show (they redraw a snapshot, not a history).
var log_events := false
const EVENT_LOG_CAP := 500
var _event_log: Array[String] = []
var _sim_time := 0.0
## body name -> name of the body it actually orbits right now (the physics'
## own pick, not the hysteresis-smoothed [member _predicted_ref]) -- tracked
## only while [member log_events] is on, to log genuine reparenting (a moon
## actually getting captured by the star) as distinct from the overlay's own
## display hysteresis.
var _actual_dominant: Dictionary = {}

## Gameplay prep, not simulation realism (see the class's own "discovered, not
## declared" orbits — this mode is the opposite of that, deliberately). When
## true, every planet/moon travels a fixed, perfectly stable orbit around
## whichever body was dominant the moment it locked (see [method _lock_body])
## instead of drifting under real N-body gravity — orbits stop decaying or
## precessing at all. A collision impulse hard enough (see [method
## _maybe_break_lock], called from [method _resolve_collisions]) knocks a body
## loose into ordinary free physics; [method _update_relock_check] then locks
## it onto a *fresh* orbit — which can be around a different dominant body,
## e.g. a moon knocked clear of its planet settling into the star's own orbit
## instead — once its free motion has looked stable for long enough. Off by
## default: every existing system (every smoke test, the lab's own real-N-body
## demonstration) sees no change. Scoped to planets/moons, not asteroids —
## belt rocks already get their own drift (see [method _update_belt_visuals],
## [method _integrate]'s ASTEROID branch).
var orbit_lock_enabled := false
## Δv from a single collision, as a fraction of the body's own current lock
## speed, that breaks its orbit lock. Fraction rather than an absolute speed
## so it scales across systems whose orbital speeds differ (a Vast-preset
## outer planet moves far slower than a Compact-preset inner one).
const ORBIT_LOCK_BREAK_FRACTION := 0.35
## How long a freed body's motion must keep reading as a stable orbit (see
## [method GravitySystem.is_in_orbit]) before [method _update_relock_check]
## locks it back down — that method's own doc calls for hysteresis on top of
## the instantaneous check; this is it.
const ORBIT_LOCK_RELOCK_GRACE := 1.2
## Minimum time after a lock breaks before it's eligible to re-lock — without
## this, a body sitting right at the is_in_orbit threshold could lock/break/
## lock every frame.
const ORBIT_LOCK_BREAK_COOLDOWN := 1.0

## One entry per generated body:
## {kind, name, node: Node3D, velocity: Vector3, gbody: GravitySystem.GravityBody
## or null, radius: float, mass: float, planet_data: PlanetData or null}
## [member GravitySystem.GravityBody] is null for moons and asteroids — they
## are too light to gravitate anything themselves, only to be pulled (see
## [method GravitySystem.register_body]'s docstring on why only sources are
## tracked there). `mass` is always populated, independent of `gbody` — it is
## what [method _resolve_collisions] resolves bounces with.
var bodies: Array[Dictionary] = []

## Belt LOD state: a belt is either a single cheap [MultiMeshInstance3D] ring
## with no physics cost ([constant BeltState.LUMPED] — the default, and where
## an unattended belt spends nearly all its life), or real per-rock
## [GravityBody]-integrated [constant BodyKind.ASTEROID] entries in [member
## bodies] ([constant BeltState.LIVE]). [method set_lod_focus] + [method
## _update_belt_lod] promote/demote automatically-spawned belts based on
## distance from whatever focus point is handed in (in practice: the
## flight-test ship, when one exists — see [SolarSystemGenLabRoot._process]);
## a `manual` belt (the lab's own "Spawn belt" buttons) starts LIVE and stays
## that way, matching this lab's original always-inspectable behaviour.
enum BeltState { LUMPED, LIVE }
## One entry per [method spawn_asteroid_belt] call:
## {id, center_name, center_pos, ring_radius, count, thickness, belt_seed,
## state, mesh_inst: MultiMeshInstance3D or null, rock_names: Array[String],
## manual}. `center_name`, when non-empty, is a body this belt's ring
## recentres onto every frame (see [method _belt_center]) rather than staying
## fixed in space — the ring around a planet must follow the planet.
var belts: Array[Dictionary] = []
var _belt_id_counter := 0
const BELT_LOD_CHECK_INTERVAL := 0.5
## How far past a belt's own ring radius (plus its thickness) a focus point
## must come before the belt promotes to LIVE — generous enough that a ship
## flying toward a belt sees it "turn on" a little before it's already inside.
const BELT_LOD_NEAR_MULT := 1.6
const BELT_LUMPED_SPIN_RATE := 0.02  # rad/s, a cheap stand-in for collective orbital motion
var _lod_focus_pos := Vector3.ZERO
var _lod_focus_active := false
var _belt_lod_timer := 0.0

var gravity := GravitySystem.new()
var _rng := RandomNumberGenerator.new()

var _paths_root: Node3D
var _predicted_meshes: Dictionary = {}  # body name -> MeshInstance3D
var _trail_meshes: Dictionary = {}      # body name -> MeshInstance3D
var _trail_history: Dictionary = {}     # body name -> PackedVector3Array
var _trail_timer := 0.0
var _predicted_orbit_timer := 0.0


func _ready() -> void:
	if bodies.is_empty():
		generate_system()


## Rerolls every [constant RANDOMIZABLE] dial whose key isn't set (true) in
## [member locked], each within its own schema range, seeded from
## [member system_seed] so the same seed always proposes the same params for
## a given lock combination. Deliberately separate from [method
## generate_system] rather than folded into it — a caller that sets
## [member planet_count] etc. directly and calls generate_system() (every
## existing smoke test, [method SolarSystemGenLabRoot._spawn_test_ship]'s
## generator, ...) must keep working unchanged; only the lab's own
## "Regenerate / reseed" button opts into this reroll, by calling it first.
func randomize_unlocked_params() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = system_seed
	for entry in RANDOMIZABLE:
		var key: String = entry["key"]
		if locked.get(key, false):
			continue
		var lo: float = entry["min"]
		var hi: float = entry["max"]
		if entry.get("is_int", false):
			set(key, rng.randi_range(int(lo), int(hi)))
		else:
			set(key, rng.randf_range(lo, hi))


func generate_system() -> void:
	clear_system()
	_rng.seed = system_seed
	var mult := maxf(distance_scale, 0.05)
	# Stretching every orbit distance by `mult` drops acceleration by mult²
	# under the inverse-square law, straight through [constant
	# GravitySystem.RELEVANCE_EPSILON]'s fixed absolute floor — every body would
	# read as "orbits nothing" no matter how far _spawn_stars widens the star's
	# relevant_range, since that only patches the distance-based reject and not
	# the separate accel-floor one. Boosting g by the same square on this
	# generator's own private GravitySystem (never the live game's) cancels it
	# exactly: accelerations, and so dominant-body selection, come out
	# identical at every equivalent orbital slot for any preset, just spread
	# out to look the distance scale's part.
	gravity.apply_law(GravitySystem.GAME_G * mult * mult * gravity_strength_mult, gravity_falloff)
	var star_positions := _spawn_stars()
	for i in planet_count:
		_spawn_planet(star_positions[0])
	_spawn_moons()
	if _rng.randf() < wide_belt_chance:
		var outer := _planet_gap() * float(maxi(planet_count, 1)) * _distance_mult()
		spawn_asteroid_belt(star_positions[0], outer * 1.2, WIDE_BELT_AUTO_COUNT, outer * 0.05, bodies[0]["name"])
	if show_predicted_orbits:
		_predicted_orbit_timer = PREDICTED_ORBIT_REFRESH_INTERVAL
		_rebuild_predicted_orbits()
	if orbit_lock_enabled:
		for entry in bodies:
			if entry["kind"] != BodyKind.STAR and entry["kind"] != BodyKind.ASTEROID:
				_lock_body(entry)
	if log_events:
		_log_event("== system generated (seed %d) ==" % system_seed)


## Farthest any live body or belt actually reaches from the (first) star,
## measured from the real generated result rather than re-derived from the
## generation dials — a caller sizing a backdrop against this doesn't need to
## know [constant PLANET_GAP] or duplicate the belt/gap-jitter math to stay
## right when those numbers change. 0.0 if nothing has been generated yet.
func outer_extent() -> float:
	if bodies.is_empty():
		return 0.0
	var origin: Vector3 = (bodies[0]["node"] as Node3D).position
	var farthest := 0.0
	for entry in bodies:
		var node: Node3D = entry["node"]
		var reach: float = origin.distance_to(node.position) + float(entry["radius"])
		farthest = maxf(farthest, reach)
	for belt in belts:
		var centre: Vector3 = _belt_center(belt)
		var reach: float = origin.distance_to(centre) + float(belt["ring_radius"]) + float(belt["thickness"])
		farthest = maxf(farthest, reach)
	return farthest


func clear_system() -> void:
	for entry in bodies:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			# Detach immediately, not just queue_free: a regenerate calls this and
			# then re-spawns under the same names (Star_0, Planet_0, ...) in the
			# same frame, before a deferred free has actually removed the old node
			# — Godot then auto-uniquifies the new one to Star_0@2, silently
			# breaking every name the hierarchy readout and belt lookups rely on.
			remove_child(node)
			node.queue_free()
	bodies.clear()
	gravity.clear()
	for belt in belts:
		var mesh_inst: Node = belt.get("mesh_inst")
		if mesh_inst != null and is_instance_valid(mesh_inst):
			remove_child(mesh_inst)
			mesh_inst.queue_free()
	belts.clear()
	_belt_lod_timer = 0.0
	_clear_meshes(_predicted_meshes)
	_clear_meshes(_trail_meshes)
	_trail_history.clear()
	_predicted_ref.clear()
	_actual_dominant.clear()


# --- Generation ---------------------------------------------------------------

func _spawn_stars() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var star_mass := STAR_MASS * star_mass_mult
	var star_radius := STAR_RADIUS * star_radius_mult
	for i in maxi(star_count, 1):
		var pos := Vector3.ZERO
		if i > 0:
			# Companion stars just sit far out in a ring; multi-star gravitational
			# dynamics is out of scope here, this is enough to see a binary system
			# from the far-view lab.
			var angle := TAU * float(i) / float(star_count)
			pos = Vector3(cos(angle), 0.0, sin(angle)) * PLANET_GAP * planet_count * _distance_mult() * 1.5
		var node := _make_sphere_body("Star_%d" % i, star_radius, Palette.color("star"), true)
		node.position = pos
		add_child(node)
		var gbody := gravity.register_body(pos, star_mass, star_radius, node.name, true)
		# A star's mass-derived relevant_range can fall short of its own
		# planet_count * PLANET_GAP span (more planets just means a wider
		# system, not a heavier star) -- past that range GravitySystem drops
		# the star as a candidate entirely and an outer planet or belt would
		# find nothing to orbit. Force the range to always cover the system.
		var system_span := PLANET_GAP * float(maxi(planet_count, 1)) * _distance_mult()
		gbody.relevant_range = maxf(gbody.relevant_range, system_span * 8.0)
		bodies.append({
			"kind": BodyKind.STAR, "name": node.name, "node": node, "velocity": Vector3.ZERO,
			"gbody": gbody, "radius": star_radius, "mass": star_mass, "planet_data": null,
		})
		positions.append(pos)
	return positions


## A big [member star_radius_mult] can grow the star past [constant
## PLANET_GAP]'s fixed 900m spacing — without widening the gap to match, the
## inner planet(s) spawn already inside the star's surface, and [method
## _resolve_collisions] then pins them right at that surface every frame:
## still technically moving (velocity is fine), but visually swallowed by/
## glued to the star, which reads as "doesn't move". The default (star_radius
## well under PLANET_GAP) is untouched.
func _planet_gap() -> float:
	return maxf(PLANET_GAP, STAR_RADIUS * star_radius_mult * 2.2)


func _spawn_planet(star_pos: Vector3) -> void:
	var index := bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == BodyKind.PLANET).size()
	var gap_jitter := 1.0 + _rng.randf_range(-planet_gap_jitter, planet_gap_jitter)
	var distance := _planet_gap() * float(index + 1) * _distance_mult() * gap_jitter
	var angle := _rng.randf() * TAU
	var pos := star_pos + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	var radius := lerpf(PLANET_RADIUS_MIN * planet_radius_mult, PLANET_RADIUS_MAX * planet_radius_mult, _rng.randf())
	var data := _random_planet_data(radius, false)
	var base_mass := PLANET_DENSITY * radius * radius * radius
	var node := _make_planet_node("Planet_%d" % index, data)
	node.position = pos
	add_child(node)
	# orbit_strength scales only the mass this planet *gravitates with* (how
	# hard it holds its own moons/belt), never the collision mass below — a
	# strong-holding planet isn't also a heavier wrecking ball for free.
	var gbody := gravity.register_body(pos, base_mass * data.orbit_strength, radius, node.name, true)
	var dominant := gravity.find_dominant_body(pos)
	var vel := _orbit_velocity_at(pos, dominant) * data.orbit_speed
	bodies.append({
		"kind": BodyKind.PLANET, "name": node.name, "node": node, "velocity": vel,
		"gbody": gbody, "radius": radius, "mass": base_mass, "planet_data": data,
	})
	if _rng.randf() < planet_belt_chance:
		var near_radius := minf(gbody.radius * 2.2 + 60.0, _hill_radius(gbody, pos) * 0.5)
		spawn_asteroid_belt(pos, near_radius, PLANET_BELT_AUTO_COUNT, 15.0, node.name)


func _spawn_moons() -> void:
	var planets := bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == BodyKind.PLANET)
	for planet_entry in planets:
		var moon_count := 0
		for _slot in max_moons_per_planet:
			if _rng.randf() < moon_chance:
				moon_count += 1
		var planet_node: Node3D = planet_entry["node"]
		var planet_gbody: GravitySystem.GravityBody = planet_entry["gbody"]
		# Half the Hill radius: a moon placed any farther than this is closer to
		# being the star's than the planet's, no matter how the mass/gap roll
		# landed -- clamp instead of just hoping the roll stays small enough.
		var hill_limit := _hill_radius(planet_gbody, planet_node.position) * 0.5
		for i in moon_count:
			var gap := lerpf(MOON_GAP_MIN, MOON_GAP_MAX, _rng.randf()) * _distance_mult()
			var distance := clampf(planet_gbody.radius * 2.2 + gap, planet_gbody.radius * 1.3, maxf(hill_limit, planet_gbody.radius * 1.3))
			var angle := _rng.randf() * TAU
			var pos := planet_node.position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			var radius := lerpf(MOON_RADIUS_MIN, MOON_RADIUS_MAX, _rng.randf())
			var data := _random_planet_data(radius, true)
			var node := _make_planet_node("%s_Moon_%d" % [planet_node.name, i], data)
			node.position = pos
			add_child(node)
			# Moons don't need to gravitate anything else in this generator, so
			# they stay off the gravity source list — they are pulled, not pulling.
			var dominant := gravity.find_dominant_body(pos)
			var vel := _orbit_velocity_at(pos, dominant) * data.orbit_speed
			bodies.append({
				"kind": BodyKind.MOON, "name": node.name, "node": node, "velocity": vel,
				"gbody": null, "radius": radius, "mass": MOON_DENSITY * radius * radius * radius,
				"planet_data": data,
			})


## The classic Hill-sphere approximation: the distance from [param gbody]
## within which its own pull beats whatever body currently dominates it (its
## "parent" -- the star, for a plain planet). r_hill = d * cbrt(m/3M). Used as
## a placement limit, not the literal boundary -- real orbits get unstable
## well before the true edge, so callers clamp against a fraction of this.
func _hill_radius(gbody: GravitySystem.GravityBody, pos: Vector3) -> float:
	var parent := gravity.find_dominant_body(pos)
	if parent == null or parent.mass <= 0.0:
		return INF
	var d := pos.distance_to(parent.position)
	return d * pow(gbody.mass / (3.0 * parent.mass), 1.0 / 3.0)


## Circular-orbit velocity consistent with the *actual* field at [param pos] —
## the same blended pull [method GravitySystem.compute_gravity] would apply
## during integration, not [method GravitySystem.orbit_velocity]'s isolated
## two-body formula against [param dominant] alone. Those two disagree exactly
## where it matters most: a moon near its planet's Hill limit, or an asteroid
## at a belt's outer edge, both close enough to a second body (the star) that
## its pull is no longer negligible. Spawning with the isolated formula gave
## the body an initial speed that didn't match what integration immediately
## applied — the orbit was eccentric or actively decaying from frame one. This
## matches the instant field exactly, so a fresh orbit starts clean; it can
## still evolve as the body moves (a real multi-body field keeps nudging it),
## but that's honest drift, not a spawn-time bug.
func _orbit_velocity_at(pos: Vector3, dominant: GravitySystem.GravityBody) -> Vector3:
	if dominant == null:
		return Vector3.ZERO
	var to_body := dominant.position - pos
	var dist := to_body.length()
	if dist < GravitySystem.MIN_ORBIT_RADIUS:
		return Vector3.ZERO
	var net_accel := gravity.compute_gravity(pos)
	var speed := sqrt(net_accel.length() * dist)
	var radial := to_body.normalized()
	# Tangential direction: perpendicular to radial, in a mostly-horizontal
	# plane (world up), so every fresh orbit shares one plane instead of each
	# body picking an arbitrary one.
	var tangent := Vector3.UP.cross(radial).normalized()
	if tangent.length_squared() < 0.001:
		tangent = radial.cross(Vector3.RIGHT).normalized()
	return tangent * speed


## Registers a belt of [param count] rocks in a ring of [param ring_radius]
## around [param center] (or, if [param center_body_name] names a live body,
## around that body's *current* position from then on — see [method
## _belt_center]; a ring around a planet must follow the planet as it orbits).
## A ring dropped close around a planet reads as "this planet's belt"; the
## same call with a wider radius around the star reads as "the system's main
## belt" — the eventual per-rock orbit target is discovered by physics once
## LIVE, not declared here.
##
## Starts LUMPED (a single cheap [MultiMeshInstance3D], no physics cost) unless
## [param manual] is true, in which case it starts LIVE and — unlike an
## automatically spawned belt — is never demoted by [method _update_belt_lod];
## that's what the lab's own "Spawn belt" buttons pass, since a user who just
## clicked one wants real, bounceable rocks to inspect immediately, belt LOD
## or no belt LOD.
func spawn_asteroid_belt(
	center: Vector3, ring_radius: float, count: int, thickness: float = 50.0,
	center_body_name: String = "", manual: bool = false
) -> void:
	_belt_id_counter += 1
	var belt := {
		"id": _belt_id_counter, "center_name": center_body_name, "center_pos": center,
		"ring_radius": ring_radius, "count": count, "thickness": thickness,
		"belt_seed": _rng.randi(), "state": BeltState.LUMPED, "mesh_inst": null,
		"rock_names": [] as Array[String], "manual": manual,
	}
	belts.append(belt)
	if manual and belts_simulate:
		_promote_belt_to_live(belt)
	else:
		_build_belt_lumped(belt)


## The belt's current centre: a moving body's live position if [param belt]
## names one, else the fixed point it was spawned at.
func _belt_center(belt: Dictionary) -> Vector3:
	var body_name: String = belt.get("center_name", "")
	if body_name != "":
		var entry := find_body(body_name)
		if not entry.is_empty():
			return (entry["node"] as Node3D).position
	return belt["center_pos"]


## Deterministic per-rock placement + size for [param belt], from its own
## `belt_seed` — shared by the LUMPED [MultiMesh] build and the LIVE per-rock
## body build so a belt looks the same the moment it promotes (before real
## physics has a chance to drift it), whichever representation is active.
## Same placement formula the original always-LIVE implementation used.
func _belt_rock_specs(belt: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(belt["belt_seed"])
	var thickness: float = belt["thickness"]
	var ring_radius: float = belt["ring_radius"]
	var specs: Array[Dictionary] = []
	for i in int(belt["count"]):
		var angle := rng.randf() * TAU
		var r := ring_radius + rng.randf_range(-thickness, thickness) * 0.5
		var h := rng.randf_range(-thickness, thickness) * 0.25
		specs.append({
			"offset": Vector3(cos(angle) * r, h, sin(angle) * r),
			"orbit_radius": r,
			"orbit_angle0": angle,
			"orbit_height": h,
			# Inner rocks orbit faster than outer ones (rate ~ 1/sqrt(r), the
			# same shape as a real Kepler orbit) instead of the whole belt
			# spinning as one rigid disc — see _update_belt_visuals, which is
			# what actually reads this. A rare (5%) retrograde straggler at a
			# slower rate breaks up the "all rocks in lockstep" look further.
			"angular_rate": BELT_LUMPED_SPIN_RATE * sqrt(ring_radius / maxf(r, 1.0)) \
				* (-0.6 if rng.randf() < 0.05 else 1.0),
			"spin_axis": Vector3(
				rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
			).normalized(),
			"spin_rate": rng.randf_range(0.15, 0.6),
			"radius": lerpf(2.0, 9.0, rng.randf()),
			# Independent per-axis jitter, not one uniform scalar: a rock
			# stretched differently on each axis reads as a chunk, not a resized
			# marble. Paired with _rock_mesh's own bumps and a random rotation
			# below (see _build_belt_lumped/_promote_belt_to_live), not a smooth
			# sphere's uniform scale doing all the work alone.
			"scale_jitter": Vector3(
				rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.3)
			),
			"rotation": Vector3(
				rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)
			),
			"speed_jitter": rng.randf_range(0.94, 1.06),
		})
	return specs


func _build_belt_lumped(belt: Dictionary) -> void:
	var specs := _belt_rock_specs(belt)
	# One shared chunky mesh (MultiMesh needs a single mesh resource) — variety
	# across the belt comes from each instance's own rotation and non-uniform
	# scale below, not per-rock mesh shape; that's cheap at belt counts where
	# LUMPED runs (dozens to a couple hundred), unlike a unique mesh per rock.
	var mesh := _build_rock_mesh(float(belt["belt_seed"]))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = specs.size()
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var basis := Basis.from_euler(spec["rotation"]).scaled(
			Vector3.ONE * float(spec["radius"]) * (spec["scale_jitter"] as Vector3)
		)
		mm.set_instance_transform(i, Transform3D(basis, spec["offset"]))
	var inst := MultiMeshInstance3D.new()
	inst.name = "BeltLumped_%d" % int(belt["id"])
	inst.multimesh = mm
	inst.material_override = _body_material(Palette.color("metal_mid"))
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.position = _belt_center(belt)
	add_child(inst)
	belt["mesh_inst"] = inst
	# Cached so [method _update_belt_visuals] can re-drive each instance's
	# per-rock drift/tumble every frame without re-running this belt's whole
	# RNG draw sequence (a few [method RandomNumberGenerator.randf] calls per
	# rock) each time — cheap once, wasteful at 60fps for a couple hundred rocks.
	belt["specs"] = specs
	belt["state"] = BeltState.LUMPED


## Swaps a LUMPED belt's single draw call for real, [GravitySystem]-integrated
## rocks at the same positions [method _belt_rock_specs] already committed it
## to — see [method spawn_asteroid_belt] for why manual belts start here
## directly.
func _promote_belt_to_live(belt: Dictionary) -> void:
	var mesh_inst: Node = belt.get("mesh_inst")
	if mesh_inst != null and is_instance_valid(mesh_inst):
		remove_child(mesh_inst)
		mesh_inst.queue_free()
	belt["mesh_inst"] = null
	var center := _belt_center(belt)
	var specs := _belt_rock_specs(belt)
	var rock_names: Array[String] = []
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var offset: Vector3 = spec["offset"]
		var radius: float = spec["radius"]
		var pos := center + offset
		var node := _make_rock_body("Rock_%d_%d" % [int(belt["id"]), i], int(belt["belt_seed"]) + i)
		node.position = pos
		node.rotation = spec["rotation"]
		# radius × independent per-axis jitter on top of the mesh's own bumps —
		# a chunk of rock, not a resized marble. See _belt_rock_specs.
		node.scale = (spec["scale_jitter"] as Vector3) * radius
		add_child(node)
		var dominant := gravity.find_dominant_body(pos)
		# A small per-rock speed jitter so a belt reads as a scatter of orbits
		# clustered around the ring rather than every rock in exact lockstep.
		var vel := _orbit_velocity_at(pos, dominant) * float(spec["speed_jitter"]) if dominant else Vector3.ZERO
		bodies.append({
			"kind": BodyKind.ASTEROID, "name": node.name, "node": node,
			"velocity": vel, "gbody": null, "radius": radius,
			"mass": ROCK_DENSITY * radius * radius * radius, "planet_data": null,
		})
		rock_names.append(node.name)
	belt["rock_names"] = rock_names
	belt["state"] = BeltState.LIVE


## The inverse of [method _promote_belt_to_live]: frees every real rock body
## this belt owns and rebuilds the single lumped [MultiMesh] in their place.
## Positions won't exactly match wherever real physics scattered them to —
## expected for a "lump it back together once nobody's looking" approximation,
## not a bug.
func _demote_belt_to_lumped(belt: Dictionary) -> void:
	var rock_names: Array = belt.get("rock_names", [])
	for rock_name in rock_names:
		for i in bodies.size():
			if bodies[i]["name"] == rock_name:
				var node: Node3D = bodies[i]["node"]
				if is_instance_valid(node):
					remove_child(node)
					node.queue_free()
				bodies.remove_at(i)
				break
	belt["rock_names"] = []
	_build_belt_lumped(belt)


## Focus point for belt LOD — see [enum BeltState]'s doc. Cheap to call every
## frame (two field writes); the actual promote/demote work only happens on
## [constant BELT_LOD_CHECK_INTERVAL]'s own throttled timer.
func set_lod_focus(pos: Vector3, active: bool) -> void:
	_lod_focus_pos = pos
	_lod_focus_active = active


func _update_belt_lod(delta: float) -> void:
	if belts.is_empty() or not belts_simulate:
		return
	_belt_lod_timer += delta
	if _belt_lod_timer < BELT_LOD_CHECK_INTERVAL:
		return
	_belt_lod_timer = 0.0
	for belt in belts:
		if bool(belt.get("manual", false)):
			continue
		var center := _belt_center(belt)
		var reach := (float(belt["ring_radius"]) + float(belt["thickness"])) * BELT_LOD_NEAR_MULT
		var near := _lod_focus_active and _lod_focus_pos.distance_to(center) < reach
		var is_live := int(belt["state"]) == BeltState.LIVE
		if near and not is_live:
			_promote_belt_to_live(belt)
			_log_event("belt %d promoted to live (focus within %.0fm)" % [int(belt["id"]), reach])
		elif not near and is_live:
			_demote_belt_to_lumped(belt)
			_log_event("belt %d demoted to lumped (focus left %.0fm)" % [int(belt["id"]), reach])


## Keeps a LUMPED belt's single node tracking its (possibly moving) centre.
## Runs every physics frame, not on the LOD timer — cheap at LUMPED counts,
## not a rebuild. Drives each LUMPED rock along its own analytic orbit + tumble
## (see the
## "angular_rate"/"spin_axis"/"spin_rate" fields [method _belt_rock_specs]
## computes) instead of spinning the whole belt as one rigid disc — a belt a
## player is flying past but hasn't gotten close enough to promote to real,
## individually-simulated rocks (see [enum BeltState]) still reads as a field
## of independently wandering chunks, not a single spinning texture, for
## whatever this costs (an instance-transform write per rock per frame,
## cheap at LUMPED counts).
func _update_belt_visuals(_delta: float) -> void:
	for belt in belts:
		if int(belt["state"]) != BeltState.LUMPED:
			continue
		var mesh_inst: MultiMeshInstance3D = belt.get("mesh_inst")
		if mesh_inst == null or not is_instance_valid(mesh_inst):
			continue
		mesh_inst.position = _belt_center(belt)
		var specs: Array = belt.get("specs", [])
		for i in specs.size():
			var spec: Dictionary = specs[i]
			var angle: float = float(spec["orbit_angle0"]) + float(spec["angular_rate"]) * _sim_time
			var r: float = spec["orbit_radius"]
			var pos := Vector3(cos(angle) * r, float(spec["orbit_height"]), sin(angle) * r)
			var spin: Vector3 = (spec["rotation"] as Vector3) \
				+ (spec["spin_axis"] as Vector3) * float(spec["spin_rate"]) * _sim_time
			var basis := Basis.from_euler(spin).scaled(
				Vector3.ONE * float(spec["radius"]) * (spec["scale_jitter"] as Vector3)
			)
			mesh_inst.multimesh.set_instance_transform(i, Transform3D(basis, pos))


func _distance_mult() -> float:
	return distance_scale


# --- Live simulation -----------------------------------------------------------

## Sub-stepped so a large [member time_scale] can't blow orbits up: a moon a
## few hundred metres from its planet needs a much smaller integration step
## than the same delta would need for the planet's own orbit around the star.
## Substeps are capped at [constant MAX_SUBSTEPS] so an extreme multiplier
## trades accuracy for staying real-time rather than stalling the frame.
func _physics_process(delta: float) -> void:
	if time_scale <= 0.0:
		return
	var total_dt := delta * time_scale
	_sim_time += total_dt
	var substeps := clampi(ceili(time_scale), 1, MAX_SUBSTEPS)
	var step := total_dt / float(substeps)
	for _s in substeps:
		_integrate(step)
	# Collisions resolve once per real frame, not per substep — cheap enough at
	# this body count (a few dozen to a couple hundred with belts) and a fast
	# mover tunnelling through in one substep at extreme time_scale is an
	# acceptable trade for a "fast forward and watch" feature, not a physics
	# guarantee.
	_resolve_collisions()
	_track_actual_dominant()
	_update_belt_lod(delta)
	_update_belt_visuals(delta)
	_update_actual_trails(delta)
	if show_predicted_orbits:
		_predicted_orbit_timer += delta
		if _predicted_orbit_timer >= PREDICTED_ORBIT_REFRESH_INTERVAL:
			_predicted_orbit_timer = 0.0
			_rebuild_predicted_orbits()


func _integrate(dt: float) -> void:
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR:
			continue
		if orbit_lock_enabled and bool(entry.get("locked", false)):
			_integrate_locked(entry, dt)
			continue
		if orbit_lock_enabled and entry["kind"] != BodyKind.ASTEROID:
			_update_relock_check(entry, dt)
		var node: Node3D = entry["node"]
		var pos := node.position
		var accel := gravity.compute_gravity(pos)
		var vel: Vector3 = entry["velocity"] + accel * dt
		entry["velocity"] = vel
		pos += vel * dt
		node.position = pos
		var gbody: GravitySystem.GravityBody = entry.get("gbody")
		if gbody != null:
			gbody.position = pos


## Moves a locked body along the fixed circular-ish orbit [method _lock_body]
## captured, rather than integrating real gravity — see [member
## orbit_lock_enabled]'s doc for why. [member Dictionary entry]'s "velocity"
## is still kept current (as the orbit's own instantaneous tangential speed)
## so anything else reading it — collision response, a HUD readout — sees a
## sane value, not a stale one from the moment it locked.
func _integrate_locked(entry: Dictionary, dt: float) -> void:
	var lock: Dictionary = entry["lock"]
	var dominant: GravitySystem.GravityBody = lock["dominant"]
	var angular_rate: float = lock["angular_rate"]
	var angle: float = float(lock["angle"]) + angular_rate * dt
	lock["angle"] = angle
	var radius: float = lock["radius"]
	var pos := dominant.position + Vector3(cos(angle) * radius, float(lock["height"]), sin(angle) * radius)
	var node: Node3D = entry["node"]
	node.position = pos
	entry["velocity"] = Vector3(-sin(angle), 0.0, cos(angle)) * radius * angular_rate
	var gbody: GravitySystem.GravityBody = entry.get("gbody")
	if gbody != null:
		gbody.position = pos


## Snaps [param entry] onto a fixed orbit matching its *current* position and
## velocity around whichever body is dominant there right now — not an
## idealized circular speed, so locking a body caught mid-drift doesn't jolt
## it onto a different path than the one it was already on. Returns false (and
## leaves the body unlocked) if there's nothing to orbit or it's sitting on
## top of its dominant body's centre.
func _lock_body(entry: Dictionary) -> bool:
	var node: Node3D = entry["node"]
	var pos := node.position
	var dominant := gravity.find_dominant_body(pos)
	if dominant == null:
		return false
	var to_body := pos - dominant.position
	var radius := Vector2(to_body.x, to_body.z).length()
	if radius < GravitySystem.MIN_ORBIT_RADIUS:
		return false
	var vel: Vector3 = entry["velocity"]
	var speed_xz := Vector2(vel.x, vel.z).length()
	# Signed by the body's actual current direction of travel (2D cross of
	# radial and velocity) — a retrograde capture stays retrograde, not
	# silently flipped to match every other body's rotation sense.
	var cross := to_body.x * vel.z - to_body.z * vel.x
	var angular_rate := (speed_xz / radius) * (1.0 if cross >= 0.0 else -1.0)
	entry["locked"] = true
	entry["lock"] = {
		"dominant": dominant, "radius": radius, "height": to_body.y,
		"angle": atan2(to_body.z, to_body.x), "angular_rate": angular_rate,
	}
	entry["_relock_timer"] = 0.0
	return true


## Called from [method _resolve_collisions] whenever a locked body's velocity
## just changed from an impulse — [param delta_v] is that change. Breaks the
## lock (back to ordinary free physics next frame) once it's a big enough
## fraction of the body's own current orbital speed; see [constant
## ORBIT_LOCK_BREAK_FRACTION].
func _maybe_break_lock(entry: Dictionary, delta_v: Vector3) -> void:
	var lock: Dictionary = entry.get("lock", {})
	if lock.is_empty():
		return
	var lock_speed: float = absf(float(lock["angular_rate"])) * float(lock["radius"])
	if delta_v.length() <= maxf(lock_speed, 0.01) * ORBIT_LOCK_BREAK_FRACTION:
		return
	entry["locked"] = false
	entry["lock"] = {}
	entry["_break_cooldown"] = ORBIT_LOCK_BREAK_COOLDOWN
	if log_events:
		_log_event("orbit lock broken: %s (hit Δv %.1f)" % [entry["name"], delta_v.length()])


## Re-locks a free body once its motion has read as a stable orbit (see
## [method GravitySystem.is_in_orbit]) for [constant ORBIT_LOCK_RELOCK_GRACE]
## straight seconds — the hysteresis that method's own doc calls for, so a
## body only briefly grazing orbital speed doesn't lock/break every frame.
## The orbit it locks onto is whatever [method _lock_body] finds *now*, which
## may be around a different dominant body than the one it broke free of.
func _update_relock_check(entry: Dictionary, dt: float) -> void:
	var cooldown: float = entry.get("_break_cooldown", 0.0)
	if cooldown > 0.0:
		entry["_break_cooldown"] = cooldown - dt
		return
	var node: Node3D = entry["node"]
	var pos := node.position
	var dominant := gravity.find_dominant_body(pos)
	if dominant == null:
		entry["_relock_timer"] = 0.0
		return
	var vel: Vector3 = entry["velocity"]
	if not gravity.is_in_orbit(dominant, pos, vel):
		entry["_relock_timer"] = 0.0
		return
	var t: float = float(entry.get("_relock_timer", 0.0)) + dt
	entry["_relock_timer"] = t
	if t >= ORBIT_LOCK_RELOCK_GRACE:
		if _lock_body(entry) and log_events:
			_log_event("orbit lock re-acquired: %s" % entry["name"])


## Bulk toggle for the lab's UI checkbox (see [member orbit_lock_enabled]):
## locks every live planet/moon immediately when turned on (each onto its
## current position/velocity, not reset to a fresh spawn orbit) and unlocks
## all of them when turned off, rather than only affecting bodies spawned
## after the toggle.
func set_orbit_lock_enabled(enabled: bool) -> void:
	orbit_lock_enabled = enabled
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR or entry["kind"] == BodyKind.ASTEROID:
			continue
		if enabled:
			_lock_body(entry)
		else:
			entry["locked"] = false
			entry["lock"] = {}


## Simple mass-weighted elastic bounce between every pair of overlapping
## bodies, plus a positional correction so they don't keep sinking into each
## other. Deliberately a "sort of bounce" and nothing more — a real explosion /
## fragmentation mechanic is future work, this just stops bodies passing
## through each other. O(n²) over `bodies`, which stays cheap at lab body
## counts (a few dozen to a couple hundred with belts spawned).
func _resolve_collisions() -> void:
	var n := bodies.size()
	for i in n:
		var a := bodies[i]
		var node_a: Node3D = a["node"]
		var a_kinematic: bool = a["kind"] == BodyKind.STAR
		# Radius and inverse mass belong to the body, not to the pair, so they are
		# hoisted out of the inner loop — this O(n²) sweep is what makes a system
		# with every belt live cost tens of ms a frame, and the per-pair dictionary
		# reads are most of it.
		var ra: float = a["radius"]
		var inv_a := 0.0 if a_kinematic else 1.0 / float(a["mass"])
		for j in range(i + 1, n):
			var b := bodies[j]
			var node_b: Node3D = b["node"]
			var b_kinematic: bool = b["kind"] == BodyKind.STAR
			if a_kinematic and b_kinematic:
				continue
			var rb: float = b["radius"]
			var delta := node_b.position - node_a.position
			var dist := delta.length()
			var min_dist := ra + rb
			if dist >= min_dist:
				continue
			if log_events:
				_log_event("collision: %s x %s (overlap %.1fm)" % [a["name"], b["name"], min_dist - dist])
			var normal := delta / dist if dist > 0.0001 else Vector3.UP
			var overlap := min_dist - dist
			var inv_b := 0.0 if b_kinematic else 1.0 / float(b["mass"])
			var inv_sum := inv_a + inv_b
			if inv_sum <= 0.0:
				continue
			# Positional correction first, so a fast overlap doesn't leave the
			# pair still touching next frame and re-triggering every step.
			node_a.position -= normal * (overlap * inv_a / inv_sum)
			node_b.position += normal * (overlap * inv_b / inv_sum)
			var va: Vector3 = a["velocity"]
			var vb: Vector3 = b["velocity"]
			var rel := vb - va
			var sep_speed := rel.dot(normal)
			if sep_speed >= 0.0:
				continue  # already separating — nothing to resolve
			var j_impulse := -(1.0 + COLLISION_RESTITUTION) * sep_speed / inv_sum
			var impulse := normal * j_impulse
			if not a_kinematic:
				var new_va: Vector3 = va - impulse * inv_a
				if orbit_lock_enabled and bool(a.get("locked", false)):
					_maybe_break_lock(a, new_va - va)
				a["velocity"] = new_va
			if not b_kinematic:
				var new_vb: Vector3 = vb + impulse * inv_b
				if orbit_lock_enabled and bool(b.get("locked", false)):
					_maybe_break_lock(b, new_vb - vb)
				b["velocity"] = new_vb
			var gbody_a: GravitySystem.GravityBody = a.get("gbody")
			if gbody_a != null:
				gbody_a.position = node_a.position
			var gbody_b: GravitySystem.GravityBody = b.get("gbody")
			if gbody_b != null:
				gbody_b.position = node_b.position


## What actually orbits what, right now — computed the same way the live
## simulation itself decides it, not from how the body was spawned.
func describe_hierarchy() -> String:
	var lines: PackedStringArray = []
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR:
			lines.append("%s (star)" % entry["name"])
			continue
		var dominant := gravity.find_dominant_body((entry["node"] as Node3D).position)
		lines.append("%s orbits %s" % [entry["name"], dominant.name if dominant else "nothing"])
	return "\n".join(lines)


## Convenience for callers (the lab UI, smoke tests) that want to name an
## existing body as a belt's centre rather than passing a raw position.
func find_body(body_name: String) -> Dictionary:
	for entry in bodies:
		if entry["name"] == body_name:
			return entry
	return {}


## Bodies worth a row in a body-picker UI: every star, planet and moon,
## skipping individual asteroids — a belt is dozens of rocks with no
## individual identity worth a button of its own.
func pickable_bodies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in bodies:
		if entry["kind"] != BodyKind.ASTEROID:
			out.append(entry)
	return out


# --- Debug orbit paths ---------------------------------------------------------

func set_show_predicted_orbits(enabled: bool) -> void:
	show_predicted_orbits = enabled
	if enabled:
		_predicted_orbit_timer = PREDICTED_ORBIT_REFRESH_INTERVAL
		_rebuild_predicted_orbits()
	else:
		_clear_meshes(_predicted_meshes)


func set_show_actual_trails(enabled: bool) -> void:
	show_actual_trails = enabled
	if not enabled:
		_clear_meshes(_trail_meshes)
		_trail_history.clear()


# --- Debug event log ------------------------------------------------------------

## The predicted-orbit reference body for [param entry], with hysteresis — see
## [constant PREDICTED_REF_SWITCH_MARGIN]. Only [method predicted_orbit_points]
## calls this; real integration always uses the live, unsmoothed
## [method GravitySystem.find_dominant_body].
func _predicted_reference_body(entry: Dictionary, pos: Vector3) -> GravitySystem.GravityBody:
	var candidate := gravity.find_dominant_body(pos)
	var body_name: String = entry["name"]
	var current: GravitySystem.GravityBody = _predicted_ref.get(body_name)
	if current == null or candidate == null or candidate == current:
		_predicted_ref[body_name] = candidate
		return candidate
	var candidate_accel := gravity.compute_gravity_from(candidate, pos).length()
	var current_accel := gravity.compute_gravity_from(current, pos).length()
	if candidate_accel > current_accel * PREDICTED_REF_SWITCH_MARGIN:
		if log_events:
			_log_event("%s predicted-orbit reference switched %s -> %s (accel x%.2f)" % [
				body_name, current.name, candidate.name, candidate_accel / maxf(current_accel, 0.0001)
			])
		_predicted_ref[body_name] = candidate
		return candidate
	return current


## The *actual* dominant body per non-star, non-asteroid body, tracked only
## while [member log_events] is on. Logs genuine reparenting (a moon actually
## getting captured by the star, not just the overlay's own display
## hysteresis) — see [member _actual_dominant]'s doc.
func _track_actual_dominant() -> void:
	if not log_events:
		return
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR or entry["kind"] == BodyKind.ASTEROID:
			continue
		var body_name: String = entry["name"]
		var node: Node3D = entry["node"]
		var dominant := gravity.find_dominant_body(node.position)
		var dominant_name := dominant.name if dominant != null else "nothing"
		if _actual_dominant.has(body_name) and _actual_dominant[body_name] != dominant_name:
			_log_event("%s now actually orbits %s (was %s)" % [body_name, dominant_name, _actual_dominant[body_name]])
		_actual_dominant[body_name] = dominant_name


func _log_event(message: String) -> void:
	if not log_events:
		return
	var line := "[%7.2fs] %s" % [_sim_time, message]
	_event_log.append(line)
	if _event_log.size() > EVENT_LOG_CAP:
		_event_log = _event_log.slice(_event_log.size() - EVENT_LOG_CAP)
	print("[orbit-log] " + line)


## Copy of the in-memory ring buffer for a UI readout.
func get_event_log() -> PackedStringArray:
	return PackedStringArray(_event_log)


## Writes the current event log to [param path] (a `user://` path by default —
## the repo is not the place for a runtime debug artifact). Returns the path
## written, or "" if the file could not be opened.
func dump_event_log(path: String = "user://solar_system_events.log") -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SolarSystemGenerator: could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	for line in _event_log:
		f.store_line(line)
	f.close()
	return path


func _paths_container() -> Node3D:
	if _paths_root == null or not is_instance_valid(_paths_root):
		_paths_root = Node3D.new()
		_paths_root.name = "OrbitPaths"
		add_child(_paths_root)
	return _paths_root


## Sample points along the Keplerian ellipse [param entry] would follow if its
## current dominant body's pull were the only force acting — the "predicted"
## path, as opposed to the recorded actual trail (see [method
## _update_actual_trails]), which bends with every other body's pull too.
## Returns an empty array for an unbound trajectory (hyperbolic escape, no
## dominant body, or degenerate angular momentum).
func predicted_orbit_points(entry: Dictionary, segments: int = PREDICTED_ORBIT_SEGMENTS) -> PackedVector3Array:
	var node: Node3D = entry["node"]
	var pos := node.position
	var dominant := _predicted_reference_body(entry, pos)
	if dominant == null:
		return PackedVector3Array()
	var vel: Vector3 = entry["velocity"]
	var r_vec := pos - dominant.position
	var r := r_vec.length()
	if r < GravitySystem.MIN_ORBIT_RADIUS:
		return PackedVector3Array()
	var mu := gravity.g * dominant.mass
	var v := vel.length()
	var energy := v * v / 2.0 - mu / r
	if energy >= 0.0:
		if log_events:
			_log_event("%s is unbound from %s (energy %.4f)" % [entry["name"], dominant.name, energy])
		return PackedVector3Array()  # unbound -- nothing periodic to draw
	var a := -mu / (2.0 * energy)
	var h_vec := r_vec.cross(vel)
	var h := h_vec.length()
	if h < 0.001:
		return PackedVector3Array()
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * h * h / (mu * mu)))
	# Eccentricity vector points from the focus to periapsis -- the ellipse's
	# own long axis, not an arbitrary reference direction.
	var e_vec := (vel.cross(h_vec) / mu) - r_vec.normalized()
	var basis1 := e_vec.normalized() if e > 0.01 else r_vec.normalized()
	var basis2 := h_vec.normalized().cross(basis1).normalized()
	var points := PackedVector3Array()
	points.resize(segments + 1)
	for i in segments + 1:
		var theta := TAU * float(i) / float(segments)
		var radius := a * (1.0 - e * e) / (1.0 + e * cos(theta))
		points[i] = dominant.position + basis1 * (radius * cos(theta)) + basis2 * (radius * sin(theta))
	return points


func _rebuild_predicted_orbits() -> void:
	var container := _paths_container()
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR or entry["kind"] == BodyKind.ASTEROID:
			continue
		var points := predicted_orbit_points(entry)
		var body_name: String = entry["name"]
		var mesh_inst: MeshInstance3D = _predicted_meshes.get(body_name)
		if mesh_inst == null or not is_instance_valid(mesh_inst):
			mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "Predicted_%s" % body_name
			mesh_inst.material_override = _line_material(Color(Palette.color("ui_accent"), 0.55))
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			container.add_child(mesh_inst)
			_predicted_meshes[body_name] = mesh_inst
		mesh_inst.mesh = _make_line_mesh(points)


func _update_actual_trails(delta: float) -> void:
	if not show_actual_trails:
		return
	_trail_timer += delta
	if _trail_timer < TRAIL_SAMPLE_INTERVAL:
		return
	_trail_timer = 0.0
	var container := _paths_container()
	for entry in bodies:
		if entry["kind"] == BodyKind.STAR or entry["kind"] == BodyKind.ASTEROID:
			continue
		var body_name: String = entry["name"]
		var history: PackedVector3Array = _trail_history.get(body_name, PackedVector3Array())
		history.append((entry["node"] as Node3D).position)
		if history.size() > TRAIL_MAX_POINTS:
			history = history.slice(history.size() - TRAIL_MAX_POINTS)
		_trail_history[body_name] = history
		var mesh_inst: MeshInstance3D = _trail_meshes.get(body_name)
		if mesh_inst == null or not is_instance_valid(mesh_inst):
			mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "Trail_%s" % body_name
			mesh_inst.material_override = _line_material(Color(Palette.color("ui_warn"), 0.6))
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			container.add_child(mesh_inst)
			_trail_meshes[body_name] = mesh_inst
		mesh_inst.mesh = _make_line_mesh(history)


func _clear_meshes(dict: Dictionary) -> void:
	for node: Variant in dict.values():
		if node is Node and is_instance_valid(node):
			(node as Node).queue_free()
	dict.clear()


func _make_line_mesh(points: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return mesh


func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	return mat


# --- Visuals -------------------------------------------------------------------

## Deterministic per-vertex hash, not [RandomNumberGenerator] — [method
## _build_rock_mesh] calls this once per vertex of a shared base sphere, and a
## stateful RNG's draw order would depend on vertex iteration order (which
## [SurfaceTool] doesn't promise), silently reshuffling the rock's bumps
## between engine versions. A closed-form hash of the vertex's own direction
## is order-independent and exactly reproducible from [param seed_v] alone.
func _rock_hash(dir: Vector3, seed_v: float) -> float:
	var x := sin(dir.dot(Vector3(12.9898, 78.233, 37.719)) + seed_v) * 43758.5453
	return x - floor(x)


## A chunky, irregular low-poly rock — plain uniformly-scaled spheres are what
## made the belts read as "marbles", not asteroids. Self-contained (a few value
## -noise bumps over a low-res UV sphere, deindexed so the facets stay flat
## rather than smooth-shaded like a lumpy ball) rather than reaching into
## ship_builder's LowPoly/MeshRounding pipeline for this — this module has no
## other need for that machinery (see the class doc's module-isolation rule).
## [param seed_v] picks the bump pattern; every call with the same seed
## reproduces the same rock.
func _build_rock_mesh(seed_v: float) -> ArrayMesh:
	var base := SphereMesh.new()
	base.radius = 1.0
	base.height = 2.0
	base.radial_segments = 8
	base.rings = 5
	var st := SurfaceTool.new()
	st.create_from(base, 0)
	st.deindex()
	var flat := st.commit()
	var arrays := flat.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var dir := verts[i].normalized()
		var n := _rock_hash(dir * 2.7, seed_v) + _rock_hash(dir * 5.3, seed_v + 19.0) * 0.5
		var r := 1.0 + (n - 0.6) * 0.55
		verts[i] = dir * r
	arrays[Mesh.ARRAY_VERTEX] = verts
	# Leave the stale (pre-displacement) normals in place rather than clearing
	# them to an empty array — a normals array whose size doesn't match the
	# vertex count makes add_surface_from_arrays reject the surface outright.
	# generate_normals() below recomputes them from the displaced geometry
	# regardless of what's here now.
	var displaced := ArrayMesh.new()
	displaced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Vertices are already deindexed (one per triangle corner), so regenerating
	# normals here has nothing to average across — each face gets its own flat
	# normal instead of the smooth ball's blended ones.
	var st2 := SurfaceTool.new()
	st2.create_from(displaced, 0)
	st2.generate_normals()
	return st2.commit()


## A live, individually-simulated asteroid — its own unique [method
## _build_rock_mesh] (seeded from [param mesh_seed]), unlike [method
## _build_belt_lumped]'s one shared mesh across the whole MultiMesh belt. Cheap
## at LIVE rock counts (dozens, not the hundreds a LUMPED belt can hold) and
## gives each promoted rock its own irregular shape instead of just its own
## scale. The mesh is unit-sized (radius 1) — the caller's own [member
## Node3D.scale] (radius × its per-axis jitter, see [method _belt_rock_specs])
## is what sizes it, so this doesn't collide with that.
func _make_rock_body(node_name: String, mesh_seed: int) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = _build_rock_mesh(float(mesh_seed))
	inst.material_override = _body_material(Palette.color("metal_mid"))
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return inst


func _make_sphere_body(node_name: String, radius: float, color: Color, emissive: bool) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = ShipMaterials.glow_material(color) if emissive else _body_material(color)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if emissive \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return inst


## Same part-shader/palette pipeline every ship hull and rock in the game uses
## (see space_scene.gd's `_rock_material`), so generated bodies read as part of
## this game's cartoony style rather than a placeholder grey sphere. Only
## asteroids use this now — planets and moons build through [Planet] instead
## (see [method _make_planet_node]).
func _body_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ShipMaterials.part_shader()
	var c := Palette.get_sat_lifted_color(color)
	mat.set_shader_parameter("primary_color", c)
	mat.set_shader_parameter("accent_color", c)
	mat.set_shader_parameter("trim_color", c.lightened(0.15))
	mat.set_shader_parameter("metallic_amount", 0.05)
	mat.set_shader_parameter("roughness_amount", 0.85)
	mat.set_shader_parameter("specular_amount", 0.2)
	mat.set_shader_parameter("rim_strength", 0.3)
	mat.set_shader_parameter("ao_strength", 0.3)
	mat.set_shader_parameter("solidity", 0.6)
	ShipMaterials.apply_style_dials(mat)
	return mat


## A real [Planet], built from [param data] — the same procedural-surface
## pipeline [SpaceScene] flies past, so a generated world looks like part of
## this game rather than a placeholder sphere.
func _make_planet_node(node_name: String, data: PlanetData) -> Planet:
	var planet := Planet.new()
	planet.name = node_name
	planet.configure(data)
	return planet


## A randomised [PlanetData] for a freshly-generated planet or moon. Moons get
## a cheaper build (lower resolution, no rings/atmosphere/clouds) since a
## system can carry several times as many of them as planets.
func _random_planet_data(radius: float, is_moon: bool) -> PlanetData:
	var data := PlanetData.new()
	data.seed_value = _rng.randi()
	data.planet_radius = radius
	if high_res_geometry:
		data.sphere_resolution = 24 if is_moon else 48
	else:
		data.sphere_resolution = 16 if is_moon else 32
	var gas_giant := (not is_moon) and _rng.randf() < gas_giant_chance
	data.planet_type = PlanetData.PlanetType.GAS_GIANT if gas_giant else PlanetData.PlanetType.ROCKY
	# Anchored to the palette's planet hues rather than the whole colour wheel —
	# see [method Palette.planet_color]. The jitter is what keeps a system's worlds
	# from being eight copies of one colour.
	var hue_index := _rng.randi()
	data.primary_color = Palette.planet_color(hue_index, PLANET_HUE_JITTER, _rng)
	data.secondary_color = data.primary_color.lightened(0.2)
	data.water_color = Palette.planet_sea(data.primary_color, _rng.randf_range(0.10, 0.35))
	data.ice_amount = _rng.randf() * (0.15 if gas_giant else 0.6)
	data.terrain_height = 0.0 if gas_giant else lerpf(0.02, 0.09, _rng.randf())
	data.continent_scale = lerpf(0.6, 2.2, _rng.randf())
	data.mountain_scale = lerpf(2.0, 7.0, _rng.randf())
	data.ridge_strength = lerpf(0.2, 0.6, _rng.randf())
	data.sea_level = lerpf(0.35, 0.55, _rng.randf())
	data.band_count = lerpf(4.0, 14.0, _rng.randf())
	data.swirl_speed = lerpf(0.05, 0.3, _rng.randf())
	data.swirl_scale = lerpf(1.5, 5.0, _rng.randf())
	data.detail_strength = lerpf(0.05, 0.2, _rng.randf())
	# Axis spin: visible variety, some worlds barely turning, others fast.
	data.rotation_speed = lerpf(0.004, 0.05, _rng.randf())
	if not is_moon:
		data.ring_enabled = _rng.randf() < ring_chance
		if data.ring_enabled:
			data.ring_inner_radius = lerpf(1.3, 1.6, _rng.randf())
			data.ring_outer_radius = lerpf(1.9, 2.6, _rng.randf())
			data.ring_color_a = Palette.color("planet_ring").lightened(_rng.randf_range(0.0, 0.2))
			data.ring_color_b = Palette.color("planet_ring").darkened(_rng.randf_range(0.15, 0.35))
		if _rng.randf() < atmosphere_chance:
			data.atmosphere_density = lerpf(0.15, 0.6, _rng.randf())
			data.atmosphere_color = Palette.planet_sky(
				data.primary_color, _rng.randf_range(-0.08, 0.08), 0.30
			)
		if _rng.randf() < cloud_chance:
			data.cloud_density = lerpf(0.2, 0.6, _rng.randf())
			data.cloud_color = Palette.color("planet_cloud")
	# Orbit dials the generator reads straight back out (see _spawn_planet and
	# _spawn_moons) — kept on the data itself so the planet editor or any other
	# consumer sees the same numbers a hand-authored planet would tune. Capped
	# tighter than the field's own editable range (see PLANET_DENSITY's doc on
	# why orbit_strength must not push a planet's registered mass too close to
	# the star's).
	data.orbit_strength = lerpf(0.7, 1.35, _rng.randf())
	data.orbit_speed = lerpf(1.0 - orbit_eccentricity, 1.0 + orbit_eccentricity, _rng.randf())
	return data
