## One part placed into one socket, plus whatever is placed on *that* part.
##
## The design tree is made entirely of these: the root attachment is the chassis,
## its children are the parts in the chassis sockets, their children are parts on
## sub-sockets, and so on to any depth. That recursion is where "true modularity"
## lives — a capital ship is the same data structure as a fighter, just deeper.
class_name PartAttachment
extends Resource

## Id of the [ShipPart] mounted here.
@export var part_id := ""

## Joint pose within the socket's limits: yaw/pitch/roll degrees, slide metres,
## scale multiplier. Always clamped by [PartJoint.clamp_pose] before use.
@export var pose: Dictionary = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "slide": 0.0, "scale": 1.0}

## Per-part colour overrides, channel name -> Color. Channels not present here
## inherit the ship palette, which is what makes "pick a faction, done" work
## while still allowing per-part painting for players who want it.
@export var color_overrides: Dictionary = {}

## socket_id -> PartAttachment. Sockets absent from this dictionary are empty.
@export var children: Dictionary = {}


static func create(part_id: String) -> PartAttachment:
	var a := PartAttachment.new()
	a.part_id = part_id
	return a


func get_pose_value(key: String) -> float:
	return float(pose.get(key, 1.0 if key == "scale" else 0.0))


func set_pose_value(key: String, value: float) -> void:
	pose[key] = value


func has_child(socket_id: String) -> bool:
	return children.has(socket_id)


func get_child_attachment(socket_id: String) -> PartAttachment:
	return children.get(socket_id, null) as PartAttachment


func set_child_attachment(socket_id: String, attachment: PartAttachment) -> void:
	if attachment == null:
		children.erase(socket_id)
	else:
		children[socket_id] = attachment


func clear_child(socket_id: String) -> void:
	children.erase(socket_id)


## Deep copy of this attachment and everything under it. Named clone_tree rather
## than the obvious duplicate_deep because Resource gained a native method of that
## name in Godot 4.5, and shadowing it is an error.
func clone_tree() -> PartAttachment:
	var copy := PartAttachment.new()
	copy.part_id = part_id
	copy.pose = pose.duplicate()
	copy.color_overrides = color_overrides.duplicate()
	for socket_id: Variant in children:
		var child := children[socket_id] as PartAttachment
		if child != null:
			copy.children[socket_id] = child.clone_tree()
	return copy


func to_dict() -> Dictionary:
	var d := {"part": part_id}
	var trimmed := {}
	for key: Variant in pose:
		var v := float(pose[key])
		var default_v := 1.0 if key == "scale" else 0.0
		if not is_equal_approx(v, default_v):
			trimmed[key] = snappedf(v, 0.001)
	if not trimmed.is_empty():
		d["pose"] = trimmed
	if not color_overrides.is_empty():
		var cols := {}
		for channel: Variant in color_overrides:
			cols[channel] = (color_overrides[channel] as Color).to_html(false)
		d["colors"] = cols
	if not children.is_empty():
		var kids := {}
		for socket_id: Variant in children:
			var child := children[socket_id] as PartAttachment
			if child != null:
				kids[socket_id] = child.to_dict()
		d["children"] = kids
	return d


static func from_dict(d: Dictionary) -> PartAttachment:
	var a := PartAttachment.new()
	a.part_id = String(d.get("part", ""))
	var raw_pose: Dictionary = d.get("pose", {})
	for key: Variant in raw_pose:
		a.pose[String(key)] = float(raw_pose[key])
	var raw_cols: Dictionary = d.get("colors", {})
	for channel: Variant in raw_cols:
		a.color_overrides[String(channel)] = Color.from_string(String(raw_cols[channel]), Color.MAGENTA)
	var raw_kids: Dictionary = d.get("children", {})
	for socket_id: Variant in raw_kids:
		a.children[String(socket_id)] = PartAttachment.from_dict(raw_kids[socket_id])
	return a
