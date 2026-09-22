## Headless interaction smoke test for the Ship Builder harness.
##
##     godot --headless --path . --script modules/ship_builder/tools/smoke_test.gd
##
## The content validator checks the data; this drives the editor. It loads the real
## scene and performs every edit a player can perform — place, move, remove, pose,
## break symmetry, swap hulls, repaint, undo, redo, save, load, throttle up and
## fire — a few frames apart so tweens, _process code and the systems sim actually
## run between steps.
##
## Exit code is 1 if any step fails. Godot prints its own errors to stderr, so CI
## should also fail the run if the output contains "SCRIPT ERROR" or "ERROR:".
extends SceneTree

const SCENE_PATH := "res://modules/ship_builder/ship_builder.tscn"
## Frames between steps: enough for a rebuild, a tween tick and a physics frame.
const FRAMES_PER_STEP := 3

var _builder: BuilderRoot = null
var _steps: Array[Dictionary] = []
var _index := 0
var _frames := 0
var _failures: Array[String] = []
var _refusals: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("smoke: cannot load " + SCENE_PATH)
		quit(1)
		return
	_builder = packed.instantiate() as BuilderRoot
	if _builder == null:
		push_error("smoke: scene root is not a BuilderRoot")
		quit(1)
		return
	root.add_child(_builder)
	# A refused edit is a feature, not a fault — the builder explains itself instead
	# of silently no-opping. They are collected and printed, never failed on.
	_builder.notice.connect(func(text: String, kind: String) -> void:
		if kind == "error":
			_refusals.append(text)
	)
	_build_steps()
	print("── Ship Builder smoke test ───────────────────────────────")
	print("  %s   %d steps" % [SCENE_PATH.get_file(), _steps.size()])
	print("")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % FRAMES_PER_STEP != 0:
		return false
	if _index >= _steps.size():
		return _finish()
	var step := _steps[_index]
	_index += 1
	var before := _failures.size()
	(step["fn"] as Callable).call()
	print("  %-38s %s" % [
		String(step["name"]), "ok" if _failures.size() == before else "FAIL"
	])
	return false


func _finish() -> bool:
	print("")
	if not _refusals.is_empty():
		print("── Refusals surfaced to the player (%d) ──────────────────" % _refusals.size())
		for text in _refusals:
			print("  · " + text)
		print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for text in _failures:
			print("  ✗ " + text)
		quit(1)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- Helpers ----------------------------------------------------------------

func _res() -> DesignResolution:
	return _builder.view.resolution


func _sim() -> SystemsSim:
	return _builder.get_node("%Systems") as SystemsSim


## First open socket that some part in the library will actually go into, plus that
## part's id. Returns {} on a design with nothing left to fit.
func _first_fit() -> Dictionary:
	for entry in _res().open_sockets:
		var options := _builder.library.parts_for_socket(entry["socket"] as PartSocket)
		if not options.is_empty():
			return {"path": String(entry["path"]), "part_id": options[0].id}
	return {}


## A fitted, non-chassis, non-shadow placement — the thing every "act on the
## selection" step needs.
func _first_fitted() -> Placement:
	for p in _res().selectable_placements():
		if not p.is_chassis():
			return p
	return null


func _first_jointed() -> Placement:
	for p in _res().selectable_placements():
		if p.socket != null and p.socket.joint != null and p.socket.joint.is_articulated():
			return p
	return null


func _first_mirrored() -> Placement:
	for p in _res().selectable_placements():
		if p.mirrored and not p.is_chassis():
			return p
	return null


func _add(step_name: String, fn: Callable) -> void:
	_steps.append({"name": step_name, "fn": fn})


# --- The script the test performs -------------------------------------------

func _build_steps() -> void:
	_add("scene wiring", _step_wiring)
	_add("first design resolves", _step_resolved)
	_add("fit a part", _step_place)
	_add("select and read the inspector", _step_select)
	_add("pose a joint", _step_pose)
	_add("reset that pose", _step_reset_pose)
	_add("break then restore symmetry", _step_symmetry)
	_add("move a part to another mount", _step_move)
	_add("remove the selection", _step_remove)
	_add("undo back to the start", _step_undo_all)
	_add("redo forward again", _step_redo_all)
	_add("swap through every hull", _step_chassis)
	_add("load every preset", _step_presets)
	_add("strip then autofill", _step_strip_autofill)
	_add("apply every livery", _step_factions)
	_add("repaint all three channels", _step_palette)
	_add("every surface finish", _step_finishes)
	_add("per-part colour override", _step_part_color)
	_add("json round trip", _step_json)
	_add("save then load from disk", _step_files)
	_add("cargo load changes the stats", _step_cargo)
	_add("mounts, labels, framing", _step_view_tools)
	_add("all three drag modes", _step_drag_modes)
	_add("cycle empty mounts by keyboard", _step_cycle_sockets)
	_add("camera view presets", _step_camera_views)
	_add("high contrast on and off", _step_contrast)
	_add("panel drawers", _step_panels)
	_add("help overlay", _step_help)
	_add("popup instructions", _step_coach)
	_add("mount markers only where it fits", _step_marker_honesty)
	_add("throttle up", _step_throttle)
	for i in 6:
		_add("  burn and fire (%d/6)" % (i + 1), _step_burn)
	_add("engines and guns did work", _step_systems_check)
	_add("systems idle back down", _step_systems_stop)


# --- Steps ------------------------------------------------------------------

## Every node a script reaches for by unique name. A missing one is a silent null
## dereference three panels later, so it is the first thing checked.
func _step_wiring() -> void:
	for unique_name in [
		"%World", "%ShipHolder", "%Ghost", "%Systems", "%Camera", "%ViewportFrame",
		"%LeftPanel", "%RightPanel", "%PartPalette", "%PanelToggles", "%StatusLabel",
		"%HelpOverlay", "%Coach",
	]:
		_check(_builder.get_node_or_null(unique_name) != null, "missing node " + unique_name)
	_check(_builder.library != null and _builder.library.count() > 0, "part library is empty")
	_check(_builder.library.load_errors.is_empty(), "library reported load errors")


func _step_resolved() -> void:
	_check(_builder.view != null, "no ShipView after the first rebuild")
	_check(_res() != null and _res().part_count() > 0, "design resolved to nothing")
	_check(_res().content_errors.is_empty(), "resolution reported content errors")
	_check(_builder.stats() != null, "no stats")
	_check(not _res().open_sockets.is_empty(), "starting hull offers no open mounts")


func _step_place() -> void:
	var fit := _first_fit()
	if fit.is_empty():
		_failures.append("no open mount accepts any part in the library")
		return
	var before := _res().part_count()
	_check(_builder.place_part(String(fit["path"]), String(fit["part_id"])), "place_part refused a part the socket accepts")
	_check(_res().part_count() > before, "part count did not grow after a placement")


func _step_select() -> void:
	var placement := _first_fitted()
	if placement == null:
		_failures.append("nothing fitted to select")
		return
	_builder.select(placement.editable_path())
	_check(_builder.selected != "", "selection did not stick")
	_check(_builder.selected_placement() != null, "selected path resolves to no placement")
	_check(_builder.part_at(_builder.selected) != null, "selected path resolves to no part")


func _step_pose() -> void:
	var placement := _first_jointed()
	if placement == null:
		_refusals.append("no articulated mount on this design — pose step skipped")
		return
	var joint := placement.socket.joint
	var path := placement.editable_path()
	var key := ""
	var limit := 0.0
	for candidate: Array in [
		["yaw", joint.yaw_range], ["pitch", joint.pitch_range],
		["roll", joint.roll_range], ["slide", joint.slide_range],
	]:
		var span := candidate[1] as Vector2
		if not is_equal_approx(span.x, span.y):
			key = String(candidate[0])
			limit = maxf(absf(span.x), absf(span.y))
			break
	if key == "":
		_refusals.append("the articulated mount only scales — pose step skipped")
		return
	# Deliberately far past the limit: a joint that does not clamp is a joint that
	# folds a wing through the hull, and stores that in the saved design.
	_builder.begin_continuous("Pose")
	_builder.set_pose(path, key, 9000.0, true)
	_builder.end_continuous()
	var after := _builder.placement_at(path)
	_check(after != null, "posed placement vanished")
	if after == null:
		return
	var value := float(after.attachment.pose.get(key, 0.0))
	_check(absf(value) <= limit + 0.001, "%s pose was not clamped to its limit (%.1f > %.1f)" % [key, value, limit])
	_check(not is_zero_approx(value), "%s pose was clamped all the way to nothing" % key)
	_check(_builder.history.can_undo(), "a pose drag left no undo entry")


func _step_reset_pose() -> void:
	var placement := _first_jointed()
	if placement == null:
		return
	var path := placement.editable_path()
	_builder.reset_pose(path)
	var after := _builder.placement_at(path)
	if after == null:
		_failures.append("placement vanished on pose reset")
		return
	for key in ["yaw", "pitch", "roll", "slide"]:
		_check(is_zero_approx(float(after.attachment.pose.get(key, 0.0))), "pose %s did not reset" % key)


## Mirroring only shows up once something is fitted to a socket another socket
## mirrors, so the step fits one itself rather than hoping the design has one.
func _step_symmetry() -> void:
	# Start from a bare hull: the earlier steps may well have filled the very mount
	# this one needs free, and a skipped mirror check is the one gap worth closing.
	_builder.new_design()
	_builder.strip_design()
	var chassis := _res().placements[0].part
	var mirror_sources := {}
	for socket in chassis.sockets:
		if socket.is_mirror():
			mirror_sources[socket.mirror_of] = true
	var target := ""
	var part_id := ""
	for entry in _res().open_sockets:
		var socket := entry["socket"] as PartSocket
		if not mirror_sources.has(socket.id):
			continue
		var options := _builder.library.parts_for_socket(socket)
		if not options.is_empty():
			target = String(entry["path"])
			part_id = options[0].id
			break
	if target == "":
		_refusals.append("this hull has no mirrored mount free — symmetry step skipped")
		return

	var before := _res().part_count()
	_check(_builder.place_part(target, part_id), "a mirrored mount refused a part it accepts")
	_check(_res().part_count() == before + 2, "filling a mirrored mount did not produce a twin")
	var source := _builder.placement_at(target)
	if source == null:
		_failures.append("the mirrored part is not addressable after placement")
		return
	var twin_path := ""
	for p in _res().placements:
		if p.shadow and p.shadow_root != "":
			twin_path = p.path
			break
	_check(twin_path != "", "no generated twin appeared, or it is not marked as one")
	if twin_path == "":
		return
	_check(source.editable_path() != twin_path, "the twin is not addressable separately")

	# Break from the twin — the side the player clicks on when they want the
	# starboard engine pointed somewhere else.
	_check(_builder.break_symmetry(twin_path), "break_symmetry refused a generated twin")
	var independent := 0
	for p in _res().selectable_placements():
		if p.mirrored:
			independent += 1
	_check(independent > 0, "breaking symmetry produced no independently editable twin")
	_check(_res().part_count() == before + 2, "breaking symmetry changed the part count")
	_check(_builder.restore_symmetry(twin_path), "restoring symmetry was refused")
	var still_shadowed := false
	for p in _res().placements:
		if p.path == twin_path:
			still_shadowed = p.shadow
	_check(still_shadowed, "the twin did not go back to following its source")
	_check(_res().part_count() == before + 2, "restoring symmetry changed the part count")


func _step_move() -> void:
	var roomiest: ShipPart = null
	for chassis in _builder.library.chassis_list():
		if roomiest == null or chassis.sockets.size() > roomiest.sockets.size():
			roomiest = chassis
	_builder.swap_chassis(roomiest.id)
	_builder.autofill()
	var from_path := ""
	var target := ""
	for placement in _res().selectable_placements():
		if placement.is_chassis():
			continue
		for entry in _res().open_sockets:
			var socket := entry["socket"] as PartSocket
			if socket.accepts_part(placement.part):
				from_path = placement.editable_path()
				target = String(entry["path"])
				break
		if target != "":
			break
	if target == "":
		_refusals.append("every mount that fits is already full — move step skipped")
		return
	var before := _res().part_count()
	_check(_builder.move_part(from_path, target), "move_part refused a move into an accepting mount")
	_check(_res().part_count() == before, "moving a part changed the part count")


func _step_remove() -> void:
	var placement := _first_fitted()
	if placement == null:
		_failures.append("nothing fitted to remove")
		return
	_builder.select(placement.editable_path())
	var before := _res().part_count()
	_builder.remove_selected()
	_check(_res().part_count() < before, "removing the selection changed nothing")
	_check(_builder.selected == "" or _builder.selected_placement() != null, "selection points at a part that no longer exists")


func _step_undo_all() -> void:
	var guard := 0
	while _builder.history.can_undo() and guard < 80:
		_builder.undo()
		guard += 1
	_check(guard > 0, "history was empty after a dozen edits")
	_check(not _builder.history.can_undo(), "undo stack did not drain")
	_check(_res().part_count() > 0, "undoing everything left no ship")


func _step_redo_all() -> void:
	var guard := 0
	while _builder.history.can_redo() and guard < 80:
		_builder.redo()
		guard += 1
	_check(guard > 0, "nothing to redo after draining the undo stack")
	_check(_res() != null and _res().part_count() > 0, "redoing everything left no ship")


func _step_chassis() -> void:
	for chassis in _builder.library.chassis_list():
		_builder.swap_chassis(chassis.id)
		_check(_builder.design.chassis_id() == chassis.id, "hull did not change to " + chassis.id)
		_check(_res().content_errors.is_empty(), "%s resolved with content errors" % chassis.id)
		_check(_builder.stats() != null, "%s produced no stats" % chassis.id)


func _step_presets() -> void:
	for preset in _builder.library.presets:
		var preset_id := String(preset.get("id", ""))
		_builder.load_preset(preset_id)
		_check(_res().part_count() > 1, "preset %s loaded as a bare hull" % preset_id)
		_check(_res().content_errors.is_empty(), "preset %s resolved with content errors" % preset_id)


func _step_strip_autofill() -> void:
	_builder.strip_design()
	_check(_res().part_count() == 1, "stripping left more than the hull")
	_builder.autofill()
	var stats := _builder.stats()
	_check(stats != null, "autofill produced no stats")
	if stats != null:
		# Autofill exists so a new player is never staring at an unflyable hull.
		_check(stats.errors.is_empty(), "autofilled hull is still unflyable: " + ", ".join(stats.errors))


func _step_factions() -> void:
	for faction in _builder.library.factions:
		var faction_id := String(faction.get("id", ""))
		_builder.apply_faction(faction_id)
		_check(_builder.design.faction_id == faction_id, "livery %s did not stick" % faction_id)


func _step_palette() -> void:
	for channel in ShipDesign.CHANNELS:
		_builder.begin_continuous("Paint")
		_builder.set_palette_color(channel, Color(0.2, 0.7, 0.9), true)
		_builder.end_continuous()
		_check(_builder.design.get_color(channel).is_equal_approx(Color(0.2, 0.7, 0.9)), "channel %s did not take the colour" % channel)
	_check(_builder.design.faction_id == "", "hand-painting did not clear the livery name")


func _step_finishes() -> void:
	for preset: String in ShipDesign.MATERIAL_PRESETS:
		_builder.set_material_preset(preset)
		_check(_builder.design.material_preset == preset, "finish %s did not stick" % preset)


func _step_part_color() -> void:
	var placement := _first_fitted()
	if placement == null:
		_failures.append("nothing fitted to repaint")
		return
	var path := placement.editable_path()
	_builder.set_part_color(path, ShipDesign.CHANNELS[0], Color.RED)
	var after := _builder.placement_at(path)
	_check(after != null and not after.attachment.color_overrides.is_empty(), "per-part override was not recorded")
	_builder.clear_part_color(path)
	after = _builder.placement_at(path)
	_check(after != null and after.attachment.color_overrides.is_empty(), "per-part override did not clear")


func _step_json() -> void:
	var text := _builder.design_json()
	_check(text.length() > 40, "design_json produced almost nothing")
	_check(_builder.load_json(text), "the builder would not load its own JSON")
	_check(_builder.design_json() == text, "design changed across a JSON round trip")
	_check(not _builder.load_json('{"not_a": "design"}'), "load_json accepted JSON that is not a design")


func _step_files() -> void:
	_builder.rename_design("Smoke Test Hull")
	_check(_builder.design.design_name == "Smoke Test Hull", "rename did not stick")
	_builder.save_to_file()
	var saved := _builder.saved_designs()
	_check(not saved.is_empty(), "saving produced no file")
	if saved.is_empty():
		return
	var before := _builder.design_json()
	# saved_designs() lists every design on disk, and the player may well have
	# their own. Load the file this run wrote — matching it by name — rather than
	# trusting the first entry, or the round-trip check compares two different
	# ships and blames save/load for it.
	var target := ""
	for path in saved:
		if path.get_file().to_lower().contains("smoke_test_hull"):
			target = path
			break
	if target == "":
		target = saved[0]
	_builder.new_design()
	_builder.load_from_file(target)
	_check(_builder.design_json() == before, "a design did not survive save then load")


func _step_cargo() -> void:
	var capacity := _builder.stats().get_stat("cargo_capacity")
	if capacity <= 0.0:
		_refusals.append("this hull carries nothing — cargo step skipped")
		return
	var empty_speed := _builder.stats().top_speed
	_builder.set_cargo_load(capacity)
	_check(_builder.stats().cargo_used > 0.0, "cargo did not load")
	# The whole point of the mass model: a full hold is a slower ship.
	_check(_builder.stats().top_speed < empty_speed, "a full hold did not cost any speed")
	_builder.set_cargo_load(0.0)


func _step_view_tools() -> void:
	var viewport := _builder.get_node("%ViewportFrame") as BuilderViewport
	viewport.toggle_sockets()
	_check(_builder.view.sockets_visible(), "mounts did not become visible")
	viewport.toggle_socket_labels()
	_check(viewport.socket_labels_on, "mount labels did not turn on")
	viewport.frame_ship()
	viewport.toggle_socket_labels()
	viewport.toggle_sockets()
	_check(not _builder.view.sockets_visible(), "mounts did not hide again")


func _step_drag_modes() -> void:
	var viewport := _builder.get_node("%ViewportFrame") as BuilderViewport
	for mode in [BuilderViewport.DragMode.LOOK, BuilderViewport.DragMode.POSE, BuilderViewport.DragMode.MOVE]:
		viewport.set_drag_mode(mode)
		_check(viewport.drag_mode == mode, "drag mode %d did not take" % mode)
	viewport.cycle_drag_mode()
	viewport.set_drag_mode(BuilderViewport.DragMode.LOOK)


func _step_cycle_sockets() -> void:
	var viewport := _builder.get_node("%ViewportFrame") as BuilderViewport
	viewport.cycle_socket(1)
	var first := viewport.focused_socket()
	_check(first != "", "cycling empty mounts focused nothing")
	viewport.cycle_socket(1)
	viewport.cycle_socket(-1)
	_check(viewport.focused_socket() == first, "cycling forward then back landed somewhere else")


func _step_camera_views() -> void:
	var camera := _builder.get_node("%Camera") as OrbitCamera
	for view_name in ["front", "side", "top", "back", "bottom", "iso"]:
		camera.set_view(view_name)
	camera.zoom(2.0)
	camera.orbit(Vector2(40.0, 20.0))
	camera.pan(Vector2(10.0, 10.0), 600.0)
	camera.snap()
	_check(camera.distance >= OrbitCamera.DIST_MIN, "camera zoomed inside its own limit")
	_check(camera.pitch <= OrbitCamera.PITCH_MAX + 0.01, "camera pitched past its limit")


func _step_contrast() -> void:
	var was := BuilderTheme.high_contrast
	_builder.toggle_high_contrast()
	_check(BuilderTheme.high_contrast != was, "high contrast did not toggle")
	_builder.toggle_high_contrast()
	_check(BuilderTheme.high_contrast == was, "high contrast did not toggle back")


func _step_panels() -> void:
	var left := _builder.get_node("%LeftPanel") as Control
	var right := _builder.get_node("%RightPanel") as Control
	var was_left := left.visible
	_builder.toggle_panel("left")
	_check(left.visible != was_left, "the parts drawer did not toggle")
	_builder.toggle_panel("left")
	var was_right := right.visible
	_builder.toggle_panel("right")
	_check(right.visible != was_right, "the stats drawer did not toggle")
	_builder.toggle_panel("right")
	_check(left.visible and right.visible, "a panel stayed hidden")


func _step_help() -> void:
	var help := _builder.get_node("%HelpOverlay") as HelpOverlay
	help.toggle()
	_check(help.visible, "the help card did not open")
	help.toggle()
	_check(not help.visible, "the help card did not close")


## The walkthrough opens, pages, closes, and each one-shot tip fires exactly once.
func _step_coach() -> void:
	var coach := _builder.coach()
	coach.reset_all()
	coach.start()
	_check(coach.visible, "the walkthrough did not open on a fresh install")
	coach.close_overlay()
	_check(not coach.visible, "the walkthrough did not close")
	_check(coach.has_seen("walkthrough"), "a dismissed walkthrough was not remembered")
	coach.start()
	_check(not coach.visible, "the walkthrough came back after being dismissed")
	coach.start(false)
	_check(coach.visible, "the menu could not reopen the walkthrough deliberately")
	coach.close_overlay()

	_check(coach.show_tip("smoke_tip", "T", "Body"), "a first-time tip did not fire")
	coach.close_overlay()
	_check(not coach.show_tip("smoke_tip", "T", "Body"), "a one-shot tip fired twice")
	# Leave the install in the state a returning player has, so nothing later in
	# the run is interrupted by a card.
	coach.reset_all()
	coach._mark_seen("walkthrough")


## The heart of the drag-and-drop contract: while a part is being carried, a
## visible mount marker must mean "this will accept it". Anything else teaches
## the player that the snapping is broken.
func _step_marker_honesty() -> void:
	var view := _builder.view
	var checked := 0
	for category in ["engine", "weapon", "wing", "cockpit"]:
		var part: ShipPart = null
		for id: Variant in _builder.library.parts:
			var candidate := _builder.library.get_part(String(id))
			if candidate != null and candidate.category == category:
				part = candidate
				break
		if part == null:
			continue
		checked += 1
		view.show_sockets(true, part)
		var shown := 0
		for path: Variant in view.socket_nodes:
			var node := view.socket_nodes[path] as Node3D
			if node == null or not node.visible:
				continue
			shown += 1
			var entry := view.resolution.find_open_socket(String(path))
			_check(not entry.is_empty(), "a marker is shown for a mount that is not open")
			if entry.is_empty():
				continue
			_check(
				(entry["socket"] as PartSocket).accepts_part(part),
				"a marker glowed for a %s on a mount that refuses it" % category
			)
		_check(
			shown == view.resolution.sockets_accepting(part).size(),
			"markers shown (%d) do not match mounts that accept a %s (%d)" % [
				shown, category, view.resolution.sockets_accepting(part).size()
			]
		)
		if shown == 0:
			# The silent case has to explain itself rather than leaving the player
			# to conclude that dropping does not work.
			_check(
				view.resolution.explain_no_socket(part) != "",
				"nothing accepts a %s and nothing said why" % category
			)
	_check(checked > 0, "no parts were available to test marker honesty with")
	view.show_sockets(false)


func _step_throttle() -> void:
	# Fit a full working ship first: the systems sim can only spool engines and fire
	# guns that are actually bolted on.
	var armed := ""
	for preset in _builder.library.presets:
		_builder.load_preset(String(preset.get("id", "")))
		if _builder.stats().weapon_count > 0 and _builder.stats().engine_count > 0:
			armed = String(preset.get("id", ""))
			break
	_check(armed != "", "no shipped preset has both engines and guns")
	if armed == "":
		return
	var stats := _builder.stats()
	_check(stats.engine_count > 0, "%s has no engines to spool" % armed)
	_check(stats.weapon_count > 0, "%s has no guns to fire" % armed)
	var sim := _sim()
	sim.state_changed.connect(func(energy_fraction: float, heat_fraction: float, _notes: String) -> void:
		_energy_low = minf(_energy_low, energy_fraction)
		_heat_high = maxf(_heat_high, heat_fraction)
	)
	sim.set_throttle(1.0)
	sim.set_firing(true)
	_check(is_equal_approx(sim.throttle, 1.0), "throttle did not take")
	_check(sim.firing, "the trigger did not latch")
	_check(sim.shots_fired == 0, "shots were counted before the trigger was pulled")


func _step_burn() -> void:
	var sim := _sim()
	_shots_seen = maxi(_shots_seen, sim.shots_fired)
	_plumes_seen = maxi(_plumes_seen, sim.plumes_lit())
	_in_flight_seen = maxi(_in_flight_seen, sim.shots_in_flight())


## The "does it work" half of the builder: engines that were only fitted, not
## simulated, would light no plumes, and guns that were only counted would spawn
## no projectiles.
func _step_systems_check() -> void:
	var sim := _sim()
	var view := _builder.view
	_check(_shots_seen > 0, "holding the trigger fired nothing")
	_check(_in_flight_seen > 0, "shots were counted but none existed in the world")
	_check(_plumes_seen == view.exhausts.size(), "lit %d plumes for %d exhausts" % [_plumes_seen, view.exhausts.size()])
	_check(not view.muzzles.is_empty(), "no muzzle markers were hoisted into ship space")
	_check(sim.describe() != "", "the systems sim reports nothing about itself")
	print("      %d shots · %d plumes · energy floor %.2f · heat peak %.2f" % [
		_shots_seen, _plumes_seen, _energy_low, _heat_high
	])


func _step_systems_stop() -> void:
	var sim := _sim()
	sim.stop_all()
	_check(is_zero_approx(sim.throttle), "throttle did not return to idle")
	_check(not sim.firing, "the trigger did not release")
	_check(sim.shots_in_flight() == 0, "projectiles outlived the trigger release")
	_check(sim.plumes_lit() == 0, "plumes stayed lit after the throttle closed")


# --- State carried between steps --------------------------------------------

var _energy_low := INF
var _heat_high := 0.0
var _shots_seen := 0
var _plumes_seen := 0
var _in_flight_seen := 0
