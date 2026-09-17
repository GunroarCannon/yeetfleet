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

## The design this view was built from. Kept so [method restyle] can re-derive
## part colours without its caller having to hold the design alongside the view.
var design: ShipDesign = null

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
## Ship-space bounds of each placement's geometry, in the same space as
## [member aabb] and in the same order as [member resolution]'s placements.
## Feeds [method collision_hull].
var part_boxes: Array[AABB] = []

## Individual part colliders for direct physical interaction, vital for big ships.
var part_colliders: Array[CollisionShape3D] = []

## Single merged ArrayMesh instance for high performance on mobile / large fleets.
var baked_mesh_instance: MeshInstance3D = null

## Cached baked compound collision hull.
var _baked_hull: Array[Dictionary] = []

## Corner brackets drawn around the selected part. Built lazily and resized in
## place, because selection changes on every tap.
var _selection_cage: MeshInstance3D = null

var _selected_path := ""
var _hovered_path := ""
var _emphasised_socket := ""
var _filter_part: ShipPart = null
var _sockets_visible := false

## The uniform scale [method apply_scale] was last called with. Kept so
## [method _recompute_bounds] can re-derive ship-space bounds at the size the ship
## is actually drawn at, instead of at the unit scale the meshes are built in.
var _scale := 1.0


## Node names cannot contain "/", placement paths can, so keep them separate.
static func sanitise(path: String) -> String:
	return "chassis" if path == "" else path.replace("/", "__")


func has_path(path: String) -> bool:
	return part_nodes.has(path)


## Uniformly scale this ship (the "ship size" flight setting). Called right
## after assembly: geometry scales via [member root], and every ship-space number
## a downstream consumer reads — the bounding box, muzzle/exhaust/eye offsets —
## scales by the same factor. That way camera framing, collision radius, plumes
## and shots all agree with the bigger visuals without any of them knowing a
## scale exists. A no-op at the default scale of 1.
##
## Remembered on [member _scale] so that a later [method rebuild_meshes] re-derives
## the bounds at the same size rather than snapping the ship back to unit scale.
func apply_scale(s: float) -> void:
	if is_equal_approx(s, 1.0):
		return
	_scale = s
	root.scale = Vector3.ONE * s
	aabb.position *= s
	aabb.size *= s
	var scaled_boxes: Array[AABB] = []
	for box in part_boxes:
		scaled_boxes.append(AABB(box.position * s, box.size * s))
	part_boxes = scaled_boxes
	_scale_offsets(muzzles, s)
	_scale_offsets(exhausts, s)
	_scale_offsets(eyes, s)


## Re-ask [PartMeshFactory] for every part's mesh and swap it in place.
##
## A geometry style dial changes the mesh a part resolves to, but a ship already in
## the scene is holding the old one — its [MeshInstance3D]s point at meshes built
## under the previous look. This replaces the geometry without rebuilding the node
## tree, so parts keep their colour overrides, selection state and markers.
##
## The factory's cache is keyed by the look, so every part already built under this
## look is a hit and only the first switch to a look pays for the geometry.
func rebuild_meshes() -> void:
	for placement in resolution.placements:
		var inst := part_meshes.get(placement.path) as MeshInstance3D
		if inst == null:
			continue
		inst.mesh = PartMeshFactory.build(placement.part, placement.mirrored).mesh
	_recompute_bounds()


## Bring this ship fully up to date with the current look and palette: new geometry
## where a geometry dial moved, and refreshed shader uniforms and outline
## everywhere.
##
## One call rather than two because the halves have to happen together — a switch
## that replaced geometry but left the previous outline pass attached is
## half-applied, and every consumer that owns a [ShipView] would otherwise have to
## remember to do both.
##
## A whole new [ShipView] would also work, and is what a design change does, but
## that throws away selection, hover and socket state; a look switch is not a
## design change and should not feel like one.
func restyle(update_palette := true) -> void:
	if update_palette and design != null:
		design.refresh_palette()
	rebuild_meshes()
	for path: Variant in part_materials:
		var mat := part_materials[path] as ShaderMaterial
		if mat == null:
			continue
		var overrides: Dictionary = part_overrides.get(path, {})
		ShipMaterials.apply_palette(mat, design, overrides)
		ShipMaterials.apply_outline(mat)
	_baked_hull.clear()
	if baked_mesh_instance != null and is_instance_valid(baked_mesh_instance):
		enable_baked_mesh(true)


## Creates dedicated physical [CollisionShape3D] colliders for each part of the ship.
## Essential for big ships (carriers, motherships, freighters) so each part has physical collision.
func create_part_colliders(parent_node: Node3D = null) -> Array[CollisionShape3D]:
	var target: Node3D = parent_node
	if target == null:
		target = parts_root if parts_root != null else root
	if target == null:
		return []

	# Clear previous colliders
	for col in part_colliders:
		if is_instance_valid(col):
			col.queue_free()
	part_colliders.clear()

	part_colliders = MeshBaker.create_part_colliders(self, target)
	return part_colliders


## Toggles single baked ArrayMesh mode for extreme mobile rendering efficiency.
func enable_baked_mesh(enabled: bool) -> void:
	if enabled:
		if baked_mesh_instance == null or not is_instance_valid(baked_mesh_instance):
			baked_mesh_instance = MeshBaker.bake_ship_mesh(self)
			if baked_mesh_instance != null:
				parts_root.add_child(baked_mesh_instance)
		if baked_mesh_instance != null:
			baked_mesh_instance.visible = true
		for inst in part_meshes.values():
			if is_instance_valid(inst):
				inst.visible = false
	else:
		if baked_mesh_instance != null and is_instance_valid(baked_mesh_instance):
			baked_mesh_instance.visible = false
		for inst in part_meshes.values():
			if is_instance_valid(inst):
				inst.visible = true


## Re-derive the ship-space bounds and per-part boxes from the current meshes, and
## resize the pick areas to match.
##
## Chunkiness moves vertices, so a look switch that fattens or slims a hull also
## moves every number derived from its geometry: the box the camera frames, the
## per-part boxes the collision hull is built from, and the pick areas that decide
## what a tap on the hull actually hits.
func _recompute_bounds() -> void:
	var boxes: Array[AABB] = []
	var bounds := AABB()
	var first := true
	for placement in resolution.placements:
		var built := PartMeshFactory.build(placement.part, placement.mirrored)
		var box: AABB = placement.xform * built.aabb
		if not is_equal_approx(_scale, 1.0):
			box = AABB(box.position * _scale, box.size * _scale)
		boxes.append(box)
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	part_boxes = boxes
	aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 1, 2)) if first else bounds
	_resize_pick_areas()


## Match each part's pick box to its current bounds. A hull that grew under the new
## look would otherwise have dead patches where the geometry now reaches past its
## old collider — most visible on the builder's tap-to-select, which would stop
## responding on exactly the parts that just got fatter.
func _resize_pick_areas() -> void:
	for i in resolution.placements.size():
		var placement := resolution.placements[i]
		var holder := part_nodes.get(placement.path) as Node3D
		if holder == null:
			continue
		var area := holder.get_node_or_null("Pick") as Area3D
		if area == null or area.get_child_count() == 0:
			continue
		var shape := area.get_child(0) as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		var box: AABB = part_boxes[i]
		(shape.shape as BoxShape3D).size = Vector3(
			maxf(box.size.x, ShipAssembler.MIN_PICK_SIZE.x),
			maxf(box.size.y, ShipAssembler.MIN_PICK_SIZE.y),
			maxf(box.size.z, ShipAssembler.MIN_PICK_SIZE.z)
		)
		shape.position = box.get_center()


func _scale_offsets(list: Array[Dictionary], s: float) -> void:
	for entry in list:
		if entry.has("xform"):
			(entry["xform"] as Transform3D).origin *= s


## The ship's collision hull in ship space, for [PhysBody.set_hull]: one
## `{offset: Vector3, radius: float}` per hull section. Empty when the design
## built no geometry at all, in which case the caller's single sphere stands.
##
## A ship is not a sphere. Its bounds describe a long box, and the one sphere
## that encloses that box is enormous across the ship's short axes — two ships
## passing with two metres of clearance used to collide, because each was
## carrying a five-metre ball. Here each part's bounds become a chain of spheres
## down its longest axis, sized to that part's own cross-section, so contact
## happens where the geometry is and the separating push runs along the
## direction the hulls actually met.
##
## The fitting itself lives in [method HullFit.append_box_spheres], next to the
## [member PhysBody.hull] it produces, because large craft need the identical
## answer for their own parts.
func collision_hull() -> Array[Dictionary]:
	if not _baked_hull.is_empty():
		return _baked_hull
	_baked_hull = MeshBaker.bake_compound_spheres(part_boxes)
	return _baked_hull


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
			color = ShipMaterials.hover_color()
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
