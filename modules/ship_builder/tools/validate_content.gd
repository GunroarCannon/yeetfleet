## Headless content check. Run it before shipping content and after any edit to
## the JSON in /data:
##
##     godot --headless --path . --script modules/ship_builder/tools/validate_content.gd
##
## It loads the whole part library, resolves every shipped preset, builds every
## part's mesh, and exercises the mirror/break-symmetry paths. Exit code is 1 if
## anything is wrong, so this drops straight into CI.
extends SceneTree


var _errors: Array[String] = []
var _warnings: Array[String] = []


func _initialize() -> void:
	var library := PartLibrary.new()
	library.load_all()

	print("── Part library ──────────────────────────────────────────")
	print("  parts: %d   presets: %d   factions: %d" % [
		library.count(), library.presets.size(), library.factions.size()
	])
	for category in ShipPart.CATEGORIES:
		var list := library.parts_in_category(category)
		print("    %-9s %d" % [category, list.size()])
	for e in library.load_errors:
		_errors.append("library: " + String(e))

	_check_sockets(library)
	_check_meshes(library)
	_check_presets(library)
	_check_mirroring(library)
	_check_autofill(library)
	_check_round_trip(library)

	print("")
	if not _warnings.is_empty():
		print("── Warnings (%d) ─────────────────────────────────────────" % _warnings.size())
		for w in _warnings:
			print("  ! " + w)
	if _errors.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _errors.size())
		for e in _errors:
			print("  ✗ " + e)
		quit(1)


## Every socket must be reachable: something in the catalogue has to fit it, or
## the player is looking at a mount they can never use.
func _check_sockets(library: PartLibrary) -> void:
	var unfillable := 0
	var total := 0
	for id: Variant in library.parts:
		var part := library.get_part(String(id))
		for socket in part.sockets:
			total += 1
			if library.parts_for_socket(socket).is_empty():
				unfillable += 1
				_warnings.append("no part fits %s/%s (accepts %s, sizes %s)" % [
					part.id, socket.id, str(socket.accepts), str(socket.size_classes)
				])
	print("  sockets: %d defined, %d with no compatible part" % [total, unfillable])


## Mesh generation must not crash and must produce geometry with real bounds.
func _check_meshes(library: PartLibrary) -> void:
	var empty := 0
	for id: Variant in library.parts:
		var part := library.get_part(String(id))
		for mirrored: bool in [false, true]:
			var built := PartMeshFactory.build(part, mirrored)
			if built == null or built.mesh == null or built.mesh.get_surface_count() == 0:
				_errors.append("mesh build produced nothing for " + part.id)
				continue
			if built.aabb.get_volume() <= 0.0000001:
				empty += 1
				_warnings.append("degenerate bounds for %s (mirrored=%s)" % [part.id, mirrored])
	print("  meshes: built %d parts in both handednesses, %d degenerate" % [library.count(), empty])


## Every shipped preset must resolve with no content errors and no *blocking*
## validation errors — a preset that cannot fly is a content bug, not a lesson.
func _check_presets(library: PartLibrary) -> void:
	print("")
	print("── Presets ───────────────────────────────────────────────")
	for entry in library.presets:
		var preset_id := String(entry.get("id", "?"))
		var design := library.build_preset_design(preset_id)
		if design == null:
			_errors.append("preset %s did not build" % preset_id)
			continue
		var res := design.resolve(library)
		for e in res.content_errors:
			_errors.append("preset %s: %s" % [preset_id, String(e)])
		for e in res.stats.errors:
			_errors.append("preset %s: %s" % [preset_id, String(e)])
		var view_parts := res.placements.size()
		print("  %-22s %3d parts  %2d open  %6.0f t  %5.0f m/s  %4.1f deg/s  %s" % [
			preset_id,
			view_parts,
			res.open_sockets.size(),
			res.stats.get_stat("mass"),
			res.stats.top_speed,
			res.stats.agility,
			"warn: " + str(res.stats.warnings.size()) if not res.stats.warnings.is_empty() else "clean"
		])
		for w in res.stats.warnings:
			_warnings.append("preset %s: %s" % [preset_id, String(w)])
		# Shadow placements must always resolve to a real attachment.
		for p in res.placements:
			if design.get_attachment(p.data_path) == null:
				_errors.append("preset %s: placement %s has dead data path %s" % [
					preset_id, p.path, p.data_path
				])
		# Open sockets must be writable.
		for open_socket in res.open_sockets:
			var dp := String(open_socket["data_path"])
			var parent_path: String = String(ShipDesign.split_path(dp)[0])
			if design.get_attachment(parent_path) == null:
				_errors.append("preset %s: open socket %s has no data parent (%s)" % [
					preset_id, String(open_socket["path"]), parent_path
				])


## The point of the mirroring rules: fill one socket, get two parts; break
## symmetry, get two independent parts on the correct sides.
func _check_mirroring(library: PartLibrary) -> void:
	print("")
	print("── Mirroring ─────────────────────────────────────────────")
	var chassis: ShipPart = null
	var mirror_socket: PartSocket = null
	for c in library.chassis_list():
		for socket in c.sockets:
			if socket.is_mirror():
				chassis = c
				mirror_socket = socket
				break
		if chassis != null:
			break
	if chassis == null:
		_errors.append("no chassis in the catalogue has a mirrored socket pair")
		return

	var source_id := mirror_socket.mirror_of
	var design := ShipDesign.create(chassis.id)
	var candidates := library.parts_for_socket(chassis.get_socket(source_id))
	if candidates.is_empty():
		_errors.append("nothing fits %s/%s" % [chassis.id, source_id])
		return
	var part: ShipPart = candidates[0]

	if not design.place_part(source_id, part.id, library):
		_errors.append("could not place %s at %s" % [part.id, source_id])
		return
	var res := design.resolve(library)
	var src := res.get_placement(source_id)
	var twin := res.get_placement(mirror_socket.id)
	if src == null or twin == null:
		_errors.append("filling %s did not produce a twin at %s" % [source_id, mirror_socket.id])
		return
	print("  %s: filling %s produced %s (shadow=%s, mirrored=%s)" % [
		chassis.id, source_id, mirror_socket.id, twin.shadow, twin.mirrored
	])
	if not twin.shadow:
		_errors.append("generated twin at %s is not flagged as a shadow" % mirror_socket.id)
	if twin.mirrored == src.mirrored:
		_errors.append("twin at %s has the same handedness as its source" % mirror_socket.id)
	if twin.data_path != source_id:
		_errors.append("twin data path is %s, expected %s" % [twin.data_path, source_id])
	# The two must sit on opposite sides of the hull.
	if signf(src.xform.origin.x) == signf(twin.xform.origin.x):
		_errors.append("mirrored pair %s/%s are on the same side (x %.2f / %.2f)" % [
			source_id, mirror_socket.id, src.xform.origin.x, twin.xform.origin.x
		])
	# Reflected geometry must still point outboard, not back through the hull.
	var src_far := (src.xform * PartMeshFactory.build(src.part, src.mirrored).aabb).get_center()
	var twin_far := (twin.xform * PartMeshFactory.build(twin.part, twin.mirrored).aabb).get_center()
	if signf(src_far.x) == signf(twin_far.x) and absf(src_far.x) > 0.01:
		_errors.append("mirrored geometry for %s does not extend outboard (centres %.2f / %.2f)" % [
			mirror_socket.id, src_far.x, twin_far.x
		])
	print("  outboard check: source centre x=%.2f, twin centre x=%.2f" % [src_far.x, twin_far.x])

	# Break symmetry and confirm the override is independent, still reflected, and
	# still on the correct side.
	var broken := design.break_symmetry(mirror_socket.id, library)
	if broken == "":
		_errors.append("break_symmetry failed on %s" % mirror_socket.id)
		return
	var res2 := design.resolve(library)
	var twin2 := res2.get_placement(mirror_socket.id)
	if twin2 == null:
		_errors.append("broken-symmetry placement vanished at %s" % mirror_socket.id)
		return
	if twin2.shadow:
		_errors.append("broken-symmetry placement at %s is still a shadow" % mirror_socket.id)
	if not twin2.mirrored:
		_errors.append("broken-symmetry placement at %s lost its reflection" % mirror_socket.id)
	if signf(twin2.xform.origin.x) == signf(res2.get_placement(source_id).xform.origin.x):
		_errors.append("broken-symmetry placement moved to the wrong side")
	print("  break symmetry: %s now independent (shadow=%s, mirrored=%s, x=%.2f)" % [
		broken, twin2.shadow, twin2.mirrored, twin2.xform.origin.x
	])
	if not design.restore_symmetry(mirror_socket.id):
		_errors.append("restore_symmetry failed on %s" % mirror_socket.id)
	var res3 := design.resolve(library)
	if not res3.get_placement(mirror_socket.id).shadow:
		_errors.append("restore_symmetry did not return %s to a shadow" % mirror_socket.id)
	print("  restore symmetry: back to a generated twin")


## Autofill must make every chassis flyable on its own, or the starter experience
## is a wall of red text.
func _check_autofill(library: PartLibrary) -> void:
	print("")
	print("── Autofill per chassis ──────────────────────────────────")
	for chassis in library.chassis_list():
		var design := ShipDesign.create(chassis.id)
		var placed := library.autofill_required(design)
		var res := design.resolve(library)
		# A hull tagged "component" is a section of a larger ship (a capital spine
		# segment), not something that flies on its own, so flyability is not a
		# meaningful test for it.
		var is_component := chassis.tags.has("component")
		var state := "OK" if res.stats.errors.is_empty() else ("COMPONENT" if is_component else "ERRORS")
		print("  %-24s +%d parts  %s" % [chassis.id, placed, state])
		if is_component:
			continue
		for e in res.stats.errors:
			_errors.append("autofilled %s: %s" % [chassis.id, String(e)])


## Save/load must be lossless, because designs are shared as text.
func _check_round_trip(library: PartLibrary) -> void:
	print("")
	print("── Serialisation round trip ──────────────────────────────")
	for entry in library.presets:
		var preset_id := String(entry.get("id", "?"))
		var a := library.build_preset_design(preset_id)
		if a == null:
			continue
		var text := a.to_json()
		var b := ShipDesign.from_json(text)
		if b == null:
			_errors.append("%s did not survive a JSON round trip" % preset_id)
			continue
		var again := b.to_json()
		if text != again:
			_errors.append("%s is not stable across save/load" % preset_id)
		var ra := a.resolve(library)
		var rb := b.resolve(library)
		if ra.placements.size() != rb.placements.size():
			_errors.append("%s changed part count across a round trip (%d -> %d)" % [
				preset_id, ra.placements.size(), rb.placements.size()
			])
	print("  %d presets round-tripped byte-for-byte" % library.presets.size())
