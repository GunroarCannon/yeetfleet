## The built scene graph for one ship, plus every lookup the editor needs.
##
## Rebuilt wholesale on each design change. That sounds wasteful and is not:
## meshes are cached per part by [PartMeshFactory], so a rebuild is a few dozen
## node allocations. One code path for "the design changed" removes a whole class
## of stale-state bugs that incremental updates invite.
class_name ShipView
extends RefCounted

var root: Node3D = null
var parts_root: Node3D = null
var sockets_root: Node3D = null
var resolution: DesignResolution = null

## placement path -> node
var part_nodes: Dictionary = {}
var part_meshes: Dictionary = {}
var part_materials: Dictionary = {}
## placement path -> the path that owns its data (differs only for mirrors).
var edit_paths: Dictionary = {}
## placement path -> colour override dictionary, so the palette can be re-applied
## without rebuilding the scene while a colour picker is being dragged.
var part_overrides: Dictionary = {}

## socket path -> node / label
var socket_nodes: Dictionary = {}
var socket_labels: Dictionary = {}

## Functional attachment points in ship space, for the systems simulation.
## Muzzle entry: {path, part, xform, func}. Exhaust adds radius.
var muzzles: Array[Dictionary] = []
var exhausts: Array[Dictionary] = []
## Cockpit eye points, for a cockpit camera.
var eyes: Array[Dictionary] = []

## Ship-space bounds of all part geometry.
var aabb := AABB()

## Corner brackets drawn around the selected part. Built lazily and resized in
## place, because selection changes on every tap.
var _selection_cage: MeshInstance3D = null

var _selected_path := ""
var _hovered_path := ""
var _emphasised_socket := ""
var _filter_part: ShipPart = null
var _sockets_visible := false


## Node names cannot contain "/", placement paths can, so keep them separate.
static func sanitise(path: String) -> String:
	return "chassis" if path == "" else path.replace("/", "__")


func has_path(path: String) -> bool:
	return part_nodes.has(path)


func material_for(path: String) -> ShaderMaterial:
	return part_materials.get(path, null) as ShaderMaterial


func mesh_for(path: String) -> MeshInstance3D:
	return part_meshes.get(path, null) as MeshInstance3D


func node_for(path: String) -> Node3D:
	return part_nodes.get(path, null) as Node3D


## Every placement path that shares this path's data — one entry normally, two
## for a mirrored pair.
func paths_in_group(edit_path: String) -> Array[String]:
	var out: Array[String] = []
	for p: Variant in edit_paths:
		if String(edit_paths[p]) == edit_path:
			out.append(String(p))
	return out


## Ship-space bounds of a placement and its mirror, for framing the camera on a
## selection and sizing the selection brackets.
func bounds_for(edit_path: String) -> AABB:
	var box := AABB()
	var first := true
	for path in paths_in_group(edit_path):
		var mesh := mesh_for(path)
		var holder := node_for(path)
		if mesh == null or holder == null:
			continue
		var local: AABB = holder.transform * mesh.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box


# --- Visual state -----------------------------------------------------------
# Selection is communicated three ways at once — brackets, a highlight tint, and
# dimming everything else — because any single channel fails for somebody.

func set_selected(edit_path: String) -> void:
	_selected_path = edit_path
	_refresh_highlights()


func set_hovered(edit_path: String) -> void:
	if _hovered_path == edit_path:
		return
	_hovered_path = edit_path
	_refresh_highlights()


func selected_path() -> String:
	return _selected_path


func hovered_path() -> String:
	return _hovered_path


func _refresh_highlights() -> void:
	for p: Variant in part_materials:
		var path := String(p)
		var owner_path := String(edit_paths.get(path, path))
		var mat := part_materials[path] as ShaderMaterial
		var amount := 0.0
		var color := ShipMaterials.selected_color()
		if owner_path == _selected_path:
			amount = 1.0
		elif owner_path == _hovered_path:
			amount = 0.45
			color = ShipMaterials.COL_HOVER
		ShipMaterials.set_highlight(mat, amount, color)
		# Only dim when something is selected, and never dim the selection or the
		# thing under the cursor.
		var dim := 0.0
		if _selected_path != "" and amount == 0.0:
			dim = 0.35
		ShipMaterials.set_dim(mat, dim)
	_refresh_selection_cage()


## The geometric half of the selection cue. The tint alone cannot carry it: the
## chassis is what the builder has selected when nothing else is, so a tint strong
## enough to be unmistakable would leave every ship sitting in selection gold
## instead of its own paint. Brackets say "this one" without touching the paint,
## and they say it to a colour-blind player too.
func _refresh_selection_cage() -> void:
	if root == null:
		return
	if _selection_cage == null:
		_selection_cage = MeshInstance3D.new()
		_selection_cage.name = "SelectionCage"
		_selection_cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(_selection_cage)
	var box := bounds_for(_selected_path)
	if box.size.length_squared() <= 0.0:
		_selection_cage.visible = false
		return
	_selection_cage.visible = true
	# Grown slightly so the lines sit clear of the hull rather than z-fighting it.
	_selection_cage.mesh = LowPoly.selection_brackets(box.grow(0.04), 0.25)
	_selection_cage.material_override = ShipMaterials.line_material(
		ShipMaterials.selected_color()
	)


## Re-apply the ship palette in place. Used while dragging colour pickers, where
## rebuilding the scene every frame would be silly.
func refresh_palette(design: ShipDesign) -> void:
	for p: Variant in part_materials:
		var path := String(p)
		var overrides: Dictionary = part_overrides.get(path, {})
		ShipMaterials.apply_palette(part_materials[path] as ShaderMaterial, design, overrides)
	_refresh_highlights()


# --- Socket markers ---------------------------------------------------------

## Show or hide the empty-socket markers. Passing the part being dragged turns the
## markers into an answer to "where can this go" rather than decoration.
##
## While a part is being carried, a marker means exactly one thing: **let go here
## and it fits**. Mounts that would refuse the part are hidden outright rather
## than drawn small and dim. Showing them was meant to be informative and was
## read as an invitation -- markers lit up all over the hull, the drop was
## refused at most of them, and the only lesson available was that the snapping
## is broken. What the player needs while carrying something is the shortlist,
## not the catalogue; the full set is one tap away on the G key the moment their
## hands are empty.
func show_sockets(visible_state: bool, filter_part: ShipPart = null) -> void:
	_sockets_visible = visible_state
	_filter_part = filter_part
	_emphasised_socket = ""
	for p: Variant in socket_nodes:
		var path := String(p)
		var node := socket_nodes[path] as Node3D
		if node == null:
			continue
		node.scale = Vector3.ONE
		if not visible_state:
			node.visible = false
			continue
		var entry := resolution.find_open_socket(path)
		if entry.is_empty():
			node.visible = false
			continue
		var socket := entry["socket"] as PartSocket
		if filter_part == null:
			node.visible = true
			_tint_socket(node, ShipMaterials.socket_color(socket.required))
		elif socket.accepts_part(filter_part):
			node.visible = true
			node.scale = Vector3.ONE * 1.35
			_tint_socket(node, ShipMaterials.valid_color())
		else:
			node.visible = false


func sockets_visible() -> bool:
	return _sockets_visible


## Emphasise one socket as the live drop target.
func emphasise_socket(path: String) -> void:
	if _emphasised_socket == path:
		return
	_emphasised_socket = path
	for p: Variant in socket_nodes:
		var node := socket_nodes[p] as Node3D
		if node == null or not node.visible:
			continue
		var entry := resolution.find_open_socket(String(p))
		if entry.is_empty():
			continue
		var socket := entry["socket"] as PartSocket
		var accepts := _filter_part == null or socket.accepts_part(_filter_part)
		if String(p) == path:
			node.scale = Vector3.ONE * 1.9
			_tint_socket(node, ShipMaterials.selected_color())
		elif _filter_part != null:
			# Only compatible markers are on screen at all while carrying a part,
			# so anything here is a live alternative to the one under the cursor.
			node.scale = Vector3.ONE * 1.35
			_tint_socket(node, ShipMaterials.valid_color())
		else:
			node.scale = Vector3.ONE
			_tint_socket(node, ShipMaterials.socket_color(socket.required))


func emphasised_socket() -> String:
	return _emphasised_socket


## Socket name plates. Off by default (they clutter a busy ship) but essential for
## keyboard-only building, where you need to know what the focused socket is.
func set_socket_labels_visible(visible_state: bool) -> void:
	for p: Variant in socket_labels:
		var label := socket_labels[p] as Label3D
		if label != null:
			label.visible = visible_state and (socket_nodes[p] as Node3D).visible


func _tint_socket(node: Node3D, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = color
		elif child is Label3D:
			(child as Label3D).modulate = Color(color.r, color.g, color.b, 1.0)


## Free the whole view. Callers hold no other references into it.
func destroy() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	parts_root = null
	sockets_root = null
	part_nodes.clear()
	part_meshes.clear()
	part_materials.clear()
	socket_nodes.clear()
	socket_labels.clear()
