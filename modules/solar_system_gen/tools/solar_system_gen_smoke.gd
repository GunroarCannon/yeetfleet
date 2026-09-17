## Headless smoke test for modules/solar_system_gen: proves generated systems
## actually orbit under real gravity rather than just instantiating without error.
##
##     godot --path . --headless --script modules/solar_system_gen/tools/solar_system_gen_smoke.gd
##
## Runs the generator's own simulation step directly (no scene tree, no engine
## frame timing) so results are fully deterministic — no dependency on render
## frame pacing, and only fixed candidate seeds are ever tried, never a live
## RNG draw whose outcome could vary run to run (see the orbit_check.gd
## AiSpawner flakiness this project already hit once).
##
## Verified:
##   - a generated planet holds a stable orbit around its star
##   - a moon's dominant body is its planet, not the star — nested orbits work
##   - an asteroid ring dropped near a planet reads as that planet's belt; the
##     same call dropped between planets reads as the system's belt
##   - a distance_scale preset actually changes orbit distance
##   - time_scale actually changes how far a body moves per real step
##   - a fresh orbit's initial speed matches the actual (blended) local field
##   - two overlapping bodies bounce apart instead of passing through
extends SceneTree

const DT := 1.0 / 60.0
var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── solar_system_gen smoke test ─────────────────────────")
	_test_planet_orbits_star()
	_test_moon_orbits_planet()
	_test_asteroid_belt_targets()
	_test_distance_scale()
	_test_time_scale()
	_test_orbit_velocity_matches_field()
	_test_collision_bounce()
	_test_randomize_unlocked_params()
	_test_moon_chance_and_belt_chance()
	_test_belt_lod_promotes_and_demotes()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


func _step(gen: SolarSystemGenerator, seconds: float) -> void:
	var steps := int(seconds / DT)
	for _i in steps:
		gen._physics_process(DT)


func _test_planet_orbits_star() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 42
	gen.planet_count = 3
	gen.generate_system()

	var planet: Dictionary = gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]
	var star_name: String = gen.bodies[0]["name"]
	var node: Node3D = planet["node"]
	var d0 := node.position.length()

	var dominant := gen.gravity.find_dominant_body(node.position)
	_check(dominant != null and dominant.name == star_name, "planet's dominant body is not the star (%s)" % [dominant.name if dominant else "null"])

	var d_min := d0
	var d_max := d0
	# 8 sim-seconds is several orbit fractions at this scale/mass — enough to
	# reveal a spiral-in or an escape, the same invariant orbit_check.gd checks
	# for the hand-built system.
	for _i in 8:
		_step(gen, 1.0)
		var d := node.position.length()
		d_min = minf(d_min, d)
		d_max = maxf(d_max, d)
	print("  planet orbit: start=%.0f min=%.0f max=%.0f" % [d0, d_min, d_max])
	_check(d_min > d0 * 0.6, "planet spiralled toward the star (%.0f -> %.0f)" % [d0, d_min])
	_check(d_max < d0 * 1.4, "planet escaped its orbit (%.0f -> %.0f)" % [d0, d_max])
	_done("Planet orbits its star")


func _test_moon_orbits_planet() -> void:
	var gen: SolarSystemGenerator = null
	var moon: Dictionary = {}
	# Moon count per planet is randomised (0..3); try a fixed, deterministic
	# list of candidate seeds until one produces a moon rather than trusting a
	# single seed to always do so.
	for seed_candidate in [42, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		gen = SolarSystemGenerator.new()
		gen.system_seed = seed_candidate
		gen.planet_count = 4
		gen.generate_system()
		var moons := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.MOON)
		if not moons.is_empty():
			moon = moons[0]
			break

	if moon.is_empty():
		_failures.append("no seed in the candidate list produced a moon — cannot test nesting")
		_done("Moon orbits its planet, not the star")
		return

	var moon_node: Node3D = moon["node"]
	var planet_name: String = String(moon["name"]).split("_Moon_")[0]
	var planet_entry := gen.find_body(planet_name)
	var planet_node: Node3D = planet_entry["node"]

	var dominant := gen.gravity.find_dominant_body(moon_node.position)
	_check(dominant != null and dominant.name == planet_name,
		"moon's dominant body is %s, expected its own planet %s" % [dominant.name if dominant else "null", planet_name])

	var d0 := moon_node.position.distance_to(planet_node.position)
	var planet_d0 := planet_node.position.length()
	_step(gen, 2.0)
	var d1 := moon_node.position.distance_to(planet_node.position)
	var planet_moved := planet_node.position.length() - planet_d0
	print("  moon-planet distance: start=%.0f now=%.0f | planet also moved %.0f from star" % [d0, d1, absf(planet_moved)])
	_check(absf(d1 - d0) < d0 * 0.5, "moon drifted far from its planet (%.0f -> %.0f)" % [d0, d1])
	_done("Moon orbits its planet, not the star")


func _test_asteroid_belt_targets() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 7
	gen.planet_count = 3
	gen.generate_system()

	var star_name: String = gen.bodies[0]["name"]
	var planet: Dictionary = gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]
	var planet_node: Node3D = planet["node"]
	var planet_name: String = planet["name"]
	var planet_gbody: GravitySystem.GravityBody = planet["gbody"]

	# A tight ring right around a planet should read as that planet's belt.
	# Half the planet's own Hill radius (same limit _spawn_moons clamps
	# against) rather than a fixed distance or raw planet-radius multiple --
	# a ring that far out from a *close-in* planet can sit closer to the star's
	# pull than the planet's even though it looks "tight" next to the planet.
	var near_radius := minf(planet_gbody.radius * 2.2 + 60.0, gen._hill_radius(planet_gbody, planet_node.position) * 0.5)
	# manual=true: this test inspects the rocks' own physics immediately, so it
	# needs the LIVE state rather than the default LUMPED (no-physics) one.
	gen.spawn_asteroid_belt(planet_node.position, near_radius, 6, 15.0, planet_name, true)
	var near_rocks := gen.bodies.slice(gen.bodies.size() - 6, gen.bodies.size())
	var near_ok := true
	for rock in near_rocks:
		var dominant := gen.gravity.find_dominant_body((rock["node"] as Node3D).position)
		if dominant == null or dominant.name != planet_name:
			near_ok = false
	_check(near_ok, "a ring dropped tight around %s did not orbit %s" % [planet_name, planet_name])

	# A wide ring well past every planet's orbit, far from any single planet,
	# should read as the system's own belt (the star dominates). Picking a
	# radius alone can't guarantee "far from every planet" -- two orbiting
	# rings can put a planet arbitrarily close to any given angle at a given
	# radius -- so the angle is chosen to maximize the minimum separation
	# from every planet's actual (randomised) position, at a radius modest
	# enough to stay well above the star's absolute accel floor.
	var planets := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)
	var outer_dist := float(gen.planet_count) * SolarSystemGenerator.PLANET_GAP * gen._distance_mult()
	var far_radius := outer_dist * 1.8
	var far_angle := 0.0
	var best_min_dist := -1.0
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var probe := Vector3(cos(angle), 0.0, sin(angle)) * far_radius
		var min_dist := INF
		for p in planets:
			min_dist = minf(min_dist, probe.distance_to((p["node"] as Node3D).position))
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			far_angle = angle
	var far_center := Vector3(cos(far_angle), 0.0, sin(far_angle)) * far_radius
	gen.spawn_asteroid_belt(far_center, 300.0, 6, 20.0, "", true)
	var far_rocks := gen.bodies.slice(gen.bodies.size() - 6, gen.bodies.size())
	var far_ok := true
	for rock in far_rocks:
		var dominant := gen.gravity.find_dominant_body((rock["node"] as Node3D).position)
		if dominant == null or dominant.name != star_name:
			far_ok = false
	_check(far_ok, "a ring dropped between planets did not orbit the star (%s)" % star_name)
	_done("Asteroid belt finds its own centre (planet vs system)")


func _test_distance_scale() -> void:
	var compact := SolarSystemGenerator.new()
	compact.system_seed = 5
	compact.planet_count = 2
	compact.distance_scale = 1.0
	compact.generate_system()

	var realistic := SolarSystemGenerator.new()
	realistic.system_seed = 5
	realistic.planet_count = 2
	realistic.distance_scale = 14.0
	realistic.generate_system()

	var c_planet: Dictionary = compact.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]
	var r_planet: Dictionary = realistic.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]
	var c_dist: float = (c_planet["node"] as Node3D).position.length()
	var r_dist: float = (r_planet["node"] as Node3D).position.length()
	print("  distance_scale: compact=%.0f realistic=%.0f" % [c_dist, r_dist])
	_check(r_dist > c_dist * 5.0, "distance_scale=14 did not spread orbits out (compact=%.0f realistic=%.0f)" % [c_dist, r_dist])
	_done("Distance scale changes orbit distance")


## The bug _orbit_velocity_at exists to fix: a moon placed near its planet's
## Hill limit (where the star's pull is no longer negligible) must not spiral
## away or in over the very first orbit fraction, the way the old
## isolated-two-body formula let it. Asteroid belts hit the same limit — see
## the class doc on why both use the same fix.
func _test_orbit_velocity_matches_field() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 3
	gen.planet_count = 3
	gen.generate_system()

	var planets := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)
	var worst_ratio := 0.0
	for planet_entry in planets:
		var node := planet_entry["node"] as Node3D
		var gbody := planet_entry["gbody"] as GravitySystem.GravityBody
		# Probe right at the moon-placement limit this generator itself uses.
		var probe_dist := gen._hill_radius(gbody, node.position) * 0.5
		if probe_dist == INF or probe_dist <= 0.0:
			continue
		var probe_pos := node.position + Vector3(probe_dist, 0.0, 0.0)
		var dominant := gen.gravity.find_dominant_body(probe_pos)
		if dominant == null:
			continue
		var d0 := probe_pos.distance_to(dominant.position)
		var vel := gen._orbit_velocity_at(probe_pos, dominant)
		# Step this single probe forward under the live field for a short
		# stretch and confirm it neither collapses nor escapes — the direct
		# behavioural check, not just "the formula ran".
		var pos := probe_pos
		var v := vel
		var d_min := d0
		var d_max := d0
		for _i in 300:
			var accel := gen.gravity.compute_gravity(pos)
			v += accel * 0.05
			pos += v * 0.05
			var d := pos.distance_to(dominant.position)
			d_min = minf(d_min, d)
			d_max = maxf(d_max, d)
		worst_ratio = maxf(worst_ratio, maxf(d0 / maxf(d_min, 0.001), d_max / d0))
	print("  orbit velocity at Hill-limit probes: worst drift ratio %.2f (want < 1.5)" % worst_ratio)
	_check(worst_ratio < 1.5, "a Hill-limit orbit drifted too fast (ratio %.2f) — spawn velocity didn't match the field" % worst_ratio)
	_done("Fresh orbits match the actual blended field, even near a Hill limit")


## Two bodies dropped on top of each other must separate and end up moving
## apart, not sit stacked forever — the "planets bump and bounce" behaviour.
func _test_collision_bounce() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 9
	gen.planet_count = 1
	gen.generate_system()

	var planet: Dictionary = gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]
	var node := planet["node"] as Node3D
	var radius: float = planet["radius"]

	# Drop a second body (reusing the moon spawn path so it's a real, gbody-less
	# mover) so it starts overlapping the planet.
	var intruder := gen._make_planet_node("Intruder", gen._random_planet_data(radius * 0.6, true))
	intruder.position = node.position + Vector3(radius * 0.5, 0.0, 0.0)
	gen.add_child(intruder)
	gen.bodies.append({
		"kind": SolarSystemGenerator.BodyKind.MOON, "name": "Intruder", "node": intruder,
		"velocity": Vector3.ZERO, "gbody": null, "radius": radius * 0.6,
		"mass": SolarSystemGenerator.MOON_DENSITY * pow(radius * 0.6, 3.0), "planet_data": null,
	})

	var start_dist := node.position.distance_to(intruder.position)
	for _i in 10:
		gen._physics_process(1.0 / 60.0)
	var end_dist := node.position.distance_to(intruder.position)
	print("  collision bounce: overlap start=%.1f end=%.1f (radii sum=%.1f)" % [start_dist, end_dist, radius * 1.6])
	_check(end_dist > start_dist, "two overlapping bodies did not separate after colliding (%.1f -> %.1f)" % [start_dist, end_dist])
	_check(end_dist >= radius * 1.6 - 1.0, "bodies are still overlapping after collision resolution (%.1f < %.1f)" % [end_dist, radius * 1.6])
	_done("Overlapping bodies bounce apart")


func _test_time_scale() -> void:
	var slow := SolarSystemGenerator.new()
	slow.system_seed = 5
	slow.planet_count = 2
	slow.time_scale = 1.0
	slow.generate_system()
	var slow_planet: Node3D = slow.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]["node"]
	var slow_start := slow_planet.position

	var fast := SolarSystemGenerator.new()
	fast.system_seed = 5
	fast.planet_count = 2
	fast.time_scale = 6.0
	fast.generate_system()
	var fast_planet: Node3D = fast.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)[0]["node"]
	var fast_start := fast_planet.position

	for _i in 30:
		slow._physics_process(DT)
		fast._physics_process(DT)

	var slow_moved := slow_planet.position.distance_to(slow_start)
	var fast_moved := fast_planet.position.distance_to(fast_start)
	print("  time_scale: 1x moved %.1f m, 6x moved %.1f m over the same real steps" % [slow_moved, fast_moved])
	_check(fast_moved > slow_moved * 2.0, "raising time_scale did not meaningfully speed up motion (1x=%.1f 6x=%.1f)" % [slow_moved, fast_moved])
	_done("time_scale speeds up the simulation")


## A locked dial must survive [method SolarSystemGenerator.randomize_unlocked_params];
## an unlocked one must actually reroll into its own schema range.
func _test_randomize_unlocked_params() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 7
	gen.planet_count = 4
	gen.locked["planet_count"] = true
	gen.gravity_strength_mult = -999.0  # sentinel, well outside the schema range
	gen.randomize_unlocked_params()
	_check(gen.planet_count == 4, "locked planet_count changed on reroll (%d)" % gen.planet_count)
	_check(gen.gravity_strength_mult >= 0.4 and gen.gravity_strength_mult <= 2.5,
		"unlocked gravity_strength_mult was not rerolled into its schema range (%.3f)" % gen.gravity_strength_mult)
	_done("randomize_unlocked_params respects per-dial locks")


## The Phase B generation dials must actually change what generates, not just
## exist as unread exported vars.
func _test_moon_chance_and_belt_chance() -> void:
	var no_moons := SolarSystemGenerator.new()
	no_moons.system_seed = 3
	no_moons.planet_count = 4
	no_moons.moon_chance = 0.0
	no_moons.generate_system()
	var moon_count := no_moons.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.MOON).size()
	_check(moon_count == 0, "moon_chance=0 still produced %d moons" % moon_count)

	var always_belt := SolarSystemGenerator.new()
	always_belt.system_seed = 3
	always_belt.planet_count = 2
	always_belt.planet_belt_chance = 1.0
	always_belt.generate_system()
	# Auto-spawned belts start LUMPED (no physics bodies) — see BeltState's doc
	# — so this checks the belt registry, not gen.bodies.
	_check(always_belt.belts.size() >= always_belt.planet_count,
		"planet_belt_chance=1.0 produced only %d belts for %d planets" % [always_belt.belts.size(), always_belt.planet_count])
	_done("moon_chance and planet_belt_chance dials take effect")


## An automatically spawned (non-manual) belt starts LUMPED with zero physics
## bodies, promotes to real per-rock bodies once a focus gets close, and
## demotes back once the focus leaves — the whole point of BeltState.
func _test_belt_lod_promotes_and_demotes() -> void:
	var gen := SolarSystemGenerator.new()
	gen.system_seed = 11
	gen.planet_count = 2
	gen.generate_system()
	var star_name: String = gen.bodies[0]["name"]
	var star_pos: Vector3 = (gen.bodies[0]["node"] as Node3D).position
	gen.spawn_asteroid_belt(star_pos, 500.0, 10, 40.0, star_name)  # not manual -> starts LUMPED
	var belt: Dictionary = gen.belts[0]

	_check(int(belt["state"]) == SolarSystemGenerator.BeltState.LUMPED, "auto-spawned belt did not start LUMPED")
	var rocks_while_lumped := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.ASTEROID).size()
	_check(rocks_while_lumped == 0, "a LUMPED belt registered real physics bodies (%d)" % rocks_while_lumped)

	# A focus right on top of the belt should promote it within one LOD tick.
	gen.set_lod_focus(star_pos, true)
	gen._physics_process(SolarSystemGenerator.BELT_LOD_CHECK_INTERVAL + 0.01)
	_check(int(belt["state"]) == SolarSystemGenerator.BeltState.LIVE, "belt did not promote to LIVE when the focus got close")
	var rocks_while_live := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.ASTEROID).size()
	_check(rocks_while_live == 10, "promoted belt did not register its rocks as real bodies (%d)" % rocks_while_live)

	# Pulling the focus far away demotes it back, freeing the physics cost.
	gen.set_lod_focus(star_pos + Vector3(1_000_000.0, 0.0, 0.0), true)
	gen._physics_process(SolarSystemGenerator.BELT_LOD_CHECK_INTERVAL + 0.01)
	_check(int(belt["state"]) == SolarSystemGenerator.BeltState.LUMPED, "belt did not demote back to LUMPED when the focus left")
	var rocks_after_demote := gen.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.ASTEROID).size()
	_check(rocks_after_demote == 0, "demoted belt left physics bodies behind (%d)" % rocks_after_demote)
	_done("Asteroid belt LOD promotes near a focus and demotes when it leaves")


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ " + f)
		quit(1)
