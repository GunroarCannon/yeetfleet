## A complete, saveable ship: a chassis, the recursive tree of parts bolted to it,
## and the colour palette it is painted in.
##
## The design is pure data and holds no scene references, so it can be resolved
## into meshes, fed to the stat model, serialised to JSON for sharing, or handed
## to the flight module without any of those knowing about each other.
class_name ShipDesign
extends Resource

const FORMAT_VERSION := 1

## Colour channels, in the order the UI presents them. These map onto the
## vertex-colour mask baked into every part mesh.
const CHANNELS: Array[String] = ["primary", "accent", "trim"]

const CHANNEL_LABELS := {
	"primary": "Primary hull",
	"accent": "Accent / stripe",
	"trim": "Trim / shadow",
}

## Surface finishes. Values feed the shader roughness/metallic/weathering.
## Metallic is kept low across the board on purpose. The GL Compatibility
## renderer has no reflection probes, so a metallic surface has nothing but the
## flat ambient colour to mirror: it loses its diffuse shading and gains a broad
## wet highlight, which is precisely the plastic look these presets exist to
## avoid. Finish is carried by roughness and specular instead.
const MATERIAL_PRESETS := {
	"matte": {"roughness": 0.88, "metallic": 0.0, "specular": 0.18, "weathering": 0.05},
	"gloss": {"roughness": 0.46, "metallic": 0.12, "specular": 0.42, "weathering": 0.0},
	"weathered": {"roughness": 0.94, "metallic": 0.04, "specular": 0.12, "weathering": 0.6},
	"industrial": {"roughness": 0.70, "metallic": 0.20, "specular": 0.30, "weathering": 0.40},
}

## Channel -> the [Palette] role a fresh hull takes its paint from. A new design
## is painted from the active palette until the player picks colours of their own,
## at which point [member palette] holds explicit values and wins.
const CHANNEL_ROLES := {
	"primary": "hull_primary",
	"accent": "hull_accent",
	"trim": "hull_trim",
}


## The paint a fresh design starts on, read from the active palette.
##
## A function rather than a const because it follows the live palette: switching
## palettes has to change what the next new ship is painted in, and a const is
## baked at parse time.
static func default_palette() -> Dictionary:
	var out := {}
	for channel in CHANNELS:
		out[channel] = Palette.color(channel_role(channel))
	return out


## The palette role backing [param channel], defaulting to the hull primary for a
## channel this module does not know about.
static func channel_role(channel: String) -> String:
	return String(CHANNEL_ROLES.get(channel, "hull_primary"))

@export var design_name := "Untitled"
## The chassis and everything on it.
@export var root: PartAttachment
## Channel name -> Color.
@export var palette: Dictionary = {}
@export var material_preset := "matte"
## Id of the faction preset last applied, for display only.
@export var faction_id := ""


func _init() -> void:
	if palette.is_empty():
		palette = default_palette()


static func create(chassis_id: String) -> ShipDesign:
	var d := ShipDesign.new()
	d.root = PartAttachment.create(chassis_id)
	return d


func chassis_id() -> String:
	return root.part_id if root != null else ""


func get_color(channel: String) -> Color:
	return palette.get(channel, Palette.color(channel_role(channel)))


func set_color(channel: String, color: Color) -> void:
	palette[channel] = color


func material_params() -> Dictionary:
	return MATERIAL_PRESETS.get(material_preset, MATERIAL_PRESETS["matte"])


# --- Path addressing --------------------------------------------------------
# A path is the "/"-joined chain of socket ids from the chassis. The chassis
# itself is the empty string. Paths are the stable identity for selection, undo
# and the socket tree, and survive part swaps in the same socket.

## The attachment at a path, or null.
func get_attachment(path: String) -> PartAttachment:
	if path == "":
		return root
	var node := root
	for socket_id in path.split("/", false):
		if node == null:
			return null
		node = node.get_child_attachment(socket_id)
	return node


## Split a path into its parent path and final socket id.
static func split_path(path: String) -> Array:
	var idx := path.rfind("/")
	if idx == -1:
		return ["", path]
	return [path.substr(0, idx), path.substr(idx + 1)]


static func join_path(parent_path: String, socket_id: String) -> String:
	return socket_id if parent_path == "" else parent_path + "/" + socket_id


## Mount a part at a socket path, replacing whatever is there.
##
## When replacing, children still valid on the new part are carried over, so
## swapping a wing for a different wing keeps the pylons and their weapons.
func place_part(socket_path: String, part_id: String, library: PartLibrary) -> bool:
	if socket_path == "":
		return set_chassis(part_id, library)
	var split := split_path(socket_path)
	var parent := get_attachment(String(split[0]))
	if parent == null:
		return false
	var socket_id := String(split[1])
	var new_part := library.get_part(part_id)
	if new_part == null:
		return false
	var attachment := PartAttachment.create(part_id)
	var existing := parent.get_child_attachment(socket_id)
	if existing != null:
		attachment.color_overrides = existing.color_overrides.duplicate()
		_carry_over_children(existing, attachment, new_part, library)
	parent.set_child_attachment(socket_id, attachment)
	return true


## Swap the chassis, keeping any parts whose sockets still exist and still fit.
func set_chassis(part_id: String, library: PartLibrary) -> bool:
	var new_part := library.get_part(part_id)
	if new_part == null:
		return false
	var old := root
	root = PartAttachment.create(part_id)
	if old != null:
		root.color_overrides = old.color_overrides.duplicate()
		_carry_over_children(old, root, new_part, library)
	return true


func _carry_over_children(
	from_attachment: PartAttachment,
	to_attachment: PartAttachment,
	to_part: ShipPart,
	library: PartLibrary
) -> void:
	for socket_id: Variant in from_attachment.children:
		var socket := to_part.get_socket(String(socket_id))
		if socket == null:
			continue
		var child := from_attachment.get_child_attachment(String(socket_id))
		if child == null:
			continue
		var child_part := library.get_part(child.part_id)
		if child_part == null or not socket.accepts_part(child_part):
			continue
		to_attachment.set_child_attachment(String(socket_id), child.clone_tree())


func remove_at(socket_path: String) -> bool:
	if socket_path == "":
		return false
	var split := split_path(socket_path)
	var parent := get_attachment(String(split[0]))
	if parent == null:
		return false
	if not parent.has_child(String(split[1])):
		return false
	parent.clear_child(String(split[1]))
	return true


## Copy a mirrored placement data into its own socket so the two sides can
## diverge. Returns the path that now holds independent data.
func break_symmetry(mirror_socket_path: String, library: PartLibrary) -> String:
	var split := split_path(mirror_socket_path)
	var parent_path := String(split[0])
	var socket_id := String(split[1])
	var parent := get_attachment(parent_path)
	if parent == null:
		return ""
	var parent_part := library.get_part(parent.part_id)
	if parent_part == null:
		return ""
	var socket := parent_part.get_socket(socket_id)
	if socket == null or not socket.is_mirror():
		return ""
	var source := parent.get_child_attachment(socket.mirror_of)
	if source == null:
		return ""
	parent.set_child_attachment(socket_id, source.clone_tree())
	return mirror_socket_path


## Drop an explicit override on a mirror socket, returning it to following its
## source.
func restore_symmetry(mirror_socket_path: String) -> bool:
	return remove_at(mirror_socket_path)


func set_pose(socket_path: String, key: String, value: float) -> bool:
	var attachment := get_attachment(socket_path)
	if attachment == null:
		return false
	attachment.set_pose_value(key, value)
	return true


# --- Resolution ------------------------------------------------------------

## Reflect a transform across the YZ plane (negate X). Used for automatic socket
## mirroring. Applying it twice returns the original, and the basis stays
## right-handed, so lighting behaves. The mesh is mirrored separately by
## PartMeshFactory rather than by a negative scale.
static func reflect_x(t: Transform3D) -> Transform3D:
	var r := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3.ZERO)
	return r * t * r


## Flatten the design into placements, open sockets and stats.
func resolve(library: PartLibrary, cargo_load := 0.0) -> DesignResolution:
	var res := DesignResolution.new()
	res.stats = ShipStats.new()
	if root == null:
		res.content_errors.append("Design has no chassis.")
		res.stats.finalise(cargo_load)
		return res
	var chassis_part := library.get_part(root.part_id)
	if chassis_part == null:
		res.content_errors.append("Unknown chassis id: " + root.part_id)
		res.stats.finalise(cargo_load)
		return res
	res.stats.chassis = chassis_part
	_walk(root, "", "", "", null, Transform3D.IDENTITY, 1, false, "", 0, res, library)
	res.stats.finalise(cargo_load)
	return res


func _walk(
	attachment: PartAttachment,
	path: String,
	data_path: String,
	parent_path: String,
	socket: PartSocket,
	xform: Transform3D,
	mirror_sign: int,
	shadow: bool,
	shadow_root: String,
	depth: int,
	res: DesignResolution,
	library: PartLibrary
) -> void:
	var part := library.get_part(attachment.part_id)
	if part == null:
		res.content_errors.append("Unknown part id " + attachment.part_id + " at socket " + path)
		return

	var placement := Placement.new(part, path, xform)
	placement.parent_path = parent_path
	placement.socket = socket
	placement.attachment = attachment
	placement.mirrored = mirror_sign < 0
	placement.shadow = shadow
	placement.data_path = data_path
	placement.shadow_root = shadow_root
	placement.depth = depth
	res.placements.append(placement)
	res.by_path[path] = placement
	# Only count a part once. A shadow is the same physical part seen from the
	# other side of the hull... except it isn't: a mirrored pair is two real parts,
	# so both are counted. What must not happen is counting an explicit override
	# twice, and it cannot, because an override has its own attachment.
	res.stats.add_part(part)

	for child_socket in part.sockets:
		var child_path := join_path(path, child_socket.id)
		var socket_xform := _effective_socket_transform(part, child_socket, mirror_sign)
		var socket_world := xform * socket_xform

		var content: PartAttachment = null
		# Geometry mirroring follows the socket, not the data. A mirror socket's
		# frame is the reflection of its source's, so anything sitting in it must
		# be reflected too — an explicit override included, or a break-symmetry
		# wing would extend inboard through the hull.
		var child_sign := -mirror_sign if child_socket.is_mirror() else mirror_sign
		var child_shadow := shadow
		var child_shadow_root := shadow_root
		# Data for a mirror socket lives under the source socket id unless the
		# player has explicitly broken symmetry on this side.
		var child_data_id := child_socket.id
		var joint := child_socket.joint

		if child_socket.is_mirror():
			var explicit := attachment.get_child_attachment(child_socket.id)
			var source := attachment.get_child_attachment(child_socket.mirror_of)
			var source_socket := part.get_socket(child_socket.mirror_of)
			if source_socket != null:
				# Shared limits: the pair is one logical mount.
				joint = source_socket.joint
			if explicit != null:
				content = explicit
				# An override owns its data, so it stops being a shadow even if its
				# parent was one. Its own children then become editable as well.
				child_shadow = false
				child_shadow_root = ""
			elif source != null:
				content = source
				child_shadow = true
				child_data_id = child_socket.mirror_of
				# The outermost mirror socket in a chain of shadows is the only place
				# symmetry can be broken, so remember where that was.
				if shadow_root == "":
					child_shadow_root = child_path
		else:
			content = attachment.get_child_attachment(child_socket.id)

		var child_data_path := join_path(data_path, child_data_id)

		if content == null:
			# Mirror sockets are not offered as drop targets: fill the source and
			# both sides appear. Asymmetry is an explicit break-symmetry action,
			# which keeps symmetric building effortless.
			if not child_socket.is_mirror():
				res.open_sockets.append({
					"path": child_path,
					"data_path": child_data_path,
					"socket": child_socket,
					"xform": socket_world,
					"parent_path": path,
					"mirror_sign": mirror_sign,
					# A marker inside a shadow subtree has no attachment of its own;
					# dropping on it writes to data_path, so both sides fill at once.
					"shadow": shadow,
				})
			continue

		if joint == null:
			joint = PartJoint.rigid()
		var pose_x := joint.pose_transform(content.pose, child_sign < 0)
		_walk(
			content, child_path, child_data_path, path, child_socket,
			socket_world * pose_x, child_sign, child_shadow, child_shadow_root,
			depth + 1, res, library
		)


## A socket frame, honouring automatic mirroring and the current branch sign.
##
## A mirror socket left at the origin derives its transform by reflecting its
## source, so content authors place only the left wing and get the right for
## free. A mirror socket with explicit coordinates keeps them.
func _effective_socket_transform(part: ShipPart, socket: PartSocket, mirror_sign: int) -> Transform3D:
	var t := socket.local_transform()
	if socket.is_mirror() and socket.position.is_zero_approx() and socket.rotation_deg.is_zero_approx():
		var source := part.get_socket(socket.mirror_of)
		if source != null:
			t = reflect_x(source.local_transform())
	if mirror_sign < 0:
		t = reflect_x(t)
	return t


# --- Serialisation ---------------------------------------------------------
# Designs save as compact JSON: readable, diffable, and short enough to pass in a
# URL parameter for web sharing.

func to_dict() -> Dictionary:
	var cols := {}
	for channel in CHANNELS:
		cols[channel] = get_color(channel).to_html(false)
	return {
		"format": FORMAT_VERSION,
		"name": design_name,
		"faction": faction_id,
		"material": material_preset,
		"palette": cols,
		"root": root.to_dict() if root != null else {},
	}


static func from_dict(d: Dictionary) -> ShipDesign:
	var design := ShipDesign.new()
	design.design_name = String(d.get("name", "Untitled"))
	design.faction_id = String(d.get("faction", ""))
	design.material_preset = String(d.get("material", "matte"))
	var cols: Dictionary = d.get("palette", {})
	for channel: Variant in cols:
		design.palette[String(channel)] = Color.from_string(String(cols[channel]), Color.MAGENTA)
	var root_dict: Dictionary = d.get("root", {})
	design.root = PartAttachment.from_dict(root_dict) if not root_dict.is_empty() else null
	return design


func to_json(pretty := true) -> String:
	return JSON.stringify(to_dict(), "  " if pretty else "")


static func from_json(text: String) -> ShipDesign:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return from_dict(parsed)
	return null


func duplicate_design() -> ShipDesign:
	var copy := ShipDesign.new()
	copy.design_name = design_name
	copy.faction_id = faction_id
	copy.material_preset = material_preset
	copy.palette = palette.duplicate()
	copy.root = root.clone_tree() if root != null else null
	return copy
