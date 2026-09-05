## Turns a [ShipDesign] into a live scene graph.
##
## This is the seam between data and presentation: everything above it is pure
## data (parts, sockets, joints, poses) and everything below it is nodes. Nothing
## else in the module creates ship geometry, so a second consumer — the flight
## module, a shipyard preview, a paper-doll thumbnail — gets identical results by
## calling [method assemble] and nothing more.
class_name ShipAssembler
extends RefCounted

## Pick colliders never shrink below this, so a tiny antenna is still tappable on
## a phone. Touch targets that match the visual silhouette exactly are unusable
## for small parts.
const MIN_PICK_SIZE := Vector3(0.22, 0.22, 0.22)

## Physics layers. Parts and sockets are separated so a raycast can ask for one
## or the other: hovering asks for parts, dragging asks for sockets.
const LAYER_PARTS := 1
const LAYER_SOCKETS := 2

const SOCKET_MARKER_RADIUS := 0.16


## Build a fresh [ShipView] from [param design]. The returned view's `root` is
## not in the tree — the caller adds it and frees any previous one, which keeps
## this function free of scene-tree assumptions and callable from a test.
static func assemble(
	design: ShipDesign,
	library: PartLibrary,
	cargo_load := 0.0,
	with_colliders := true,
	with_sockets := true
) -> ShipView:
	var view := ShipView.new()
	view.resolution = design.resolve(library, cargo_load)

	view.root = Node3D.new()
	view.root.name = "Ship"
	view.parts_root = Node3D.new()
	view.parts_root.name = "Parts"
	view.root.add_child(view.parts_root)
	view.sockets_root = Node3D.new()
	view.sockets_root.name = "Sockets"
	view.root.add_child(view.sockets_root)

	var first := true
	for placement in view.resolution.placements:
		var built := PartMeshFactory.build(placement.part, placement.mirrored)
		_add_placement(view, design, placement, built, with_colliders)
		var box: AABB = placement.xform * built.aabb
		if first:
			view.aabb = box
			first = false
		else:
			view.aabb = view.aabb.merge(box)
		_collect_markers(view, placement, built)

	if with_sockets:
		for entry in view.resolution.open_sockets:
			_add_socket_marker(view, entry, with_colliders)
		view.show_sockets(false)

	if first:
		# Empty design (no chassis). Give the camera something sane to frame.
		view.aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 1, 2))
	return view


static func _add_placement(
	view: ShipView,
	design: ShipDesign,
	placement: Placement,
	built: PartMeshFactory.Built,
	with_colliders: bool
) -> void:
	var holder := Node3D.new()
	holder.name = ShipView.sanitise(placement.path)
	holder.transform = placement.xform
	view.parts_root.add_child(holder)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = built.mesh
	var overrides: Dictionary = {}
	if placement.attachment != null:
		overrides = placement.attachment.color_overrides
	var mat := ShipMaterials.make_part_material(design, overrides)
	mesh_inst.material_override = mat
	# No shadow casting: the GL Compatibility shadow path is the single biggest
	# cost on low-end mobile and the silhouette-led art direction does not need it.
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh_inst)

	view.part_nodes[placement.path] = holder
	view.part_meshes[placement.path] = mesh_inst
	view.part_materials[placement.path] = mat
	# Clicking an auto-mirrored copy edits its source, so both wings behave as one
	# object without the player having to learn the distinction.
	view.edit_paths[placement.path] = placement.editable_path()
	view.part_overrides[placement.path] = overrides

	if with_colliders:
		holder.add_child(_make_pick_area(built.aabb, LAYER_PARTS, {
			"kind": "part",
			"path": placement.editable_path(),
			"raw_path": placement.path,
		}))


static func _make_pick_area(box: AABB, layer: int, meta: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.name = "Pick"
	area.collision_layer = layer
	# Nothing needs collision *detection* — these exist purely to be raycast.
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	for key: Variant in meta:
		area.set_meta(String(key), meta[key])

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(
		maxf(box.size.x, MIN_PICK_SIZE.x),
		maxf(box.size.y, MIN_PICK_SIZE.y),
		maxf(box.size.z, MIN_PICK_SIZE.z)
	)
	shape.shape = box_shape
	shape.position = box.get_center()
	area.add_child(shape)
	return area


## Hoist part-local functional markers into ship space so the systems simulation
## can fire a gun or light an exhaust without knowing anything about the tree.
static func _collect_markers(view: ShipView, placement: Placement, built: PartMeshFactory.Built) -> void:
	var func_data := placement.part.func_data
	for m: Variant in built.marker_list("muzzle"):
		view.muzzles.append({
			"path": placement.path,
			"part": placement.part,
			"xform": placement.xform * (m as Transform3D),
			"func": func_data,
		})
	var radius := 0.3
	var radius_markers := built.marker_list("exhaust_radius")
	if not radius_markers.is_empty():
		radius = (radius_markers[0] as Transform3D).basis.get_scale().x
	for m: Variant in built.marker_list("exhaust"):
		view.exhausts.append({
			"path": placement.path,
			"part": placement.part,
			"xform": placement.xform * (m as Transform3D),
			"radius": radius,
			"func": func_data,
		})
	for m: Variant in built.marker_list("eye"):
		view.eyes.append({
			"path": placement.path,
			"xform": placement.xform * (m as Transform3D),
		})


## An empty socket, drawn as a ring plus a short axis cross. Deliberately not a
## filled sphere: rings read as "something goes here" and never hide the hull
## behind them.
static func _add_socket_marker(view: ShipView, entry: Dictionary, with_colliders: bool) -> void:
	var socket := entry["socket"] as PartSocket
	var path := String(entry["path"])

	var node := Node3D.new()
	node.name = "Socket_" + ShipView.sanitise(path)
	node.transform = entry["xform"] as Transform3D

	# Bigger mounts get bigger markers, so socket size is legible before you try
	# to fit anything into one.
	var size_bonus := 0
	for s in socket.size_classes:
		size_bonus = maxi(size_bonus, ShipPart.SIZE_CLASSES.find(s))
	var radius := SOCKET_MARKER_RADIUS * (1.0 + 0.28 * float(maxi(size_bonus, 0)))
	var color := ShipMaterials.socket_color(socket.required)

	# Fadeable: [ShipView.show_sockets] recolours these to signal compatibility,
	# and half of that signal is alpha.
	node.add_child(
		_line_instance(LowPoly.ring_lines(radius, 18, Vector3.FORWARD), color, "Ring", true)
	)
	node.add_child(_line_instance(LowPoly.axis_cross(radius * 0.85), color, "Cross", true))

	var label := Label3D.new()
	label.name = "Label"
	label.text = socket.display_name if socket.display_name != "" else socket.id
	label.font_size = 48
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 16
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.no_depth_test = true
	label.position = Vector3(0.0, radius + 0.1, 0.0)
	label.visible = false
	node.add_child(label)

	if with_colliders:
		var area := Area3D.new()
		area.name = "Pick"
		area.collision_layer = LAYER_SOCKETS
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("kind", "socket")
		area.set_meta("path", path)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		# Generous compared to the drawn ring: dropping a part onto a socket must
		# be forgiving, especially with a finger.
		sphere.radius = maxf(radius * 2.2, 0.34)
		shape.shape = sphere
		area.add_child(shape)
		node.add_child(area)

	view.sockets_root.add_child(node)
	view.socket_nodes[path] = node
	view.socket_labels[path] = label


static func _line_instance(
	mesh: ArrayMesh, color: Color, node_name: String, fadeable := false
) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = ShipMaterials.line_material(color, fadeable)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


## Reusable ground reference grid for the builder viewport.
##
## The caller is expected to drop it *below* the hull with [method grid_floor_y].
## Ship origins sit roughly at the middle of the hull, so a grid on the y = 0
## plane slices the ship in half and draws its lines across the far side of the
## fuselage. Geometrically correct, and the single loudest reason the ships read
## as see-through: nothing says "transparent" like a background line crossing a
## piece of hull.
static func make_grid(half_extent := 8.0, step := 1.0) -> MeshInstance3D:
	return _line_instance(
		LowPoly.grid_lines(half_extent, step), ShipMaterials.grid_color(), "Grid"
	)


## Where the grid plane belongs for a ship of these bounds: just clear of the
## lowest geometry, so it reads as a floor the ship is parked above.
static func grid_floor_y(bounds: AABB) -> float:
	return bounds.position.y - clampf(bounds.size.y * 0.35, 0.25, 2.5)
