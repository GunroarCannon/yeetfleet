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


# --- Display settings (moved here from FlightRoot's statics) ------------------
# These are read during scene construction, so they have to survive scene
# reloads; see the class doc for why they live here and not on a scene root.

## Planet size scale: radii (and gravity mass, to match) multiply by this.
## Formerly `FlightRoot._planet_scale`.
static var planet_scale := 1.0
## Planet spacing scale: gaps between worlds and the moon's orbit.
## Formerly `FlightRoot._planet_spacing`.
static var planet_spacing := 1.0
## Ship size scale: multiplies every spawned hull — the player's own and each AI
## ship — and its collision radius. 1.0 is the design size. Changing it reloads
## the flight scene so all ships rebuild at the new scale.
static var ship_scale := 1.0
## Debug: stream one `[ORBIT]` line per gravitating ship per second to the
## console. Off by default — the log exists for orbit tuning and, left on, flushes
## the console every second per ship, which stutters windowed runs.
static var debug_orbit_log := false
## High-res: render at a higher internal resolution and rebuild geometry denser.
## Formerly `FlightRoot._high_res_on`.
static var high_res := false
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
static var planet_pointer := true
## World-build quality dials. Read while the space scene builds, so changing one
## takes effect on the next scene restart (the menus label them "restart to
## apply", the same contract as [member planet_scale]).
static var star_density := 1.0
static var asteroid_density := 1.0
## Enhanced backdrop: corona, distant galaxy and nebula dust around the star.
static var render_backdrop := true
## Trail length multiplier, read by Trail3D when a trail is (re)built.
static var trail_length := 1.0
## Solar system gen lab: simulation speed multiplier, live-read (no restart
## needed) by [SolarSystemGenerator.time_scale]. Persisted so reopening the lab
## resumes at the speed it was left at.
static var solar_time_scale := 1.0
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
static var npc_speed_scale := 1.0
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
static var arcade_pivot := 1.0
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


# --- Boot -------------------------------------------------------------------

## The launcher calls this once, before deciding what to show. Reads the
## command line for `--module=<id>`, `--seed=<n>` and `--mode=...`, rolls a
## random seed when none was forced, then prints the run's identity so a bug
## report is a number.
static func start() -> void:
	if _started:
		return
	_started = true
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


## Restore every persisted display/menu setting to its shipped default. The
## Flight HUD Settings menu's "Reset all settings" row calls this and then
## restarts the scene so the world, ships and HUD all rebuild at the defaults.
static func reset_to_defaults() -> void:
	planet_scale = 1.0
	planet_spacing = 1.0
	ship_scale = 1.0
	high_res = false
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
	drift_field = true
	planet_pointer = true
	star_density = 1.0
	asteroid_density = 1.0
	render_backdrop = true
	trail_length = 1.0
	solar_time_scale = 1.0
	player_speed_scale = 1.0
	npc_speed_scale = 1.0
	fast_orbits = false
	orbit_speed_scale = 4.0
	arcade_pivot = 1.0
	pending_solar_system = null
	pending_spawn_body_name = ""

