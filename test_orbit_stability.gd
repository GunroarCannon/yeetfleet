## Test script to check orbital stability across multiple seeds
extends SceneTree

const TEST_COUNT := 50
const SIM_TIME := 10.0  # seconds to simulate
const DT := 1.0 / 60.0

var _failures : Array[String]
var _tested : int
var _current_seed : int
var _generator : SolarSystemGenerator
var _sim_time : float
var _steps_done : bool
var _initial_distances : Array[float]
var _current_planets : Array[Dictionary]

func _initialize() -> void:
    _failures = []
    _tested = 0
    _current_seed = 0
    _sim_time = 0.0
    _steps_done = false
    _initial_distances = []
    _current_planets = []
    print("Testing orbital stability across %d seeds..." % TEST_COUNT)
    _test_next_seed()

func _test_next_seed() -> void:
    if _current_seed >= TEST_COUNT:
        _finish()
        return

    _generator = SolarSystemGenerator.new()
    _generator.system_seed = _current_seed
    _generator.planet_count = 6
    root.add_child(_generator)
    _generator.generate_system()

    # Skip if no planets were generated
    var planets : Array[Dictionary] = _generator.bodies.filter(func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET)
    if planets.is_empty():
        _generator.queue_free()
        _current_seed += 1
        _test_next_seed()
        return

    _tested += 1
    _sim_time = 0.0

    # Record initial distances from star
    var star_pos : Vector3 = _generator.bodies[0]["node"].position
    _initial_distances = []
    for planet in planets:
        var dist : float = (planet["node"] as Node3D).position.distance_to(star_pos)
        _initial_distances.append(dist)

    _current_planets = planets

func _finish() -> void:
    print("")
    print("Tested %d seeds" % _tested)
    if _failures.size() == 0:
        print("✓ ALL TESTS PASSED - No orbital instability detected")
    else:
        print("✗ FAILURES DETECTED (%d)" % _failures.size())
        for failure in _failures:
            print("  %s" % failure)

    quit(0 if _failures.size() == 0 else 1)

func _process(delta: float) -> bool:
    if _steps_done:
        return true

    _sim_time += delta
    if _sim_time >= SIM_TIME:
        _steps_done = true

        # Check if planets drifted too far or collided with star
        var star_pos : Vector3 = _generator.bodies[0]["node"].position
        for i in _current_planets.size():
            var planet : Dictionary = _current_planets[i]
            var current_dist : float = (planet["node"] as Node3D).position.distance_to(star_pos)
            var initial_dist : float = _initial_distances[i]

            # Check if planet fell into star (distance < 80% of initial)
            if current_dist < initial_dist * 0.8:
                _failures.append("Seed %d: Planet %d fell into star (%.0f -> %.0f)" % [_current_seed, i, initial_dist, current_dist])
                _generator.queue_free()
                _current_seed += 1
                _steps_done = false
                _test_next_seed()
                return true

            # Check if planet escaped (distance > 120% of initial)
            if current_dist > initial_dist * 1.2:
                _failures.append("Seed %d: Planet %d escaped orbit (%.0f -> %.0f)" % [_current_seed, i, initial_dist, current_dist])
                _generator.queue_free()
                _current_seed += 1
                _steps_done = false
                _test_next_seed()
                return true

        _generator.queue_free()
        _current_seed += 1
        _steps_done = false
        _test_next_seed()

    return false