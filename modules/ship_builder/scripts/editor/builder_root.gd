## The ship builder's controller: owns the design, the assembled view and the
## undo stack, and is the single place any UI panel goes to change something.
##
## Every panel talks to this node and nothing else. That is what keeps the module
## isolated the way the GDD asks for: the palette does not know the socket tree
## exists, the inspector does not know how meshes are built, and none of them
## touch [ShipDesign] directly. One consequence worth stating, because it is the
## rule that makes the mirroring architecture safe: **UI never mutates the design
## except through [method apply]**, and every path handed to a mutator is a *data*
## path, resolved here by [method data_path_of]. A view path taken from a pick ray
## can name a generated twin, and writing to one of those would silently do
## nothing.
class_name BuilderRoot
extends Control

## The view was reassembled; panels should refresh from it.
signal design_rebuilt(view: ShipView)
## Selection moved. Carries a data path, or "" for the chassis.
signal selection_changed(data_path: String)
## Undo/redo availability changed.
signal history_changed
## Something worth a toast happened.
signal notice(text: String, kind: String)
## A part is being considered (palette hover / drag). Carries the stats the ship
## *would* have, or null to clear the comparison.
signal preview_changed(preview: ShipStats, label: String)

const AUTOSAVE_PATH := "user://ship_builder_autosave.json"
const FLIGHT_SCENE := "res://modules/flight/flight_test.tscn"
const DESIGN_DIR := "user://designs"

## Below this width the side panels become overlay drawers instead of columns, so
## the builder is usable on a phone.
##
## Expressed in the density-corrected units [BuilderTheme.apply_density_scale]
## establishes, where the number means something physical: 1040 dp is a small
## tablet's short edge. Every phone, in either orientation, lands under it and
## gets drawers — which is the point, since three columns on a handset leave the
## ship about a thumb's width of screen.
const NARROW_WIDTH := 1040.0

## Named axis views, in number-key order. The view menu reads the same list.
const CAMERA_VIEWS: Array[String] = ["front", "side", "top", "back", "bottom"]

var library: PartLibrary
var design: ShipDesign
var view: ShipView
var history := EditHistory.new()

## Data path of the current selection. "" is the chassis, which is always valid.
var selected := ""
## Tonnes of cargo assumed aboard when computing stats. Laden and empty are
## different ships, and the stat panel lets the player see both.
var cargo_load := 0.0

var _world: Node3D
var _ship_holder: Node3D
var _viewport: BuilderViewport
var _systems: SystemsSim
var _grid: MeshInstance3D
var _grid_extent := 0.0
var _theme_dirty := false
var _narrow := false
var _suppress_rebuild := false

@onready var _camera: OrbitCamera = %Camera


## Content and the current design are prepared here, not in [method _ready].
## Godot readies children before their parent, so every panel's _ready runs first
## and reads `library`, `design` and the theme while it builds its controls. The
## node references and the first rebuild stay in _ready, where @onready vars and
## the panels' signal connections both exist.
func _enter_tree() -> void:
	library = PartLibrary.instance()
	library.load_all()
	_apply_theme()

	if not _load_autosave():
		design = library.default_design()
		library.autofill_required(design)


func _ready() -> void:
	_world = %World
	_ship_holder = %ShipHolder
	_viewport = %ViewportFrame
	_systems = %Systems

	history.changed.connect(func() -> void: history_changed.emit())

	_grid = ShipAssembler.make_grid(10.0, 1.0)
	_world.add_child(_grid)

	rebuild(false)
	_report_load_errors()
	get_viewport().size_changed.connect(_on_window_resized)
	BuilderTheme.apply_density_scale(get_window())
	_on_window_resized()
	# Broadcast the starting mode now that every panel has connected: panels run
	# their _ready before this one, so anything emitted earlier had no listeners.
	_viewport.set_drag_mode(BuilderViewport.DragMode.LOOK)
	# A builder with no instructions is a wall of buttons. New players get the
	# walkthrough card; returning ones, who have already dismissed it, get the
	# one-line reminder instead.
	if coach().has_seen("walkthrough"):
		notice.emit("Drag a part onto a glowing mount, or press ? for help", "info")
	else:
		coach().start()


func _exit_tree() -> void:
	_save_autosave()


func _report_load_errors() -> void:
	if library.load_errors.is_empty():
		return
	push_warning("Part library loaded with %d problems." % library.load_errors.size())
	for e in library.load_errors:
		push_warning("  " + String(e))
	notice.emit(
		"%d content problems — see the log" % library.load_errors.size(), "error"
	)


# --- Rebuild ---------------------------------------------------------------

## Re-resolve the design and rebuild every mesh. Cheap enough to run on every
## edit: meshes are cached per part, so a rebuild is a few hundred node creations
## and no geometry work in the common case.
func rebuild(keep_camera := true) -> void:
	if _suppress_rebuild:
		return
	var sockets_were_visible := view != null and view.sockets_visible()
	var labels_were_visible := false
	if view != null:
		labels_were_visible = view.socket_labels.size() > 0 and _viewport != null and _viewport.socket_labels_on
		view.destroy()

	view = ShipAssembler.assemble(design, library, cargo_load)
	_ship_holder.add_child(view.root)

	# Selection survives a rebuild whenever the path still exists. It usually does
	# — swapping a part keeps the socket — and losing it on every edit would make
	# the inspector useless.
	if not view.has_path(selected) and selected != "":
		selected = _nearest_surviving_path(selected)
	view.set_selected(selected)
	if sockets_were_visible:
		view.show_sockets(true)
	view.set_socket_labels_visible(labels_were_visible)

	if _systems != null:
		_systems.bind(view, self)
	_place_grid()

	if not keep_camera:
		_camera.frame(view.aabb, _viewport_aspect(), true)

	for e in view.resolution.content_errors:
		push_warning("design: " + String(e))

	design_rebuilt.emit(view)
	selection_changed.emit(selected)


## Drop the reference grid clear of the hull and size it to the ship.
##
## The grid is a floor, not a section plane. Left on y = 0 it passes through the
## middle of every hull and paints its own lines across the far side of the
## fuselage, which is the difference between a ship that looks parked over a grid
## and one that looks made of glass.
func _place_grid() -> void:
	if _grid == null or view == null:
		return
	_grid.position.y = ShipAssembler.grid_floor_y(view.aabb)
	# A capital keel is 90 m long; a ten-metre grid under it conveys nothing.
	var wanted := clampf(maxf(view.aabb.size.x, view.aabb.size.z) * 1.6, 8.0, 120.0)
	var step := 1.0 if wanted <= 24.0 else (2.0 if wanted <= 60.0 else 5.0)
	if not is_equal_approx(_grid_extent, wanted):
		_grid_extent = wanted
		_grid.mesh = LowPoly.grid_lines(wanted, step)


## After a destructive edit the selected path may be gone. Walk up its ancestors
## until something exists, rather than dumping the player back at the chassis.
func _nearest_surviving_path(path: String) -> String:
	var probe := path
	while probe != "":
		probe = String(ShipDesign.split_path(probe)[0])
		if view.has_path(probe):
			return probe
	return ""


func _viewport_aspect() -> float:
	if _viewport == null:
		return 1.6
	var s := _viewport.size
	return maxf(s.x, 1.0) / maxf(s.y, 1.0)


# --- The one mutation path -------------------------------------------------

## Run a mutation inside the undo system.
##
## [param mutate] takes no arguments and returns true if it changed anything. On
## true the design is rebuilt and one undo entry is recorded. This is the only
## sanctioned way to change the design, so undo can never miss an edit.
func apply(label: String, mutate: Callable) -> bool:
	var before := design.to_dict()
	var changed: bool = mutate.call()
	if not changed:
		return false
	var after := design.to_dict()
	if history.in_transaction():
		# A continuous edit is in progress; it will record one entry on commit.
		rebuild()
		return true
	history.push(label, before, after)
	rebuild()
	return true


## Open a coalescing edit — a slider drag or a colour scrub. Every [method apply]
## until [method end_continuous] folds into a single undo entry.
func begin_continuous(label: String) -> void:
	history.begin(label, design.to_dict())


func end_continuous() -> void:
	if history.in_transaction():
		history.commit(design.to_dict())


func undo() -> void:
	if not history.can_undo():
		notice.emit("Nothing to undo", "info")
		return
	var label := history.undo_label()
	_restore(history.undo())
	notice.emit("Undid: " + label, "info")


func redo() -> void:
	if not history.can_redo():
		notice.emit("Nothing to redo", "info")
		return
	var label := history.redo_label()
	_restore(history.redo())
	notice.emit("Redid: " + label, "info")


func _restore(state: Dictionary) -> void:
	if state.is_empty():
		return
	design = ShipDesign.from_dict(state)
	rebuild()


# --- Path helpers ----------------------------------------------------------

## Convert any path the UI might be holding into the data path that owns it.
##
## Pick rays and marker lists hand out *view* paths, which inside a mirrored
## subtree name a generated twin with no attachment of its own. Writing to one
## would silently do nothing, so everything funnels through here first.
func data_path_of(path: String) -> String:
	if view == null:
		return path
	var placement := view.resolution.get_placement(path)
	if placement != null:
		return placement.editable_path()
	return view.resolution.data_path_for_socket(path)


func placement_at(path: String) -> Placement:
	if view == null:
		return null
	return view.resolution.get_placement(path)


## The part currently at a path, or null.
func part_at(path: String) -> ShipPart:
	var p := placement_at(path)
	return p.part if p != null else null


func selected_placement() -> Placement:
	return placement_at(selected)


func stats() -> ShipStats:
	return view.resolution.stats if view != null else null


# --- Selection -------------------------------------------------------------

func select(path: String) -> void:
	var data_path := data_path_of(path)
	if data_path == selected:
		return
	selected = data_path
	if view != null:
		view.set_selected(selected)
	selection_changed.emit(selected)


func hover(path: String) -> void:
	if view != null:
		view.set_hovered(data_path_of(path) if path != "" else "")


## Move the selection to the parent part. The keyboard route out of a nested
## greeble without hunting for its pylon in the viewport.
func select_parent() -> void:
	var p := selected_placement()
	if p == null or p.is_chassis():
		return
	select(p.parent_path)


# --- Editing ---------------------------------------------------------------

## Mount a part in an empty socket. [param socket_path] may be a view path.
func place_part(socket_path: String, part_id: String) -> bool:
	var part := library.get_part(part_id)
	if part == null:
		notice.emit("Unknown part: " + part_id, "error")
		return false
	var entry := view.resolution.find_open_socket(socket_path)
	if entry.is_empty():
		# Not an empty socket — treat it as a swap request on a filled one.
		return replace_part(socket_path, part_id)
	var socket := entry["socket"] as PartSocket
	if not socket.accepts_part(part):
		notice.emit(socket.rejection_reason(part), "error")
		return false
	var data_path := String(entry["data_path"])
	var was_shadow: bool = bool(entry.get("shadow", false))
	var ok := apply("Fit " + part.display_name, func() -> bool:
		return design.place_part(data_path, part_id, library)
	)
	if ok:
		selected = data_path
		view.set_selected(selected)
		selection_changed.emit(selected)
		if was_shadow:
			notice.emit("%s fitted to both sides" % part.display_name, "good")
		else:
			notice.emit("Fitted " + part.display_name, "good")
	return ok


## Swap the part already in a socket for another, keeping compatible children.
func replace_part(path: String, part_id: String) -> bool:
	var data_path := data_path_of(path)
	var placement := placement_at(path)
	var part := library.get_part(part_id)
	if part == null:
		return false
	if data_path == "":
		return swap_chassis(part_id)
	if placement != null and placement.socket != null and not placement.socket.accepts_part(part):
		notice.emit(placement.socket.rejection_reason(part), "error")
		return false
	var ok := apply("Swap to " + part.display_name, func() -> bool:
		return design.place_part(data_path, part_id, library)
	)
	if ok:
		selected = data_path
		notice.emit("Swapped in " + part.display_name, "good")
	return ok


func remove_part(path: String) -> bool:
	var data_path := data_path_of(path)
	if data_path == "":
		notice.emit("The chassis cannot be removed — swap it instead", "error")
		return false
	var placement := placement_at(data_path)
	var label := placement.part.display_name if placement != null else "part"
	var ok := apply("Remove " + label, func() -> bool:
		return design.remove_at(data_path)
	)
	if ok:
		notice.emit("Removed " + label, "info")
	return ok


func remove_selected() -> void:
	remove_part(selected)


## Move a fitted part — and everything mounted on it — into a different socket.
##
## A move is not remove-then-fit: that would drop the part's own children, its
## pose and its paint. The whole attachment subtree is relocated intact, and only
## the pose is re-clamped, because the destination joint may be tighter than the
## one it came from.
func move_part(from_path: String, to_socket_path: String) -> bool:
	var from_data := data_path_of(from_path)
	if from_data == "":
		notice.emit("The chassis cannot be moved", "error")
		return false
	var entry := view.resolution.find_open_socket(to_socket_path)
	if entry.is_empty():
		notice.emit("That is not an empty socket", "error")
		return false
	var to_data := String(entry["data_path"])
	var socket := entry["socket"] as PartSocket
	var moving := design.get_attachment(from_data)
	if moving == null:
		return false
	var part := library.get_part(moving.part_id)
	if part == null:
		return false
	if not socket.accepts_part(part):
		notice.emit(socket.rejection_reason(part), "error")
		return false
	if to_data == from_data:
		return false
	# Moving a part into a socket underneath itself would detach the whole subtree
	# from the design and leave it parented to nothing.
	if to_data.begins_with(from_data + "/"):
		notice.emit("A part cannot be mounted on itself", "error")
		return false

	var subtree := moving.clone_tree()
	if socket.joint != null:
		socket.joint.clamp_pose(subtree.pose)
	var split := ShipDesign.split_path(to_data)
	var ok := apply("Move " + part.display_name, func() -> bool:
		if not design.remove_at(from_data):
			return false
		var new_parent := design.get_attachment(String(split[0]))
		if new_parent == null:
			return false
		new_parent.set_child_attachment(String(split[1]), subtree)
		return true
	)
	if ok:
		selected = to_data
		view.set_selected(selected)
		selection_changed.emit(selected)
		var label := socket.display_name if socket.display_name != "" else socket.id
		notice.emit("Moved %s to %s" % [part.display_name, label], "good")
	return ok


func swap_chassis(chassis_id: String) -> bool:
	var part := library.get_part(chassis_id)
	if part == null or part.category != "chassis":
		return false
	if part.id == design.chassis_id():
		return false
	var before_count := view.resolution.part_count()
	var ok := apply("Chassis: " + part.display_name, func() -> bool:
		return design.set_chassis(chassis_id, library)
	)
	if ok:
		selected = ""
		_camera.frame(view.aabb, _viewport_aspect())
		var kept := view.resolution.part_count()
		if kept < before_count:
			notice.emit(
				"%s fitted — %d part(s) did not transfer" % [part.display_name, before_count - kept],
				"warn"
			)
		else:
			notice.emit("Chassis swapped to " + part.display_name, "good")
	return ok


## Give one side of a mirrored pair its own data so the two can differ.
##
## [param path] is whatever the player clicked, which for a twin is a shadow view
## path. The break has to happen at [member Placement.shadow_root] — the outermost
## mirror socket in the chain — because that is the only socket in a shadow subtree
## whose parent is real data.
func break_symmetry(path: String) -> bool:
	var placement := placement_at(path)
	if placement == null:
		return false
	var target := placement.shadow_root
	if target == "":
		# Not a shadow. If it *is* a mirror socket with its own data it is already
		# independent; say so rather than doing nothing silently.
		if placement.socket != null and placement.socket.is_mirror():
			notice.emit("This side is already independent", "info")
		else:
			notice.emit("Only mirrored parts can have their symmetry broken", "info")
		return false
	var ok := apply("Break symmetry", func() -> bool:
		return design.break_symmetry(target, library) != ""
	)
	if ok:
		selected = target
		view.set_selected(selected)
		selection_changed.emit(selected)
		notice.emit("Symmetry broken — this side is now independent", "good")
	else:
		notice.emit("Could not break symmetry here", "error")
	return ok


## Return an independent side to following its twin.
func restore_symmetry(path: String) -> bool:
	var placement := placement_at(path)
	if placement == null or placement.socket == null or not placement.socket.is_mirror():
		notice.emit("Nothing to re-link here", "info")
		return false
	if placement.shadow:
		notice.emit("Already mirrored from the other side", "info")
		return false
	var target := placement.path
	var ok := apply("Re-link symmetry", func() -> bool:
		return design.restore_symmetry(target)
	)
	if ok:
		selected = _nearest_surviving_path(target)
		notice.emit("Re-linked — this side follows its twin again", "good")
	return ok


## Toggle symmetry at the selection, for the M key.
func toggle_symmetry_at(path: String) -> void:
	var placement := placement_at(path)
	if placement == null:
		return
	if placement.shadow:
		break_symmetry(path)
	elif placement.socket != null and placement.socket.is_mirror():
		restore_symmetry(path)
	else:
		notice.emit("Selected part is not part of a mirrored pair", "info")


func set_pose(path: String, key: String, value: float, continuous := false) -> void:
	var data_path := data_path_of(path)
	if data_path == "":
		return
	# Clamp here rather than only in [PartJoint.pose_transform]: a value that is
	# merely drawn inside its limits is still saved, copied and shared out of range,
	# and would jump the moment the joint's limits changed.
	var placement := placement_at(path)
	var joint := placement.socket.joint if placement != null and placement.socket != null else null
	if joint != null:
		value = float(joint.clamp_pose({key: value}).get(key, value))
	else:
		# A rigid mount has no pose. Writing the neutral value makes this a no-op
		# rather than a silent stash of numbers nothing will ever read.
		value = 1.0 if key == "scale" else 0.0
	if continuous and not history.in_transaction():
		begin_continuous("Adjust " + key)
	apply("Adjust " + key, func() -> bool:
		var attachment := design.get_attachment(data_path)
		if attachment == null:
			return false
		if is_equal_approx(attachment.get_pose_value(key), value):
			return false
		attachment.set_pose_value(key, value)
		return true
	)


func reset_pose(path: String) -> void:
	var data_path := data_path_of(path)
	apply("Reset pose", func() -> bool:
		var attachment := design.get_attachment(data_path)
		if attachment == null:
			return false
		var fresh := {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "slide": 0.0, "scale": 1.0}
		if attachment.pose == fresh:
			return false
		attachment.pose = fresh
		return true
	)
	notice.emit("Pose reset", "info")


# --- Paint -----------------------------------------------------------------

func set_palette_color(channel: String, color: Color, continuous := false) -> void:
	if continuous and not history.in_transaction():
		begin_continuous("Paint " + channel)
	# Repainting does not change geometry, so skip the whole rebuild and push the
	# new colours straight into the shader uniforms. This is what makes dragging a
	# colour picker feel instant even on a capital ship.
	var before := design.to_dict()
	if design.get_color(channel).is_equal_approx(color):
		return
	design.set_color(channel, color)
	design.faction_id = ""
	view.refresh_palette(design)
	if not history.in_transaction():
		history.push("Paint " + channel, before, design.to_dict())


func set_material_preset(preset: String) -> void:
	if not ShipDesign.MATERIAL_PRESETS.has(preset) or design.material_preset == preset:
		return
	var before := design.to_dict()
	design.material_preset = preset
	view.refresh_palette(design)
	history.push("Finish: " + preset, before, design.to_dict())
	notice.emit("Finish: " + preset, "info")


func set_part_color(path: String, channel: String, color: Color, continuous := false) -> void:
	var data_path := data_path_of(path)
	var attachment := design.get_attachment(data_path)
	if attachment == null:
		return
	if continuous and not history.in_transaction():
		begin_continuous("Paint part")
	var before := design.to_dict()
	attachment.color_overrides[channel] = color
	_refresh_part_palette(data_path)
	if not history.in_transaction():
		history.push("Paint part", before, design.to_dict())


func clear_part_color(path: String, channel := "") -> void:
	var data_path := data_path_of(path)
	var attachment := design.get_attachment(data_path)
	if attachment == null or attachment.color_overrides.is_empty():
		return
	var before := design.to_dict()
	if channel == "":
		attachment.color_overrides.clear()
	else:
		attachment.color_overrides.erase(channel)
	_refresh_part_palette(data_path)
	history.push("Clear part paint", before, design.to_dict())


## Push one part's palette to the shader without a rebuild. Covers every view path
## backed by this data path, so repainting a mirrored wing updates both sides.
func _refresh_part_palette(data_path: String) -> void:
	var attachment := design.get_attachment(data_path)
	if attachment == null:
		return
	for p in view.paths_in_group(data_path):
		var mat := view.material_for(p)
		if mat != null:
			ShipMaterials.apply_palette(mat, design, attachment.color_overrides)
			view.part_overrides[p] = attachment.color_overrides
	view.set_selected(selected)


func apply_faction(faction_id: String) -> void:
	var faction := library.get_faction(faction_id)
	if faction.is_empty():
		return
	var before := design.to_dict()
	if not library.apply_faction(design, faction_id):
		return
	view.refresh_palette(design)
	history.push("Livery: " + String(faction.get("name", faction_id)), before, design.to_dict())
	notice.emit("Livery: " + String(faction.get("name", faction_id)), "good")


# --- Whole-design operations ----------------------------------------------

func load_preset(preset_id: String) -> void:
	var fresh := library.build_preset_design(preset_id)
	if fresh == null:
		notice.emit("Could not load that design", "error")
		return
	design = fresh
	selected = ""
	history.clear(design.to_dict())
	rebuild(false)
	notice.emit("Loaded " + design.design_name, "good")


func new_design(chassis_id := "") -> void:
	var id := chassis_id
	if id == "":
		id = design.chassis_id()
	design = ShipDesign.create(id)
	design.design_name = "Untitled"
	selected = ""
	history.clear(design.to_dict())
	rebuild(false)
	notice.emit("Bare hull — nothing fitted", "info")


func autofill() -> void:
	var placed := 0
	var ok := apply("Fit required parts", func() -> bool:
		placed = library.autofill_required(design)
		return placed > 0
	)
	if ok:
		notice.emit("Fitted %d required part(s)" % placed, "good")
	else:
		notice.emit("Nothing required is missing", "info")


func strip_design() -> void:
	var ok := apply("Strip to hull", func() -> bool:
		if design.root == null or design.root.children.is_empty():
			return false
		design.root.children.clear()
		return true
	)
	if ok:
		selected = ""
		notice.emit("Stripped to the bare hull", "info")


func rename_design(new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	if trimmed == "" or trimmed == design.design_name:
		return
	var before := design.to_dict()
	design.design_name = trimmed
	history.push("Rename", before, design.to_dict())


func set_cargo_load(tonnes: float) -> void:
	if is_equal_approx(cargo_load, tonnes):
		return
	cargo_load = tonnes
	# Stats only; geometry is unchanged, but the stat panel reads from the
	# resolution, so a rebuild is the honest way to refresh it.
	rebuild()


# --- Persistence -----------------------------------------------------------

func design_json() -> String:
	return design.to_json()


func load_json(text: String) -> bool:
	var fresh := ShipDesign.from_json(text)
	if fresh == null or fresh.root == null:
		notice.emit("That is not a ship design", "error")
		return false
	if not library.has_part(fresh.root.part_id):
		notice.emit("Unknown chassis: " + fresh.root.part_id, "error")
		return false
	design = fresh
	selected = ""
	history.clear(design.to_dict())
	rebuild(false)
	notice.emit("Loaded " + design.design_name, "good")
	return true


func save_to_file(path := "") -> void:
	var target := path
	if target == "":
		DirAccess.make_dir_recursive_absolute(DESIGN_DIR)
		target = "%s/%s.json" % [DESIGN_DIR, _slug(design.design_name)]
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		notice.emit("Could not write " + target, "error")
		return
	f.store_string(design.to_json())
	f.close()
	notice.emit("Saved to " + target.get_file(), "good")


func load_from_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		notice.emit("Could not read " + path.get_file(), "error")
		return
	var text := f.get_as_text()
	f.close()
	load_json(text)


func saved_designs() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DESIGN_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			out.append(DESIGN_DIR + "/" + file_name)
	out.sort()
	return out


static func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if c.is_valid_identifier() or c.is_valid_int() else "_"
	return out.strip_edges().trim_prefix("_").trim_suffix("_") if out != "" else "design"


func _save_autosave() -> void:
	if design == null:
		return
	var f := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(design.to_json())
		f.close()


func _load_autosave() -> bool:
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return false
	var f := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var fresh := ShipDesign.from_json(text)
	if fresh == null or fresh.root == null or not library.has_part(fresh.root.part_id):
		return false
	design = fresh
	history.clear(design.to_dict())
	return true


# --- Preview (hover comparison) -------------------------------------------

## Compute what the ship's stats would be with [param part] fitted at
## [param socket_path], without touching the real design. Feeds the stat panel's
## delta column so the player can compare before committing.
func preview_fit(socket_path: String, part_id: String) -> void:
	var part := library.get_part(part_id)
	if part == null:
		clear_preview()
		return
	var probe := design.duplicate_design()
	var target := socket_path
	if target == "":
		var candidates := view.resolution.sockets_accepting(part)
		if candidates.is_empty():
			# Still worth previewing a chassis swap, which has no socket.
			if part.category == "chassis":
				probe.set_chassis(part_id, library)
				preview_changed.emit(probe.resolve(library, cargo_load).stats, part.display_name)
				return
			clear_preview()
			return
		target = String(candidates[0]["data_path"])
	else:
		target = data_path_of(target)
	if part.category == "chassis":
		probe.set_chassis(part_id, library)
	elif not probe.place_part(target, part_id, library):
		clear_preview()
		return
	preview_changed.emit(probe.resolve(library, cargo_load).stats, part.display_name)


## What the ship would be without the part at [param path].
func preview_removal(path: String) -> void:
	var data_path := data_path_of(path)
	if data_path == "":
		clear_preview()
		return
	var probe := design.duplicate_design()
	if not probe.remove_at(data_path):
		clear_preview()
		return
	var label := "without " + (part_at(data_path).display_name if part_at(data_path) != null else "part")
	preview_changed.emit(probe.resolve(library, cargo_load).stats, label)


func clear_preview() -> void:
	preview_changed.emit(null, "")


# --- Layout / theme -------------------------------------------------------

func _apply_theme() -> void:
	theme = BuilderTheme.build()


func toggle_high_contrast() -> void:
	BuilderTheme.high_contrast = not BuilderTheme.high_contrast
	ShipMaterials.high_contrast = BuilderTheme.high_contrast
	_apply_theme()
	# Socket markers and highlight colours are baked at assembly time, so the 3D
	# side needs a rebuild to pick up the new palette.
	rebuild()
	notice.emit(
		"High contrast %s" % ("on" if BuilderTheme.high_contrast else "off"), "info"
	)


## Snap the camera to a named axis view. Shared by the number-key shortcuts and
## the view menu so both stay in step.
func set_camera_view(view_name: String) -> void:
	_camera.set_view(view_name)


## Hand the current design to the flight test bed.
##
## The design goes across on disk rather than in memory, through the same
## autosave the builder writes on exit: the flight scene has to work when it is
## launched cold as well, and one loading path is one loading path to get wrong.
func launch_test_flight() -> void:
	_save_autosave()
	var err := get_tree().change_scene_to_file(FLIGHT_SCENE)
	if err != OK:
		notice.emit("Could not open the flight test scene", "error")


## The popup-instruction overlay: the first-run walkthrough and the one-shot
## tips. Reached through here rather than with %Coach from six different panels,
## so the node can move without a hunt.
func coach() -> CoachOverlay:
	return %Coach as CoachOverlay


func is_narrow() -> bool:
	return _narrow


func _on_window_resized() -> void:
	# Re-derive the density scale first: on Android a rotation changes the window
	# size, which changes the stretch factor the correction is divided by.
	BuilderTheme.apply_density_scale(get_window())
	var narrow := size.x < NARROW_WIDTH
	if narrow == _narrow:
		return
	_narrow = narrow
	# In narrow layout the panels become drawers, closed by default so the ship
	# gets the whole screen.
	var left: Control = %LeftPanel
	var right: Control = %RightPanel
	for panel: Control in [left, right]:
		if narrow:
			panel.visible = false
			# A drawer wide enough to read, narrow enough to leave a strip of ship
			# visible behind it so the player keeps their bearings.
			panel.custom_minimum_size.x = clampf(size.x * 0.82, 260.0, 360.0)
		else:
			panel.visible = true
			panel.custom_minimum_size.x = 300.0 if panel == left else 320.0
	# Crossing the breakpoint hands the 3D view most of the window or takes it
	# away again. Framing computed for the old rectangle leaves the ship as a
	# thumbnail in the middle of a phone screen, so re-fit it — deferred, because
	# the containers have not relaid out yet at the moment the size changed.
	if view != null:
		call_deferred("_reframe_after_layout")


func _reframe_after_layout() -> void:
	if view != null and _camera != null:
		_camera.frame(view.aabb, _viewport_aspect())


## Show or hide a side panel.
##
## In narrow layout the panels are drawers and only one may be open at a time: two
## overlapping drawers on a phone leave no ship visible. In wide layout they are
## independent, so either can be collapsed to give the ship more room.
func toggle_panel(which: String) -> void:
	var left: Control = %LeftPanel
	var right: Control = %RightPanel
	var target: Control = left if which == "left" else right
	var other: Control = right if which == "left" else left
	target.visible = not target.visible
	if _narrow and target.visible:
		other.visible = false


# --- Input ----------------------------------------------------------------

func _shortcut_input(event: InputEvent) -> void:
	# Shortcuts live here rather than in _input so a focused LineEdit still gets
	# its keystrokes: _shortcut_input runs before _input but after GUI text entry
	# has had its say.
	if event.is_action_pressed("build_undo", true):
		undo()
		accept_event()
	elif event.is_action_pressed("build_redo", true):
		redo()
		accept_event()
	elif event.is_action_pressed("build_delete"):
		remove_selected()
		accept_event()
	elif event.is_action_pressed("build_mirror"):
		toggle_symmetry_at(selected)
		accept_event()
	elif event.is_action_pressed("build_frame_ship"):
		_camera.frame(view.aabb, _viewport_aspect())
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_QUESTION, KEY_SLASH, KEY_F1:
				(%HelpOverlay as HelpOverlay).toggle()
				accept_event()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				set_camera_view(CAMERA_VIEWS[key.keycode - KEY_1])
				accept_event()
			KEY_G:
				_viewport.toggle_sockets()
				accept_event()
			KEY_L:
				_viewport.toggle_socket_labels()
				accept_event()
			KEY_P:
				_viewport.cycle_drag_mode()
				accept_event()
			KEY_BACKSLASH:
				select_parent()
				accept_event()
			KEY_BRACKETLEFT:
				toggle_panel("left")
				accept_event()
			KEY_BRACKETRIGHT:
				toggle_panel("right")
				accept_event()
