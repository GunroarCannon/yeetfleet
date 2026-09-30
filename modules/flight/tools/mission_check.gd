## The missions and the fixes that came with them, in the real flight scene:
##
## - each objective scenario (courier, ring race, salvage, dock, escort,
##   capital escort, carrier assault) lays out its goal, points the arrow at it
##   and is won by doing it (the player is moved through it here);
## - a fast, tough ram shatters a planet (hull spared); a slower one knocks it
##   off its spot and it drifts back;
## - a mouse button let go over a HUD control no longer leaves the gesture
##   reader "held" (every mouse move used to swing the camera);
## - a baked-hull ship (mesh baking on) breaks into visible parts when it dies,
##   instead of leaving its whole baked hull behind;
## - a hostile ship in view yeets at the ship it is fighting, not only at the
##   player.
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/mission_check.gd
extends SceneTree

var _root: FlightRoot
var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(what)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	JuiceSettings._loaded = true
	# Enemy shield veils soak hits; these checks measure hull damage.
	JuiceSettings.enemy_shields = false
	JuiceSettings.kill_cam = false
	JuiceSettings.player_invulnerable = true
	print("── missions, planet pinball, gesture + wreck fixes ─────────")
	_root = (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false
	await _ticks(10)
	if not is_equal_approx(_root.time_scale(), 1.0):
		_root.set_time_scale(1.0)
	_root.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _gesture()
	await _missions()
	await _planet()
	await _baked_wreck()
	_finish()


# --- Gesture reader ----------------------------------------------------------------

func _gesture() -> void:
	var g := GestureReader.new()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(100, 100)
	g.feed(down)
	# The release lands on a HUD button and never reaches the reader; the next
	# move has no button held.
	var move := InputEventMouseMotion.new()
	move.position = Vector2(300, 100)
	move.button_mask = 0
	g.feed(move)
	_check(not g.is_down(), "a release eaten by the HUD doesn't leave the mouse 'held'")
	var rdown := InputEventMouseButton.new()
	rdown.button_index = MOUSE_BUTTON_RIGHT
	rdown.pressed = true
	g.feed(rdown)
	var swung := [0]
	g.alt_dragged.connect(func(_r: Vector2) -> void: swung[0] += 1)
	g.feed(move)
	_check(swung[0] == 0, "nor a right button (trackpad) swinging the camera on every move")


# --- Missions ----------------------------------------------------------------------

func _missions() -> void:
	var sc := _root.scenarios
	for id: String in FlightScenarios.OBJECTIVE_ORDER:
		_root.revive_player()
		_root.model.halt()
		sc.start(FlightScenarios.preset(id))
		await _ticks(3)
		var obj := sc._objectives
		if obj == null:
			_check(false, "%s lays out an objective" % id)
			continue
		var goal := obj.goal_position()
		# The arrow is laid on a render frame.
		for i in 4:
			await process_frame
		# (A protect mission starts beside its hauler: nothing to point at yet.)
		var arrow_ok := obj._arrow.visible or goal == Vector3.INF or (obj.kind == ScenarioObjectives.Kind.ESCORT and obj._hold > 0.0)
		match obj.kind:
			ScenarioObjectives.Kind.DELIVER, ScenarioObjectives.Kind.SALVAGE:
				for p in obj.points.duplicate():
					_put_player(p)
					await _ticks(3)
			ScenarioObjectives.Kind.GATES:
				for i in obj.points.size():
					var p: Vector3 = obj.points[i]
					var axis: Vector3 = obj._gate_axis[i]
					_put_player(p - axis * 30.0)
					await _ticks(2)
					_put_player(p + axis * 30.0)
					await _ticks(2)
			ScenarioObjectives.Kind.VOYAGE:
				_check(obj._voyage_name != "" and sc.status_line().begins_with("REACH "), "%s: names the planet to reach (%s)" % [id, sc.status_line()])
				_put_player(obj.points[0])
				await _ticks(3)
			ScenarioObjectives.Kind.ESCORT when obj._hold > 0.0:
				# PROTECT: stranded, it stays put; hold out and it is won.
				_check(sc.guarded_ship() == obj.ship and sc.time_left() > 0.0, "%s: a hauler to keep alive, on a clock" % id)
				var p0 := obj.ship.global_position
				await _ticks(60)
				_check(obj.ship.global_position.distance_to(p0) < 30.0, "%s: the hauler stays where it is" % id)
				obj._t = obj._hold
				await _ticks(3)
			ScenarioObjectives.Kind.ESCORT:
				# The level's opening look at the ship to guard.
				_check(sc.guarded_ship() == obj.ship, "%s: the guarded ship is known" % id)
				var r := CampaignLevelOverlay.ship_radius(obj.ship)
				var shown := _root.camera_rig.show_ship(obj.ship, r, 0.2, 0.2, 0.2)
				_check(r > 1.0 and (shown or not _root.camera_rig.is_follow_mode()), "%s: the camera shows the guarded ship" % id)
				await _ticks(60)
				_root.camera_rig.cancel_kill_cam()
				var d0 := obj.ship.global_position.distance_to(obj.destination)
				await _ticks(120)
				var d1 := obj.ship.global_position.distance_to(obj.destination)
				_check(d1 < d0 - 20.0, "%s: the convoy flies its route (%.0f → %.0f m)" % [id, d0, d1])
				var xf := obj.ship.model.global_transform
				xf.origin = obj.destination
				obj.ship.model.global_transform = xf
				await _ticks(3)
			ScenarioObjectives.Kind.ASSAULT:
				_check(obj.ship != null and obj.ship.is_mother, "%s: a mothership to bring down" % id)
				obj.ship.take_damage(obj.ship.hp + 10.0, true)
				await _ticks(3)
			ScenarioObjectives.Kind.DOCK:
				_put_player(obj.destination)
				await _ticks(int(ScenarioObjectives.DOCK_HOLD * 60.0) + 20)
		await _ticks(3)
		print("  %-14s → %s" % [id, sc.status_line()])
		_check(arrow_ok, "%s: the blue arrow points the way" % id)
		_check(sc.state == FlightScenarios.State.WON, "%s: doing it wins the mission" % id)
		sc.stop(false)
		await _ticks(2)


func _put_player(p: Vector3) -> void:
	var m := _root.model
	var xf := m.global_transform
	xf.origin = p
	m.global_transform = xf
	m.halt()
	m.reset_physics_interpolation()


# --- Planet pinball ------------------------------------------------------------------

func _planet() -> void:
	var holder: Node3D = null
	var body: PhysBody = null
	for b in _root.phys_world.bodies:
		if b.layer == PhysBody.Layer.STATIC and _root._planet_in(b.node as Node3D) != null and b.radius < 1500.0:
			holder = b.node as Node3D
			body = b
			break
	if body == null:
		_check(false, "a planet to ram")
		return
	var home := holder.global_position
	var point := home + Vector3.UP * body.radius
	# A knock: slower than the smash speed.
	_put_player(home + Vector3.UP * (body.radius + 50.0))
	var need := _root.planet_smash_need(body.radius)
	var knock := lerpf(JuiceSettings.planet_knock_speed, need, 0.5)
	print("  planet r %.0f m: knock at %.0f m/s, shatter at %.0f m/s" % [body.radius, JuiceSettings.planet_knock_speed, need])
	_check(need > JuiceSettings.planet_knock_speed, "a knock is slower than a shatter, even for a very tough hull")
	_root.planet_ram(body, point, knock)
	await _ticks(60)
	var moved := holder.global_position.distance_to(home)
	_check(moved > 5.0, "a fast ram knocks the planet off its spot (%.0f m)" % moved)
	await _ticks(60 * 30)
	_check(holder.global_position.distance_to(home) < moved, "and it drifts back home")
	# A smash.
	var spared := _root.planet_ram(body, point, 100000.0)
	await _ticks(3)
	var planet := _root._planet_in(holder)
	_check(spared and planet.has_meta("shattered"), "a hard enough ram shatters it (and spares the hull)")


# --- Baked wreck ---------------------------------------------------------------------

func _baked_wreck() -> void:
	var sp := _root.ensure_ai_spawner()
	sp.spawn_near_player(1)
	await _ticks(3)
	var ship: AiShip = null
	for s in sp.ships():
		if is_instance_valid(s) and s._alive:
			ship = s
	if ship == null:
		_check(false, "a ship to wreck")
		return
	ship._view.enable_baked_mesh(true)
	var meshes := []
	for inst in ship._view.part_meshes.values():
		meshes.append(inst)
	_check(ship._view.baked_mesh_instance != null, "the ship is drawn baked")
	ship.take_damage(ship.hp + 10.0, true)
	await _ticks(2)
	_check(ship._view.baked_mesh_instance == null, "dying drops the baked hull")
	var shown := 0
	for inst in meshes:
		if is_instance_valid(inst) and (inst as MeshInstance3D).is_visible_in_tree():
			shown += 1
	_check(shown > 0 and shown == meshes.size(), "and every part flies off visible (%d/%d)" % [shown, meshes.size()])


func _finish() -> void:
	JuiceSettings.load_from_disk()
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
	else:
		print("── FAIL: %s" % ", ".join(_failures))
	quit(0 if _failures.is_empty() else 1)
