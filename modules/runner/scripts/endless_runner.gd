## EndlessRunner: the flight test as an endless runner — the runner module's
## façade.
##
## The ship is pulled down a straight "track" (the way it faced when the run
## began) at a speed that keeps climbing, and the player only steers across
## it with whatever movement profile they fly (swipe is the one it is built
## for). Down the track come drifting rocks to dodge, boost rings to thread
## and waves of popcorn fighters that come at the player — ram or shoot them
## (yeet combat decides the clashes). The run ends when the ship goes down;
## after the respawn a new one starts by itself. Distance is the score.
##
## Everything rides on [FlightRoot]'s public API: the pull is the player
## model's [member FlightModel.frame_velocity] (a carry that never turns the
## hull), the speed shows as the mobile HUD's meter ([method
## FlightRoot.set_speed_meter]), fighters come from the [AiSpawner]. The rocks
## and rings are this module's own pooled meshes, tested against the ship by
## distance each tick — one draw-cheap pool, recycled ahead as the ship
## passes them, so a run never allocates.
##
## Attach with [method attach]; start from the scenario panel's "Endless run"
## or boot straight in through [code]runner.tscn[/code].
class_name EndlessRunner
extends Node

## The run started, ended or its status line changed.
signal changed
## The ship went down [param distance] metres into the run.
signal run_over(distance: float)

enum State { IDLE, RUNNING, OVER }

## Track speed at the start and at full ramp, × the ship's top speed.
const START_SPEED := 0.9
const MAX_SPEED := 3.2
## Seconds of running to reach [constant MAX_SPEED].
const RAMP_SECONDS := 100.0
## The track's radius, metres: content spawns inside it, and a ship that
## strays past [constant CORRIDOR] × [constant CORRIDOR_SOFT] is eased back.
const CORRIDOR := 170.0
const CORRIDOR_SOFT := 1.6
## Content is laid this far ahead of the ship, and recycled once this far behind.
const SPAWN_AHEAD := 1500.0
const RECYCLE_BEHIND := 160.0
const ROCK_COUNT := 28
const RING_COUNT := 4
## Metres of track between boost rings and between fighter waves.
const RING_SPACING := 420.0
const WAVE_SPACING := 950.0
## A rock hit: damage and knock; a ring: extra speed (× top speed), fading.
const ROCK_DAMAGE := 24.0
const RING_BOOST := 0.45
const BOOST_FADE := 0.35
## Fighters behind the ship further than this are cleared, metres.
const WAVE_BEHIND := 600.0
## Seconds after the respawn before the next run starts.
const RESTART_DELAY := 1.5

## The longest run this session (survives a scene reload).
static var best := 0.0

var state := State.IDLE
## Metres down the track this run.
var distance := 0.0
var elapsed := 0.0
var kills := 0
## The current pull down the track, m/s.
var speed := 0.0

var _root: FlightRoot
var _spawner: AiSpawner
var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD
var _right := Vector3.RIGHT
var _up := Vector3.UP
## Pools: {node, pos, radius, s} — s is the distance down the track.
var _rocks: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _wave_ships: Array[AiShip] = []
var _next_ring_s := 0.0
var _next_wave_s := 0.0
var _boost := 0.0
var _restart_in := -1.0
var _rng := RandomNumberGenerator.new()
var _pool_root: Node3D
var _last_status := ""
## How far down the track the ship was last tick (a ring is threaded when the
## ship crosses its plane between two ticks).
var _prev_s := 0.0


## The runner hanging off [param root], made on first use.
static func attach(root: FlightRoot) -> EndlessRunner:
	var r := root.get_node_or_null("EndlessRunner") as EndlessRunner
	if r == null:
		r = EndlessRunner.new()
		r.name = "EndlessRunner"
		root.add_child(r)
	r._root = root
	return r


func is_running() -> bool:
	return state == State.RUNNING


## Start a fresh run from where the ship is, facing where it faces.
func start() -> void:
	if _root == null or _root.model == null:
		return
	_spawner = _root.ensure_ai_spawner()
	if _root.scenarios != null:
		_root.scenarios.stop(false)
	if _spawner != null:
		if not _spawner.ship_destroyed.is_connected(_on_ship_destroyed):
			_spawner.ship_destroyed.connect(_on_ship_destroyed)
		_spawner.auto_fleet = false
		_spawner.teardown()
	_wave_ships.clear()
	_root.revive_player()
	_rng.randomize()
	var xf := _root.model.global_transform
	_origin = xf.origin
	_dir = -xf.basis.z.normalized()
	_up = xf.basis.y.normalized()
	_right = _dir.cross(_up).normalized()
	_up = _right.cross(_dir).normalized()
	distance = 0.0
	elapsed = 0.0
	kills = 0
	_boost = 0.0
	_restart_in = -1.0
	_root.combo.reset()
	_build_pools()
	for i in _rocks.size():
		_place_rock(_rocks[i], lerpf(260.0, SPAWN_AHEAD, float(i) / float(_rocks.size())))
	_next_ring_s = 300.0
	for r in _rings:
		_place_ring(r)
	_next_wave_s = 500.0
	_prev_s = 0.0
	_root.set_speed_meter(_top() * MAX_SPEED * (1.0 + RING_BOOST))
	state = State.RUNNING
	_root.announce("ENDLESS RUN — dodge the rocks, thread the rings, ram what comes at you")
	changed.emit()


## Back to free roam: the pull, the meter and the content go; traffic returns.
func stop() -> void:
	if state == State.IDLE:
		return
	state = State.IDLE
	if _root != null and _root.model != null:
		_root.model.frame_velocity = Vector3.ZERO
		_root.set_speed_meter(0.0)
	if _pool_root != null:
		_pool_root.visible = false
	for s in _wave_ships:
		if is_instance_valid(s):
			s.teardown()
	_wave_ships.clear()
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.teardown()
		_spawner.auto_fleet = true
		_spawner.spawn_initial_fleet()
	changed.emit()


## One line for a HUD or panel: distance, speed and the best run.
func status_line() -> String:
	match state:
		State.RUNNING:
			return "RUN %d m  ·  %d KMH  ·  %d KOs  ·  BEST %d m" % [
				roundi(distance), roundi(speed * 3.6), kills, roundi(best)]
		State.OVER:
			return "RUN OVER — %d m  ·  BEST %d m" % [roundi(distance), roundi(best)]
	return ""


func _top() -> float:
	return maxf(_root.model.top_speed, 40.0)


# --- Per tick -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _root == null or _root.model == null:
		return
	match state:
		State.RUNNING:
			if _root.is_player_dead():
				_end_run()
				return
			_run_tick(delta)
		State.OVER:
			# A new run once the player is flying again.
			if not _root.is_player_dead():
				if _restart_in < 0.0:
					_restart_in = RESTART_DELAY
				_restart_in -= delta
				if _restart_in <= 0.0:
					start()


func _run_tick(delta: float) -> void:
	var model := _root.model
	elapsed += delta
	_boost = move_toward(_boost, 0.0, BOOST_FADE * delta)
	var ramp := clampf(elapsed / RAMP_SECONDS, 0.0, 1.0)
	speed = _top() * (lerpf(START_SPEED, MAX_SPEED, ramp) + _boost)
	var pos := model.global_position
	var rel := pos - _origin
	var s := rel.dot(_dir)
	distance = maxf(distance, s)
	# Pulled down the track; strayed too wide, eased back toward it.
	var lateral := rel - _dir * s
	var carry := _dir * speed
	var soft := CORRIDOR * CORRIDOR_SOFT
	if lateral.length() > soft:
		carry -= lateral.normalized() * (lateral.length() - soft) * 1.5
	model.frame_velocity = carry

	var hull_r := 4.0
	if _root.camera_rig != null:
		hull_r = _root.camera_rig.hull_radius
	for r in _rocks:
		var rs := float(r["s"])
		if rs < s - RECYCLE_BEHIND:
			_place_rock(r, s + SPAWN_AHEAD + _rng.randf_range(0.0, 200.0))
			continue
		var rp: Vector3 = r["pos"]
		if rp.distance_to(pos) < float(r["radius"]) + hull_r:
			_hit_rock(r, pos)
			_place_rock(r, s + SPAWN_AHEAD + _rng.randf_range(0.0, 200.0))
	for r in _rings:
		var rs := float(r["s"])
		if rs < s - RECYCLE_BEHIND:
			_place_ring(r)
			continue
		# Through the ring: crossed its plane this tick, inside its hole.
		var rp: Vector3 = r["pos"]
		if _prev_s < rs and s >= rs and (pos - rp - _dir * (s - rs)).length() < float(r["radius"]):
			_boost = minf(_boost + RING_BOOST, RING_BOOST * 2.0)
			_root.hit_word("ZOOM!", rp, Color("33d6ff"), 1.2)
			_place_ring(r)
	_prev_s = s
	if s >= _next_wave_s:
		_next_wave_s += WAVE_SPACING
		_spawn_wave(s)
	_clear_passed_ships(s)
	var line := status_line()
	if line != _last_status:
		_last_status = line
		changed.emit()


func _end_run() -> void:
	state = State.OVER
	_restart_in = -1.0
	_root.model.frame_velocity = Vector3.ZERO
	best = maxf(best, distance)
	_root.announce("RUN OVER — %d m (best %d m). A new run starts after the respawn." % [roundi(distance), roundi(best)])
	run_over.emit(distance)
	changed.emit()


# --- Content --------------------------------------------------------------------

func _build_pools() -> void:
	if _pool_root != null:
		_pool_root.visible = true
		return
	_pool_root = Node3D.new()
	_pool_root.name = "RunnerContent"
	# Placed per tick, drawn as placed (the flight scene's own rule).
	_pool_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_root.add_child(_pool_root)
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color("8d7b6c")
	rock_mat.roughness = 1.0
	for i in ROCK_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.material_override = rock_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pool_root.add_child(mi)
		_rocks.append({"node": mi, "pos": Vector3.ZERO, "radius": 10.0, "s": 0.0})
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color("33d6ff")
	for i in RING_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = ring_mesh
		mi.material_override = ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pool_root.add_child(mi)
		_rings.append({"node": mi, "pos": Vector3.ZERO, "radius": 28.0, "s": 0.0})


## A point [param s] down the track, [param off] across it (in the track's
## right/up plane).
func _track_point(s: float, off: Vector2) -> Vector3:
	return _origin + _dir * s + _right * off.x + _up * off.y


func _random_off(radius: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius


func _place_rock(r: Dictionary, s: float) -> void:
	var radius := _rng.randf_range(6.0, 24.0)
	var pos := _track_point(s, _random_off(CORRIDOR))
	r["s"] = s
	r["pos"] = pos
	r["radius"] = radius
	var mi := r["node"] as MeshInstance3D
	var squash := Vector3(_rng.randf_range(0.8, 1.25), _rng.randf_range(0.7, 1.1), _rng.randf_range(0.8, 1.25))
	var b := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)).scaled(squash * radius * 2.0)
	mi.global_transform = Transform3D(b, pos)


func _place_ring(r: Dictionary) -> void:
	var s := _next_ring_s
	_next_ring_s += RING_SPACING * _rng.randf_range(0.8, 1.2)
	var pos := _track_point(s, _random_off(CORRIDOR * 0.6))
	var radius := 30.0
	r["s"] = s
	r["pos"] = pos
	r["radius"] = radius
	# The torus lies in its XZ plane: turn its Y (the hole's axis) onto the track.
	var b := Basis(_right, _dir, _right.cross(_dir)).scaled(Vector3.ONE * radius)
	(r["node"] as MeshInstance3D).global_transform = Transform3D(b, pos)


func _hit_rock(r: Dictionary, ship_pos: Vector3) -> void:
	var rp: Vector3 = r["pos"]
	var away := (ship_pos - rp).normalized()
	var point := rp + away * float(r["radius"])
	_root.take_damage(ROCK_DAMAGE, point)
	_root.model.apply_knockback(away, 10.0)
	_root.hit_word("CRUNCH!", point, Color("ffb21e"), 1.1)
	# The hit costs the ride some of its speed boost, and a little time.
	_boost = 0.0
	elapsed = maxf(elapsed - 4.0, 0.0)


## A wave of popcorn fighters ahead, spread across the track, facing the
## ship: they come at the player (and yeet, if yeet combat is on).
func _spawn_wave(s: float) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	var count := mini(2 + int(distance / 2500.0), 6)
	var before := _spawner.ships().duplicate()
	_spawner.spawn_group_with(AiFactions.create(AiFactions.Archetype.BASIC_SWARM), count, 0)
	for ship: AiShip in _spawner.ships():
		if ship in before:
			continue
		var pos := _track_point(s + _rng.randf_range(750.0, 950.0), _random_off(CORRIDOR * 0.8))
		var xf := Transform3D(Basis.looking_at(-_dir, _up), pos)
		ship.global_transform = xf #error here
		if ship.model != null:
			ship.model.global_transform = xf
			ship.model.halt()
			ship.model.reset_physics_interpolation()
		_wave_ships.append(ship)


func _clear_passed_ships(s: float) -> void:
	var keep: Array[AiShip] = []
	for ship in _wave_ships:
		if not is_instance_valid(ship) or not ship._alive:
			continue
		if (ship.global_position - _origin).dot(_dir) < s - WAVE_BEHIND:
			ship.teardown()
			continue
		keep.append(ship)
	_wave_ships = keep


func _on_ship_destroyed(ship: AiShip) -> void:
	if state == State.RUNNING and is_instance_valid(ship) and ship.killed_by_player:
		kills += 1
