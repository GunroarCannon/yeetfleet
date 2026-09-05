## The ship as a list: every mount, filled or empty, in declaration order.
##
## The viewport is the fun way to build and this is the reliable one. Deep nesting
## is where 3D picking gets frustrating — a greeble on a pylon on a wing is three
## pixels wide — so the same tree the data actually has is exposed as a plain,
## keyboard-navigable list. Empty mounts are rows too, which is the only way to see
## at a glance that a required hardpoint is still bare.
class_name SocketTree
extends VBoxContainer

var _root: BuilderRoot
var _tree: Tree
var _summary: Label
var _show_empty := true

## path -> TreeItem for the current build, used to hang children off parents.
var _items: Dictionary = {}
## Paths the player has collapsed, remembered across rebuilds so a rebuild does
## not re-expand a capital ship's entire greeble farm.
var _collapsed: Dictionary = {}
var _syncing := false


func _ready() -> void:
	_root = owner as BuilderRoot
	_build_ui()
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: refresh())
	_root.selection_changed.connect(_on_selection_changed)


func _build_ui() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "MOUNTS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", BuilderTheme.text_dim())
	header.add_child(title)
	var empty_toggle := CheckButton.new()
	empty_toggle.text = "Empty"
	empty_toggle.button_pressed = true
	empty_toggle.add_theme_font_size_override("font_size", 11)
	empty_toggle.tooltip_text = "List mounts that have nothing fitted"
	empty_toggle.toggled.connect(func(on: bool) -> void:
		_show_empty = on
		refresh()
	)
	header.add_child(empty_toggle)

	_tree = Tree.new()
	_tree.columns = 1
	_tree.hide_root = false
	_tree.allow_rmb_select = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.custom_minimum_size.y = 170
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_tree.button_clicked.connect(_on_button_clicked)
	add_child(_tree)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 10)
	_summary.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(_summary)


func refresh() -> void:
	if _root == null or _root.view == null:
		return
	_items.clear()
	_tree.clear()
	var resolution := _root.view.resolution
	var chassis := resolution.get_placement("")
	if chassis == null:
		return

	var open_by_path: Dictionary = {}
	for entry in resolution.open_sockets:
		open_by_path[String(entry["path"])] = entry

	var root_item := _tree.create_item()
	_decorate_part_row(root_item, chassis)
	_items[""] = root_item
	_add_sockets(root_item, chassis, open_by_path)

	var filled := resolution.part_count()
	var empty := resolution.open_sockets.size()
	var required_empty := 0
	for entry in resolution.open_sockets:
		if (entry["socket"] as PartSocket).required:
			required_empty += 1
	var text := "%d part(s) · %d mount(s) free" % [filled, empty]
	if required_empty > 0:
		text += " · %d required" % required_empty
	_summary.text = text
	_sync_selection()


## Walk one part's declared sockets, in the order the content author wrote them,
## so the list reads like the part sheet rather than like a hash map.
func _add_sockets(parent_item: TreeItem, placement: Placement, open_by_path: Dictionary) -> void:
	var resolution := _root.view.resolution
	for socket in placement.part.sockets:
		var child_path := ShipDesign.join_path(placement.path, socket.id)
		var child := resolution.get_placement(child_path)
		if child != null:
			var item := _tree.create_item(parent_item)
			_decorate_part_row(item, child, socket)
			_items[child_path] = item
			_add_sockets(item, child, open_by_path)
			continue
		if not _show_empty:
			continue
		var entry: Dictionary = open_by_path.get(child_path, {})
		if entry.is_empty():
			# A mirror socket whose source is empty: it is not offered as a drop
			# target, so listing it would be a row nothing can be done with.
			continue
		var socket_item := _tree.create_item(parent_item)
		_decorate_socket_row(socket_item, entry)
		_items[child_path] = socket_item


func _decorate_part_row(item: TreeItem, placement: Placement, socket: PartSocket = null) -> void:
	var mount := ""
	if socket != null:
		mount = socket.display_name if socket.display_name != "" else socket.id
	var label := placement.display_label()
	item.set_text(0, label if mount == "" else "%s · %s" % [mount, label])
	item.set_icon(0, BuilderTheme.swatch(_category_color(placement.part.category), 12))
	item.set_icon_max_width(0, 10)
	item.set_tooltip_text(0, _part_tooltip(placement, socket))
	item.set_metadata(0, {
		"kind": "part",
		"path": placement.path,
		"data_path": placement.editable_path(),
		"shadow": placement.shadow,
	})
	if placement.shadow:
		item.set_custom_color(0, BuilderTheme.text_dim())
	elif placement.is_chassis():
		item.set_custom_color(0, BuilderTheme.accent())
	if not placement.is_chassis() and not placement.shadow:
		item.add_button(0, BuilderTheme.swatch(BuilderTheme.bad(), 10), 0, false, "Remove this part")
	item.collapsed = _collapsed.has(placement.path)


func _decorate_socket_row(item: TreeItem, entry: Dictionary) -> void:
	var socket := entry["socket"] as PartSocket
	var label := socket.display_name if socket.display_name != "" else socket.id
	var suffix := "  (required)" if socket.required else ""
	item.set_text(0, "＋ %s%s" % [label, suffix])
	item.set_custom_color(0, BuilderTheme.warn() if socket.required else BuilderTheme.text_dim())
	item.set_tooltip_text(0, "%s\nTakes %s\nSize %s\n%s" % [
		label,
		", ".join(socket.accepts) if not socket.accepts.is_empty() else "anything",
		", ".join(socket.size_classes) if not socket.size_classes.is_empty() else "any",
		socket.joint.describe() if socket.joint != null else "Rigid mount",
	])
	item.set_metadata(0, {
		"kind": "socket",
		"path": String(entry["path"]),
		"data_path": String(entry.get("data_path", entry["path"])),
		"shadow": bool(entry.get("shadow", false)),
	})


func _part_tooltip(placement: Placement, socket: PartSocket) -> String:
	var lines: Array[String] = [placement.part.display_name, placement.part.summary()]
	if socket != null:
		lines.append("Mounted in " + (socket.display_name if socket.display_name != "" else socket.id))
		if socket.joint != null:
			lines.append(socket.joint.describe())
	if placement.shadow:
		lines.append("Mirrored twin — edits follow the other side. Break symmetry to give it its own fit.")
	elif placement.mirrored:
		lines.append("Reflected geometry, independent part.")
	return "\n".join(lines)


func _category_color(category: String) -> Color:
	match category:
		"chassis": return Color("6f7d94")
		"cockpit": return Color("57c7ff")
		"engine": return Color("ff9b4d")
		"weapon": return Color("ff6b6b")
		"cargo": return Color("6fe0a8")
		"wing": return Color("c99bff")
		"armor": return Color("d8c470")
		_: return Color("8b97a8")


# --- Interaction -----------------------------------------------------------

func _on_item_selected() -> void:
	if _syncing:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	var path := String(meta["path"])
	if String(meta["kind"]) == "socket":
		# Selecting an empty mount is the keyboard/list route into building: show
		# the marker, and narrow the palette to what fits.
		(%ViewportFrame as BuilderViewport).focus_socket(path)
		return
	_root.select(path)


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	if String(meta["kind"]) == "socket":
		(%ViewportFrame as BuilderViewport).focus_socket(String(meta["path"]))
	else:
		(%ViewportFrame as BuilderViewport).frame_ship()


func _on_item_collapsed(item: TreeItem) -> void:
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	var path := String(meta["path"])
	if item.collapsed:
		_collapsed[path] = true
	else:
		_collapsed.erase(path)


func _on_button_clicked(item: TreeItem, _column: int, _id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty() or String(meta["kind"]) != "part":
		return
	_root.remove_part(String(meta["path"]))


func _on_selection_changed(_data_path: String) -> void:
	_sync_selection()


## Mirror the app's selection into the list without re-emitting it, which would
## bounce the selection back and forth between the two views.
func _sync_selection() -> void:
	if _root.selected == "" and _tree.get_root() == null:
		return
	_syncing = true
	var target := _root.selected
	var item: TreeItem = _items.get(target, null)
	if item == null:
		# The selection may name a data path whose visible row is a mirrored twin.
		for path: String in _items:
			var candidate := _items[path] as TreeItem
			var meta: Dictionary = candidate.get_metadata(0)
			if not meta.is_empty() and String(meta.get("data_path", "")) == target:
				item = candidate
				break
	if item != null:
		item.select(0)
		_tree.scroll_to_item(item)
	else:
		_tree.deselect_all()
	_syncing = false
