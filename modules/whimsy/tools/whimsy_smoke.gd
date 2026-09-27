## Headless check for the whimsy module: every face's art loads, a ship pops a
## triggered emote and it fades and frees itself, scenery still wears its
## persistent faces, and a confetti pop builds and frees itself. How it all
## *looks* is judged by whimsy_shot.gd, which needs a real renderer.
##
##     godot --audio-driver Dummy --path . --headless --script modules/whimsy/tools/whimsy_smoke.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	print("── whimsy smoke ────────────────────────────────────────")
	_check_art()
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	await process_frame
	await process_frame
	await _check_ship_emotes(f)
	await _check_confetti(f)
	_check_scenery(f)
	if _failures == 0:
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures)
		quit(1)


func _row(label: String, ok: bool) -> void:
	print("  %-44s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures += 1


func _check_art() -> void:
	var all_ok := true
	for expression: String in Whimsy.EXPRESSIONS:
		var tex := Whimsy.face_texture(expression)
		if tex == null or tex.get_width() != Whimsy.FACE_SIZE or tex.get_height() != Whimsy.FACE_SIZE:
			push_error("whimsy: face '%s' missing or not %dpx square" % [expression, Whimsy.FACE_SIZE])
			all_ok = false
	_row("every expression loads at FACE_SIZE", all_ok)
	_row("confetti sheet loads", load(Whimsy.ConfettiBurst.SHEET_PATH) != null)


## Ship faces became one-shot emotes (see [method Whimsy.emote]) rather than a
## permanently-mounted sticker. Trigger one on the player and on an AI ship,
## check it actually pops out as a transient child, then check it fades and
## frees itself instead of lingering like the old static face did.
func _check_ship_emotes(f: FlightRoot) -> void:
	f._emote("ouch", 0.3)
	var popup := _find_emote(f)
	_row("the player's ship pops an emote on trigger", popup != null)

	var ships: Array = f._ai_spawner.ships()
	var ai_ok := ships.is_empty()
	if not ships.is_empty():
		var ship: AiShip = ships[0]
		ship._emote("dizzy", 0.3)
		ai_ok = _find_emote(ship.get_parent()) != null
	_row("an AI ship pops an emote on trigger", ai_ok)

	if popup != null:
		await create_timer(1.2).timeout
		_row("an emote fades out and frees itself", not is_instance_valid(popup))


func _find_emote(host: Node) -> Node3D:
	if host == null:
		return null
	for i in host.get_child_count():
		var c := host.get_child(i)
		if c.name.begins_with("Emote"):
			return c as Node3D
	return null


func _check_confetti(f: FlightRoot) -> void:
	Whimsy.confetti(f, f.model.global_position, 1.0)
	var burst := f.get_child(f.get_child_count() - 1)
	var spawned := burst != null and burst.name.begins_with("Confetti")
	# Outlives its particles by a beat, then frees itself.
	await create_timer(Whimsy.ConfettiBurst.LIFETIME + 0.6).timeout
	_row("confetti pops and cleans up after itself", spawned and not is_instance_valid(burst))


func _check_scenery(f: FlightRoot) -> void:
	var rock_faces := 0
	for entry: Dictionary in f.space.asteroid_data:
		var anchor: Node3D = entry["node"]
		if anchor != null and anchor.get_node_or_null("WhimsyFace") != null:
			rock_faces += 1
	_row("near-field rocks wear faces", rock_faces > 0)
	var sky := f.space.get_node_or_null("Sky")
	_row("the star wears a face", sky != null and sky.get_node_or_null("SunFace") != null)
