## An AI-controlled ship: a full [FlightModel] + [SystemsSim] stack driven by
## [AiBehaviour], assembled from a random preset in the [PartLibrary].
##
## Each AI ship is a complete ship — real geometry, real stats, real plumes and
## projectiles. It participates in the same physics, collision and damage systems
## as the player's ship. The only difference is that its [FlightModel.command]
## is written by a behaviour tree rather than by a human.
##
## AI ships are spawned by [AiSpawner] and live as children of [FlightRoot].
## They are intentionally simple — no dialogue, no mission logic, no loot —
## because the point is to populate the world, not to build a game loop.
## Combat behaviour (firing at the player) is included so the damage system and
## the whole juice stack have a real test target beyond asteroids.
class_name AiShip
extends Node3D

## Emitted when this ship is destroyed, so the spawner can replace it.
signal destroyed(ship: AiShip)
## A comic mark over the ship: "!" (it noticed an enemy, or it is going
## down) or "?" (someone it didn't count as an enemy shot it). Rate-limited
## per ship and across all ships — see [method _mark].
signal marked(ship: AiShip, mark: String)

## The player's power-up boost on their guns and rams, × (1 = none). Written
## by the flight root while a boost runs; read in [method take_damage].
static var player_power_boost := 1.0
## The garage's GUNS upgrade on the player's ship (1.0 = none). Separate from
## [member player_power_boost], which a power-up resets to 1.0 when it ends.
static var player_upgrade_power := 1.0

## Maximum hit points. Set from the design's hull stat.
var max_hp := 200.0
var hp := 200.0
## True once destroyed if the player landed a hit within [constant
## PLAYER_KILL_WINDOW_MS] of the death — read by whoever hears [signal
## destroyed] (the kill cam, kill freeze).
var killed_by_player := false
## Real time (ms) of the last hit the player landed on this ship.
var _last_player_hit_ms := -100000
const PLAYER_KILL_WINDOW_MS := 2500
## Rate limit for [member JuiceSettings.freeze_on_enemy_hit], shared by every
## AI ship: a volley landing on a squad is one freeze, not one per hit.
static var _next_hit_freeze_ms := 0
## Flat HP cap for a "popcorn" archetype (see [method set_group_context]) --
## low enough that a ramming hit reliably one-shots it, keeping momentum-based
## ramming play fun instead of bogged down in a real ship's hit points.
const POPCORN_MAX_HP := 80.0
## Takes no damage at all while set (the tutorial's drones, until it is time
## to wreck one).
var invulnerable := false
## Takes nothing from the player's guns or rams (a ship the player is guarding:
## a stray volley or a bounce off it must not lose the mission).
var player_proof := false
## [member scale_multiplier] from which a hull counts as a big ship: its death
## is the big blast, its fly-by the big one (see [FlightRoot]).
const BIG_SHIP_SCALE := 2.5

## The preset id this ship was built from, for display.
var preset_name := ""
## The faction id, for colour.
var faction_name := ""

var model: FlightModel
var systems: SystemsSim
var behaviour: AiBehaviour = null
var _hull_holder: Node3D
var _view: ShipView
## Part loss and its effect on the flight model — see [method break_random_part].
var _damage: DamageSystem = null
## Fire-power multiplier, cut each time a gun mount is lost.
var _weapon_mult := 1.0
## How many HP thresholds (a third each) have already cost this ship a part.
var _break_stage := 0
var _library: PartLibrary
var _design: ShipDesign
var _rng := RandomNumberGenerator.new()
var _alive := true

## Group context: set by [AiSpawner] after spawning.
var group_id := -1
var archetype: AiFactions.ArchetypeData = null
var _group_members_ref: Array = []  # Reference to the spawner's ship list

## How close the ship needs to be to the player to start shooting.
const WEAPON_RANGE := 500.0
## How far before the ship stops shooting.
const WEAPON_CEASE := 700.0
## Damage per second applied to an enemy in range and roughly aligned. Makes
## team-vs-team combat real (ships can actually destroy each other).
const WEAPON_DPS := 40.0
## Cooldown between bursts (seconds).
const FIRE_COOLDOWN := 0.3
var _fire_timer := 0.0
## The wind-up before a volley at the player ([AiTelegraph]): seconds into it
## (-1 = not charging), whether it has run (the burst may fire), and when this
## ship last fired — a pause longer than [constant TELEGRAPH_GAP_MS] needs a
## fresh warning.
var _tele_t := -1.0
var _tele_armed := false
var _last_shot_ms := 0
var _telegraph: AiTelegraph = null
const TELEGRAPH_GAP_MS := 900
## Attack pacing — see [method _paced_fire_allowed].
const BURST_MIN := 1.2
const BURST_MAX := 2.2
const REST_MIN := 1.6
const REST_MAX := 3.2
const ATTACK_SLOT_TTL_MS := 400
var _pace_bursting := false
var _pace_timer := 0.0
## Target instance id -> {ship instance id: slot expiry (ms)}, shared by every
## AI ship so they can take turns on the same target.
static var _attack_slots := {}

# --- Scenario rules (set by the flight's scenarios from [Difficulty], cleared
# when a scenario stops; free roam keeps the neutral values) ---

## The friendly ship a guard mission protects, or null. At most
## [member guard_max_attackers] ships go for it at once (by slot, like the
## attack slots); a ship within [member guard_player_range] of the player, or
## one whose own roll is past [member guard_share], goes for the player instead.
static var guard_ship: AiShip = null
static var guard_max_attackers := 2
static var guard_player_range := 0.0
static var guard_share := 1.0
## Ship instance id -> slot expiry (ms) on [member guard_ship].
static var _guard_slots := {}
const GUARD_SLOT_TTL_MS := 1500
## Enemies see the player this much nearer than they are (1 = as they are),
## so they come for the player rather than the nearest wingman.
static var player_focus := 1.0
## True while the player's ship is wrecked: nobody keeps shooting at the wreck.
## Written by FlightRoot on death and on respawn.
static var player_down := false
## Damage the player's wingmen deal, × (1 = full).
static var ally_damage_mult := 1.0
## Attack slots on the player, overriding [member JuiceSettings.ai_max_attackers] (-1 = don't).
static var max_attackers_override := -1
## Size every ship spawned from now on takes, × (a level's climb; 1 = none).
static var spawn_scale := 1.0
## Reference to the player's ship, set by [AiSpawner]. Used for detection
## distance checks and combat targeting.
var player_ref: Node3D = null

## Team and aggression, used by the AI test arena. team_id 0 = None/neutral.
var team_id := 0:
	set(val):
		team_id = val
		_apply_team_faction(val)

## Teams this ship attacks. Empty = no team warfare configured (the pre-arena
## behaviour, where aggressive ships just hunt the player).
var aggressive_to: Array[int] = []

## Reference to the [AiSpawner], so the ship can enumerate other live ships and
## pick the nearest enemy to engage.
var spawner_ref: Node = null
## Set by FlightRoot while the player is piloting this ship; the spawner skips
## tick_ai for a paused ship so the player's inputs are not overwritten.
var _ai_paused := false
## A ballistic orbit probe (see [AiSpawner.spawn_ballistic_satellite]): excluded
## from the spawner's distance-based despawn so it stays in view for orbit tests.
var is_satellite := false
## A carrier-grade mother ship: huge, and periodically launches normal-size
## fighters from the spawner. See [member scale_multiplier].
var is_mother := false
## Extra size on top of [member Session.ship_scale]. 1 = a normal hull; a mother
## ship uses a large multiplier so it towers over everything around it.
var scale_multiplier := 1.0
## Countdown until this mother launches its next fighter, seconds.
var _launch_timer := 2.0
const MOTHER_LAUNCH_INTERVAL := 5.0
## The enemy this ship currently has a weapons lock on, or null. Set whenever a
## target is inside firing range; read by the HUD to bracket ships that are
## locked onto someone, mirroring the player's own lock bracket.
var locked_enemy: Node3D = null
## The enemy [method tick_ai] picked this frame — whatever [method _find_enemy]
## settled on, which is the player's ship when nothing on a hostile team is
## closer. Kept because "who is this ship after" is a question the scene asks
## outside the AI tick, for the floating indicator over a ship coming for the
## player (see [method is_aggroed_to_player]).
var current_target: Node3D = null
## How aggressive this ship is (1 = the norm): shorter rests between bursts,
## faster fire, more frequent yeets. Set by [method set_threat].
var threat := 1.0
## A hull preset id to fly (ship_families.json) instead of a random design;
## set before [method initialise].
var design_preset := ""
## This ship's own 0..1 roll against [member guard_share].
var _guard_roll := randf()
## How far above the hull centre a reaction emote spawns from (see [method
## _emote]) -- cached once the hull is assembled, from its own bounds.
var _emote_height := 1.0

## How this ship stands toward the player, for the interaction marker's
## colour (see [method attitude_to_player]).
enum Attitude { HOSTILE, WARY, FRIENDLY, HARMLESS }
## Real time (ms) this ship last tangled with the player: shot them, was shot
## by them, came after them, or came close. See [method interacted_recently].
var _interacted_ms := -1000000
## Real time (ms) this ship last landed a hit on the player.
var _hit_player_ms := -1000000
## Real time (ms) the *player* last went after this ship — shot it or locked
## it. Only that counts as being chased (see [method _update_chase_assist]):
## a ship merely coming for the player is not being hunted by them.
var _engaged_ms := -1000000
## The chase-assist carry currently lent to this ship (see
## [method _update_chase_assist]), eased so it never jerks the hull.
var _chase_carry := Vector3.ZERO
## The launch magnet's drift into the player's path (see [method drift_toward]).
var _path_drift := Vector3.ZERO
var _drift_asked_ms := 0
const PATH_DRIFT_MAX := 70.0
## Earliest real time (ms) the next non-lethal hit explosion may go off.
var _next_hit_boom_ms := 0
## Set on a ship spawned for the player to fly (the flight test's "fly as"):
## never culled for range, and freed when the player hands it back.
var is_pilot_vessel := false
## The flight root while the player is flying this ship (see [method
## FlightRoot.take_control]); hits on it then go through the player's own
## rules ([method FlightRoot.pilot_damage]) instead of an enemy's.
var pilot_host: Node = null
## Shots this ship may still fire at the player from out of their view — see
## [method fire_gate]. Refilled only while it is out of view.
var _offview_tokens := 2.0
## Game time since this ship last thought (see [method AiSpawner._think]).
var _think_lag := 0.0
## What [method _update_combat] is shooting at this tick.
var _combat_target: Node3D = null
## A ship this close to the player counts as having tangled with them.
const INTERACT_RANGE := 180.0

# --- Shield veil, EMP freeze, comic marks ---

## What the shield veil can still soak, and its full strength (0 = no veil).
var shield_hp := 0.0
var shield_max := 0.0
var _veil: ShieldBubble = null
## Real time (ms) an EMP freeze ends.
var _frozen_until_ms := 0
## The last enemy this ship noticed (its "!"), and when it may mark again.
var _noticed: Node3D = null
var _next_mark_ms := 0
## No two marks anywhere closer together than this, ms.
const MARK_GAP_MS := 700
static var _next_any_mark_ms := 0


func _init() -> void:
	# Seed from Session so two F5 restarts replay identical AI behaviour (§0.3).
	# Hashed with the instance ID so every ship gets a different stream without
	# calling randomize(), which would break determinism.
	_rng.seed = hash(Session.seed ^ get_instance_id())


func _ready() -> void:
	add_to_group("ai_ships")
	# Moved on physics ticks (this node mirrors its model there), so drawn
	# between ticks when physics interpolation is on. The flight scene's root
	# has it off for everything moved per frame; ships opt back in.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON


## Build this ship from a random preset. Called once after [method add_child]
## completes (the subtree must be readied before [SystemsSim] can bind).
func initialise(library: PartLibrary, spawn_xform: Transform3D, ai_player: Node3D) -> void:
	_library = library
	player_ref = ai_player
	global_transform = spawn_xform
	# Random phase offset so a squad spawned in the same frame doesn't volley in
	# lockstep every [constant FIRE_COOLDOWN] thereafter -- see the jitter added
	# on every reset in [method _update_combat] for the rest of that fix.
	_fire_timer = randf_range(0.0, FIRE_COOLDOWN)

	# Build a completely random ship: random chassis, random parts per socket,
	# random faction paint. Every AI ship is unique.
	if design_preset != "":
		_design = library.build_preset_design(design_preset)
	if _design == null:
		_design = _build_random_design(library)
	if _design == null:
		push_warning("AiShip: could not build random design")
		return
	preset_name = _design.design_name
	faction_name = _design.faction_id

	# Create the FlightModel (this IS the ship — it owns the transform).
	model = FlightModel.new()
	model.name = "Model"
	# The AI population's own speed dial, set before [method FlightModel.configure]
	# runs a few lines down: see [member FlightModel.speed_scale] for why the
	# model does not read it from Session itself.
	model.speed_scale = Session.npc_speed_scale
	# World-absolute: the AiShip node mirrors the model's transform in its own
	# _physics_process, so the model must not be a child whose local offset
	# compounds with that mirror every frame.
	model.top_level = true
	add_child(model)
	# Park the top_level model at the spawn point (it owns the transform and the
	# AiShip node just mirrors it).
	model.global_transform = spawn_xform

	# Hull holder for the ship geometry.
	_hull_holder = Node3D.new()
	_hull_holder.name = "Hull"
	model.add_child(_hull_holder)

	# Systems simulation — plumes, projectiles, energy.
	systems = SystemsSim.new()
	systems.name = "Systems"
	systems.fire_gate = fire_gate
	model.add_child(systems)

	# Assemble the ship geometry.
	_view = ShipAssembler.assemble(_design, library, 0.0, false, false)
	# The Ship-size setting scales every AI hull the same way as the player's; a
	# mother ship adds its own extra multiplier on top. Ordinary traffic also
	# occasionally runs big so the belt shows real size variety instead of a
	# uniform crowd — mothers and fighters set their own scale and skip this.
	if not is_mother and not is_satellite and is_equal_approx(scale_multiplier, 1.0) \
		and _rng.randf() < 0.18:
		scale_multiplier = _rng.randf_range(3.0, 6.5)
	if not is_mother and not is_satellite:
		scale_multiplier *= spawn_scale
	_view.apply_scale(Session.ship_scale * scale_multiplier)
	_hull_holder.add_child(_view.root)
	_emote_height = _view.aabb.size.y * 0.5 + 0.3
	model.out_of_control_changed.connect(_on_model_ooc_changed)
	model.boost_changed.connect(_on_model_boost_changed)

	# Bind systems and configure the flight model from the design's stats.
	# The hull holder is the visual, so hits squash and knock the drawn hull
	# (about the hull's own centre) the same way they do the player's.
	model.configure(_view.resolution.stats, systems, null, _hull_holder)
	model.squash_pivot = _view.aabb.get_center()
	# The same part-loss rules as the player's ship: losing an engine cuts
	# thrust, a wing costs turn rate and pulls to one side, a gun mount weakens
	# the ship's fire. Not passed to configure(): collisions keep going through
	# [method break_random_part] as before.
	_damage = DamageSystem.new()
	_damage.bind(_view, model, _hull_holder)
	_damage.part_broken.connect(_on_part_broken)
	systems.bind(_view, self)
	systems.sustain_fire = true
	systems.set_throttle(0.0)
	# Arm the ship appropriately for its size — a fighter never rolls a
	# planet-buster beam, and a mother ship is never stuck with a starter
	# pulse laser. Every AiShip used to default to WEAPONS[0] (pulse_laser)
	# regardless of size because nothing here ever called set_weapon_index.
	systems.set_weapon_index(SystemsSim.weapon_index_for_size(_weapon_size_class(), _rng))
	# Its own bullet-hell firing style and cadence (see [AiFirePatterns]).
	reroll_fire_pattern()

	# Read HP from stats, scaled by the global HP dial (see JuiceSettings) --
	# lower means faster kills across the whole AI population. [member archetype]
	# is not assigned until [method set_group_context] runs (after spawn), so
	# the popcorn cap is applied there instead of here.
	max_hp = maxf(_view.resolution.stats.get_stat("hull_hp"), 50.0) * JuiceSettings.hull_hp_mult \
		* JuiceSettings.enemy_hp_mult * Difficulty.v("enemy_hp")
	hp = max_hp
	_roll_shield()

	# Create and initialise the behaviour.
	behaviour = AiBehaviour.new()
	behaviour.ship_node_ref = self
	behaviour.asteroid_data_ref = _get_asteroid_data()
	behaviour.initialise(spawn_xform.origin)
	# Gravity will be set later by set_gravity() if available.

	# Set up collision: the AI ship bounces off planets/asteroids the same way
	# the player's ship does, via FlightModel._check_collision().
	if _view.resolution.stats.get_stat("sensor_range") > 0.0:
		model._asteroid_data = behaviour.asteroid_data_ref



## This ship's firing style (see [AiFirePatterns]); empty with
## [member JuiceSettings.ai_fire_patterns] off.
var fire_pattern: Dictionary = {}


## Roll (or with [param style], pick) this ship's firing style and hand it to
## its guns. Called at spawn; the flight test calls it again when the pattern
## dials change or when the player picks a style for a ship they fly.
func reroll_fire_pattern(style := "") -> void:
	if JuiceSettings.ai_fire_patterns or style != "":
		fire_pattern = AiFirePatterns.make(_rng, maxf(JuiceSettings.ai_fire_variety, 0.0 if style == "" else 1.0), style)
	else:
		fire_pattern = {}
	if systems != null:
		systems.fire_pattern = fire_pattern


## Which [constant SystemsSim.WEAPON_SIZE_TIERS] bucket this ship's weapon
## should be drawn from, derived from the same [member scale_multiplier] that
## already decides its physical size (set just above, before this runs).
## Mother ships (scale 16, see [method AiSpawner.spawn_mother]) are the only
## "capital" tier; the occasional big-traffic roll (scale 3..6.5, see the
## comment above [member scale_multiplier]'s use in this method) is "hauler";
## everything else is an ordinary fighter, mostly, with some corvettes for
## variety.
func _weapon_size_class() -> String:
	if scale_multiplier >= 10.0:
		return "capital"
	if scale_multiplier >= 2.0:
		return "hauler"
	return "fighter" if _rng.randf() < 0.6 else "corvette"


## Set the gravity system for this ship. Called by [AiSpawner] after spawning.
## The same gravity system is shared by all ships — player and AI alike.
func set_gravity(gravity_system: GravitySystem) -> void:
	if model != null:
		model.gravity = gravity_system
	if behaviour != null:
		behaviour.gravity_ref = gravity_system


## Give this ship's FlightModel a body in the shared [PhysWorld] (M1b), so it
## collides with the player, other ships and scenery through the same layer the
## player uses — a ship can now be knocked, not just bounce. Called by the
## spawner after [method initialise]. Passing null unbinds.
func set_phys_world(world: PhysWorld) -> void:
	if model == null:
		return
	if world == null:
		model.clear_phys_world()
		return
	var radius := 3.0
	var hull: Array[Dictionary] = []
	if _view != null:
		radius = maxf(_view.aabb.size.length() * 0.5, 3.0)
		# A compound of hull sections rather than the one bounding sphere, so a
		# long hull meets the player along the part that actually touched — see
		# [method ShipView.collision_hull]. Ship space, which is the body's space:
		# the view hangs off the model through an untransformed holder.
		hull = _view.collision_hull()
	model.set_phys_world(world, radius, hull)
	# A bigger hull is a heavier hull (mass ~ scale^2), so a scaled-up hauler or
	# mother reads as a wrecking ball instead of a balloon that every scout can
	# shove around. Normal-size ships keep their design mass.
	if scale_multiplier > 1.0 and model._phys != null:
		model._phys.mass *= scale_multiplier * scale_multiplier

	# Big ships (carriers, motherships, heavy haulers) get dedicated part-level
	# collision shapes so projectiles and small craft collide with specific parts.
	if (is_mother or scale_multiplier >= 1.5) and _view != null:
		_view.create_part_colliders(model)

	if Session.mesh_baking_enabled and _view != null:
		_view.enable_baked_mesh(true)


## Re-skin this ship for the current look and palette, and re-derive its collision
## hull from the geometry the new look produced. Called by [AiSpawner] when the
## global style changes.
##
## The hull is refreshed rather than left alone because a geometry dial moves
## vertices: a hull that just got fatter would otherwise keep colliding along its
## old, thinner silhouette.
func restyle() -> void:
	if _view == null:
		return
	_view.restyle()
	if model != null and model._phys != null:
		model.refresh_hull(maxf(_view.aabb.size.length() * 0.5, 3.0), _view.collision_hull())


## Called by [AiSpawner] after spawning to assign faction archetype and
## group membership. The archetype determines HOW the ship moves and fights
## as part of a group.
func set_group_context(
	group_id_val: int,
	archetype_val: AiFactions.ArchetypeData,
	group_members_val: Array
) -> void:
	group_id = group_id_val
	archetype = archetype_val
	_group_members_ref = group_members_val
	_apply_faction_paint()
	# Popcorn enemies (see [member AiFactions.ArchetypeData.popcorn]): a low
	# flat HP so momentum-based ramming actually pops them, on top of whatever
	# [constant JuiceSettings.hull_hp_mult] already did.
	if archetype != null and archetype.popcorn and JuiceSettings.popcorn_enemies_enabled:
		max_hp = minf(max_hp, POPCORN_MAX_HP)
		hp = minf(hp, max_hp)


## Repaint the hull's primary colour to the archetype's political faction —
## see [enum AiFactions.PoliticalFaction] and factions.md. A no-op for a
## neutral archetype (wildlife, anomalies, automation, solo drifters), which
## keeps its design's own varied colours instead of claiming a side. Accent
## and trim are left as the design rolled them, so ships of one faction still
## read as individuals up close while reading as one colour at a glance.
func _apply_faction_paint() -> void:
	if archetype == null or archetype.political_faction == AiFactions.PoliticalFaction.NONE:
		return
	if _design == null or _view == null:
		return
	_design.set_color("primary", AiFactions.faction_color(archetype.political_faction))
	_view.refresh_palette(_design)


## Feed the behaviour each frame. Called by [AiSpawner].
##
## The behaviour writes to [member FlightModel.command]. The actual physics
## integration happens in [FlightModel]._physics_process, which Godot calls
## automatically. [SystemsSim] reads the model's state in its own _process,
## same as the player's ship. This method only drives the command and fires
## weapons — it does not duplicate the physics pipeline.
func tick_ai(delta: float) -> void:
	if not _alive or model == null or behaviour == null or not is_inside_tree() or not model.is_inside_tree():
		return

	# Update detection — pick the nearest enemy (a ship on an aggressive team, or
	# the player). In the arena ships fight each other; in space (no teams set)
	# this falls back to hunting the player as before.
	if is_frozen():
		_tick_frozen(delta)
		return
	var target := _find_enemy()
	current_target = target
	if systems != null:
		systems.target_ref = target
	var target_pos := Vector3.ZERO
	var target_visible := false
	var target_forward := Vector3.FORWARD
	var target_velocity := Vector3.ZERO
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		target_pos = target.global_position
		target_visible = global_position.distance_to(target_pos) < AiBehaviour.DETECTION_RANGE
		target_forward = -target.global_transform.basis.z
		# Duck-typed: the player's FlightModel and an AiShip's model both carry
		# a world-space velocity; anything else just reads as stationary.
		var v: Variant = target.get("velocity")
		if v is Vector3:
			target_velocity = v

	if target == player_ref and target != null:
		if is_aggroed_to_player() or global_position.distance_to(target_pos) < INTERACT_RANGE:
			mark_interacted()
	# First sight of a new enemy: a "!".
	if target_visible and target != _noticed:
		_noticed = target
		_mark("!")

	behaviour.player_position = target_pos
	behaviour.player_visible = target_visible
	behaviour.player_forward = target_forward
	behaviour.player_velocity = target_velocity

	# Pass group context to the behaviour.
	behaviour.archetype_data = archetype
	behaviour.group_members = _group_members_ref
	behaviour.my_index_in_group = group_id
	behaviour.group_total = _group_members_ref.size()
	if _group_members_ref.size() > 0:
		var sum := Vector3.ZERO
		for m: AiGroupBehaviour.Member in _group_members_ref:
			sum += m.position
		behaviour.group_centre = sum / float(_group_members_ref.size())
		behaviour.leader_position = _group_members_ref[0].position

	# Get behaviour output and feed it to the flight model — unless this ship
	# is fighting by slingshot launches right now.
	var cmd: Dictionary = behaviour.update(
		delta, global_position, global_transform.basis, model.top_speed
	)
	if not _yeet_tick(delta, target, target_velocity) and not _sling_tick(delta, target, target_velocity):
		model.command.throttle = float(cmd.get("throttle", 0.0))
		model.command.yaw = float(cmd.get("yaw", 0.0))
		model.command.pitch = float(cmd.get("pitch", 0.0))
		model.command.roll = float(cmd.get("roll", 0.0))
		model.command.boost = bool(cmd.get("boost", false))

	# A mother ship periodically ejects a normal-size fighter that takes up its
	# fight. The spawner refuses when the live roster is full, so this just
	# retries on the next interval.
	if is_mother and _alive and spawner_ref != null and is_instance_valid(spawner_ref):
		_launch_timer -= delta
		if _launch_timer <= 0.0:
			_launch_timer = MOTHER_LAUNCH_INTERVAL
			spawner_ref.spawn_fighter_near(self)

	# Combat: fire at the chosen enemy if in range and roughly aligned.
	_update_combat(delta, target)


# --- Yeet combat ---

## This ship's dash attack ([YeetDash]), made the first time it is allowed one.
var _yeet: YeetDash = null
## The yeet wind-up's glow and aim line (its own, so the gun telegraph hiding
## itself every tick it isn't firing never blinks it).
var _yeet_tele: AiTelegraph = null


## [member JuiceSettings.yeet_combat]: in the player's view, dash at them now
## and then. Returns true while the dash owns the flight model's command.
func _yeet_tick(delta: float, target: Node3D, target_velocity: Vector3) -> bool:
	if not JuiceSettings.yeet_combat:
		if _yeet != null:
			_yeet.release()
		return false
	if _yeet == null:
		_yeet = YeetDash.new(self)
	return _yeet.tick(delta, target, target_velocity)


## Drop any yeet in progress (the player is taking this ship over).
func stop_yeet() -> void:
	if _yeet != null:
		_yeet.release()


## Draw the yeet wind-up toward [param aim_at], [param t] 0..1 through it
## (below 0: hide it).
func show_yeet_charge(aim_at: Vector3, t: float) -> void:
	if t < 0.0:
		if _yeet_tele != null:
			_yeet_tele.hide_charge()
		return
	if _yeet_tele == null:
		_yeet_tele = AiTelegraph.new()
		_yeet_tele.name = "YeetTelegraph"
		add_child(_yeet_tele)
	var r := 4.0
	if model != null and model.phys_body() != null:
		r = model.phys_body().radius
	_yeet_tele.show_charge(global_position - global_transform.basis.z * r * 0.9, aim_at, r * 1.3, t)


# --- Slingshot fighting ---

## This ship's slingshot cycle ([SlingRun]), made the first time it launches.
var _sling: SlingRun = null
## Rolled once: the ship slings when this is under [member
## JuiceSettings.ai_sling_share] (so moving the dial re-picks live).
var _sling_roll := randf()
var _sling_cooldown := randf_range(0.5, 2.0)

## Ramming damage a slinging AI ship deals.
const SLING_RAM_DEALT := 1.5
## Launch power reaches full at this many times its launch reach.
const SLING_REACH := 1.1


## When [member JuiceSettings.ai_slingshot] picks this ship: aim at the
## target's lead point, launch, ping-pong, recover, repeat. Returns true while
## it owns the flight model's command (the behaviour's output is skipped).
func _sling_tick(delta: float, target: Node3D, target_velocity: Vector3) -> bool:
	var slinging := JuiceSettings.ai_slingshot and _sling_roll < JuiceSettings.ai_sling_share 		and not is_satellite and not is_mother
	if not slinging:
		if _sling != null:
			_sling.release()
			model.ram_dealt_mult = 1.0
			_sling = null
		return false
	if _sling == null:
		_sling = SlingRun.new(model)
		model.ram_dealt_mult = SLING_RAM_DEALT
	_sling.tick(delta)
	model.command.throttle = 0.0
	model.command.roll = 0.0
	model.command.boost = false
	if _sling.state == SlingRun.State.READY:
		model.command.yaw = 0.0
		model.command.pitch = 0.0
		_sling_cooldown -= delta
		if _sling_cooldown <= 0.0 and target != null and is_instance_valid(target):
			_sling_cooldown = randf_range(1.5, 3.0)
			var reach := JuiceSettings.sling_power * maxf(model.top_speed, 40.0) * SLING_REACH
			var lead := TargetLeadReticle.calculate_lead_position(
				global_position, Vector3.ZERO, target.global_position, target_velocity, reach
			)
			var to := lead - global_position
			_sling.launch(to, clampf(to.length() / reach, 0.35, 1.0))
	return true


## The nearest ship to engage: the closest live ship (or the player) on a team
## this ship is aggressive to. With no team warfare configured (aggressive_to
## empty — the pre-arena case), the player is always fair game.
## Whether this ship is coming for the player right now: it has picked the
## player's ship as its enemy *and* its behaviour is steering at it. Read by the
## scene to float an indicator over the ships that are after you (see [method
## FlightRoot._update_aggro_indicators]).
##
## Pursuit and investigate both count. Investigate is the "I saw something, going
## to look" state and it steers at the last known player position, which for a
## pilot on the receiving end is the same message as an attack run: that one has
## noticed me and is closing. Everything else — patrol, formation, cruise, flee —
## means the ship is doing its own thing.
func is_aggroed_to_player() -> bool:
	if not _alive or behaviour == null or player_ref == null:
		return false
	if not is_instance_valid(player_ref) or current_target != player_ref:
		return false
	return behaviour.state == AiBehaviour.State.PURSUIT \
		or behaviour.state == AiBehaviour.State.INVESTIGATE


## Note that this ship just tangled with the player. See [method
## interacted_recently]; also called by the flight root (a lock-on, a hit).
func mark_interacted() -> void:
	_interacted_ms = Time.get_ticks_msec()


## The player went after this ship (a hit, a lock-on).
func mark_engaged() -> void:
	_engaged_ms = Time.get_ticks_msec()
	mark_interacted()


## This ship landed a hit on the player: it is hostile from here on.
func note_hit_player() -> void:
	_hit_player_ms = Time.get_ticks_msec()
	mark_interacted()


## Whether the player has tangled with this ship within [member
## JuiceSettings.interaction_memory] seconds. Drives the interaction marker
## and the chase assist.
func interacted_recently() -> bool:
	if not _alive:
		return false
	return Time.get_ticks_msec() - _interacted_ms <= int(JuiceSettings.interaction_memory * 1000.0)


## Whether this ship can hurt anyone at all: an orbit probe, a hull whose
## guns have all been shot off, or a purely civilian archetype cannot.
func can_attack() -> bool:
	if is_satellite or _weapon_mult < 0.05:
		return false
	if archetype != null and archetype.aggression <= 0.05:
		return false
	if systems != null and systems._get_effective_muzzles().is_empty():
		return false
	return true


## How this ship stands toward the player: [enum Attitude]. Friendly = on the
## player's team or not at war with it; harmless = cannot attack at all;
## hostile = coming for the player, has shot them, or is at war with their
## team; wary = armed and not (yet) after them — it may turn.
func attitude_to_player() -> int:
	var p_team := 0
	if player_ref != null and is_instance_valid(player_ref):
		p_team = int(player_ref.get_meta("team", 0))
	if p_team != 0 and team_id == p_team:
		return Attitude.FRIENDLY
	# Harmless by design (a civilian, a probe), not merely out of working guns: a
	# fighter whose guns were shot off is still the enemy, and used to turn
	# grey mid-fight.
	if is_satellite or _weapon_mult < 0.05 or (archetype != null and archetype.aggression <= 0.05):
		return Attitude.HARMLESS
	var memory_ms := int(JuiceSettings.interaction_memory * 1000.0)
	if Time.get_ticks_msec() - _hit_player_ms <= memory_ms or is_aggroed_to_player():
		return Attitude.HOSTILE
	if p_team != 0 and aggressive_to.has(p_team):
		return Attitude.HOSTILE
	if team_id != 0 and not aggressive_to.is_empty() and (p_team == 0 or not aggressive_to.has(p_team)):
		return Attitude.FRIENDLY
	return Attitude.WARY


## How far above this ship's own origin a floating marker has to sit to clear the
## hull: the top of the assembled geometry plus [param margin]. Falls back to the
## margin alone when the ship has no geometry to measure.
func marker_height(margin: float) -> float:
	if _view == null:
		return margin
	return _view.aabb.end.y + margin


func _find_enemy() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := INF
	var player_ok := false
	var player_d := INF
	if spawner_ref != null and is_instance_valid(spawner_ref):
		var ships: Array = spawner_ref._ships
		for other in ships:
			if not is_instance_valid(other) or not other._alive or other == self or not other.is_inside_tree():
				continue
			if other.team_id != 0 and aggressive_to.has(other.team_id):
				var d := global_position.distance_squared_to(other.global_position)
				if d < best_d:
					best_d = d
					best = other
	if player_ref != null and is_instance_valid(player_ref) and player_ref.is_inside_tree():
		var player_team_id: int = int(player_ref.get_meta("team", 0))
		if aggressive_to.is_empty() or (player_team_id != 0 and aggressive_to.has(player_team_id)):
			player_ok = true
			player_d = global_position.distance_squared_to(player_ref.global_position)
			# Seen nearer than it is: enemies hunt the player, not the wingmen.
			var focus := player_focus if player_team_id != 0 else 1.0
			if player_d * focus * focus < best_d:
				best = player_ref
	if best != null and best == guard_ship:
		if not _may_attack_guarded(player_ok, player_d):
			return player_ref
	else:
		_guard_slots.erase(get_instance_id())
	return best


## Whether this ship may go for the guarded ship (see [member guard_ship]):
## not with the player close by or with its roll on the player, and only
## while one of the guard slots is free. Holds (renews) the slot when it may.
func _may_attack_guarded(player_ok: bool, player_d: float) -> bool:
	var me := get_instance_id()
	if player_ok and (player_d < guard_player_range * guard_player_range or _guard_roll >= guard_share):
		_guard_slots.erase(me)
		return false
	var now := Time.get_ticks_msec()
	for id: int in _guard_slots.keys():
		if _guard_slots[id] < now or not is_instance_id_valid(id):
			_guard_slots.erase(id)
	if not player_ok or _guard_slots.has(me) or _guard_slots.size() < guard_max_attackers:
		_guard_slots[me] = now + GUARD_SLOT_TTL_MS
		return true
	return false


## Clear the scenario rules back to free roam's.
static func clear_scenario_rules() -> void:
	guard_ship = null
	_guard_slots.clear()
	guard_player_range = 0.0
	guard_share = 1.0
	player_focus = 1.0
	ally_damage_mult = 1.0
	max_attackers_override = -1
	spawn_scale = 1.0


## Ships going for the guarded ship right now (for the checks).
static func guard_attackers() -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for id: int in _guard_slots:
		if _guard_slots[id] >= now and is_instance_id_valid(id):
			n += 1
	return n


## Make this ship [param t] times as aggressive as the norm: its guns fire
## faster and aim truer, its rests are shorter (see [method
## _paced_fire_allowed]) and it yeets more often (see [YeetDash]).
func set_threat(t: float) -> void:
	threat = maxf(t, 0.1)
	if fire_pattern.is_empty():
		return
	fire_pattern["rate_mult"] = float(fire_pattern.get("rate_mult", 1.0)) * sqrt(threat)
	fire_pattern["aim_error_deg"] = float(fire_pattern.get("aim_error_deg", 0.0)) / threat
	if systems != null:
		systems.fire_pattern = fire_pattern


## Arm this ship from gun class [param gun_class] (0 fighter … 3 capital:
## [constant SystemsSim.WEAPON_SIZE_TIERS]) — a railgun or a planet-buster
## at the top.
func arm(gun_class: int) -> void:
	if systems == null:
		return
	var c := clampi(gun_class, 0, SystemsSim.WEAPON_SIZE_TIERS.size() - 1)
	systems.set_weapon_index(SystemsSim.weapon_index_for_size(SystemsSim.WEAPON_SIZE_TIERS[c], _rng))
	systems.fire_pattern = fire_pattern


# --- Off-screen fire allowance -------------------------------------------------

## Whether the player's camera has this ship in view (its centre inside the
## frustum). No camera (a headless check) counts as in view.
func in_player_view() -> bool:
	var vp := get_viewport() if is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp != null else null
	return cam == null or cam.is_position_in_frustum(global_position)


## Out of view, the allowance refills at [member
## JuiceSettings.offscreen_shots] per [member JuiceSettings.offscreen_window]
## seconds, up to that many. In view the clock stops.
func _tick_offview(delta: float) -> void:
	if in_player_view():
		return
	var cap := JuiceSettings.offscreen_shots
	_offview_tokens = minf(_offview_tokens + delta * cap / maxf(JuiceSettings.offscreen_window, 1.0), cap)


## [member SystemsSim.fire_gate]: may this ship fire right now? Against the
## player from out of their view, only while it has allowance left — each
## firing frame spends one. Ships fighting ships, a ship the player is
## flying, and everything with the cheat off are never held.
func fire_gate() -> bool:
	if is_frozen():
		return false
	if player_down and not (_combat_target is AiShip):
		return false
	if not JuiceSettings.cheat_offscreen_mercy or pilot_host != null:
		return true
	var t := _combat_target
	if t == null or not is_instance_valid(t) or t is AiShip:
		return true
	if in_player_view():
		return true
	if _offview_tokens >= 1.0:
		_offview_tokens -= 1.0
		return true
	return false


func _update_combat(delta: float, target: Node3D) -> void:
	_combat_target = target
	if JuiceSettings.cheat_offscreen_mercy:
		_tick_offview(delta)
	if not _alive:
		systems.set_firing(false)
		locked_enemy = null
		return
	if player_down and not (target is AiShip):
		target = null
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		systems.set_firing(false)
		locked_enemy = null
		_fire_timer = 0.0
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	# Inside firing range the ship has a weapons lock: it rotates onto the target
	# (the behaviour's steering does that) and the HUD can bracket it like the
	# player's own lock. Outside range the lock drops so stale brackets vanish.
	locked_enemy = target if dist < WEAPON_RANGE else null
	# Roughly aligned (the enemy is ahead) as well as in range.
	var ahead := (-global_transform.basis.z).dot(to_target.normalized())
	var should_fire := dist < WEAPON_RANGE and ahead > 0.2
	# Debugger: passive enemies still fly and lock, but never shoot the player.
	if JuiceSettings.enemies_passive and not (target is AiShip):
		should_fire = false
	# Yeeting, a ship fires once as it launches and then holds fire.
	var yeeting := _yeet != null and _yeet.state != YeetDash.State.IDLE
	if yeeting:
		should_fire = should_fire and _yeet.take_volley()
		if should_fire:
			_fire_timer = 0.0
	else:
		if should_fire and JuiceSettings.ai_attack_pacing:
			should_fire = _paced_fire_allowed(delta, target)
		should_fire = _telegraph_gate(delta, target, should_fire)
	# Evasive break countermeasure deployment (defensive flak & chaff)
	if behaviour != null and behaviour.state == AiBehaviour.State.EVASIVE_BREAK:
		if _fire_timer <= 0.0:
			_fire_timer = 0.55
			var audio := SpaceAudio.instance()
			var flak_pos := global_position - global_transform.basis.z * 10.0
			if audio != null:
				audio.play_flak_detonation(flak_pos)
			Juice.burst(BurstPresets.Preset.VAPOUR, Transform3D(global_transform.basis, flak_pos), 2.0, Color(0.55, 0.55, 0.6, 0.65))
			Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(global_transform.basis, flak_pos), 1.5, Color(1.0, 0.65, 0.2))

	if should_fire:
		_fire_timer = maxf(_fire_timer - delta, 0.0)
		if _fire_timer <= 0.0:
			systems.set_firing(true)
			# Jittered, not a flat reset: several AI acquiring the same target in
			# the same frame (a squad spotting the player at once) would otherwise
			# stay locked to the exact same firing phase forever, so every ship in
			# range unloads on the same frame every [constant FIRE_COOLDOWN] --
			# playtest read as "too many enemies shoot at once" and the resulting
			# pile of simultaneous [SpaceAudio] voices as noise, not gunfire.
			_fire_timer = (FIRE_COOLDOWN + randf_range(-0.06, 0.08)) \
				/ maxf(JuiceSettings.enemy_fire_rate_mult, 0.1)
			# One discrete damage tick per shot landing, not continuous per-frame
			# DPS — a ship held in a firing arc for a whole second used to call
			# take_damage (and its full hit-VFX/sound/damage-number chain) ~60
			# times; this caps it at 1/FIRE_COOLDOWN while keeping the same
			# average DPS (WEAPON_DPS * FIRE_COOLDOWN every FIRE_COOLDOWN sec).
			_apply_combat_damage(target, FIRE_COOLDOWN)
	else:
		systems.set_firing(false)
		_fire_timer = maxf(_fire_timer - delta, 0.0)



## The warning before a volley at the player: a burst that wants to start
## first charges for [member JuiceSettings.enemy_telegraph] seconds (the glow
## and aim line of [AiTelegraph]), then fires. Returns whether to fire now.
## Ship-vs-ship fights and a zero dial fire at once, as before.
func _telegraph_gate(delta: float, target: Node3D, want: bool) -> bool:
	var wind := JuiceSettings.enemy_telegraph
	var now := Time.get_ticks_msec()
	if target is AiShip or wind <= 0.0 or not _alive:
		_stop_telegraph()
		return want
	if not want:
		if now - _last_shot_ms > TELEGRAPH_GAP_MS:
			_tele_armed = false
		_stop_telegraph()
		return false
	if _tele_armed:
		_last_shot_ms = now
		return true
	_tele_t = maxf(_tele_t, 0.0) + delta
	if _telegraph == null:
		_telegraph = AiTelegraph.new()
		_telegraph.name = "Telegraph"
		add_child(_telegraph)
	var r := 4.0
	if model != null and model.phys_body() != null:
		r = model.phys_body().radius
	var nose := global_position - global_transform.basis.z * r * 0.9
	_telegraph.show_charge(nose, target.global_position, r, _tele_t / wind)
	if _tele_t < wind:
		return false
	_tele_armed = true
	_last_shot_ms = now
	_stop_telegraph()
	return true


func _stop_telegraph() -> void:
	_tele_t = -1.0
	if _telegraph != null:
		_telegraph.hide_charge()


## Attack pacing: fire in bursts with rests between, and against the player
## only while holding one of [member JuiceSettings.ai_max_attackers] attack
## slots. Without it every ship in range fired nonstop, all at once — a
## bombardment with no gaps to fight back in, rather than a series of attack
## runs the player can read and answer. Ship-vs-ship fights (the arena) skip
## the slot limit and only keep the burst rhythm.
func _paced_fire_allowed(delta: float, target: Node3D) -> bool:
	_pace_timer -= delta
	if _pace_timer <= 0.0:
		_pace_bursting = not _pace_bursting
		# A firing style brings its own rhythm: a sniper's long wait, a
		# burster's short stabs. Without one, the shared defaults.
		var on: Vector2 = fire_pattern.get("burst_on", Vector2(BURST_MIN, BURST_MAX))
		var off: Vector2 = fire_pattern.get("burst_off", Vector2(REST_MIN, REST_MAX))
		if _pace_bursting:
			_pace_timer = randf_range(on.x, on.y)
		else:
			_pace_timer = randf_range(off.x, off.y) * JuiceSettings.ai_rest_mult / threat
	if not _pace_bursting:
		_release_attack_slot(target)
		return false
	if target is AiShip:
		return true
	return _claim_attack_slot(target)


## Hold (or renew) an attack slot on [param target]. Slots expire on their
## own, so a ship that dies or loses the target never blocks one for long.
func _claim_attack_slot(target: Node3D) -> bool:
	var now := Time.get_ticks_msec()
	var key := target.get_instance_id()
	var holders: Dictionary = _attack_slots.get(key, {})
	for id: int in holders.keys():
		if holders[id] < now:
			holders.erase(id)
	_attack_slots[key] = holders
	var me := get_instance_id()
	var cap := max_attackers_override if max_attackers_override >= 0 else int(JuiceSettings.ai_max_attackers)
	if holders.has(me) or holders.size() < cap:
		holders[me] = now + ATTACK_SLOT_TTL_MS
		return true
	return false


func _release_attack_slot(target: Node3D) -> void:
	var holders: Dictionary = _attack_slots.get(target.get_instance_id(), {})
	holders.erase(get_instance_id())


func _apply_combat_damage(target: Node3D, delta: float) -> void:
	var dmg := WEAPON_DPS * delta * _weapon_mult
	if target is AiShip:
		(target as AiShip).take_damage(dmg, false, systems)
	elif target != null:
		# With real projectiles the shots themselves land (or miss) — no dice.
		if JuiceSettings.ai_real_projectiles:
			return
		# Shots at the player: the debugger's accuracy and damage dials.
		if _rng.randf() > JuiceSettings.enemy_accuracy:
			return
		dmg *= JuiceSettings.enemy_damage_mult
		# A ship the player is flying takes the hit as itself.
		if target.get_parent() is AiShip:
			(target.get_parent() as AiShip).take_damage(dmg, false, systems)
			return
		# The shooter's own position, passed as the hit point: it gives the
		# direction the shot came from, and [method FlightRoot.take_damage]
		# pulls it onto the hull on that side before spawning anything there.
		# Through take_enemy_fire when there is one, so the off-screen mercy
		# applies to the dice too.
		var sink := SystemsSim._enemy_fire_sink(target)
		if sink != null:
			sink.take_enemy_fire(dmg, global_position, systems)
		elif target.has_method("take_damage"):
			target.take_damage(dmg, global_position)
		else:
			Juice.flash(Color("ff6644"), 0.06, 0.1)


## Apply damage to this ship. Called by [FlightModel] when it hits something
## fast enough, or when a projectile strikes it.
##
## [param from_player]: the player's own guns or ram landed this hit. Those
## hits take the debugger's damage-dealt dial and one-hit-kill switch, and
## mark the ship so its death counts as the player's kill.
func take_damage(amount: float, from_player := false, source: Object = null) -> void:
	if not _alive or invulnerable or (from_player and player_proof):
		return
	# The player is flying this ship: it takes hits as the player would.
	if pilot_host != null and is_instance_valid(pilot_host) and not from_player:
		amount = pilot_host.pilot_damage(self, amount, source)
		if amount <= 0.0:
			return
	if _hit_by_non_enemy(from_player, source):
		_mark("?")
	# A wingman's hit: turned down, so the wingmen can't win the fight alone.
	if not from_player and ally_damage_mult != 1.0 and _hit_by_player_side(source):
		amount *= ally_damage_mult
	if from_player:
		amount *= JuiceSettings.player_damage_dealt_mult * JuiceSettings.player_power * player_power_boost \
				* player_upgrade_power
		# A gun hit comes with its systems sim as the source; a ram with none.
		if source != null:
			amount *= JuiceSettings.player_gun_damage
		if JuiceSettings.one_hit_kills:
			amount = maxf(amount, hp + 1.0)
		_last_player_hit_ms = Time.get_ticks_msec()
		mark_engaged()
		if JuiceSettings.kill_freeze_frame and JuiceSettings.freeze_on_enemy_hit \
				and amount < hp and _last_player_hit_ms >= _next_hit_freeze_ms:
			_next_hit_freeze_ms = _last_player_hit_ms + 250
			Juice.freeze(JuiceSettings.freeze_enemy_hit_ms / 1000.0, JuiceSettings.freeze_depth)
	amount = _soak_shield(amount)
	if amount <= 0.0:
		return
	hp -= amount
	_emote("ouch", 0.9)

	# Visible, felt damage before death: a part comes off at each third of HP
	# lost, plus a small chance on any hit once badly hurt. A ship can limp on
	# with a missing engine or wing instead of only ever dying whole.
	if hp > 0.0:
		var stage := int((1.0 - hp / maxf(max_hp, 1.0)) * 3.0)
		while _break_stage < mini(stage, 2):
			_break_stage += 1
			break_random_part()
		if hp < max_hp * 0.45 and _rng.randf() < 0.12:
			break_random_part()

	# Weapon-hit juice: squash and knockback, mirroring the player's own
	# take_damage (FlightRoot). No exact hit point reaches this call, so the
	# impulse uses a random direction rather than a true impact vector.
	if model != null:
		var hit_severity := clampf(amount / maxf(max_hp, 1.0), 0.1, 1.0)
		var hit_dir := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized()
		if JuiceSettings.hit_squash_stretch:
			model.squash_from_weapon_hit(hit_dir, hit_severity)
		if JuiceSettings.hit_knockback:
			model.apply_knockback(hit_dir, clampf(amount * 0.12, 1.0, 14.0))

	# Explosions are not only for deaths: a heavy hit always blows a chunk
	# of hull, a lighter one sometimes does (see [member
	# JuiceSettings.hit_explosions]). Rate-limited per ship so a stream of
	# small shots is a crackle of pops, not a wall of fire.
	if JuiceSettings.hit_explosions and hp > 0.0 and is_inside_tree():
		var heavy := amount >= max_hp * 0.18
		var now_ms := Time.get_ticks_msec()
		if now_ms >= _next_hit_boom_ms and (heavy or _rng.randf() < JuiceSettings.hit_explosion_chance):
			_next_hit_boom_ms = now_ms + (90 if heavy else 220)
			_hit_explosion(heavy)

	if hp <= 0.0:
		_destroy()


## Pop a reaction emote off this ship (see [method Whimsy.emote]) -- a
## triggered, one-shot "pops out and fades" reaction rather than the old
## permanently-mounted face. Launches mostly upward off the hull with a little
## sideways scatter so repeated pops in a scrap don't all overlap on screen.
## Earliest tick (ms) the next emote may pop — one at a time, not one per hit.
var _next_emote_ms := 0


## A small blast somewhere on the hull — see the hit explosion in [method
## take_damage]. Off-centre, so a burst of them reads as the ship being
## chewed up rather than one spot flashing.
func _hit_explosion(heavy: bool) -> void:
	var world_host: Node = get_parent()
	if world_host == null or not world_host.is_inside_tree():
		return
	var hull_r := _view.aabb.size.length() * 0.5 if _view != null else 3.0
	var off := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * hull_r * 0.8
	var pos := global_position + global_transform.basis * off
	var size := (0.9 if heavy else 0.45) * clampf(scale_multiplier, 0.5, 4.0) * JuiceSettings.hit_explosion_size
	if size <= 0.0:
		return
	AddonVfx.explosion(world_host, pos, size, false, Color("ff8844"))
	Juice.light_pop(pos, Color("ffaa55"), 6.0 * size, 0.1)
	var audio := SpaceAudio.instance()
	if audio != null and heavy:
		audio.play_blast(pos, &"explosion_small")


func _emote(expression: String, hold := 1.0) -> void:
	if not is_inside_tree() or not JuiceSettings.enemy_emotes:
		return
	# The chance dial thins the everyday reactions; the death "dizzy" always
	# shows while enemy emotes are on at all.
	if expression != "dizzy" and _rng.randf() > JuiceSettings.enemy_emote_chance:
		return
	var now := Time.get_ticks_msec()
	if now < _next_emote_ms and expression != "dizzy":
		return
	_next_emote_ms = now + int(hold * 700.0)
	var xform := global_transform
	var pos := xform.origin + xform.basis.y * _emote_height
	var side := xform.basis.x * randf_range(-0.6, 0.6)
	var launch_dir := (xform.basis.y + side).normalized()
	var world_host := get_parent()
	if world_host == null:
		return
	# Sized from the whole hull and riding along with it — see FlightRoot._emote.
	var hull_r := _view.aabb.size.length() * 0.5 if _view != null else 3.0
	var size := clampf(hull_r * 0.9, 1.5, 12.0) * JuiceSettings.emote_size
	if size <= 0.0:
		return
	Whimsy.emote(world_host, pos, expression, launch_dir, size, hold, model)


func _on_model_ooc_changed(active: bool) -> void:
	if active:
		_emote("dizzy", 1.6)


func _on_model_boost_changed(level: float) -> void:
	if level > 0.0:
		_emote("grin", 1.2)


## Break one random part off (see [method DamageSystem.break_random_part]).
## The part becomes collidable debris and its effect lands on the flight
## model: an engine cuts thrust, a wing costs turn rate and pulls to one side,
## a cockpit wrecks handling. Visuals in [method _on_part_broken].
func break_random_part() -> void:
	if _damage == null or not _alive:
		return
	# Debris goes to the world, not under this ship: it must outlive the hull.
	_damage.debris_parent = get_parent()
	_damage.break_random_part(0.5)


## A part came off: explode at the break, and weaken the guns if it was one.
func _on_part_broken(broken: DamageSystem.BrokenPart, effects: Array) -> void:
	var host := get_parent()
	if host != null and host.is_inside_tree():
		AddonVfx.explosion(host, broken.world_pos, 0.6 * clampf(scale_multiplier, 1.0, 4.0), false, Color("ff9944"))
	var audio := SpaceAudio.instance()
	if audio != null:
		audio.play_blast(broken.world_pos, &"explosion_small")
	var xform := Transform3D(Basis(), broken.world_pos)
	Juice.burst(BurstPresets.Preset.SPARKS, xform, 1.2, Color("ff9933"))
	Juice.burst(BurstPresets.Preset.DEBRIS, xform, 0.8)
	Juice.light_pop(broken.world_pos, Color("ffaa44"), 4.0, 0.12)
	for e: DamageSystem.DamageEffect in effects:
		if e.effect_type == DamageSystem.EffectType.WEAPON_LOST:
			_weapon_mult *= 0.6


func _destroy() -> void:
	if not _alive:
		return
	_alive = false
	locked_enemy = null
	_stop_telegraph()
	if _yeet != null:
		_yeet.release()
	killed_by_player = Time.get_ticks_msec() - _last_player_hit_ms <= PLAYER_KILL_WINDOW_MS
	# A last "seeing stars" reaction before the parts scatter, and now and
	# then a "!" as it goes.
	_emote("dizzy", 1.2)
	if _rng.randf() < 0.5:
		_mark("!", true)
	if _veil != null and is_instance_valid(_veil):
		_veil.pop_out()
	_veil = null
	systems.set_firing(false)
	systems.set_throttle(0.0)
	systems.set_boost(false)
	# Leave the physics world: a destroyed ship is a corpse, not a collider.
	if model != null:
		model.clear_phys_world()

	# A baked hull (Session.mesh_baking_enabled) draws the whole ship as one
	# mesh with every part's own mesh hidden: scattering the parts then threw
	# invisible debris while the intact baked hull stayed put — the kill cam
	# swooped onto a ship that looked alive, which later just vanished. Back
	# to the parts first, so they are what flies apart.
	if _view != null and _view.baked_mesh_instance != null and is_instance_valid(_view.baked_mesh_instance):
		_view.enable_baked_mesh(false)
		_view.baked_mesh_instance.queue_free()
		_view.baked_mesh_instance = null
	# Scatter all remaining parts into tumbling debris
	if _view != null and not _view.part_nodes.is_empty():
		var world_parent := get_parent()
		for path in _view.part_nodes.keys():
			var node: Node3D = _view.part_nodes.get(path)
			if node != null and is_instance_valid(node):
				var orig_xform := node.global_transform
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				for child in node.get_children():
					if child is Area3D:
						child.collision_layer = 0
						child.collision_mask = 0
				var out_dir := (orig_xform.origin - global_position).normalized()
				if out_dir.length_squared() < 0.01:
					out_dir = Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized()
				var speed := _rng.randf_range(20.0, 52.0)
				var drift_vel := out_dir * speed + (model.velocity * 0.4 if model != null else Vector3.ZERO)
				# Real, collidable wreckage — the same treatment
				# DamageSystem gives the player's own broken-off parts (see
				# DebrisRegistry.wrap_rigidbody) — rather than a decorative
				# node that drifts through everything.
				DebrisRegistry.wrap_rigidbody(
					node, orig_xform, world_parent, drift_vel,
					Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)),
				)
		_view.part_nodes.clear()
		_view.part_meshes.clear()
		_view.part_materials.clear()

	# Explosion juice: the full stack, with BinbunVFX addon explosion layer.
	if is_inside_tree():
		var my_pos := global_position
		var my_xform := global_transform
		var world_host: Node = get_parent()
		if world_host != null and world_host.is_inside_tree():
			# Scale by the ship's own size — a mothership's death should not
			# look the same as a small fighter's.
			var death_scale := 2.5 * clampf(scale_multiplier, 1.0, 4.0) * JuiceSettings.kill_explosion_size
			# The bang: a fighter's is a normal blast, a big hull's the big one.
			var audio := SpaceAudio.instance()
			if audio != null:
				audio.play_blast(my_pos, &"explosion_big" if scale_multiplier >= BIG_SHIP_SCALE else &"explosion")
			if death_scale > 0.0:
				AddonVfx.explosion(world_host, my_pos, death_scale, true, Color("ff8844"))
			# A chance (the Juice panel's dial, 33% by default) of a bigger
			# secondary blast a beat later — real ships breaking apart don't
			# all detonate identically.
			if JuiceSettings.enemy_death_random_explosion and death_scale > 0.0 \
					and _rng.randf() < JuiceSettings.kill_explosion_chance:
				AddonVfx.nuke(world_host, my_pos, death_scale * 1.4, Color("ffaa44"))
			Whimsy.confetti(world_host, my_pos, clampf(scale_multiplier, 1.0, 5.0))
		Juice.burst(BurstPresets.Preset.RING_SPARK, my_xform, 2.5, Color("ffaa44"))
		Juice.burst(BurstPresets.Preset.SPARKS, my_xform, 2.5, Color("ff8844"))
		Juice.burst(BurstPresets.Preset.EMBERS, my_xform, 1.8)
		Juice.burst(BurstPresets.Preset.DEBRIS, my_xform, 1.5)
		Juice.burst(BurstPresets.Preset.VAPOUR, my_xform, 2.0)
		Juice.light_pop(my_pos, Color("ffcc66"), 12.0, 0.3)
		Juice.ring(my_xform, 4.0, Color("ffaa44"), 0.5)
		# A kill out across the map does not rattle the player's view.
		Juice.shake(0.5 * JuiceSettings.kill_shake * AddonVfx.camera_falloff(my_pos, 900.0))
		Juice.flash(Color("ff8844"), 0.4 * JuiceSettings.kill_flash, 0.3)
		# The player's own kills get the real freeze (unless a kill cam takes
		# the moment instead — see FlightRoot._on_ai_ship_destroyed); anyone
		# else's keep the old slight hitstop.
		if JuiceSettings.kill_freeze_frame:
			if killed_by_player and JuiceSettings.freeze_on_kill:
				Juice.freeze(JuiceSettings.freeze_kill_ms / 1000.0, JuiceSettings.freeze_depth)
			elif not killed_by_player:
				Juice.hitstop(0.04, 0.2)

	destroyed.emit(self)


## Sync SystemsSim with the FlightModel's live state after physics integration.
## FlightModel._physics_process computes throttle and boost; SystemsSim needs
## those same values for plume visuals. This mirrors what FlightRoot._physics_process
## does for the player's ship.
func _physics_process(_delta: float) -> void:
	if model == null or systems == null or not is_inside_tree() or not model.is_inside_tree():
		return
	systems.set_throttle(clampf(absf(model.command.throttle), 0.0, 1.0))
	systems.set_boost(model.command.boost)
	_update_chase_assist(_delta)
	# The FlightModel is the ship's transform owner; mirror its transform up to
	# the AiShip node so targeting, the roster and camera focus all read the
	# ship's real position (previously this node sat at spawn forever).
	global_transform = model.global_transform


## The chase-assist cheat ([member JuiceSettings.cheat_chase_assist]): a ship
## the player has gone after (shot or locked, within [member
## JuiceSettings.interaction_memory]), and is now pointing at, closing on and
## throttling toward, inside [member JuiceSettings.chase_assist_range], is
## carried along the player's line of travel at (most of) the player's speed.
## Never a friendly: a wingman is not being chased. It goes on the model's
## [member FlightModel.frame_velocity], not its velocity, so the ship does not
## turn to it and its own flying (assist, steering) never fights it — it is the
## world quietly keeping the quarry ahead of the hunter.
func _update_chase_assist(delta: float) -> void:
	var want := Vector3.ZERO
	var engaged := Time.get_ticks_msec() - _engaged_ms <= int(JuiceSettings.interaction_memory * 1000.0)
	if JuiceSettings.cheat_chase_assist and _alive and not _ai_paused and engaged \
			and player_ref != null and is_instance_valid(player_ref) and player_ref.is_inside_tree() \
			and attitude_to_player() != Attitude.FRIENDLY and _player_throttling():
		var v: Variant = player_ref.get("velocity")
		var p_vel: Vector3 = v if v is Vector3 else Vector3.ZERO
		var to_me := global_position - player_ref.global_position
		var dist := to_me.length()
		var reach := JuiceSettings.chase_assist_range
		var p_speed := p_vel.length()
		if dist > 1.0 and dist < reach and p_speed > 15.0:
			var dir_me := to_me / dist
			var facing := (-player_ref.global_transform.basis.z).dot(dir_me)
			if facing > 0.75 and p_vel.dot(dir_me) > 0.0:
				var along := p_vel / p_speed
				var need := p_speed - model.velocity.dot(along)
				if need > 0.0:
					var fade := clampf((reach - dist) / (reach * 0.35), 0.0, 1.0)
					var aim := smoothstep(0.75, 0.93, facing)
					want = along * need * JuiceSettings.chase_assist_strength * fade * aim
	_chase_carry = _chase_carry.lerp(want, 1.0 - exp(-delta * 3.0))
	if _chase_carry.length_squared() < 0.01 and want == Vector3.ZERO:
		_chase_carry = Vector3.ZERO
	if Time.get_ticks_msec() - _drift_asked_ms > 120:
		_path_drift = _path_drift.move_toward(Vector3.ZERO, PATH_DRIFT_MAX * delta)
	model.frame_velocity = _chase_carry + _path_drift


## The player's launch magnet picked this ship: it drifts toward [param point]
## on the player's path, gaining up to [param accel] m/s² while asked (capped
## at [constant PATH_DRIFT_MAX]), so it "happens" to cross it. On the model's
## [member FlightModel.frame_velocity] like the chase assist — its own flying
## never fights it — and it fades by itself once no longer asked.
func drift_toward(point: Vector3, accel: float, delta: float) -> void:
	if not _alive or model == null:
		return
	var off := point - global_position
	var d := off.length()
	var want := Vector3.ZERO
	if d > 1.0:
		want = off / d * minf(d * 1.5, PATH_DRIFT_MAX)
	_path_drift = _path_drift.move_toward(want, accel * delta)
	_drift_asked_ms = Time.get_ticks_msec()


## Whether the player is pushing on — throttle up or boosting — rather than
## coasting (an orbit, a drift): only then are they chasing anything.
func _player_throttling() -> bool:
	var cmd: Variant = player_ref.get("command")
	if cmd == null:
		return true
	return float(cmd.get("throttle")) > 0.2 or bool(cmd.get("boost"))


## Build a completely random ship design: random chassis, random parts in
func _apply_team_faction(t: int) -> void:
	if _library == null or _design == null:
		return
	var fid := ""
	match t:
		1: fid = "cobalt_vanguard"   # Blue
		2: fid = "crimson_toybox"    # Red
		3: fid = "amethyst_void"     # Purple
		4: fid = "solar_raiders"     # Orange
		5: fid = "emerald_warlords"  # Green
		_: fid = ""
	paint_as(fid)


## Repaint the hull in faction [param fid]'s colours ("" does nothing): a
## level named for a colour paints the ships it is about that colour.
func paint_as(fid: String) -> void:
	if fid == "" or _library == null or _design == null:
		return
	_library.apply_faction(_design, fid)
	faction_name = fid
	if _view != null:
		_view.restyle(false)


## Build a completely random design for an AI ship: random chassis, parts for
## every socket, random faction paint. Every AI ship is unique.
func _build_random_design(library: PartLibrary) -> ShipDesign:
	# Pick a random chassis.
	var chassis_list: Array[ShipPart] = library.chassis_list()
	if chassis_list.is_empty():
		push_warning("AiShip: no chassis parts available")
		return null
	var chassis: ShipPart = chassis_list[randi() % chassis_list.size()]
	var design := ShipDesign.create(chassis.id)

	# Cartoon factions: basic bold colors (Red, Orange, Blue, Green, Purple, Teal, Yellow)
	var cartoon_factions: Array[String] = [
		"crimson_toybox",   # Bold Red
		"solar_raiders",    # Bold Orange
		"cobalt_vanguard",  # Bold Blue
		"emerald_warlords", # Bold Green
		"amethyst_void",    # Bold Purple
		"cyber_teal",       # Bold Teal
		"vega_industrial",  # Bold Yellow
		"neon_turbo"        # Hot Magenta
	]
	var fid := ""
	match team_id:
		1: fid = "cobalt_vanguard"
		2: fid = "crimson_toybox"
		3: fid = "amethyst_void"
		4: fid = "solar_raiders"
		5: fid = "emerald_warlords"
		_:
			fid = cartoon_factions[randi() % cartoon_factions.size()]

	library.apply_faction(design, fid)

	# 50% chance for extra saturated cartoon toy pops on primary/accent/trim
	if randf() < 0.50:
		var hue := randf()
		var primary_col := Color.from_hsv(hue, randf_range(0.85, 1.0), randf_range(0.90, 1.0))
		var accent_col := Color.from_hsv(fmod(hue + randf_range(0.25, 0.45), 1.0), randf_range(0.88, 1.0), 1.0)
		var trim_col := Color.from_hsv(fmod(hue + 0.65, 1.0), randf_range(0.80, 0.95), randf_range(0.90, 1.0))
		design.set_color("primary", primary_col)
		design.set_color("accent", accent_col)
		design.set_color("trim", trim_col)
		design.material_preset = "gloss"

	# Fill every socket with a random compatible part. Required sockets
	# always get filled; optional sockets have a 50% chance.
	for _pass in 6:
		var res := design.resolve(library)
		var filled_any := false
		for entry: Dictionary in res.open_sockets:
			var socket: PartSocket = entry["socket"] as PartSocket
			if not socket.required and randf() > 0.5:
				continue
			var candidates: Array[ShipPart] = library.parts_for_socket(socket)
			if candidates.is_empty():
				continue
			var pick: ShipPart = candidates[randi() % candidates.size()]
			var path: String = String(entry["path"])
			if design.place_part(path, pick.id, library):
				filled_any = true
		if not filled_any:
			break
	# Generate a name from faction + chassis.
	var faction_label := "Unknown"
	if design.faction_id != "":
		var fdata: Dictionary = library.get_faction(design.faction_id)
		faction_label = String(fdata.get("name", "Unknown"))
	design.design_name = "%s %s" % [faction_label, chassis.display_name]
	return design



## Clean up and free this ship's resources.
func teardown() -> void:
	if _yeet != null and model != null:
		_yeet.release()
	_alive = false
	set_physics_process(false)
	set_process(false)
	if model != null:
		model.set_physics_process(false)
		model.set_process(false)
		model.clear_phys_world()
	if systems != null:
		systems.stop_all()
	if _view != null:
		_view.destroy()
	queue_free()


func _get_asteroid_data() -> Array:
	# Walk up to FlightRoot and read the SpaceScene's asteroid data.
	var root := get_parent()
	while root != null:
		if root is FlightRoot and root.space != null and root.space.has_meta("asteroid_data"):
			return root.space.get_meta("asteroid_data") as Array
		root = root.get_parent()
	return []


# --- Shield veil ---------------------------------------------------------------

## Some armed ships spawn with a veil ([member JuiceSettings.enemy_shields]).
func _roll_shield() -> void:
	if not JuiceSettings.enemy_shields or is_satellite or _view == null:
		return
	if _rng.randf() >= JuiceSettings.enemy_shield_chance:
		return
	give_shield(max_hp * JuiceSettings.enemy_shield_hp)


## Put a veil of [param strength] HP round this ship (replacing any).
func give_shield(strength: float) -> void:
	shield_max = maxf(strength, 1.0)
	shield_hp = shield_max
	if _veil != null and is_instance_valid(_veil):
		_veil.queue_free()
	if _hull_holder == null or _view == null:
		return
	var r := maxf(_view.aabb.size.length() * 0.5, 2.0) * 1.08
	_veil = ShieldBubble.attach(_hull_holder, r)
	_veil.position = _view.aabb.get_center()


## The veil soaks what it can of [param amount]; returns what gets through.
func _soak_shield(amount: float) -> float:
	if shield_hp <= 0.0:
		return amount
	var soaked := minf(shield_hp, amount)
	shield_hp -= soaked
	if _veil != null and is_instance_valid(_veil):
		_veil.hit_flash()
	if shield_hp <= 0.0:
		shield_hp = 0.0
		if _veil != null and is_instance_valid(_veil):
			_veil.pop_out()
			var host := get_parent()
			if host != null and host.is_inside_tree():
				AddonVfx.electric(host, global_position, clampf(scale_multiplier, 1.0, 4.0), false)
		_veil = null
	return amount - soaked


# --- EMP freeze -------------------------------------------------------------------

## Freeze this ship for [param seconds]: no thinking, no firing, it drifts to
## a stop. A later freeze only ever extends it.
func emp_freeze(seconds: float) -> void:
	if not _alive:
		return
	_frozen_until_ms = maxi(_frozen_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	_stop_telegraph()
	if _yeet != null:
		_yeet.release()
	if systems != null:
		systems.set_firing(false)
	var host := get_parent()
	if host != null and host.is_inside_tree():
		AddonVfx.electric(host, global_position, clampf(scale_multiplier, 1.0, 4.0), false)
	_emote("dizzy", seconds)


func is_frozen() -> bool:
	return Time.get_ticks_msec() < _frozen_until_ms


func _tick_frozen(delta: float) -> void:
	locked_enemy = null
	if systems != null:
		systems.set_firing(false)
	if model != null:
		model.command.throttle = 0.0
		model.command.yaw = 0.0
		model.command.pitch = 0.0
		model.command.roll = 0.0
		model.command.boost = false
		model.velocity = model.velocity * exp(-2.5 * delta)


# --- Comic marks ------------------------------------------------------------------

## Pop [param mark] ("!" / "?") over this ship, if the dial allows, it is in
## the player's view, and neither this ship's own cooldown ([member
## JuiceSettings.enemy_mark_cooldown]) nor the global gap has it waiting.
## [param dying] skips the per-ship cooldown (it is its last chance).
func _mark(mark: String, dying := false) -> void:
	if not JuiceSettings.enemy_marks or is_satellite or pilot_host != null:
		return
	if not is_inside_tree() or not in_player_view():
		return
	var now := Time.get_ticks_msec()
	if now < _next_any_mark_ms or (now < _next_mark_ms and not dying):
		return
	_next_any_mark_ms = now + MARK_GAP_MS
	_next_mark_ms = now + int(JuiceSettings.enemy_mark_cooldown * 1000.0)
	marked.emit(self, mark)


## True when this hit came from someone this ship did not count as an enemy:
## the player while it wasn't hostile to them, or a ship not on a team it
## is at war with.
func _hit_by_non_enemy(from_player: bool, source: Object) -> bool:
	if from_player:
		return attitude_to_player() != Attitude.HOSTILE
	var n := source as Node
	while n != null and not n is AiShip:
		n = n.get_parent()
	var attacker := n as AiShip
	if attacker == null or attacker == self:
		return false
	return not (attacker.team_id != 0 and aggressive_to.has(attacker.team_id))


## Whether [param source] (a gun's [SystemsSim]) belongs to a ship on the
## player's team — a wingman — not the player's own guns.
func _hit_by_player_side(source: Object) -> bool:
	var shooter := source as SystemsSim
	if shooter == null or player_ref == null or not is_instance_valid(player_ref):
		return false
	var ship := shooter.get("_root") as AiShip
	if ship == null or ship.pilot_host != null:
		return false
	var p_team := int(player_ref.get_meta("team", 0))
	return p_team != 0 and ship.team_id == p_team and team_id != p_team
