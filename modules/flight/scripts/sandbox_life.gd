## SandboxLife: what makes the sandbox a living system. [FlightRoot] adds one
## to a sandbox flight (a ship from the menu, no level).
##
## - Incidents are real. The [IncidentDirector] only lays out markers and
##   placeholder bodies; this dresses each one with the real thing and
##   resolves it from what happens:
##   - PIRATE AMBUSH: a hauler and three pirates going for it (and you).
##     Break the raid for points.
##   - FACTION SKIRMISH: a police patrol and a pirate band fighting each
##     other; you are not their target unless you join in.
##   - METEOR INCOMING: a shower of burning rocks across your path. They
##     bounce you and they hurt.
##   - DISTRESS CALL / DERELICT / RARE DRIFT / CARGO REQUEST: something
##     drifting out there (a crippled ship, a wreck, glowing pods) — fly to it
##     for points.
##   Now and then a pirate raid brings a megastructure dreadnought instead
##   of raiders: guns, launch bays, a hull shot off piece by piece.
## - Big ships: neutral freighter giants cross the system, and megastructures
##   stand in it as landmarks — a ring station by the main world, a sun-sized
##   one out by the far planets — named on the HUD like the planets are.
## - The player flies for the player's team, so raiders treat them as a
##   target and a patrol as a friend.
class_name SandboxLife
extends Node

## Points for breaking a raid, winning a fight you joined, and finding a
## drifting thing.
const RAID_POINTS := 500
const RESCUE_POINTS := 300
const FIND_POINTS := 200
## How close counts as "got there" for a drifting find (m, plus its size).
const FIND_REACH := 140.0
## Neutral giants: seconds between checks, how many cross at once, how far
## off they appear, and how far before they are cleared away.
const GIANT_EVERY := 40.0
const GIANTS_MAX := 1
const GIANT_SPAWN := Vector2(1600.0, 2600.0)
const GIANT_CLEAR := 7000.0
## A meteor shower: rocks, the seconds they arrive over, their speed, and the
## hit one lands (before the damage dials).
const METEORS := 8
const METEOR_SPREAD := 6.0
const METEOR_SPEED := Vector2(130.0, 210.0)
const METEOR_DAMAGE := 40.0
const METEOR_LIFE := 30.0
## Chance a raid is a dreadnought instead (once the first few minutes pass).
const WARSHIP_CHANCE := 0.35
const WARSHIP_AFTER := 150.0

var root: FlightRoot
var director: IncidentDirector
## Running jobs: {inc, kind, foes, friends, ward, find, rocks, t, done}.
var _jobs: Array[Dictionary] = []
var _giants: Array[AiShip] = []
var _giant_clock := 10.0
## Megastructure landmarks: {gen, mark} (mark is its entry in the landmarks).
var _structures: Array[Dictionary] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(flight_root: FlightRoot, incident_director: IncidentDirector) -> void:
	root = flight_root
	director = incident_director


func _ready() -> void:
	_rng.randomize()
	root.set_player_team(FlightScenarios.PLAYER_TEAM)
	if director != null:
		director.incident_started.connect(_on_incident_started)
		# Things keep happening: a new incident every so often, a couple at once.
		director.auto_spawn = true
		director.bubble_cooldown = 40.0
		director.max_active_incidents = 2
		director.min_player_dist = 800.0
		director.max_player_dist = 1600.0
	# Once the ship has been placed and the opening shot has landed.
	get_tree().create_timer(1.5, false).timeout.connect(_build_structures)


func _process(delta: float) -> void:
	_t += delta
	_tick_giants(delta)
	for s: Dictionary in _structures:
		var gen: LargeCraftGenerator = s["gen"]
		if is_instance_valid(gen):
			(s["mark"] as Dictionary)["position"] = gen.get_structure_center()
	for i in range(_jobs.size() - 1, -1, -1):
		var job: Dictionary = _jobs[i]
		job["t"] = float(job["t"]) + delta
		_tick_rocks(job, delta)
		if bool(job["done"]):
			if (job["rocks"] as Array).is_empty():
				_jobs.remove_at(i)
			continue
		_tick_job(job)


# --- Megastructure landmarks -----------------------------------------------------

## A ring station by the main world and a sun-sized structure out by a far
## planet (or the second world), both neutral, both named on the HUD.
func _build_structures() -> void:
	if not is_instance_valid(root) or root.space == null:
		return
	var lm := root.landmarks()
	if lm.is_empty():
		return
	var main: Dictionary = lm[0]
	var out := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)).normalized()
	_structure(LargeCraftGenerator.Archetype.RING_STATION, FlightRoot.CraftSize.DEFAULT,
		main["position"] + out * (float(main["radius"]) * 2.0 + 1800.0), "FREEPORT", Color("ffcc1a"))
	# The far one: by the outermost world there is.
	var far := main
	for e: Dictionary in lm:
		if bool(e.get("dynamic", false)) or float(e.get("radius", 0.0)) < 150.0:
			continue
		if (e["position"] as Vector3).length() > (far["position"] as Vector3).length():
			far = e
	if far != main:
		var kinds := [LargeCraftGenerator.Archetype.GATE_FRAME, LargeCraftGenerator.Archetype.TOWER_CLUSTER,
			LargeCraftGenerator.Archetype.MOTHERSHIP]
		var side := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 0.4), _rng.randf_range(-1, 1)).normalized()
		_structure(kinds[_rng.randi_range(0, kinds.size() - 1)], FlightRoot.CraftSize.PLANET,
			far["position"] + side * (float(far["radius"]) * 2.0 + 5000.0), "THE COLOSSUS", Color("ff8a1f"))


func _structure(kind: int, size: int, at: Vector3, title: String, col: Color) -> void:
	var gen := root.spawn_large_craft(kind, Vector3.ZERO, size, at)
	if gen == null:
		return
	# Neutral: no guns on the player, docks that pull (a mothership), and it
	# can still be shot to pieces.
	root.arm_large_craft(gen, false)
	var mark := {"name": title, "position": gen.get_structure_center(), "radius": gen.approx_extent(),
		"color": col, "dynamic": true}
	root.space.landmarks.append(mark)
	_structures.append({"gen": gen, "mark": mark})


# --- Neutral giants -----------------------------------------------------------

## Big freighters crossing the system, never coming at the player.
func _tick_giants(delta: float) -> void:
	var model := root.active_model()
	if model == null:
		return
	var alive: Array[AiShip] = []
	for g in _giants:
		if not is_instance_valid(g) or not g._alive:
			continue
		if g.global_position.distance_to(model.global_position) > GIANT_CLEAR:
			g.teardown()
			continue
		alive.append(g)
	_giants = alive
	_giant_clock -= delta
	if _giant_clock > 0.0 or _giants.size() >= GIANTS_MAX:
		return
	_giant_clock = GIANT_EVERY * _rng.randf_range(0.7, 1.3)
	var spawner := root.ensure_ai_spawner()
	if spawner == null:
		return
	var side := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-1, 1)).normalized()
	var pos := model.global_position + side * _rng.randf_range(GIANT_SPAWN.x, GIANT_SPAWN.y)
	var heading := side.cross(Vector3.UP).normalized()
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	var xf := Transform3D(Basis.looking_at(heading, Vector3.UP), pos)
	var g := spawner.spawn_big(xf, _rng.randf_range(3.5, 6.0), 0, AiFactions.create(AiFactions.Archetype.CONVOY_TRADER))
	if g == null:
		return
	_place(g, xf)
	g.model.velocity = heading * 40.0
	_giants.append(g)


# --- Incidents ----------------------------------------------------------------

func _on_incident_started(inc: Incident) -> void:
	if inc == null or root.phys_world == null:
		return
	# The director's stand-in bodies: invisible things to bump into. The real
	# cast replaces them.
	for b in inc.phys_bodies:
		root.phys_world.remove(b)
	inc.phys_bodies.clear()
	var job := {"inc": inc, "kind": inc.incident_type, "foes": [] as Array[AiShip], "friends": [] as Array[AiShip],
		"ward": null, "find": null, "mega": null, "rocks": [] as Array[Dictionary], "t": 0.0, "done": false}
	# Listed first, so making room for one side never clears the other.
	_jobs.append(job)
	match inc.incident_type:
		"pirate_raid":
			if _t > WARSHIP_AFTER and _rng.randf() < WARSHIP_CHANCE:
				_dress_warship(job)
			else:
				_dress_raid(job)
		"faction_skirmish":
			_dress_skirmish(job)
		"meteor_strike":
			_dress_meteors(job)
		_:
			_dress_find(job)


## A hauler (on its own team, so the raiders go for it) and three pirates.
func _dress_raid(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var spawner := root.ensure_ai_spawner()
	if spawner == null:
		return
	var xf := Transform3D(Basis.looking_at(Vector3(1, 0, 0.3).normalized(), Vector3.UP), inc.origin)
	var hauler := spawner.spawn_big(xf, 3.5, 3, AiFactions.create(AiFactions.Archetype.CONVOY_TRADER))
	if hauler != null:
		_place(hauler, xf)
		hauler.aggressive_to = [] as Array[int]
		job["ward"] = hauler
		_point_marker(inc, hauler)
	var foes := _group(AiFactions.Archetype.WOLF_PIRATE, 3, FlightScenarios.ENEMY_TEAM, inc.origin, 260.0)
	for f in foes:
		f.aggressive_to = [FlightScenarios.PLAYER_TEAM, 3] as Array[int]
		root.pin_marker(f, InteractionMarkers.COLORS[AiShip.Attitude.HOSTILE])
	job["foes"] = foes


## A police patrol and a pirate band at each other's throats; the player is
## nobody's target until they pick a side.
func _dress_skirmish(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var a := _group(AiFactions.Archetype.POLICE_PATROL, 3, 3, inc.origin + Vector3(-180, 0, 0), 120.0)
	# Kept before the other side spawns, so making room for it never clears these.
	job["friends"] = a
	var b := _group(AiFactions.Archetype.WOLF_PIRATE, 3, 4, inc.origin + Vector3(180, 0, 0), 120.0)
	for s in a:
		s.aggressive_to = [4] as Array[int]
	for s in b:
		s.aggressive_to = [3] as Array[int]
	job["friends"] = a
	job["foes"] = b
	if not a.is_empty():
		_point_marker(inc, a[0])


## A megastructure dreadnought with its guns and launch bays, coming in.
func _dress_warship(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var model := root.active_model()
	var gen := root.spawn_large_craft(LargeCraftGenerator.Archetype.DREADNOUGHT, Vector3.ZERO, FlightRoot.CraftSize.DEFAULT,
		inc.origin + (inc.origin - model.global_position).normalized() * 1500.0 if model != null else inc.origin)
	if gen == null:
		_dress_raid(job)
		return
	job["mega"] = root.arm_large_craft(gen, true)
	inc.title = "WARSHIP INBOUND"
	root.big_notice("WARSHIP!", "", Color("ff2a4a"), 1.4)


## Burning rocks streaking across the player's path over a few seconds.
func _dress_meteors(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var model := root.active_model()
	if model == null or root.space == null:
		return
	inc.title = "METEOR SHOWER"
	# They come from the incident's side and cross near where the ship will be.
	var from_dir := (inc.origin - model.global_position).normalized()
	for i in METEORS:
		var delay := _rng.randf_range(0.0, METEOR_SPREAD)
		(job["rocks"] as Array).append({"delay": delay, "from": from_dir, "node": null, "body": null, "life": METEOR_LIFE})


## Something drifting out there to fly to: a crippled ship, a wreck, pods.
func _dress_find(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var spawner := root.ensure_ai_spawner()
	if spawner == null:
		return
	var xf := Transform3D(Basis.looking_at(Vector3(0.3, 0.2, 1).normalized(), Vector3.UP), inc.origin)
	var size := 2.5 if inc.incident_type in ["distress_call", "derelict_tumble"] else 1.2
	var s := spawner.spawn_big(xf, size, 0, AiFactions.create(AiFactions.Archetype.CONVOY_TRADER))
	if s == null:
		return
	_place(s, xf)
	s._ai_paused = true
	s.player_proof = true
	s.systems.set_firing(false)
	# Drifting, slowly turning: plainly not flying anywhere.
	s.model.velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-2, 2), _rng.randf_range(-6, 6))
	job["find"] = s
	_point_marker(inc, s)
	root.pin_marker(s, Color("ffcc1a"))


func _tick_job(job: Dictionary) -> void:
	var inc: Incident = job["inc"]
	var model := root.active_model()
	var expired := inc.is_resolved
	match String(job["kind"]):
		"pirate_raid":
			var mega: MegaCraft = job["mega"]
			if mega != null:
				if not is_instance_valid(mega) or mega.is_dead():
					_finish(job, "pirates_routed", RAID_POINTS * 4, "WARSHIP DOWN!")
				elif expired:
					_finish(job, "", 0, "")
				return
			var ward: AiShip = job["ward"]
			if (job["foes"] as Array).is_empty():
				# Nobody came (no room for them): nothing to pay for.
				_finish(job, "", 0, "")
			elif _alive(job["foes"]).is_empty():
				_finish(job, "pirates_routed", RAID_POINTS, "RAID BROKEN!")
			elif ward != null and (not is_instance_valid(ward) or not ward._alive):
				_finish(job, "hauler_destroyed", 0, "")
			elif expired:
				_finish(job, "", 0, "")
		"faction_skirmish":
			var a := _alive(job["friends"])
			var b := _alive(job["foes"])
			if (job["friends"] as Array).is_empty() or (job["foes"] as Array).is_empty():
				_finish(job, "", 0, "")
			elif a.is_empty() or b.is_empty():
				_finish(job, "faction_b_won" if a.is_empty() else "faction_a_won", 0, "")
			elif expired:
				_finish(job, "", 0, "")
		"meteor_strike":
			if float(job["t"]) > METEOR_SPREAD + 4.0:
				_finish(job, "passed", 0, "")
		_:
			var s: AiShip = job["find"]
			if s == null or not is_instance_valid(s) or not s._alive:
				_finish(job, "lost", 0, "")
			elif model != null and model.global_position.distance_to(s.global_position) < FIND_REACH + CampaignLevelOverlay.ship_radius(s):
				var rescue := String(job["kind"]) == "distress_call"
				_finish(job, "player_rescued", RESCUE_POINTS if rescue else FIND_POINTS, "RESCUED!" if rescue else "SALVAGED!")
				s.teardown()
			elif expired:
				_finish(job, "", 0, "")
				s.teardown()


## End a job: resolve its incident (if still open), pay the player and say
## so. [param how] "" when it simply ran out.
func _finish(job: Dictionary, how: String, points: int, word: String) -> void:
	job["done"] = true
	var inc: Incident = job["inc"]
	if how != "" and not inc.is_resolved:
		inc.resolve(how, "player" if points > 0 else null)
	if points > 0:
		root.score += points
		var at := root.active_model().global_position if root.active_model() != null else inc.origin
		root.hit_word("%s +%d" % [word, points], at, Color("ffe23d"), 1.4)


# --- Meteors ------------------------------------------------------------------

func _tick_rocks(job: Dictionary, delta: float) -> void:
	var rocks: Array = job["rocks"]
	if rocks.is_empty():
		return
	var model := root.active_model()
	var still: Array[Dictionary] = []
	for r: Dictionary in rocks:
		if r["node"] == null:
			r["delay"] = float(r["delay"]) - delta
			if float(r["delay"]) <= 0.0 and model != null:
				_launch_rock(r, model)
			still.append(r)
			continue
		var node: Node3D = r["node"]
		r["life"] = float(r["life"]) - delta
		if not is_instance_valid(node) or float(r["life"]) <= 0.0:
			_drop_rock(r)
			continue
		still.append(r)
	job["rocks"] = still


## One burning rock from far off on the shower's side, aimed to cross close
## by where the ship is heading.
func _launch_rock(r: Dictionary, model: FlightModel) -> void:
	var size := _rng.randf_range(7.0, 20.0)
	var from_dir: Vector3 = r["from"]
	var side := from_dir.cross(Vector3.UP).normalized()
	var start := model.global_position + from_dir * 1600.0 + side * _rng.randf_range(-500.0, 500.0) \
		+ Vector3.UP * _rng.randf_range(-200.0, 200.0)
	var aim := model.global_position + model.velocity * 4.0 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * 140.0
	var vel := (aim - start).normalized() * _rng.randf_range(METEOR_SPEED.x, METEOR_SPEED.y)
	var node := Node3D.new()
	node.name = "Meteor"
	var rock := MeshInstance3D.new()
	rock.mesh = root.space._make_rock(_rng.randi_range(0, 4))
	rock.material_override = root.space._rock_material(_rng.randi_range(0, 3))
	rock.scale = Vector3.ONE * size
	node.add_child(rock)
	# The burn: a hot glow round it.
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size * 1.25
	sphere.height = size * 2.5
	sphere.radial_segments = 10
	sphere.rings = 6
	glow.mesh = sphere
	glow.material_override = ShipMaterials.glow_material(Color("ff7a2a"))
	glow.transparency = 0.55
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(glow)
	root.add_child(node)
	node.global_position = start
	var body := PhysBody.new(size * size * size * 0.02, size)
	body.node = node
	body.layer = PhysBody.Layer.ROCK
	body.velocity = vel
	body.angular = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	body.impacted.connect(_on_meteor_hit.bind(body))
	root.phys_world.add(body)
	r["node"] = node
	r["body"] = body


func _on_meteor_hit(other: PhysBody, _impulse: float, point: Vector3, _normal: Vector3, closing: float, body: PhysBody) -> void:
	var model := root.active_model()
	if model == null or other != model.phys_body() or body.has_meta("hit"):
		return
	body.set_meta("hit", true)
	root.take_enemy_fire(METEOR_DAMAGE * clampf(closing / 120.0, 0.5, 2.0), point, null)
	root.hit_word("METEOR!", point, Color("ff7a2a"), 1.1)


func _drop_rock(r: Dictionary) -> void:
	var body: PhysBody = r["body"]
	if body != null and root.phys_world != null:
		root.phys_world.remove(body)
	var node: Node3D = r["node"]
	if is_instance_valid(node):
		node.queue_free()


# --- Helpers ------------------------------------------------------------------

## [param count] ships of an archetype on [param team], placed round
## [param at] (the spawner drops them by the player).
func _group(arch: int, count: int, team: int, at: Vector3, spread: float) -> Array[AiShip]:
	var out: Array[AiShip] = []
	var spawner := root.ensure_ai_spawner()
	if spawner == null:
		return out
	spawner.make_room(count, _cast())
	var before := spawner.ships().duplicate()
	spawner.spawn_group_with(AiFactions.create(arch), count, team)
	for s: AiShip in spawner.ships():
		if s in before:
			continue
		var p := at + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)) * spread
		_place(s, Transform3D(Basis.looking_at((at - p).normalized() if p.distance_to(at) > 1.0 else Vector3.FORWARD, Vector3.UP), p))
		out.append(s)
	return out


## Every ship some running job or crossing giant owns (never cleared for room).
func _cast() -> Array:
	var out: Array = _giants.duplicate()
	for job: Dictionary in _jobs:
		out.append_array(job["foes"])
		out.append_array(job["friends"])
	return out


func _alive(list: Array) -> Array[AiShip]:
	var out: Array[AiShip] = []
	for s in list:
		if is_instance_valid(s) and (s as AiShip)._alive:
			out.append(s)
	return out


## The incident's floating marker rides on the real ship instead of the stand-in.
func _point_marker(inc: Incident, ship: AiShip) -> void:
	if is_instance_valid(inc.marker) and ship.model != null:
		inc.marker.target_node = ship.model


func _place(s: AiShip, xf: Transform3D) -> void:
	s.global_transform = xf
	if s.model != null:
		s.model.global_transform = xf
		s.model.halt()
		s.model.reset_physics_interpolation()


func _exit_tree() -> void:
	for job: Dictionary in _jobs:
		for r: Dictionary in job["rocks"]:
			_drop_rock(r)
