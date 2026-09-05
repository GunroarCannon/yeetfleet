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
