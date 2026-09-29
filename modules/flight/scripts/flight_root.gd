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
	## A system handed off from the solar_system_gen lab's "Enter flight test"
	## button (see [member Session.pending_solar_system]) — a real,
	## [GravitySystem]-driven generated system instead of [SpaceScene]'s
	## hand-authored one. Falls back to a fresh random system if nothing was
	## handed off (this scene run directly, F6, or a stale flag).
	GENERATED_SYSTEM,
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
var audio: SpaceAudio = null

var _headlight_l: SpotLight3D = null
var _headlight_r: SpotLight3D = null
var _nav_light_port: OmniLight3D = null
var _nav_light_starboard: OmniLight3D = null

var library: PartLibrary
var design: ShipDesign
var view: ShipView

var location: Location = Location.SPACE

## Non-null only in [constant Location.SPACE]. [FlightCamera] reads it directly
## (see [member FlightCamera.space]) to recentre the sky dome on itself; nothing
## else about the rig's transform is Juice's or the location's to touch.
var space: SpaceScene = null
## Non-null only in [constant Location.GENERATED_SYSTEM]. See [method
## _build_generated_system].
var generated_system: SolarSystemGenerator = null

var _hud: FlightHud
var incident_director: IncidentDirector = null
var _coach: CoachOverlay
var _ship_holder: Node3D
var _motes: MultiMeshInstance3D
var _mote_field_on := true
## Smoothed 0..1 stretch of the drift motes into motion streaks, driven by speed.
var _mote_stretch := 0.0
var _render_visible := true
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
var _rim_light: DirectionalLight3D
## All active debris nodes, tracked for drift and fade each frame.
var _debris_list: Array[Dictionary] = []

## Seconds left before another near-miss slowmo can trigger — a single
## passing shot should read as one beat, not a stutter of hitstops while it
## stays close. Starts positive (a brief grace period) rather than 0: a shot
## passing close on the very first frames after spawning is not a moment the
## player has had time to notice yet, so triggering slowmo there would just
## read as an unexplained stutter — and briefly scaling Engine.time_scale
## that early was enough to occasionally throw off other startup timing.
var _near_miss_cooldown := 1.0
const NEAR_MISS_RADIUS := 6.0
const NEAR_MISS_COOLDOWN := 1.2

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
## How far above the hull centre a reaction emote spawns from (see [method
## _emote]) -- cached at [method _assemble] from the hull's own bounds, so a
## big design pops its emote clear of the canopy instead of from inside it.
var _emote_height := 1.0
## Touch-to-accelerate: when the player holds anywhere on screen (that is not
## a widget), the ship accelerates forward. The throttle still sets the
## maximum speed; this just drives it to full while held. Only in the two
## views where looking IS flying — see [method _touch_accel_allowed].
var _touch_accel := false
## The pilot's last stick deflection (screen axes), kept apart from the command
## so assists blend from it instead of from their own output.
var _stick_input := Vector2.ZERO
## Touch HUD roll buttons (see [method set_roll]).
var _button_roll := 0.0
## Whether an assist wrote yaw/pitch last tick (see [method _physics_process]).
var _assist_steering := false
var _keyboard_steering := false

var _ai_spawner: AiSpawner = null
## Set-piece fights: duel, skirmish, waves... (see [FlightScenarios]).
var scenarios: FlightScenarios = null
## Garage upgrades of the ship the menu handed over ([member
## Session.pending_ship]): stat → multiplier. Empty in a plain test flight.
var upgrade_mults := {}
var _big_notice: BigNotice = null
## The campaign level being flown, its map button and end card; null in free
## flight. See [CampaignLevelOverlay].
var campaign_overlay: CampaignLevelOverlay = null
## The flight test's bug hunt — see [BugHunt] and the 🐞 panel.
var bug_hunt: BugHunt = null
## The player's team for AI targeting (0 = everyone's target).
var _player_team := 0
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
## Light shafts + grade over the 3D view; see [method _build_advanced_lighting].
var _advanced_lighting: AdvancedLighting = null
var _rear_camera: Camera3D = null
var _rear_texture_rect: TextureRect = null
var _rear_view_on := false

## Player hull HP and shield — tracked here so the HUD, damage system, and
## AI weapons all have a single source of truth.
var player_hp := 500.0
var player_max_hp := 500.0
var player_shield := 0.0
var player_max_shield := 0.0
## Earliest tick (ms) the next shield flash / hull-hit spark may spawn — see
## [method take_damage].
var _next_shield_fx_ms := 0
var _next_hit_fx_ms := 0
## Earliest tick (ms) the next non-lethal hull explosion may go off.
var _next_hit_boom_ms := 0
## Earliest tick (ms) the next hit freeze may start — a volley is one freeze.
var _next_hit_freeze_ms := 0
## Real tick (ms) of the last damage the player took, for the shield-regen delay.
var _last_hit_ms := 0
## Earliest real tick (ms) the next kill cam may start.
var _next_kill_cam_ms := 0
var _player_dead := false
var _game_over_timer := 0.0  # slow-mo duration before showing modal
## Real tick (ms) the post-respawn grace ends ([member
## JuiceSettings.respawn_grace]); 0 = none running.
var _grace_until_ms := 0
## The camera view the player had when they died — the death camera orbits in
## FREE, and a respawn puts this back instead of leaving them in it.
var _view_before_death := -1

## Debris from AI ship part scatter and player collision. Entries have:
## { node, velocity, spin_axis, spin_speed, life, material }
## The "material" key may be null for non-fading node types (e.g. no special mat).


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
	# This scene is reached two ways: through the ship builder's "Enter flight
	# test" (which goes through the launcher, so [method Session.start] — and
	# therefore this load — already ran once at boot), and run directly (F6,
	# see the class doc's [enum Location] comment) — which skips the launcher
	# entirely. Without this, every dial below that reads a `Session.*` value
	# (camera FOV/chase, assist/damping multipliers, HUD toggles, render
	# quality, ...) silently falls back to its hardcoded default on an F6 run
	# instead of what was last saved. Idempotent, so it costs nothing on the
	# normal path where [method Session.start] already loaded it once.
	Session.load_from_disk()
	# The 🎬 Juice dials too, before anything below reads one — see [method
	# JuiceSettings.ensure_loaded].
	JuiceSettings.ensure_loaded()
	if Session.far_clip > 0.0:
		_far_clip = Session.far_clip
	if Session.far_view_max > 0.0:
		_far_view_max = Session.far_view_max
	_restore_early_prefs()
	library = PartLibrary.instance()
	library.load_all()
	_load_design()

	audio = SpaceAudio.new()
	audio.name = "SpaceAudio"
	add_child(audio)

	# A scene restart reloads this node; land back in the location we were in.
	location = Session.flight_location
	# Campaign levels are always flown in the space scene: the scenarios need
	# its AI spawner, whatever the flight test was last left on.
	if not Session.pending_level.is_empty():
		location = Location.SPACE
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
	# Deferred: gravity, the HUD, the rear view and the weapon systems all need
	# to exist before their saved state can be put back.
	_restore_prefs.call_deferred()
	_setup_ship_lights()
	# The player's own hull has to follow a global look and palette change, like the

	# traffic and the scenery do — see [method AiSpawner._on_style_changed] and
	StyleManager.instance().style_changed.connect(_on_style_changed)
	StyleManager.instance().palette_changed.connect(_on_palette_changed)
	# Apply the Settings panel's persisted far values now that the camera exists
	# (it is created in FlightCamera._ready, so _enter_tree was too early).
	camera_rig.set_far_clip(_far_clip)
	camera_rig.set_far_view_max(_far_view_max)
	camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if Session.camera_view in PERSISTED_VIEWS:
		camera_rig.set_mode(Session.camera_view)
	if Session.mobile_view_fit:
		camera_rig.set_mobile_view(true)
	camera_rig.adopt(model, model, view)
	_build_advanced_lighting()
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
	elif location == Location.GENERATED_SYSTEM:
		var spawn := _generated_system_spawn(Session.pending_spawn_body_name)
		if spawn["ok"]:
			model.global_position = spawn["pos"]
			model.velocity = spawn["vel"]
			var vel: Vector3 = spawn["vel"]
			if vel.length_squared() > 0.01:
				model.global_transform.basis = Basis.looking_at(vel.normalized(), Vector3.UP)
	_spawn = model.global_transform
	# Feed asteroid positions into the model for collision detection. The
	# SpaceScene populates its meta in its own _ready, which runs before this.
	if space != null and space.has_meta("asteroid_data"):
		model._asteroid_data = space.get_meta("asteroid_data") as Array	# Hand the gravity system to the flight model AND the space scene
	# (so the moon integrates via real gravity, not sine animation).
	if gravity != null:
		gravity.pull_enabled = Session.gravity_pull
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
	bug_hunt = BugHunt.new()
	bug_hunt.name = "BugHunt"
	bug_hunt.root = self
	add_child(bug_hunt)
	# Spray-painted targets over the ships the player has tangled with; drawn
	# on the HUD so they keep a fixed screen size at any range.
	_interaction_markers = InteractionMarkers.new()
	_interaction_markers.name = "InteractionMarkers"
	_interaction_markers.ships_source = _marker_ships
	_interaction_markers.exclude_source = func() -> Variant: return controlled_ai
	_hud.add_child(_interaction_markers)
	# Re-apply persisted trail toggles after a scene restart: the preference flags
	# survive in static state, but the trail nodes themselves were rebuilt.
	set_trail_player(Session.trail_player)
	set_trail_ships(Session.trail_ships)
	# Persisted drift field and planet pointer: rebuild the overlays the menus
	# left on. The drift flag also gates the streak update each frame.
	_mote_field_on = Session.drift_field
	if _motes != null:
		_motes.visible = _mote_field_on
	if Session.planet_pointer and gravity != null and model != null:
		if _planet_pointer == null:
			_planet_pointer = PlanetPointer.new()
			_planet_pointer.name = "PlanetPointer"
			_planet_pointer.setup(gravity, model)
		if not _planet_pointer.is_showing():
			add_child(_planet_pointer)
			_planet_pointer.toggle()
	_coach = %Coach as CoachOverlay
	_coach.steps = FLIGHT_STEPS
	_coach.walkthrough_id = "flight_walkthrough"
	_coach.start()
	power_ups = PowerUps.new()
	power_ups.setup(self)
	power_ups.picked.connect(func(_k: int) -> void: tutorial_note("powerup"))
	add_child(power_ups)
	GameDefaults.auto_bake = bool(Session.pref("auto_bake", true))
	# The interactive tutorial runs once, on a real (windowed) first flight.
	if JuiceSettings.tutorial_on and not bool(Session.pref("tutorial_done", false)) 			and Session.pending_level.is_empty()			and DisplayServer.get_name() != "headless":
		start_tutorial.call_deferred()

	systems.state_changed.connect(_on_systems_state)
	systems.fire_blocked.connect(_on_systems_fire_blocked)
	systems.weapon_switched.connect(_on_weapon_switched)
	if _hud != null and _hud.has_method("update_weapon_badge"):
		_hud.update_weapon_badge(systems.get_active_weapon())
	model.assist_changed.connect(_on_model_assist_changed)
	model.orbit_changed.connect(_on_orbit_changed)
	model.collided.connect(_on_model_collided)
	model.out_of_control_changed.connect(_on_model_ooc_changed)
	model.boost_changed.connect(_on_model_boost_changed)
	_build_incident_director()

	BuilderTheme.apply_density_scale(get_window())
	get_viewport().size_changed.connect(
		func() -> void: BuilderTheme.apply_density_scale(get_window())
	)

	apply_performance()
	# Lights and environments that arrive later (AI ships' headlights, a
	# rebuilt space scene) obey the shadow/glow dials too.
	if not get_tree().node_added.is_connected(PerformanceSettings.apply_to_node):
		get_tree().node_added.connect(PerformanceSettings.apply_to_node)
	# Reached from the game's menu (a campaign level or sandbox): the way home,
	# and for a level its start, status and end card.
	if not Session.pending_level.is_empty() or not Session.pending_ship.is_empty():
		campaign_overlay = CampaignLevelOverlay.new()
		campaign_overlay.name = "CampaignOverlay"
		campaign_overlay.setup(self)
		add_child(campaign_overlay)


## Push the ⚡ Performance panel's settings onto the engine and this scene.
## High-res renders the 3D scene at a higher internal resolution and
## downscales to the viewport: same FOV, just sharper. It multiplies with the
## panel's render scale instead of overwriting it.
##
## Physics interpolation: only the ships opt in (see [method _build_ship] and
## [AiShip]). They are the things moved on physics ticks. Everything else in
## this scene is placed per render frame (camera, sky, HUD, emotes, effects),
## and interpolating those would just drag them a tick behind, so this root
## switches it off for its subtree and each ship switches it back on.
func apply_performance() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	PerformanceSettings.apply(get_tree(), 1.5 if Session.high_res else 1.0)


# --- Construction -----------------------------------------------------------

func _load_design() -> void:
	# The menu handed over a ship (campaign or sandbox): fly exactly that hull
	# in exactly that paint, with its garage upgrades.
	upgrade_mults = (Session.pending_ship.get("mults", {}) as Dictionary).duplicate()
	AiShip.player_upgrade_power = upgrade("guns")
	var preset_id := String(Session.pending_ship.get("preset", ""))
	if preset_id != "":
		design = library.build_preset_design(preset_id)
		if design != null:
			var paint := String(Session.pending_ship.get("paint", ""))
			if paint != "":
				library.apply_faction(design, paint)
			design.design_name = String(Session.pending_ship.get("name", design.design_name))
			return
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
		var toy_factions := ["neon_turbo", "cobalt_vanguard", "emerald_warlords", "crimson_toybox", "amethyst_void", "solar_raiders", "cyber_teal"]
		var pick_fid: String = toy_factions[randi() % toy_factions.size()]
		library.apply_faction(design, pick_fid)
		design.design_name = design.design_name + " (Toy Edition)"


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
		_ai_spawner.ship_destroyed.connect(_on_ai_ship_destroyed)
		_ai_spawner.ship_marked.connect(_on_ai_ship_marked)
		_ai_spawner.ship_yeeted.connect(_on_ai_ship_yeeted)
		add_child(_ai_spawner)
	elif location == Location.GENERATED_SYSTEM:
		_build_generated_system()
		_build_test_volume_environment()
	else:
		_build_test_volume_environment()
	scenarios = FlightScenarios.new()
	scenarios.name = "Scenarios"
	scenarios.setup(self)
	add_child(scenarios)


## [constant Location.GENERATED_SYSTEM]: the solar_system_gen lab's own
## [SolarSystemGenerator], rebuilt here from [member Session.pending_solar_system]
## rather than reused live — a generator built in the lab scene does not
## survive [method SceneTree.change_scene_to_file], so the lab hands off a
## recipe, not a node (see [SolarSystemGenLabRoot._on_enter_flight_test_pressed]).
## Params are applied before [method Node.add_child] so the generator's own
## [method Node._ready] (which auto-generates once [member
## SolarSystemGenerator.bodies] is empty and it enters the tree) uses them
## directly instead of generating twice; manually-placed belts replay after,
## since they need a generated system to attach to.
func _build_generated_system() -> void:
	generated_system = SolarSystemGenerator.new()
	generated_system.name = "GeneratedSystem"
	var recipe := Session.pending_solar_system as SolarSystemData
	if recipe != null:
		recipe.apply_params(generated_system)
	else:
		generated_system.system_seed = Session.seed if Session.seed != 0 else randi()
	# The lab's fast-forward is an observation dial, not a property of the system
	# — and it arrives here as one, because the recipe stores the generator's
	# time_scale and Session keeps the last slider position. Left alone, a lab
	# parked at 60× makes this scene run 48 N-body substeps over every body every
	# physics frame, which measures ~170 ms a frame once belts are live: single
	# digit FPS from a setting the player set to watch orbits drift, not to fly
	# through. Flying a system is a 1× activity; the scene's own X2/X4/X10
	# (see [method set_time_scale]) is how you speed it up here.
	generated_system.time_scale = 1.0
	# Belt rocks are scenery in this location, never simulated bodies — see
	# [member SolarSystemGenerator.belts_simulate] for the measurement. Nothing
	# here can collide with them (this location builds no [PhysWorld]), so LIVE
	# rocks are pure cost.
	generated_system.belts_simulate = false
	# The generator's own O(n²) collision sweep (see
	# [method SolarSystemGenerator._resolve_collisions]) still runs every frame
	# over the remaining planets/moons/manual belts even with live rocks off,
	# and flight has no use for it catching an overlap within one frame — a
	# stable system's bodies drift into each other over many seconds, not one.
	# Checking every 4th frame keeps the safety net while cutting this sweep's
	# cost by 4x, which is the other big chunk of "flying into a generated
	# system lags worse than a hand-built one".
	generated_system.collision_check_interval = 4
	add_child(generated_system)
	if recipe != null:
		recipe.spawn_manual_belts(generated_system)


## Spawn transform for [constant Location.GENERATED_SYSTEM]: a clean orbit near
## [param body_name] (or the first planet if it's empty or not found) — the
## same placement [method SolarSystemGenLabRoot._spawn_test_ship] already
## proved out in the lab. {"pos": Vector3, "vel": Vector3, "ok": bool}; ok is
## false only when there is no generated system or no planet to spawn near.
func _generated_system_spawn(body_name: String) -> Dictionary:
	if generated_system == null:
		return {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "ok": false}
	var entry := generated_system.find_body(body_name)
	if entry.is_empty():
		var planets := generated_system.pickable_bodies().filter(
			func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET
		)
		if planets.is_empty():
			return {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "ok": false}
		entry = planets[0]
	var body_node: Node3D = entry["node"]
	var radius: float = entry["radius"]
	var spawn_dist := radius * 3.0 + 400.0
	var dir := Vector3(1.0, 0.15, 0.0).normalized()
	var pos := body_node.global_position + dir * spawn_dist
	var dominant := generated_system.gravity.find_dominant_body(pos)
	var vel := generated_system._orbit_velocity_at(pos, dominant) if dominant != null else Vector3.ZERO
	return {"pos": pos, "vel": vel, "ok": true}


## Create the gravity system and register all gravitating bodies from
## [SpaceScene]'s constants. Gravity is off by default — the player
## toggles it with the G key. In the test volume, gravity stays off.
func _build_gravity() -> void:
	if location == Location.GENERATED_SYSTEM and generated_system != null:
		# Reuse the generator's own already-populated GravitySystem rather than
		# re-registering every body — SPACE builds its own because SpaceScene
		# exposes plain position/radius constants, not a live GravitySystem.
		gravity = generated_system.gravity
		return
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
			# Bound: the signal names only the other body, and the handler has
			# to know which rock was struck (unbound, every knock errored).
			body.impacted.connect(_on_rock_impacted.bind(body))
		phys_world.add(body)

	# The player's own ship: a driven body that keeps its hand integration.
	model.set_phys_world(phys_world, _ship_collision_radius(view), _ship_hull(view))


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


func _build_incident_director() -> void:
	if incident_director != null:
		incident_director.queue_free()
	incident_director = IncidentDirector.new()
	incident_director.name = "IncidentDirector"
	var ctx := NebulaContext.new()
	ctx.gravity = gravity
	ctx.phys = phys_world
	# M5 — create a session-scoped reputation store and wire it in.
	var rep_store := SessionRepStore.new()
	ctx.reputation = rep_store
	incident_director.context = ctx
	incident_director.world_parent = self
	if _hud != null:
		incident_director.hud_container = _hud.get_event_container()
	add_child(incident_director)
	# Wire incident outcomes into the reputation system.
	# Signature: incident_resolved(id: String, how: String, who: Variant) —
	# "who" is null when nobody in particular resolved it (a String here
	# errored on every such incident).
	incident_director.incident_resolved.connect(
		func(_id: String, _how: String, who: Variant) -> void:
			# "who" is the actor node name; "how" is the resolve verb.
			# Only hostile resolutions generate grudges for now.
			var _who := str(who) if who != null else ""
			if _who.is_empty():
				return
			match _how:
				"player_attacked":
					rep_store.record_act("player", "faction_generic", RepStore.ACTS.ATTACK, 4)
				"player_rescued":
					rep_store.record_act("player", "faction_generic", RepStore.ACTS.RESCUE, 3)
				_:
					pass
	)



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


## The name of the live profile, for the HUD and the Flight menu's readout.
func phys_profile_id() -> String:
	return _phys_profile_id


# --- Rock promotion (M1) ------------------------------------------------------

## A rock was hit hard enough to come loose. It stops being an immovable wall and
## becomes a free body: the world integrates it, gravity steers it, and its
## visual is drawn from its node each frame. It is given the velocity it would
## have taken from this hit if it had had mass all along (the solver resolved it
## as kinematic, so it absorbed the hit without moving).
func _on_rock_impacted(
	_other: PhysBody, impulse: float, _point: Vector3, normal: Vector3, closing: float, rock: PhysBody
) -> void:
	if not rock.kinematic or closing < ROCK_KNOCK_SPEED:
		return
	# Only a ship knocks a rock loose. A freed rock hitting its neighbours
	# would free them too, and a chain through the belt filled the live-rock
	# slots within a second.
	if _other != null and _other.layer == PhysBody.Layer.ROCK:
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
##
## This is the fallback shape, not the shape. [method _ship_hull] supersedes it
## with a compound of hull sections wherever the design has geometry to build one
## from; this single sphere is what a design that assembled to nothing collides
## as, and what every reader that can only afford one sphere still sees.
func _ship_collision_radius(view: ShipView) -> float:
	if view == null:
		return 3.0
	return maxf(view.aabb.size.length() * 0.5, 3.0)


## The ship's compound collision hull — see [method ShipView.collision_hull] —
## or empty when there is no assembled geometry, so the single sphere stands.
## Offsets are ship space, which is the space [PhysBody] reads them in: the
## body's node *is* the [FlightModel], and the assembled [ShipView] hangs off it
## through an untransformed holder, so the two spaces coincide.
func _ship_hull(view: ShipView) -> Array[Dictionary]:
	if view == null:
		return []
	return view.collision_hull()


## Re-skin the player's hull for the new look and palette, and re-derive its
## collision volume from the geometry that look produced.
##
## Uses [method FlightModel.refresh_hull] rather than re-binding the world, because
## re-binding multiplies mass by the ship-size factor each call — a style change
## must not make the player heavier.
func _on_style_changed(_profile: StyleProfile) -> void:
	if view == null:
		return
	view.restyle()
	if model != null:
		model.refresh_hull(_ship_collision_radius(view), _ship_hull(view))


func _on_palette_changed(_palette: Palette) -> void:
	if view != null:
		view.restyle(true)
	if model != null:
		model.refresh_hull(_ship_collision_radius(view), _ship_hull(view))
	LargeCraftGenerator.refresh_materials()
	for craft in _large_craft:
		if is_instance_valid(craft):
			craft.restyle()
	if _hud != null:
		_hud.refresh_palette()


## Toggles mobile screen fitting view (closer framing & responsive UI).
func set_mobile_view(enabled: bool) -> void:
	Session.mobile_view_fit = enabled
	Session.save_to_disk()
	if camera_rig != null:
		camera_rig.set_mobile_view(enabled)
	if _hud != null:
		_hud.update_mobile_view(enabled)


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

	# Three lights: Key, Fill, and Rim.
	# The key light illuminates form with crisp directional shadows on enhanced lighting.
	# The fill light softens shadows with cool sky tones.
	# The rim light catches edges from behind, replacing the camera-axis hack with authentic edge separation.
	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	_key_light.light_energy = 2.4 if Session.enhanced_lighting else 2.0
	_key_light.light_color = Color("fff1de")
	_key_light.shadow_enabled = Session.enhanced_lighting
	_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_key_light.directional_shadow_max_distance = 180.0
	_key_light.directional_shadow_blend_splits = true
	_key_light.shadow_bias = 0.03
	_key_light.shadow_normal_bias = 1.2
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

	# Rim / Kicker: angled from behind-above to carve out silhouette and metallic edges
	# against the black void of space, avoiding the flat washed-out camera flashlight look.
	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "RimLight"
	_rim_light.light_energy = 1.15 if Session.enhanced_lighting else 0.8
	_rim_light.light_color = Color("9ec8ff")
	_rim_light.light_specular = 0.75
	_rim_light.shadow_enabled = false
	_rim_light.look_at_from_position(Vector3.ZERO, Vector3(0.55, 0.4, 0.75), Vector3.UP)
	add_child(_rim_light)


# --- Ship Lights & Tactical Searchlights -------------------------------------

func _setup_ship_lights() -> void:
	if model == null:
		return
	var on := Session.ship_headlights

	_headlight_l = SpotLight3D.new()
	_headlight_l.name = "HeadlightL"
	_headlight_l.light_energy = 3.8 if on else 0.0
	_headlight_l.light_color = Color("eef6ff")
	_headlight_l.spot_range = 220.0
	_headlight_l.spot_angle = 32.0
	_headlight_l.spot_attenuation = 1.0
	_headlight_l.position = Vector3(-1.8, 0.0, -1.2)
	_headlight_l.rotation = Vector3.ZERO # Point along -Z (ship forward)
	model.add_child(_headlight_l)

	_headlight_r = SpotLight3D.new()
	_headlight_r.name = "HeadlightR"
	_headlight_r.light_energy = 3.8 if on else 0.0
	_headlight_r.light_color = Color("eef6ff")
	_headlight_r.spot_range = 220.0
	_headlight_r.spot_angle = 32.0
	_headlight_r.spot_attenuation = 1.0
	_headlight_r.position = Vector3(1.8, 0.0, -1.2)
	_headlight_r.rotation = Vector3.ZERO # Point along -Z (ship forward)
	model.add_child(_headlight_r)

	_nav_light_port = OmniLight3D.new()
	_nav_light_port.name = "NavPort"
	_nav_light_port.light_color = Color("ff2233")
	_nav_light_port.light_energy = 0.9 if on else 0.0
	_nav_light_port.omni_range = 8.0
	_nav_light_port.position = Vector3(-2.4, 0.2, 0.6)
	model.add_child(_nav_light_port)

	_nav_light_starboard = OmniLight3D.new()
	_nav_light_starboard.name = "NavStarboard"
	_nav_light_starboard.light_color = Color("22ff66")
	_nav_light_starboard.light_energy = 0.9 if on else 0.0
	_nav_light_starboard.omni_range = 8.0
	_nav_light_starboard.position = Vector3(2.4, 0.2, 0.6)
	model.add_child(_nav_light_starboard)


func toggle_headlights() -> bool:
	Session.ship_headlights = not Session.ship_headlights
	Session.save_to_disk()
	var on := Session.ship_headlights
	if _headlight_l != null:
		_headlight_l.light_energy = 3.5 if on else 0.0
	if _headlight_r != null:
		_headlight_r.light_energy = 3.5 if on else 0.0
	if _nav_light_port != null:
		_nav_light_port.light_energy = 0.9 if on else 0.0
	if _nav_light_starboard != null:
		_nav_light_starboard.light_energy = 0.9 if on else 0.0
	if audio != null:
		audio.play_light_switch_sound()
	if _hud != null:
		_hud.show_hint("Tactical Headlights: %s (L)" % ("ON" if on else "OFF"))
	return on


# --- Atmospheric Re-entry VFX -----------------------------------------------

func _update_atmospheric_reentry(_delta: float) -> void:
	if model == null or view == null or not model.is_inside_tree():
		return
	var ship_pos := model.global_position
	var speed := model.velocity.length()
	var atmo_burn := 0.0

	if location == Location.SPACE and space != null:
		var p_dist := ship_pos.distance_to(space.planet_centre)
		var atmo_outer := space.planet_radius * 1.35
		var atmo_inner := space.planet_radius * 1.02
		if p_dist < atmo_outer and speed > 120.0:
			var depth := clampf((atmo_outer - p_dist) / (atmo_outer - atmo_inner), 0.0, 1.0)
			var speed_factor := clampf((speed - 120.0) / 250.0, 0.0, 1.0)
			atmo_burn = depth * speed_factor
	elif location == Location.GENERATED_SYSTEM and gravity != null:
		var dominant := gravity.find_dominant_body(ship_pos)
		if dominant != null and dominant.radius > 50.0 and speed > 120.0:
			var p_dist := ship_pos.distance_to(dominant.position)
			var atmo_outer := dominant.radius * 1.35
			var atmo_inner := dominant.radius * 1.02
			if p_dist < atmo_outer:
				var depth := clampf((atmo_outer - p_dist) / (atmo_outer - atmo_inner), 0.0, 1.0)
				var speed_factor := clampf((speed - 120.0) / 250.0, 0.0, 1.0)
				atmo_burn = depth * speed_factor

	view.set_reentry_burn(atmo_burn)
	if atmo_burn > 0.12 and randf() < 0.35:
		var nose_pos := model.global_position - model.global_transform.basis.z * (view.aabb.size.z * 0.5 + 0.5)
		Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(model.global_transform.basis, nose_pos), atmo_burn * 1.8, Color(1.0, 0.55, 0.15))
		if atmo_burn > 0.4 and randf() < 0.2:
			Juice.burst(BurstPresets.Preset.VAPOUR, Transform3D(model.global_transform.basis, nose_pos), atmo_burn * 2.0, Color(1.0, 0.35, 0.1, 0.6))



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
	# A speck half a metre across: a handful of faces reads just as round.
	# SphereMesh's default 64 × 32 made every mote 4,224 triangles — 3 million
	# a frame for the field, 96% of everything the flight scene drew, and the
	# single biggest drain on a phone's battery.
	mesh.radial_segments = 8
	mesh.rings = 4

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
	# The player's own speed dial, set before [method _assemble] configures the
	# model: see [member FlightModel.speed_scale] for why the model does not read
	# it from Session itself.
	model.speed_scale = player_speed_base()
	model.ram_upgrade = upgrade("yeet")
	# Restore the last control and assist modes. Both used to live only on this
	# instance, so every launch came back in Arcade with default assist.
	if Session.control_mode >= 0 and Session.control_mode < FlightModel.ControlMode.size():
		model.control_mode = Session.control_mode
	if Session.assist_mode >= 0:
		model.set_assist_mode(Session.assist_mode)
	# Drawn between physics ticks when interpolation is on — see [method
	# apply_performance]. The hull, plumes and lights are children and ride along.
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
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
	_emote_height = view.aabb.size.y * 0.5 + 0.3
	model.configure(view.resolution.stats, systems, damage, _ship_holder)
	model.squash_pivot = view.aabb.get_center()
	systems.bind(view, self)
	systems.sustain_fire = true
	systems.is_player_rig = true
	damage.bind(view, model, _ship_holder)
	damage.part_broken.connect(_on_part_broken)
	if camera_rig != null:
		camera_rig.adopt(model, model, view)

	# Init player HP from ship stats (clamped to a playable range, scaled by the
	# global HP dial and the player's own extra durability -- see JuiceSettings).
	_player_dead = false
	var stats := view.resolution.stats
	var base_hp := maxf(stats.get_stat("hull_hp"), 80.0) * JuiceSettings.hull_hp_mult
	player_max_hp = base_hp * JuiceSettings.player_durability_mult
	player_hp = player_max_hp
	player_max_shield = _design_shield()
	player_shield = player_max_shield


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

## Views worth coming back to after a restart. The orbit/planet/free/target
## views are situational (game over switches to FREE, for one), so they aren't
## remembered.
const PERSISTED_VIEWS := [
	FlightCamera.Mode.COCKPIT, FlightCamera.Mode.CHASE, FlightCamera.Mode.REAR,
	FlightCamera.Mode.ACTION, FlightCamera.Mode.CINEMATIC, FlightCamera.Mode.SIDE,
	FlightCamera.Mode.TOP_DOWN,
]
## Next [method Time.get_ticks_msec] at which [method _sync_session] runs.
var _next_session_sync_ms := 0


## Mirror live player state that has no persisting setter of its own into
## [Session], then save if anything changed. It runs about once a second and
## on exit, so a setting reaches disk however it was changed: the menu, a
## hotkey, or a call site that forgot to save. Skipped headless, so a smoke
## test's throwaway settings never overwrite the player's.
func _sync_session() -> void:
	if model != null:
		Session.control_mode = model.control_mode
		Session.assist_mode = model.assist_mode
	Session.move_profile = move_profile
	if camera_rig != null and camera_rig.mode in PERSISTED_VIEWS and not _player_dead:
		Session.camera_view = camera_rig.mode
	Session.far_clip = _far_clip
	Session.far_view_max = _far_view_max
	_capture_prefs()
	if DisplayServer.get_name() != "headless":
		Session.autosave()


## Copy every live flight-test setting that has no persisting home of its own
## into [member Session.prefs]. Read from the live objects rather than hooked
## into each menu row, so a change is caught however it was made: menu,
## hotkey, or combat panel. [method _restore_prefs] is the other half.
func _capture_prefs() -> void:
	if not _prefs_restored:
		# Before the restore has run, the live state is still defaults, and
		# capturing it would overwrite what was saved.
		return
	var p := Session.prefs
	p["rear_view"] = _rear_view_on
	p["high_contrast"] = BuilderTheme.high_contrast
	p["phys_profile"] = _phys_profile_id
	p["facing_target"] = facing_target
	p["time_scale"] = _time_scale
	p["craft_size"] = craft_size_preset
	if camera_rig != null:
		p["ooc_camera_hold"] = camera_rig.ooc_camera_hold
	if model != null:
		p["warp"] = model.warp_active
		p["gravity_strength"] = model.gravity_strength
		p["orbital_assist_rate"] = model.orbital_assist_rate
	if systems != null:
		p["weapon_index"] = systems.active_weapon_index
	if gravity != null:
		p["gravity_mode"] = gravity.mode
		p["gravity_chaos"] = _gravity_chaos
		# Chaos forces its own range; only a hand-picked range is worth keeping.
		if not _gravity_chaos:
			p["gravity_range"] = gravity.range_multiplier
	p["gravity_viz"] = _gravity_viz != null and _gravity_viz.is_showing()
	var style := StyleManager.instance().current_profile
	if style != null:
		p["star_style_" + style.id] = [style.star_size, style.star_five_point]


## Set by [method _restore_prefs]; [method _capture_prefs] waits for it.
var _prefs_restored := false


## The prefs that must be in place before the scene builds: the collision feel
## profile (read when the physics world is made), high contrast (read when
## materials are made) and the star style (read when the sky is built).
func _restore_early_prefs() -> void:
	_phys_profile_id = String(Session.pref("phys_profile", _phys_profile_id))
	var hc := bool(Session.pref("high_contrast", BuilderTheme.high_contrast))
	BuilderTheme.high_contrast = hc
	ShipMaterials.high_contrast = hc
	var style := StyleManager.instance().current_profile
	if style != null:
		var star: Variant = Session.pref("star_style_" + style.id, null)
		if star is Array and (star as Array).size() == 2:
			style.star_size = float(star[0])
			style.star_five_point = float(star[1])


## Put the rest of [member Session.prefs] back once the scene is built.
func _restore_prefs() -> void:
	if not is_inside_tree():
		return
	if Session.move_profile != move_profile:
		set_move_profile(Session.move_profile)
	var p := Session.prefs
	if BuilderTheme.high_contrast:
		get_window().theme = BuilderTheme.build()
	if bool(p.get("rear_view", false)) and not _rear_view_on:
		toggle_rear_view()
	if camera_rig != null:
		camera_rig.ooc_camera_hold = bool(p.get("ooc_camera_hold", camera_rig.ooc_camera_hold))
	facing_target = bool(p.get("facing_target", facing_target))
	craft_size_preset = int(p.get("craft_size", craft_size_preset))
	var saved_time := float(p.get("time_scale", 1.0))
	if not is_equal_approx(saved_time, _time_scale):
		set_time_scale(saved_time)
		# Said out loud: a warp carried over from last time makes every fight
		# run that many times faster (and the machine do that much more work).
		if _hud != null and not is_equal_approx(saved_time, 1.0):
			_hud.show_hint("Time warp ×%s carried over from last session" % str(snappedf(saved_time, 0.1)))
	if model != null:
		model.warp_active = bool(p.get("warp", model.warp_active))
		model.gravity_strength = float(p.get("gravity_strength", model.gravity_strength))
		model.orbital_assist_rate = float(p.get("orbital_assist_rate", model.orbital_assist_rate))
	if systems != null and p.has("weapon_index"):
		var idx := int(p["weapon_index"])
		if idx >= 0 and idx < SystemsSim.WEAPONS.size() and idx != systems.active_weapon_index:
			set_weapon_index(idx)
	if gravity != null:
		gravity.mode = int(p.get("gravity_mode", gravity.mode))
		if bool(p.get("gravity_chaos", false)) and not _gravity_chaos:
			toggle_gravity_chaos()
		elif p.has("gravity_range"):
			gravity.range_multiplier = float(p["gravity_range"])
	if bool(p.get("gravity_viz", false)) and (_gravity_viz == null or not _gravity_viz.is_showing()):
		toggle_gravity_viz()
	_prefs_restored = true


func _exit_tree() -> void:
	_sync_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_sync_session()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back(true)


## Back (a phone's back button/gesture) and Escape: close the open panel or
## popup first. With nothing open, Back does what D does on a keyboard — opens
## the debug column (which has a Hangar button) — and Escape leaves for the
## hangar as it always has.
func _on_back(from_phone: bool) -> void:
	if _hud != null and _hud.close_top_panel():
		return
	if from_phone:
		if _hud != null:
			_hud.toggle_debug_panel()
	else:
		return_to_hangar()


func _process(delta: float) -> void:
	_update_blast_outline(delta)
	_update_knocked_planets(delta)
	if _pilot != null:
		_pilot.frame_tick(delta)
	if Time.get_ticks_msec() >= _next_session_sync_ms:
		_next_session_sync_ms = Time.get_ticks_msec() + 1000
		_sync_session()
	# If the ship being piloted died, hand control back to the player's own ship.
	if controlled_ai != null and (not is_instance_valid(controlled_ai) or not controlled_ai._alive):
		leave_control()
		if _hud != null:
			_hud.show_hint("That ship was shot down — back in your own")
	_update_grace_blink()
	# Feed the lock-on target to whichever systems are firing so guided shots home.
	# A lock whose target died this frame is a freed reference: typed-assigning
	# it (even to null-typed Node3D) errors, so drop it first.
	if not is_instance_valid(locked_target):
		locked_target = null
	if active_systems() != null:
		active_systems().target_ref = locked_target
	# The one place the flight scene's time-scale is written: the time warp
	# (satellite X2/X4/X10) × death slow-mo × the live hitstop. Writing
	# _time_scale alone here used to cancel both of the others a frame after
	# they began.
	# The kill cam's pause rides on the same product (see [method
	# _kill_cam_factor]).
	Engine.time_scale = _time_scale * _slowmo * Juice.hitstop_factor() * _kill_cam_factor()
	_regen_player(delta)
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
	# Belt LOD (see SolarSystemGenerator.BeltState): the player ship is the
	# only focus a generated system's belts promote near, matching the lab's
	# own "only when a player exists" contract.
	if generated_system != null and model != null:
		generated_system.set_lod_focus(model.global_position, true)
	# Update moon gravity body and landmark position so collision/gravity/markers
	# match the visual orbit.
	if gravity != null and space != null and space._moon_node != null:
		var moon_pos := space._moon_node.global_position
		if gravity._bodies.size() > 3:
			gravity._bodies[3].position = moon_pos
		# Update the moon landmark position (index 1 after Tarn IV).
		if space.landmarks.size() > 1:
			space.landmarks[1]["position"] = moon_pos
	if _motes != null and _mote_field_on:
		_motes.global_position = (model.global_position / MOTE_SPACING).round() * MOTE_SPACING
		_update_mote_streaks(delta)
	# Motion trails: the player's own, and one per live AI ship, so the direction
	# of travel is readable at a glance. Toggled separately from the Trails menu.
	_update_player_trail()
	_update_ship_trails()
	_update_aggro_indicators()
	_update_near_miss(delta)
	_update_large_craft_orbits(delta)
	_update_large_craft_patrols(delta)
	_update_large_craft_turrets(delta)
	# Drift, spin and fade broken-off debris.
	var still_alive: Array[Dictionary] = []
	for d in _debris_list:
		# DebrisRegistry can free a piece off-screen at any time without
		# pruning this list — validate the raw reference *before* casting it,
		# since casting an already-freed Object throws "Trying to cast a
		# freed object" even though the very next check would have caught it.
		var raw_node: Object = d["node"]
		if raw_node == null or not is_instance_valid(raw_node):
			continue
		var node: Node3D = raw_node as Node3D
		if not node.is_inside_tree():
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
	# Runs before PhysWorldDriver's own _physics_process (a child of this
	# node, so it processes after its parent — the same ordering the world's
	# own doc comment already leans on for "controllers write velocity, then
	# the world steps") — a part freed this frame must be pruned from
	# phys_world *before* it steps, or the freed PhysBody.node crashes
	# PhysWorld's own scenery indexing on the very next step.
	_prune_large_craft_collision()
	_read_keyboard(delta)
	_update_large_craft_docking(delta)
	# Once a second, put knocked-loose rocks back to scenery when they drift away.
	_rock_demote_timer -= delta
	if _rock_demote_timer <= 0.0:
		_rock_demote_timer = 1.0
		_sweep_live_rocks()
	# A dead lock is no lock — drop it so facing assist stops fighting a freed
	# reference and the HUD stops drawing a bracket around nothing.
	if not is_instance_valid(locked_target):
		locked_target = null
	# Nose-on assist: when armed (the facing toggle, or dogfight control mode)
	# and a target is locked, steer yaw/pitch so the ship always faces it.
	# Otherwise, the lighter-touch aim-assist nudge gets a turn instead.
	# An assist that stopped (lock lost, cone left) hands the axes straight
	# back to the stick; otherwise its last command would keep the ship turning.
	var steered := active_model()
	if _assist_steering and steered != null:
		steered.command.yaw = -_stick_input.x
		steered.command.pitch = -_stick_input.y
	_assist_steering = locked_target != null
	if locked_target != null and (facing_target or _dogfight_armed()):
		_apply_target_facing()
	elif locked_target != null:
		_apply_aim_assist()
	# A movement profile's pilot flies after the assists, so it has the last word.
	_tick_pilot(delta)
	_tick_ram_reach()
	# Touch-to-accelerate: holding the screen drives throttle to full.
	var flight := active_model()
	var systems_now := active_systems()
	if flight != null:

		if _touch_accel and not _button_boost:
			flight.command.throttle = clampf(
				flight.command.throttle + 1.2 * delta,
				ThrottleLever.MIN_VALUE, 1.0
			)
			if systems_now != null:
				systems_now.set_throttle(clampf(absf(flight.command.throttle), 0.0, 1.0))
		if systems_now != null:
			systems_now.set_boost(flight.command.boost)


	if audio != null and flight != null:
		var strafe := flight.velocity.slide(flight.global_transform.basis.z).length()
		audio.update_engine_spool(flight.command.throttle, flight.command.boost, strafe, delta)

	_update_atmospheric_reentry(delta)



# --- Ram reach --------------------------------------------------------------------

## Earliest next reach-ram per ship (instance id -> msec), so a pass rams once.
var _ram_reach_next: Dictionary = {}
## Below this closing speed (m/s) the reach does nothing — a drift past is no ram.
const RAM_REACH_MIN_CLOSING := 12.0


## The player's attack reach: a ship inside [member JuiceSettings.player_ram_reach]
## × the player's hull radius that the player is closing on fast is rammed as if
## they had touched ([method FlightModel.take_reach_ram]) — a bigger hitbox for
## dealing a ram, never for taking one. Hulls actually touching are left to the
## physics. Friendly and harmless ships only with the one-thumb profiles' magnet
## on them ([member JuiceSettings.magnet_friendlies]).
func _tick_ram_reach() -> void:
	var m := active_model()
	if m == null or _player_dead or JuiceSettings.player_ram_reach <= 1.0:
		return
	var body := m.phys_body()
	if body == null or m.velocity.length() < RAM_REACH_MIN_CLOSING:
		return
	var any_side := JuiceSettings.magnet_friendlies and profile_is_one_thumb(move_profile)
	var now := Time.get_ticks_msec()
	for ship in live_enemies():
		if ship == controlled_ai or ship.model == null or not ship.is_inside_tree():
			continue
		if not any_side and ship.attitude_to_player() in [AiShip.Attitude.FRIENDLY, AiShip.Attitude.HARMLESS]:
			continue
		var other := ship.model.phys_body()
		if other == null:
			continue
		var to := ship.model.global_position - m.global_position
		var d := to.length()
		if d < 0.01 or d <= body.radius + other.radius or d > body.radius * JuiceSettings.player_ram_reach + other.radius:
			continue
		var n := to / d
		var closing := (m.velocity - ship.model.velocity).dot(n)
		if closing < RAM_REACH_MIN_CLOSING or int(_ram_reach_next.get(ship.get_instance_id(), 0)) > now:
			continue
		_ram_reach_next[ship.get_instance_id()] = now + 450
		var point := ship.model.global_position - n * other.radius
		ship.model.take_reach_ram(body, point, n, closing)
		# The rammer's own reaction (a slingshot bounce, a swipe's dash knocked
		# out), as for a real hit — without any damage to it.
		m.impacted.emit(other, -n, closing)
		Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), point), 1.4, Color(1.0, 0.8, 0.35))
		Juice.shake(clampf(closing * 0.003, 0.08, 0.4), 0.25)


## True when the active ship's control mode should implicitly keep the nose on a
## locked target: dogfight (built for knife-fight range) and arcade (the mode a
## player goes to to actually hit things). Realistic and Sim stay manual.
func _dogfight_armed() -> bool:
	var flight := active_model()
	if flight == null:
		return false
	return flight.control_mode == FlightModel.ControlMode.DOGFIGHT \
		or flight.control_mode == FlightModel.ControlMode.ARCADE


# --- Movement profiles ---

## How the player moves: the classic stick and buttons, one swipe to go, or the
## pull-back slingshot. A separate axis from [enum FlightModel.ControlMode],
## which keeps tuning the flight numbers underneath. See [MovePilot].
enum MoveProfile { CLASSIC, SWIPE, SLINGSHOT, FPS }
const MOVE_PROFILE_NAMES := ["Classic", "Swipe", "Slingshot", "FPS"]

var move_profile: int = MoveProfile.CLASSIC
## The active profile's pilot, null for classic.
var _pilot: MovePilot = null


func set_move_profile(p: int) -> void:
	p = clampi(p, 0, MoveProfile.size() - 1)
	if _pilot != null:
		_pilot.deactivate()
		_pilot = null
	move_profile = p
	Session.move_profile = p
	match p:
		MoveProfile.SWIPE: _pilot = SwipePilot.new(self)
		MoveProfile.SLINGSHOT: _pilot = SlingshotPilot.new(self)
		MoveProfile.FPS: _pilot = FpsPilot.new(self)
	if _pilot != null and active_model() != null:
		_pilot.activate(active_model())
	if _hud != null:
		_hud.set_move_profile(p)
		_hud.show_hint("Movement: %s — %s" % [MOVE_PROFILE_NAMES[p], _move_profile_hint(p)])


func cycle_move_profile() -> void:
	set_move_profile((move_profile + 1) % MoveProfile.size())


func pilot() -> MovePilot:
	return _pilot


## Swipe and slingshot fly off the bare screen with no stick or buttons.
static func profile_is_one_thumb(p: int) -> bool:
	return p == MoveProfile.SWIPE or p == MoveProfile.SLINGSHOT


## The touch/desktop stick's deflection (screen axes, right/down positive),
## or zero while the arrow keys own it (they write it flipped).
func touch_stick() -> Vector2:
	return Vector2.ZERO if _keyboard_steering else _stick_input


func _move_profile_hint(p: int) -> String:
	match p:
		MoveProfile.SWIPE: return "swipe to fly, tap to shoot, hold to boost (longer: warp)"
		MoveProfile.SLINGSHOT: return "drag back from your ship and let go; tap to shoot, touch the ship to catch it"
		MoveProfile.FPS: return "stick moves (push further = faster, all the way = boost); drag the screen to look"
	return "stick, throttle and buttons"


## Run the profile's pilot, re-seating it when the flown ship changed (fly as,
## respawn) and parking it while the pilot is dead.
func _tick_pilot(delta: float) -> void:
	if _pilot == null or controls_locked():
		return
	var flown := active_model()
	if _player_dead or flown == null:
		return
	if _pilot.model != flown:
		if _pilot.model != null:
			_pilot.deactivate()
		_pilot.activate(flown)
	_pilot.physics_tick(delta)


## Seconds the nose-on assist takes to close most of its aim error.
const FACING_TIME := 0.22


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
	steer_nose_toward(locked_target.global_position - ship.global_position)


## Turn the active ship's nose toward world direction [param dir] (yaw/pitch
## only; roll and throttle are left alone). The same critically damped rate
## solve the nose-on assist uses, shared with the movement profiles' pilots.
func steer_nose_toward(dir: Vector3) -> void:
	var flight := active_model()
	var ship := active_ship_node()
	if flight == null or ship == null or dir.length_squared() < 0.001:
		return
	var local := ship.global_transform.basis.inverse() * dir.normalized()
	var flat := sqrt(local.x * local.x + local.z * local.z)
	# Ask for a turn *rate* proportional to the error (radians → the fraction
	# of the hull's top rate that closes it in about [constant FACING_TIME]
	# seconds), so the nose eases onto the target. A command straight from the
	# angle over-drove agile hulls past the target every tick and the ship
	# buzzed around its aim.
	var tr := maxf(flight.turn_rate, 0.05)
	# Capped by the hull's spool lag so the loop stays critically damped on a
	# slow-spooling (Realistic) hull instead of wobbling around the target.
	var gain := minf(1.0 / FACING_TIME, 0.25 / maxf(flight.turn_spool, 0.01)) / tr
	flight.command.yaw = clampf(-atan2(local.x, -local.z) * gain, -1.0, 1.0)
	flight.command.pitch = clampf(atan2(local.y, flat) * gain, -1.0, 1.0)


## How close (as a dot-product threshold, ~30° half-cone) the predictive lead
## point has to already be to dead ahead before [method _apply_aim_assist]
## nudges at all -- magnetism for an aim that is already close, not autopilot
## from any angle.
const AIM_ASSIST_CAPTURE_COS := 0.86
## At [member JuiceSettings.aim_assist_strength] == 1.0, how far each frame's
## yaw/pitch command is blended toward the lead point -- capped well short of
## 1.0 so this always reads as a nudge on top of the player's own stick, never
## a snap.
const AIM_ASSIST_MAX_PULL := 0.5


## Crosshair magnetism: when a target is locked and the predictive lead point
## (the same [TargetLeadReticle] math the HUD draws) is already roughly where
## the player is aiming, nudge yaw/pitch toward it by a small, capped amount.
## Distinct from [method _apply_target_facing]'s full nose-lock: this rides on
## top of whatever the player's own stick just wrote to [member
## FlightModel.command] instead of replacing it, so it stays "the gun found
## the target" rather than the ship flying itself. See [JuiceSettings].
func _apply_aim_assist() -> void:
	if not JuiceSettings.aim_assist_enabled or locked_target == null or not is_instance_valid(locked_target):
		return
	var flight := active_model()
	var ship := active_ship_node()
	if flight == null or ship == null:
		return
	var shooter_pos := ship.global_position
	var target_pos := locked_target.global_position
	var target_vel := Vector3.ZERO
	if locked_target is CharacterBody3D:
		target_vel = (locked_target as CharacterBody3D).velocity
	elif locked_target is RigidBody3D:
		target_vel = (locked_target as RigidBody3D).linear_velocity
	elif locked_target.get("velocity") != null:
		target_vel = locked_target.get("velocity")
	var proj_speed := 1100.0
	var sys := active_systems()
	if sys != null and sys.has_method("get_active_weapon"):
		var cur_wep: Dictionary = sys.get_active_weapon()
		proj_speed = float(cur_wep.get("speed", 1100.0))
	var lead := TargetLeadReticle.calculate_lead_position(
		shooter_pos, flight.velocity, target_pos, target_vel, proj_speed
	)
	var to_lead := lead - shooter_pos
	if to_lead.length_squared() < 0.001:
		return
	var local := ship.global_transform.basis.inverse() * to_lead.normalized()
	if -local.z < AIM_ASSIST_CAPTURE_COS:
		return
	var desired_yaw := clampf(-atan2(local.x, -local.z), -1.0, 1.0)
	var flat := sqrt(local.x * local.x + local.z * local.z)
	var desired_pitch := clampf(atan2(local.y, flat), -1.0, 1.0)
	var pull := JuiceSettings.aim_assist_strength * AIM_ASSIST_MAX_PULL
	# Blend from the pilot's own stick, not from last tick's command. The touch
	# stick only reports when it moves, so lerping the command onto itself
	# compounded every tick into full autopilot, and the next thumb twitch
	# yanked it back: the ship shook between the two aims.
	flight.command.yaw = lerpf(-_stick_input.x, desired_yaw, pull)
	flight.command.pitch = lerpf(-_stick_input.y, desired_pitch, pull)


## Keyboard flying, feeding the same [FlightModel.Command] the touch widgets do.
## Read every frame rather than event-driven, because holding a key is an
## analogue input: the longer it is down, the further the throttle moves.
##
## All axes are written every frame — including when the key is released —
## so the command snaps to zero on release. The old code only wrote when
## non-zero, which left yaw/pitch/roll stuck at their last value.
## True while a level's opening shot is playing: every control is ignored
## until the camera has landed behind the ship.
func controls_locked() -> bool:
	return camera_rig != null and camera_rig.intro_active()


func _read_keyboard(delta: float) -> void:
	if controls_locked():
		return
	var flight := active_model()
	var stick := Vector2(
		Input.get_action_strength("flight_yaw_right") - Input.get_action_strength("flight_yaw_left"),
		Input.get_action_strength("flight_pitch_down") - Input.get_action_strength("flight_pitch_up")
	)
	if not is_zero_approx(stick.x) or not is_zero_approx(stick.y):
		set_stick(Vector2(-stick.x, -stick.y))
		_keyboard_steering = true
	elif _keyboard_steering:
		set_stick(Vector2.ZERO)
		_keyboard_steering = false

	flight.command.roll = clampf(
		Input.get_action_strength("flight_roll_right")
		- Input.get_action_strength("flight_roll_left") + _button_roll, -1.0, 1.0
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

	if _player_dead:
		return

	flight.command.boost = Input.is_action_pressed("flight_boost") or _button_boost
	var sys_active := active_systems()
	if sys_active != null:
		sys_active.set_firing(Input.is_action_pressed("flight_fire") or _button_firing)


func _on_systems_state(energy: float, heat: float, _notes: String) -> void:
	_hud.set_power(energy, heat)


func _on_systems_fire_blocked(reason: String) -> void:
	if is_instance_valid(_hud):
		_hud.show_hint(reason)


func _on_model_assist_changed(_on: bool) -> void:
	if is_instance_valid(_hud):
		_hud.show_hint(_assist_hint())


## The player's own ship took a genuine physical hit (ship-to-ship, ship-to-
## rock/scenery) — see [signal FlightModel.collided]. Pulls the camera back
## briefly; [FlightModel] itself already handles the shake/squash/hitstop
## side of the same event.
##
## A hit on massive kinematic scenery (a planet, station or anomaly) gets a
## far bigger, slower-recovering pull-back than a normal ship-to-ship ram —
## see [method FlightCamera.bump_zoom]'s doc. Without this the chase camera's
## small fixed pull-back left it clipped inside the object's own geometry,
## which read as the game breaking rather than as a crash.
func _on_model_collided(closing: float, other_radius: float, other_kinematic: bool) -> void:
	if not JuiceSettings.collision_bump_zoom or camera_rig == null:
		return
	var massive := other_kinematic and other_radius > FlightCamera.MASSIVE_HIT_RADIUS
	camera_rig.bump_zoom(clampf(closing / 60.0, 0.0, 1.0), massive)


# --- The interface the HUD calls -------------------------------------------

func set_throttle(value: float) -> void:
	active_model().command.throttle = clampf(value, ThrottleLever.MIN_VALUE, 1.0)


## Screen axes to flight axes. Pushing the stick forward pitches the nose down
## and right yaws right, which is the aircraft convention and the one every
## player arrives with.
func set_stick(value: Vector2) -> void:
	_stick_input = value
	active_model().command.yaw = -value.x
	active_model().command.pitch = -value.y


## Held roll from the touch HUD's roll buttons, -1..1 (right positive). Added
## to the keyboard's roll each tick, which otherwise owns the axis.
func set_roll(value: float) -> void:
	_button_roll = clampf(value, -1.0, 1.0)


func set_firing(value: bool) -> void:
	if value and not _button_firing:
		tutorial_note("fire")
	_button_firing = value


## Pop a reaction emote off the player's own ship (see [method Whimsy.emote]) --
## a triggered, one-shot "pops out and fades" reaction rather than the old
## permanently-mounted face. Launches mostly upward off the hull with a little
## sideways scatter so repeated pops in a scrap don't all overlap on screen.
## Earliest tick (ms) the next emote may pop — see [method _emote].
var _next_emote_ms := 0


func _emote(expression: String, hold := 1.0) -> void:
	if model == null or not is_inside_tree() or not JuiceSettings.player_emotes:
		return
	if expression != "dizzy" and randf() > JuiceSettings.player_emote_chance:
		return
	# One at a time: every damage tick asks for an "ouch", and a volley stacked
	# a dozen identical icons on top of each other.
	# "dizzy" (tumbling, death) always gets through: it's the one that matters.
	var now := Time.get_ticks_msec()
	if now < _next_emote_ms and expression != "dizzy":
		return
	_next_emote_ms = now + int(hold * 700.0)
	var xform := model.global_transform
	var pos := xform.origin + xform.basis.y * _emote_height
	var side := xform.basis.x * randf_range(-0.6, 0.6)
	var launch_dir := (xform.basis.y + side).normalized()
	# Sized from the whole hull, not its height: a flat fighter used to get a
	# sub-metre icon, invisible from a chase camera 15–40 m back.
	var hull_r := camera_rig.hull_radius if camera_rig != null else 3.0
	var size := clampf(hull_r * 0.9, 1.5, 8.0) * JuiceSettings.emote_size
	if size <= 0.0:
		return
	Whimsy.emote(self, pos, expression, launch_dir, size, hold, model)


func _on_model_ooc_changed(active: bool) -> void:
	if active:
		_emote("dizzy", 1.6)


func _on_model_boost_changed(level: float) -> void:
	if level > 0.0:
		_emote("grin", 1.2)


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
	return camera_rig.is_follow_mode() and camera_rig.mode != FlightCamera.Mode.REAR


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
	# Same grace period as the initial spawn — see _near_miss_cooldown's doc.
	_near_miss_cooldown = 1.0
	# Re-derive stats from the design so damage penalties are undone.
	if view != null:
		model.configure(view.resolution.stats, systems, damage)
	# Clean up any debris nodes left over from previous impacts.
	for d in _debris_list:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	_debris_list.clear()
	_hud.sync_throttle(0.0)
	# Reset player HP on respawn
	if view != null:
		var stats := view.resolution.stats
		var base_hp := maxf(stats.get_stat("hull_hp"), 80.0) * JuiceSettings.hull_hp_mult
		player_max_hp = base_hp * JuiceSettings.player_durability_mult
		player_hp = player_max_hp
		if power_ups != null:
			power_ups.clear_effects()
		player_max_shield = _design_shield()
		player_shield = player_max_shield
	_after_respawn()
	_hud.show_hint("Back at the start point")


## Everything a respawn owes the player, whichever way it came (R, the
## popup's button, the debug respawn): alive, the popup gone, normal time, the
## view they had before the death camera, and a short grace in which nothing
## can hurt them — they used to die again the moment they reappeared.
func _after_respawn() -> void:
	_player_dead = false
	_slowmo = 1.0
	if _hud != null and _hud.has_method("hide_game_over"):
		_hud.hide_game_over()
	if camera_rig != null:
		camera_rig.set_mode(_view_before_death if _view_before_death >= 0 else FlightCamera.Mode.CHASE)
	_view_before_death = -1
	if JuiceSettings.respawn_grace > 0.0:
		_grace_until_ms = Time.get_ticks_msec() + int(JuiceSettings.respawn_grace * 1000.0)


## Whether the post-respawn grace is still running.
func in_respawn_grace() -> bool:
	return Time.get_ticks_msec() < _grace_until_ms


## The hull blinks while the grace runs, and shows solid again after.
func _update_grace_blink() -> void:
	if _grace_until_ms == 0 or view == null or view.root == null or not is_instance_valid(view.root):
		return
	var left := _grace_until_ms - Time.get_ticks_msec()
	if left <= 0:
		_grace_until_ms = 0
		view.root.visible = true
		return
	view.root.visible = (left / 120) % 2 == 0


# --- Blast outline ------------------------------------------------------------------

const HULL_OUTLINE := preload("res://modules/flight/shaders/hull_outline.gdshader")
var _outline_mat: ShaderMaterial = null
var _outline := 0.0
var _outline_on := false


## A big white blast behind the player's ship washes its silhouette out: while
## one is (on screen) round the ship and further from the camera, the hull
## gets a thin black outline ([code]hull_outline.gdshader[/code]), easing in and
## out. Attached as a per-instance overlay only while needed.
func _update_blast_outline(delta: float) -> void:
	var cam := camera_node()
	var want := 0.0
	if cam != null and view != null and model != null and not AddonVfx.recent_blasts.is_empty():
		var ship := model.get_global_transform_interpolated().origin
		if not cam.is_position_behind(ship):
			var ship_s := cam.unproject_position(ship)
			var ship_d := cam.global_position.distance_to(ship)
			var now := Time.get_ticks_msec()
			for b in AddonVfx.recent_blasts:
				var age := float(now - int(b["ms"])) / float(AddonVfx.BLAST_MEMORY_MS)
				var p: Vector3 = b["pos"]
				if age >= 1.0 or cam.is_position_behind(p):
					continue
				var d := cam.global_position.distance_to(p)
				if d < ship_d - 2.0:
					continue
				# The blast's radius in pixels at its distance.
				var px := float(b["radius"]) / maxf(d * tan(deg_to_rad(cam.fov) * 0.5), 0.01) 					* get_viewport().get_visible_rect().size.y * 0.5
				if cam.unproject_position(p).distance_to(ship_s) < px * 1.3 + 40.0:
					want = maxf(want, 1.0 - age * age)
	var dt := delta / maxf(Engine.time_scale, 0.001)
	_outline = move_toward(_outline, want, dt * (6.0 if want > _outline else 2.5))
	var on := _outline > 0.01
	if on:
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = HULL_OUTLINE
		_outline_mat.set_shader_parameter("strength", _outline)
		_outline_mat.set_shader_parameter("width_px", 4.5 * maxf(get_viewport().get_visible_rect().size.y / 720.0, 1.0))
		_outline_mat.set_shader_parameter("push_m", (camera_rig.hull_radius if camera_rig != null else 3.0) * 0.6)
	if on != _outline_on:
		_outline_on = on
		_set_hull_overlay(_outline_mat if on else null)


func _set_hull_overlay(mat: Material) -> void:
	if view == null:
		return
	for inst in view.part_meshes.values():
		if is_instance_valid(inst):
			(inst as GeometryInstance3D).material_overlay = mat
	if view.baked_mesh_instance != null and is_instance_valid(view.baked_mesh_instance):
		view.baked_mesh_instance.material_overlay = mat


## Where the player's hull was last hit, on the hull (world). The comic
## shouts ([method hit_word]) pop there.
var last_hit_point := Vector3.ZERO


## Accept damage to the player ship (called by AI weapons and collision model).
## Applies shield absorption first, then hull. Triggers game over at 0 HP.
func take_damage(amount: float, hit_point := Vector3.ZERO) -> void:
	if _player_dead:
		return
	# The debugger's god mode and damage-taken dial (see CombatStatsPanel), over
	# the player's own toughness (the hero's hull is sturdier than the AI's).
	amount *= JuiceSettings.player_damage_taken_mult / maxf(JuiceSettings.player_toughness, 0.05)
	amount /= maxf(upgrade("hull"), 0.05)
	if JuiceSettings.player_invulnerable or amount <= 0.0 or in_respawn_grace():
		return
	_last_hit_ms = Time.get_ticks_msec()
	var where := hit_point if hit_point != Vector3.ZERO else (
		model.global_position if model != null else Vector3.ZERO
	)
	# [param hit_point] can be anywhere along the line of fire (AI weapons pass
	# the shooter's own position, which gives the direction). Pull it onto the
	# hull on that side, so effects land on the ship instead of out at the
	# attacker, and never in the middle of the ship where the chase camera looks.
	if model != null:
		var hull_r := camera_rig.hull_radius if camera_rig != null else 3.0
		var off := where - model.global_position
		if off.length() > hull_r * 0.8:
			where = model.global_position + off.normalized() * hull_r * 0.8
	last_hit_point = where
	var now_ms := Time.get_ticks_msec()
	# Shield absorbs 65% of incoming damage while it holds.
	var prev_shield := player_shield
	if player_shield > 0.0:
		# The power-up's bubble soaks everything; the design's shield 65%.
		var bubble := power_ups != null and power_ups.shield_active()
		var absorbed := minf(player_shield, amount * (1.0 if bubble else 0.65))
		player_shield -= absorbed
		amount -= absorbed
		if bubble:
			power_ups.shield_hit()
		if audio != null:
			audio.play_shield_hit_sound(model.global_position if model != null else Vector3.ZERO, true)
		# A lighter flash than a hull hit: this is the shield blooming, not the
		# hull taking a bite. Dimmed and rate-limited by its own dial: one flash
		# per hit, under sustained fire, was both too much on screen and a new
		# sprite node every few frames.
		var shield_fx := JuiceSettings.shield_fx_intensity
		if shield_fx > 0.0 and PerformanceSettings.shield_ripples and now_ms >= _next_shield_fx_ms:
			AddonVfx.spawn_sprite_hit(self, where, Vector3.UP, 1.4 * shield_fx)
			_next_shield_fx_ms = now_ms + int(lerpf(600.0, 120.0, shield_fx))
	var vfx_scale := JuiceSettings.hit_vfx_scale
	if prev_shield > 0.0 and player_shield <= 0.0:
		if power_ups != null:
			power_ups.shield_broken()
		# The shield failing outright is a moment worth its own explosion, not
		# just the sprite bloom above — explosions used to be reserved
		# entirely for ship death.
		if vfx_scale > 0.0:
			AddonVfx.explosion(self, where, 1.2 * vfx_scale, false, Color("6ec6ff"))
		Juice.ring(Transform3D(Basis(), where), 3.0, Color("6ec6ff"), 0.4)
		if JuiceSettings.kill_freeze_frame:
			Juice.hitstop(0.03, 0.4)
	if amount <= 0.0:
		return
	var prev_hp := player_hp
	player_hp = maxf(player_hp - amount, 0.0)
	_emote("ouch", 0.9)
	# Addon layer on the hull hit, scaled by the damage taken, plus the library's
	# hit sound. No sound comes from the addon itself — [SpaceAudio] owns the
	# mix, and the two would just be twice as loud.
	var hit_scale := clampf(amount * 0.04, 0.6, 2.4) * vfx_scale
	# Rate-limited like the shield flash: under sustained fire, a spark per
	# tick stacked into one big additive blob in front of the camera.
	if hit_scale > 0.0 and now_ms >= _next_hit_fx_ms:
		AddonVfx.spawn(self, AddonVfx.Kind.HIT, where, Vector3.UP, hit_scale, Color("ffb347"))
		AddonVfx.spawn_sprite_hit(self, where, Vector3.UP, hit_scale)
		_next_hit_fx_ms = now_ms + 120
	if audio != null:
		audio.play_hit(where, true)
	# A single heavy hit gets its own small explosion too — see the shield
	# note above, same reasoning.
	var hit_severity := clampf(amount / maxf(player_max_hp, 1.0), 0.1, 1.0)
	# Lighter hits roll the same chance an enemy hull does (see [member
	# JuiceSettings.hit_explosions]), rate-limited so a stream is a crackle.
	var heavy_hit := amount >= player_max_hp * 0.18
	if JuiceSettings.hit_explosions and vfx_scale > 0.0 and now_ms >= _next_hit_boom_ms \
			and (heavy_hit or randf() < JuiceSettings.hit_explosion_chance):
		_next_hit_boom_ms = now_ms + (90 if heavy_hit else 260)
		AddonVfx.explosion(self, where, (0.9 if heavy_hit else 0.4) * vfx_scale * JuiceSettings.hit_explosion_size,
			false, Color("ff8844"))
	# A real freeze-frame on any hit past the Juice panel's threshold. It used
	# to be a 60 ms slow-down on heavy hits only, which never read as a freeze.
	# Rate-limited so a volley is one beat, not a stutter.
	if JuiceSettings.kill_freeze_frame and JuiceSettings.freeze_on_player_hit \
			and amount >= player_max_hp * JuiceSettings.freeze_hit_threshold \
			and now_ms >= _next_hit_freeze_ms and player_hp > 0.0:
		_next_hit_freeze_ms = now_ms + 350
		Juice.freeze(JuiceSettings.freeze_hit_ms / 1000.0, JuiceSettings.freeze_depth)
	# Being shot is a camera event too, not just a physical ram -- see [method
	# _on_model_collided]. Reuses the same bump-zoom trauma model so a sustained
	# volley keeps the camera pulled back for as long as the hits keep landing
	# (each one just re-raises the same decaying target) and eases back in on
	# its own once they stop.
	if JuiceSettings.collision_bump_zoom and camera_rig != null:
		camera_rig.bump_zoom(lerpf(0.3, 1.0, hit_severity))
	# Weapon-hit juice: squash, knockback and screen shake — distinct from
	# FlightModel._on_phys_impacted's own set, which only fires for a genuine
	# physical collision, never a weapon hit.
	if model != null:
		if JuiceSettings.hit_squash_stretch:
			model.squash_from_weapon_hit(where - model.global_position, hit_severity)
		if JuiceSettings.hit_knockback:
			var push_dir := (model.global_position - where)
			if push_dir.length_squared() < 0.01:
				push_dir = -model.global_transform.basis.z
			model.apply_knockback(push_dir, clampf(amount * 0.15, 1.0, 18.0))
	if JuiceSettings.hit_screen_shake:
		Juice.shake(clampf(amount * 0.01, 0.05, 0.5) * JuiceSettings.hit_shake_strength, 0.25)
	if player_hp <= 0.0 and prev_hp > 0.0:
		game_over()


## Trigger the game-over sequence: scatter all parts, slow-mo, show modal.
func game_over() -> void:
	if _player_dead:
		return
	_player_dead = true
	model.halt()
	model.clear_phys_world()
	_emote("dizzy", 1.4)
	Whimsy.confetti(self, model.global_position, 1.6)

	# Scatter every remaining part from the player ship
	if damage != null:
		var broken_parts := damage.break_all_parts()
		for bp in broken_parts:
			_on_part_broken(bp, [])

	# Dramatic juice
	var xform := model.global_transform
	Juice.ring(xform, 5.0, Color("ff5500"), 0.6)
	Juice.burst(BurstPresets.Preset.RING_SPARK, xform, 3.0, Color("ff8800"))
	Juice.burst(BurstPresets.Preset.SPARKS, xform, 3.0, Color("ffcc44"))
	Juice.burst(BurstPresets.Preset.EMBERS, xform, 2.5)
	Juice.burst(BurstPresets.Preset.DEBRIS, xform, 2.0)
	Juice.burst(BurstPresets.Preset.VAPOUR, xform, 2.0)
	Juice.light_pop(model.global_position, Color("ff8844"), 20.0, 0.6)
	Juice.shake(1.5)
	Juice.flash(Color("ff6600"), 0.6, 0.4)
	if audio != null:
		audio.play_explosion(model.global_position, true)
	# The addon's heaviest effect on top of the debris scatter. Sound stays with
	# SpaceAudio just above, so this only adds the visuals. Ship death should
	# read as the single biggest moment in a fight — much bigger than any
	# in-combat hit explosion above.
	var death_scale := JuiceSettings.kill_explosion_size
	if death_scale > 0.0:
		AddonVfx.explosion(self, model.global_position, 6.0 * death_scale, true, Color("ff8844"))
	# A chance (the Juice panel's dial) of a bigger secondary blast a beat
	# later — real ships breaking apart don't all detonate identically.
	if JuiceSettings.enemy_death_random_explosion and death_scale > 0.0 \
			and randf() < JuiceSettings.kill_explosion_chance:
		AddonVfx.nuke(self, model.global_position, 5.0 * death_scale, Color("ffaa44"))
	# ExplosionRegistry: player ship death gets the assigned SLOT_SHIP_DEATH effect.
	# This stacks on top of the Juice / AddonVfx layer rather than replacing it,
	# so the best-of-both-worlds result is always used.
	var _reg := ExplosionRegistry.new()
	_reg.spawn_event(self, ExplosionRegistry.SLOT_SHIP_DEATH,
		model.global_position, Vector3.UP, 1.5)

	if JuiceSettings.kill_freeze_frame and JuiceSettings.freeze_on_kill:
		Juice.freeze(JuiceSettings.freeze_kill_ms / 1000.0, JuiceSettings.freeze_depth)
	if camera_rig != null:
		camera_rig.cancel_kill_cam()

	# Slow motion
	_slowmo = 0.25

	# Switch to a death orbiting camera, remembering the view to come back to.
	if camera_rig != null:
		if camera_rig.mode != FlightCamera.Mode.FREE:
			_view_before_death = camera_rig.mode
		camera_rig.set_mode(FlightCamera.Mode.FREE)
		camera_rig.recentre()

	# After a brief slow-mo delay, restore time and show Game Over modal
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.4)
	tw.tween_callback(_show_game_over_if_dead)


## The game-over popup, unless the player already respawned during the
## slow-mo beat — it used to pop up over a live ship and stay there.
func _show_game_over_if_dead() -> void:
	if not _player_dead:
		return
	_slowmo = 1.0
	if _hud != null and _hud.has_method("show_game_over"):
		_hud.show_game_over()


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
	Session.save_to_disk()


## Apply a new planet spacing scale. Callers are expected to restart after.
func set_planet_spacing(value: float) -> void:
	Session.planet_spacing = clampf(value, 0.5, 5.0)
	Session.save_to_disk()


# --- Kill cam ---------------------------------------------------------------------

## Kills the player chains close together (x2, x3 …); see [ComboChain].
var combo := ComboChain.new()
## The floating pick-ups kills drop and their timed effects ([PowerUps]).
var power_ups: PowerUps = null
## The short interactive tutorial ([FlightTutorial]), while it runs.
var tutorial: FlightTutorial = null

## Show the speed as a meter up to [param max_mps] on the mobile HUD (0 =
## the normal number). The endless runner uses it.
func set_speed_meter(max_mps: float) -> void:
	if _hud != null:
		_hud.set_speed_meter(max_mps)


var _next_clash_word_ms := 0


## A yeet-combat ram between the player and an AI ship at [param point]
## ([method YeetDash.clash_player_wins]): [param won] means the player came in
## faster and took nothing. A win gets its own shout where it happened (a
## loss is a hull hit, which already pops one).
func yeet_clash(won: bool, point: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if not won or now < _next_clash_word_ms or not JuiceSettings.world_hit_words:
		return
	# One shout per clash: the contact can report on a few ticks running.
	_next_clash_word_ms = now + 250
	hit_word(["BAM!", "WHAM!", "KAPOW!", "YEET!"].pick_random(), point, Color("46ff9b"), 1.25)


# --- Planet pinball ------------------------------------------------------------------

## Planets knocked off their spot: collider node → {home, vel, grav}.
var _knocked := {}
## How fast a knocked planet eases home (spring, per s²) and loses speed (per s).
const KNOCK_SPRING := 0.35
const KNOCK_DAMP := 1.1


## The player's ship rammed a static body at [param closing] m/s. A planet
## ([PhysBody] on one of its collider nodes): hard enough for its size and the
## hull's toughness ([member JuiceSettings.planet_smash_speed]) and it shatters
## — returns true, the hull is spared the crash; fast enough to matter
## ([member JuiceSettings.planet_knock_speed]) and it is knocked off its spot
## like a pinball bumper, drifting home again (the hull still takes the crash).
func planet_ram(other: PhysBody, point: Vector3, closing: float) -> bool:
	var holder := other.node as Node3D
	var planet := _planet_in(holder)
	if planet == null or planet.has_meta("shattered") or model == null:
		return false
	var scale_k := sqrt(maxf(other.radius, 1.0) / 1000.0)
	if closing >= planet_smash_need(other.radius):
		_knocked.erase(holder)
		hit_word("KABOOM!", point, Color("ffe23d"), 1.8)
		if systems != null:
			systems._destroy_planet(planet, point)
		else:
			on_planet_destroyed(planet)
		return true
	if closing >= JuiceSettings.planet_knock_speed and JuiceSettings.planet_knock > 0.0:
		var e: Dictionary = _knocked.get(holder, {})
		if e.is_empty():
			var grav: GravitySystem.GravityBody = null
			if gravity != null:
				var near := gravity.nearest_body(holder.global_position)
				if near != null and near.position.distance_to(holder.global_position) < other.radius * 0.5:
					grav = near
			e = {"home": holder.global_position, "vel": Vector3.ZERO, "grav": grav, "radius": other.radius}
			_knocked[holder] = e
		var push := (holder.global_position - model.global_position).normalized()
		# Speed over what knocks it, against the planet's size: a moon flies, a
		# giant budges.
		var kick := (closing - JuiceSettings.planet_knock_speed * 0.5) * 6.0 * JuiceSettings.planet_knock / scale_k
		e["vel"] = (e["vel"] as Vector3) + push * kick
		hit_word(["BOING!", "BONK!", "YEET!"].pick_random(), point, Color("33d6ff"), 1.4)
	return false


## The ram speed (m/s) that shatters a planet of [param radius] with the
## player's hull: [member JuiceSettings.planet_smash_speed] for a 1 km planet
## and an average hull, more for a bigger planet, less for a tougher hull —
## within reason (a hull with a hundred thousand hit points still has to be
## going some; toughness counts ×0.5–2.5).
func planet_smash_need(radius: float) -> float:
	var tough := clampf(sqrt(model.ram_toughness()), 0.5, 2.5) if model != null else 1.0
	return JuiceSettings.planet_smash_speed * sqrt(maxf(radius, 1.0) / 1000.0) / tough


## The [Planet] a collider node stands for: itself, or one it holds (Tarn IV
## is a pivot carrying the planet and its moon).
func _planet_in(node: Node3D) -> Planet:
	if node == null or not is_instance_valid(node):
		return null
	if node is Planet:
		return node as Planet
	for c in node.get_children():
		if c is Planet:
			return c as Planet
	return null


## Knocked planets fly off, slow, and ease back home (their collider moves with
## the node; their gravity well is carried along).
func _update_knocked_planets(delta: float) -> void:
	if _knocked.is_empty():
		return
	for holder: Node3D in _knocked.keys():
		if not is_instance_valid(holder):
			_knocked.erase(holder)
			continue
		var e: Dictionary = _knocked[holder]
		var home: Vector3 = e["home"]
		var vel: Vector3 = e["vel"]
		var pos := holder.global_position
		vel += (home - pos) * KNOCK_SPRING * delta
		vel *= exp(-KNOCK_DAMP * delta)
		pos += vel * delta
		holder.global_position = pos
		var grav: GravitySystem.GravityBody = e["grav"]
		if grav != null:
			grav.position = pos
		e["vel"] = vel
		if pos.distance_to(home) < float(e["radius"]) * 0.002 and vel.length() < 1.0:
			holder.global_position = home
			if grav != null:
				grav.position = home
			_knocked.erase(holder)


## A ship in view just launched a yeet dash: shout it where it starts.
func _on_ai_ship_yeeted(ship: AiShip) -> void:
	if JuiceSettings.world_hit_words and is_instance_valid(ship):
		hit_word("YEET!", ship.global_position, Color("ff3fa4"), 1.1)


## (Re)start the interactive tutorial ([FlightTutorial]) for the current
## movement profile.
func start_tutorial() -> void:
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.queue_free()
	if _hud == null:
		return
	tutorial = FlightTutorial.new()
	tutorial.setup(self)
	_hud.add_banner(tutorial)


## Tell the tutorial the player just did [param event] (see [method FlightTutorial.note]).
func tutorial_note(event: String) -> void:
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.note(event)


## A ship popped "!" or "?" ([signal AiShip.marked]): a comic speech bubble
## rides over it.
func _on_ai_ship_marked(ship: AiShip, mark: String) -> void:
	if _hud == null or not is_instance_valid(ship):
		return
	var col := Color("ff3b3b") if mark == "!" else Color("2f8dff")
	_hud.mark_word(mark, ship, ship.marker_height(1.0), col)


## A Persona-style callout from the player's own ship ([PlayerCallouts]):
## part lost, power-up taken, shield down, hull critical …
## The moment-stopping headline (see [BigNotice]): a power-up, a planet.
func big_notice(word: String, sub: String, col: Color, hold := 1.2) -> void:
	if _big_notice == null:
		_big_notice = BigNotice.new()
		_big_notice.name = "BigNotice"
		add_child(_big_notice)
	_big_notice.show_notice(word, sub, col, hold)


func player_callout(text: String, col := Color("ff2a4a")) -> void:
	if _hud != null and JuiceSettings.player_callouts:
		_hud.callout(text, col)


## A comic shout (POW!, x3! …) popped at [param world_pos] by whichever HUD
## is up (see [method FlightHud.hit_word]).
func hit_word(word: String, world_pos: Vector3, col: Color, scale := 1.0) -> void:
	if _hud != null:
		_hud.hit_word(word, world_pos, col, scale)


## Any roster ship died. A player kill may get the kill cam: the game pauses
## under the camera while it swoops onto the wreck, then comes back. See
## [method FlightCamera.start_kill_cam] and [member JuiceSettings.kill_cam].
func _on_ai_ship_destroyed(ship: AiShip) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.killed_by_player:
		return
	if power_ups != null:
		power_ups.maybe_drop(ship.global_position)
	tutorial_note("kill")
	var chain := combo.note_kill(ship.global_position)
	if chain >= 2 and JuiceSettings.combo_counter:
		hit_word("x%d!" % chain, ship.global_position, Color("ffe23d"), 1.0 + minf(float(chain) * 0.12, 0.8))
	if not JuiceSettings.kill_cam or JuiceSettings.reduce_motion or _player_dead:
		return
	if camera_rig == null or controlled_ai == ship:
		return
	var now := Time.get_ticks_msec()
	if now < _next_kill_cam_ms or randf() > JuiceSettings.kill_cam_chance:
		return
	var radius := 4.0
	if ship._view != null:
		radius = maxf(ship._view.aabb.size.length() * 0.5, 1.0)
	# Held on the spot it blew up (no node to follow): the dead ship's node
	# drifts on after its parts scatter, and following it swooped onto loose
	# wreckage instead of the blast.
	if camera_rig.start_kill_cam(null, ship.global_position, radius):
		var total := JuiceSettings.kill_cam_blend * (1.0 + JuiceSettings.kill_cam_ease_in) + JuiceSettings.kill_cam_hold
		_next_kill_cam_ms = now + int((total + JuiceSettings.kill_cam_cooldown) * 1000.0)


## The kill cam's share of [member Engine.time_scale]: eases down to [member
## JuiceSettings.kill_cam_time_scale] as the camera swoops in and back up as
## it returns. Never quite zero (see [constant JuiceRuntime.FREEZE_FLOOR]).
func _kill_cam_factor() -> float:
	if camera_rig == null or not camera_rig.kill_cam_active():
		return 1.0
	var paused := maxf(JuiceSettings.kill_cam_time_scale, JuiceRuntime.FREEZE_FLOOR)
	return lerpf(1.0, paused, camera_rig.kill_cam_weight())


# --- Player & enemy stats (the 🧪 Stats debugger panel) -----------------------

## Hull and shield regeneration from the debugger's dials, per real second of
## game time. The shield waits out its delay after the last hit.
func _regen_player(delta: float) -> void:
	if _player_dead:
		return
	if JuiceSettings.player_hp_regen > 0.0 and player_hp < player_max_hp:
		player_hp = minf(player_hp + player_max_hp * JuiceSettings.player_hp_regen * 0.01 * delta, player_max_hp)
	if JuiceSettings.player_shield_regen > 0.0 and player_shield < player_max_shield:
		var since := (Time.get_ticks_msec() - _last_hit_ms) / 1000.0
		if since >= JuiceSettings.player_shield_regen_delay:
			player_shield = minf(
				player_shield + player_max_shield * JuiceSettings.player_shield_regen * 0.01 * delta,
				player_max_shield
			)


## Re-derive the player's max hull and shield from the design and the current
## dials, keeping the same fraction of each that the ship had.
func refresh_player_max_stats() -> void:
	if view == null:
		return
	var stats := view.resolution.stats
	var hp_frac := player_hp / maxf(player_max_hp, 1.0)
	var sh_frac := player_shield / maxf(player_max_shield, 1.0) if player_max_shield > 0.0 else 1.0
	player_max_hp = maxf(stats.get_stat("hull_hp"), 80.0) * JuiceSettings.hull_hp_mult \
		* JuiceSettings.player_durability_mult
	if power_ups != null and power_ups.shield_active():
		# The power-up's bubble owns the shield while it lasts.
		if not _player_dead:
			player_hp = player_max_hp * hp_frac
		return
	player_max_shield = _design_shield()
	if not _player_dead:
		player_hp = player_max_hp * hp_frac
	player_shield = player_max_shield * sh_frac


## The ship design's own shield, if [member JuiceSettings.design_shields] is
## on; otherwise none — shields come from the power-up only.
func _design_shield() -> float:
	if not JuiceSettings.design_shields or view == null:
		return 0.0
	return maxf(view.resolution.stats.get_stat("shield_hp"), 0.0) * JuiceSettings.player_shield_mult


## The shield bubble ended: back to the design's shield (usually none).
func restore_design_shield() -> void:
	player_max_shield = _design_shield()
	player_shield = player_max_shield


## Set the player's hull to [param fraction] of max (0 kills the ship).
func set_player_hp_fraction(fraction: float) -> void:
	if _player_dead:
		return
	player_hp = player_max_hp * clampf(fraction, 0.0, 1.0)
	if player_hp <= 0.0:
		game_over()


func refill_player_shield() -> void:
	player_shield = player_max_shield


## Live AI ships, for the debugger.
func live_enemies() -> Array[AiShip]:
	var out: Array[AiShip] = []
	if _ai_spawner == null:
		return out
	for ship in _ai_spawner._ships:
		if is_instance_valid(ship) and ship._alive:
			out.append(ship)
	return out


## Rescale every live AI ship's hull after the enemy-HP dial moved from
## [param old_mult] to the current value, keeping each ship's fraction.
func rescale_enemy_hp(old_mult: float) -> void:
	var ratio := JuiceSettings.enemy_hp_mult / maxf(old_mult, 0.01)
	for ship in live_enemies():
		ship.max_hp *= ratio
		ship.hp *= ratio


## Deal [param fraction] of each live AI ship's max hull as damage — not the
## player's hit, so no kill cam.
func damage_all_enemies(fraction: float) -> void:
	for ship in live_enemies():
		ship.take_damage(ship.max_hp * fraction)


func heal_all_enemies() -> void:
	for ship in live_enemies():
		ship.hp = ship.max_hp


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
	ship.pilot_host = self
	ship.stop_yeet()
	ship.model.frame_velocity = Vector3.ZERO
	if ship.systems != null:
		ship.systems.player_flown = true
	# The piloted hull stands in for the player: the AI hunts it (see
	# [method AiSpawner._find_player_node]) and team checks read its meta.
	ship.model.set_meta("team", _player_team)
	if camera_rig != null:
		camera_rig.adopt(ship, ship.model, ship._view)
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if _hud != null:
		_hud.show_hint("Piloting %s — L to leave control" % ship.preset_name)
		if ship.systems != null and _hud.has_method("update_weapon_badge"):
			_hud.update_weapon_badge(ship.systems.get_active_weapon())


## Give control back to the player's own ship. A ship spawned just to be
## flown ([method fly_as]) goes away with it.
func leave_control() -> void:
	if controlled_ai != null and is_instance_valid(controlled_ai):
		controlled_ai._ai_paused = false
		controlled_ai.pilot_host = null
		if controlled_ai.systems != null:
			controlled_ai.systems.player_flown = false
		if controlled_ai.is_pilot_vessel:
			controlled_ai.teardown()
	controlled_ai = null
	if camera_rig != null and model != null:
		camera_rig.adopt(model, model, view)
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if _hud != null:
		_hud.show_hint("Back in your own ship")
		if systems != null and _hud.has_method("update_weapon_badge"):
			_hud.update_weapon_badge(systems.get_active_weapon())


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
		best.mark_engaged()
		_hud.show_hint("Locked: %s" % best.preset_name)
	else:
		_hud.show_hint("No target to lock")


# --- Fly as another ship -------------------------------------------------------

## Hull sizes the flight test's "Fly as" picker offers, as a multiplier on the
## normal ship size — from a dart to something the size of a station.
const FLY_AS_SIZES := {
	"Tiny (0.35x)": 0.35,
	"Small (0.6x)": 0.6,
	"Normal (1x)": 1.0,
	"Large (2.5x)": 2.5,
	"Hauler (5x)": 5.0,
	"Capital (12x)": 12.0,
	"Titan (24x)": 24.0,
}


## Spawn a random ship of [param size_mult] alongside the player's, armed with
## weapon [param weapon_index] (-1 = whatever fits its size) and firing style
## [param style] ("" = the plain weapon), and take control of it — to feel how
## other ships fly and fight. Handing control back ([method leave_control])
## frees it and returns to the player's own ship.
func fly_as(size_mult: float, weapon_index := -1, style := "") -> AiShip:
	var spawner := ensure_ai_spawner()
	var host := active_ship_node()
	if spawner == null or host == null:
		return null
	var ship := spawner.spawn_pilot_vessel(host.global_transform, size_mult)
	if ship == null:
		return null
	if weapon_index >= 0 and ship.systems != null:
		ship.systems.set_weapon_index(weapon_index)
	if style != "":
		ship.reroll_fire_pattern(style)
	else:
		ship.fire_pattern = {}
		if ship.systems != null:
			ship.systems.fire_pattern = {}
	ship.team_id = _player_team
	# Built as an enemy, it had an enemy's hit points; flown by the player it
	# gets the player's own hull, scaled a little with its size.
	ship.max_hp = maxf(ship.max_hp, player_max_hp * clampf(sqrt(size_mult), 0.6, 4.0))
	ship.hp = ship.max_hp
	take_control(ship)
	if _hud != null:
		_hud.show_hint("Flying a %s — L to hand it back" % _size_label(size_mult))
	return ship


func _size_label(size_mult: float) -> String:
	for label: String in FLY_AS_SIZES.keys():
		if is_equal_approx(float(FLY_AS_SIZES[label]), size_mult):
			return label
	return "%.2fx ship" % size_mult


# --- Enemy fire on the player's hull -----------------------------------------

## An enemy shot has struck the player's own hull (called by [SystemsSim]
## when a real projectile or beam lands, and by [AiShip]'s dice fallback).
## The player-favouring rules live here: no friendly fire, and a ship the
## player cannot see only rarely lands a hit (see [member
## JuiceSettings.cheat_offscreen_mercy]). Returns whether it counted.
func take_enemy_fire(amount: float, hit_point: Vector3, shooter: SystemsSim) -> bool:
	if shooter != null and shooter == active_systems():
		return false
	var ship: AiShip = shooter.get("_root") as AiShip if shooter != null else null
	if ship != null and _player_team != 0 and ship.team_id == _player_team:
		return false
	# Real shots were already held back at the gun (see [method
	# AiShip.fire_gate]); the dice fallback has no gun to hold, so it asks here.
	if ship != null and not JuiceSettings.ai_real_projectiles and not ship.fire_gate():
		return false
	if ship != null:
		ship.note_hit_player()
	take_damage(amount * JuiceSettings.enemy_damage_mult, hit_point)
	return true


## A ship the player is flying ([member AiShip.pilot_host]) is hit: how much
## of [param amount] it takes. The player's own rules — god mode, the respawn
## grace, no friendly fire, and an enemy's shots at their tuned strength — so a
## borrowed hull is not shot out from under them in a few seconds.
func pilot_damage(ship: AiShip, amount: float, source: Object) -> float:
	if JuiceSettings.player_invulnerable or in_respawn_grace():
		return 0.0
	var shooter := source as SystemsSim
	if shooter != null:
		if shooter == ship.systems:
			return 0.0
		var s_ship := shooter.get("_root") as AiShip
		if s_ship != null:
			if _player_team != 0 and s_ship.team_id == _player_team:
				return 0.0
			s_ship.note_hit_player()
		amount *= JuiceSettings.enemy_shot_damage_scale
	_last_hit_ms = Time.get_ticks_msec()
	return amount * JuiceSettings.enemy_damage_mult * JuiceSettings.player_damage_taken_mult 		/ maxf(JuiceSettings.player_toughness, 0.05) / maxf(upgrade("hull"), 0.05)


# --- Interaction markers ---------------------------------------------------------

var _interaction_markers: InteractionMarkers = null


func _marker_ships() -> Array[AiShip]:
	if _ai_spawner == null or not is_instance_valid(_ai_spawner):
		return []
	return _ai_spawner.ships()


# --- Satellites + time-scale --------------------------------------------------

## The global time scale (×1/×2/×4/×10), re-applied every frame so Juice hitstop
## cannot wipe it. For watching satellites orbit.
var _time_scale := 1.0
## Death slow-mo multiplier on top of [member _time_scale] (1.0 = none).
var _slowmo := 1.0
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


## Spawned large-craft structures (motherships, ring stations, etc — see
## [LargeCraftGenerator]), tracked so they can be cleared together. A
## one-directional dependency the same way [constant Location.GENERATED_SYSTEM]
## depends on [SolarSystemGenerator]: large_craft_gen never reaches back into
## flight.
var _large_craft: Array[LargeCraftGenerator] = []
const LARGE_CRAFT_SPAWN_DIST := 300.0

## One spawned large craft's circular orbit around whichever [GravityBody]
## dominates the spot it was dropped at — computed once at spawn from the
## same [method GravitySystem.orbit_velocity]/tangent math [method _ready]
## already uses to put the player in orbit, then just walked forward each
## frame. Not real gravity integration (the craft has no mass to the physics
## layer) — a stable circular rail is enough for "yes, it visibly orbits the
## planet" and costs nothing at any structure scale.
class _CraftOrbit extends RefCounted:
	var gen: LargeCraftGenerator
	var dominant: GravitySystem.GravityBody
	var radius: float
	var y_offset: float
	var angle: float
	var angular_speed: float

var _craft_orbits: Array[_CraftOrbit] = []

## Every [constant LargeCraftGenerator.RANDOMIZABLE] dial gets multiplied by a
## random factor in this range at spawn, so mashing "Spawn: X" a few times
## doesn't drop identical-looking structures — full manual control over the
## exact dials stays the lab's job.
const CRAFT_JITTER_RANGE := Vector2(0.75, 1.4)

## Debug size presets for the flight-test spawner (Large craft menu), keyed
## against [constant SpaceScene.PLANET_RADIUS] (1400m) and
## [constant SolarSystemGenerator.STAR_RADIUS] (220m, ×10 max mult = 2200m) —
## the two real yardsticks this game already has for "how big is that". These
## set [member LargeCraftGenerator.scale_mult] directly (overriding its own
## dial jitter, see [method spawn_large_craft]) rather than leaving size to
## chance — a debug spawner should hit the size you asked for.
enum CraftSize { SMALL, DEFAULT, PLANET, SUN }
const CRAFT_SIZE_LABELS := {
	CraftSize.SMALL: "Small (frigate-scale)",
	CraftSize.DEFAULT: "Default (~quarter-planet)",
	CraftSize.PLANET: "Planet-sized",
	CraftSize.SUN: "Sun-sized",
}
## scale_mult targets — unscaled default extent is ~85m, so these land at
## roughly 130m / 425m / 1400m / 3000m.
const CRAFT_SIZE_SCALE := {
	CraftSize.SMALL: 1.5,
	CraftSize.DEFAULT: 5.0,
	CraftSize.PLANET: 16.5,
	CraftSize.SUN: 35.0,
}
## Selected in the Large craft HUD popup; read by [method spawn_large_craft].
var craft_size_preset: int = CraftSize.DEFAULT

## Hard floors for [method spawn_large_craft] to top up to after generating —
## [constant CRAFT_SIZE_SCALE] targets an *average* extent, but the per-dial
## jitter that runs first can hand back a smaller-than-usual unscaled
## structure before scale_mult is even applied, and "quarter-planet" was an
## explicit floor from the user ("these should be planet-sized... or at
## LEAST 1/4 of a normal planet"), not a rough average. [constant CraftSize.SMALL]
## has no entry — it's deliberately allowed to vary small.
const CRAFT_SIZE_FLOOR := {
	CraftSize.DEFAULT: 350.0,   # 1/4 of SpaceScene.PLANET_RADIUS (1400m)
	CraftSize.PLANET: 1400.0,  # SpaceScene.PLANET_RADIUS
	CraftSize.SUN: 2200.0,     # SolarSystemGenerator.STAR_RADIUS * its own 10x max mult
}

## Spawns a [LargeCraftGenerator] of the given archetype a short distance
## ahead of whichever ship the player is flying, lightly jittering its dials
## off the generator's own (deliberately large) defaults — full dial control
## stays the lab's job; this is a quick "drop one in and go fly around it"
## test spawn, the same scope as [method spawn_satellite]. Orbits the nearest
## gravitating body if one dominates the spawn point (see [_CraftOrbit]).
func spawn_large_craft(archetype: int) -> void:
	var ship := active_ship_node()
	if ship == null:
		return
	var gen := LargeCraftGenerator.new()
	gen.name = "LargeCraft_%d" % _large_craft.size()
	gen.archetype = archetype
	gen.craft_seed = randi()
	# Jitter before add_child: the generator's own _ready() auto-generates
	# once it enters the tree, so dials must land before that or it builds
	# twice (wasted work at this scale — hundreds of parts).
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.craft_seed
	for entry: Dictionary in LargeCraftGenerator.RANDOMIZABLE:
		var key: String = entry["key"]
		var jittered := float(gen.get(key)) * rng.randf_range(CRAFT_JITTER_RANGE.x, CRAFT_JITTER_RANGE.y)
		var v := clampf(jittered, float(entry["min"]), float(entry["max"]))
		gen.set(key, roundi(v) if bool(entry.get("is_int", false)) else v)
	# The size preset overrides whatever the loop above just jittered
	# scale_mult to — a debug spawner should reliably land on the size you
	# picked, not "probably somewhere near it".
	gen.scale_mult = float(CRAFT_SIZE_SCALE[craft_size_preset]) * rng.randf_range(0.85, 1.15)
	add_child(gen)

	# Top up to this preset's floor: the per-dial jitter above can hand back
	# a smaller-than-usual unscaled structure before scale_mult even applies,
	# and "quarter-planet" is a floor the user asked for explicitly, not an
	# average to land near.
	if CRAFT_SIZE_FLOOR.has(craft_size_preset):
		var min_extent: float = CRAFT_SIZE_FLOOR[craft_size_preset]
		var current_extent := gen.approx_extent()
		if current_extent < min_extent:
			gen.scale *= (min_extent / current_extent)

	# Spawn distance and fan-out spacing both scale with the structure's own
	# size — a fixed 300 m was fine for the old modest defaults but drops the
	# ship inside (or right on top of) anything built at mega-structure scale.
	var extent := gen.approx_extent()
	var spawn_dist := maxf(LARGE_CRAFT_SPAWN_DIST, extent * 1.8)
	var fwd := -ship.global_transform.basis.z
	var side := ship.global_transform.basis.x
	# Fan spawns out sideways so mashing several "Spawn: X" buttons in a row
	# (testing archetypes back to back) doesn't stack them on top of each other.
	var fan := side * float(_large_craft.size()) * spawn_dist * 0.9
	gen.global_position = ship.global_position + fwd * spawn_dist + fan
	_large_craft.append(gen)
	_register_large_craft_collision(gen)
	# Ships move under their own power; everything else (stations, gates,
	# towers) is a fixture that at most orbits whatever it was dropped near.
	if archetype == LargeCraftGenerator.Archetype.DREADNOUGHT:
		_place_large_craft_patrol(gen)
	else:
		_place_large_craft_orbit(gen)
	if _hud != null:
		var label: String = LargeCraftGenerator.ARCHETYPE_NAMES.get(archetype, "Large craft")
		_hud.show_hint("Spawned %s — %d parts, %d dock pads" % [label, gen.part_count(), gen.dock_pad_count()])


## Debug bulk-spawn: drops [param count] large craft of random archetypes at
## the current [member craft_size_preset] in one call, for quickly filling a
## test flight with megastructures instead of clicking "Spawn: X" repeatedly.
func spawn_large_craft_mix(count: int) -> void:
	var kinds: Array = LargeCraftGenerator.ARCHETYPE_NAMES.keys()
	for i in count:
		spawn_large_craft(kinds[randi() % kinds.size()])


## Every [PhysBody] registered for a spawned large craft's structural parts
## (see [method LargeCraftGenerator.get_collision_spheres]), keyed by the
## generator, so they can be torn down again in [method clear_large_craft]
## or when a shot-off part frees its own body in [method
## _on_large_craft_part_detached].
var _craft_collision_bodies: Dictionary = {}  ## LargeCraftGenerator -> Array[PhysBody]

## Registers one kinematic [PhysBody] per structural part so the player's
## ship actually collides with a spawned large craft instead of flying
## straight through it — [PhysWorld] is the flight model's own hand-rolled
## collision layer, entirely separate from Godot's native physics that
## [LargeCraftGenerator]'s [StaticBody3D] parts already sit in (which is why
## [method LargeCraftGenerator.shoot_at]'s raycast and [DockingPad]'s Area3D
## overlap already worked without this — those go through the engine's own
## physics server, not [PhysWorld]). Only [constant Location.SPACE] builds a
## [PhysWorld] at all (see [method _build_phys_world]); elsewhere this is a
## a no-op, same as every other collider in the scene.
##
## Each body gets the part's fitted sphere chain rather than one enclosing ball,
## so a long hull segment is collided with along its actual length — see
## [method LargeCraftGenerator.get_collision_spheres] for what that replaced.
func _register_large_craft_collision(gen: LargeCraftGenerator) -> void:
	if phys_world == null:
		return
	var made: Array[PhysBody] = []
	for entry: Dictionary in gen.get_collision_spheres():
		# Radius is a placeholder: set_hull re-derives the enclosing radius from the
		# compound it is handed.
		var body := PhysBody.new(1.0, 1.0)
		body.node = entry["node"]
		var hull: Array[Dictionary] = entry.get("hull", [])
		if hull.is_empty():
			body.radius = float(entry.get("radius", 1.0))
		else:
			body.set_hull(hull)
		body.layer = PhysBody.Layer.STATIC
		body.kinematic = true
		phys_world.add(body)
		made.append(body)
	_craft_collision_bodies[gen] = made


## When a structural part is shot off, [method LargeCraftGenerator._detach_part]
## frees its original [StaticBody3D] and [signal LargeCraftGenerator.part_detached]
## hands back the *new* debris [RigidBody3D] instead — there is no direct way
## to match that signal back to which [PhysBody] just lost its node. Simplest
## correct fix: sweep for staleness instead of trying to catch the exact
## event. Cheap (a handful of validity checks per spawned craft) and correct
## regardless of exactly when Godot's deferred deletion actually runs.
func _prune_large_craft_collision() -> void:
	if phys_world == null or _craft_collision_bodies.is_empty():
		return
	var any_removed := false
	for gen in _craft_collision_bodies.keys():
		var bodies: Array = _craft_collision_bodies[gen]
		var still: Array = []
		for body: PhysBody in bodies:
			if is_instance_valid(body.node):
				still.append(body)
			else:
				phys_world.remove(body)
				any_removed = true
		_craft_collision_bodies[gen] = still
	if any_removed:
		phys_world.mark_scenery_dirty()


## If a [GravityBody] dominates [param gen]'s spawn position, put it into a
## circular orbit around that body at its current distance and height instead
## of leaving it parked in open space — the original design called for large
## craft that can "just orbit", and a mega-structure dropped near a planet
## reading as motionless was the actual bug report.
func _place_large_craft_orbit(gen: LargeCraftGenerator) -> void:
	if gravity == null or gravity.mode == GravitySystem.GravityMode.OFF:
		return
	var dominant := gravity.find_dominant_body(gen.global_position)
	if dominant == null:
		return
	var to_craft := gen.global_position - dominant.position
	var flat := Vector3(to_craft.x, 0.0, to_craft.z)
	if flat.length() < 1.0:
		return
	var orbit := _CraftOrbit.new()
	orbit.gen = gen
	orbit.dominant = dominant
	orbit.radius = flat.length()
	orbit.y_offset = to_craft.y
	orbit.angle = atan2(flat.z, flat.x)
	orbit.angular_speed = gravity.orbit_velocity(dominant, to_craft.length()) / maxf(orbit.radius, 1.0)
	_craft_orbits.append(orbit)


## Walk every tracked orbit forward. Purely kinematic (see [_CraftOrbit]) —
## cheap enough to run every frame regardless of how many craft are orbiting.
func _update_large_craft_orbits(delta: float) -> void:
	if _craft_orbits.is_empty():
		return
	var still: Array[_CraftOrbit] = []
	for orbit in _craft_orbits:
		if not is_instance_valid(orbit.gen):
			continue
		orbit.angle += orbit.angular_speed * delta
		var pos := orbit.dominant.position + Vector3(cos(orbit.angle), 0.0, sin(orbit.angle)) * orbit.radius
		pos.y += orbit.y_offset
		orbit.gen.global_position = pos
		still.append(orbit)
	_craft_orbits = still
	# A body that moved into a new spatial-grid cell since PhysWorld last
	# indexed its scenery stays collidable at its *old* cell until the index
	# rebuilds — orbiting counts as "moved" every frame it's on, so keep it
	# fresh. Cheap relative to a whole flight scene's rock count; only paid
	# at all while something here is actually orbiting.
	if phys_world != null:
		phys_world.mark_scenery_dirty()


## A [constant LargeCraftGenerator.Archetype.DREADNOUGHT]'s own movement:
## cruises forward along its current facing and slowly turns to bring its
## nose toward the player, the "moves under its own power like a real ship"
## the user asked for. Deliberately simple — no steering/avoidance, no AI
## module dependency — a big capital ship reads as "alive" from a slow turn
## and a steady cruise alone, and a real behaviour tree is more than a debug
## spawn-menu megastructure needs.
class _CraftPatrol extends RefCounted:
	var gen: LargeCraftGenerator
	var speed: float
	var turn_rate: float  ## 0..1 basis-slerp factor per second

var _craft_patrols: Array[_CraftPatrol] = []
const DREADNOUGHT_CRUISE_SPEED := 12.0
const DREADNOUGHT_TURN_RATE := 0.12


func _place_large_craft_patrol(gen: LargeCraftGenerator) -> void:
	var patrol := _CraftPatrol.new()
	patrol.gen = gen
	# Cruise speed scales gently with size — a sun-scale dreadnought crawling
	# forward at the same literal m/s as a frigate-scale one reads wrong at
	# either end of the size dial, but a full linear scale would make the
	# biggest ones absurdly fast, so this is clamped and sub-linear.
	patrol.speed = DREADNOUGHT_CRUISE_SPEED * clampf(gen.scale_mult / 5.0, 0.6, 4.0)
	patrol.turn_rate = DREADNOUGHT_TURN_RATE
	_craft_patrols.append(patrol)


## Turn each patrolling dreadnought toward the player and walk it forward
## along its own (post-turn) facing — [member Node3D.scale] has to be
## preserved explicitly here since [Basis.looking_at] hands back a bare
## rotation, not this node's actual [member LargeCraftGenerator.scale_mult].
func _update_large_craft_patrols(delta: float) -> void:
	if _craft_patrols.is_empty() or model == null:
		return
	var still: Array[_CraftPatrol] = []
	for patrol in _craft_patrols:
		if not is_instance_valid(patrol.gen):
			continue
		var gen := patrol.gen
		var t := gen.global_transform
		var to_player := model.global_position - t.origin
		if to_player.length_squared() > 1.0:
			var wanted_fwd := to_player.normalized()
			var cur_fwd := -t.basis.z.normalized()
			var new_fwd := cur_fwd.slerp(wanted_fwd, clampf(patrol.turn_rate * delta, 0.0, 1.0))
			if new_fwd.length_squared() > 0.001:
				var up := Vector3.UP if absf(new_fwd.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
				t.basis = Basis.looking_at(new_fwd, up).scaled(Vector3.ONE * gen.scale.x)
		t.origin += (-t.basis.z.normalized()) * patrol.speed * delta
		gen.global_transform = t
		still.append(patrol)
	_craft_patrols = still
	if phys_world != null:
		phys_world.mark_scenery_dirty()  # see the matching note in _update_large_craft_orbits


## Visual-only weapon fire from [constant LargeCraftGenerator.Archetype.DREADNOUGHT]
## turrets: a volley of glowing bolts travels in a straight line toward
## wherever the player was at the moment of firing, then fades out. No damage
## is applied — the user explicitly chose "looks and moves like it's
## fighting" over full combat integration for this pass; real hull damage can
## wire into [member damage] later without touching any of this.
const TURRET_RANGE := 900.0
const TURRET_COOLDOWN := 1.6
const TURRET_BOLT_SPEED := 220.0
const TURRET_BOLT_LIFE := 3.5

var _turret_timers: Dictionary = {}  ## LargeCraftGenerator -> seconds to next volley
var _turret_bolts: Array[Dictionary] = []  ## {node, velocity, life}


func _update_large_craft_turrets(delta: float) -> void:
	if model == null:
		return
	for gen in _large_craft:
		if not is_instance_valid(gen) or gen.archetype != LargeCraftGenerator.Archetype.DREADNOUGHT:
			continue
		var cooldown: float = float(_turret_timers.get(gen, 0.0)) - delta
		if cooldown > 0.0:
			_turret_timers[gen] = cooldown
			continue
		if gen.global_position.distance_to(model.global_position) > TURRET_RANGE:
			_turret_timers[gen] = 0.5  # cheap range re-check, not a full reload
			continue
		_turret_timers[gen] = TURRET_COOLDOWN
		var target := model.global_position
		for muzzle in gen.get_turret_points():
			_spawn_turret_bolt(muzzle.origin, (target - muzzle.origin).normalized())
	_update_turret_bolts(delta)


func _spawn_turret_bolt(pos: Vector3, dir: Vector3) -> void:
	if dir.length_squared() < 0.001:
		return
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh_inst.mesh = sphere
	mesh_inst.material_override = ShipMaterials.glow_material(Color("ff5a3c"))
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)
	mesh_inst.global_position = pos
	_turret_bolts.append({"node": mesh_inst, "velocity": dir * TURRET_BOLT_SPEED, "life": TURRET_BOLT_LIFE})


func _update_turret_bolts(delta: float) -> void:
	if _turret_bolts.is_empty():
		return
	var still: Array[Dictionary] = []
	for b: Dictionary in _turret_bolts:
		var node: MeshInstance3D = b["node"]
		if not is_instance_valid(node):
			continue
		node.global_position += (b["velocity"] as Vector3) * delta
		var life: float = float(b["life"]) - delta
		if life <= 0.0:
			node.queue_free()
		else:
			b["life"] = life
			still.append(b)
	_turret_bolts = still


## Magnetizes the player's own ship toward any spawned large craft's dock
## pads. [DockingPad]'s own Area3D overlap path already handles debris and
## the gen-lab's RigidBody3D test craft automatically; [FlightModel] has no
## collider (see its own doc comment) so it never appears in
## [method Area3D.get_overlapping_bodies] and has to be pulled explicitly.
func _update_large_craft_docking(delta: float) -> void:
	if model == null or _large_craft.is_empty():
		return
	for gen in _large_craft:
		if not is_instance_valid(gen):
			continue
		for pad in gen.get_dock_pads():
			model.velocity = pad.pull_point(model.global_position, model.velocity, delta, model)


func clear_large_craft() -> void:
	for gen in _large_craft:
		if phys_world != null and _craft_collision_bodies.has(gen):
			for body: PhysBody in _craft_collision_bodies[gen]:
				phys_world.remove(body)
		if is_instance_valid(gen):
			gen.queue_free()
	_craft_collision_bodies.clear()
	if phys_world != null:
		phys_world.mark_scenery_dirty()
	_large_craft.clear()
	_craft_orbits.clear()
	_craft_patrols.clear()
	_turret_timers.clear()
	for b: Dictionary in _turret_bolts:
		var node: Node = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	_turret_bolts.clear()
	if _hud != null:
		_hud.show_hint("Large craft cleared")


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
	# set_velocity, not a bare write: by the time anything asks for an orbit this
	# ship is bound to the physics world, and the world's driven body reads its
	# own copy back at the top of the next step (see [method
	# FlightModel.set_velocity]).
	model.set_velocity(vel)
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
	model.set_velocity(dir * v_orbit)
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


## Camera FOV dial, degrees. Persists in Session so it survives a restart, and
## applies live to the current rig (chase mode adds its boost dolly each frame).
func set_camera_fov(deg: float) -> void:
	Session.camera_fov = deg
	Session.save_to_disk()
	if camera_rig != null:
		camera_rig.set_fov(deg)


## Third-person chase-distance dial (×). Persists in Session; applies live.
func set_camera_chase(scale: float) -> void:
	Session.camera_chase = scale
	Session.save_to_disk()
	if camera_rig != null:
		camera_rig.set_chase_scale(scale)


## When on, the chase camera freezes while the ship is out-of-control and snaps
## back the moment control returns. Off by default.
func toggle_ooc_camera_hold() -> void:
	if camera_rig != null:
		camera_rig.ooc_camera_hold = not camera_rig.ooc_camera_hold


func ooc_camera_hold_on() -> bool:
	return camera_rig != null and camera_rig.ooc_camera_hold


## Toggle Galaxy on Fire 2 style cinematic sunflare, radiant rays and dramatic contrast.
func toggle_cinematic_lighting() -> void:
	Session.cinematic_lighting = not Session.cinematic_lighting
	Session.save_to_disk()
	if space != null:
		space.set_cinematic_lighting(Session.cinematic_lighting)
	if _advanced_lighting != null:
		_advanced_lighting.enabled = Session.cinematic_lighting
	if _hud != null:
		_hud.show_hint("Cinematic sun lighting: %s" % ("ON" if Session.cinematic_lighting else "OFF"))


func cinematic_lighting_on() -> bool:
	return Session.cinematic_lighting


## The screen-space light shafts and grade, riding on the cinematic toggle. Only
## in [constant Location.SPACE]: it is the one location with a fixed star
## direction to march toward.
func _build_advanced_lighting() -> void:
	if space == null or camera_rig == null or camera_rig.camera == null:
		return
	_advanced_lighting = AdvancedLighting.create(camera_rig.camera, SpaceScene.SUN_DIR)
	_advanced_lighting.set_shaft_color(Palette.color("star").lerp(Color.WHITE, 0.35))
	add_child(_advanced_lighting)
	_advanced_lighting.enabled = Session.cinematic_lighting

## Toggle high-detail rendering. Does NOT resize the window (that just zoomed
## the stretch-scaled canvas); it raises the 3D render scale and rebuilds the
## procedural geometry — planets, nebula, rocks, sky — at higher segment counts
## so everything is genuinely less low-poly. Restarts the scene to rebuild.
func toggle_high_res() -> void:
	Session.high_res = not Session.high_res
	Session.save_to_disk()
	_hud.show_hint("High res: %s — rebuilding scene…" % ("ON" if Session.high_res else "OFF"))
	restart_scene()


## Planet mesh quality tier — 0 Low, 1 Medium, 2 High. Separate from [method
## toggle_high_res] (viewport supersampling): see [member Session.planet_quality].
func planet_quality() -> int:
	return Session.planet_quality


func set_planet_quality(tier: int) -> void:
	Session.planet_quality = clampi(tier, 0, 2)
	Session.save_to_disk()
	_hud.show_hint("Planet quality: %s — rebuilding scene…" % ["Low", "Medium", "High"][Session.planet_quality])
	restart_scene()


func toggle_high_contrast() -> void:
	BuilderTheme.high_contrast = not BuilderTheme.high_contrast
	ShipMaterials.high_contrast = BuilderTheme.high_contrast
	get_window().theme = BuilderTheme.build()
	_assemble()


## Set how fast the *player's* ship flies — the Settings dial behind [member
## Session.player_speed_scale] — and push it onto the ship already in the scene,
## so it takes effect as the slider moves rather than at the next respawn.
##
## Nothing here touches asteroids, debris or orbits: those are not
## [FlightModel]s, which is exactly the boundary the dial is meant to have. The
## AI population has its own dial, [method set_npc_speed_scale].
func set_player_speed_scale(scale: float) -> void:
	Session.player_speed_scale = maxf(scale, 0.05)
	Session.save_to_disk()
	if model != null:
		model.speed_scale = player_speed_base()
		model.rescale_speed(player_speed_base())


## The garage upgrade multiplier for [param stat] (`hull`, `guns`, `speed`,
## `yeet`) on the ship the menu handed over; 1.0 in a plain test flight.
func upgrade(stat: String) -> float:
	return float(upgrade_mults.get(stat, 1.0))


## The player's speed dial times the ship's speed upgrade — what every speed
## rescale of the player's own model starts from.
func player_speed_base() -> float:
	return Session.player_speed_scale * upgrade("speed")


## Set how fast every *other* ship flies — the AI population — and push it onto
## all of them at once. Separate from [method set_player_speed_scale] so slowing
## a fight down to make it readable and slowing the enemy down to make it winnable
## are two different things, which one dial could not express.
func set_npc_speed_scale(scale: float) -> void:
	Session.npc_speed_scale = maxf(scale, 0.05)
	Session.save_to_disk()
	if _ai_spawner == null:
		return
	for ship in _ai_spawner.ships():
		if is_instance_valid(ship) and ship.model != null:
			ship.model.speed_scale = Session.npc_speed_scale
			ship.model.rescale_speed(Session.npc_speed_scale)


## First [MeshInstance3D] found anywhere under [param n] (depth-first),
## including [param n] itself. Debris pieces are usually a RigidBody3D
## wrapper (see [method DebrisRegistry.wrap_rigidbody]) around the actual
## part node, so the mesh is one level deeper than a direct child.
func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for child in n.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


## Called by the damage system when a part breaks off. The damage system
## already moved the actual part node to world space as debris_node. We
## track that node, add a transparency fade, and spawn particle bursts.
func _on_part_broken(broken: DamageSystem.BrokenPart, _effects: Array) -> void:
	var node := broken.debris_node
	if node == null or not is_instance_valid(node):
		# No real node provided — skip the fallback box; a burst and a small
		# explosion are enough.
		AddonVfx.explosion(self, broken.world_pos, 0.7, false, Color("ff9944"))
		var break_xform := Transform3D(Basis(), broken.world_pos)
		Juice.burst(BurstPresets.Preset.SPARKS, break_xform, 1.2, Color("ffcc44"))
		Juice.burst(BurstPresets.Preset.DEBRIS, break_xform, 0.8)
		Juice.light_pop(broken.world_pos, Color("ff8844"), 3.0, 0.15)
		Juice.shake(0.15)
		AddonVfx.electric(self, broken.world_pos, 1.0, false)
		# ExplosionRegistry: small flash for the no-node fallback case.
		var _reg2 := ExplosionRegistry.new()
		_reg2.spawn_event(self, ExplosionRegistry.SLOT_PART_BREAKOFF,
			broken.world_pos, Vector3.UP, 0.7)
		return

	# Enable transparency fade on the first mesh found under the debris node.
	# Since DamageSystem now wraps every broken part in a RigidBody3D (see
	# DebrisRegistry.wrap_rigidbody), the mesh is usually nested one level
	# inside that wrapper rather than a direct child.
	var fade_mat: StandardMaterial3D = null
	var mi := _find_first_mesh(node)
	if mi != null:
		var mo = mi.material_override
		if mo is StandardMaterial3D:
			var m := (mo as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = m
			fade_mat = m
		else:
			var surf := mi.get_surface_override_material(0) as StandardMaterial3D
			if surf == null:
				surf = mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh != null else null
			if surf != null:
				surf = surf.duplicate() as StandardMaterial3D
				surf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.set_surface_override_material(0, surf)
				fade_mat = surf

	# wrap_rigidbody already gave a RigidBody3D piece its velocity, early-cull
	# timer and self-cleanup tween. Driving it kinematically via _debris_list
	# too would fight Godot's own physics step for the same transform every
	# frame, so only a plain node is tracked here. This used to `return` for
	# rigid bodies instead, and every part break is one now, so the whole
	# effect block below (sparks, explosion, "part lost" hint) never ran.
	if not node is RigidBody3D:
		var debris_life := 10.0 if _player_dead else 8.0
		DebrisRegistry.maybe_cull_when_unseen(node)
		_debris_list.append({
			"node": node,
			"velocity": broken.drift_dir * broken.drift_speed + model.velocity * 0.15,
			"spin_axis": Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(),
			"spin_speed": randf_range(2.5, 7.5),
			"life": debris_life,
			"material": fade_mat,
		})

	# A lost part goes out with a bang, not just a spark. Skipped in the
	# game-over break-up, where every part lands here in the same frame and
	# the death explosion already covers it.
	if not _player_dead:
		AddonVfx.explosion(self, broken.world_pos, 0.7, false, Color("ff9944"))
		if audio != null:
			audio.play_explosion(broken.world_pos, false)
	# Particle bursts at the break socket.
	var break_xform := Transform3D(Basis(), broken.world_pos)
	Juice.burst(BurstPresets.Preset.SPARKS, break_xform, 1.5, Color("ffcc44"))
	Juice.burst(BurstPresets.Preset.DEBRIS, break_xform, 1.0)
	Juice.burst(BurstPresets.Preset.EMBERS, break_xform, 0.7)
	Juice.light_pop(broken.world_pos, Color("ff8844"), 4.0, 0.18)
	Juice.shake(0.2)
	AddonVfx.electric(self, broken.world_pos, 1.2, false)
	if not _player_dead:
		Juice.kick(broken.drift_dir, 0.3)

	# Show loss hint (suppressed during total break-up to avoid 10 simultaneous hints)
	if not _player_dead:
		# A shout, not a sentence: the part's first word ("WING LOST!").
		player_callout("%s LOST!" % String(broken.part_name).get_slice(" ", 0))


func toggle_help() -> void:
	_coach.start(false)


func toggle_drift_field() -> void:
	Session.drift_field = not Session.drift_field
	Session.save_to_disk()
	_mote_field_on = Session.drift_field
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
	Session.save_to_disk()
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


## True while the debug chaos law (key Y) is applied, so the Gravity menu row
## can reflect the current state.
func gravity_chaos_on() -> bool:
	return _gravity_chaos


## True when gravity bodies attract things in ("pull"). Gravity menu toggle:
## off means orbit-only — bodies keep their own orbits and nothing falls in.
func gravity_pull_on() -> bool:
	return gravity != null and gravity.pull_enabled


func toggle_gravity_pull() -> void:
	if gravity == null:
		_hud.show_hint("Gravity pull needs gravity (G)")
		return
	gravity.pull_enabled = not gravity.pull_enabled
	Session.gravity_pull = gravity.pull_enabled
	Session.save_to_disk()
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
	Session.planet_pointer = _planet_pointer.is_showing()
	Session.save_to_disk()
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
	Session.save_to_disk()
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
	Session.save_to_disk()
	if not on:
		for trail in _ship_trails.values():
			if is_instance_valid(trail):
				(trail as Trail3D).set_enabled(false)
	_hud.show_hint("All-ships trail: %s" % ("on" if on else "off"))


## Recreate the enabled trails so a Trail-length change (which Trail3D reads at
## build time) takes effect immediately. Trails that are off stay off.
func refresh_trails() -> void:
	var player := trail_player_on()
	var ships := trail_ships_on()
	set_trail_player(false)
	set_trail_ships(false)
	if _player_trail != null:
		_player_trail.queue_free()
		_player_trail = null
	for trail in _ship_trails.values():
		if is_instance_valid(trail):
			(trail as Trail3D).queue_free()
	_ship_trails.clear()
	if player:
		set_trail_player(true)
	if ships:
		set_trail_ships(true)


## Keep the AI trails matched to the live roster: create one for each alive ship
## (or enable the existing), disable and free trails for ships that despawned.
## Ships farther than this from the player stop rebuilding their trail mesh
## every frame — an off-screen or far AI ship's trail was previously rebuilt
## unconditionally each frame regardless of whether anyone could see it.
const TRAIL_CULL_DIST := 1500.0

func _update_ship_trails() -> void:
	var keep: Dictionary = {}
	var focus_pos := model.global_position if model != null else Vector3.ZERO
	if _ai_spawner != null and Session.trail_ships:
		for ship in _ai_spawner._ships:
			if not is_instance_valid(ship) or not ship._alive:
				continue
			var near := ship.global_position.distance_to(focus_pos) <= TRAIL_CULL_DIST
			var trail := _ship_trails.get(ship) as Trail3D
			if trail == null:
				if not near:
					continue
				trail = Trail3D.new()
				trail.name = "ShipTrail_%s" % ship.name
				add_child(trail)
				trail.set_color(BuilderTheme.text_dim())
				_ship_trails[ship] = trail
			trail.set_enabled(near)
			if near:
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


# --- Aggro indicators ---------------------------------------------------------

## One floating icon per AI ship currently coming for the player, keyed by ship.
var _aggro_markers: Dictionary = {}
const AGGRO_MARKER_ICON := "guns/delapouite/crosshair.png"
## How far above the top of the hull the icon floats, in metres.
const AGGRO_MARKER_MARGIN := 2.5
## How wide the icon is in world metres — held constant regardless of how big the
## ship under it is, so it reads as a label rather than as part of the vessel.
const AGGRO_MARKER_SIZE := 4.0
## Past this the icon is dropped: across a solar system it is clutter, not
## information, and every marker is a node the renderer has to cull.
const AGGRO_MARKER_RANGE := 6000.0


## Float a billboarded icon over every AI ship currently aggroed onto the player.
##
## The HUD's lock bracket already answers "which ship am I after"; this answers
## the question a pilot actually gets shot over — "which of these six are after
## *me*". Shares the Markers toggle with the rest of the ship markings.
## A fast enemy shot passing close by without hitting is its own beat — a
## brief, gentle slowmo, distinct from the sharper hitstop a landed hit gets.
## There is no cross-ship collision layer for "did a shot pass near me", so
## this walks every live AI ship's own [SystemsSim.live_shot_positions] each
## frame instead.
func _update_near_miss(delta: float) -> void:
	_near_miss_cooldown = maxf(_near_miss_cooldown - delta, 0.0)
	if not JuiceSettings.near_miss_slowmo or _near_miss_cooldown > 0.0:
		return
	if model == null or _ai_spawner == null or _player_dead:
		return
	var p_pos := model.global_position
	for ship in _ai_spawner.ships():
		if not is_instance_valid(ship) or ship.systems == null:
			continue
		for pos in ship.systems.live_shot_positions():
			if p_pos.distance_to(pos) < NEAR_MISS_RADIUS:
				Juice.hitstop(0.05, 0.35)
				_near_miss_cooldown = NEAR_MISS_COOLDOWN
				return


func _update_aggro_indicators() -> void:
	var keep: Dictionary = {}
	var focus_pos := model.global_position if model != null else Vector3.ZERO
	if _ai_spawner != null and Session.hud_markers:
		for ship in _ai_spawner.ships():
			if not is_instance_valid(ship) or not ship._alive:
				continue
			if not is_instance_valid(ship.model) or not ship.is_aggroed_to_player():
				continue
			var pos := ship.model.global_position
			var dist := pos.distance_to(focus_pos)
			if dist > AGGRO_MARKER_RANGE:
				continue
			var marker := _aggro_markers.get(ship) as Sprite3D
			if marker == null:
				marker = _make_aggro_marker()
				add_child(marker)
				_aggro_markers[ship] = marker
			# Above the hull, along the *ship's* up: a rolled ship's icon rides
			# with the roll instead of sliding off to one side.
			var up: Vector3 = ship.model.global_transform.basis.y
			marker.global_position = pos + up * ship.marker_height(AGGRO_MARKER_MARGIN)
			# Fade out with range, so a distant melee is a hint rather than a wall
			# of identical icons. Only the alpha moves — the red it was given at
			# creation stays put. The floor stays high: a marker far enough away
			# to be nearly invisible is exactly the one worth knowing about.
			marker.modulate.a = clampf(1.0 - dist / AGGRO_MARKER_RANGE, 0.45, 1.0)
			keep[ship] = true
	for key in _aggro_markers.keys():
		if not keep.has(key):
			var gone := _aggro_markers[key] as Sprite3D
			if gone != null:
				gone.queue_free()
			_aggro_markers.erase(key)


## One indicator: a billboarded quad, so it faces the camera however the ship
## under it rolls or banks.
##
## Tinted red rather than left as the icon's own art. The icon is drawn white —
## it is a menu glyph — and white over a dark hull at range reads as a smudge of
## scenery, which is the one thing a threat marker must not be. The tint is
## [method BuilderTheme.bad], the same red the HUD already uses for the things
## that are shooting at you, so the two agree and high-contrast mode carries
## through to it.
func _make_aggro_marker() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "AggroMarker"
	var tex := load("res://assets/icons/" + AGGRO_MARKER_ICON) as Texture2D
	marker.texture = tex
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Unshaded: a label lit by the scene's sun would go black on its dark side.
	# It also means the tint below is the final colour, not a shade of it.
	marker.shaded = false
	marker.modulate = BuilderTheme.bad()
	# Sized from the texture's own width so the icon lands at AGGRO_MARKER_SIZE
	# metres across whatever resolution the art happens to be.
	var width := float(tex.get_width()) if tex != null else 64.0
	marker.pixel_size = AGGRO_MARKER_SIZE / maxf(width, 1.0)
	return marker


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
	for node in [_env_holder, _key_light, _fill_light, _rim_light]:
		if node != null:
			node.queue_free()
	_env_holder = null
	_key_light = null
	_fill_light = null
	_rim_light = null
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
	if controls_locked():
		get_viewport().set_input_as_handled()
		return
	# A one-thumb movement profile reads the bare screen first.
	if _pilot != null and not _player_dead and _pilot.handle_input(event):
		get_viewport().set_input_as_handled()
		return
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
		KEY_F:
			cycle_weapon()
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
			else:
				toggle_headlights()

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
			if key.shift_pressed:
				shatter_nearest_planet()
			else:
				camera_rig.set_mode(FlightCamera.Mode.PLANET)
				_hud.show_hint("Planet view — %s" % camera_rig.mode_label())
		KEY_X:
			_fire_heavy_weapon()
			_hud.show_hint("Heavy antimatter blast fired (X)")
		KEY_K:
			# A/B the feel: cycles every .tres in physics/data/profiles live. The
			# swap covers collision AND gravity. Only in space, where a world exists.
			var profile := cycle_phys_profile()
			if profile != "":
				_hud.show_hint("Feel profile: %s (collision + gravity)" % profile)
		KEY_R:
			if _player_dead:
				respawn_player_ship()
			else:
				respawn()
		KEY_U:
			cycle_move_profile()
		KEY_D:
			if key.shift_pressed:
				_dump_scene_tree()
			else:
				_hud.toggle_debug_panel()
		KEY_B:
			if _player_dead:
				return_to_hangar()
			else:
				toggle_rear_view()
		KEY_C:
			model.trigger_quick_turn()
		KEY_Z:
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
		KEY_8, KEY_KP_8:
			if incident_director != null:
				var types := IncidentDirector.INCIDENT_TYPES
				var t: String = types[randi() % types.size()]
				var inc := incident_director.trigger_incident(t)
				if inc != null:
					_hud.show_hint("Incident: %s" % inc.title)
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
		KEY_F4:
			# Manual player-ship respawn: rebuild the ship into a fresh circular
			# orbit around the current dominant body (debug helper, F4 is free).
			if enable_manual_spawn:
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_spawn_time >= spawn_cooldown:
					respawn_player_ship()
					_last_spawn_time = now
		KEY_F2:
			# Portrait preview on PC: flip the window between landscape and a
			# phone-shaped portrait one; the HUD lays itself out for either.
			if not OS.has_feature("mobile"):
				var sz := DisplayServer.window_get_size()
				var portrait := sz.y <= sz.x
				var want := Vector2i(540, 960) if portrait else Vector2i(1280, 720)
				DisplayServer.window_set_size(want)
				var screen := DisplayServer.screen_get_usable_rect()
				DisplayServer.window_set_position(screen.position + (screen.size - want) / 2)
				_hud.show_hint("Window: %s (F2 flips)" % ("portrait 540×960" if portrait else "landscape 1280×720"))
		KEY_F5:
			restart_scene()
		KEY_F6:
			if _hud != null:
				_hud.toggle_wireframe_mode()
			else:
				var on: bool = StyleManager.instance().toggle_wireframe()
		KEY_F7:
			if space != null and space.has_method("toggle_glare"):
				var on: bool = space.toggle_glare()
				if _hud != null:
					_hud.show_hint("Solar Glare: %s" % ("ON" if on else "OFF"))
		KEY_F8:
			set_mobile_view(not Session.mobile_view_fit)
		KEY_F9:
			if _hud != null:
				_hud.toggle_art_style()
		KEY_F10:
			if _hud != null:
				_hud.toggle_palette_menu()
		KEY_F11:
			var tree := get_tree()
			tree.debug_collisions_hint = not tree.debug_collisions_hint
			if _hud != null:
				_hud.show_hint("Collision Debug: %s" % ("ON" if tree.debug_collisions_hint else "OFF"))
		KEY_F12:
			_render_visible = not _render_visible
			set_debug_visible("everything", _render_visible)
			if _hud != null:
				_hud.show_hint("Rendering: %s" % ("ON" if _render_visible else "OFF (Collisions Only)"))
		KEY_F1:
			# F1 is the way back out of the mobile HUD (see FlightHud); with
			# the normal HUD up it keeps its old job, the controls card.
			if _hud != null and _hud.mobile_layout_active():
				_hud.set_mobile_layout(false)
			else:
				toggle_help()
		KEY_QUESTION, KEY_SLASH:
			toggle_help()
		KEY_ESCAPE:
			_on_back(false)
	if vp != null:
		vp.set_input_as_handled()

## Manual player-ship respawn (F4): rebuild the vessel into a fresh circular
## orbit around the current dominant body, without reloading the whole scene.
@export var enable_manual_spawn: bool = true
var _last_spawn_time: float = 0.0
var spawn_cooldown := 1.0  # Seconds between manual respawns

## Rebuild the player ship and spawn it in orbit around the dominant body. A
## manual respawn for flight testing: unlike [method respawn], which just resets
## the existing ship in place, this replaces the vessel so a broken hull comes
## back fresh — while AI traffic and scenery carry on.
## The AI spawner, made on demand in the locations that start without one
## (the test volume, a generated system) so scenarios work everywhere. A
## spawner made here starts with no ambient traffic.
func ensure_ai_spawner() -> AiSpawner:
	if _ai_spawner == null or not is_instance_valid(_ai_spawner):
		_ai_spawner = AiSpawner.new()
		_ai_spawner.name = "AiSpawner"
		_ai_spawner.auto_fleet = false
		_ai_spawner.ship_destroyed.connect(_on_ai_ship_destroyed)
		_ai_spawner.ship_marked.connect(_on_ai_ship_marked)
		_ai_spawner.ship_yeeted.connect(_on_ai_ship_yeeted)
		add_child(_ai_spawner)
	return _ai_spawner


## Put the player on an AI team (0 = none: every AI hunts the player).
func set_player_team(team: int) -> void:
	_player_team = team
	if model != null:
		model.set_meta("team", team)


## Full hull and shield; rebuilds the ship first if it was shot down.
func revive_player() -> void:
	if _player_dead or model == null:
		respawn_player_ship()
	player_hp = player_max_hp
	player_shield = player_max_shield
	set_player_team(_player_team)


## A headline for the player: the hint line on both HUDs.
## Whether the player's ship is down (between death and respawn).
func is_player_dead() -> bool:
	return _player_dead


func announce(text: String) -> void:
	if _hud != null:
		_hud.show_hint(text)


func respawn_player_ship() -> void:
	# Tear down the current ship. Drop the physics body first so the world never
	# steps a body pointing at a node that is about to be freed.
	if model != null:
		if location == Location.SPACE:
			model.clear_phys_world()
		model.queue_free()
		model = null
		if view != null:
			view.destroy()
			view = null
		systems = null
		damage = null  # DamageSystem is RefCounted; dropping it frees it.

	# Rebuild from the current design, then re-wire what the root binds once per
	# vessel: gravity, asteroid data, the physics body, and HUD feedback signals.
	_build_ship()
	_assemble()
	if gravity != null:
		model.gravity = gravity
	if space != null and space.has_meta("asteroid_data"):
		model._asteroid_data = space.get_meta("asteroid_data") as Array
	if location == Location.SPACE and phys_world != null and view != null:
		model.set_phys_world(phys_world, _ship_collision_radius(view), _ship_hull(view))
	systems.state_changed.connect(_on_systems_state)
	systems.fire_blocked.connect(_on_systems_fire_blocked)
	systems.weapon_switched.connect(_on_weapon_switched)
	if _hud != null and _hud.has_method("update_weapon_badge"):
		_hud.update_weapon_badge(systems.get_active_weapon())
	model.assist_changed.connect(_on_model_assist_changed)
	model.orbit_changed.connect(_on_orbit_changed)
	model.collided.connect(_on_model_collided)
	model.out_of_control_changed.connect(_on_model_ooc_changed)
	model.boost_changed.connect(_on_model_boost_changed)

	# Position: a stable circular orbit around the current dominant body, or the
	# origin when there is no space scene to orbit.
	var spawn_pos := Vector3.ZERO
	var spawn_velocity := Vector3.ZERO
	var face_orbit := false
	if space != null and location == Location.SPACE:
		var spawn_dist := space.planet_radius * 2.857
		spawn_pos = space.planet_centre + Vector3(spawn_dist, 0.0, 0.0)
		if gravity != null:
			var dominant := gravity.find_dominant_body(spawn_pos)
			if dominant != null:
				# Exact circular-orbit speed for this body: v = sqrt(G*M/r).
				var v_orbit := gravity.orbit_velocity(dominant, spawn_dist)
				var radial := (spawn_pos - dominant.position).normalized()
				var tangent := Vector3(-radial.z, 0.0, radial.x).normalized()
				spawn_velocity = tangent * v_orbit
				face_orbit = true
	elif location == Location.GENERATED_SYSTEM:
		var spawn := _generated_system_spawn(Session.pending_spawn_body_name)
		if spawn["ok"]:
			spawn_pos = spawn["pos"]
			spawn_velocity = spawn["vel"]
			face_orbit = spawn_velocity.length_squared() > 0.01

	model.global_position = spawn_pos
	model.velocity = spawn_velocity
	# Face along the orbit direction so flight assist doesn't pull toward the planet.
	if face_orbit:
		model.global_transform.basis = Basis.looking_at(spawn_velocity.normalized(), Vector3.UP)
	else:
		model.global_transform.basis = Basis()  # Reset rotation
	_after_respawn()
	if _hud != null:
		_hud.show_hint("Player ship rebuilt into orbit")


func cycle_weapon() -> void:
	var sys := active_systems()
	if sys == null:
		return
	var w: Dictionary = sys.cycle_weapon()
	if _hud != null:
		_hud.show_hint("Weapon: %s" % w.get("name", "Unknown"))
		if _hud.has_method("update_weapon_badge"):
			_hud.update_weapon_badge(w)


func set_weapon_index(idx: int) -> void:
	var sys := active_systems()
	if sys == null:
		return
	var w: Dictionary = sys.set_weapon_index(idx)
	if _hud != null:
		_hud.show_hint("Weapon: %s" % w.get("name", "Unknown"))
		if _hud.has_method("update_weapon_badge"):
			_hud.update_weapon_badge(w)


func _on_weapon_switched(weapon: Dictionary) -> void:
	if _hud != null and _hud.has_method("update_weapon_badge"):
		_hud.update_weapon_badge(weapon)


func on_planet_destroyed(planet: Planet) -> void:
	if planet == null or not is_instance_valid(planet):
		return
	var p_pos: Vector3 = planet.global_position
	var p_radius: float = planet.data.planet_radius if planet.data != null else 1500.0
	var p_name: String = planet.data.planet_name if planet.data != null else "Planet"
	
	if not planet.has_meta("shattered"):
		planet.set_meta("shattered", true)
		PlanetDebrisBuilder.shatter_planet(planet, p_pos, self, 420.0, Session.planet_break_fineness, phys_world)
	
	# Hide and disable planet
	planet.visible = false
	planet.process_mode = Node.PROCESS_MODE_DISABLED
	for child in planet.get_children():
		if child is Node3D:
			child.visible = false
	
	# Clean up landmarks so HUD indicators and minimap clear
	if space != null and space.get("landmarks") != null:
		var remaining_landmarks: Array[Dictionary] = []
		for lm in space.landmarks:
			var lm_pos: Vector3 = lm.get("position", Vector3.ZERO)
			var lm_name: String = lm.get("name", "")
			if lm_pos.distance_to(p_pos) > p_radius * 1.5 and lm_name != p_name and not p_name in lm_name:
				remaining_landmarks.append(lm)
		space.landmarks = remaining_landmarks
	
	# Clean up PhysWorld static colliders (preserve dynamic rock debris)
	if phys_world != null:
		var to_remove: Array[PhysBody] = []
		for b in phys_world.bodies:
			if b.kinematic and b.layer == PhysBody.Layer.STATIC:
				if b.node == planet or b.node == planet.get_parent() or (b.node != null and b.node.global_position.distance_to(p_pos) < p_radius * 1.2):
					to_remove.append(b)
		for b in to_remove:
			phys_world.remove(b)
	
	# Clean up gravity body
	if gravity != null:
		gravity.remove_body_near(p_pos, p_radius * 2.5)
		
	# Reset camera & targeting
	if camera_rig != null and camera_rig.mode == FlightCamera.Mode.PLANET:
		camera_rig.set_mode(FlightCamera.Mode.CHASE)
	if locked_target == planet:
		locked_target = null
	_planet_kill_moment(p_pos, p_radius, p_name)


## A planet wrecked by the player is the biggest thing that can happen: a
## nuke's mushroom cloud stands up where it was (upright on screen), the
## camera pushes slowly in on it while the game holds, and the headline says
## what just happened.
func _planet_kill_moment(p_pos: Vector3, p_radius: float, p_name: String) -> void:
	var up := camera_rig.camera.global_basis.y if camera_rig != null and camera_rig.camera != null else Vector3.UP
	CartoonBlast.mushroom(self, p_pos, p_radius * 0.9, up)
	Juice.flash(Color("ffb347"), 0.7, 0.6)
	Juice.shake(0.6)
	big_notice("PLANET WRECKED", p_name, Color("ff3a6e"), 2.2)
	if camera_rig != null and not _player_dead and not JuiceSettings.reduce_motion:
		camera_rig.cancel_kill_cam()
		camera_rig.start_kill_cam(null, p_pos, p_radius * 0.9, 2.5)


## Immediately shatters the nearest or locked planet with 3D fragments and asteroids.
func shatter_nearest_planet() -> void:
	var target_planet: Planet = null
	if locked_target is Planet and is_instance_valid(locked_target) and (locked_target as Planet).visible:
		target_planet = locked_target as Planet
	else:
		var candidate_planets := get_tree().get_nodes_in_group("planets")
		if candidate_planets.is_empty() and space != null:
			candidate_planets = space.find_children("", "Planet", true, false)
		
		var closest_dist := 1e9
		var cam_pos := camera_rig.camera.global_position if camera_rig != null and camera_rig.camera != null else (model.global_position if model != null else Vector3.ZERO)
		for p in candidate_planets:
			if p is Planet and is_instance_valid(p) and p.visible and p.data != null:
				var d := cam_pos.distance_to(p.global_position)
				if d < closest_dist:
					closest_dist = d
					target_planet = p
	
	if target_planet == null:
		if _hud != null:
			_hud.show_hint("No active planet found to shatter")
		return
	
	var p_pos := target_planet.global_position
	var p_radius: float = target_planet.data.planet_radius if target_planet.data != null else 1000.0
	var cam_pos := camera_rig.camera.global_position if camera_rig != null and camera_rig.camera != null else (model.global_position if model != null else p_pos + Vector3(0, 0, p_radius * 2.0))
	var hit_pos := p_pos + (cam_pos - p_pos).normalized() * p_radius
	
	_spawn_heavy_explosion(hit_pos)
	if systems != null:
		systems._destroy_planet(target_planet, hit_pos)
	else:
		if not target_planet.has_meta("shattered"):
			target_planet.set_meta("shattered", true)
			PlanetDebrisBuilder.shatter_planet(target_planet, hit_pos, self, 420.0, Session.planet_break_fineness, phys_world)
		on_planet_destroyed(target_planet)
	
	if _hud != null:
		var p_name: String = target_planet.data.planet_name if target_planet.data != null else "Planet"
		_hud.show_hint("💥 %s OBLITERATED (fineness ×%.2f)!" % [p_name, Session.planet_break_fineness])


func _fire_heavy_weapon() -> void:
	if camera_rig == null:
		return
	var camera := camera_rig.camera
	var from := camera.global_position
	var ray_dir := -camera.global_transform.basis.z
	var to := from + ray_dir * 100000.0
	var space_state := space.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	
	# Godot's built in raycast
	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		var hit_pos: Vector3 = result["position"]
		var collider: Node3D = result["collider"]
		
		# Spawn heavy explosion
		_spawn_heavy_explosion(hit_pos)
		
		# If it's a large craft part, fracture it
		if collider is StaticBody3D:
			var cur: Node = collider
			var gen: LargeCraftGenerator = null
			while cur != null:
				if cur is LargeCraftGenerator:
					gen = cur as LargeCraftGenerator
					break
				cur = cur.get_parent()
			if gen != null:
				gen.shatter_at(hit_pos, 30.0, ray_dir * 60.0)
		return

	# If we didn't hit a StaticBody3D, check planets
	if space != null:
		var closest_dist := 100000.0
		var closest_planet: Planet = null
		var hit_point := Vector3.ZERO
		
		var candidate_planets := get_tree().get_nodes_in_group("planets")
		if candidate_planets.is_empty():
			candidate_planets = space.find_children("", "Planet", true, false)
			
		for p in candidate_planets:
			if not (p is Planet) or not is_instance_valid(p):
				continue
			var sub := p as Planet
			if not sub.visible or sub.data == null:
				continue
			var center: Vector3 = sub.global_position
			var radius: float = sub.data.planet_radius
			var L: Vector3 = center - from
			var tca: float = L.dot(ray_dir)
			var d2: float = L.length_squared() - tca * tca
			var r2: float = radius * radius
			if d2 > r2:
				continue
			var thc: float = sqrt(maxf(0.0, r2 - d2))
			var t0: float = tca - thc
			var t1: float = tca + thc
			var t_hit := -1.0
			if t0 > 0.0:
				t_hit = t0
			elif t1 > 0.0:
				t_hit = t1
			if t_hit > 0.0 and t_hit < closest_dist:
				closest_dist = t_hit
				closest_planet = sub
				hit_point = from + ray_dir * t_hit
							
		if closest_planet != null:
			_spawn_heavy_explosion(hit_point)
			if systems != null:
				systems._destroy_planet(closest_planet, hit_point)
			else:
				on_planet_destroyed(closest_planet)


func _spawn_heavy_explosion(pos: Vector3) -> void:
	Juice.flash(Color(1.0, 0.8, 0.5), 0.2, 1.0)
	Juice.light_pop(pos, Color(1.0, 0.5, 0.2), 30.0, 1.5)
	Juice.shake(0.8)
	
	# Razor-thin luminous shockwave wavefront ring
	var mesh_inst := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 36
	tm.ring_segments = 16
	mesh_inst.mesh = tm
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_inst.material_override = mat
	
	add_child(mesh_inst)
	mesh_inst.global_position = pos
	mesh_inst.scale = Vector3(0.01, 0.05, 0.01)
	
	var tween := create_tween()
	tween.tween_property(mesh_inst, "scale", Vector3(120.0, 0.35, 120.0), 0.85).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.85)
	tween.tween_callback(mesh_inst.queue_free)
