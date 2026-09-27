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

## Re-emits every roster ship's [signal AiShip.destroyed], so the flight scene
## can react to a kill (kill cam, stats) without wiring each ship itself.
signal ship_destroyed(ship: AiShip)

## Phone ceiling on the live roster, whatever the Performance panel says.
const MAX_SHIPS_MOBILE := 4
## A running [FlightScenarios] set-piece's own roster cap (both sides), or -1
## for the Performance panel's.
static var scenario_cap := -1


## Live roster cap, from the ⚡ Performance panel ([member
## PerformanceSettings.max_ai_ships], default 12).
static func _max_ships() -> int:
	if scenario_cap >= 0:
		return scenario_cap
	PerformanceSettings.ensure_loaded()
	var cap := PerformanceSettings.max_ai_ships
	return mini(cap, MAX_SHIPS_MOBILE) if OS.has_feature("mobile") else cap
const DESPAWN_DISTANCE := 3500.0
const SPAWN_MIN_DIST := 300.0
const SPAWN_MAX_DIST := 2200.0
const RESPAWN_INTERVAL := 2.0
## Size multiplier for a mother ship, on top of [member Session.ship_scale].
const MOTHER_SCALE := 16.0
## Size multiplier for the normal-size fighters a mother ejects.
const MOTHER_FIGHTER_SCALE := 0.7

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
	# A global look change has to reach traffic that is already flying, not only
	# ships spawned after it — the player flips the toggle and expects the belt to
	# change with them.
	StyleManager.instance().style_changed.connect(_on_style_changed)
	StyleManager.instance().palette_changed.connect(_on_palette_changed)
	print("AiSpawner: %d presets, %d parts" % [_library.presets.size(), _library.parts.size()])
	# Deferred: the player ship is positioned in FlightRoot._ready, which runs
	# after this node's _ready. Deferring lets the initial fleet spawn around the
	# player's actual spawn point instead of the pre-positioned origin.
	if auto_fleet:
		_spawn_initial_fleet.call_deferred()


## Bring the ambient traffic back (after a scenario ends).
func spawn_initial_fleet() -> void:
	_spawn_initial_fleet()


func _spawn_initial_fleet() -> void:
	var max_ships: int = _max_ships()
	# Every session meets a hunter squad first; the rest of the cap is the usual
	# random traffic (which may be all civilians, hence the guarantee).
	spawn_hunters()
	while _ships.size() < max_ships:
		_spawn_group()
	print("AiSpawner: spawned %d ships in %d groups" % [_ships.size(), _groups.size()])


## Re-skin every ship in flight for the new look and palette.
##
## Geometry goes through [PartMeshFactory], whose cache is keyed by the geometry
## dials, so a shading-only change is a cache hit for every part and costs a
## handful of uniform writes per material rather than a rebuild.
func _on_style_changed(_profile: StyleProfile) -> void:
	for ship in _ships:
		if is_instance_valid(ship):
			ship.restyle()


func _on_palette_changed(_palette: Palette) -> void:
	for ship in _ships:
		if is_instance_valid(ship):
			ship.restyle()


func _process(delta: float) -> void:
	# Rebuild group member arrays each frame (positions change).
	_rebuild_group_members()

	# Tick every alive ship's behaviour with full group context. Ships the player
	# is piloting (_ai_paused) are left alone so their inputs are not overwritten.
	# Everyone hunts whichever hull the player is flying right now — their own,
	# or a ship they have taken control of.
	var hunted := _find_player_node()
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive and not ship._ai_paused:
			if hunted != self and hunted != ship.model:
				ship.player_ref = hunted
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
		# Satellites are orbit probes — never cull them for flying out of range;
		# nor the ship the player spawned to fly.
		if not ship.is_satellite and not ship.is_pilot_vessel \
				and ship.global_position.distance_to(player_pos) > DESPAWN_DISTANCE:
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

	# Respawn to fill the cap — only for the ambient traffic. With the auto
	# fleet off (a scenario, the arena) this used to refill the roster with
	# random traffic every couple of seconds anyway.
	if not auto_fleet:
		return
	var max_ships: int = _max_ships()
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
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship._alive:
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
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship._alive:
			continue
		var gid: int = ship.group_id
		if _groups.has(gid):
			ship._group_members_ref = _groups[gid]["members"] as Array
			var members: Array = _groups[gid]["members"] as Array
			for i in members.size():
				var mem: AiGroupBehaviour.Member = members[i]
				if mem.position.is_equal_approx(ship.global_position):
					if ship.behaviour != null:
						ship.behaviour.my_index_in_group = i
					break



## Per-ship spawn offset (from the group's cluster centre) and facing for ship
## [param index] of [param group_size] in an [param arch] group. Most
## archetypes still get the old scattered cluster — it reads fine for a wolf
## pack, a swarm or a lone drifter — but a few archetypes have a shape that's
## part of what they ARE, and spawning them already in that shape (rather than
## clustered and only forming it after the fact, once [AiGroupBehaviour] takes
## over) is what makes them readable as that archetype on sight.
func _spawn_layout(arch: AiFactions.ArchetypeData, index: int, group_size: int) -> Dictionary:
	var n := maxf(float(group_size), 1.0)
	match arch.archetype:
		AiFactions.Archetype.STATION_GUARD, AiFactions.Archetype.HONOR_GUARD, \
		AiFactions.Archetype.DEFENSE_GRID:
			# A guard's whole point is holding a ring around what it protects —
			# spawn already on that ring, facing outward along it, instead of
			# clustered off to one side.
			var angle := TAU * float(index) / n
			var radius := arch.formation_spacing * 1.3
			var offset := Vector3(cos(angle), _rng.randf_range(-0.15, 0.15), sin(angle)) * radius
			return {"offset": offset, "facing": Vector3(cos(angle), 0.0, sin(angle))}

		AiFactions.Archetype.CONVOY_TRADER, AiFactions.Archetype.MIGRATION_FLEET:
			# Already strung out nose-to-tail along a lane when the player meets
			# them, rather than a knot that only stretches into its line after
			# spawning.
			var lane_dir := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
			lane_dir = lane_dir.normalized() if lane_dir.length_squared() > 0.0001 else Vector3.FORWARD
			var offset := lane_dir * arch.formation_spacing * (float(index) - float(group_size - 1) * 0.5)
			offset.y = _rng.randf_range(-15.0, 15.0)
			return {"offset": offset, "facing": lane_dir}

		AiFactions.Archetype.WOLF_PIRATE, AiFactions.Archetype.PIRATE_FLEET:
			# A raiding pack closing in from one shared heading, not orbiting the
			# player from every side at once — reads as an approach, not scenery
			# that happened to spawn nearby.
			var approach := Vector3(
				_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-1.0, 1.0)
			)
			approach = approach.normalized() if approach.length_squared() > 0.0001 else Vector3.FORWARD
			var side := approach.cross(Vector3.UP)
			side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
			var spread := (float(index) - float(group_size - 1) * 0.5) * arch.formation_spacing
			return {"offset": approach * 250.0 + side * spread, "facing": -approach}

		AiFactions.Archetype.AMBUSHER:
			# Lying in wait means sitting out at the edge of easy notice, not in
			# the middle of the cluster the player spawns into.
			var hide_angle := _rng.randf_range(0.0, TAU)
			var offset := Vector3(cos(hide_angle), _rng.randf_range(-40.0, 40.0), sin(hide_angle)) \
				* (arch.detection_range * 0.85)
			return {"offset": offset, "facing": -offset.normalized()}

		_:
			var offset := Vector3(
				_rng.randf_range(-100.0, 100.0),
				_rng.randf_range(-30.0, 30.0),
				_rng.randf_range(-100.0, 100.0),
			)
			var fwd := Vector3(
				_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.0, 1.0)
			).normalized()
			return {"offset": offset, "facing": fwd}


## Spawn a new group of ships with a shared archetype.
func _spawn_group() -> void:
	var archetype_id := AiFactions.random_archetype(_rng)
	var arch := AiFactions.create(archetype_id)

	var group_size := _rng.randi_range(arch.group_size_min, arch.group_size_max)
	group_size = mini(group_size, _max_ships() - _ships.size())
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

		# Position within the group, shaped by what this archetype actually is —
		# see [method _spawn_layout].
		var layout := _spawn_layout(arch, i, group_size)
		var spawn_pos := cluster_centre + (layout["offset"] as Vector3)
		var fwd: Vector3 = layout["facing"]
		if fwd.length_squared() < 0.0001:
			fwd = Vector3.FORWARD
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
		# Join the shared physics layer so ships can knock and be knocked (M1b).
		ship.set_phys_world(_find_world())
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


func _on_ship_destroyed(ship: AiShip) -> void:
	ship_destroyed.emit(ship)


func _find_player_position() -> Vector3:
	# _ready() (line 47) runs before FlightRoot._build_ship() creates `model`,
	# so the first resolve falls into _find_player_node()'s `return self`
	# branch and used to latch there forever — every spawn then clustered on
	# the spawner's own position (world origin) instead of the player's.
	# Keep retrying until the real ship exists, then stop.
	# Re-resolved every call: taking control of another ship moves "the player".
	_cached_player = _find_player_node()
	if _cached_player != null and is_instance_valid(_cached_player) and _cached_player != self:
		return _cached_player.global_position
	return global_position


func _find_player_node() -> Node3D:
	var root := get_parent()
	if root is FlightRoot and root.model != null:
		return (root as FlightRoot).active_model()
	return self


func _find_gravity() -> GravitySystem:
	if _cached_gravity != null:
		return _cached_gravity
	var root := get_parent()
	if root is FlightRoot:
		return root.gravity
	return null


## The shared PhysWorld, found the same way gravity is. Null when the parent is
## not a space [FlightRoot] (the tuning test volume, a combat arena without a
## physics layer) — ships just do not join a world there.
func _find_world() -> PhysWorld:
	var root := get_parent()
	if root is FlightRoot:
		return root.phys_world
	return null


func live_count() -> int:
	var n := 0
	for ship in _ships:
		if is_instance_valid(ship) and ship._alive:
			n += 1
	return n


## Every ship this spawner is currently tracking, live or not. Read-only for
## callers that need to push a change across the whole population at once — a
## [Session] setting the player moves, for instance (see
## [method FlightRoot.set_npc_speed_scale]).
func ships() -> Array[AiShip]:
	return _ships


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
	ship.set_phys_world(_find_world())
	# Ballistic: no AI, no teams — just the perfect circular orbit.
	ship._ai_paused = true
	ship.is_satellite = true
	ship.team_id = 0
	# Through the model's setter, not a bare write: the satellite is already
	# bound to the physics world by the line above, and the driven body's step
	# would otherwise read the solver's (zero) copy back over this the moment it
	# ran — a probe that never leaves its spawn point.
	ship.model.set_velocity(grav.circular_orbit_velocity(body, pos))
	_ships.append(ship)
	return ship


## A mother ship: a huge carrier hull that periodically launches normal-size
## fighters (see [method AiShip.tick_ai]). Spawned near the player; huge and
## light (mass is not scaled), so ramming one is gloriously funny.
func spawn_mother() -> AiShip:
	if _library == null:
		return null
	# Deliberately ignores the live-ship cap: a mother is a debug/testing spawn
	# and should drop in even when the fleet is full. Its fighters still respect
	# the cap.
	var player := _find_player_node()
	var dir := Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.0, 1.0)
	).normalized()
	var anchor := player.global_position if player != null else global_position
	var pos := anchor + dir * 400.0
	var spawn_xform := Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)
	var ship := AiShip.new()
	ship.name = "Mother_%d" % _ships.size()
	ship.scale_multiplier = MOTHER_SCALE
	ship.is_mother = true
	ship.spawner_ref = self
	add_child(ship)
	ship.initialise(_library, spawn_xform, player)
	if ship.model == null:
		ship.queue_free()
		return null
	# A carrier that takes a real beating, not a one-shot wreck.
	ship.max_hp = maxf(ship.max_hp * 12.0, 5000.0)
	ship.hp = ship.max_hp
	ship.set_group_context(-1, AiFactions.create(AiFactions.Archetype.LONE_WOLF), [])
	var grav := _find_gravity()
	if grav != null:
		ship.set_gravity(grav)
	ship.set_phys_world(_find_world())
	ship.destroyed.connect(_on_ship_destroyed)
	_ships.append(ship)
	return ship


## A random ship of [param size_mult] times the normal size, spawned beside
## [param near] for the player to fly (see [method FlightRoot.fly_as]).
## Ignores the live-ship cap, is never culled for range, and gets a plain
## archetype — the player's hands, not a behaviour, fly it.
func spawn_pilot_vessel(near: Transform3D, size_mult: float) -> AiShip:
	if _library == null:
		return null
	var side := near.basis.x.normalized()
	var ship := AiShip.new()
	ship.name = "PilotVessel_%d" % _ships.size()
	ship.scale_multiplier = size_mult
	ship.is_pilot_vessel = true
	ship.spawner_ref = self
	add_child(ship)
	# Off to the side by a margin that grows with the hull, facing the same way.
	var pos := near.origin + side * (30.0 + 25.0 * size_mult)
	ship.initialise(_library, Transform3D(near.basis.orthonormalized(), pos), _find_player_node())
	if ship.model == null:
		ship.queue_free()
		return null
	# A size-appropriate gun unless the caller picks one.
	ship.set_group_context(-1, AiFactions.create(AiFactions.Archetype.LONE_WOLF), [])
	# The player's own speed dial, not the AI traffic's.
	ship.model.rescale_speed(Session.player_speed_scale)
	var grav := _find_gravity()
	if grav != null:
		ship.set_gravity(grav)
	ship.set_phys_world(_find_world())
	ship.destroyed.connect(_on_ship_destroyed)
	_ships.append(ship)
	return ship


## A normal-size fighter ejected by a mother ship, near the host. Inherits the
## host's team and aggression, so a mother's fighters take up its fight.
func spawn_fighter_near(host: Node3D) -> AiShip:
	if _library == null or host == null:
		return null
	var max_ships: int = _max_ships()
	if _ships.size() >= max_ships:
		return null
	var player := _find_player_node()
	var dir := Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)
	).normalized()
	var pos := host.global_position + dir * _rng.randf_range(40.0, 90.0)
	var spawn_xform := Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	var ship := AiShip.new()
	ship.name = "Fighter_%d" % _ships.size()
	ship.scale_multiplier = MOTHER_FIGHTER_SCALE
	ship.spawner_ref = self
	add_child(ship)
	ship.initialise(_library, spawn_xform, player)
	if ship.model == null:
		ship.queue_free()
		return null
	if host is AiShip:
		var mother := host as AiShip
		ship.team_id = mother.team_id
		ship.aggressive_to = mother.aggressive_to.duplicate()
	ship.set_group_context(-1, AiFactions.create(AiFactions.Archetype.HUNTER_SQUAD), [])
	var grav := _find_gravity()
	if grav != null:
		ship.set_gravity(grav)
	ship.set_phys_world(_find_world())
	ship.destroyed.connect(_on_ship_destroyed)
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
	var max_ships: int = _max_ships()
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
		# Join the shared physics layer so ships can knock and be knocked (M1b).
		ship.set_phys_world(_find_world())
		ship.destroyed.connect(_on_ship_destroyed)
		_ships.append(ship)


## Spawn a group with an explicitly built archetype (behaviour + formation) and
## size, on a team. Drives the HUD's spawn panel — the player picks the mix, this
## makes it. team 0 = None/neutral (no team warfare, pre-arena behaviour).
func spawn_group_with(arch: AiFactions.ArchetypeData, count: int, team: int = 0) -> void:
	var max_ships: int = _max_ships()
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
		# Join the shared physics layer so ships can knock and be knocked (M1b).
		ship.set_phys_world(_find_world())
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
	for i in mini(count, _max_ships() - _ships.size()):
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
		# Join the shared physics layer so ships can knock and be knocked (M1b).
		ship.set_phys_world(_find_world())
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
