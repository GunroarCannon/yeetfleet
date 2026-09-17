## Flies the test bed without a pilot and checks that it did something.
##
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/flight_smoke.gd
##
## The point of a smoke test on a flight model is not that the numbers are right —
## no automated check can tell you a ship feels good — but that every control is
## actually wired to the thing it names. A throttle that moves no ship, a stick
## that turns nothing, a boost that spends no charge and a view button that
## changes no camera are all silent failures that look fine in a screenshot.
extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"
## Frames spent on each step. Enough for the physics to accumulate a visible
## result, short enough that the whole run is a few seconds. Steps that need
## longer than one tick to show their effect are simply listed twice: setting a
## control and measuring it are always separate steps here, because a value read
## in the same call that wrote it has had no physics frame to respond.
const FRAMES_PER_STEP := 30

var _root: FlightRoot
var _steps: Array[Dictionary] = []
var _index := 0
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("flight smoke: cannot load " + SCENE_PATH)
		quit(1)
		return
	_root = packed.instantiate() as FlightRoot
	if _root == null:
		push_error("flight smoke: scene root is not a FlightRoot")
		quit(1)
		return
	root.add_child(_root)
	# The instruction card is modal by design and would sit over the whole test.
	_root.get_node("Ui/Coach").visible = false
	_build_steps()
	print("── Flight test bed smoke test ────────────────────────────")
	print("  %s   %d steps" % [SCENE_PATH.get_file(), _steps.size()])
	print("")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % FRAMES_PER_STEP != 0:
		return false
	if _index >= _steps.size():
		return _finish()
	var step := _steps[_index]
	_index += 1
	var before := _failures.size()
	(step["fn"] as Callable).call()
	print("  %-38s %s" % [String(step["name"]), "ok" if _failures.size() == before else "FAIL"])
	return false


func _finish() -> bool:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
		return true
	print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
	for f in _failures:
		print("  · " + f)
	quit(1)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _add(step_name: String, fn: Callable) -> void:
	_steps.append({"name": step_name, "fn": fn})


# --- The flight ------------------------------------------------------------

var _cruise_speed := 0.0
var _speed_before_stop := 0.0
var _heading := Vector3.ZERO


func _build_steps() -> void:
	_add("ship assembled and configured", _step_assembled)
	_add("starts at rest", _step_at_rest)
	_add("throttle up", func() -> void: _root.set_throttle(1.0))
	_add("  accelerating", _step_accelerating)
	for i in 4:
		_add("  spooling up (%d/4)" % (i + 1), func() -> void: pass)
	_add("reaches its designed speed", _step_cruise)
	_add("stick hard over", _step_turn)
	_add("  the ship turned", _step_turned)
	_add("boost spends capacitor", _step_boost)
	_add("guns fire", _step_fire)
	_add("throttle to stop", _step_stop)
	_add("  the ship slowed", _step_slowed)
	_add("assist toggles", _step_manual)
	_add("every camera view", _step_views)
	_add("drift field toggles", _step_drift)
	_add("spawns into SpaceScene with landmarks", _step_space_scene)
	_add("  flies into the planet", _step_planet_hit)
	_add("    bounced off its surface", _step_planet_bounced)
	_add("test volume toggles and back", _step_location)
	_add("respawn returns to the start", _step_respawn)


func _step_assembled() -> void:
	_check(_root.view != null, "no ShipView in flight")
	_check(_root.model != null, "no FlightModel")
	_check(_root.camera_node() != null, "the camera rig produced no camera")
	_check(
		_root.camera_mode() == FlightCamera.Mode.CHASE,
		"the test bed did not start in third person"
	)
	_check(_root.model.top_speed > 0.0, "the design resolved to no top speed")
	_check(_root.view.resolution.part_count() > 0, "flying an empty design")
	_check(_root.location_is_space(), "the test bed did not start in SpaceScene")
	_check(_root.space != null, "SpaceScene was not instantiated")
	_check(_root.drift_field_on(), "the drift field was off with SpaceScene present")


func _step_at_rest() -> void:
	if _root.location_is_space():
		_check(_root.model.velocity.length() > 0.0, "the ship had no orbital velocity in space")
	else:
		_check(_root.model.velocity.length() < 1.0, "the ship was already moving at spawn")


func _step_accelerating() -> void:
	_check(_root.model.forward_speed() > 1.0, "full throttle produced no acceleration")


func _step_cruise() -> void:
	_cruise_speed = _root.model.forward_speed()
	_heading = -_root.model.global_transform.basis.z
	# Assist holds the throttle's speed, so cruise should land near the design's
	# own figure rather than anywhere at all.
	_check(
		_cruise_speed > _root.model.top_speed * 0.5,
		"cruise (%.0f) never approached top speed (%.0f)" % [_cruise_speed, _root.model.top_speed]
	)


func _step_turn() -> void:
	_heading = -_root.model.global_transform.basis.z
	_root.set_stick(Vector2(0.8, -0.5))


func _step_turned() -> void:
	var turned := -_root.model.global_transform.basis.z
	_check(
		turned.dot(_heading) < 0.999,
		"a full stick deflection turned the ship nowhere"
	)
	_root.set_stick(Vector2.ZERO)


func _step_boost() -> void:
	var before := _root.systems.energy
	_root.set_boosting(true)
	_check(before > 0.0, "the capacitor was empty before boosting")


func _step_fire() -> void:
	_root.set_boosting(false)
	_check(
		_root.model.boost_level > 0.0 or _root.model.command.boost,
		"holding boost neither spooled nor registered"
	)
	_root.set_firing(true)


func _step_stop() -> void:
	_check(
		_root.systems.shots_fired > 0 or _root.view.muzzles.is_empty(),
		"a ship with guns fitted fired nothing"
	)
	_root.set_firing(false)
	_speed_before_stop = _root.model.forward_speed()
	_root.set_throttle(ThrottleLever.MIN_VALUE)


func _step_slowed() -> void:
	_check(
		_root.model.forward_speed() < _speed_before_stop,
		"closing the throttle did not slow the ship (%.0f -> %.0f)" % [
			_speed_before_stop, _root.model.forward_speed()
		]
	)
	_root.set_throttle(0.0)


func _step_manual() -> void:
	# Assist now defaults ON and the toggle is a 3-state cycle (manual → damping
	# → assist), so assert a toggle changes state, then toggle until it restores.
	var was := _root.assist_enabled()
	_root.toggle_assist()
	_check(_root.assist_enabled() != was, "the assist toggle did not take")
	for i in 3:
		if _root.assist_enabled() == was:
			break
		_root.toggle_assist()
	_check(_root.assist_enabled() == was, "the assist toggle would not go back")


func _step_views() -> void:
	for mode: int in [FlightCamera.Mode.COCKPIT, FlightCamera.Mode.ORBIT, FlightCamera.Mode.CHASE, FlightCamera.Mode.FAR, FlightCamera.Mode.PLANET, FlightCamera.Mode.FREE]:
		_root.set_view(mode)
		_check(_root.camera_mode() == mode, "camera refused view %d" % mode)
		_check(_root.camera_mode_label() != "", "camera view %d has no label" % mode)
	# The player indicator is armed in every external view, never in the three
	# that keep the player in frame.
	var hud := _root._hud
	_root.set_view(FlightCamera.Mode.COCKPIT)
	_check(not hud.player_indicator_active(), "player indicator armed in cockpit")
	_root.set_view(FlightCamera.Mode.CHASE)
	_check(not hud.player_indicator_active(), "player indicator armed in chase")
	_root.set_view(FlightCamera.Mode.REAR)
	_check(not hud.player_indicator_active(), "player indicator armed in rear")
	_root.set_view(FlightCamera.Mode.FAR)
	_check(hud.player_indicator_active(), "player indicator off in far view")
	_root.set_view(FlightCamera.Mode.PLANET)
	_check(hud.player_indicator_active(), "player indicator off in planet view")
	_root.set_view(FlightCamera.Mode.FREE)
	_check(hud.player_indicator_active(), "player indicator off in free view")


func _step_drift() -> void:
	var was := _root.drift_field_on()
	_root.toggle_drift_field()
	_check(_root.drift_field_on() != was, "the drift field toggle did nothing")
	_root.toggle_drift_field()
	_check(_root.drift_field_on() == was, "the drift field toggle would not go back")


func _step_space_scene() -> void:
	_check(not _root.landmarks().is_empty(), "SpaceScene reported no landmarks to the HUD")
	_check(_root.camera_rig.space == _root.space, "FlightCamera was never handed the space scene")


## The planet is rendered from a saved [PlanetData] now, so how big it looks is
## content in res://data/planets — while the collision that stops the ship is still
## a distance check against [constant SpaceScene.PLANET_RADIUS] in [FlightModel].
## If those two ever drift apart the player flies through the surface, or bounces
## off empty space a hundred metres above it.
func _step_planet_hit() -> void:
	var planet := _root.space.get_node_or_null("Planet/Body") as Planet
	_check(planet != null, "SpaceScene's planet is not a Planet node")
	if planet != null:
		_check(
			is_equal_approx(planet.data.planet_radius, SpaceScene.PLANET_RADIUS),
			"the planet is drawn at r %.0f but the ship stops at r %.0f" % [
				planet.data.planet_radius, SpaceScene.PLANET_RADIUS,
			]
		)
	# Well inside the surface, and off-centre: at the exact centre there is no
	# direction to be pushed out along.
	_root.model.global_position = SpaceScene.PLANET_CENTRE + Vector3(0.0, 0.0, 200.0)


func _step_planet_bounced() -> void:
	var dist := _root.model.global_position.distance_to(SpaceScene.PLANET_CENTRE)
	# A window rather than an exact number, because the bounce leaves the ship with
	# a little velocity and this is measured a few frames later. Assist now defaults
	# on, which changes the approach speed, so the window is generous: the point of
	# the check is "bounced near the surface, did not fly through".
	_check(
		absf(dist - (SpaceScene.PLANET_RADIUS + 5.0)) < 250.0,
		"the ship ended up %.0f m from the planet centre, not %.0f" % [
			dist, SpaceScene.PLANET_RADIUS + 5.0,
		]
	)


func _step_location() -> void:
	_root.toggle_location()
	_check(not _root.location_is_space(), "toggling location did not leave SpaceScene")
	_check(_root.space == null, "SpaceScene was not torn down when leaving it")
	_check(_root.drift_field_on(), "the drift field did not turn on in the test volume")
	_check(_root.landmarks().is_empty(), "the test volume reported landmarks")
	# Location now cycles Space ↔ Test volume, so one toggle returns to Space.
	_root.toggle_location()
	_check(_root.location_is_space(), "toggling location did not return to SpaceScene")
	_check(_root.space != null, "SpaceScene was not rebuilt on returning to it")
	_check(not _root.landmarks().is_empty(), "landmarks did not come back with SpaceScene")


func _step_respawn() -> void:
	var flown := _root.model.global_position.distance_to(_root._spawn.origin)
	_check(flown > 10.0, "the ship never actually went anywhere (%.1f m)" % flown)
	_root.respawn()
	_check(
		_root.model.global_position.distance_to(_root._spawn.origin) < 0.01,
		"respawn did not put the ship back at the start"
	)
	_check(_root.model.velocity.length() < 0.01, "respawn left the ship moving")
