## ScenarioObjectives: the goals of the non-"kill them all" scenarios — where
## to go, what to collect, who to protect — and the markers that show them.
##
## [FlightScenarios] owns one while such a scenario runs: [method begin] lays
## the objective out from the player's ship, [method tick] advances it and
## reports won (1) / lost (-1) / running (0), [method status] is the band's
## line and [method clear] takes everything down.
##
## - DELIVER: a chain of drop points, reached in order.
## - GATES: rings to thread in order, against the clock.
## - SALVAGE: cargo pods scattered round the player, collected by touching.
## - ESCORT: a big friendly hauler (or capital ship) flies a route to a
##   destination at its own pace; it must arrive alive. Waves go for it.
## - ASSAULT: a mothership to bring down (it launches fighters).
## - DOCK: fly into a giant friendly carrier's glowing bay and come to rest.
##
## The way to the current goal is a blue chevron arrow ([ChevronArrow3D]) laid
## off the player's ship, pointing through 3D space at it, plus a glowing
## beacon (a ring on a beam of light) standing at the goal itself.
class_name ScenarioObjectives
extends Node3D

## Kinds (mirror [enum FlightScenarios.Objective]'s new entries).
enum Kind { DELIVER, GATES, SALVAGE, ESCORT, ASSAULT, DOCK }

## Metres from a drop point / pod that counts as there.
const REACH := 70.0
## The escort counts as arrived this close to its destination.
const ESCORT_ARRIVE := 160.0
## Dock: seconds held in the bay below [constant DOCK_SPEED] m/s.
const DOCK_HOLD := 1.5
const DOCK_SPEED := 40.0
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
var _arrow: ChevronArrow3D
var _dock_hold := 0.0
var _escort_speed := 50.0
var _prev_s := 0.0
var _gate_axis: Array[Vector3] = []
var _t := 0.0


## Lay the objective out. [param k] is a [enum Kind].
func begin(k: int, config: Dictionary, root: FlightRoot, spawner: AiSpawner) -> void:
	kind = k
	_config = config
	_root = root
	_spawner = spawner
	done = 0
	points.clear()
	_gate_axis.clear()
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
				p += dir * float(config.get("spacing", 1600.0)) * rng.randf_range(0.8, 1.2)
				points.append(p)
				_markers.append(_beacon(p, BLUE, 40.0))
		Kind.GATES:
			var p := origin
			var dir := fwd
			for i in int(config.get("gates", 8)):
				dir = dir.rotated(up, rng.randf_range(-0.6, 0.6)).rotated(right, rng.randf_range(-0.3, 0.3)).normalized()
				p += dir * rng.randf_range(380.0, 560.0)
				points.append(p)
				_gate_axis.append(dir)
				_markers.append(_gate(p, dir, 34.0))
		Kind.SALVAGE:
			for i in int(config.get("pods", 6)):
				var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.35, 0.35), rng.randf_range(-1.0, 1.0)).normalized()
				var p := origin + off * rng.randf_range(300.0, float(config.get("spacing", 900.0)))
				points.append(p)
				_markers.append(_pod(p))
		Kind.ESCORT:
			destination = origin + fwd * float(config.get("route", 3500.0))
			_escort_speed = float(config.get("escort_speed", 50.0))
			ship = spawner.spawn_pilot_vessel(xf, float(config.get("escort_size", 4.0)))
			if ship != null:
				ship.is_pilot_vessel = false
				ship._ai_paused = true
				ship.team_id = FlightScenarios.PLAYER_TEAM
				ship.max_hp = 900.0 * float(config.get("escort_size", 4.0)) * float(config.get("escort_hp", 1.0))
				ship.hp = ship.max_hp
				ship.systems.set_firing(false)
				ship.model.external_drive = true
			_markers.append(_beacon(destination, GOLD, 90.0))
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
	_arrow = ChevronArrow3D.new()
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
			if done < points.size() and pos.distance_to(points[done]) < REACH + _hull():
				_markers[done].visible = false
				_root.hit_word("DROP %d!" % (done + 1), points[done], GOLD, 1.3)
				done += 1
			if done >= points.size():
				return 1
		Kind.GATES:
			if done < points.size():
				var p := points[done]
				var axis := _gate_axis[done]
				var s := (pos - p).dot(axis)
				if _prev_s < 0.0 and s >= 0.0 and (pos - p - axis * s).length() < 34.0 * 2.2:
					_markers[done].visible = false
					_root.hit_word("GATE %d!" % (done + 1), p, BLUE, 1.2)
					done += 1
					if done < points.size():
						_prev_s = (pos - points[done]).dot(_gate_axis[done])
						return 0
				_prev_s = s
			if done >= points.size():
				return 1
		Kind.SALVAGE:
			for i in points.size():
				if _markers[i].visible and pos.distance_to(points[i]) < REACH * 0.8 + _hull():
					_markers[i].visible = false
					_root.hit_word("GOT IT!", points[i], GOLD, 1.1)
					done += 1
			if done >= points.size():
				return 1
		Kind.ESCORT:
			if ship == null or not is_instance_valid(ship) or not ship._alive:
				return -1
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
		Kind.DOCK:
			if ship == null or not is_instance_valid(ship) or not ship._alive:
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
		return -1
	_lay_arrow()
	return 0


## The band's line for this objective.
func status() -> String:
	var line := String(_config.get("name", "")).to_upper()
	var goal := goal_position()
	var far := ""
	if goal != Vector3.INF and _root.model != null:
		far = "  ·  %s" % _fmt_dist(_root.model.global_position.distance_to(goal))
	match kind:
		Kind.DELIVER:
			line += "  ·  DROP %d/%d" % [mini(done + 1, points.size()), points.size()] + far
		Kind.GATES:
			line += "  ·  GATE %d/%d" % [mini(done + 1, points.size()), points.size()] + far
		Kind.SALVAGE:
			line += "  ·  %d/%d PODS" % [done, points.size()] + far
		Kind.ESCORT:
			if ship != null and is_instance_valid(ship):
				line += "  ·  HULL %d%%  ·  %s TO GO" % [
					roundi(ship.hp / maxf(ship.max_hp, 1.0) * 100.0), _fmt_dist(ship.global_position.distance_to(destination))]
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
	var limit := float(_config.get("time_limit", 0.0))
	return maxf(limit - _t, 0.0) if limit > 0.0 else -1.0


## Where the arrow points now (Vector3.INF: nowhere).
func goal_position() -> Vector3:
	match kind:
		Kind.DELIVER, Kind.GATES:
			return points[done] if done < points.size() else Vector3.INF
		Kind.SALVAGE:
			var best := Vector3.INF
			var bd := INF
			var pos := _root.model.global_position if _root.model != null else Vector3.ZERO
			for i in points.size():
				if _markers[i].visible and pos.distance_to(points[i]) < bd:
					bd = pos.distance_to(points[i])
					best = points[i]
			return best
		Kind.ESCORT:
			# Stay with the convoy; point at it when drifting away.
			if ship != null and is_instance_valid(ship):
				var d := _root.model.global_position.distance_to(ship.global_position)
				return ship.global_position if d > 600.0 else destination
			return destination
		Kind.ASSAULT:
			return ship.global_position if ship != null and is_instance_valid(ship) else Vector3.INF
		Kind.DOCK:
			return destination
	return Vector3.INF


func clear() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()
	if ship != null and is_instance_valid(ship) and ship._alive:
		ship.teardown()
	ship = null
	queue_free()


# --- Markers ---------------------------------------------------------------------

func _lay_arrow() -> void:
	var goal := goal_position()
	var cam := _root.camera_node()
	var model := _root.model
	if goal == Vector3.INF or cam == null or model == null or _root.camera_rig == null:
		_arrow.hide_arrow()
		return
	var centre := model.get_global_transform_interpolated().origin
	var to := goal - centre
	var d := to.length()
	if d < REACH:
		_arrow.hide_arrow()
		return
	var dir := to / d
	var hull := _root.camera_rig.hull_radius
	var from := centre + dir * hull * 1.6
	var length := clampf(d - hull * 1.6, hull, hull * 5.0)
	# Pulses gently, brighter the further the goal.
	var glow := 0.7 + 0.3 * sin(_t * 4.0)
	_arrow.place(from, from + dir * length, hull * 0.9, cam, BLUE, glow)


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


## A glowing cargo pod.
func _pod(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var box := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(10.0, 6.0, 14.0)
	box.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GOLD
	mat.emission_enabled = true
	mat.emission = GOLD
	mat.emission_energy_multiplier = 1.5
	box.material_override = mat
	n.add_child(box)
	var halo := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 16.0
	s.height = 32.0
	s.radial_segments = 12
	s.rings = 6
	halo.mesh = s
	halo.material_override = _glow(GOLD, 0.18)
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
