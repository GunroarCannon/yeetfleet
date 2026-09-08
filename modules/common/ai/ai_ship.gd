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

## Maximum hit points. Set from the design's hull stat.
var max_hp := 200.0
var hp := 200.0

## The preset id this ship was built from, for display.
var preset_name := ""
## The faction id, for colour.
var faction_name := ""

var model: FlightModel
var systems: SystemsSim
var behaviour: AiBehaviour = null
var _hull_holder: Node3D
var _view: ShipView
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
## Reference to the player's ship, set by [AiSpawner]. Used for detection
## distance checks and combat targeting.
var player_ref: Node3D = null

## Team and aggression, used by the AI test arena. team_id 0 = None/neutral.
var team_id := 0
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


func _init() -> void:
	_rng.randomize()


## Build this ship from a random preset. Called once after [method add_child]
## completes (the subtree must be readied before [SystemsSim] can bind).
func initialise(library: PartLibrary, spawn_xform: Transform3D, ai_player: Node3D) -> void:
	_library = library
	player_ref = ai_player
	global_transform = spawn_xform

	# Build a completely random ship: random chassis, random parts per socket,
	# random faction paint. Every AI ship is unique.
	_design = _build_random_design(library)
	if _design == null:
		push_warning("AiShip: could not build random design")
		return
	preset_name = _design.design_name
	faction_name = _design.faction_id

	# Create the FlightModel (this IS the ship — it owns the transform).
	model = FlightModel.new()
	model.name = "Model"
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
	model.add_child(systems)

	# Assemble the ship geometry.
	_view = ShipAssembler.assemble(_design, library, 0.0, false, false)
	# The Ship-size setting scales every AI hull the same way as the player's; a
	# mother ship adds its own extra multiplier on top.
	_view.apply_scale(Session.ship_scale * scale_multiplier)
	_hull_holder.add_child(_view.root)

	# Bind systems and configure the flight model from the design's stats.
	model.configure(_view.resolution.stats, systems, null)
	systems.bind(_view, self)
	systems.set_throttle(0.0)

	# Read HP from stats.
	max_hp = maxf(_view.resolution.stats.get_stat("hull_hp"), 50.0)
	hp = max_hp

	# Create and initialise the behaviour.
	behaviour = AiBehaviour.new()
	behaviour.initialise(spawn_xform.origin)
	# Gravity will be set later by set_gravity() if available.

	# Set up collision: the AI ship bounces off planets/asteroids the same way
	# the player's ship does, via FlightModel._check_collision().
	if _view.resolution.stats.get_stat("sensor_range") > 0.0:
		model._asteroid_data = _get_asteroid_data()


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
	if _view != null:
		radius = maxf(_view.aabb.size.length() * 0.5, 3.0)
	model.set_phys_world(world, radius)


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


## Feed the behaviour each frame. Called by [AiSpawner].
##
## The behaviour writes to [member FlightModel.command]. The actual physics
## integration happens in [FlightModel]._physics_process, which Godot calls
## automatically. [SystemsSim] reads the model's state in its own _process,
## same as the player's ship. This method only drives the command and fires
## weapons — it does not duplicate the physics pipeline.
func tick_ai(delta: float) -> void:
	if not _alive or model == null or behaviour == null:
		return

	# Update detection — pick the nearest enemy (a ship on an aggressive team, or
	# the player). In the arena ships fight each other; in space (no teams set)
	# this falls back to hunting the player as before.
	var target := _find_enemy()
	if systems != null:
		systems.target_ref = target
	var target_pos := Vector3.ZERO
	var target_visible := false
	if target != null:
		target_pos = target.global_position
		target_visible = global_position.distance_to(target_pos) < AiBehaviour.DETECTION_RANGE

	behaviour.player_position = target_pos
	behaviour.player_visible = target_visible

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

	# Get behaviour output and feed it to the flight model.
	var cmd: Dictionary = behaviour.update(
		delta, global_position, global_transform.basis, model.top_speed
	)
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


## The nearest ship to engage: the closest live ship (or the player) on a team
## this ship is aggressive to. With no team warfare configured (aggressive_to
## empty — the pre-arena case), the player is always fair game.
func _find_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	if spawner_ref != null and is_instance_valid(spawner_ref):
		var ships: Array = spawner_ref._ships
		for other in ships:
			if not is_instance_valid(other) or not other._alive or other == self:
				continue
			if other.team_id != 0 and aggressive_to.has(other.team_id):
				var d := global_position.distance_squared_to(other.global_position)
				if d < best_d:
					best_d = d
					best = other
	if player_ref != null and is_instance_valid(player_ref):
		var player_team_id: int = int(player_ref.get_meta("team", 0))
		if aggressive_to.is_empty() or (player_team_id != 0 and aggressive_to.has(player_team_id)):
			var d := global_position.distance_squared_to(player_ref.global_position)
			if d < best_d:
				best = player_ref
	return best


func _update_combat(delta: float, target: Node3D) -> void:
	if not _alive:
		systems.set_firing(false)
		locked_enemy = null
		return
	if target == null:
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
	if should_fire:
		if _fire_timer <= 0.0:
			systems.set_firing(true)
			_fire_timer = FIRE_COOLDOWN
		# Continuous damage while engaged (ships visibly trade fire and die).
		_apply_combat_damage(target, delta)
	else:
		systems.set_firing(false)
		_fire_timer = maxf(_fire_timer - delta, 0.0)


func _apply_combat_damage(target: Node3D, delta: float) -> void:
	if target is AiShip:
		(target as AiShip).take_damage(WEAPON_DPS * delta)
	else:
		# The player: no HP system, so a hit flash so getting shot is legible.
		Juice.flash(Color("ff6644"), 0.06, 0.1)


## Apply damage to this ship. Called by [FlightModel] when it hits something
## fast enough, or when a projectile strikes it.
func take_damage(amount: float) -> void:
	if not _alive:
		return
	hp -= amount
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	if not _alive:
		return
	_alive = false
	locked_enemy = null
	systems.set_firing(false)
	systems.set_throttle(0.0)
	systems.set_boost(false)
	# Leave the physics world: a destroyed ship is a corpse, not a collider.
	if model != null:
		model.clear_phys_world()

	# Explosion juice: the full stack.
	Juice.burst(BurstPresets.Preset.SPARKS, global_transform, 2.0, Color("ff8844"))
	Juice.burst(BurstPresets.Preset.EMBERS, global_transform, 1.5)
	Juice.burst(BurstPresets.Preset.DEBRIS, global_transform, 1.0)
	Juice.light_pop(global_position, Color("ffcc66"), 8.0, 0.25)
	Juice.ring(global_transform, 3.0, Color("ffaa44"), 0.5)
	Juice.shake(0.5)
	Juice.flash(Color("ff8844"), 0.4, 0.3)
	Juice.hitstop(0.04, 0.2)

	destroyed.emit(self)


## Sync SystemsSim with the FlightModel's live state after physics integration.
## FlightModel._physics_process computes throttle and boost; SystemsSim needs
## those same values for plume visuals. This mirrors what FlightRoot._physics_process
## does for the player's ship.
func _physics_process(_delta: float) -> void:
	if model == null or systems == null:
		return
	systems.set_throttle(clampf(absf(model.command.throttle), 0.0, 1.0))
	systems.set_boost(model.command.boost)
	# The FlightModel is the ship's transform owner; mirror its transform up to
	# the AiShip node so targeting, the roster and camera focus all read the
	# ship's real position (previously this node sat at spawn forever).
	global_transform = model.global_transform


## Build a completely random ship design: random chassis, random parts in
## every socket, random faction paint. Every AI ship is unique.
func _build_random_design(library: PartLibrary) -> ShipDesign:
	# Pick a random chassis.
	var chassis_list: Array[ShipPart] = library.chassis_list()
	if chassis_list.is_empty():
		push_warning("AiShip: no chassis parts available")
		return null
	var chassis: ShipPart = chassis_list[randi() % chassis_list.size()]
	var design := ShipDesign.create(chassis.id)
	var faction_names: Array[String] = []
	for f: Dictionary in library.factions:
		faction_names.append(String(f.get("id", "")))
	# Apply a random faction paint.
	if not faction_names.is_empty():
		var fid: String = faction_names[randi() % faction_names.size()]
		library.apply_faction(design, fid)
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
	_alive = false
	if model != null:
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
