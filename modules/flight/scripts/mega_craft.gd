## MegaCraft: what makes a [LargeCraftGenerator] warship fight — its guns, its
## hangars and its hull. The generator only builds geometry (it stays combat-
## agnostic, see its class doc); this is the flight side of one craft.
##
## - Guns: every [constant GUN_COOLDOWN] seconds, while the player is in
##   range, the turrets nearest the player (at most [constant GUNS_PER_VOLLEY])
##   each fire a glowing bolt at where the player will be. A bolt that passes
##   the player's hull lands through [method FlightRoot.take_enemy_fire], so
##   god mode, the respawn grace and the damage dials all apply.
## - Hangars: every [constant LAUNCH_EVERY] seconds a fighter leaves a dock pad
##   (at most [constant MAX_LAUNCHED] of its own alive at once) and takes up
##   the fight on the craft's side ([signal launched]).
## - Hull: [method health] falls as parts are shot off; at
##   [constant KILL_SHARE] of its parts gone it breaks up in a chain of blasts
##   ([signal destroyed]) and [FlightRoot] clears it away.
##
## A craft that is not [member hostile] (a station, a friendly carrier) holds
## its fire and launches nothing; it can still be shot to pieces.
class_name MegaCraft
extends Node

signal destroyed(craft: MegaCraft)
signal launched(ship: AiShip)

## Share of the craft's parts that, shot off, wrecks it.
const KILL_SHARE := 0.3
## Seconds between volleys, and the most turrets that fire in one.
const GUN_COOLDOWN := 1.6
const GUNS_PER_VOLLEY := 6
## Bolt flight: speed (m/s), life (s), size (m) and hit (before the dials).
const BOLT_SPEED := 230.0
const BOLT_LIFE := 6.0
const BOLT_RADIUS := 2.4
const BOLT_DAMAGE := 24.0
## Guns reach at least this far, and further on a big craft (× its size).
const GUN_RANGE_MIN := 1300.0
const GUN_RANGE_PER_EXTENT := 1.6
## Seconds between fighter launches, and how many of its own may fly at once.
const LAUNCH_EVERY := 9.0
const MAX_LAUNCHED := 4
## Seconds the break-up runs before the wreck is cleared away.
const DEATH_TIME := 3.2

var gen: LargeCraftGenerator
var root: FlightRoot
## Shoots and launches at the player (false: a station, a friendly carrier).
var hostile := true
## The team its fighters fly for, and the teams they go for.
var team := FlightScenarios.ENEMY_TEAM
var enemies_of: Array[int] = [FlightScenarios.PLAYER_TEAM]
## The level's enemy damage dial, on top of [constant BOLT_DAMAGE].
var damage_mult := 1.0
## Launches fighters at all (a dreadnought's hangars and a mothership's bays).
var launches := true
## A level's boss: launches its fighters wherever the player is, not only once
## they are in gun range, so the fight comes to them.
var always_active := false
## A name for the HUD ("MOTHERSHIP", "DREADNOUGHT").
var label := "WARSHIP"

var _parts_start := 1
var _lost := 0
var _gun_clock := 2.0
var _launch_clock := 4.0
var _bolts: Array[Dictionary] = []
var _launched: Array[AiShip] = []
var _dead := false
var _death_t := 0.0
var _rng := RandomNumberGenerator.new()


## Take charge of [param craft] for [param flight_root].
func setup(craft: LargeCraftGenerator, flight_root: FlightRoot) -> void:
	gen = craft
	root = flight_root
	_rng.randomize()
	_parts_start = maxi(gen.part_count(), 1)
	gen.part_detached.connect(_on_part_detached)
	label = "MOTHERSHIP" if gen.archetype == LargeCraftGenerator.Archetype.MOTHERSHIP else "DREADNOUGHT"


## 1 = whole, 0 = breaking up.
func health() -> float:
	return clampf(1.0 - float(_lost) / (float(_parts_start) * KILL_SHARE), 0.0, 1.0)


func is_dead() -> bool:
	return _dead


## Where the craft is (its structure's middle), for markers and the camera.
func centre() -> Vector3:
	return gen.get_structure_center() if is_instance_valid(gen) else Vector3.INF


func radius() -> float:
	return gen.approx_extent() if is_instance_valid(gen) else 1.0


func _on_part_detached(_kind: String, _node: Node3D) -> void:
	if _dead:
		return
	_lost += 1
	if health() <= 0.0:
		_break_up()


func _process(delta: float) -> void:
	_tick_bolts(delta)
	if not is_instance_valid(gen):
		return
	if _dead:
		_tick_death(delta)
		return
	var model := root.active_model() if root != null else null
	if model == null or not hostile or root.is_player_dead():
		return
	var to_player := model.global_position - gen.global_position
	var reach := maxf(GUN_RANGE_MIN, gen.approx_extent() * GUN_RANGE_PER_EXTENT)
	var in_reach := to_player.length() <= reach
	if in_reach:
		_gun_clock -= delta
		if _gun_clock <= 0.0:
			_gun_clock = GUN_COOLDOWN * _rng.randf_range(0.85, 1.2)
			_volley(model)
	if launches and (in_reach or always_active):
		_launch_clock -= delta
		if _launch_clock <= 0.0:
			_launch_clock = LAUNCH_EVERY * _rng.randf_range(0.8, 1.25)
			_launch()


# --- Guns ----------------------------------------------------------------------

## The turrets nearest the player that can bear on them fire at the player's
## lead point.
func _volley(model: FlightModel) -> void:
	var target := model.global_position
	var muzzles := gen.get_turret_points()
	if muzzles.is_empty():
		return
	muzzles.sort_custom(func(a: Transform3D, b: Transform3D) -> bool:
		return a.origin.distance_squared_to(target) < b.origin.distance_squared_to(target))
	var fired := 0
	for m in muzzles:
		if fired >= GUNS_PER_VOLLEY:
			break
		var to := target - m.origin
		var dist := to.length()
		if dist < 1.0:
			continue
		# A turret on the far side of the hull can't bear on the player.
		var out := (m.origin - gen.get_structure_center()).normalized()
		if out.dot(to / dist) < -0.35:
			continue
		var lead := target + model.velocity * (dist / BOLT_SPEED) * 0.8
		var dir := (lead - m.origin).normalized()
		# A little spread: a wall of bolts, not one laser.
		dir = (dir + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.025).normalized()
		_spawn_bolt(m.origin, dir)
		fired += 1
	if fired > 0:
		var audio := SpaceAudio.instance()
		if audio != null:
			audio.play_blast(muzzles[0].origin, &"shatter")


func _spawn_bolt(pos: Vector3, dir: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BOLT_RADIUS
	sphere.height = BOLT_RADIUS * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	mesh_inst.mesh = sphere
	mesh_inst.material_override = ShipMaterials.glow_material(Color("ff5a3c"))
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh_inst)
	mesh_inst.global_position = pos
	_bolts.append({"node": mesh_inst, "velocity": dir * BOLT_SPEED, "life": BOLT_LIFE})


## Move the bolts; one that passes through the player's hull this frame lands.
func _tick_bolts(delta: float) -> void:
	if _bolts.is_empty():
		return
	var model := root.active_model() if root != null and is_instance_valid(root) else null
	var hit_r := 0.0
	var ship_pos := Vector3.INF
	if model != null:
		ship_pos = model.global_position
		hit_r = BOLT_RADIUS + (root.camera_rig.hull_radius if root.camera_rig != null else 3.0) * 0.8
	var still: Array[Dictionary] = []
	for b: Dictionary in _bolts:
		var node: MeshInstance3D = b["node"]
		if not is_instance_valid(node):
			continue
		var from := node.global_position
		var to := from + (b["velocity"] as Vector3) * delta
		node.global_position = to
		var life := float(b["life"]) - delta
		if ship_pos != Vector3.INF and _segment_distance(from, to, ship_pos) <= hit_r:
			root.take_enemy_fire(BOLT_DAMAGE * damage_mult, ship_pos, null)
			Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), to), 1.4, Color("ff7a4a"))
			node.queue_free()
			continue
		if life <= 0.0:
			node.queue_free()
			continue
		b["life"] = life
		still.append(b)
	_bolts = still


static func _segment_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var seg := to - from
	var t := clampf((point - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	return (from + seg * t).distance_to(point)


# --- Hangars -------------------------------------------------------------------

## A fighter out of a dock pad (or off the hull's edge when every pad is
## gone), flying for the craft's side.
func _launch() -> void:
	var alive: Array[AiShip] = []
	for s in _launched:
		if is_instance_valid(s) and s._alive:
			alive.append(s)
	_launched = alive
	if _launched.size() >= MAX_LAUNCHED:
		return
	var spawner := root.ensure_ai_spawner()
	if spawner == null:
		return
	# Free flight: a launch outranks far-off ambient traffic. A level's roster
	# is all fighters that matter, so there it only launches into free room.
	if root.scenarios == null or not root.scenarios.is_running():
		spawner.make_room(1, _launched)
	var ship := spawner.spawn_fighter_near(gen)
	if ship == null:
		return
	var pads := gen.get_dock_points()
	var xf: Transform3D
	var c := gen.get_structure_center()
	if not pads.is_empty():
		var pad := pads[_rng.randi_range(0, pads.size() - 1)]
		var out := (pad.origin - c).normalized()
		xf = Transform3D(Basis.looking_at(out, Vector3.UP if absf(out.y) < 0.95 else Vector3.FORWARD), pad.origin + out * 30.0)
	else:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1, 1)).normalized()
		xf = Transform3D(Basis.looking_at(dir, Vector3.UP), c + dir * (gen.approx_extent() + 40.0))
	ship.global_transform = xf
	if ship.model != null:
		ship.model.global_transform = xf
		ship.model.halt()
		ship.model.velocity = -xf.basis.z * 60.0
		ship.model.reset_physics_interpolation()
	ship.team_id = team
	ship.aggressive_to = enemies_of.duplicate()
	_launched.append(ship)
	launched.emit(ship)


# --- Break-up ------------------------------------------------------------------

func _break_up() -> void:
	_dead = true
	_death_t = 0.0
	hostile = false
	if root != null:
		root.big_notice("%s DOWN!" % label, "", Color("ffe23d"), 1.4)
		root.score += 2500
	destroyed.emit(self)


## A chain of blasts across the hull, each knocking a chunk loose, then gone.
func _tick_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	# About eight blasts a second, bigger toward the end.
	if floori(_death_t * 8.0) > floori(before * 8.0):
		var c := gen.get_structure_center()
		var r := gen.approx_extent()
		var p := c + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * r * 0.7
		var k := _death_t / DEATH_TIME
		CartoonBlast.spawn(root, p, lerpf(r * 0.08, r * 0.22, k), Vector3.UP, 0.6)
		gen.shatter_at(p, r * 0.25, (p - c).normalized() * 40.0)
		var audio := SpaceAudio.instance()
		if audio != null:
			audio.play_blast(p, &"explosion")
	if _death_t >= DEATH_TIME:
		if root != null:
			# The last word: a mushroom cloud standing over where it was.
			CartoonBlast.mushroom(root, gen.get_structure_center(), clampf(gen.approx_extent() * 0.35, 8.0, 400.0))
			Juice.shake(1.0, 0.8)
			root.remove_large_craft(gen)
		queue_free()


func _exit_tree() -> void:
	for b: Dictionary in _bolts:
		var node: Node = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	_bolts.clear()
