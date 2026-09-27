## How a built ship moves. Every number it uses comes from [ShipStats], so a
## design that reads as sluggish in the builder flies sluggish here.
##
## Two flight modes, because the two things players want from a space game are
## incompatible: assist ON flies like an aeroplane (the ship goes where the nose
## points, throttle sets a speed to hold) and assist OFF flies like a spacecraft
## (thrust changes momentum, nothing stops you, the nose and the direction of
## travel are unrelated). Both run through the same integrator; assist is one
## extra force that steers velocity towards the nose.
##
## The ship is a plain [Node3D] that integrates its own velocity. Collision is a
## separate concern: once the scene binds this model to a [PhysWorld] (M1b) the
## ship is a driven body there — it writes its velocity each step and the world
## resolves it against scenery and other ships, handing impulses and spin back.
## A model that never joins a world keeps the old distance-based checks. A
## hand-integrated state is far easier to tune and to test than a [RigidBody3D]
## whose behaviour is buried in the physics server.
class_name FlightModel
extends Node3D

## Emitted when the flight-assist mode flips, so the HUD can relabel itself.
signal assist_changed(enabled: bool)

## Emitted when the ship's speed crosses into or out of boost, so the HUD and the
## camera can react to it. [param level] is 0..1.
signal boost_changed(level: float)

## Emitted when the ship enters or recovers from an out-of-control spin state.
signal out_of_control_changed(active: bool)

## Emitted from [method _on_phys_impacted] after a genuinely physical hit
## (ship-to-ship, ship-to-rock/scenery) is resolved — distinct from weapon
## damage, which never goes through the physics solver. [FlightRoot] uses
## this for the camera bump-zoom juice effect on the player's own ship.
## [param other_radius]/[param other_kinematic] describe what was hit, so a
## planet/station/anomaly can be told apart from a ship or a rock — see
## [method FlightRoot._on_model_collided].
signal collided(closing: float, other_radius: float, other_kinematic: bool)
## The same hit as [signal collided], with what was hit and the contact normal
## (pointing from [param other] toward this ship). The slingshot profile
## ([SlingRun]) picks its bounce from it.
signal impacted(other: PhysBody, normal: Vector3, closing: float)


func _ready() -> void:
	add_to_group("flight_models")


## Control input, all in -1..1 except throttle. Written every frame by
## [FlightControls]; read here and nowhere else.
class Command:
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	## Where the throttle lever is: 0..1 forward. Negative reverses.
	var throttle := 0.0
	## Held boost, spends energy for extra thrust.
	var boost := false
	## Lateral and vertical translation, for docking-speed nudges.
	var strafe := Vector3.ZERO


## Fraction of top speed the ship holds per unit of throttle.
const REVERSE_FRACTION := 0.45
## Boost multiplies thrust and raises the speed ceiling by this much.
const BOOST_THRUST := 2.1
const BOOST_SPEED := 1.35
## Energy per second a boost costs. Boosting a dry capacitor simply does nothing.
const BOOST_DRAIN := 14.0
## Seconds for the rotation rate to reach the commanded rate. Small enough that
## the ship feels connected to the stick, large enough that it is not a turret.
const ROTATION_SPOOL := 0.08
## Rotational damping when the stick is centred, as a fraction shed per second.
## Assist off still damps: a real ship has attitude thrusters and a pilot who
## uses them, and an un-damped tumble is nausea, not simulation.
const SPIN_DAMP_ASSIST := 7.0
const SPIN_DAMP_FREE := 2.0
## How hard assist pulls velocity onto the nose, per second.
const ASSIST_AUTHORITY := 2.6
## How hard the damping mode sheds velocity not aligned with the nose, per
## second. It is gentler than assist — the ship drifts, but drift decays.
const DAMPING_AUTHORITY := 0.8
## Roll is the one axis that should feel fast regardless of hull, so it gets a
## multiplier on the design's own agility.
const ROLL_FACTOR := 1.35
## Strafe thrust as a fraction of main thrust. Manoeuvring thrusters are small.
const STRAFE_FRACTION := 0.32
## How hard the ship visually rolls into a yaw turn, as a fraction of the yaw
## rate. This is a cosmetic tilt, not real aero — space has no lift — but it
## sells the direction of the turn to the player.
const VISUAL_ROLL_FACTOR := 0.4
## Smoothed visual roll, degrees per second of approach.
const VISUAL_ROLL_SMOOTH := 4.0

## Absolute floor and ceiling on the speed a design can be tuned to. A capital
## ship that computes to 40 m/s is unplayable and a scout at 900 m/s outruns the
## asteroid field's ability to convey speed.
const SPEED_MIN := 90.0
const SPEED_MAX := 520.0

var command := Command.new()

# --- Pilot overrides (movement profiles) ---

## Velocity is flown by a movement profile's pilot ([SwipePilot], [SlingRun])
## instead of throttle and assist: no thrust, no assist, no speed ceiling here.
## Gravity, orbital assist and collisions still apply.
var external_drive := false
## The hull spins freely (a slingshot launch): the stick is ignored, a knock's
## tumble is not snapped to a spinning top, and it decays at
## [member free_spin_damp] per second.
var free_spin := false
var free_spin_damp := 0.15
## With [member free_spin]: the nose follows the velocity like a rocket and the
## hull rolls about it at [member rocket_roll_rate] rad/s, instead of tumbling.
var rocket_spin := false
var rocket_roll_rate := 0.0
## Ramming: damage this ship deals when it rams, and takes when rammed. A
## movement profile built around ramming raises the first and lowers the other.
var ram_dealt_mult := 1.0
var ram_taken_mult := 1.0
## Scales [method _durability] (how hard this hull is to crush).
var durability_mult := 1.0

## True when the throttle sets a speed to hold and the ship follows its nose.
## 0 = manual, 1 = damping, 2 = assist (full fly-by-wire).
## Assist is the default now: the player spawns in orbit and assist's "coasting"
## rule (see _integrate_translation) leaves an un-throttled ship alone under
## gravity, so the orbit is held without fighting it.
var assist_mode := 2
## Legacy helper: true when full assist is on.
var assist := true

## Current world velocity, m/s.
##
## Writing this directly is honoured even on a body bound to a [PhysWorld]: see
## [method set_velocity] and [method _pull_solver_state] for how a teleport, a
## spawn ejection or a test's set-up survives the step that follows it.
var velocity := Vector3.ZERO
## The velocity this ship last handed the solver (see [method _pull_solver_state]).
var _phys_velocity_written := Vector3.ZERO
## A velocity the ship is carried along at on top of its own, as if flying
## inside a moving frame: it moves the ship but is not part of [member
## velocity], so the flight assist never brakes it, the nose never turns to it
## and the speed ceiling never clips it. Written by [AiShip]'s chase assist.
var frame_velocity := Vector3.ZERO
## The [member frame_velocity] folded into the solver's copy last step, taken
## back out when the solver's result is read (see [method _pull_solver_state]).
var _frame_velocity_written := Vector3.ZERO
## Current body-frame angular rate, rad/s: x pitch, y yaw, z roll.
var angular := Vector3.ZERO

## Filled from the design at [method configure].
var top_speed := 240.0
var accel := 20.0
## Peak turn rate, rad/s.
var turn_rate := 0.6
## This ship's speed multiplier: top speed and acceleration both scale by it.
##
## Set by whoever owns the ship rather than read from [Session] here, because a
## [FlightModel] genuinely does not know whether it is the player's — and now
## that those are two separate dials (see [member Session.player_speed_scale] and
## [member Session.npc_speed_scale]) it must not guess.
var speed_scale := 1.0
## The [member speed_scale] the two above were last derived with — see
## [method rescale_speed], which moves a live ship to a new one by the ratio.
var _speed_scale_at_configure := 1.0

var boost_level := 0.0

## Control-feel values in force from the control-mode preset: how hard full
## assist snaps velocity onto the nose, how hard damping relaxes it, and how fast
## the ship spools to the commanded turn rate. Wiring these per preset (they were
## declared but never read) is what actually separates Arcade from Realistic —
## authority and spool are the feel; the turn-rate multiplier alone is not.
var assist_authority := ASSIST_AUTHORITY
var damping_authority := DAMPING_AUTHORITY
var turn_spool := ROTATION_SPOOL

var _stats: ShipStats
## The capacitor lives in [SystemsSim] so weapons and boost draw on one pool.
var _systems: SystemsSim
var _was_boosting := false
## Smoothed visual roll added on top of the physics roll, so the ship visibly
## leans into yaw turns even when the pilot is not touching the roll axis.
var _visual_roll := 0.0

## Quick-turn state. Press C and the ship flips 180° over the top — nose leads
## the rotation around the ship's lateral axis over QUICK_TURN_DURATION seconds,
## ending inverted (the user's explicit call: "rotate with its nose, even if it
## ends up upside down"). The velocity is NOT changed — only the nose direction.
var _quick_turn_timer := 0.0
var _quick_turn_active := false
var _quick_turn_remaining := 0.0
const QUICK_TURN_DURATION := 0.25
## Total rotation: PI radians = 180°.
const QUICK_TURN_TOTAL := PI
var _damage: DamageSystem = null
## Asteroid positions for collision, set by FlightRoot after building the scene.
var _asteroid_data: Array = []

## The hull node an impact squash actually scales -- FlightRoot's "Hull" holder,
## handed in through [method configure] since it is built one level above this
## model (see FlightRoot._build_ship). Null is fine: squash is purely cosmetic,
## so a model with no visual (AI traffic, a headless smoke) just skips it.
var _visual: Node3D = null
## Current squash scale, eased back to [constant Vector3.ONE] over
## [member PhysProfile.squash_recovery] seconds. Kept separate from any scale
## the design/Session apply so the two never fight over [member Node3D.scale].
var _squash_scale := Vector3.ONE
var _squash_recovery := 0.5
## Where the squash scales about, in [member _visual]'s local space — the hull's
## centre. Scaling about the holder's own origin instead slid the whole hull
## toward that origin on every hit and back as it recovered, which read as the
## ship jumping and snapping home. Set by whoever builds the ship.
var squash_pivot := Vector3.ZERO
## [member _visual]'s resting position, captured when it is bound.
var _visual_rest_pos := Vector3.ZERO
## Visual knockback (see [member JuiceSettings.knockback_visual]): an offset of
## the drawn hull in ship space, sprung back home, and its spring velocity.
var _recoil := Vector3.ZERO
var _recoil_vel := Vector3.ZERO
## Peak visual knockback, in metres per unit of knockback strength.
const RECOIL_METRES := 0.14
## Hard cap on the visual knockback offset, in metres.
const RECOIL_MAX := 3.0

## Debug warp speed: held key multiplies effective thrust and speed ceiling.
## Not part of the flight model — purely a debug tool for exploring the
## wider system without waiting minutes to cross the belt.
var warp_active := false
const WARP_THRUST_MULT := 8.0
const WARP_SPEED_MULT := 8.0

## Gravity system reference. Set by FlightRoot after building the scene.
## When non-null, gravitational forces are applied each physics frame.
var gravity: GravitySystem = null

## Physics-layer membership (M1b). Null until the scene binds this model to a
## [PhysWorld]; once bound, collisions run through that world — this model
## writes its velocity onto [member _phys] each step and reads the solver's
## impulses and spin back, and the old distance-based [_method _check_collision]
## is disabled. A model that never joins a world keeps the old hand-rolled
## collision as a fallback.
var phys_world: PhysWorld = null
## This ship's body in the world. The controller (this model) writes its
## velocity and moves its own node; the world resolves against it and never
## integrates it. See [PhysBody.driven].
var _phys: PhysBody = null
## Rad/s of collision-induced tumble about a world axis, applied on top of the
## commanded rotation and decaying at the profile's spin damp. Kept separate
## from [member angular] so the pilot never fights a knocked spin through the
## stick — you recover from a tumble by boosting, not by fighting it.
var _tumble := Vector3.ZERO
## Seconds left in the post-impact window where flight-assist, damping and the
## orbital assist stay disengaged, so the consequence of a hit is visible
## before the computer flies the ship back onto its rails (§3.1 #6). Set from
## [PhysProfile.assist_lockout_on_impact].
var _assist_lockout := 0.0
## Out-of-control spin state: when an impact or shockwave induces violent spin,
## control authority is lost and the ship tumbles until it dampens or recovers.
var out_of_control := false
var _out_of_control_timer := 0.0
## Asymmetric aerodynamic or thruster drag resulting from severed wings / detached parts,
## which exerts constant rotational drift in forward flight.
var asymmetric_drag := Vector3.ZERO

## An induced tumble is capped so a violent hit can spin the ship fast and disorienting,
## but not infinitely break numerical integration.
const TUMBLE_MAX := 18.0
## How fast (rad/s²-equivalent lerp rate) an out-of-control tumble's axis snaps
## to world-up -- see [method _integrate_rotation]'s "simple spinning-top
## tumble" comment. High enough to converge within a couple of frames instead
## of a visible slow drift.
const TOP_SPIN_SNAP := 16.0
## Approach speed (m/s) below which a contact is a touch, not a crash.
const IMPACT_TOUCH_SPEED := 6.0
## Approach speed at which a hit starts breaking parts off.
const IMPACT_DAMAGE_SPEED := 18.0

## Orbit detection: emits when the ship enters or leaves a stable orbit.
signal orbit_changed(body_name: String, in_orbit: bool)
var _in_orbit := false
var _orbit_body_name := ""
## The fast-orbit dial's multiplier, for as long as [method
## _apply_orbital_assist] currently has this ship held in orbit — 1.0 whenever
## it does not. Read by the gravity step, which turns it into the k² of extra
## pull a k-times-faster circle needs; see [method _fast_orbit_factor].
var _orbital_hold_boost := 1.0

## Hysteresis timers: how long the ship must stay in band to be declared
## "in orbit" and how long it must stay out of band before being declared
## "lost", so the HUD status doesn't flicker on a slightly-elliptical orbit.
const ORBIT_GAIN_TIME := 0.4
const ORBIT_LOSE_TIME := 3.0
## How strongly the orbital assist pulls velocity toward the local circular-orbit
## velocity, per second. A lerp factor: 1.2/s catches you back into a circular
## orbit within about a second of coasting — a firm hold, so a stray nudge does
## not lose the orbit. Adjustable at runtime like [member gravity_strength].
var orbital_assist_rate := 1.8
const ORBITAL_ASSIST_RATE_STEPS := [0.5, 1.0, 1.8, 3.0, 6.0]
## The orbital assist engages once past this multiple of the body's radius —
## inside it, it's too late anyway (collision handles it). There is no outer
## radius cap: the outer edge instead tracks [member GravityBody.relevant_range]
## (the same mass-scaled "this body is dominant out to here" distance dominant-
## body selection already uses), so a ship coasting anywhere the sun (or any
## body) is the strongest pull gets caught — not just within a few body-radii.
## A fixed few-radii cap was the bug: a planet-sized orbit around the sun sits
## far outside 4× the sun's radius, so the old cap silently never engaged there.
const ORBITAL_ASSIST_MIN_R := 1.15
## Above this speed the assist stands down — a ship on a fast interplanetary
## coast should sail through, not get snapped onto a local circular rail. Below
## it (roughly a stock ship's top speed, see [member top_speed]) a coasting ship
## is assumed to want to settle into orbit.
const ORBITAL_ASSIST_MAX_SPEED := 300.0
## Throttle must pass this much before the ship is "really flying" under gravity.
## Below it the ship is treated as coasting and the orbital assist holds the
## orbit, so a light tap on the throttle does not kick you out of orbit — to
## leave you have to commit (throttle past ~20% or boost). Only applies where
## gravity is live; in open space a small throttle drives normally.
const ORBIT_THROTTLE_DEADZONE := 0.2
var _orbit_solid_time := 0.0
var _orbit_lost_time := 0.0
## Gravity strength multiplier, adjustable at runtime via number keys.
var gravity_strength := 1.0
const GRAVITY_STRENGTH_STEPS := [0.5, 1.0, 2.0, 5.0, 10.0]
var _orbit_log_timer := 0.0

## Control mode presets. ARCADE is forgiving and responsive; REALISTIC is
## sluggish and demanding; SIM defaults to the design's stats with no overrides.
## DOGFIGHT is tuned for knife-fight range and pairs with [FlightRoot]'s nose-on
## assist: the ship is agile enough to stay pointed at a locked target.
enum ControlMode { ARCADE, SIM, REALISTIC, DOGFIGHT }
var control_mode: int = ControlMode.ARCADE
## Multipliers applied on top of the design's own stats. `assist_autority` is how
## hard full-assist snaps velocity onto the nose, `damping` scales the damping
## authority, and `turn_spool` is how fast the ship reaches the commanded turn
## rate (seconds — small = snappy, large = heavy). These are the numbers that
## give a preset its character.
const PRESET_ARCADE := {
	"speed_mult": 1.8,
	"accel_mult": 2.5,
	"turn_mult": 3.0,
	"assist_autority": 4.5,
	"damping": 0.8,
	"turn_spool": 0.02,
}
const PRESET_SIM := {
	"speed_mult": 1.0,
	"accel_mult": 1.0,
	# Was 1.0: the design's raw agility turned most hulls far too slowly to
	# fight in.
	"turn_mult": 1.9,
	"assist_autority": ASSIST_AUTHORITY,
	"damping": 0.8,
	"turn_spool": ROTATION_SPOOL,
}
const PRESET_REALISTIC := {
	"speed_mult": 0.5,
	"accel_mult": 0.4,
	"turn_mult": 0.4,
	"assist_autority": 0.8,
	"damping": 0.8,
	"turn_spool": 0.25,
}
const PRESET_DOGFIGHT := {
	"speed_mult": 1.2,
	"accel_mult": 1.6,
	"turn_mult": 2.0,
	"assist_autority": 3.6,
	"damping": 1.2,
	"turn_spool": 0.02,
}


## Bind the model to a design's performance figures. Safe to call again when the
## player edits their ship and comes back.
func configure(
	stats: ShipStats, systems: SystemsSim, damage: DamageSystem = null, visual: Node3D = null
) -> void:
	_stats = stats
	_systems = systems
	_damage = damage
	if visual != null:
		_visual = visual
		_visual_rest_pos = visual.position
	if stats == null:
		return
	# Base stats from the design.
	var base_speed := clampf(stats.top_speed, SPEED_MIN, SPEED_MAX)
	var base_accel := maxf(stats.accel, base_speed * 0.12)
	var base_turn := deg_to_rad(clampf(stats.agility, 6.0, 140.0))
	# Apply control mode presets.
	var preset: Dictionary = PRESET_SIM
	match control_mode:
		ControlMode.ARCADE: preset = PRESET_ARCADE
		ControlMode.REALISTIC: preset = PRESET_REALISTIC
		ControlMode.DOGFIGHT: preset = PRESET_DOGFIGHT
	top_speed = base_speed * preset["speed_mult"] * speed_scale
	accel = base_accel * preset["accel_mult"] * speed_scale
	_speed_scale_at_configure = speed_scale
	turn_rate = base_turn * preset["turn_mult"] * _arcade_pivot_mult()
	# The preset's feel numbers — the authority, damping and spool that actually
	# give each mode its character (this is what was declared-but-never-read).
	# The Session multipliers let a persistent "feel" dial compose on top of the
	# mode's own preset, so a change survives mode switches and respawns.
	assist_authority = float(preset.get("assist_autority", ASSIST_AUTHORITY)) * Session.assist_mult
	damping_authority = DAMPING_AUTHORITY * float(preset.get("damping", 1.0)) * Session.damping_mult
	turn_spool = clampf(float(preset.get("turn_spool", ROTATION_SPOOL)), 0.02, 0.5)
	# A design re-tune (control mode preset, damage-driven re-derive) changes the
	# mass the physics layer resolves this ship with.
	if _phys != null:
		_phys.mass = _ship_mass()


func set_control_mode(mode: int) -> void:
	control_mode = mode
	# Re-apply stats with the new preset.
	if _stats != null:
		configure(_stats, _systems, _damage)


func set_assist_mode(mode: int) -> void:
	assist_mode = clampi(mode, 0, 2)
	assist = assist_mode == 2
	assist_changed.emit(assist)


func set_assist(enabled: bool) -> void:
	set_assist_mode(2 if enabled else 0)


func toggle_assist() -> void:
	# Cycle: assist -> damping -> manual -> assist
	var next := (assist_mode + 1) % 3
	set_assist_mode(next)


## Speed along the nose, signed. This is the number a pilot reads, not the
## magnitude of the velocity vector: drifting sideways at 200 m/s while pointing
## at a station is not "approaching at 200".
func forward_speed() -> float:
	return velocity.dot(-global_transform.basis.z)


## What the throttle is currently asking for, in m/s. Only meaningful with assist
## on; with it off the throttle is a thrust lever and this is what it would
## converge to.
func target_speed() -> float:
	var ceiling := top_speed * (BOOST_SPEED if boost_level > 0.01 else 1.0)
	# Debug warp raises the ceiling too: assist mode accelerates toward target_speed,
	# so a warp that only multiplied thrust would reach normal cruise faster but
	# never cruise faster — which reads as "warp does nothing".
	if warp_active:
		ceiling *= WARP_SPEED_MULT
	if command.throttle >= 0.0:
		return command.throttle * ceiling
	return command.throttle * top_speed * REVERSE_FRACTION


## Set the ship's velocity outright, keeping a bound physics body in step.
##
## This is the way to mean "this is my velocity now" — a teleport, a respawn,
## an ejection onto an orbit (see [method FlightRoot.enter_orbit] and
## [method AiSpawner.spawn_ballistic_satellite]), or a test setting up a speed.
## A plain [member velocity] write is honoured too as long as the solver has not
## touched the body since (see [method _pull_solver_state]); this method is the
## one that says so out loud.
func set_velocity(value: Vector3) -> void:
	velocity = value
	if _phys != null:
		_phys.velocity = value
		_phys_velocity_written = value


## This ship's body in the [PhysWorld], or null when it is not bound to one.
func phys_body() -> PhysBody:
	return _phys


## Drop all motion. Used when the scene restarts the ship rather than reloading.
func halt() -> void:
	velocity = Vector3.ZERO
	_knock_pending = Vector3.ZERO
	_recoil = Vector3.ZERO
	_recoil_vel = Vector3.ZERO
	angular = Vector3.ZERO
	_tumble = Vector3.ZERO
	_assist_lockout = 0.0
	boost_level = 0.0
	if _phys != null:
		_phys.velocity = Vector3.ZERO
		_phys.angular = Vector3.ZERO
		_phys_velocity_written = Vector3.ZERO
	# Re-derive speed/turn from stats if we have them, undoing any damage.
	if _stats != null:
		var base := clampf(_stats.top_speed, SPEED_MIN, SPEED_MAX)
		top_speed = base * speed_scale
		accel = maxf(_stats.accel, base * 0.12) * speed_scale
		_speed_scale_at_configure = speed_scale
		turn_rate = deg_to_rad(clampf(_stats.agility, 6.0, 140.0)) * _arcade_pivot_mult()


## Move this ship to a new [member speed_scale] without rebuilding it,
## by the *ratio* to the scale it was configured with: whatever the ship is
## doing right now — damage-shrunk engines, a preset's own multipliers, an AI's
## tuning — is preserved and only the pace changes. This is what lets the
## Settings dial reach ships already in flight, and reach them all rather than
## only the one being rebuilt next.
func rescale_speed(scale: float) -> void:
	if is_equal_approx(scale, _speed_scale_at_configure) or _speed_scale_at_configure <= 0.0:
		return
	var ratio := scale / _speed_scale_at_configure
	top_speed *= ratio
	accel *= ratio
	_speed_scale_at_configure = scale


## [member Session.arcade_pivot] while flying arcade, 1.0 in every other mode.
##
## Applied to [member turn_rate] at both places it is derived, so a respawn keeps
## the dial and a mode switch applies or drops it. Arcade's own [member
## turn_spool] is already near-instant, so this really is "the nose is where you
## pointed it" rather than a faster version of the same lag.
func _arcade_pivot_mult() -> float:
	if control_mode != ControlMode.ARCADE:
		return 1.0
	return maxf(Session.arcade_pivot, 0.01)


func _physics_process(delta: float) -> void:
	_update_boost(delta)
	_pull_solver_state(delta)
	_feed_knockback(delta)
	_integrate_rotation(delta)
	_integrate_translation(delta)
	_update_visual_roll(delta)
	_update_quick_turn(delta)
	_update_squash(delta)
	# Collisions are the PhysWorld's job once this model is bound to one; the old
	# distance-based tests are only a fallback for a model that never joined a
	# world (the tuning test volume, a combat arena without physics).
	if phys_world == null:
		_check_collision()
	_detect_teleport(delta)


## Last physics tick's position, for [method _detect_teleport].
var _last_tick_pos := Vector3.INF


## With physics interpolation on, a ship is drawn between its previous and
## current tick positions. A teleport (respawn, location change, arena jump)
## would then be drawn as a one-frame streak across the scene. Any move far
## beyond what this tick's velocity explains is treated as a teleport and the
## interpolation is reset. Cheap enough to run every tick, and it covers every
## caller that moves the ship, without each one having to remember to.
func _detect_teleport(delta: float) -> void:
	var here := global_position
	if _last_tick_pos != Vector3.INF:
		var expected := (velocity + frame_velocity).length() * delta
		if here.distance_to(_last_tick_pos) > expected * 3.0 + 25.0:
			reset_physics_interpolation()
	_last_tick_pos = here


## Apply an impact spin from a physical collision or explosion torque.
## [param torque_impulse] is in radians/second.
## [param out_of_control_duration] if > 0 locks out assist and scrambles pilot controls.
func apply_impact_spin(torque_impulse: Vector3, out_of_control_duration: float = 0.0) -> void:
	_tumble = (_tumble + torque_impulse).limit_length(TUMBLE_MAX)
	if out_of_control_duration > 0.0:
		_out_of_control_timer = maxf(_out_of_control_timer, out_of_control_duration)
		_assist_lockout = maxf(_assist_lockout, out_of_control_duration + 0.4)
		if not out_of_control:
			out_of_control = true
			out_of_control_changed.emit(true)


## Apply an explosive radial blast wave from [param blast_origin] out to [param max_radius].
## Pushes velocity outward, applies angular tumble torque, and knocks the ship out of control.
func apply_radial_blast(blast_origin: Vector3, max_radius: float, peak_force: float, peak_torque: float = 8.0) -> void:
	var diff := global_position - blast_origin
	var dist := diff.length()
	if dist >= max_radius:
		return
	var falloff := 1.0 - clampf(dist / max_radius, 0.0, 1.0)
	var intensity := falloff * falloff
	var push_dir := diff.normalized() if dist > 0.01 else -global_transform.basis.z
	# The player gets a scaled-down shove and spin (see
	# [member JuiceSettings.player_blast_push]): at full strength a nearby
	# blast threw the ship hundreds of metres and tumbled it for seconds.
	var push_mult := JuiceSettings.player_blast_push if is_player() else 1.0
	var spin_mult := JuiceSettings.player_blast_spin if is_player() else 1.0
	var impulse := push_dir * (peak_force * intensity * push_mult)
	velocity += impulse / _ship_mass()

	var spin_axis := push_dir.cross(Vector3(0.3, 0.9, -0.2)).normalized()
	if spin_axis.length_squared() < 0.01:
		spin_axis = Vector3.UP
	var torque := spin_axis * (peak_torque * intensity * spin_mult)
	var ooc_time := clampf(intensity * 2.5, 0.3, 3.0) * spin_mult
	if spin_mult > 0.0:
		apply_impact_spin(torque, ooc_time if ooc_time >= 0.15 else 0.0)

	if is_player():
		Juice.shake(clampf(intensity * 0.85, 0.2, 1.0), 0.45)
		Juice.hitstop(clampf(intensity * 0.06, 0.02, 0.09), 0.15)


# --- Rotation ---------------------------------------------------------------

func _integrate_rotation(delta: float) -> void:
	if free_spin:
		_integrate_free_spin(delta)
		return
	var wanted := Vector3(
		command.pitch * turn_rate,
		command.yaw * turn_rate,
		command.roll * turn_rate * ROLL_FACTOR
	)

	# If currently spinning out of control from an impact or blast:
	if _out_of_control_timer > 0.0:
		_out_of_control_timer = maxf(_out_of_control_timer - delta, 0.0)
		if _out_of_control_timer <= 0.0 and out_of_control:
			out_of_control = false
			out_of_control_changed.emit(false)
		# Simple spinning-top tumble: the tumble axis snaps to world-up almost
		# immediately and stays there, rate preserved — a single fast, clean
		# spin rather than a chaotic multi-axis wobble. (Playtest ask: "a
		# simple spin, like spinning a top, fast and quick" — this used to
		# blend in slowly and layer a jittery wobble on top so the first half
		# second read as chaos on purpose; that read as broken, not cartoony.)
		var spin_speed := _tumble.length()
		if spin_speed > 0.01:
			var top_axis := Vector3.UP * (1.0 if _tumble.y >= 0.0 else -1.0)
			var axis_now := (_tumble / spin_speed).lerp(top_axis, clampf(delta * TOP_SPIN_SNAP, 0.0, 1.0))
			_tumble = axis_now.normalized() * spin_speed
		wanted = Vector3.ZERO


	# Asymmetric drag from missing wings / detached parts pulls the ship continuously:
	# The player keeps a steady ship (only the lost turn rate) unless
	# [member JuiceSettings.player_wing_spiral] says otherwise; the AI spirals.
	if asymmetric_drag.length_squared() > 1e-6 and (JuiceSettings.player_wing_spiral or not is_player()):
		var fwd_speed := forward_speed()
		var drag_factor := clampf(fwd_speed / 120.0, 0.2, 2.5)
		wanted += asymmetric_drag * drag_factor

	# Spool towards the commanded rate on each axis, then damp any axis the pilot
	# is not asking anything of. Two separate steps rather than one blended one,
	# because damping an axis you are actively commanding is what makes a ship
	# feel like it is fighting you.
	var spool := clampf(delta / turn_spool, 0.0, 1.0)
	angular = angular.lerp(wanted, spool)

	var damp := SPIN_DAMP_ASSIST if assist_mode == 2 else (SPIN_DAMP_ASSIST * 0.6 if assist_mode == 1 else SPIN_DAMP_FREE)
	if out_of_control or _assist_lockout > 0.0:
		damp = SPIN_DAMP_FREE * 0.65
	var decay := clampf(damp * delta, 0.0, 1.0)
	if absf(command.pitch) < 0.01:
		angular.x = lerpf(angular.x, 0.0, decay)
	if absf(command.yaw) < 0.01:
		angular.y = lerpf(angular.y, 0.0, decay)
	if absf(command.roll) < 0.01:
		angular.z = lerpf(angular.z, 0.0, decay)

	if angular.length_squared() < 1e-8 and _tumble.length_squared() < 1e-8:
		return
	# Rotate in the body frame, in pitch/yaw/roll order. Applied as three local
	# rotations rather than one euler assignment so the ship has no gimbal lock
	# and no preferred "up" — you can fly inverted and it behaves identically.
	var basis := global_transform.basis
	basis = basis.rotated(basis.x, angular.x * delta)
	basis = basis.rotated(basis.y, angular.y * delta)
	basis = basis.rotated(basis.z, angular.z * delta)
	# Collision tumble rides on top, about a *world* axis (that is the axis the
	# solver spun this ship around). Premultiplied so it is independent of where
	# the nose happens to point, then decayed at the profile's mode-dependent
	# spin damp — fast when assist is flying, slow when the pilot is on manual,
	# which is what makes "got knocked, boost to recover" a real event.
	if _tumble.length_squared() > 1e-10:
		var rate := _tumble.length()
		var step := rate * delta
		if step > 1e-6:
			basis = (Basis(_tumble / rate, step) * basis).orthonormalized()
		_tumble *= clampf(1.0 - _spin_damp_now() * delta, 0.0, 1.0)

	# Renormalise: thousands of incremental rotations accumulate skew otherwise,
	# and a sheared basis shears the whole ship with it.
	global_transform = Transform3D(basis.orthonormalized(), global_transform.origin)


## A launched hull: no pilot, no assist. Either tumbles about whatever axis
## the knocks gave it, or points its nose along the flight path and rolls.
func _integrate_free_spin(delta: float) -> void:
	angular = Vector3.ZERO
	var basis := global_transform.basis
	if rocket_spin and velocity.length_squared() > 1.0:
		var fwd := velocity.normalized()
		var up := basis.y if absf(basis.y.dot(fwd)) < 0.95 else basis.x
		var aligned := Basis.looking_at(fwd, up)
		basis = basis.slerp(aligned, clampf(delta * 8.0, 0.0, 1.0))
		if absf(rocket_roll_rate) > 0.0:
			basis = Basis(fwd, rocket_roll_rate * delta) * basis
		_tumble = Vector3.ZERO
	elif _tumble.length_squared() > 1e-10:
		var rate := _tumble.length()
		basis = Basis(_tumble / rate, rate * delta) * basis
		_tumble *= clampf(1.0 - free_spin_damp * delta, 0.0, 1.0)
	global_transform = Transform3D(basis.orthonormalized(), global_transform.origin)


# --- Translation ------------------------------------------------------------

func _integrate_translation(delta: float) -> void:
	var basis := global_transform.basis
	var forward := -basis.z
	var thrust := accel * (BOOST_THRUST if boost_level > 0.01 else 1.0)
	# Debug warp: multiply thrust and speed ceiling while held.
	if warp_active:
		thrust *= WARP_THRUST_MULT

	# Under gravity, a coasting ship (no throttle, no strafe) is left alone in
	# every assist mode: assist would brake the orbital velocity to zero every
	# frame and damping would shed the radial pull, so a ship dropped in a
	# stable orbit instantly loses it and anything falling toward a planet is
	# yanked in. Hands on the stick, the modes behave as usual.
	var gravity_active := gravity != null and gravity.mode != GravitySystem.GravityMode.OFF
	var coasting := gravity_active \
		and absf(command.throttle) <= ORBIT_THROTTLE_DEADZONE and command.strafe == Vector3.ZERO

	# For a moment after an impact the ship flies manual: assist and damping
	# would erase the knock before the player has seen it, which is exactly the
	# "assist that undoes the story" the design bans (§3.1 #6). During the
	# lockout window the ship keeps whatever the collision handed it.
	var ctl := 0 if _assist_lockout > 0.0 else assist_mode

	if external_drive:
		# A movement profile's pilot owns the velocity (see [member external_drive]).
		pass
	elif ctl == 2:
		# Fly-by-wire: compute the velocity the pilot is asking for — the target
		# speed, along the nose — and accelerate towards it. This one line is the
		# whole difference between the full-assist mode.
		if not coasting:
			var wanted := forward * target_speed() + _strafe_vector(basis) * (top_speed * 0.25)
			var error := wanted - velocity
			var step := thrust * assist_authority * delta
			if error.length() <= step:
				velocity = wanted
			else:
				velocity += error.normalized() * step
	elif ctl == 1:
		# Damping: thrust like manual, but the velocity slowly relaxes towards
		# the nose heading. Gives the player a safety net without flying for them.
		velocity += forward * (thrust * command.throttle * delta)
		velocity += _strafe_vector(basis) * (thrust * STRAFE_FRACTION * delta)
		if not coasting:
			var wanted := forward * velocity.dot(forward)
			var error := wanted - velocity
			var damping_step := damping_authority * velocity.length() * delta
			if error.length() <= damping_step:
				velocity = wanted
			else:
				velocity += error.normalized() * damping_step
	else:
		# Manual: the throttle is a thrust lever, and nothing slows you down.
		velocity += forward * (thrust * command.throttle * delta)
		velocity += _strafe_vector(basis) * (thrust * STRAFE_FRACTION * delta)
	var ceiling := top_speed * BOOST_SPEED * 1.6
	if warp_active:
		ceiling *= WARP_SPEED_MULT
	if external_drive:
		# The pilot caps its own dashes and launches; this only stops a runaway.
		ceiling = top_speed * (WARP_SPEED_MULT * 2.0 if warp_active else 6.0)
	if velocity.length() > ceiling:
		velocity = velocity.normalized() * ceiling

	# Apply gravitational acceleration from all registered bodies.
	# Gravity is NOT clamped by the speed ceiling — a ship falling toward a
	# planet accelerates beyond its normal top speed, which is the whole
	# point of orbital mechanics. We do clamp at a hard maximum to prevent
	# numerical explosions from extremely close approaches. 30× top speed is
	# deliberately loose: this is an arcade game, falling fast should feel
	# ridiculous, not capped at a polite ceiling.
	if gravity != null and gravity.mode != GravitySystem.GravityMode.OFF:
		var grav_force := gravity.compute_gravity(global_position)
		# The fast-orbit dial's pull, squared: a circle taken at k times the
		# circular speed needs k² times the centripetal acceleration, so a ship
		# the orbital assist is holding is given k² times the gravity to go with
		# its k times the speed — and it is a real orbit rather than a fake one.
		# One frame behind the assist, which sets it at the end of its own step;
		# it is 1.0 for every ship that is not being held, so nothing else feels
		# it. See [method _fast_orbit_factor].
		var pull := gravity_strength * _orbital_hold_boost * _orbital_hold_boost
		velocity += grav_force * pull * delta
		var hard_ceiling := top_speed * 30.0 * _orbital_hold_boost
		if velocity.length() > hard_ceiling:
			velocity = velocity.normalized() * hard_ceiling
	# Settle into orbit: the assist nudges a coasting ship toward the local
	# circular-orbit velocity, so releasing the throttle near a planet catches
	# you into orbit instead of spiralling in. Throttle / strafe / boost
	# disengage it, which is how you fly out of orbit.
	_apply_orbital_assist(delta)
	# Orbit detection — check every frame, emit signal on state change.
	_check_orbit()

	# Hand the final velocity to the world (M1b) before moving the node, so the
	# solver's swept test measures the same travel this node is about to make.
	# The node moves here, not in the world: this is a driven body that keeps
	# its tuned hand-integration.
	var carried := velocity + frame_velocity
	if _phys != null:
		_phys.velocity = carried
		_phys_velocity_written = carried
		_frame_velocity_written = frame_velocity
	global_position += carried * delta


func _strafe_vector(basis: Basis) -> Vector3:
	if command.strafe == Vector3.ZERO:
		return Vector3.ZERO
	return (basis.x * command.strafe.x + basis.y * command.strafe.y).limit_length(1.0)


# --- Boost ------------------------------------------------------------------

## The ship visibly rolls into yaw turns even without pilot roll input, so
## the player sees the hull lean in the direction of the turn.
func _update_visual_roll(delta: float) -> void:
	var yaw_input := command.yaw
	var wanted := -yaw_input * turn_rate * VISUAL_ROLL_FACTOR
	_visual_roll = lerpf(_visual_roll, wanted, clampf(delta * VISUAL_ROLL_SMOOTH, 0.0, 1.0))
	# Apply on top of whatever the pilot is commanding on the roll axis.
	var basis := global_transform.basis
	basis = basis.rotated(basis.z, _visual_roll * delta)
	global_transform = Transform3D(basis.orthonormalized(), global_transform.origin)


## Start a 180° yaw flip. Changes the ship's facing direction so the pilot
## can immediately fly the other way. One flip at a time.
func trigger_quick_turn() -> void:
	if _quick_turn_active:
		return
	_quick_turn_active = true
	_quick_turn_timer = QUICK_TURN_DURATION
	_quick_turn_remaining = QUICK_TURN_TOTAL
	Juice.shake(0.15)

## Apply the nose-over flip each physics frame. Rotates around the ship's local
## right axis (basis.x) so the nose leads over the top, ending inverted. The
## velocity is unchanged — with assist on, the ship then accelerates in the new
## (backward) forward direction.
func _update_quick_turn(delta: float) -> void:
	if not _quick_turn_active:
		return
	_quick_turn_timer -= delta
	if _quick_turn_timer <= 0.0:
		# Snap to exact 180° if we overshot.
		var basis := global_transform.basis
		var remaining := _quick_turn_remaining
		if remaining > 0.01:
			basis = basis.rotated(basis.x, remaining)
			global_transform = Transform3D(basis.orthonormalized(), global_transform.origin)
		_quick_turn_active = false
		_quick_turn_timer = 0.0
		_quick_turn_remaining = 0.0
		return
	var speed := QUICK_TURN_TOTAL / QUICK_TURN_DURATION
	var step := minf(speed * delta, _quick_turn_remaining)
	_quick_turn_remaining -= step
	var basis := global_transform.basis
	basis = basis.rotated(basis.x, step)
	global_transform = Transform3D(basis.orthonormalized(), global_transform.origin)


## Distance-based collision against all registered gravity bodies.
## The ship bounces back and sheds velocity on contact rather than passing
## through scenery. If the collision is fast enough, parts break off.
func _check_collision() -> void:
	var pos := global_position
	# Check every registered gravity body for collision.
	if gravity != null:
		for i in gravity.body_count():
			var body := gravity._bodies[i] if i < gravity._bodies.size() else null
			if body == null:
				continue
			var dist := pos.distance_to(body.position)
			var collision_r := body.radius + 5.0
			if dist < collision_r:
				var push_dir := (pos - body.position).normalized()
				if push_dir.length_squared() < 0.001:
					push_dir = Vector3.FORWARD
				global_position = body.position + push_dir * collision_r
				var impact_speed := velocity.dot(-push_dir)
				# Bounce with restitution. Always ensure the ship moves AWAY from
				# the surface — never sticks, never stops at 0 m/s.
				var new_vel := velocity.bounce(push_dir) * 0.6
				# Ensure minimum outward velocity proportional to impact speed.
				var min_speed := maxf(30.0, impact_speed * 0.4)
				var outward_speed := new_vel.dot(push_dir)
				if outward_speed < min_speed:
					new_vel += push_dir * (min_speed - outward_speed)
				velocity = new_vel
				var planet_spin := (push_dir.cross(velocity.normalized()) + Vector3(0.2, 0.5, 0.1)).normalized() * (impact_speed * 0.05)
				apply_impact_spin(planet_spin, clampf(impact_speed / 60.0, 0.2, 1.5))
				# Planet contacts are soft: the orbital assist (see
				# _apply_orbital_assist) should keep the ship out of the surface,
				# and a slow scrape here is a bump, not a hull breach. Only a
				# genuinely fast slam (three times the asteroid threshold) breaks
				# parts off.
				if impact_speed > 120.0:
					_on_impact(impact_speed)
	# Asteroids: check every rock. Expensive for a belt of 260, so we first
	# check if the ship is anywhere near the belt volume (centred at origin,
	# inner 900m, outer 2600m, height ±160m).
	if not _asteroid_data.is_empty():
		var dist_from_origin := Vector2(pos.x, pos.z).length()
		if dist_from_origin > 3000.0 or absf(pos.y) > 250.0:
			# Ship is well outside the belt — skip all 260 checks.
			pass
		else:
			for rock in _asteroid_data:
				var rock_pos: Vector3 = rock["position"]
				var rock_radius: float = rock["radius"]
				var rock_dist := pos.distance_to(rock_pos)
				var collision_radius := rock_radius + 3.0
				if rock_dist < collision_radius:
					var push_dir := (pos - rock_pos).normalized()
					if push_dir.length_squared() < 0.001:
						push_dir = Vector3.FORWARD
					global_position = rock_pos + push_dir * collision_radius
					var impact_speed := velocity.dot(-push_dir)
					velocity = velocity.bounce(push_dir) * 0.25
					var ast_lever := (pos - rock_pos).normalized()
					var ast_spin := (ast_lever.cross(velocity.normalized()) + Vector3(0.3, 0.4, -0.2)).normalized() * (impact_speed * 0.07)
					apply_impact_spin(ast_spin, clampf(impact_speed / 35.0, 0.3, 2.0))
					if impact_speed > 30.0:
						_on_impact(impact_speed)
					break  # one rock per frame


## Called by [method _check_collision] when the impact was fast enough to
## damage the ship. Delegates to the [DamageSystem] which breaks parts off
## and applies stat penalties.
func _on_impact(impact_speed: float) -> void:
	if _damage != null:
		_damage.handle_impact(impact_speed)


# --- Physics layer (M1b) ------------------------------------------------------

## Bind this model to the scene's PhysWorld as a driven ship body. [param radius]
## is the collision-sphere radius for the hull (from the design's bounds); the
## mass is read from [ShipStats]. Once bound, collisions run through the world:
## this model writes its velocity each step and reads the solver's impulses and
## spin back, and the fallback [_method _check_collision] is disabled.
##
## [param hull], when given, is a compound of ship-space spheres (see
## [method ShipView.collision_hull]) that replaces the single bounding sphere as
## the collision shape — a ship is a long box, and the sphere containing it is
## far too fat across the ship's short axes to collide believably. The radius
## passed alongside is still what every single-sphere reader sees.
func set_phys_world(world: PhysWorld, radius: float, hull: Array[Dictionary] = []) -> void:
	if _phys == null:
		_phys = PhysBody.new(_ship_mass(), radius)
		_phys.node = self
		_phys.driven = true
		_phys.layer = PhysBody.Layer.SHIP
		_phys.impacted.connect(_on_phys_impacted)
	else:
		_phys.radius = radius
	# set_hull re-derives the enclosing radius from the compound, so it goes last
	# of the two. An empty hull clears any previous one and leaves the radius.
	if hull.is_empty():
		_phys.hull.clear()
	else:
		_phys.set_hull(hull)
	_phys.mass = _ship_mass()
	_phys.velocity = velocity
	_phys_velocity_written = velocity
	phys_world = world
	if world != null and not world.bodies.has(_phys):
		world.add(_phys)

	# Synchronize with Godot physics engine for direct raycasts and rigid body contacts
	var col_body := get_node_or_null("GodotCollider") as AnimatableBody3D
	if col_body == null:
		col_body = AnimatableBody3D.new()
		col_body.name = "GodotCollider"
		col_body.collision_layer = 1 | 2
		col_body.collision_mask = 1 | 2 | 4
		col_body.sync_to_physics = false
		add_child(col_body)
		var cs := CollisionShape3D.new()
		cs.name = "ColShape"
		var ss := SphereShape3D.new()
		ss.radius = maxf(radius * 0.85, 1.5)
		cs.shape = ss
		col_body.add_child(cs)
	else:
		var cs := col_body.get_node_or_null("ColShape") as CollisionShape3D
		if cs != null and cs.shape is SphereShape3D:
			(cs.shape as SphereShape3D).radius = maxf(radius * 0.85, 1.5)


## Leave the world (ship destroyed, scene torn down). Idempotent.
func clear_phys_world() -> void:
	if phys_world != null and _phys != null:
		phys_world.remove(_phys)
	phys_world = null


## The RID of this ship's Godot physics collider (the "GodotCollider"
## [AnimatableBody3D] raycasts and direct-space queries actually hit), or an
## invalid [RID] if the model has not synced to a [PhysWorld] yet. Weapon fire
## uses this to exclude the shooter's own hull from its hit raycast.
func get_collider_rid() -> RID:
	var col_body := get_node_or_null("GodotCollider") as CollisionObject3D
	return col_body.get_rid() if col_body != null else RID()


## Re-derive this body's collision volume from rebuilt geometry, without touching
## the world binding or the mass.
##
## A look switch can move a hull's vertices (see [method StyleProfile.roundness],
## [member StyleProfile.chunkiness]), which moves the compound spheres
## [method ShipView.collision_hull] produces — so a body left holding the old ones
## collides along a silhouette it no longer has.
##
## Deliberately not [method set_phys_world]: that one is a *binding* call and
## multiplies mass by the scale factor every time it runs, so using it here would
## make a ship heavier on every style change.
func refresh_hull(radius: float, hull: Array[Dictionary]) -> void:
	if _phys == null:
		return
	_phys.radius = radius
	if hull.is_empty():
		_phys.hull.clear()
	else:
		_phys.set_hull(hull)


## The mass the physics layer resolves this ship with: the fully-loaded mass the
## stats computed, falling back to the hull stat when the ship carries no cargo.
func _ship_mass() -> float:
	if _stats == null:
		return 1.0
	var m := _stats.loaded_mass
	if m <= 0.0:
		m = _stats.get_stat("mass")
	return maxf(m, 0.5)


## Called by [PhysWorld] when this body took an impulse. Routes the severity of
## the hit — its closing speed, the number a pilot reads as "how hard did I hit
## that" — into the assist lockout, part damage and hitstop.
func _on_phys_impacted(other: PhysBody, impulse: float, point: Vector3, normal: Vector3, closing: float) -> void:
	if closing <= IMPACT_TOUCH_SPEED:
		return
	var profile := _active_profile()
	# Disengage the assists for the profile's window so the knock plays out.
	var lockout := profile.assist_lockout_on_impact if profile != null else 0.6
	if lockout > _assist_lockout:
		_assist_lockout = lockout

	# Collision & ramming damage factoring speed and durability
	_apply_collision_damage(other, impulse, point, closing)

	# Damage: a genuinely fast slam breaks parts off.
	if closing >= IMPACT_DAMAGE_SPEED and _damage != null:
		_damage.handle_impact(closing)

	# Calculate contact lever arm and impact torque to spin the ship:
	var lever := point - global_position
	var contact_torque := lever.cross(-normal) * (closing * 0.12)
	# If head-on or near-center, add tangential spin so ships reliably spin on impact:
	if contact_torque.length() < closing * 0.04:
		var side_axis := (-normal.cross(global_transform.basis.y) + Vector3(0.1, 0.4, -0.2)).normalized()
		contact_torque += side_axis * (closing * 0.08)
	var ooc_time := 0.0
	if closing >= IMPACT_DAMAGE_SPEED:
		ooc_time = clampf((closing - IMPACT_DAMAGE_SPEED) / 22.0, 0.4, 2.5)
	apply_impact_spin(contact_torque, ooc_time)

	# Impact freeze, scaled by the profile.
	if profile != null and profile.hitstop_scale > 0.0 and closing > IMPACT_TOUCH_SPEED * 2.0:
		var seconds := clampf(0.015 + closing * 0.0004, 0.02, profile.hitstop_max)
		Juice.hitstop(seconds * profile.hitstop_scale, 0.15)
	# A little shake so even a mid hit reads in the camera.
	# Any ship's bump, scaled by how near the camera it happened.
	Juice.shake(clampf(closing * 0.003, 0.08, 0.45) * AddonVfx.camera_falloff(global_position, 400.0), 0.3)
	_trigger_squash(profile, normal, closing)
	var other_radius := other.radius if other != null else 0.0
	var other_kinematic := other != null and other.kinematic
	collided.emit(closing, other_radius, other_kinematic)
	impacted.emit(other, normal, closing)


## A ram that landed without the hulls touching: the player's attack reach
## ([member JuiceSettings.player_ram_reach]) caught this ship. It takes the
## ram's damage, a shove along [param push] (unit, away from the rammer) and a
## spin, as if they had collided; the rammer takes nothing from it.
func take_reach_ram(rammer: PhysBody, point: Vector3, push: Vector3, closing: float) -> void:
	_apply_collision_damage(rammer, 0.0, point, closing)
	set_velocity(velocity + push * closing * 0.35)
	var lever := point - global_position
	apply_impact_spin(lever.cross(push) * (closing * 0.08) + push.cross(global_transform.basis.y) * (closing * 0.04))
	_trigger_squash(_active_profile(), -push, closing)


func is_player() -> bool:
	var p := get_parent()
	return p != null and not (p is AiShip)


func _durability() -> float:
	var hp := 160.0
	if _stats != null:
		hp = maxf(_stats.get_stat("hull_hp"), 80.0)
	hp *= JuiceSettings.hull_hp_mult
	var m := _ship_mass()
	var d := (hp + m * 2.5) * durability_mult
	if is_player():
		# Player parts have naturally higher strength and durability
		d *= JuiceSettings.player_durability_mult
	return d


func _other_durability(other: PhysBody) -> float:
	if other == null:
		return 150.0
	if other.layer == PhysBody.Layer.STATIC or other.layer == PhysBody.Layer.ROCK:
		return 3500.0  # Massive immovable rock or structure
	var other_mass := other.mass
	var other_d := 150.0 + other_mass * 2.5
	if other.node != null:
		var other_owner = other.node.get_parent()
		if other_owner != null:
			if not (other_owner is AiShip) and other_owner.has_method("take_damage"):
				other_d *= 2.5
			elif other_owner is AiShip:
				var ai: AiShip = other_owner as AiShip
				other_d = ai.max_hp + other_mass * 2.0
	return other_d


func _apply_collision_damage(other: PhysBody, _impulse: float, point: Vector3, closing: float) -> void:
	if closing < 10.0:
		return

	# Coefficients bumped (2.5→3.5 base, 1.4→2.0 past the >25 floor) per
	# playtest feedback wanting more "bump to destroy" — a faster ram should
	# hit noticeably harder, not just marginally. [member JuiceSettings.
	# ram_damage_mult] scales the whole result on top, for live tuning.
	var base_dmg := (closing - 8.0) * 3.5
	var my_d := _durability()
	var their_d := _other_durability(other)

	var my_speed := velocity.length()
	var their_speed := other.velocity.length() if other != null else 0.0
	var speed_ratio := (their_speed + 6.0) / (my_speed + their_speed + 12.0)

	var durability_ratio := sqrt(their_d / maxf(my_d, 10.0))
	var dmg := base_dmg * durability_ratio * speed_ratio * 1.5

	if closing > 25.0:
		dmg = maxf(dmg, (closing - 18.0) * 2.0)

	if is_player():
		# Heroic ramming advantage: player ship shrugs off self damage and hits harder
		dmg *= 0.25
	else:
		# If AI hit by player, AI takes devastating kinetic ramming crush
		if other != null and other.node != null:
			var other_parent = other.node.get_parent()
			if other_parent != null and not (other_parent is AiShip):
				dmg *= 2.0

	dmg *= JuiceSettings.ram_damage_mult
	# Movement-profile ramming dials: what the rammer deals, what this hull takes.
	dmg *= ram_taken_mult
	if other != null and other.node is FlightModel:
		dmg *= (other.node as FlightModel).ram_dealt_mult

	var p := get_parent()
	if p != null:
		if is_player() and p.has_method("take_damage"):
			p.take_damage(dmg, point)
		elif p is AiShip:
			var ai := p as AiShip
			# Popcorn enemies (see AiFactions.ArchetypeData.popcorn): any
			# ramming hit that reaches this point (closing >= 10 m/s) pops
			# them outright, rather than needing enough scaled damage to.
			if ai.archetype != null and ai.archetype.popcorn and JuiceSettings.popcorn_enemies_enabled:
				dmg = ai.hp + 1.0
			# Rammed by the player's own ship (its owner is the flight root, not
			# an AiShip) — counts as the player's hit for kill cams and stats.
			var rammer: Node = other.node.get_parent() if other != null and other.node != null else null
			var by_player := rammer != null and not (rammer is AiShip) and rammer.has_method("take_damage")
			ai.take_damage(dmg, by_player)
			if closing > 22.0 and ai.has_method("break_random_part"):
				ai.break_random_part()


## Cartoony impact deformation: flatten the hull along the hit normal and bulge
## it along the other two axes, then let [method _update_squash] ease it back
## to [constant Vector3.ONE] over [member PhysProfile.squash_recovery] seconds.
## Consumes [member PhysProfile.squash_amount]/[member squash_recovery] and is
## gated on [member StyleProfile.squash_enabled] — the style dial exists
## precisely so this deformation can be turned off for a "grounded" look.
func _trigger_squash(profile: PhysProfile, normal: Vector3, closing: float) -> void:
	if profile == null or profile.squash_amount <= 0.0:
		return
	var local_normal := (global_transform.basis.inverse() * normal).normalized()
	# How hard: scales with closing speed past the touch threshold, capped by the
	# profile's own dial so a plinking hit barely dents while a slam maxes out.
	var severity := clampf((closing - IMPACT_TOUCH_SPEED) / (IMPACT_DAMAGE_SPEED * 2.0), 0.0, 1.0)
	apply_squash(local_normal, severity, profile.squash_amount, profile.squash_recovery)


## Ship-local squash & stretch, [param local_dir] the impact axis (ship
## space), [param severity] 0..1. Shared by [method _trigger_squash] (a
## physical collision, with its own profile-driven amount/recovery) and
## [method squash_from_weapon_hit] (a weapon hit, no physics profile
## involved). Squashes along the hit axis and bulges the other two — volume
## roughly preserved rather than the hull just shrinking on impact.
func apply_squash(local_dir: Vector3, severity: float, amount: float, recovery: float) -> void:
	amount *= JuiceSettings.squash_strength
	if _visual == null or amount <= 0.0:
		return
	var style := StyleManager.instance().current_profile
	if not style or not style.squash_enabled:
		return
	if local_dir.length_squared() < 0.001:
		local_dir = Vector3.FORWARD
	var flat := maxf(1.0 - amount * severity * 0.4, 0.3)
	var bulge := 1.0 + amount * severity * 0.2
	var axis := local_dir.normalized().abs()
	_squash_scale = Vector3(
		lerpf(bulge, flat, axis.x), lerpf(bulge, flat, axis.y), lerpf(bulge, flat, axis.z)
	)
	_squash_recovery = maxf(recovery, 0.05)
	_visual.scale = _squash_scale
	_place_visual()


## Default squash amount/recovery for a weapon hit — tuned separately from a
## physical collision's [PhysProfile] dials since there is no "closing speed"
## for a raycast hit, only the damage dealt.
const WEAPON_SQUASH_AMOUNT := 0.3
const WEAPON_SQUASH_RECOVERY := 0.16


## Squash from taking weapon damage. [param world_dir] is world-space,
## typically the direction from the shot's origin (or hit point) toward the
## ship; [param severity] 0..1, usually the damage as a fraction of max HP.
func squash_from_weapon_hit(world_dir: Vector3, severity: float) -> void:
	apply_squash(
		global_transform.basis.inverse() * world_dir, severity,
		WEAPON_SQUASH_AMOUNT, WEAPON_SQUASH_RECOVERY
	)


## A knockback impulse to the ship's velocity, from a weapon hit or a strong
## weapon's own recoil. Distinct from [method _on_phys_impacted]'s
## solver-resolved impulse, which only fires for genuine physical contact.
##
## Queued, not applied at once: [method _feed_knockback] feeds it in over about
## [constant KNOCKBACK_SPREAD] seconds. The whole velocity change used to land
## in a single physics tick, which reads as the ship teleporting sideways. The
## total push is unchanged; only its onset is eased. Scaled by
## [member JuiceSettings.hit_knockback_strength].
##
## With [member JuiceSettings.knockback_visual] on (and a visual bound), the
## push moves only the drawn hull, sprung back home over [member
## JuiceSettings.knockback_return_time]. The velocity version is kept for
## A/B; in full assist the fly-by-wire cancels it within a few ticks, so the
## chase camera saw a jump and an immediate snap back.
func apply_knockback(world_dir: Vector3, strength: float) -> void:
	if world_dir.length_squared() < 0.001 or strength <= 0.0:
		return
	var push := strength * JuiceSettings.hit_knockback_strength
	if JuiceSettings.knockback_visual and _visual != null:
		# An impulse sized so a critically damped spring peaks at
		# RECOIL_METRES per unit of push, whatever the return time.
		var w := _recoil_omega()
		var local_dir := (global_transform.basis.inverse() * world_dir).normalized()
		_recoil_vel += local_dir * push * RECOIL_METRES * w * exp(1.0)
		return
	_knock_pending += world_dir.normalized() * push


## Stiffness of the visual knockback spring: settled in about
## [member JuiceSettings.knockback_return_time] seconds.
func _recoil_omega() -> float:
	return 4.0 / maxf(JuiceSettings.knockback_return_time, 0.05)


## Queued knockback velocity not yet applied — see [method apply_knockback].
var _knock_pending := Vector3.ZERO
const KNOCKBACK_SPREAD := 0.25


func _feed_knockback(delta: float) -> void:
	if _knock_pending == Vector3.ZERO:
		return
	var step := _knock_pending * (1.0 - exp(-delta * 4.0 / KNOCKBACK_SPREAD))
	velocity += step
	_knock_pending -= step
	if _knock_pending.length_squared() < 0.0001:
		_knock_pending = Vector3.ZERO


## Eases [member Node3D.scale] on [member _visual] back toward
## [constant Vector3.ONE] every frame after a squash. Cheap no-op once settled.
func _update_squash(delta: float) -> void:
	if _visual == null:
		return
	var recoiling := _recoil != Vector3.ZERO or _recoil_vel != Vector3.ZERO
	if _visual.scale.is_equal_approx(Vector3.ONE) and not recoiling:
		return
	var rate := clampf(delta / _squash_recovery, 0.0, 1.0)
	_visual.scale = _visual.scale.lerp(Vector3.ONE, rate)
	if _visual.scale.is_equal_approx(Vector3.ONE):
		_visual.scale = Vector3.ONE
	if recoiling:
		# Critically damped: out and home again with no overshoot. Substepped
		# so a stiff spring stays stable on a slow physics tick.
		var w := _recoil_omega()
		var steps := clampi(ceili(w * delta / 0.5), 1, 8)
		var h := delta / float(steps)
		for i in steps:
			_recoil_vel += (-w * w * _recoil - 2.0 * w * _recoil_vel) * h
			_recoil += _recoil_vel * h
		_recoil = _recoil.limit_length(RECOIL_MAX)
		if _recoil.length_squared() < 1e-6 and _recoil_vel.length_squared() < 1e-4:
			_recoil = Vector3.ZERO
			_recoil_vel = Vector3.ZERO
	_place_visual()


## Put [member _visual] where its squash and recoil say: scaled about
## [member squash_pivot] rather than its own origin, plus the recoil offset.
func _place_visual() -> void:
	var s := _visual.scale
	var pivot_shift := squash_pivot - squash_pivot * s
	_visual.position = _visual_rest_pos + pivot_shift + _recoil


## At the start of each physics step, take back what the solver did to this
## ship's body last step: the knocked velocity becomes this frame's base, and
## any spin the solver wrote is folded into the induced tumble (then cleared so
## it cannot accumulate). Also decays the assist-lockout window.
func _pull_solver_state(delta: float) -> void:
	if _assist_lockout > 0.0:
		_assist_lockout = maxf(_assist_lockout - delta, 0.0)
	if _phys == null:
		return
	# Only take the solver's copy back when it is not the one we handed it. The
	# world never integrates a driven body, so a value that differs is a
	# collision impulse and has to be read; a value that matches means nothing
	# touched us, and any velocity written since the last step — a spawn orbit, a
	# teleport, [method set_velocity] — stands instead of being silently reverted
	# before it is ever integrated.
	if _phys.velocity != _phys_velocity_written:
		velocity = _phys.velocity - _frame_velocity_written
	if _phys.angular != Vector3.ZERO:
		_tumble = (_tumble + _phys.angular).limit_length(TUMBLE_MAX)
		_phys.angular = Vector3.ZERO


## How fast an induced tumble decays right now: fast while full assist is flying
## (it damps the wobble away), slow on manual or damping — and the ship is
## effectively manual during the lockout window, so the knock is actually seen.
func _spin_damp_now() -> float:
	var profile := _active_profile()
	if profile == null:
		return SPIN_DAMP_ASSIST if assist_mode == 2 else SPIN_DAMP_FREE
	if assist_mode == 2 and _assist_lockout <= 0.0:
		return profile.spin_damp_assist
	return profile.spin_damp_induced


func _active_profile() -> PhysProfile:
	if phys_world != null:
		return phys_world.profile
	return null


## Settle into orbit. In full assist, while coasting (no throttle / strafe /
## boost) under gravity near a body, gently steer velocity toward the local
## circular-orbit velocity — radial component driven to zero, tangential driven
## to sqrt(GM/r). Releasing the throttle near a planet therefore catches you
## into a stable orbit instead of spiralling in; pressing the throttle or
## boosting disengages it and the fly-by-wire accelerates you out of the orbit.
func _apply_orbital_assist(delta: float) -> void:
	# Assume this ship is not being held; every early return below leaves the
	# fast-orbit pull switched off, which is what makes the dial apply to ships
	# in orbit and to nothing else.
	_orbital_hold_boost = 1.0
	if assist_mode != 2:
		return
	if gravity == null or gravity.mode == GravitySystem.GravityMode.OFF:
		return
	# A recent impact disengages orbital assist too: a ship knocked toward a
	# planet should visibly fall for a moment, not be silently re-circularised
	# the instant it stops touching the throttle (§3.1 #6).
	if _assist_lockout > 0.0:
		return
	# No-pull gravity has no radial force to orbit against; catching you onto a
	# circular rail would just drift you outward, so the assist stands down.
	if not gravity.pull_enabled:
		return
	# Throttle past the deadzone, strafe or boost means the pilot is really
	# flying — leave orbit. A light throttle tap stays inside the deadzone and the
	# orbit holds.
	if absf(command.throttle) > ORBIT_THROTTLE_DEADZONE or command.strafe != Vector3.ZERO or command.boost:
		return
	# The speed gate below is what tells "coasting in orbit" from "streaking past
	# on a fly-by", and a fast orbit is legitimately several times the circular
	# speed — so it has to be measured against the same dial the target is.
	var boost := _fast_orbit_factor()
	if velocity.length() > ORBITAL_ASSIST_MAX_SPEED * boost:
		return
	var body := gravity.find_dominant_body(global_position)
	if body == null:
		return
	var to_body := body.position - global_position
	var dist := to_body.length()
	var min_r := body.radius * ORBITAL_ASSIST_MIN_R
	var max_r := body.relevant_range * maxf(gravity.range_multiplier, 0.1)
	if dist < min_r or dist > max_r:
		return

	var radial := to_body / dist
	var v_rad := velocity.dot(radial)
	var v_tan_vec := velocity - radial * v_rad
	var v_tan := v_tan_vec.length()
	var v_orbit := gravity.orbit_velocity(body, dist)

	# Tangential direction: keep the ship's own orbit plane; fall back to the
	# gravity system's tangent if the ship has no tangential motion at all
	# (e.g. dropping straight down).
	var tangent := Vector3.ZERO
	if v_tan > 0.001:
		tangent = v_tan_vec / v_tan
	else:
		var fallback := gravity.circular_orbit_velocity(body, global_position)
		if fallback.length_squared() < 0.001:
			return
		tangent = fallback.normalized()

	var target := tangent * (v_orbit * boost)
	var rate := clampf(delta * orbital_assist_rate, 0.0, 1.0)
	# Tell the gravity step above how hard to pull: k², but *k as the ship is
	# actually flying it*, not as the dial asks for. A circle taken at k times the
	# circular speed needs k² times the pull, so handing the ship the dial's full
	# k² while it is still accelerating through the slower circles would drag it
	# inward through the spin-up — the fine print behind "the same circle, just
	# sooner". Held to the ratio of its own tangential speed to circular, the pull
	# grows under the ship exactly as its speed does, and the radius holds still
	# the whole way up. Only read back while the assist keeps holding, so a fast
	# orbit that gets flown out of returns to ordinary gravity at once.
	var held := clampf(v_tan / maxf(v_orbit, 0.001), 1.0, boost)
	_orbital_hold_boost = held
	velocity = velocity.lerp(target, rate)


## The fast-orbit dial's multiplier for this ship right now — 1.0, a true
## circular orbit, unless the player has switched it on (see [member
## Session.fast_orbits]). Read by [method _apply_orbital_assist] for the orbit's
## speed and by [method _check_orbit] to judge the orbit in the gravity system's
## own frame rather than the boosted one.
func _fast_orbit_factor() -> float:
	if not Session.fast_orbits:
		return 1.0
	return maxf(Session.orbit_speed_scale, 1.0)


## Check if the ship is in a stable orbit around any gravitating body.
## Emits [signal orbit_changed] on state transitions so FlightRoot can
## show debug text. Runs every physics frame — cheap for ≤5 bodies.
func _check_orbit() -> void:
	if gravity == null or gravity.mode == GravitySystem.GravityMode.OFF:
		if _in_orbit:
			_in_orbit = false
			orbit_changed.emit(_orbit_body_name, false)
			_orbit_body_name = ""
		return

	# Use dominant body selection — the body producing the most local
	# acceleration. This naturally handles moons orbiting planets
	# instead of the sun, without any is_planet flag.
	var best_body := gravity.find_dominant_body(global_position)

	if best_body == null:
		if _in_orbit:
			_in_orbit = false
			orbit_changed.emit(_orbit_body_name, false)
			_orbit_body_name = ""
		return

	var in_orbit_now := gravity.is_in_orbit(best_body, global_position, velocity / _fast_orbit_factor())
	var dist_to_body := global_position.distance_to(best_body.position)
	var speed := velocity.length() / _fast_orbit_factor()
	var v_orbit := gravity.orbit_velocity(best_body, dist_to_body)
	var v_diff := absf(speed - v_orbit)
	var pct_off := (v_diff / v_orbit * 100.0) if v_orbit > 0.0 else 0.0
	_orbit_log_timer += get_physics_process_delta_time()
	if _orbit_log_timer >= 1.0:
		_orbit_log_timer = 0.0
		# Debug-only: one line per ship per second, off by default because the
		# console flush stutters windowed runs. KEY_H (gravity viz) turns it on.
		if Session.debug_orbit_log:
			print("[ORBIT] %s dist=%.0fm speed=%.0f m/s v_orbit=%.0f m/s (%.0f%% off) %s" % [
				best_body.name, dist_to_body, speed, v_orbit, pct_off,
				"IN ORBIT" if in_orbit_now else "not in orbit"
			])
	# Hysteresis so the status doesn't flicker: "in orbit" needs a short solid
	# stretch to appear, and once gained it takes a few seconds out of band to
	# be declared lost. An elliptical orbit swings past the band every loop —
	# without this it flips "gained"/"lost" on every pass.
	if in_orbit_now:
		_orbit_lost_time = 0.0
		if not _in_orbit:
			_orbit_solid_time += get_physics_process_delta_time()
			if _orbit_solid_time >= ORBIT_GAIN_TIME:
				_orbit_solid_time = 0.0
				_in_orbit = true
				_orbit_body_name = best_body.name
				orbit_changed.emit(_orbit_body_name, true)
	else:
		_orbit_solid_time = 0.0
		if _in_orbit:
			_orbit_lost_time += get_physics_process_delta_time()
			if _orbit_lost_time >= ORBIT_LOSE_TIME:
				_orbit_lost_time = 0.0
				_in_orbit = false
				orbit_changed.emit(_orbit_body_name, false)
				_orbit_body_name = ""
		else:
			_orbit_lost_time = 0.0


## Cycle gravity strength through the preset steps.
func cycle_gravity_strength() -> float:
	var idx := GRAVITY_STRENGTH_STEPS.find(gravity_strength)
	if idx < 0:
		idx = 1  # Default to 1.0
	idx = (idx + 1) % GRAVITY_STRENGTH_STEPS.size()
	gravity_strength = GRAVITY_STRENGTH_STEPS[idx]
	return gravity_strength


func _update_boost(delta: float) -> void:
	var wants := command.boost and command.throttle > 0.05
	# Boost is bought from the same capacitor the guns fire from, so a pilot who
	# runs everywhere at full burn has nothing left to shoot with. Refusing the
	# boost rather than letting it run the capacitor negative keeps that trade
	# visible instead of mysterious.
	if wants and _systems != null:
		if _systems.energy <= 0.5:
			wants = false
		else:
			_systems.energy = maxf(_systems.energy - BOOST_DRAIN * delta, 0.0)
	boost_level = lerpf(boost_level, 1.0 if wants else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if boost_level < 0.02:
		boost_level = 0.0
	var boosting := boost_level > 0.01
	if boosting != _was_boosting:
		_was_boosting = boosting
		boost_changed.emit(boost_level)
