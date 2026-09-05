## Spawns and manages a fleet of [AiShip]s with faction archetypes and group IDs.
##
## Ships are created in groups sharing the same archetype. Each group gets a
## unique ID and a shared member array that the behaviour system uses for
## boid flocking, formation flying, wolfpack pursuit, etc.
##
## Groups are respawned as units — when a group is depleted, a new one spawns
## with a fresh archetype. This keeps the system modular: adding a new faction
## type means adding an archetype, not touching the spawner.
class_name AiSpawner
extends Node3D

const MAX_SHIPS_DESKTOP := 12
const MAX_SHIPS_MOBILE := 4
const DESPAWN_DISTANCE := 3500.0
const SPAWN_MIN_DIST := 300.0
const SPAWN_MAX_DIST := 2200.0
const RESPAWN_INTERVAL := 2.0

var _ships: Array[AiShip] = []
var _library: PartLibrary
var _respawn_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _next_group_id := 0

## Group bookkeeping: group_id → {archetype, members: Array[AiGroupBehaviour.Member]}
var _groups: Dictionary = {}


func _init() -> void:
	_rng.randomize()


## Spawns the default random fleet on ready. The AI arena disables this (it
## spawns its own team-vs-team fleets instead).
var auto_fleet := true


func _ready() -> void:
	_library = PartLibrary.instance()
	_library.load_all()
	# Cache player and gravity references once — avoid tree walks every frame.
	_cached_player = _find_player_node()
	_cached_gravity = _find_gravity()
	print("AiSpawner: %d presets, %d parts" % [_library.presets.size(), _library.parts.size()])
	# Deferred: the player ship is positioned in FlightRoot._ready, which runs
	# after this node's _ready. Deferring lets the initial fleet spawn around the
	# player's actual spawn point instead of the pre-positioned origin.
	if auto_fleet:
		_spawn_initial_fleet.call_deferred()


func _spawn_initial_fleet() -> void:
	var max_ships: int = MAX_SHIPS_MOBILE if OS.has_feature("mobile") else MAX_SHIPS_DESKTOP
	# Every session meets a hunter squad first; the rest of the cap is the usual
	# random traffic (which may be all civilians, hence the guarantee).
	spawn_hunters()
	while _ships.size() < max_ships:
		_spawn_group()
	print("AiSpawner: spawned %d ships in %d groups" % [_ships.size(), _groups.size()])


func _process(delta: float) -> void:
	# Rebuild group member arrays each frame (positions change).
	_rebuild_group_members()

	# Tick every alive ship's behaviour with full group context. Ships the player
	# is piloting (_ai_paused) are left alone so their inputs are not overwritten.
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive and not ship._ai_paused:
			ship.tick_ai(delta)

	_respawn_timer -= delta
	if _respawn_timer > 0.0:
		return
	_respawn_timer = RESPAWN_INTERVAL

	# Prune dead or too-distant ships.
	var still_alive: Array[AiShip] = []
	for ship in _ships:
		if not is_instance_valid(ship) or not ship._alive:
			if is_instance_valid(ship):
				ship.teardown()
			continue
		var player_pos := _find_player_position()
		# Satellites are orbit probes — never cull them for flying out of range.
		if not ship.is_satellite and ship.global_position.distance_to(player_pos) > DESPAWN_DISTANCE:
			ship.teardown()
			continue
		still_alive.append(ship)
	_ships = still_alive

	# Prune empty groups.
	var live_group_ids: Dictionary = {}
	for ship in _ships:
		if is_instance_valid(ship):
			live_group_ids[ship.group_id] = true
	for gid: int in _groups.keys():
		if not live_group_ids.has(gid):
			_groups.erase(gid)

	# Respawn to fill the cap.
	var max_ships: int = MAX_SHIPS_MOBILE if OS.has_feature("mobile") else MAX_SHIPS_DESKTOP
	while _ships.size() < max_ships:
		_spawn_group()


## Pre-allocated Member pool — avoids new() calls in the hot path.
var _member_pool: Array[AiGroupBehaviour.Member] = []
var _member_pool_size := 0
## Cached player reference — avoids tree walk every frame.
var _cached_player: Node3D = null
var _cached_gravity: GravitySystem = null

func _ensure_member_pool(size: int) -> void:
	while _member_pool.size() < size:
		_member_pool.append(AiGroupBehaviour.Member.new())
	_member_pool_size = size

func _rebuild_group_members() -> void:
	# Reset group member counts (reuse the same Array objects).
	for gid: int in _groups.keys():
		(_groups[gid]["members"] as Array).clear()

	# Count members per group to size the pool.
	var total_members := 0
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive:
			total_members += 1
	_ensure_member_pool(total_members)

	# Fill the pool with live ship data.
	var pool_idx := 0
	for ship in _ships:
		if not is_instance_valid(ship) or not ship._alive:
			continue
		var gid: int = ship.group_id
		if not _groups.has(gid):
			continue
		var members: Array = _groups[gid]["members"] as Array
		var m: AiGroupBehaviour.Member = _member_pool[pool_idx]
		m.position = ship.global_position
		m.velocity = ship.model.velocity if ship.model != null else Vector3.ZERO
		m.forward = -ship.global_transform.basis.z
		m.index = members.size()
		m.tag = gid
		members.append(m)
		pool_idx += 1

	# Push the rebuilt member arrays to each ship in the group.
	for ship in _ships:
		if not is_instance_valid(ship) or not ship._alive:
			continue
		var gid: int = ship.group_id
		if _groups.has(gid):
			ship._group_members_ref = _groups[gid]["members"] as Array
			var members: Array = _groups[gid]["members"] as Array
			for i in members.size():
				var mem: AiGroupBehaviour.Member = members[i]
				if mem.position.is_equal_approx(ship.global_position):
					ship.behaviour.my_index_in_group = i
					break


## Spawn a new group of ships with a shared archetype.
func _spawn_group() -> void:
	var archetype_id := AiFactions.random_archetype(_rng)
	var arch := AiFactions.create(archetype_id)

	var group_size := _rng.randi_range(arch.group_size_min, arch.group_size_max)
	group_size = mini(group_size, MAX_SHIPS_MOBILE if OS.has_feature("mobile") else MAX_SHIPS_DESKTOP - _ships.size())
	if group_size <= 0:
		return

	var gid := _next_group_id
	_next_group_id += 1
	_groups[gid] = {
		"archetype": arch,
		"members": [] as Array,
	}

	# Spawn the group near the player, clustered together — the point of AI
	# traffic is having someone to meet, and out at the belt's edge that was
	# a two-minute cruise away.
	var player_pos := _find_player_position()
	var cluster_centre := player_pos + Vector3(
		_rng.randf_range(-1500.0, 1500.0),
		_rng.randf_range(-200.0, 200.0),
		_rng.randf_range(-1500.0, 1500.0),
	)

	for i in group_size:
		var ship := AiShip.new()
		ship.name = "AiShip_%d_G%d" % [_ships.size(), gid]
		add_child(ship)

		# Position within the cluster.
		var offset := Vector3(
			_rng.randf_range(-100.0, 100.0),
			_rng.randf_range(-30.0, 30.0),
			_rng.randf_range(-100.0, 100.0),
		)
		var spawn_pos := cluster_centre + offset

		# Random facing.
		var fwd := Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.0, 1.0)
		).normalized()
		var spawn_xform := Transform3D(Basis.looking_at(fwd, Vector3.UP), spawn_pos)

		ship.initialise(_library, spawn_xform, _find_player_node())
		ship.spawner_ref = self
		if ship.model == null:
			ship.queue_free()
			continue

		# Assign group context.
		ship.set_group_context(gid, arch, [])
		# Pass the gravity system so AI ships experience orbital mechanics too.
		var grav := _find_gravity()
		if grav != null:
			ship.set_gravity(grav)
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


func _on_ship_destroyed(ship: AiShip) -> void:
	pass


func _find_player_position() -> Vector3:
	if _cached_player != null and is_instance_valid(_cached_player):
		return _cached_player.global_position
	return global_position


func _find_player_node() -> Node3D:
	var root := get_parent()
	if root is FlightRoot and root.model != null:
		return root.model
	return self


func _find_gravity() -> GravitySystem:
	if _cached_gravity != null:
		return _cached_gravity
	var root := get_parent()
	if root is FlightRoot:
		return root.gravity
	return null


func live_count() -> int:
	var n := 0
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive:
			n += 1
	return n


## Spawn a single ballistic probe in a circular orbit around the dominant body:
## a random ship with its AI paused, placed at [param distance] out and given the
## exact circular-orbit velocity. It just follows gravity — the definitive way to
## watch whether orbit works.
func spawn_ballistic_satellite(grav: GravitySystem, distance: float) -> AiShip:
	if _library == null or grav == null:
		return null
	# Find the dominant body from the player's position, not the spawner's — the
	# distance was computed relative to whichever body the player is orbiting.
	var player := _find_player_node()
	var body := grav.find_dominant_body(player.global_position) if player != null else grav.find_dominant_body(global_position)
	if body == null:
		return null
	var ship := AiShip.new()
	ship.name = "Satellite_%d" % _ships.size()
	add_child(ship)
	var dir := Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.0, 1.0)
	).normalized()
	var pos := body.position + dir * distance
	ship.initialise(_library, Transform3D(Basis.looking_at(-dir, Vector3.UP), pos), _find_player_node())
	if ship.model == null:
		ship.queue_free()
		return null
	ship.spawner_ref = self
	ship.set_group_context(-1, AiFactions.create(AiFactions.Archetype.LONE_WOLF), [])
	var grav_ref := _find_gravity()
	if grav_ref != null:
		ship.set_gravity(grav_ref)
	# Ballistic: no AI, no teams — just the perfect circular orbit.
	ship._ai_paused = true
	ship.is_satellite = true
	ship.team_id = 0
	ship.model.velocity = grav.circular_orbit_velocity(body, pos)
	_ships.append(ship)
	return ship


## A read-only snapshot of every live ship, for the arena roster UI.
func ship_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ship in _ships:
		if not is_instance_valid(ship) or not ship._alive:
			continue
		out.append({
			"node": ship,
			"name": ship.preset_name,
			"team": ship.team_id,
			"hp": ship.hp,
			"max_hp": ship.max_hp,
			"aggro": ship.aggressive_to.duplicate(),
		})
	return out


## Spawn a guaranteed hunter squad that immediately pursues the player.
##
## A dedicated [Archetype.HUNTER_SQUAD] — tight V formation, pincer attack,
## aggression 1.0 — placed just inside its detection range so the ships are
## already closing in from the first frame. Called by [method _spawn_initial_fleet]
## before the random traffic fills the cap.
func spawn_hunters() -> void:
	var max_ships: int = MAX_SHIPS_MOBILE if OS.has_feature("mobile") else MAX_SHIPS_DESKTOP
	var player_pos := _find_player_position()
	var arch := AiFactions.create(AiFactions.Archetype.HUNTER_SQUAD)
	var gid := _next_group_id
	_next_group_id += 1
	_groups[gid] = {"archetype": arch, "members": [] as Array}
	var count := mini(arch.group_size_max, max_ships - _ships.size())
	# Squad centre: 1000–1500 m out, so it is within HUNTER_SQUAD's 1600 m
	# detection range but not on top of the player.
	var dir := Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.25, 0.25), _rng.randf_range(-1.0, 1.0)
	).normalized()
	var centre := player_pos + dir * _rng.randf_range(1000.0, 1500.0)
	for i in count:
		var ship := AiShip.new()
		ship.name = "Hunter_%d_G%d" % [_ships.size(), gid]
		add_child(ship)
		var offset := Vector3(
			_rng.randf_range(-120.0, 120.0),
			_rng.randf_range(-40.0, 40.0),
			_rng.randf_range(-120.0, 120.0)
		)
		var spawn_pos := centre + offset
		var fwd := (player_pos - spawn_pos).normalized()
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
		var spawn_xform := Transform3D(Basis.looking_at(fwd, Vector3.UP), spawn_pos)
		ship.initialise(_library, spawn_xform, _find_player_node())
		ship.spawner_ref = self
		if ship.model == null:
			ship.queue_free()
			continue
		ship.set_group_context(gid, arch, [])
		var grav := _find_gravity()
		if grav != null:
			ship.set_gravity(grav)
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


## Spawn a group with an explicitly built archetype (behaviour + formation) and
## size, on a team. Drives the HUD's spawn panel — the player picks the mix, this
## makes it. team 0 = None/neutral (no team warfare, pre-arena behaviour).
func spawn_group_with(arch: AiFactions.ArchetypeData, count: int, team: int = 0) -> void:
	var max_ships: int = MAX_SHIPS_MOBILE if OS.has_feature("mobile") else MAX_SHIPS_DESKTOP
	var player_pos := _find_player_position()
	var gid := _next_group_id
	_next_group_id += 1
	_groups[gid] = {"archetype": arch, "members": [] as Array}
	var aggressive := _team_aggression(team)
	for i in mini(maxi(count, 1), max_ships - _ships.size()):
		var ship := AiShip.new()
		ship.name = "Spawn_%d_G%d" % [_ships.size(), gid]
		add_child(ship)
		var offset := Vector3(
			_rng.randf_range(-200.0, 200.0),
			_rng.randf_range(-50.0, 50.0),
			_rng.randf_range(-200.0, 200.0)
		)
		var fwd := (player_pos - (player_pos + offset)).normalized()
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
		var spawn_xform := Transform3D(Basis.looking_at(fwd, Vector3.UP), player_pos + offset)
		ship.initialise(_library, spawn_xform, _find_player_node())
		ship.spawner_ref = self
		ship.team_id = team
		ship.aggressive_to = aggressive.duplicate()
		if ship.model == null:
			ship.queue_free()
			continue
		ship.set_group_context(gid, arch, [])
		var grav := _find_gravity()
		if grav != null:
			ship.set_gravity(grav)
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


## The teams a given team is aggressive to: every other team (free-for-all) by
## default. Team 0 (None) fights no one.
static func _team_aggression(team: int) -> Array[int]:
	var out: Array[int] = []
	if team == 0:
		return out
	for t in [1, 2, 3, 4]:
		if t != team:
			out.append(t)
	return out


## Public: spawn a group of AI ships near the player.
## Called from the flight menu to let the player request reinforcements.
func spawn_near_player(count: int = 3) -> void:
	var player_pos := _find_player_position()
	var gid := _next_group_id
	_next_group_id += 1
	var archetype_id := AiFactions.random_archetype(_rng)
	var arch := AiFactions.create(archetype_id)
	_groups[gid] = {"archetype": arch, "members": [] as Array}
	for i in mini(count, MAX_SHIPS_DESKTOP - _ships.size()):
		var ship := AiShip.new()
		ship.name = "AiShip_%d_G%d" % [_ships.size(), gid]
		add_child(ship)
		var offset := Vector3(
			_rng.randf_range(-200.0, 200.0),
			_rng.randf_range(-50.0, 50.0),
			_rng.randf_range(-200.0, 200.0)
		)
		var fwd := (player_pos - (player_pos + offset)).normalized()
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
		var spawn_xform := Transform3D(Basis.looking_at(fwd, Vector3.UP), player_pos + offset)
		ship.initialise(_library, spawn_xform, _find_player_node())
		ship.spawner_ref = self
		if ship.model == null:
			ship.queue_free()
			continue
		ship.set_group_context(gid, arch, [])
		var grav := _find_gravity()
		if grav != null:
			ship.set_gravity(grav)
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


func teardown() -> void:
	for ship in _ships:
		if is_instance_valid(ship):
			ship.teardown()
	_ships.clear()
	_groups.clear()


## Destroy every live ship (with their explosion effects), for the arena menu's
## "Kill all AI ships".
func kill_all() -> void:
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive:
			ship.take_damage(ship.hp)
	_ships.clear()
	_groups.clear()
