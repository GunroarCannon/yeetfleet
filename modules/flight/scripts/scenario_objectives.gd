## ScenarioObjectives: the goals of the non-"kill them all" scenarios — where
## to go, what to collect, who to protect — and the markers that show them.
##
## [FlightScenarios] owns one while such a scenario runs: [method begin] lays
## the objective out from the player's ship, [method tick] advances it and
## reports won (1) / lost (-1) / running (0), [method status] is the band's
## line and [method clear] takes everything down.
##
## - DELIVER: cargo packages to fly into and grab, in any order.
## - GATES: rings to thread in any order (a generous pass: through the hoop
##   either way, or just close to its middle).
## - SALVAGE: cargo pods scattered round the player, collected by touching.
## - ESCORT: a big friendly hauler (or capital ship) flies a route to a
##   destination at its own pace; it must arrive alive. Waves go for it.
## - ASSAULT: a mothership to bring down (it launches fighters).
## - DOCK: fly into a giant friendly carrier's glowing bay and come to rest.
## - ESCORT with [code]hold_time[/code] (PROTECT): the hauler is stranded;
##   keep it alive until the clock runs out.
## - VOYAGE: fly out to the system's farthest named planet.
##
## An escort's route is drawn as a dashed gold line from the hauler to its
## beacon, and the band says how much of it is done.
##
## The way to the current goal is one 3D arrowhead at the top-centre of the
## view ([GoalPointer3D]), turning to point through 3D space at it, plus a
## glowing beacon (a ring on a beam of light) standing at the goal itself.
##
## Goals pull: every go-here goal has a gravity well that draws the player in
## from [constant PULL_REACH], a player flying roughly at one is bent onto it,
## like the launch magnet bends onto ships ([method _attract]), and [method
## magnet_points] lets a slingshot aim snap onto them. They also catch the
## ship from further out than their glow suggests ([constant REACH]).
class_name ScenarioObjectives
extends Node3D

## Kinds (mirror [enum FlightScenarios.Objective]'s new entries).
enum Kind { DELIVER, GATES, SALVAGE, ESCORT, ASSAULT, DOCK, VOYAGE }

## Metres from a drop point / pod that counts as there: generous, well past
## the beacon's own ring, so a near pass never "just misses".
const REACH := 170.0
## The goals' gravity well: reach (m) and pull at the goal (m/s²), easing
## to nothing at the edge.
const PULL_REACH := 750.0
const PULL_ACCEL := 70.0
## The guarded ship's hull, per unit of its size (way tougher than a ship
## its size: it is the mission).
const ESCORT_HP_PER_SIZE := 3200.0
## The escort counts as arrived this close to its destination.
const ESCORT_ARRIVE := 160.0
## The guarded ship's leash on the player: past this many metres from it the
## player drifts back toward it, up to [constant ESCORT_PULL] m/s² at twice
## the distance. Slight: a nudge to stay near, never a tow.
const ESCORT_LEASH := 260.0
const ESCORT_PULL := 16.0
## The goal magnet: reach (m), cone (degrees off the flight) and the most it
## turns the flight (degrees/s, harder close in).
const MAGNET_REACH := 900.0
const MAGNET_CONE_DEG := 35.0
const MAGNET_TURN_DEG := 70.0
## Gate ring radius (the hoop's middle) and how near its middle counts.
const GATE_RADIUS := 34.0
const GATE_PASS := GATE_RADIUS * 3.4
## Dock: seconds held in the bay below [constant DOCK_SPEED] m/s.
const DOCK_HOLD := 1.5
const DOCK_SPEED := 40.0
## Length of a courier package and a salvage pod (m): big enough to read
## from far off.
const PACKAGE_SIZE := 38.0
const POD_SIZE := 30.0
const BLUE := Color(0.22, 0.55, 1.0)
const GOLD := Color("ffcc1a")

var kind: int = Kind.DELIVER
## Points to reach in order (DELIVER, GATES), or to collect (SALVAGE).
var points: Array[Vector3] = []
var done := 0
## The ship being escorted / assaulted / docked with.
var ship: AiShip = null
var destination := Vector3.ZERO

var _root: FlightRoot
var _spawner: AiSpawner
var _config: Dictionary
var _markers: Array[Node3D] = []
var _arrow: GoalPointer3D
var _dock_hold := 0.0
var _escort_speed := 50.0
var _gate_axis: Array[Vector3] = []
## Each gate's side of its plane last tick (for "went through").
var _gate_side: Array[float] = []
var _passed: Array[bool] = []
var _t := 0.0
## Why the objective was lost ("ESCORT DESTROYED", "OUT OF TIME"), or "".
var lose_reason := ""
## PROTECT: seconds the stranded hauler must be kept alive (0 = an escort run).
var _hold := 0.0
## An escort's whole route length (m), for the band's "% done".
var _route_len := 1.0
## The dashed line from the hauler to its beacon.
var _route_line: MeshInstance3D = null
## VOYAGE: the planet's name and radius.
var _voyage_name := ""
var _voyage_radius := 0.0


## Lay the objective out. [param k] is a [enum Kind].
func begin(k: int, config: Dictionary, root: FlightRoot, spawner: AiSpawner) -> void:
	kind = k
	_config = config
	_root = root
	_spawner = spawner
	done = 0
	points.clear()
	_gate_axis.clear()
	_gate_side.clear()
	_passed.clear()
	var xf := root.model.global_transform
	var fwd := -xf.basis.z
	var up := xf.basis.y
	var right := xf.basis.x
	var origin := xf.origin
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	match kind:
		Kind.DELIVER:
			var p := origin
			var dir := fwd
			for i in int(config.get("points", 3)):
				# Each leg swings off the last, so the route bends.
				dir = dir.rotated(up, rng.randf_range(-1.1, 1.1)).rotated(right, rng.randf_range(-0.35, 0.35)).normalized()
				p += dir * float(config.get("spacing", 1000.0)) * rng.randf_range(0.8, 1.2)
				points.append(p)
				# A real package to grab, not an empty beacon.
				_markers.append(_pod(p, PACKAGE_SIZE))
		Kind.GATES:
			var p := origin
			var dir := fwd
			for i in int(config.get("gates", 8)):
				dir = dir.rotated(up, rng.randf_range(-0.6, 0.6)).rotated(right, rng.randf_range(-0.3, 0.3)).normalized()
				p += dir * rng.randf_range(380.0, 560.0)
				points.append(p)
				_gate_axis.append(dir)
				_gate_side.append((origin - p).dot(dir))
				_passed.append(false)
				_markers.append(_gate(p, dir, GATE_RADIUS))
		Kind.SALVAGE:
			for i in int(config.get("pods", 6)):
				var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.35, 0.35), rng.randf_range(-1.0, 1.0)).normalized()
				var p := origin + off * rng.randf_range(250.0, float(config.get("spacing", 800.0)))
				points.append(p)
				_markers.append(_pod(p, POD_SIZE))
		Kind.ESCORT:
			_hold = float(config.get("hold_time", 0.0))
			# PROTECT: stranded where it is (the "destination" is its own spot).
			destination = origin + fwd * (0.0 if _hold > 0.0 else float(config.get("route", 3500.0)))
			_route_len = maxf(origin.distance_to(destination), 1.0)
			_escort_speed = float(config.get("escort_speed", 50.0))
			ship = spawner.spawn_pilot_vessel(xf, float(config.get("escort_size", 4.0)))
			if ship != null:
				ship.is_pilot_vessel = false
				ship._ai_paused = true
				ship.team_id = FlightScenarios.PLAYER_TEAM
				ship.player_proof = true
				ship.max_hp = ESCORT_HP_PER_SIZE * float(config.get("escort_size", 4.0)) * float(config.get("escort_hp", 1.0))
				ship.hp = ship.max_hp
				ship.systems.set_firing(false)
				ship.model.external_drive = true
				# A gold target on it, held at the screen edge when out of view.
				root.pin_marker(ship, GOLD)
			if _hold <= 0.0:
				_markers.append(_beacon(destination, GOLD, 90.0))
				_route_line = _dashed_line(GOLD)
		Kind.VOYAGE:
			# The farthest named body (the moon moves, so not that one).
			var best := {}
			for lm: Dictionary in root.landmarks():
				if bool(lm.get("dynamic", false)):
					continue
				if best.is_empty() or origin.distance_to(lm["position"]) > origin.distance_to(best["position"]):
					best = lm
			if best.is_empty():
				best = {"name": "DEEP SPACE", "position": origin + fwd * 8000.0, "radius": 200.0}
			_voyage_name = String(best["name"]).to_upper()
			_voyage_radius = float(best.get("radius", 200.0))
			destination = best["position"]
			# The goal: a beacon just above its surface, on the side facing us.
			var p := destination + (origin - destination).normalized() * _voyage_radius * 1.25
			points.append(p)
			_markers.append(_beacon(p, BLUE, maxf(_voyage_radius * 0.15, 120.0)))
		Kind.ASSAULT:
			ship = spawner.spawn_mother()
			if ship != null:
				var pos := origin + fwd * float(config.get("enemy_distance", 1400.0))
				_place(ship, Transform3D(Basis.looking_at(-fwd, up), pos))
				ship.team_id = FlightScenarios.ENEMY_TEAM
				var enemy_of: Array[int] = [FlightScenarios.PLAYER_TEAM]
				ship.aggressive_to = enemy_of
		Kind.DOCK:
			ship = spawner.spawn_pilot_vessel(xf, float(config.get("escort_size", 10.0)))
			if ship != null:
				ship.is_pilot_vessel = false
				ship._ai_paused = true
				ship.team_id = FlightScenarios.PLAYER_TEAM
				var pos := origin + fwd * float(config.get("route", 2500.0))
				_place(ship, Transform3D(Basis.looking_at(fwd, up), pos))
				ship.systems.set_firing(false)
				var r := _ship_radius(ship)
				# The bay: off the carrier's stern, big enough to fly into.
				destination = pos + fwd * r * 1.1
				_markers.append(_beacon(destination, BLUE, maxf(r * 0.3, 60.0)))
	_arrow = GoalPointer3D.new()
	var cam := root.camera_node()
	if cam != null:
		cam.add_child(_arrow)
	else:
		add_child(_arrow)


## Advance the objective. 1 won, -1 lost, 0 still running.
func tick(delta: float) -> int:
	_t += delta
	var model := _root.model
	if model == null:
		return 0
	var pos := model.global_position
	for i in _markers.size():
		# Beacons turn slowly; the collected / passed ones are hidden.
		if is_instance_valid(_markers[i]):
			_markers[i].rotate_object_local(Vector3.UP, delta * 0.6)
	match kind:
		Kind.DELIVER:
			# Any order: whichever beacon the player reaches counts.
			for i in points.size():
				if _markers[i].visible and pos.distance_to(points[i]) < REACH + _hull():
					_markers[i].visible = false
					done += 1
					_root.hit_word("CARGO %d/%d!" % [done, points.size()], points[i], GOLD, 1.3)
					GameAudio.ui(&"coin")
			if done >= points.size():
				return 1
		Kind.GATES:
			# Any order. Through the hoop either way, or close to its middle.
			for i in points.size():
				if _passed[i]:
					continue
				var p := points[i]
				var axis := _gate_axis[i]
				var s := (pos - p).dot(axis)
				var crossed := signf(s) != signf(_gate_side[i]) and (pos - p - axis * s).length() < GATE_PASS
				_gate_side[i] = s
				if crossed or pos.distance_to(p) < GATE_RADIUS * 2.6 + _hull():
					_passed[i] = true
					_markers[i].visible = false
					done += 1
					_root.hit_word("RING %d/%d!" % [done, points.size()], p, BLUE, 1.2)
			if done >= points.size():
				return 1
		Kind.SALVAGE:
			for i in points.size():
				if _markers[i].visible and pos.distance_to(points[i]) < REACH + _hull():
					_markers[i].visible = false
					_root.hit_word("GOT IT!", points[i], GOLD, 1.1)
					GameAudio.ui(&"coin")
					done += 1
			if done >= points.size():
				return 1
		Kind.ESCORT:
			if ship == null or not is_instance_valid(ship) or not ship._alive:
				lose_reason = "ESCORT DESTROYED"
				return -1
			if _hold > 0.0:
				# PROTECT: it sits and drifts; hold out till the clock is done.
				ship.model.velocity = ship.model.velocity.move_toward(Vector3.ZERO, 20.0 * delta)
				if _t >= _hold:
					_root.hit_word("SAFE!", ship.global_position, GOLD, 1.6)
					return 1
				_attract(delta)
				_lay_arrow(delta)
				return 0
			_draw_route()
			var to := destination - ship.global_position
			if to.length() < ESCORT_ARRIVE:
				ship.model.velocity = Vector3.ZERO
				return 1
			var dir := to.normalized()
			ship.model.velocity = ship.model.velocity.move_toward(dir * _escort_speed, _escort_speed * delta)
			# Turn the hull onto its course, gently.
			var b := ship.model.global_transform.basis
			var want := Basis.looking_at(dir, b.y)
			ship.model.global_transform.basis = Basis(b.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-1.2 * delta)))
		Kind.ASSAULT:
			if ship == null or not is_instance_valid(ship) or not ship._alive:
				return 1
		Kind.VOYAGE:
			if pos.distance_to(points[0]) < REACH * 1.5 + _hull() or pos.distance_to(destination) < _voyage_radius * 1.4:
				_root.hit_word("ARRIVED!", pos, BLUE, 1.6)
				return 1
		Kind.DOCK:
			if ship == null or not is_instance_valid(ship) or not ship._alive:
				lose_reason = "CARRIER DESTROYED"
				return -1
			var r := maxf(_ship_radius(ship) * 0.3, 60.0)
			if pos.distance_to(destination) < r and model.velocity.length() < DOCK_SPEED:
				_dock_hold += delta
				if _dock_hold >= DOCK_HOLD:
					_root.hit_word("DOCKED!", destination, BLUE, 1.6)
					return 1
			else:
				_dock_hold = 0.0
	var limit := float(_config.get("time_limit", 0.0))
	if limit > 0.0 and _t >= limit:
		lose_reason = "OUT OF TIME"
		return -1
	_attract(delta)
	_lay_arrow(delta)
	return 0


## The goal magnet: bend the player's flight onto the nearest goal it is
## roughly heading for, up to [constant MAGNET_TURN_DEG]°/s (harder close in).
func _attract(delta: float) -> void:
	var model := _root.model
	if model == null or _root.controls_locked():
		return
	_pull(delta)
	_escort_leash(delta)
	var v := model.velocity
	var sp := v.length()
	if sp < 20.0:
		return
	var dir := v / sp
	var pos := model.global_position
	var best := Vector3.INF
	var best_ang := deg_to_rad(MAGNET_CONE_DEG)
	for p in magnet_points():
		var to := p - pos
		var d := to.length()
		if d < 1.0 or d > MAGNET_REACH:
			continue
		var ang := dir.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = p
	if best == Vector3.INF:
		return
	var near := 1.0 - clampf(pos.distance_to(best) / MAGNET_REACH, 0.0, 1.0)
	var rate := deg_to_rad(MAGNET_TURN_DEG) * (0.5 + 1.5 * near)
	var want := (best - pos).normalized()
	if best_ang > 1e-4:
		model.velocity = dir.slerp(want, minf(rate * delta / best_ang, 1.0)).normalized() * sp


## The gravity well round the nearest goal: a steady pull toward it inside
## [constant PULL_REACH], stronger the closer the ship is, whatever way it is
## flying (even sitting still).
func _pull(delta: float) -> void:
	var model := _root.model
	var pos := model.global_position
	var best := Vector3.INF
	var bd := PULL_REACH
	for p in magnet_points():
		var d := pos.distance_to(p)
		if d < bd:
			bd = d
			best = p
	if best == Vector3.INF or bd < 1.0:
		return
	var k := 1.0 - bd / PULL_REACH
	model.velocity += (best - pos) / bd * PULL_ACCEL * (0.25 + 0.75 * k * k) * delta


## The guarded ship pulls the player back when they stray (see [constant
## ESCORT_LEASH]).
func _escort_leash(delta: float) -> void:
	if kind != Kind.ESCORT or ship == null or not is_instance_valid(ship) or not ship._alive:
		return
	var model := _root.model
	var to := ship.global_position - model.global_position
	var d := to.length()
	if d <= ESCORT_LEASH:
		return
	var k := clampf((d - ESCORT_LEASH) / ESCORT_LEASH, 0.0, 1.0)
	model.velocity += to / d * ESCORT_PULL * k * delta


## The goals that pull (and a slingshot aim snaps onto): rings not yet
## passed, the next drop point, pods left, the dock bay.
func magnet_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	match kind:
		Kind.GATES:
			for i in points.size():
				if not _passed[i]:
					out.append(points[i])
		Kind.DELIVER:
			for i in points.size():
				if _markers[i].visible:
					out.append(points[i])
		Kind.SALVAGE:
			for i in points.size():
				if _markers[i].visible:
					out.append(points[i])
		Kind.DOCK:
			out.append(destination)
		Kind.VOYAGE:
			out.append_array(points)
	return out


## A dashed line mesh in [param col], redrawn by [method _draw_route].
func _dashed_line(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Route"
	mi.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, 0.7)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn in world space, whatever this node's own transform.
	mi.top_level = true
	add_child(mi)
	return mi


## The escort's way ahead: dashes from the hauler to its beacon, so where it
## is going is plain to see.
func _draw_route() -> void:
	if _route_line == null or ship == null or not is_instance_valid(ship):
		return
	var m := _route_line.mesh as ImmediateMesh
	m.clear_surfaces()
	var from := ship.global_position
	var span := destination - from
	var n := clampi(int(span.length() / 60.0), 1, 80)
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in n:
		m.surface_add_vertex(from + span * (float(i) / n))
		m.surface_add_vertex(from + span * ((i + 0.55) / n))
	m.surface_end()


## The band's line for this objective.
func status() -> String:
	var line := String(_config.get("name", "")).to_upper()
	var goal := goal_position()
	var far := ""
	if goal != Vector3.INF and _root.model != null:
		far = "  ·  %s" % _fmt_dist(_root.model.global_position.distance_to(goal))
	match kind:
		Kind.DELIVER:
			line += "  ·  CARGO %d/%d" % [done, points.size()] + far
		Kind.GATES:
			line += "  ·  RINGS %d/%d" % [done, points.size()] + far
		Kind.SALVAGE:
			line += "  ·  %d/%d PODS" % [done, points.size()] + far
		Kind.ESCORT:
			if ship != null and is_instance_valid(ship):
				var hull := roundi(ship.hp / maxf(ship.max_hp, 1.0) * 100.0)
				if _hold > 0.0:
					var left := maxi(ceili(_hold - _t), 0)
					line += "  ·  HULL %d%%  ·  HOLD OUT %d:%02d" % [hull, left / 60, left % 60]
				else:
					var to_go := ship.global_position.distance_to(destination)
					line += "  ·  HULL %d%%  ·  ROUTE %d%%  ·  %s TO GO" % [
						hull, clampi(roundi((1.0 - to_go / _route_len) * 100.0), 0, 100), _fmt_dist(to_go)]
		Kind.VOYAGE:
			line = "REACH %s" % _voyage_name + far
		Kind.ASSAULT:
			if ship != null and is_instance_valid(ship):
				line += "  ·  CARRIER %d%%" % roundi(ship.hp / maxf(ship.max_hp, 1.0) * 100.0) + far
		Kind.DOCK:
			line += "  ·  INTO THE BAY, SLOW" + far
	var limit := float(_config.get("time_limit", 0.0))
	if limit > 0.0:
		var left := maxi(ceili(limit - _t), 0)
		line += "  ·  %d:%02d" % [left / 60, left % 60]
	return line


## Seconds left on the clock, or -1 when this objective is not timed.
func time_left() -> float:
	if kind == Kind.ESCORT and _hold > 0.0:
		return maxf(_hold - _t, 0.0)
	var limit := float(_config.get("time_limit", 0.0))
	return maxf(limit - _t, 0.0) if limit > 0.0 else -1.0


## Where the arrow points now (Vector3.INF: nowhere).
func goal_position() -> Vector3:
	match kind:
		Kind.GATES, Kind.SALVAGE, Kind.DELIVER:
			var best := Vector3.INF
			var bd := INF
			var pos := _root.model.global_position if _root.model != null else Vector3.ZERO
			for i in points.size():
				var open: bool = not _passed[i] if kind == Kind.GATES else _markers[i].visible
				if open and pos.distance_to(points[i]) < bd:
					bd = pos.distance_to(points[i])
					best = points[i]
			return best
		Kind.ESCORT:
			# Stay with the convoy; point at it when drifting away.
			if ship != null and is_instance_valid(ship):
				var d := _root.model.global_position.distance_to(ship.global_position)
				return ship.global_position if d > 600.0 or _hold > 0.0 else destination
			return destination
		Kind.VOYAGE:
			return points[0] if not points.is_empty() else Vector3.INF
		Kind.ASSAULT:
			return ship.global_position if ship != null and is_instance_valid(ship) else Vector3.INF
		Kind.DOCK:
			return destination
	return Vector3.INF


func clear() -> void:
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()
	if ship != null and is_instance_valid(ship) and ship._alive:
		ship.teardown()
	ship = null
	queue_free()


# --- Markers ---------------------------------------------------------------------

func _lay_arrow(delta: float) -> void:
	if _arrow == null or not is_instance_valid(_arrow):
		return
	var goal := goal_position()
	var cam := _root.camera_node()
	var model := _root.model
	if goal == Vector3.INF or cam == null or model == null or _root.controls_locked():
		_arrow.hide_pointer()
		return
	var centre := model.get_global_transform_interpolated().origin
	if centre.distance_to(goal) < REACH:
		_arrow.hide_pointer()
		return
	var col := GOLD if kind in [Kind.ESCORT, Kind.SALVAGE, Kind.DELIVER] else BLUE
	_arrow.point_at(cam, centre, goal, delta, col)


func _hull() -> float:
	return _root.camera_rig.hull_radius if _root.camera_rig != null else 4.0


## A ring on a beam of light standing over [param at], visible from afar.
func _beacon(at: Vector3, col: Color, radius: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.86
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _glow(col, 1.0)
	n.add_child(ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.08
	cyl.bottom_radius = radius * 0.08
	cyl.height = radius * 30.0
	cyl.radial_segments = 8
	cyl.rings = 1
	beam.mesh = cyl
	beam.material_override = _glow(col, 0.35)
	n.add_child(beam)
	return n


## A ring to fly through, facing along [param axis].
func _gate(at: Vector3, axis: Vector3, radius: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := axis.cross(up).normalized()
	n.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), at)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 1.7
	torus.outer_radius = radius * 2.0
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _glow(BLUE, 1.0)
	n.add_child(ring)
	return n


## A glowing cargo pod: a banded canister ([CargoPod]) in a soft halo, with
## a short pillar of light so it can be spotted from far off.
func _pod(at: Vector3, length := POD_SIZE) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	n.add_child(CargoPod.build(length, GOLD))
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = length * 0.06
	cyl.bottom_radius = length * 0.06
	cyl.height = length * 7.0
	cyl.radial_segments = 8
	cyl.rings = 1
	pillar.mesh = cyl
	pillar.material_override = _glow(GOLD, 0.22)
	n.add_child(pillar)
	var halo := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = length * 0.8
	s.height = length * 1.6
	s.radial_segments = 12
	s.rings = 6
	halo.mesh = s
	halo.material_override = _glow(GOLD, 0.12)
	n.add_child(halo)
	return n


static func _glow(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if alpha < 1.0 else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _ship_radius(s: AiShip) -> float:
	if s.model != null and s.model.phys_body() != null:
		return s.model.phys_body().radius
	return 40.0


static func _place(s: AiShip, xf: Transform3D) -> void:
	s.global_transform = xf
	if s.model != null:
		s.model.global_transform = xf
		s.model.halt()
		s.model.reset_physics_interpolation()


static func _fmt_dist(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % roundi(m)
