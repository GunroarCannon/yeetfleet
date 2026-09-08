## The flight test bed: your built ship, a camera behind it, and nothing else.
##
## This is deliberately an empty volume rather than [SpaceScene]. A test rig for a
## flight model wants the flight model and no confounders — no planet to judge
## your attitude against, no asteroid belt to hide a tuning problem behind, no
## station to fly at instead of testing the turn rate. Black, and the ship.
##
## The one concession is the drift field: a sparse lattice of small motes that the
## ship flies through. Genuinely empty space gives the eye nothing at all to
## measure against, and a throttle test where full ahead and dead stop look
## identical is not a test. The motes exist only to make speed visible and are one
## menu item away from being switched off.
##
## Everything about the ship — geometry, mass, thrust, guns, exhausts — comes from
## the same [ShipDesign] the builder autosaved, through the same [ShipAssembler],
## so what flies here is exactly what was built there.
class_name FlightRoot
extends Node3D

enum Location {
	## The star, planet, station and belt of [SpaceScene] — the default, and by
	## far the cheapest step toward looking like the plan's reference shots.
	SPACE,
	## The bare volume this scene used to always be. Kept behind the ☰ menu for
	## a real reason: judging a flight-model change wants nothing else in frame
	## to mistake for the change itself.
	TEST_VOLUME,
}

## Distance between motes in the drift lattice, in metres. Roughly a fifth of a
## second at cruise, which is the spacing at which a passing speck reads as
## motion rather than as a flicker.
const MOTE_SPACING := 70.0
## Motes per axis. 9^3 is about seven hundred specks — enough that a few are
## always near enough to stream past, cheap enough for one MultiMesh draw.
const MOTE_COUNT := 9
const MOTE_SIZE := 0.55

## How fast the keyboard throttle keys move the lever, per second.
const THROTTLE_KEY_RATE := 0.8

## Popup instructions for this scene, shown once on the first visit.
const FLIGHT_STEPS: Array[Dictionary] = [
	{
		"title": "Test flight",
		"body": "This is your ship in open space, seen from behind. Other ships "
			+ "fly through the belt around you — some will shoot back if you get "
			+ "too close. The specks drifting past are there so you can see "
			+ "that you are moving.",
		"tip": "The icon buttons at the top left open the menus — view, combat, gravity, orbit and more.",
	},
	{
		"title": "Throttle and stick",
		"body": "The lever on the bottom left sets your speed; the pad on the "
			+ "bottom right steers. On a keyboard that is W and S for the "
			+ "throttle, the arrow keys for pitch and yaw, and Q and E to roll.",
		"tip": "The green tick beside the throttle is your actual speed. When it lags the lever, you are watching your ship's acceleration.",
	},
	{
		"title": "Assist, damping, manual",
		"body": "You start in DAMPING: thrust builds momentum and the ship slowly "
			+ "settles onto its heading — forgiving, but nothing flies for you. "
			+ "Cycle to full ASSIST and the ship goes where the nose points with "
			+ "the throttle holding a speed. Cycle to MANUAL for real momentum: "
			+ "thrust changes your velocity and nothing brings it back. "
			+ "The circle marker shows where you are actually heading.",
		"tip": "Z cycles flight modes (damping → assist → manual). V changes the camera.",
		"done": "Fly",
	},
]

var model: FlightModel
var camera_rig: FlightCamera
var systems: SystemsSim
var damage: DamageSystem

var library: PartLibrary
var design: ShipDesign
var view: ShipView

var location: Location = Location.SPACE
## Non-null only in [constant Location.SPACE]. [FlightCamera] reads it directly
## (see [member FlightCamera.space]) to recentre the sky dome on itself; nothing
## else about the rig's transform is Juice's or the location's to touch.
var space: SpaceScene = null

var _hud: FlightHud
var _coach: CoachOverlay
var _ship_holder: Node3D
var _motes: MultiMeshInstance3D
var _mote_field_on := true
## Smoothed 0..1 stretch of the drift motes into motion streaks, driven by speed.
var _mote_stretch := 0.0
## Whether the mote instance bases are currently written as streaks (so they get
## reset to identity once — not every frame — when the ship slows back down).
var _mote_writing_streak := false
## Above this speed (m/s) the drift motes stretch into velocity streaks.
const MOTE_STREAK_SPEED := 300.0
## How long a full-speed streak is, in units of the mote's own size.
const MOTE_STREAK_LEN := 16.0
## Cached world-space position of every drift mote, so the per-frame updater can
## rebuild a transform without a per-instance get (and skip the write entirely
## when nothing changed).
var _mote_positions := PackedVector3Array()
## The last stretch value actually written to the MultiMesh; the updater only
## rewrites instances when the stretch has moved past a visible threshold.
var _mote_stretch_written := 0.0
## The last streak direction written, so a turn at streak speed refreshes the
## streaks without rewriting them every frame of straight flight.
var _mote_streak_dir := Vector3.ZERO
var _env_holder: WorldEnvironment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _view_light: DirectionalLight3D
## All active debris nodes, tracked for drift and fade each frame.
var _debris_list: Array[Dictionary] = []

## Screen-space look drag, tracked here because the HUD's widgets each own their
## own gesture and whatever is left over is a look.
var _look_pointer := -1
var _looking := false
## Second screen-space pointer used to pan the FREE view. Separate from the look
## pointer so one finger orbits while the second pans — or the right mouse button
## pans on desktop.
var _pan_pointer := -1
var _panning := false

## Held state of the two on-screen hold buttons. Kept apart from the keyboard's
## own reading of the same actions; see [method _read_keyboard].
var _button_firing := false
var _button_boost := false
## Touch-to-accelerate: when the player holds anywhere on screen (that is not
## a widget), the ship accelerates forward. The throttle still sets the
## maximum speed; this just drives it to full while held. Only in the two
## views where looking IS flying — see [method _touch_accel_allowed].
var _touch_accel := false

var _ai_spawner: AiSpawner = null
var gravity: GravitySystem = null
var _gravity_viz: GravityVisualizer = null

## Gravity chaos: a debug toggle (Y) that slams the force law to cartoon
## extremes for wild slingshots and flung rocks. Off restores the live profile's
## own law. Reset whenever the world is rebuilt.
var _gravity_chaos := false
const GRAVITY_CHAOS_G := 9.0
const GRAVITY_CHAOS_FALLOFF := 1.55

## The scene's collision world (M1b). Built only for [constant Location.SPACE]:
## populated with the player's ship, AI ships (via the spawner) and every static
## collider SpaceScene exposes, then stepped by a [PhysWorldDriver] after all
## controllers have written their bodies' velocities. Null elsewhere — the test
## volume has no colliders and keeps the model's fallback collision. Torn down
## with the space scene so a freed SpaceScene never leaves bodies dangling.
var phys_world: PhysWorld = null
var _phys_profile: PhysProfile = null
var _phys_driver: PhysWorldDriver = null
## Every profile found in modules/physics/data/profiles, keyed by file base
## name, plus the current id. KEY_K cycles the live profile for honest A/B —
## the world reads its profile on every step, so swapping the Resource the
## world holds changes feel instantly, no rebuild.
var _phys_profiles: Dictionary = {}
var _phys_profile_ids: Array[String] = []
var _phys_profile_id := "cartoony"
## Rocks knocked loose into free bodies (rock promotion, M1). Tracked in the
## order they came loose, so the oldest can be put back to scenery when too many
## are flying.
var _live_rock_bodies: Array[PhysBody] = []
var _rock_demote_timer := 0.0
## Closing speed (m/s) above which a hit frees a rock from the belt.
const ROCK_KNOCK_SPEED := 18.0
## Tonnes per cubic metre of rock: a big boulder is heavy, a pebble is not.
const ROCK_MASS_DENSITY := 0.02
## How many rocks may fly at once before the oldest is put back.
const ROCK_LIVE_MAX := 20
## A live rock farther than this from the player is put back to scenery.
const ROCK_DEMOTE_RANGE := 2200.0
var _planet_pointer: PlanetPointer = null
var _spawn := Transform3D()
## Rear view camera: SubViewport + Camera3D looking backward from the ship.
var _rear_viewport: SubViewport = null
var _rear_camera: Camera3D = null
var _rear_texture_rect: TextureRect = null
var _rear_view_on := false


## The nodes are created here rather than in [method _ready] because Godot
## readies children before their parent, and [FlightHud] reaches back for the
## camera mode, the assist state and the ship's stats while it lays itself out.
## Anything the HUD touches has to *exist* by then, and the only point earlier
## than a child's _ready is the parent's _enter_tree.
##
## Only creation happens here. Binding does not: a node added during _enter_tree
## has not had its own _ready run yet, so [SystemsSim] has no scene sub-roots to
## hang its plumes on and [FlightCamera] has not made its camera. Those wait for
## [method _ready], by which time the whole subtree is up.
func _enter_tree() -> void:
	library = PartLibrary.instance()
	library.load_all()
	_load_design()

	# A scene restart reloads this node; land back in the location we were in.
	location = Session.flight_location
	_build_location()
	_build_gravity()
	_build_drift_field()
	# The drift field is the speed cue everywhere now — a disc of specks that
	# stream past, and stretch into streaks past 300 m/s. It used to be the test
	# volume's only marker; on by default in space too.
	_mote_field_on = true
	_motes.visible = _mote_field_on
	_build_ship()
	_build_camera()
	camera_rig.space = space
	camera_rig.gravity = gravity


## Binding and wiring, both of which need the subtree readied — and the HUD and
## the instruction card, which are scene children and do not exist at all until
## after [method _enter_tree] has run.
func _ready() -> void:
	_assemble()
	# Apply the Settings panel's persisted far values now that the camera exists
	# (it is created in FlightCamera._ready, so _enter_tree was too early).
	camera_rig.set_far_clip(_far_clip)
	camera_rig.set_far_view_max(_far_view_max)
	camera_rig.set_mode(FlightCamera.Mode.CHASE)
	camera_rig.adopt(model, model, view)
	# Start closer to Tarn IV so gravity is immediately noticeable.
	# Ship spawns in a stable orbit: correct tangential velocity and
	# faces along the orbit direction so flight assist keeps you in orbit.
	if location == Location.SPACE:
		# Orbit spawn distance scales with the planet so a scaled-up world still
		# spawns you in a readable orbit around it.
		var spawn_dist := space.planet_radius * 2.857
		var spawn_pos := space.planet_centre + Vector3(spawn_dist, 0.0, 0.0)
		model.global_position = spawn_pos
		if gravity != null:
			var dominant := gravity.find_dominant_body(spawn_pos)
			if dominant != null:
				# Full circular orbit velocity: v = sqrt(G*M/r).
				var v_orbit := gravity.orbit_velocity(dominant, spawn_dist)
				# Tangential direction: perpendicular to the radial vector.
				var radial := (spawn_pos - dominant.position).normalized()
				var tangent := Vector3(-radial.z, 0.0, radial.x).normalized()
				model.velocity = tangent * v_orbit
				# Face along the orbit direction so assist doesn't pull toward planet.
				var look_ahead := spawn_pos + tangent * 100.0
				model.global_transform.basis = Basis.looking_at(look_ahead - spawn_pos, Vector3.UP)
	_spawn = model.global_transform
	# Feed asteroid positions into the model for collision detection. The
	# SpaceScene populates its meta in its own _ready, which runs before this.
	if space != null and space.has_meta("asteroid_data"):
		model._asteroid_data = space.get_meta("asteroid_data") as Array	# Hand the gravity system to the flight model AND the space scene
	# (so the moon integrates via real gravity, not sine animation).
	if gravity != null:
		model.gravity = gravity
		if space != null:
			space.set_gravity(gravity)
	_setup_gravity_viz()
	# M1b: the physics layer. Must come after the ship is spawned and the space
	# scene has built its rocks — both are above — so the player's body can be
	# bound with its real mass and the scenery can be registered once.
	_build_phys_world()


	# The theme goes on the window rather than on a Control, because this scene's
	# root is a Node3D and has no theme of its own to propagate. Every Control
	# under it — HUD, card, popups — inherits from there.
	get_window().theme = BuilderTheme.build()

	_hud = %Hud as FlightHud
	# Re-apply persisted trail toggles after a scene restart: the preference flags
	# survive in static state, but the trail nodes themselves were rebuilt.
	set_trail_player(Session.trail_player)
	set_trail_ships(Session.trail_ships)
	_coach = %Coach as CoachOverlay
	_coach.steps = FLIGHT_STEPS
	_coach.walkthrough_id = "flight_walkthrough"
	_coach.start()

	systems.state_changed.connect(_on_systems_state)
	systems.fire_blocked.connect(func(reason: String) -> void: _hud.show_hint(reason))
	model.assist_changed.connect(func(_on: bool) -> void: _hud.show_hint(_assist_hint()))
	model.orbit_changed.connect(_on_orbit_changed)

	BuilderTheme.apply_density_scale(get_window())
	get_viewport().size_changed.connect(
		func() -> void: BuilderTheme.apply_density_scale(get_window())
	)

	# High-res renders the 3D scene at a higher internal resolution and
	# downscales to the viewport — same FOV, just sharper. The window size is
	# left alone (resizing it zoomed the stretch-scaled canvas).
	get_viewport().scaling_3d_scale = 1.5 if Session.high_res else 1.0


# --- Construction -----------------------------------------------------------

func _load_design() -> void:
	# Randomly pick a preset ship from the library so every test flight starts
	# with a different vessel, letting the player see how various builds handle.
	var presets: Array[Dictionary] = library.presets
	if not presets.is_empty():
		design = library.build_preset_design(
			String(presets[randi() % presets.size()].get("id", ""))
		)
	if design == null:
		design = library.default_design()
		library.autofill_required(design)
	if design != null:
		design.design_name = design.design_name + " (Random)"


## [constant Location.SPACE] gets [SpaceScene]'s own environment and lights for
## free; the test volume needs its own, built here, because it is deliberately
## nothing else.
func _build_location() -> void:
	if location == Location.SPACE:
		space = SpaceScene.new()
		space.name = "Space"
		add_child(space)
		# AI ships populate the belt. Only in SPACE — the test volume is for
		# flight-model tuning and has no confounders.
		_ai_spawner = AiSpawner.new()
		_ai_spawner.name = "AiSpawner"
		add_child(_ai_spawner)
	else:
		_build_test_volume_environment()


## Create the gravity system and register all gravitating bodies from
## [SpaceScene]'s constants. Gravity is off by default — the player
## toggles it with the G key. In the test volume, gravity stays off.
func _build_gravity() -> void:
	gravity = GravitySystem.new()
	if location != Location.SPACE or space == null:
		gravity.mode = GravitySystem.GravityMode.OFF
		return
	# Register planets. GAME_G = 3.0.
	# At 4000m from Tarn IV: accel = 3.0 * 1e7 / 16e6 ≈ 1.9 m/s² (noticeable curve).
	# At 2000m: accel ≈ 7.5 m/s² (strong pull, orbit at ~122 m/s).
	# Gravity weakens with distance — ships barely notice beyond 6000m.
	# Mass scales with radius² so a bigger planet pulls proportionally (surface
	# gravity stays comparable) and the moon's orbit stays stable when scaled.
	var mass_scale := Session.planet_scale * Session.planet_scale
	gravity.register_body(
		space.planet_centre, _gravity_mass("tarn_iv", 10000000.0) * mass_scale, space.planet_radius,
		"Tarn IV", true
	)
	gravity.register_body(
		space.planet2_centre, _gravity_mass("ashara", 2000000.0) * mass_scale, space.planet2_radius,
		"Ashara", true
	)
	gravity.register_body(
		space.planet3_centre, _gravity_mass("glacius", 500000.0) * mass_scale, space.planet3_radius,
		"Glacius", true
	)
	# Moon — orbits Tarn IV, and is heavy enough to hold *its own* orbiters. A
	# moon is "what orbits what" by strength and closeness: whoever pulls hardest
	# at a point wins. With its old tiny mass the planet swamped the moon even a
	# few hundred metres out, so nothing could ever orbit the moon. This mass
	# gives the moon a domination radius of ~1 km (scaled with the world like the
	# planets), so a ship or a station can genuinely settle into orbit around it.
	var moon_pos: Vector3 = space.planet_centre + Vector3(
		space.moon_orbit_radius, 0.0, 0.0
	)
	gravity.register_body(
		moon_pos, 2000000.0 * mass_scale, SpaceScene.MOON_RADIUS,
		"Tarn IV Moon", true
	)
	# Station — negligible pull.
	gravity.register_body(
		SpaceScene.STATION_POS, 10000.0, SpaceScene.STATION_RADIUS,
		"Ceres Gate", false
	)
	# The force law comes from the feel profile (g, falloff). Applied before the
	# ship spawns so the spawn orbit is computed for the same gravity the ship
	# will actually feel, and before the moon integrates so it starts matched.
	_apply_gravity_profile()
	# Gravity starts ON in space — player disables with G if desired.
	gravity.mode = GravitySystem.GravityMode.NORMAL


## The gravity mass (in game units) for a planet, from its saved PlanetData so the
## editor's "Gravity pull" slider actually changes how hard the world pulls in
## flight. Falls back to the scene's hardcoded value if the data is missing.
func _gravity_mass(id: String, fallback: float) -> float:
	var data := PlanetLibrary.instance().get_data(id)
	if data == null:
		return fallback
	return maxf(data.gravity_mass, 0.01) * 1000000.0


func _setup_gravity_viz() -> void:
	if _gravity_viz != null:
		if _gravity_viz.get_parent() != null:
			_gravity_viz.get_parent().remove_child(_gravity_viz)
		_gravity_viz.queue_free()
		_gravity_viz = null
	# Don't create until first toggle — nothing in the scene tree.


## Build the scene's [PhysWorld] (M1b). Only space has colliders; the tuning
## test volume keeps none and stays on the model's fallback collision.
func _build_phys_world() -> void:
	if location != Location.SPACE or space == null or model == null:
		return
	# _apply_gravity_profile in _build_gravity already selected the profile; this
	# just guarantees it is loaded even if gravity was not in play.
	_ensure_profile_selected()
	phys_world = PhysWorld.new(_phys_profile)
	# Free bodies (rocks knocked loose) fall and orbit under the scene's gravity.
	phys_world.gravity = gravity
	_live_rock_bodies.clear()
	_rock_demote_timer = 0.0

	var driver := PhysWorldDriver.new()
	driver.name = "PhysDriver"
	driver.world = phys_world
	add_child(driver)
	_phys_driver = driver

	# Static scenery: planets, the moon, the station and every rock become
	# kinematic bodies — infinite-mass walls with a radius. Rocks bounce the ship
	# per the profile's restitution until a hard knock frees one into a real body
	# (see [_method _on_rock_impacted]); each rock gets a volume-derived mass so
	# the knock it eventually takes is proportional to how heavy it looks.
	for collider in space.collision_statics():
		var body := PhysBody.new(1.0, float(collider["radius"]))
		body.node = collider["node"]
		body.layer = int(collider["layer"])
		body.kinematic = true
		if body.layer == PhysBody.Layer.ROCK:
			body.mass = body.radius * body.radius * body.radius * ROCK_MASS_DENSITY
			body.impacted.connect(_on_rock_impacted)
		phys_world.add(body)

	# The player's own ship: a driven body that keeps its hand integration.
	var hull_radius := 3.0
	if view != null:
		hull_radius = _ship_collision_radius(view.aabb)
	model.set_phys_world(phys_world, hull_radius)


## Drop the physics layer: unbind the player's body, free the driver, clear the
## world. Called when leaving space so a freed SpaceScene never leaves bodies
## pointing at its (now gone) collider nodes. The AI ships unbind themselves on
## teardown, which the caller runs before this.
func _teardown_phys_world() -> void:
	if model != null:
		model.clear_phys_world()
	if _phys_driver != null:
		_phys_driver.queue_free()
		_phys_driver = null
	phys_world = null
	_phys_profile = null
	_live_rock_bodies.clear()


## Load every .tres profile in modules/physics/data/profiles, keyed by file base
## name, so the A/B key can hot-swap the live profile without a Resource load.
## The physics lab authors new profiles here; anything saved lands in the cycle.
func _load_phys_profiles() -> void:
	_phys_profiles.clear()
	_phys_profile_ids.clear()
	var dir := "res://modules/physics/data/profiles"
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var loaded := load(dir.path_join(file)) as PhysProfile
		if loaded == null:
			continue
		var id := file.get_basename()
		_phys_profiles[id] = loaded
		_phys_profile_ids.append(id)
	if _phys_profile_ids.is_empty():
		_phys_profile_ids.append("default")


func _profiles_for_id(id: String) -> PhysProfile:
	return _phys_profiles.get(id) as PhysProfile


## Pick the current profile id's resource, loading the profile list first if it
## has not been scanned yet. Safe to call from gravity setup in _enter_tree.
func _ensure_profile_selected() -> void:
	if _phys_profiles.is_empty():
		_load_phys_profiles()
	if _phys_profile == null:
		_phys_profile = _profiles_for_id(_phys_profile_id)
		if _phys_profile == null:
			push_warning("FlightRoot: profile '%s' not in data/profiles — using built-in defaults" % _phys_profile_id)
			_phys_profile = PhysProfile.new()


## Push this profile's gravity law (g, falloff) into the GravitySystem and
## re-circularise the moon so nothing keeps orbiting under the old law. Called
## when a profile is applied at build and again when KEY_K cycles it.
func _apply_gravity_profile() -> void:
	if gravity == null:
		return
	# Any (re)apply of the profile's own law drops a chaos override, so Y's chaos
	# cannot leak across a profile cycle or a location rebuild.
	_gravity_chaos = false
	_ensure_profile_selected()
	gravity.apply_law(_phys_profile.gravity_g, _phys_profile.gravity_falloff)
	if space != null:
		space.sync_moon_orbit(gravity)


## Cycle the live feel profile (debug A/B, KEY_K). Returns the new id, or ""
## when there is no world to swap. Because the world and every FlightModel read
## profile.* live each step, the swap takes effect immediately.
func cycle_phys_profile() -> String:
	if phys_world == null or _phys_profile_ids.is_empty():
		return ""
	var idx := _phys_profile_ids.find(_phys_profile_id)
	idx = (idx + 1) % _phys_profile_ids.size()
	_phys_profile_id = _phys_profile_ids[idx]
	_phys_profile = _profiles_for_id(_phys_profile_id)
	if _phys_profile == null:
		_phys_profile = PhysProfile.new()
	phys_world.profile = _phys_profile
	# Gravity rides on the same feel profile: re-apply the law live so a cartoon
	# falloff actually turns into cartoon slingshots as soon as you press K.
	_apply_gravity_profile()
	return _phys_profile_id


## The name of the live profile, for the HUD.
func phys_profile_id() -> String:
	return _phys_profile_id


# --- Rock promotion (M1) ------------------------------------------------------

## A rock was hit hard enough to come loose. It stops being an immovable wall and
## becomes a free body: the world integrates it, gravity steers it, and its
## visual is drawn from its node each frame. It is given the velocity it would
## have taken from this hit if it had had mass all along (the solver resolved it
## as kinematic, so it absorbed the hit without moving).
func _on_rock_impacted(
	rock: PhysBody, _other: PhysBody, impulse: float, _point: Vector3, normal: Vector3, closing: float
) -> void:
	if not rock.kinematic or closing < ROCK_KNOCK_SPEED:
		return
	if _live_rock_bodies.size() >= ROCK_LIVE_MAX:
		_demote_rock(_live_rock_bodies[0])
	rock.kinematic = false
	# Velocity from momentum exchange, not impulse/rock.mass (which explodes for a
	# pebble): a rock of mass m_r hit at closing speed v by a ship of mass m_s
	# leaves at about v·m_s/(m_s+m_r). Small rocks fly, big boulders barely stir.
	var m_ship := _other.mass if _other != null and _other.mass > 0.0 else 30.0
	var speed := clampf(closing * 1.2 * m_ship / (m_ship + rock.mass), 0.0, 320.0)
	rock.velocity -= normal * speed
	if phys_world != null:
		phys_world.mark_scenery_dirty()
	_live_rock_bodies.append(rock)
	if space != null:
		space.set_rock_visual_live(rock, true)


## Put a flying rock back to scenery: it freezes where it is and becomes an
## immovable wall again. Idempotent.
func _demote_rock(rock: PhysBody) -> void:
	if rock == null:
		return
	_live_rock_bodies.erase(rock)
	if rock.kinematic:
		return
	rock.kinematic = true
	rock.velocity = Vector3.ZERO
	rock.angular = Vector3.ZERO
	if phys_world != null:
		phys_world.mark_scenery_dirty()
	if space != null:
		space.set_rock_visual_live(rock, false)


## Periodically put flying rocks back to scenery once they drift clear of the
## player, so knocked-loose rocks cannot accumulate forever. Once a second.
func _sweep_live_rocks() -> void:
	if _live_rock_bodies.is_empty():
		return
	var ref := model.global_position if model != null else Vector3.ZERO
	var to_demote: Array[PhysBody] = []
	for rock in _live_rock_bodies:
		if rock == null or rock.kinematic or rock.node == null or not is_instance_valid(rock.node):
			to_demote.append(rock)
		elif rock.node.global_position.distance_to(ref) > ROCK_DEMOTE_RANGE:
			to_demote.append(rock)
	for rock in to_demote:
		_demote_rock(rock)


## The collision-sphere radius for the assembled hull: half the bounding box's
## diagonal, i.e. the sphere that just contains the whole design. This replaces
## the old fixed +5/+3 standoffs (plan §3.1 #13) with a number that scales with
## the actual ship — a scout and a hauler no longer collide at the same size.
func _ship_collision_radius(bounds: AABB) -> float:
	return maxf(bounds.size.length() * 0.5, 3.0)


func _build_test_volume_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# The same cool ambient the builder stage uses, at the same strength. A ship
	# has to look like the ship you built: shipping it out here under a darker
	# sky than the hangar had is how a hull that read as painted metal on the
	# workbench turns into a silhouette in flight.
	env.ambient_light_color = Color(0.29, 0.35, 0.47)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	_env_holder = WorldEnvironment.new()
	_env_holder.name = "Environment"
	_env_holder.environment = env
	add_child(_env_holder)

	# Three lights and no shadows. The key and the fill are world-fixed, which is
	# most of how attitude is legible out here: roll the ship and you visibly
	# change which faces catch the light.
	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	_key_light.light_energy = 2.1
	_key_light.light_color = Color("fff1de")
	_key_light.shadow_enabled = false
	_key_light.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -0.7, -0.45), Vector3.UP)
	add_child(_key_light)

	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "FillLight"
	_fill_light.light_energy = 0.45
	_fill_light.light_color = Color("6b86c4")
	_fill_light.light_specular = 0.0
	_fill_light.shadow_enabled = false
	_fill_light.look_at_from_position(Vector3.ZERO, Vector3(0.6, 0.45, 0.65), Vector3.UP)
	add_child(_fill_light)

	# The third is aimed down the camera's own axis and re-aimed every frame.
	#
	# Two world-fixed lights cannot keep an arbitrarily-oriented ship readable:
	# fly away from the key and the chase camera is looking at the hull's shadow
	# side, which against a black background is not a ship at all, it is a hole.
	# A weak view-axis light guarantees the surface facing the player is always
	# lit *somewhat*, without flattening it — at this energy the key still decides
	# the form and this only rescues the floor.
	_view_light = DirectionalLight3D.new()
	_view_light.name = "ViewLight"
	_view_light.light_energy = 0.95
	_view_light.light_color = Color("c8d4e8")
	_view_light.light_specular = 0.25
	_view_light.shadow_enabled = false
	add_child(_view_light)


## A lattice of motionless specks the ship flies through.
##
## The whole lattice is teleported in whole-cell steps to stay centred on the
## ship, which makes it endless at the cost of nothing: because it only ever
## moves by an exact multiple of the spacing, every mote lands where a mote would
## have been anyway, and the field looks fixed in space no matter how far you
## fly. One [MultiMesh], one draw call, no per-frame allocation.
func _build_drift_field() -> void:
	# Round motes, not cubes — the specks read as particles, not as a grid.
	var mesh := SphereMesh.new()
	mesh.radius = MOTE_SIZE * 0.5
	mesh.height = MOTE_SIZE

	var rng := RandomNumberGenerator.new()
	rng.seed = 41973
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Per-instance colour, kept for a constant alpha. The motes must NOT fade in
	# and out with opacity: the field re-centres on the ship in whole-cell steps,
	# and a rim that fades to transparent reads as specks winking in and out.
	# Every mote gets the same alpha so the disc is a constant presence.
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MOTE_COUNT * MOTE_COUNT * MOTE_COUNT
	# A disc (cylinder), not a cube: polar sampling with sqrt so the motes are
	# evenly spread by area. A cube reads as a room; a disc reads as "space is
	# all around you", and the vertical thickness keeps a pitch-climb from
	# flying straight out the top.
	var radius := MOTE_SPACING * float(MOTE_COUNT - 1) * 0.5
	var thickness := MOTE_SPACING
	_mote_positions.resize(mm.instance_count)
	var colors := PackedColorArray()
	colors.resize(mm.instance_count)
	for i in mm.instance_count:
		var angle := rng.randf() * TAU
		# nf = 0 at the centre, 1 at the rim. It used to drive a per-mote alpha
		# fade at the disc's edge; the alpha is now uniform (see above) and nf
		# only shapes the disc's spread.
		var nf := sqrt(rng.randf())
		var pos := Vector3(
			cos(angle) * nf * radius,
			rng.randf_range(-thickness, thickness),
			sin(angle) * nf * radius
		)
		_mote_positions[i] = pos
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		colors[i] = Color(1.0, 1.0, 1.0, 0.45)
	mm.color_array = colors

	_motes = MultiMeshInstance3D.new()
	_motes.name = "DriftField"
	_motes.multimesh = mm
	# Dim on purpose. The motes are a speed gauge, not scenery: bright specks
	# against black out-read the hull and make the ship look like the dim thing
	# on screen, which is precisely backwards. Vertex colours feed the rim fade
	# (alpha per mote), so the material has to read them and be transparent.
	var mote_mat := ShipMaterials.glow_material(Color(0.34, 0.39, 0.50))
	mote_mat.vertex_color_use_as_albedo = true
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_motes.material_override = mote_mat
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The lattice origin can sit far from any mote that is on screen, so Godot
	# must not cull the whole field on the strength of its centre.
	_motes.extra_cull_margin = MOTE_SPACING * float(MOTE_COUNT)
	add_child(_motes)


## At speed the round motes stretch into streaks along the velocity vector — the
## field becomes a set of motion lines that read as "very fast" at a glance.
##
## The per-instance colours are baked once at build (their rim fade never moves),
## and the transforms are only rewritten when the streak basis actually changed:
## when the stretch has moved past a visible threshold, when the velocity turned
## at streak speed, or when crossing into/out of streak mode. Idle and straight
## cruise — the long common case — write nothing at all.
func _update_mote_streaks(delta: float) -> void:
	if model == null or _motes.multimesh == null:
		return
	var speed := model.velocity.length()
	var target := clampf((speed - MOTE_STREAK_SPEED) / 150.0, 0.0, 1.0)
	_mote_stretch = lerpf(_mote_stretch, target, clampf(delta * 6.0, 0.0, 1.0))
	var mm: MultiMesh = _motes.multimesh
	var dir := model.velocity.normalized()
	var write_streak := _mote_stretch > 0.01 and dir.length_squared() > 0.001

	# Everything below either returns without touching the MultiMesh or rewrites
	# all instances once. The threshold on the stretch is the visible step: a
	# 0.02 change in a 0..1 ramp is far below what the eye can pick out, so it is
	# safe to let the streak trail the acceleration by a couple of frames.
	var stretch_moved := absf(_mote_stretch - _mote_stretch_written) >= 0.02
	var turned := write_streak and _mote_streak_dir != Vector3.ZERO \
		and dir.dot(_mote_streak_dir) < 0.98
	if not stretch_moved and not turned and write_streak == _mote_writing_streak:
		return
	_mote_stretch_written = _mote_stretch
	_mote_writing_streak = write_streak
	if write_streak:
		_mote_streak_dir = dir
	else:
		_mote_streak_dir = Vector3.ZERO

	# Streak basis: long axis along the velocity vector.
	var streak := Basis()
	if write_streak:
		var up0 := Vector3.UP
		if absf(dir.dot(up0)) > 0.99:
			up0 = Vector3.FORWARD
		var z := dir.cross(up0).normalized()
		var y := z.cross(dir).normalized()
		var s := 1.0 + _mote_stretch * MOTE_STREAK_LEN
		streak = Basis(dir * s, y, z)

	for j in mm.instance_count:
		mm.set_instance_transform(j, Transform3D(streak, _mote_positions[j]))


func _build_ship() -> void:
	model = FlightModel.new()
	model.name = "Ship"
	add_child(model)

	_ship_holder = Node3D.new()
	_ship_holder.name = "Hull"
	model.add_child(_ship_holder)

	# Systems ride with the hull: plumes are placed in ship space and shots are
	# spawned from `global_transform * muzzle`, so this node has to *be* the ship.
	systems = SystemsSim.new()
	systems.name = "Systems"
	model.add_child(systems)

	damage = DamageSystem.new()


## Rebuild the flown ship from the current design. Separate from [method
## _build_ship] so a future "you edited your ship, here it is" path has one call
## to make.
func _assemble() -> void:
	if view != null:
		view.destroy()
	# No colliders and no socket markers: nothing raycasts the hull in flight, and
	# a ship covered in mount rings is a hangar view, not a cockpit view.
	view = ShipAssembler.assemble(design, library, 0.0, false, false)
	# The Ship-size setting scales the whole hull (and its offsets) at assembly.
	view.apply_scale(Session.ship_scale)
	_ship_holder.add_child(view.root)
	model.configure(view.resolution.stats, systems, damage)
	systems.bind(view, self)
	damage.bind(view, model, _ship_holder)
	damage.part_broken.connect(_on_part_broken)
	if camera_rig != null:
		camera_rig.adopt(model, model, view)


## Third person is the default and, for now, the view this scene exists to test:
## you cannot judge how a ship handles without watching it bank. The rig still
## carries the cockpit and external modes and the V key reaches them.
func _build_camera() -> void:
	camera_rig = FlightCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)


## Build the rear view: a small SubViewport with a backward-facing camera,
## displayed as a TextureRect in the top-right corner of the HUD.
func _build_rear_view() -> void:
	_rear_viewport = SubViewport.new()
	_rear_viewport.name = "RearView"
	_rear_viewport.size = Vector2i(200, 150)
	_rear_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rear_viewport.transparent_bg = false
	# Share the main World3D: a fresh world has no Environment and no lights, so
	# everything the rear camera sees renders pitch black. Sharing keeps the same
	# ambient, sun and view light the main view gets.
	_rear_viewport.own_world_3d = false
	add_child(_rear_viewport)

	_rear_camera = Camera3D.new()
	_rear_camera.name = "RearCamera"
	_rear_camera.fov = 80.0
	_rear_camera.near = 0.5
	# Match the main camera's far plane or the sky is clipped in the rear view
	# too, and "what is behind me" is a black wall instead of a starfield.
	_rear_camera.far = _far_clip
	_rear_viewport.add_child(_rear_camera)

	# TextureRect to display the rear view in the HUD.
	_rear_texture_rect = TextureRect.new()
	_rear_texture_rect.name = "RearViewDisplay"
	_rear_texture_rect.texture = _rear_viewport.get_texture()
	_rear_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rear_texture_rect.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rear_texture_rect.offset_right = -BuilderTheme.PAD
	_rear_texture_rect.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_rear_texture_rect.offset_left = -200.0 - BuilderTheme.PAD
	_rear_texture_rect.offset_bottom = 150.0 + BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_rear_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rear_texture_rect.visible = false
	# Add to HUD so it renders on top of the 3D scene.
	if _hud != null:
		_hud.add_child(_rear_texture_rect)


## Toggle the rear view camera on/off.
func toggle_rear_view() -> void:
	_rear_view_on = not _rear_view_on
	if _rear_viewport == null:
		_build_rear_view()
	_rear_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _rear_view_on else SubViewport.UPDATE_DISABLED
	if _rear_texture_rect != null:
		_rear_texture_rect.visible = _rear_view_on
	_hud.show_hint("Rear view: %s" % ("ON" if _rear_view_on else "OFF"))


# --- Per-frame --------------------------------------------------------------

func _process(delta: float) -> void:
	# If the ship being piloted died, hand control back to the player's own ship.
	if controlled_ai != null and (not is_instance_valid(controlled_ai) or not controlled_ai._alive):
		leave_control()
	# Feed the lock-on target to whichever systems are firing so guided shots home.
	if active_systems() != null:
		active_systems().target_ref = locked_target
	# Keep the time-scale (satellite X2/X4/X10) applied — Juice hitstop resets it.
	Engine.time_scale = _time_scale
	# Update rear camera: position behind the ship, looking backward.
	if _rear_view_on and _rear_camera != null and model != null:
		var ship_xform := model.global_transform
		# Camera sits behind the ship, looking in the opposite direction.
		var back := -ship_xform.basis.z * -8.0  # Behind the ship
		var up := ship_xform.basis.y * 2.0
		_rear_camera.global_position = ship_xform.origin + back + up
		# Look in the direction the ship came from (behind).
		var look_target := ship_xform.origin + ship_xform.basis.z * 100.0
		_rear_camera.look_at(look_target, ship_xform.basis.y)
	# Update moon gravity body and landmark position so collision/gravity/markers
	# match the visual orbit.
	if gravity != null and space != null and space._moon_node != null:
		var moon_pos := space._moon_node.global_position
		if gravity._bodies.size() > 3:
			gravity._bodies[3].position = moon_pos
		# Update the moon landmark position (index 1 after Tarn IV).
		if space.landmarks.size() > 1:
			space.landmarks[1]["position"] = moon_pos
	var camera := camera_node()
	if camera != null and _view_light != null:
		_view_light.global_transform = Transform3D(camera.global_transform.basis, Vector3.ZERO)
	if _motes != null and _mote_field_on:
		_motes.global_position = (model.global_position / MOTE_SPACING).round() * MOTE_SPACING
		_update_mote_streaks(delta)
	# Motion trails: the player's own, and one per live AI ship, so the direction
	# of travel is readable at a glance. Toggled separately from the Trails menu.
	_update_player_trail()
	_update_ship_trails()
	# Drift, spin and fade broken-off debris.
	var still_alive: Array[Dictionary] = []
	for d in _debris_list:
		var node: MeshInstance3D = d["node"]
		if not is_instance_valid(node):
			continue
		var vel: Vector3 = d["velocity"]
		# Very gentle drag so debris slows down rather than flying forever.
		vel *= (1.0 - 0.3 * delta)
		d["velocity"] = vel
		node.global_position += vel * delta
		node.global_transform.basis = node.global_transform.basis.rotated(
			d["spin_axis"], d["spin_speed"] * delta
		)
		var life: float = d["life"] - delta
		d["life"] = life
		var fade := clampf(life / 3.0, 0.0, 1.0)
		var mat: StandardMaterial3D = d["material"]
		if mat != null:
			mat.albedo_color.a = fade * 0.85
		if life <= 0.0:
			node.queue_free()
		else:
			still_alive.append(d)
	_debris_list = still_alive


func _physics_process(delta: float) -> void:
	_read_keyboard(delta)
	# Once a second, put knocked-loose rocks back to scenery when they drift away.
	_rock_demote_timer -= delta
	if _rock_demote_timer <= 0.0:
		_rock_demote_timer = 1.0
		_sweep_live_rocks()
	# A dead lock is no lock — drop it so facing assist stops fighting a freed
	# reference and the HUD stops drawing a bracket around nothing.
	if locked_target != null and not is_instance_valid(locked_target):
		locked_target = null
	# Nose-on assist: when armed (the facing toggle, or dogfight control mode)
	# and a target is locked, steer yaw/pitch so the ship always faces it.
	if locked_target != null and (facing_target or _dogfight_armed()):
		_apply_target_facing()
	# Touch-to-accelerate: holding the screen drives throttle to full.
	var flight := active_model()
	var systems_now := active_systems()
	if _touch_accel and not _button_boost:
		flight.command.throttle = clampf(
			flight.command.throttle + 1.2 * delta,
			ThrottleLever.MIN_VALUE, 1.0
		)
		systems_now.set_throttle(clampf(absf(flight.command.throttle), 0.0, 1.0))
	systems_now.set_boost(flight.command.boost)


## True when the active ship's control mode should implicitly keep the nose on a
## locked target: dogfight (built for knife-fight range) and arcade (the mode a
## player goes to to actually hit things). Realistic and Sim stay manual.
func _dogfight_armed() -> bool:
	var flight := active_model()
	if flight == null:
		return false
	return flight.control_mode == FlightModel.ControlMode.DOGFIGHT \
		or flight.control_mode == FlightModel.ControlMode.ARCADE


## Steer the active ship's yaw/pitch to keep it facing [member locked_target].
## Roll and throttle stay with the player; the ship never stops translating, it
## just points where the fight is. Uses the same local-space atan2 solve as
## [AiBehaviour] so player-facing and AI-facing behave identically.
func _apply_target_facing() -> void:
	var flight := active_model()
	var ship := active_ship_node()
	if flight == null or ship == null or locked_target == null \
		or not is_instance_valid(locked_target):
		return
	var to_target := locked_target.global_position - ship.global_position
	if to_target.length_squared() < 0.001:
		return
	var local := ship.global_transform.basis.inverse() * to_target.normalized()
	flight.command.yaw = clampf(-atan2(local.x, -local.z), -1.0, 1.0)
	var flat := sqrt(local.x * local.x + local.z * local.z)
	flight.command.pitch = clampf(atan2(local.y, flat), -1.0, 1.0)


## Keyboard flying, feeding the same [FlightModel.Command] the touch widgets do.
## Read every frame rather than event-driven, because holding a key is an
## analogue input: the longer it is down, the further the throttle moves.
##
## All axes are written every frame — including when the key is released —
## so the command snaps to zero on release. The old code only wrote when
## non-zero, which left yaw/pitch/roll stuck at their last value.
func _read_keyboard(delta: float) -> void:
	var flight := active_model()
	var stick := Vector2(
		Input.get_action_strength("flight_yaw_right") - Input.get_action_strength("flight_yaw_left"),
		Input.get_action_strength("flight_pitch_down") - Input.get_action_strength("flight_pitch_up")
	)
	set_stick(Vector2(-stick.x, -stick.y))

	flight.command.roll = (
		Input.get_action_strength("flight_roll_right")
		- Input.get_action_strength("flight_roll_left")
	)

	var throttle_up := Input.get_action_strength("flight_thrust")
	var throttle_down := Input.get_action_strength("flight_reverse")
	if not is_zero_approx(throttle_up) or not is_zero_approx(throttle_down):
		# W increases throttle, S decreases it. Both can be held — net effect.
		var delta_throttle := (throttle_up - throttle_down) * THROTTLE_KEY_RATE * delta
		var wanted := clampf(
			flight.command.throttle + delta_throttle,
			ThrottleLever.MIN_VALUE, 1.0
		)
		flight.command.throttle = wanted
		_hud.sync_throttle(wanted)
	else:
		# Neither key held — throttle holds position (lever behaviour).
		pass

	flight.command.boost = Input.is_action_pressed("flight_boost") or _button_boost
	# Two sources for one piece of state, so it is recomputed from both every
	# frame rather than each of them writing into it and clearing the other.
	active_systems().set_firing(Input.is_action_pressed("flight_fire") or _button_firing)


func _on_systems_state(energy: float, heat: float, _notes: String) -> void:
	_hud.set_power(energy, heat)


# --- The interface the HUD calls -------------------------------------------

func set_throttle(value: float) -> void:
	active_model().command.throttle = clampf(value, ThrottleLever.MIN_VALUE, 1.0)


## Screen axes to flight axes. Pushing the stick forward pitches the nose down
## and right yaws right, which is the aircraft convention and the one every
## player arrives with.
func set_stick(value: Vector2) -> void:
	active_model().command.yaw = -value.x
	active_model().command.pitch = -value.y


func set_firing(value: bool) -> void:
	_button_firing = value


func set_boosting(value: bool) -> void:
	_button_boost = value


## Whether holding bare screen should drive the throttle. Only the two views
## where looking is flying — cockpit and chase. In every detached view (external,
## far, planet, free, rear) a bare-screen drag is a camera gesture: the player is
## framing a shot, not asking for full power, and a ship that silently accelerates
## while they do that is a ship flying itself.
func _touch_accel_allowed() -> bool:
	if camera_rig == null:
		return false
	return camera_rig.mode == FlightCamera.Mode.COCKPIT \
		or camera_rig.mode == FlightCamera.Mode.CHASE


func toggle_assist() -> void:
	model.toggle_assist()


func assist_enabled() -> bool:
	return model.assist


func _assist_hint() -> String:
	match model.assist_mode:
		0: return "Flight mode: manual — momentum is yours to cancel"
		2: return "Flight assist on — the ship follows its nose"
		_: return "Flight mode: damping — speed holds, drift settles"


func camera_mode() -> int:
	return camera_rig.mode


func camera_mode_label() -> String:
	return camera_rig.mode_label()


func camera_node() -> Camera3D:
	return camera_rig.camera


func set_view(mode: int) -> void:
	camera_rig.set_mode(mode)
	_hint_free_view()


func cycle_view() -> void:
	camera_rig.cycle_mode()
	_hint_free_view()


## One-shot hint on entering the FREE view, so the controls for a new mode are
## discoverable without digging through help.
func _hint_free_view() -> void:
	if camera_rig.mode == FlightCamera.Mode.FREE:
		_hud.show_hint("Free view — drag to orbit, right-drag/2nd finger to pan, Home to re-centre")


## The planet and the station in [constant Location.SPACE]; nothing to navigate
## to in the empty test volume.
func landmarks() -> Array[Dictionary]:
	if space != null:
		return space.landmarks
	var none: Array[Dictionary] = []
	return none


func target_line() -> String:
	var speed := model.velocity.length()
	var mode_label := "assist"
	if model.assist_mode == 1:
		mode_label = "damping"
	elif model.assist_mode == 0:
		mode_label = "manual"
	return "%s · %s · %d m/s over ground" % [
		design.design_name,
		mode_label,
		roundi(speed)
	]


## Put the ship back where it started, stationary and level. The equivalent of
## picking a test aircraft up and setting it down again.
func respawn() -> void:
	model.halt()
	model.global_transform = _spawn
	model.command.throttle = 0.0
	damage.reset()
	# Re-derive stats from the design so damage penalties are undone.
	if view != null:
		model.configure(view.resolution.stats, systems, damage)
	# Clean up any debris nodes left over from previous impacts.
	for d in _debris_list:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	_debris_list.clear()
	_hud.sync_throttle(0.0)
	_hud.show_hint("Back at the start point")


func return_to_hangar() -> void:
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("ship_builder"))


## Restart the flight test scene completely — reload everything from scratch.
## Different from respawn, which only resets the ship position.
func restart_scene() -> void:
	get_tree().reload_current_scene()


## Render settings, persisted across a scene reload. Driven by the HUD's Settings
## panel sliders.
static var _far_clip := 30000.0
static var _far_view_max := 400.0

func far_clip() -> float:
	return _far_clip


func far_view_max() -> float:
	return _far_view_max


## High-res rendering now lives in [Session] (see [member Session.high_res]); this
## accessor and the planet scale/spacing accessors below survive for the HUD,
## which still talks to this root rather than to Session directly.
func high_res_on() -> bool:
	return Session.high_res


func planet_scale() -> float:
	return Session.planet_scale


func planet_spacing() -> float:
	return Session.planet_spacing


## Apply a new planet size scale. Callers are expected to restart the scene after.
func set_planet_scale(value: float) -> void:
	Session.planet_scale = clampf(value, 0.5, 10.0)


## Apply a new planet spacing scale. Callers are expected to restart after.
func set_planet_spacing(value: float) -> void:
	Session.planet_spacing = clampf(value, 0.5, 5.0)


# --- Take control + weapons lock -------------------------------------------------

## The AI ship the player is currently piloting, or null.
var controlled_ai: AiShip = null
## The ship the player has locked on to (T key); guided shots home to it.
var locked_target: Node3D = null
## When true, a locked ship is kept nose-on to the target automatically: the
## flight computer steers yaw/pitch onto it every frame (roll and throttle stay
## with the player). Turned on by the Combat menu, and implicitly by dogfight
## control mode. See [method _apply_target_facing].
var facing_target := false

## Which ship the player actually flies right now: the controlled AI ship if
## piloting one, otherwise the player's own ship. Input, HUD and camera all read
## through this so "take control" is one reference swap.
func active_model() -> FlightModel:
	return controlled_ai.model if controlled_ai != null else model


func active_systems() -> SystemsSim:
	return controlled_ai.systems if controlled_ai != null else systems


func active_ship_node() -> Node3D:
	return controlled_ai if controlled_ai != null else model


## Take control of an AI ship: its behaviour pauses, the player's inputs and
## camera move to it, and the HUD reads its state.
func take_control(ship: AiShip) -> void:
	if ship == null or not is_instance_valid(ship) or not ship._alive:
		return
	leave_control()
	controlled_ai = ship
	ship._ai_paused = true
	if camera_rig != null:
		camera_rig.adopt(ship, ship.model, ship._view)
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if _hud != null:
		_hud.show_hint("Piloting %s — L to leave control" % ship.preset_name)


## Give control back to the player's own ship.
func leave_control() -> void:
	if controlled_ai != null and is_instance_valid(controlled_ai):
		controlled_ai._ai_paused = false
	controlled_ai = null
	if camera_rig != null and model != null:
		camera_rig.adopt(model, model, view)
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if _hud != null:
		_hud.show_hint("Back in your own ship")


## Toggle a weapons lock on the nearest live AI ship (or release the current one).
## Guided shots home to the locked ship; the HUD draws a bracket around it.
func toggle_lock() -> void:
	if locked_target != null and is_instance_valid(locked_target):
		locked_target = null
		_hud.show_hint("Lock released")
		return
	var best: Node3D = null
	var best_d := INF
	if _ai_spawner != null:
		for ship in _ai_spawner._ships:
			if not is_instance_valid(ship) or not ship._alive:
				continue
			var d := active_ship_node().global_position.distance_squared_to(ship.global_position)
			if d < best_d:
				best_d = d
				best = ship
	if best != null:
		locked_target = best
		_hud.show_hint("Locked: %s" % best.preset_name)
	else:
		_hud.show_hint("No target to lock")


# --- Satellites + time-scale --------------------------------------------------

## The global time scale (×1/×2/×4/×10), re-applied every frame so Juice hitstop
## cannot wipe it. For watching satellites orbit.
var _time_scale := 1.0
## Spawned ballistic orbit probes, tracked so they can be deleted together.
var _satellites: Array[AiShip] = []


func time_scale() -> float:
	return _time_scale


func set_time_scale(scale: float) -> void:
	_time_scale = scale
	Engine.time_scale = scale
	if _hud != null:
		_hud.show_hint("Time scale: ×%.0f" % scale)


## Launch a ballistic probe into a circular orbit just outside the player's own
## orbit, so gravity can be watched at ×2/×4/×10.
func spawn_satellite() -> void:
	if _ai_spawner == null or gravity == null:
		_hud.show_hint("No gravity to orbit — enable it (G) in space")
		return
	var dist := 3000.0
	var body := gravity.find_dominant_body(active_ship_node().global_position)
	if body != null:
		dist = active_ship_node().global_position.distance_to(body.position) + 400.0
	var sat := _ai_spawner.spawn_ballistic_satellite(gravity, dist)
	if sat != null:
		_satellites.append(sat)
		_hud.show_hint("Satellite in orbit at %.0f m — O cycles speed, M clears" % dist)
	else:
		_hud.show_hint("Could not launch a satellite")


func delete_satellites() -> void:
	for sat in _satellites:
		if is_instance_valid(sat):
			sat.teardown()
	_satellites.clear()
	if _hud != null:
		_hud.show_hint("Satellites cleared")


## The definitive orbit test: put the ship into the perfect circular orbit at its
## current position and release the throttle. If orbit works, the ship stays put;
## if it spirals in or out, the flight model is fighting the gravity.
func enter_orbit() -> void:
	if gravity == null or model == null:
		return
	var body := gravity.find_dominant_body(model.global_position)
	if body == null:
		_hud.show_hint("No gravity body to orbit")
		return
	var vel := gravity.circular_orbit_velocity(body, model.global_position)
	if vel.length_squared() < 0.001:
		return
	model.velocity = vel
	model.command.throttle = 0.0
	model.command.boost = false
	_hud.show_hint("Entering orbit — circular velocity set, throttle released")


## Gentler variant: keep the current heading, just set the speed to the local
## circular-orbit speed, so the ship settles into orbit without a vector snap.
func match_circular_speed() -> void:
	if gravity == null or model == null:
		return
	var body := gravity.find_dominant_body(model.global_position)
	if body == null:
		return
	var dist := model.global_position.distance_to(body.position)
	var v_orbit := gravity.orbit_velocity(body, dist)
	var dir := model.velocity.normalized()
	if dir.length_squared() < 0.001:
		dir = -model.global_transform.basis.z
	model.velocity = dir * v_orbit
	_hud.show_hint("Speed matched to circular (%.0f m/s)" % v_orbit)


## Far clip (m): how far the main and rear cameras render. Raising it keeps
## planets on screen long after ships have despawned (those are culled at 3.5 km).
func set_far_clip(value: float) -> void:
	_far_clip = maxf(value, 1000.0)
	if camera_rig != null:
		camera_rig.set_far_clip(_far_clip)
	if _rear_camera != null:
		_rear_camera.far = _far_clip


## How far the FAR view can pull out, in metres (was [constant FlightCamera.FAR_MAX_DIST]).
func set_far_view_max(value: float) -> void:
	_far_view_max = maxf(value, 100.0)
	if camera_rig != null:
		camera_rig.set_far_view_max(_far_view_max)

## Toggle high-detail rendering. Does NOT resize the window (that just zoomed
## the stretch-scaled canvas); it raises the 3D render scale and rebuilds the
## procedural geometry — planets, nebula, rocks, sky — at higher segment counts
## so everything is genuinely less low-poly. Restarts the scene to rebuild.
func toggle_high_res() -> void:
	Session.high_res = not Session.high_res
	_hud.show_hint("High res: %s — rebuilding scene…" % ("ON" if Session.high_res else "OFF"))
	restart_scene()


func toggle_high_contrast() -> void:
	BuilderTheme.high_contrast = not BuilderTheme.high_contrast
	ShipMaterials.high_contrast = BuilderTheme.high_contrast
	get_window().theme = BuilderTheme.build()
	_assemble()


## Called by the damage system when a part breaks off. The damage system
## already moved the actual part node to world space as debris_node. We
## track that node, add a transparency fade, and spawn particle bursts.
func _on_part_broken(broken: DamageSystem.BrokenPart, _effects: Array) -> void:
	var node := broken.debris_node
	if node == null or not is_instance_valid(node):
		# Fallback: create a simple box if the damage system did not provide a node.
		node = MeshInstance3D.new()
		node.name = "Debris_%s" % broken.path
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8, 0.6, 1.2)
		node.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.55, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.global_position = broken.world_pos
		add_child(node)

	# Enable transparency fade on all mesh children of the debris node.
	var fade_mat: StandardMaterial3D = null
	for child in node.get_children():
		if child is MeshInstance3D:
			var m: StandardMaterial3D = child.get_surface_override_material(0) as StandardMaterial3D
			if m != null:
				m = m.duplicate() as StandardMaterial3D
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				child.set_surface_override_material(0, m)
				fade_mat = m
		elif child.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = child.material_override as StandardMaterial3D
			m = m.duplicate() as StandardMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = m
			fade_mat = m

	# Also handle the node itself if it is a MeshInstance3D.
	if node is MeshInstance3D:
		var m: StandardMaterial3D = node.material_override as StandardMaterial3D
		if m != null:
			m = m.duplicate() as StandardMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			node.material_override = m
			fade_mat = m

	_debris_list.append({
		"node": node,
		"velocity": broken.drift_dir * broken.drift_speed + model.velocity * 0.15,
		"spin_axis": Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(),
		"spin_speed": randf_range(2.0, 6.0),
		"life": 8.0,
		"material": fade_mat,
	})

	# Particle bursts: sparks, debris chunks, and embers at the break point.
	var break_xform := Transform3D(Basis(), broken.world_pos)
	Juice.burst(BurstPresets.Preset.SPARKS, break_xform, 1.2, Color("ffcc44"))
	Juice.burst(BurstPresets.Preset.DEBRIS, break_xform, 0.8)
	Juice.burst(BurstPresets.Preset.EMBERS, break_xform, 0.6)
	Juice.light_pop(broken.world_pos, Color("ff8844"), 3.0, 0.15)
	Juice.shake(0.15)
	Juice.kick(broken.drift_dir, 0.3)

	_hud.show_hint("⚠ %s lost! %s" % [broken.part_name, broken.path])


func toggle_help() -> void:
	_coach.start(false)


func toggle_drift_field() -> void:
	_mote_field_on = not _mote_field_on
	_motes.visible = _mote_field_on
	_hud.show_hint(
		"Drift field on" if _mote_field_on else "Drift field off — empty space, no reference"
	)


## Called by FlightModel when the ship enters or leaves a stable orbit.
func _on_orbit_changed(body_name: String, in_orbit: bool) -> void:
	if in_orbit:
		_hud.show_hint("ORBIT — stable around %s" % body_name)
	else:
		_hud.show_hint("Orbit lost around %s" % body_name)


## Toggle the gravity visualizer. Called by both H key and the menu.
func toggle_gravity_viz() -> void:
	if gravity == null or model == null:
		_hud.show_hint("Gravity visualizer unavailable — enable gravity first (G)")
		return
	if _gravity_viz == null:
		_gravity_viz = GravityVisualizer.new()
		_gravity_viz.name = "GravityViz"
		_gravity_viz.setup(gravity, model)
	if not _gravity_viz.is_showing():
		add_child(_gravity_viz)
		_gravity_viz.toggle()
	else:
		_gravity_viz.toggle()
		if _gravity_viz.get_parent() != null:
			remove_child(_gravity_viz)
	# The [ORBIT] console stream rides on the visualizer: it exists to watch orbits
	# and is too chatty (a line per ship per second) to run all the time.
	Session.debug_orbit_log = _gravity_viz.is_showing()
	var viz_state := "ON" if _gravity_viz.is_showing() else "OFF"
	_hud.show_hint("Gravity viz: %s — arrows = pull at your ship, cyan rings = orbit, green = bound / orange-red = escaping" % viz_state)


## Slam the force law to cartoon extremes for wild slingshots and flung rocks,
## or restore the live profile's own law (debug key Y). Only affects gravity, so
## KEY_K (feel profile) and the collision dials are untouched.
func toggle_gravity_chaos() -> void:
	if gravity == null:
		_hud.show_hint("Gravity chaos needs gravity (G)")
		return
	_gravity_chaos = not _gravity_chaos
	if _gravity_chaos:
		gravity.apply_law(GRAVITY_CHAOS_G, GRAVITY_CHAOS_FALLOFF)
		gravity.range_multiplier = 6.0
		_hud.show_hint("Gravity chaos ON — slingshots get wild (Y to restore)")
	else:
		_apply_gravity_profile()
		gravity.range_multiplier = 1.0
		_hud.show_hint("Gravity chaos OFF")


## True when gravity bodies attract things in ("pull"). Gravity menu toggle:
## off means orbit-only — bodies keep their own orbits and nothing falls in.
func gravity_pull_on() -> bool:
	return gravity != null and gravity.pull_enabled


func toggle_gravity_pull() -> void:
	if gravity == null:
		_hud.show_hint("Gravity pull needs gravity (G)")
		return
	gravity.pull_enabled = not gravity.pull_enabled
	_hud.show_hint("Gravity pull: %s — bodies %s drag things in" % [
		"ON" if gravity.pull_enabled else "OFF",
		"do" if gravity.pull_enabled else "do not",
	])


## Spawn a mother ship near the player (debug/testing). True if one was dropped.
## Used by the Combat menu's "Spawn mother ship" row and key 6.
func spawn_mother_ship() -> bool:
	if _ai_spawner == null or space == null:
		return false
	return _ai_spawner.spawn_mother() != null


## Toggle the planet-pointer debug. Called by both J key and the menu.
func toggle_planet_pointer() -> void:
	if gravity == null or model == null:
		_hud.show_hint("Planet pointer unavailable — enable gravity first (G)")
		return
	if _planet_pointer == null:
		_planet_pointer = PlanetPointer.new()
		_planet_pointer.name = "PlanetPointer"
		_planet_pointer.setup(gravity, model)
	if not _planet_pointer.is_showing():
		add_child(_planet_pointer)
		_planet_pointer.toggle()
	else:
		_planet_pointer.toggle()
		if _planet_pointer.get_parent() != null:
			remove_child(_planet_pointer)
	_hud.show_hint("Planet pointer: %s" % ("ON" if _planet_pointer.is_showing() else "OFF"))


func planet_pointer_on() -> bool:
	return _planet_pointer != null and _planet_pointer.is_showing()


func drift_field_on() -> bool:
	return _mote_field_on


# --- Trails ------------------------------------------------------------------

## Trail *choices* live in [Session] (see [member Session.trail_player] /
## [member Session.trail_ships]) so they survive a scene restart; the per-node
## state below — the trail nodes themselves — still belongs to this scene.
## The player's own trail node, lazily created.
var _player_trail: Trail3D = null
## One trail per live AI ship: AiShip -> Trail3D. Kept in sync with the spawner's
## roster each frame (created on spawn, freed on despawn).
var _ship_trails: Dictionary = {}


func trail_player_on() -> bool:
	return Session.trail_player


func set_trail_player(on: bool) -> void:
	Session.trail_player = on
	if on:
		if _player_trail == null:
			_player_trail = Trail3D.new()
			_player_trail.name = "PlayerTrail"
			add_child(_player_trail)
			_player_trail.set_color(BuilderTheme.accent())
		_player_trail.set_enabled(true)
	elif _player_trail != null:
		_player_trail.set_enabled(false)
	_hud.show_hint("Player trail: %s" % ("on" if on else "off"))


func trail_ships_on() -> bool:
	return Session.trail_ships


func set_trail_ships(on: bool) -> void:
	Session.trail_ships = on
	if not on:
		for trail in _ship_trails.values():
			if is_instance_valid(trail):
				(trail as Trail3D).set_enabled(false)
	_hud.show_hint("All-ships trail: %s" % ("on" if on else "off"))


## Keep the AI trails matched to the live roster: create one for each alive ship
## (or enable the existing), disable and free trails for ships that despawned.
func _update_ship_trails() -> void:
	var keep: Dictionary = {}
	if _ai_spawner != null and Session.trail_ships:
		for ship in _ai_spawner._ships:
			if not is_instance_valid(ship) or not ship._alive:
				continue
			var trail := _ship_trails.get(ship) as Trail3D
			if trail == null:
				trail = Trail3D.new()
				trail.name = "ShipTrail_%s" % ship.name
				add_child(trail)
				trail.set_color(BuilderTheme.text_dim())
				_ship_trails[ship] = trail
			trail.set_enabled(true)
			trail.add_point(ship.global_position)
			keep[ship] = true
	# Free trails for ships that are gone.
	for key in _ship_trails.keys():
		if not keep.has(key):
			var trail := _ship_trails[key] as Trail3D
			if trail != null:
				trail.set_enabled(false)
				trail.queue_free()
			_ship_trails.erase(key)


func _update_player_trail() -> void:
	if Session.trail_player and _player_trail != null:
		# The player's own trail follows the player's ship only while it is the
		# ship being flown; while piloting an AI ship the player's hull is parked.
		if controlled_ai == null and model != null:
			_player_trail.add_point(model.global_position)


func ai_live_count() -> int:
	if _ai_spawner != null:
		return _ai_spawner.live_count()
	return 0


## Dump the full scene tree to the Godot console so we can identify mystery
## nodes. Shift+D triggers this — every MeshInstance3D, Camera3D, SubViewport
## and Node3D in the tree is listed with its type, name, and parent path.
func _dump_scene_tree() -> void:
	print("=== SCENE TREE DUMP (Shift+D) ===")
	_dump_node(self, 0)
	print("=== END DUMP ===")


func _dump_node(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh_name := "null"
		if mi.mesh != null:
			mesh_name = mi.mesh.get_class()
		var mat_info := "no_mat"
		if mi.material_override is ShaderMaterial:
			var sh = (mi.material_override as ShaderMaterial).shader
			mat_info = "shader:" + (sh.resource_path.get_file() if sh != null else "null")
		elif mi.material_override is StandardMaterial3D:
			var sm := mi.material_override as StandardMaterial3D
			mat_info = "stdmat_blend_%d" % sm.blend_mode
		extra = " [Mesh %s %s vis=%s]" % [mesh_name, mat_info, node.visible]
	elif node is Camera3D:
		var cam := node as Camera3D
		extra = " [Camera3D current=%s near=%.1f far=%.0f]" % [cam.current, cam.near, cam.far]
	elif node is SubViewport:
		var sv := node as SubViewport
		extra = " [SubViewport %dx%d vis=%s update=%d]" % [sv.size.x, sv.size.y, sv.visible, sv.render_target_update_mode]
	elif node is WorldEnvironment:
		extra = " [WorldEnvironment]"
	elif node is DirectionalLight3D:
		extra = " [DirectionalLight3D]"
	elif node is MultiMeshInstance3D:
		extra = " [MultiMesh vis=%s]" % node.visible
	elif node is Node3D:
		extra = " [Node3D vis=%s]" % node.visible
	var parent_name = node.get_parent().name if node.get_parent() != null else "root"
	print("%s%s|%s (parent=%s)%s" % [indent, node.get_class(), node.name, parent_name, extra])
	for child in node.get_children():
		_dump_node(child, depth + 1)


## Debug toggles — called by FlightHud checkboxes to hide/show rendering layers.
func set_debug_visible(layer: String, visible: bool) -> void:
	match layer:
		"plumes":
			if systems != null:
				for child in systems.get_children():
					if child.name == "Plumes":
						child.visible = visible
		"halos":
			if systems != null:
				for child in systems.get_children():
					if child.name == "Plumes":
						for sub in child.get_children():
							if sub.name == "Halo":
								sub.visible = visible
		"tracers":
			if systems != null:
				for child in systems.get_children():
					if child.name == "Shots":
						child.visible = visible
		"stars":
			if space != null:
				var stars := space.get_node_or_null("Sky/Stars")
				if stars != null:
					stars.visible = visible
		"nebula":
			if space != null:
				var neb := space.get_node_or_null("Sky/Nebula")
				if neb != null:
					neb.visible = visible
		"planet":
			if space != null:
				# Hide ALL planet-related nodes recursively.
				var planet_node := space.get_node_or_null("Planet")
				if planet_node != null:
					planet_node.visible = visible
				var p2 := space.get_node_or_null("Planet2")
				if p2 != null:
					p2.visible = visible
				var p3 := space.get_node_or_null("Planet3")
				if p3 != null:
					p3.visible = visible
		"everything":
			# Nuclear: hide ALL 3D children of FlightRoot, not just SpaceScene.
			# Keep the WorldEnvironment visible and swap its background to
			# bright green so any remaining artifacts are clearly visible.
			if space != null:
				# Hide all SpaceScene children EXCEPT the Environment node.
				# WorldEnvironment extends Node (not Node3D) — it has no .visible.
				for child in space.get_children():
					if child.name == "Environment":
						continue  # Skip — always keep environment
					if child is Node3D:
						child.visible = visible
				# Swap background color for debugging.
				var env_holder := space.get_node_or_null("Environment")
				if env_holder != null and env_holder is WorldEnvironment:
					var env: Environment = env_holder.environment
					if env != null:
						if not visible:
							if not env.has_meta("_orig_bg"):
								env.set_meta("_orig_bg", env.background_color)
								env.set_meta("_orig_amb", env.ambient_light_color)
								env.set_meta("_orig_amb_e", env.ambient_light_energy)
							env.background_color = Color(0.0, 0.8, 0.15)  # Bright green
							env.ambient_light_color = Color(0.0, 0.8, 0.15)
							env.ambient_light_energy = 1.0
						elif env.has_meta("_orig_bg"):
							env.background_color = env.get_meta("_orig_bg")
							env.remove_meta("_orig_bg")
							if env.has_meta("_orig_amb"):
								env.ambient_light_color = env.get_meta("_orig_amb")
								env.remove_meta("_orig_amb")
							if env.has_meta("_orig_amb_e"):
								env.ambient_light_energy = env.get_meta("_orig_amb_e")
								env.remove_meta("_orig_amb_e")
			# Also hide other direct children of FlightRoot, except the camera rig.
			for child in get_children():
				if child == space or child == camera_rig:
					continue
				if child is Node3D:
					child.visible = visible
				elif child is SubViewport:
					child.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED

		"atmo":
			if space != null:
				# Find all Atmosphere nodes recursively in all planet pivots.
				for child in space.get_children():
					if child.name.begins_with("Planet"):
						# Search grandchildren (the Planet nodes inside pivots).
						for sub in child.get_children():
							if sub is Planet:
								var atmo := sub.get_node_or_null("Atmosphere")
								if atmo != null:
									atmo.visible = visible
		"station":
			if space != null:
				var st := space.get_node_or_null("Station")
				if st != null:
					st.visible = visible
		"skydome":
			if space != null:
				var sky := space.get_node_or_null("Sky")
				if sky != null:
					sky.visible = visible
		"sun":
			if space != null:
				var sun := space.get_node_or_null("Sky/Star")
				if sun != null:
					sun.visible = visible
		"shipgeo":
			if _ship_holder != null:
				_ship_holder.visible = visible
		"asteroids":
			if space != null:
				for i in 3:
					var belt := space.get_node_or_null("Belt%d" % i)
					if belt != null:
						belt.visible = visible
				var nf := space.get_node_or_null("NearField")
				if nf != null:
					nf.visible = visible
		"drift":
			if _motes != null:
				_motes.visible = visible
		"reticle":
			# Handled in _draw_instruments via a flag.
			pass
		"markers":
			# Handled in _draw_instruments via a flag.
			pass


func location_is_space() -> bool:
	return location == Location.SPACE


## Tears down whichever environment is current and rebuilds the other. A rare,
## deliberate action from the ☰ menu, not something worth keeping both halves
## of live for.
func toggle_location() -> void:
	# Cycle: Space → Test volume → Space.
	match location:
		Location.SPACE: location = Location.TEST_VOLUME
		Location.TEST_VOLUME: location = Location.SPACE
	Session.flight_location = location
	# Release any ship the player was piloting before the spawner is torn down.
	if controlled_ai != null:
		leave_control()
	if _ai_spawner != null:
		_ai_spawner.teardown()
		_ai_spawner.queue_free()
		_ai_spawner = null
	# Drop the physics layer before the space scene goes: bodies must not keep
	# pointing at collider nodes that are about to be freed.
	_teardown_phys_world()
	if space != null:
		space.queue_free()
		space = null
	for node in [_env_holder, _key_light, _fill_light, _view_light]:
		if node != null:
			node.queue_free()
	_env_holder = null
	_key_light = null
	_fill_light = null
	_view_light = null
	_build_location()
	_build_gravity()
	camera_rig.space = space
	if gravity != null and model != null:
		model.gravity = gravity
	# Returning to space rebuilds the physics layer over the fresh scene.
	if location == Location.SPACE:
		_build_phys_world()
	_mote_field_on = true
	_motes.visible = _mote_field_on
	match location:
		Location.SPACE:
			_hud.show_hint("Space")
		Location.TEST_VOLUME:
			_hud.show_hint("Test volume — an empty volume with a drift field")


## Jump to the standalone AI test arena module scene.
func go_arena() -> void:
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("arena"))


# --- Input ------------------------------------------------------------------

## Anything the HUD widgets did not claim is a look drag. The stick, throttle and
## buttons all stop their own events, so by the time input reaches here the
## player is touching bare screen and means to look around.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				camera_rig.zoom(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			# In the FREE view the right button pans the camera (a second finger
			# does the same on touch); everywhere else both buttons are look.
			var free_pan := camera_rig.mode == FlightCamera.Mode.FREE \
				and mb.button_index == MOUSE_BUTTON_RIGHT
			if free_pan:
				_panning = mb.pressed
			else:
				_looking = mb.pressed
				camera_rig.set_looking(_looking)
				# Hold the look button to accelerate.
				if mb.pressed:
					_touch_accel = _touch_accel_allowed()
				else:
					_touch_accel = false
					# Release throttle when letting go.
					model.command.throttle = lerpf(model.command.throttle, 0.0, 0.3)
	elif event is InputEventMouseMotion:
		if _panning:
			camera_rig.pan_from_screen((event as InputEventMouseMotion).relative)
		elif _looking:
			camera_rig.look((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _look_pointer < 0:
				_look_pointer = st.index
				camera_rig.set_looking(true)
				_touch_accel = _touch_accel_allowed()
			elif _pan_pointer < 0 and camera_rig.mode == FlightCamera.Mode.FREE:
				# A second finger in the FREE view pans the camera.
				_pan_pointer = st.index
				_panning = true
		else:
			if st.index == _look_pointer:
				_look_pointer = -1
				camera_rig.set_looking(false)
				_touch_accel = false
				model.command.throttle = lerpf(model.command.throttle, 0.0, 0.3)
			elif st.index == _pan_pointer:
				_pan_pointer = -1
				_panning = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _pan_pointer:
			camera_rig.pan_from_screen(sd.relative)
		elif sd.index == _look_pointer:
			camera_rig.look(sd.relative)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var vp := get_viewport()
	if key.is_action("flight_assist"):
		toggle_assist()
		if vp != null:
			vp.set_input_as_handled()
		return
	match key.keycode:
		KEY_V:
			cycle_view()
		KEY_HOME:
			# Re-centre the FREE view on the player's ship.
			if camera_rig.mode == FlightCamera.Mode.FREE:
				camera_rig.recentre()
				_hud.show_hint("Free view re-centred on the ship")
		KEY_L:
			if controlled_ai != null:
				leave_control()
		KEY_T:
			toggle_lock()
		KEY_N:
			spawn_satellite()
		KEY_M:
			delete_satellites()
		KEY_O:
			var steps := [1.0, 2.0, 4.0, 8.0, 10.0]
			var idx := steps.find(_time_scale)
			set_time_scale(steps[(idx + 1) % steps.size()])
		KEY_P:
			camera_rig.set_mode(FlightCamera.Mode.PLANET)
			_hud.show_hint("Planet view — %s" % camera_rig.mode_label())
		KEY_K:
			# A/B the feel: cycles every .tres in physics/data/profiles live. The
			# swap covers collision AND gravity. Only in space, where a world exists.
			var profile := cycle_phys_profile()
			if profile != "":
				_hud.show_hint("Feel profile: %s (collision + gravity)" % profile)
		KEY_R:
			respawn()
		KEY_D:
			if key.shift_pressed:
				_dump_scene_tree()
			else:
				_hud.toggle_debug_panel()
		KEY_B:
			toggle_rear_view()
		KEY_C:
			model.trigger_quick_turn()
		KEY_X:
			model.warp_active = not model.warp_active
			_hud.show_hint("Warp %s" % ("ON — 8× speed" if model.warp_active else "OFF"))
		KEY_G:
			if gravity != null:
				if key.shift_pressed:
					# Shift+G: cycle gravity range multiplier.
					var ranges := [0.5, 1.0, 2.0, 4.0, 8.0]
					var idx := ranges.find(gravity.range_multiplier)
					idx = (idx + 1) % ranges.size()
					gravity.range_multiplier = ranges[idx]
					_hud.show_hint("Gravity range: ×%.1f" % gravity.range_multiplier)
				else:
					match gravity.mode:
						GravitySystem.GravityMode.OFF:
							gravity.mode = GravitySystem.GravityMode.NORMAL
						GravitySystem.GravityMode.NORMAL:
							gravity.mode = GravitySystem.GravityMode.HIGH
						GravitySystem.GravityMode.HIGH:
							gravity.mode = GravitySystem.GravityMode.OFF
					var mode_names := ["OFF", "NORMAL", "HIGH"]
					_hud.show_hint("Gravity: %s (range ×%.1f)" % [mode_names[gravity.mode], gravity.range_multiplier])
		KEY_1, KEY_KP_1:
			model.gravity_strength = 0.5
			_hud.show_hint("Gravity strength: ×0.5 (weak)")
		KEY_2, KEY_KP_2:
			model.gravity_strength = 1.0
			_hud.show_hint("Gravity strength: ×1.0 (normal)")
		KEY_3, KEY_KP_3:
			model.gravity_strength = 2.0
			_hud.show_hint("Gravity strength: ×2.0 (strong)")
		KEY_4, KEY_KP_4:
			model.gravity_strength = 5.0
			_hud.show_hint("Gravity strength: ×5.0 (heavy)")
		KEY_5, KEY_KP_5:
			model.gravity_strength = 10.0
			_hud.show_hint("Gravity strength: ×10.0 (extreme)")
		KEY_6, KEY_KP_6:
			# Debug/testing: drop a mother ship that launches fighters.
			_hud.show_hint("Mother ship launched" if spawn_mother_ship() else "No room for a mother ship")
		KEY_Y:
			toggle_gravity_chaos()
		KEY_TAB:
			var new_str := model.cycle_gravity_strength()
			_hud.show_hint("Gravity strength: ×%.1f" % new_str)
		KEY_H:
			toggle_gravity_viz()
		KEY_J:
			toggle_planet_pointer()
		KEY_F11:
			# Cycle control mode: Arcade → Sim → Realistic → Dogfight → Arcade
			var modes := [
				FlightModel.ControlMode.ARCADE, FlightModel.ControlMode.SIM,
				FlightModel.ControlMode.REALISTIC, FlightModel.ControlMode.DOGFIGHT,
			]
			var mode_names := ["Arcade", "Sim", "Realistic", "Dogfight"]
			var idx := modes.find(model.control_mode)
			idx = (idx + 1) % modes.size()
			model.set_control_mode(modes[idx])
			_hud.show_hint("Controls: %s" % mode_names[idx])
		KEY_F5:
			restart_scene()
		KEY_QUESTION, KEY_SLASH, KEY_F1:
			toggle_help()
		KEY_ESCAPE:
			return_to_hangar()
	if vp != null:
		vp.set_input_as_handled()
