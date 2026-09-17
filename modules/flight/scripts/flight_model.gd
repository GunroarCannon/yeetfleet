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

## True when the throttle sets a speed to hold and the ship follows its nose.
## 0 = manual, 1 = damping, 2 = assist (full fly-by-wire).
## Assist is the default now: the player spawns in orbit and assist's "coasting"
## rule (see _integrate_translation) leaves an un-throttled ship alone under
## gravity, so the orbit is held without fighting it.
var assist_mode := 2
## Legacy helper: true when full assist is on.
var assist := true

## Current world velocity, m/s.
var velocity := Vector3.ZERO
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

## An induced tumble is capped so a lucky glancing hit cannot spin the ship so
## fast it becomes unrecoverable or nauseating.
const TUMBLE_MAX := 5.0
## Approach speed (m/s) below which a contact is a touch, not a crash.
const IMPACT_TOUCH_SPEED := 6.0
## Approach speed at which a hit starts breaking parts off. One number where the
## pre-M1 code had a per-scenery split (30 for rocks, 120 for planets); the
## profile is where this belongs once the lab can tune it.
const IMPACT_DAMAGE_SPEED := 60.0

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
	"turn_mult": 1.0,
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


## Drop all motion. Used when the scene restarts the ship rather than reloading.
func halt() -> void:
	velocity = Vector3.ZERO
	angular = Vector3.ZERO
	_tumble = Vector3.ZERO
	_assist_lockout = 0.0
	boost_level = 0.0
	if _phys != null:
		_phys.velocity = Vector3.ZERO
		_phys.angular = Vector3.ZERO
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


# --- Rotation ---------------------------------------------------------------

func _integrate_rotation(delta: float) -> void:
	var wanted := Vector3(
		command.pitch * turn_rate,
		command.yaw * turn_rate,
		command.roll * turn_rate * ROLL_FACTOR
	)
	# Spool towards the commanded rate on each axis, then damp any axis the pilot
	# is not asking anything of. Two separate steps rather than one blended one,
	# because damping an axis you are actively commanding is what makes a ship
	# feel like it is fighting you.
	var spool := clampf(delta / turn_spool, 0.0, 1.0)
	angular = angular.lerp(wanted, spool)

	var damp := SPIN_DAMP_ASSIST if assist_mode == 2 else (SPIN_DAMP_ASSIST * 0.6 if assist_mode == 1 else SPIN_DAMP_FREE)
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

	if ctl == 2:
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
	if _phys != null:
		_phys.velocity = velocity
	global_position += velocity * delta


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
	phys_world = world
	if world != null and not world.bodies.has(_phys):
		world.add(_phys)


## Leave the world (ship destroyed, scene torn down). Idempotent.
func clear_phys_world() -> void:
	if phys_world != null and _phys != null:
		phys_world.remove(_phys)
	phys_world = null


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
func _on_phys_impacted(_other: PhysBody, _impulse: float, _point: Vector3, _normal: Vector3, closing: float) -> void:
	if closing <= IMPACT_TOUCH_SPEED:
		return
	var profile := _active_profile()
	# Disengage the assists for the profile's window so the knock plays out. The
	# window is set, never shortened: a second hit inside it keeps the ship
	# reeling rather than resetting the timer mid-fall.
	var lockout := profile.assist_lockout_on_impact if profile != null else 0.6
	if lockout > _assist_lockout:
		_assist_lockout = lockout
	# Damage: a genuinely fast slam breaks parts off. Only the player has a
	# [DamageSystem]; AI ships (configured with none) just take the knock.
	if closing >= IMPACT_DAMAGE_SPEED and _damage != null:
		_damage.handle_impact(closing)
	# Impact freeze, scaled by the profile. OFF by default in flight unless the
	# profile or reduce-motion lets it through — calling it is the wiring; Juice
	# holds the final say.
	if profile != null and profile.hitstop_scale > 0.0 and closing > IMPACT_TOUCH_SPEED * 2.0:
		var seconds := clampf(0.015 + closing * 0.0004, 0.02, profile.hitstop_max)
		Juice.hitstop(seconds * profile.hitstop_scale, 0.15)
	# A little shake so even a mid hit reads in the camera.
	Juice.shake(clampf(closing * 0.002, 0.05, 0.35), 0.3)
	_trigger_squash(profile, _normal, closing)


## Cartoony impact deformation: flatten the hull along the hit normal and bulge
## it along the other two axes, then let [method _update_squash] ease it back
## to [constant Vector3.ONE] over [member PhysProfile.squash_recovery] seconds.
## Consumes [member PhysProfile.squash_amount]/[member squash_recovery] and is
## gated on [member StyleProfile.squash_enabled] — the style dial exists
## precisely so this deformation can be turned off for a "grounded" look.
func _trigger_squash(profile: PhysProfile, normal: Vector3, closing: float) -> void:
	if _visual == null or profile == null or profile.squash_amount <= 0.0:
		return
	var style := StyleManager.instance().current_profile
	if not style or not style.squash_enabled:
		return
	var local_normal := (global_transform.basis.inverse() * normal).normalized()
	if local_normal.length_squared() < 0.001:
		local_normal = Vector3.FORWARD
	# How hard: scales with closing speed past the touch threshold, capped by the
	# profile's own dial so a plinking hit barely dents while a slam maxes out.
	var severity := clampf((closing - IMPACT_TOUCH_SPEED) / (IMPACT_DAMAGE_SPEED * 2.0), 0.0, 1.0)
	var flat := 1.0 - profile.squash_amount * severity * 0.4
	var bulge := 1.0 + profile.squash_amount * severity * 0.2
	# Squash along the hit axis, bulge the other two — volume roughly preserved
	# rather than the hull just shrinking on impact.
	var axis := local_normal.abs()
	_squash_scale = Vector3(
		lerpf(bulge, flat, axis.x), lerpf(bulge, flat, axis.y), lerpf(bulge, flat, axis.z)
	)
	_squash_recovery = maxf(profile.squash_recovery, 0.05)
	_visual.scale = _squash_scale


## Eases [member Node3D.scale] on [member _visual] back toward
## [constant Vector3.ONE] every frame after a squash. Cheap no-op once settled.
func _update_squash(delta: float) -> void:
	if _visual == null or _visual.scale.is_equal_approx(Vector3.ONE):
		return
	var rate := clampf(delta / _squash_recovery, 0.0, 1.0)
	_visual.scale = _visual.scale.lerp(Vector3.ONE, rate)


## At the start of each physics step, take back what the solver did to this
## ship's body last step: the knocked velocity becomes this frame's base, and
## any spin the solver wrote is folded into the induced tumble (then cleared so
## it cannot accumulate). Also decays the assist-lockout window.
func _pull_solver_state(delta: float) -> void:
	if _assist_lockout > 0.0:
		_assist_lockout = maxf(_assist_lockout - delta, 0.0)
	if _phys == null:
		return
	velocity = _phys.velocity
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
	# Tell the gravity step above how hard to pull: the dial's k², for as long as
	# this ship is actually being held (see the pull in [method
	# _integrate_translation]). Only read back while the assist keeps holding, so
	# a fast orbit that gets flown out of returns to ordinary gravity at once.
	_orbital_hold_boost = boost
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
