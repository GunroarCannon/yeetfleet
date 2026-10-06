## Session: everything that describes the current run and must outlive a scene
## reload.
##
## Two kinds of state live here, side by side, for two different reasons:
##
##  * **Boot state** — the seed, the current mode, the module the launcher was
##    asked to start. Set once by [method start] (which the launcher calls on
##    the way in), read at construction time by everything that builds a
##    [NebulaContext], and never mutated again for the life of the run.
##  * **Display settings** — planet scale, high-res, trails, the flight scene's
##    location. These are static for the same reason they used to be static on
##    [FlightRoot]: a scene restart (F5) frees the scene root, and a preference
##    that lived on the node would reset with it. They were spread across three
##    unrelated classes; now they live in the one class any module is allowed
##    to read instead of four statics each needing its own finder.
##
## Nothing here may reference another module — core is the layer everything else
## is allowed to stand on. The flight location is therefore an int (that scene's
## own enum values), not the enum itself.
class_name Session
extends RefCounted


## What kind of run this is. CAREER (economy, stations, contracts) is not built
## yet; the enum exists so a [NebulaContext] can be constructed knowing which
## ruleset it is serving from day one.
enum Mode {
	SANDBOX,
	CAREER,
}


# --- Boot state -------------------------------------------------------------

static var _started := false

## The module the launcher should boot, from `--module=<id>`, or "" to show the
## picker. The module ids are the registry's, not scene paths.
static var boot_module := ""
## Whether `--module=` was actually given, so the launcher knows to auto-boot
## even when the module id does not resolve (it then warns and shows the picker).
static var boot_requested := false

static var mode := Mode.SANDBOX

## The seed of this run, printed by [method start] and forced with `--seed=<n>`.
## Zero means "nobody started a session" — a scene run directly from the editor
## (F6) is deterministic and silently unseeded until the launcher is involved.
static var seed := 0
static var seed_forced := false


# --- Campaign handoff (menu → flight → menu) ------------------------------------
# Plain dictionaries so neither side has to know the other's types: the menu
# (through the campaign module) fills the first two before changing scene, the
# flight scene reads them on build and writes the third when a level ends.
# Never saved to disk — a level is only ever in flight within one run.

## The level to fly: `{key, preset, overrides, title, number}`, or {} for
## free flight (sandbox, or the flight test run directly).
static var pending_level := {}
## The ship to fly: `{id, name, preset, paint, mults: {hull, guns, speed, yeet}}`,
## or {} for the flight test's own random pick.
static var pending_ship := {}
## How the level went: `{key, won, time, kills, hull}`, or {} when nothing is
## waiting to be counted.
static var level_result := {}


# --- Display settings (moved here from FlightRoot's statics) ------------------
# These are read during scene construction, so they have to survive scene
# reloads; see the class doc for why they live here and not on a scene root.

## Planet size scale: radii (and gravity mass, to match) multiply by this.
## Formerly `FlightRoot._planet_scale`.
static var planet_scale := 1.0
## Planet spacing scale: gaps between worlds and the moon's orbit.
## Formerly `FlightRoot._planet_spacing`.
static var planet_spacing := 1.0
## Planet shatter fineness / detail level: controls piece count and fragment scale when a planet breaks.
## 1.0 is default (balanced), lower = chunkier/coarser (e.g. 0.5), higher = finer/more pieces (e.g. 2.0).
static var planet_break_fineness: float = 1.0
## Radiant glow toggle for shattered planet pieces: controls whether fractured mantle/core emission is active.
## When false, disables emission on debris chunks and asteroids for enhanced performance/FPS on low-end hardware.
static var planet_debris_glow: bool = true
## Ship size scale: multiplies every spawned hull — the player's own and each AI
## ship — and its collision radius. 1.0 is the design size. Changing it reloads
## the flight scene so all ships rebuild at the new scale.
static var ship_scale := 1.0
## Debug: stream one `[ORBIT]` line per gravitating ship per second to the
## console. Off by default — the log exists for orbit tuning and, left on, flushes
## the console every second per ship, which stutters windowed runs.
static var debug_orbit_log := false
## Developer mode: the home screen's DEBUG chip, the flight scene's debug
## keys (D, K, G, F-keys...), its dev hints ("ORBIT: stable around...") and
## wordy incident banners. Off: the game as a player sees it. Set it here
## and only here (never saved, so an old save can't switch it).
static var debug_mode := false#OS.is_debug_build()
## High-res: render at a higher internal viewport resolution (supersampling).
## Formerly `FlightRoot._high_res_on`. Planet mesh density is its own separate
## dial — [member planet_quality] — since supersampling and geometry
## resolution are different costs and a faceted planet stays faceted no
## matter how many pixels it's rendered at.
static var high_res := false
## Planet mesh quality tier: 0 = Low, 1 = Medium (default), 2 = High. Scales
## sphere_resolution (and, via [method SpaceScene._detail], cloud/ring/
## asteroid/star segment counts too) so a planet is rounder and less faceted
## at higher tiers instead of relying on [member high_res]'s supersampling to
## paper over low geometry.
static var planet_quality := 1
## Which planet surface shader technique a session starts with — see
## [method Planet.swap_all_surface_shaders]. Lets the flight-test "Planet
## look" picker start pinned to one so it can be compared against the other
## across a restart.
static var planet_surface_alt := false
## Which planet look (an index into [constant Planet.SURFACE_STYLES]) a flight
## starts with — the flight test's "Planet look" picker. Supersedes
## [member planet_surface_alt], which is kept in step for old saves.
static var planet_surface_style := 0
## Player-ship exhaust trail. Formerly `FlightRoot._trail_player`.
static var trail_player := false
## Trails on every live AI ship. Formerly `FlightRoot._trail_ships`.
static var trail_ships := false
## Which location the flight scene rebuilds into on restart, as that scene's
## own [enum FlightRoot.Location] values. An int on purpose: core must not know
## a flight type.
static var flight_location := 0


# --- Flight HUD menu settings (survive F5 like the display settings above) -----

## Camera field of view in degrees. Formerly the rig's BASE_FOV constant; the
## Settings/Flight HUD menus dial it and it must survive a scene reload.
static var camera_fov := 72.0
## Third-person camera distance multiplier (1.0 = the default framing).
static var camera_chase := 1.0
## Flight-assist authority multiplier (1.0 = the control mode's own preset).
## Applied inside FlightModel.configure so it survives respawns, control-mode
## switches and damage re-derives.
static var assist_mult := 1.0
## Damping authority multiplier (1.0 = the control mode's own preset).
static var damping_mult := 1.0
## HUD overlay toggles (reticle, lock brackets/markers, player indicator).
static var hud_reticle := true
static var hud_markers := true
static var hud_indicators := true

## Mobile screen view fit: tighter camera framing (closer chase, focused FOV) and enlarged touch targets.
static var mobile_view_fit := false

## Mesh and collision baking: merge meshes for lower draw calls and pre-bake compound colliders.
static var mesh_baking_enabled := false
## Whether the drift field (motes/streaks) and planet pointer come back on after
## a reload — they used to be ephemeral per-scene toggles.
static var drift_field := true
static var planet_pointer := false
## Whether gravity bodies attract things in ("pull"). Off by default.
static var gravity_pull := false
## World-build quality dials. Read while the space scene builds, so changing one
## takes effect on the next scene restart (the menus label them "restart to
## apply", the same contract as [member planet_scale]).
static var star_density := 1.0
## Star size multiplier for celestial background stars.
static var star_size_mult := 1.25
static var asteroid_density := 1.0
## Enhanced backdrop: corona, distant galaxy and nebula dust around the star.
static var render_backdrop := true
## The flight sky's baked nebula panorama (see [NebulaSky]): curling gas, a
## galactic band with dust lanes and a dense star field behind everything.
## Off = the flat palette background colour.
static var nebula_sky := true
## Enhanced lighting: increases rim strength and warms the main light.
static var enhanced_lighting := true
## Cinematic lighting (Galaxy on Fire 2 style): dramatic sunflare starburst, intense bloom, high-contrast rim & shadows.
## Also drives the screen-space light shafts and colour grade ([AdvancedLighting]),
## which is why it starts off on phones: the shafts cost a march per pixel.
static var cinematic_lighting := not OS.has_feature("mobile")
## Weird glare/flare effects toggle: solar corona, flare petals, intense bloom.
static var glare_enabled := true
## Tactical high-beam headlights and navigation lights on ships.
static var ship_headlights := true
## Trail length multiplier, read by Trail3D when a trail is (re)built.
static var trail_length := 1.0
## Solar system gen lab: simulation speed multiplier, live-read (no restart
## needed) by [SolarSystemGenerator.time_scale]. Persisted so reopening the lab
## resumes at the speed it was left at.
static var solar_time_scale := 1.0
## Solar system gen lab: the last "Distance" preset's scale, read by
## [method SolarSystemGenLabRoot._build_generator] so reopening the lab
## regenerates at the spacing it was left at instead of resetting to Default.
static var solar_distance_scale := 1.0
## How fast the *player's* ship flies, as a fraction of the speed its design
## resolves to. Scales [code]FlightModel[/code]'s top speed and acceleration
## together, so a slowed ship takes the same time to reach its (lower) top speed
## and handles exactly as it did — the readouts stay honest, they just read the
## lower number the ship is really doing.
##
## Ships only, and this one only the player's: asteroids, debris, planet orbits
## and every other thing that moves on its own keep their real speed, and
## [member npc_speed_scale] is the separate dial for everyone else. See
## [member arcade_pivot] and [member fast_orbits] for the other handling dials.
static var player_speed_scale := 1.0
## The same dial for every other ship — the AI population. Kept separate from
## [member player_speed_scale] so a fight can be slowed down or sped up around
## the player without changing how the player's own ship flies: turning your own
## speed down to make combat readable is a different request from turning the
## enemy's down to make it winnable, and one dial cannot do both.
static var npc_speed_scale := 0.3
## Fast orbits: a ship being held in orbit by the flight model's orbital assist
## whips around its body faster than the body's own gravity would ever carry it.
## Deliberately unphysical — that is what the toggle is for.
static var fast_orbits := false
## How much faster, when [member fast_orbits] is on. A circle taken at k times
## the circular speed needs k² times the pull, so the assist scales the gravity
## the held ship feels by k² alongside its speed: the orbit stays the same circle,
## just sooner. Only ships the assist is actively holding are affected, so
## letting go of the orbit returns gravity to normal.
static var orbit_speed_scale := 4.0
## Arcade mode's pivot multiplier: how much faster than the mode's own preset the
## nose swings round. 1.0 is arcade as authored.
##
## Arcade is the mode that exists to be responsive, so this is where an
## FPS-like "point the nose and be pointing there" belongs — crank it and the
## ship pivots almost instantly. Deliberately scoped to arcade: sim and
## realistic are the modes that exist to have weight, and a dial that could
## quietly turn those into the same thing would make the mode list a lie.
static var arcade_pivot := 3.0
## Solar-system-gen lab handoff to the real flight scene: the generation
## recipe for [constant FlightRoot.Location] value GENERATED_SYSTEM, or null
## for none pending — see [SolarSystemGenLabRoot._on_enter_flight_test_pressed].
## Typed as the engine's own [Resource], not the solar_system_gen module's own
## data class: core must not reference another module's type (see this
## class's own doc on [member flight_location] being an int for the same
## reason); [code]FlightRoot[/code] casts it back to the real type when it
## reads it.
static var pending_solar_system: Resource = null
## Body name within [member pending_solar_system] to spawn the player near.
## "" means "the first planet".
static var pending_spawn_body_name := ""
## The space system's look for the next flight, as a plain recipe ({} = the
## hand-built default system): {seed, looks: [main, second, third] palette
## ids, sizes: [main, second, third] radius multipliers, yaw (radians the
## planets are swung round the belt), rocks (floating-rock density), rings
## (main planet ringed), events: [incident ids]}. The campaign fills it from
## a level's seed, the sandbox rolls a fresh one. Not saved.
static var space_setup := {}
## The player's flight control mode (Arcade / Sim / Realistic / Dogfight), as
## the flight module's own enum value, or -1 for "the model's default". An int
## for the same reason as [member flight_location]. It used to live only on the
## player's FlightModel instance, so a restart always fell back to Arcade.
static var control_mode := -1
## Movement profile ([enum FlightRoot.MoveProfile]): 0 classic stick & buttons,
## 1 swipe, 2 slingshot (the default). Without [member debug_mode] only those two
## are reachable. A separate axis from [member control_mode], which
## tunes the flight numbers underneath whichever profile is flying.
static var move_profile := 2
## Flight-assist mode (0 manual, 1 damping, 2 full), or -1 for the default.
static var assist_mode := -1
## The chase/cockpit/rear view the player last picked, or -1 for the default.
static var camera_view := -1
## Render distance (far clip) and FAR-view ceiling, metres; -1 = defaults.
static var far_clip := -1.0
static var far_view_max := -1.0
## Every other flight-test preference, keyed by name: the menus' gravity,
## orbit, combat and camera toggles, the debug strip, star style, and so on.
## One saved dictionary rather than a static per dial, since these belong to
## the flight scene's own UI and change often. The flight scene fills it (see
## FlightRoot._capture_prefs) and reads it back on build. Values must be plain
## Variants (bool/int/float/String/Array) so ConfigFile can store them.
static var prefs := {}


## A saved flight-test preference, or [param default] if never set.
static func pref(key: String, default: Variant) -> Variant:
	return prefs.get(key, default)


# --- Boot -------------------------------------------------------------------

## The launcher calls this once, before deciding what to show. Reads the
## command line for `--module=<id>`, `--seed=<n>` and `--mode=...`, rolls a
## random seed when none was forced, then prints the run's identity so a bug
## report is a number.
static func start() -> void:
	if _started:
		return
	_started = true
	load_from_disk()
	read_cmdline(_run_args())
	if not seed_forced:
		_roll_seed()
	_announce()


## A fresh random seed for runs that were not told which seed to use. Separate
## so [method start] reads obviously: forced runs keep their number, unforced
## runs get one they could have forced.
static func _roll_seed() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	# rand() is a signed 32-bit int; printing a negative "seed -123" is fine
	# mechanically but a positive number is the one you can paste back after a
	# bug report. The +1 keeps zero ("nobody started a session") unambiguous.
	seed = (r.randi() & 0x7FFFFFFF) + 1


## Every argument this process was started with — engine args and the user args
## after `--`. `--module=` and `--seed=` never collide with an engine flag, so
## scanning across both is the most robust read: the editor's main_run_args and
## a manual `-- --module=...` land in different places, and this finds either.
static func _run_args() -> PackedStringArray:
	var all := PackedStringArray(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all


## Parse boot arguments. Split out of [method start] so tests can hand an exact
## list instead of this process's own command line.
static func read_cmdline(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--module="):
			boot_module = arg.get_slice("=", 1).strip_edges()
			boot_requested = boot_module != ""
		elif arg.begins_with("--seed="):
			_set_seed_text(arg.get_slice("=", 1))
		elif arg.begins_with("--mode="):
			var name := arg.get_slice("=", 1).strip_edges().to_lower()
			if name == "career":
				mode = Mode.CAREER
			elif name == "sandbox":
				mode = Mode.SANDBOX


## `--seed=banana` is a warning, not a crash and not a silent seed 0: a forced
## seed that is actually the default would defeat the point of forcing it.
static func _set_seed_text(text: String) -> void:
	if text.is_valid_int():
		seed = text.to_int()
		seed_forced = true
	else:
		push_warning("Session: --seed=%s is not an integer — ignoring it" % text)


static func _announce() -> void:
	var mode_name := "sandbox"
	match mode:
		Mode.SANDBOX: mode_name = "sandbox"
		Mode.CAREER: mode_name = "career"
	var forced := " (forced)" if seed_forced else ""
	print("[session] Project Nebula — mode %s, seed %d%s" % [mode_name, seed, forced])


const SETTINGS_PATH := "user://session_settings.cfg"
const SECTION := "session"


## What was last written by [method save_to_disk], so [method autosave] can
## tell whether anything changed.
static var _last_saved_text := ""


## Save only if something changed since the last save. A scene calls this on
## a timer and on exit as a safety net. Settings are changed from dozens of
## call sites, and any one that forgot its own [method save_to_disk] used to
## silently lose the setting on the next launch.
static func autosave() -> void:
	if _build_cfg().encode_to_text() != _last_saved_text:
		save_to_disk()


## Save all user-adjustable preferences to disk.
static func save_to_disk() -> void:
	var cfg := _build_cfg()
	_last_saved_text = cfg.encode_to_text()
	cfg.save(SETTINGS_PATH)
	GameDefaults.note_saved(SETTINGS_PATH)


static func _build_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "planet_scale", planet_scale)
	cfg.set_value(SECTION, "planet_spacing", planet_spacing)
	cfg.set_value(SECTION, "planet_break_fineness", planet_break_fineness)
	cfg.set_value(SECTION, "planet_debris_glow", planet_debris_glow)
	cfg.set_value(SECTION, "ship_scale", ship_scale)
	cfg.set_value(SECTION, "high_res", high_res)
	cfg.set_value(SECTION, "planet_quality", planet_quality)
	cfg.set_value(SECTION, "planet_surface_alt", planet_surface_alt)
	cfg.set_value(SECTION, "planet_surface_style", planet_surface_style)
	cfg.set_value(SECTION, "trail_player", trail_player)
	cfg.set_value(SECTION, "trail_ships", trail_ships)
	cfg.set_value(SECTION, "flight_location", flight_location)
	cfg.set_value(SECTION, "camera_fov", camera_fov)
	cfg.set_value(SECTION, "camera_chase", camera_chase)
	cfg.set_value(SECTION, "assist_mult", assist_mult)
	cfg.set_value(SECTION, "damping_mult", damping_mult)
	cfg.set_value(SECTION, "hud_reticle", hud_reticle)
	cfg.set_value(SECTION, "hud_markers", hud_markers)
	cfg.set_value(SECTION, "hud_indicators", hud_indicators)
	cfg.set_value(SECTION, "mobile_view_fit", mobile_view_fit)
	cfg.set_value(SECTION, "mesh_baking_enabled", mesh_baking_enabled)
	cfg.set_value(SECTION, "drift_field", drift_field)
	cfg.set_value(SECTION, "planet_pointer", planet_pointer)
	cfg.set_value(SECTION, "gravity_pull", gravity_pull)
	cfg.set_value(SECTION, "star_density", star_density)
	cfg.set_value(SECTION, "star_size_mult", star_size_mult)
	cfg.set_value(SECTION, "asteroid_density", asteroid_density)
	cfg.set_value(SECTION, "render_backdrop", render_backdrop)
	cfg.set_value(SECTION, "nebula_sky", nebula_sky)
	cfg.set_value(SECTION, "enhanced_lighting", enhanced_lighting)
	cfg.set_value(SECTION, "cinematic_lighting", cinematic_lighting)
	cfg.set_value(SECTION, "glare_enabled", glare_enabled)
	cfg.set_value(SECTION, "ship_headlights", ship_headlights)
	cfg.set_value(SECTION, "trail_length", trail_length)
	cfg.set_value(SECTION, "player_speed_scale", player_speed_scale)
	cfg.set_value(SECTION, "npc_speed_scale", npc_speed_scale)
	cfg.set_value(SECTION, "fast_orbits", fast_orbits)
	cfg.set_value(SECTION, "orbit_speed_scale", orbit_speed_scale)
	cfg.set_value(SECTION, "arcade_pivot", arcade_pivot)
	cfg.set_value(SECTION, "debug_orbit_log", debug_orbit_log)
	cfg.set_value(SECTION, "solar_time_scale", solar_time_scale)
	cfg.set_value(SECTION, "solar_distance_scale", solar_distance_scale)
	cfg.set_value(SECTION, "control_mode", control_mode)
	cfg.set_value(SECTION, "move_profile", move_profile)
	cfg.set_value(SECTION, "assist_mode", assist_mode)
	cfg.set_value(SECTION, "camera_view", camera_view)
	cfg.set_value(SECTION, "far_clip", far_clip)
	cfg.set_value(SECTION, "far_view_max", far_view_max)
	cfg.set_value(SECTION, "prefs", prefs)
	return cfg


## Load user preferences from disk.
static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH, Session.load_from_disk) != OK:
		return
	planet_scale = float(cfg.get_value(SECTION, "planet_scale", planet_scale))
	planet_spacing = float(cfg.get_value(SECTION, "planet_spacing", planet_spacing))
	planet_break_fineness = float(cfg.get_value(SECTION, "planet_break_fineness", planet_break_fineness))
	planet_debris_glow = bool(cfg.get_value(SECTION, "planet_debris_glow", planet_debris_glow))
	ship_scale = float(cfg.get_value(SECTION, "ship_scale", ship_scale))
	high_res = bool(cfg.get_value(SECTION, "high_res", high_res))
	planet_quality = clampi(int(cfg.get_value(SECTION, "planet_quality", planet_quality)), 0, 2)
	planet_surface_alt = bool(cfg.get_value(SECTION, "planet_surface_alt", planet_surface_alt))
	planet_surface_style = int(cfg.get_value(SECTION, "planet_surface_style", 1 if planet_surface_alt else 0))
	trail_player = bool(cfg.get_value(SECTION, "trail_player", trail_player))
	trail_ships = bool(cfg.get_value(SECTION, "trail_ships", trail_ships))
	flight_location = int(cfg.get_value(SECTION, "flight_location", flight_location))
	camera_fov = float(cfg.get_value(SECTION, "camera_fov", camera_fov))
	camera_chase = float(cfg.get_value(SECTION, "camera_chase", camera_chase))
	assist_mult = float(cfg.get_value(SECTION, "assist_mult", assist_mult))
	damping_mult = float(cfg.get_value(SECTION, "damping_mult", damping_mult))
	hud_reticle = bool(cfg.get_value(SECTION, "hud_reticle", hud_reticle))
	hud_markers = bool(cfg.get_value(SECTION, "hud_markers", hud_markers))
	hud_indicators = bool(cfg.get_value(SECTION, "hud_indicators", hud_indicators))
	mobile_view_fit = bool(cfg.get_value(SECTION, "mobile_view_fit", mobile_view_fit))
	mesh_baking_enabled = bool(cfg.get_value(SECTION, "mesh_baking_enabled", mesh_baking_enabled))
	drift_field = bool(cfg.get_value(SECTION, "drift_field", drift_field))
	planet_pointer = bool(cfg.get_value(SECTION, "planet_pointer", planet_pointer))
	gravity_pull = bool(cfg.get_value(SECTION, "gravity_pull", gravity_pull))
	star_density = float(cfg.get_value(SECTION, "star_density", star_density))
	star_size_mult = float(cfg.get_value(SECTION, "star_size_mult", star_size_mult))
	asteroid_density = float(cfg.get_value(SECTION, "asteroid_density", asteroid_density))
	render_backdrop = bool(cfg.get_value(SECTION, "render_backdrop", render_backdrop))
	nebula_sky = bool(cfg.get_value(SECTION, "nebula_sky", nebula_sky))
	enhanced_lighting = bool(cfg.get_value(SECTION, "enhanced_lighting", enhanced_lighting))
	cinematic_lighting = bool(cfg.get_value(SECTION, "cinematic_lighting", cinematic_lighting))
	glare_enabled = bool(cfg.get_value(SECTION, "glare_enabled", glare_enabled))
	ship_headlights = bool(cfg.get_value(SECTION, "ship_headlights", ship_headlights))
	trail_length = float(cfg.get_value(SECTION, "trail_length", trail_length))
	player_speed_scale = float(cfg.get_value(SECTION, "player_speed_scale", player_speed_scale))
	npc_speed_scale = float(cfg.get_value(SECTION, "npc_speed_scale", npc_speed_scale))
	fast_orbits = bool(cfg.get_value(SECTION, "fast_orbits", fast_orbits))
	orbit_speed_scale = float(cfg.get_value(SECTION, "orbit_speed_scale", orbit_speed_scale))
	arcade_pivot = float(cfg.get_value(SECTION, "arcade_pivot", arcade_pivot))
	debug_orbit_log = bool(cfg.get_value(SECTION, "debug_orbit_log", debug_orbit_log))
	solar_time_scale = float(cfg.get_value(SECTION, "solar_time_scale", solar_time_scale))
	solar_distance_scale = float(cfg.get_value(SECTION, "solar_distance_scale", solar_distance_scale))
	control_mode = int(cfg.get_value(SECTION, "control_mode", control_mode))
	move_profile = clampi(int(cfg.get_value(SECTION, "move_profile", move_profile)), 0, 3)
	assist_mode = int(cfg.get_value(SECTION, "assist_mode", assist_mode))
	camera_view = int(cfg.get_value(SECTION, "camera_view", camera_view))
	far_clip = float(cfg.get_value(SECTION, "far_clip", far_clip))
	far_view_max = float(cfg.get_value(SECTION, "far_view_max", far_view_max))
	var saved_prefs: Variant = cfg.get_value(SECTION, "prefs", {})
	if saved_prefs is Dictionary:
		prefs = (saved_prefs as Dictionary).duplicate(true)
	_last_saved_text = _build_cfg().encode_to_text()


## Restore every persisted display/menu setting to its shipped default. The
## Flight HUD Settings menu's "Reset all settings" row calls this and then
## restarts the scene so the world, ships and HUD all rebuild at the defaults.
static func reset_to_defaults() -> void:
	planet_scale = 1.0
	planet_spacing = 1.0
	planet_break_fineness = 1.0
	planet_debris_glow = true
	ship_scale = 1.0
	high_res = false
	planet_quality = 1
	planet_surface_alt = false
	planet_surface_style = 0
	trail_player = false
	trail_ships = false
	flight_location = 0
	debug_orbit_log = false
	camera_fov = 72.0
	camera_chase = 1.0
	assist_mult = 1.0
	damping_mult = 1.0
	hud_reticle = true
	hud_markers = true
	hud_indicators = true
	mobile_view_fit = false
	mesh_baking_enabled = false
	drift_field = true
	planet_pointer = false
	gravity_pull = false
	star_density = 1.0
	star_size_mult = 1.25
	asteroid_density = 1.0
	render_backdrop = true
	enhanced_lighting = true
	cinematic_lighting = not OS.has_feature("mobile")
	glare_enabled = true
	ship_headlights = true
	trail_length = 1.0
	solar_time_scale = 1.0
	solar_distance_scale = 1.0
	player_speed_scale = 1.0
	npc_speed_scale = 0.3
	fast_orbits = false
	orbit_speed_scale = 4.0
	arcade_pivot = 3.0
	control_mode = -1
	move_profile = 2
	assist_mode = -1
	camera_view = -1
	far_clip = -1.0
	far_view_max = -1.0
	prefs = {}
	pending_solar_system = null
	pending_spawn_body_name = ""
	# Remove config file so fresh defaults are preserved
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	var path_global := ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(path_global):
		DirAccess.remove_absolute(path_global)
	# Every other settings file too, then re-read: each class lands on the
	# tuning that ships ([GameDefaults]), not only on the code's defaults.
	GameDefaults.reset_player_files()
