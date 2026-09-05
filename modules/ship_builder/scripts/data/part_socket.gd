## A typed attachment point on a part.
##
## Sockets are what make the ship system modular rather than a fixed template:
## every part (not just the chassis) may expose sockets, so hulls chain into
## capital spines, pylons carry sub-weapons, and engine mounts carry greebles.
##
## A socket declares *what* may attach (category + size class), *where* it sits
## in the parent part's local space, and *how much* the attached part may be
## posed once mounted (see [PartJoint]).
class_name PartSocket
extends Resource

## Unique within the owning part. Used to address placements ("wing_l/pylon_1").
@export var id := ""
## Shown in the socket list and in spoken/live-region announcements.
@export var display_name := ""
## Part categories this socket will take, e.g. ["engine"]. Empty accepts any.
@export var accepts: Array[String] = []
## Part size classes this socket will take. Empty accepts any. This is the
## gate that stops a capital drive from snapping onto a fighter frame.
@export var size_classes: Array[String] = []
## Position in the owning part's local space, in metres.
@export var position := Vector3.ZERO
## Euler rotation in degrees applied to the socket frame. The attached part's
## -Z faces "outward" along this frame by convention.
@export var rotation_deg := Vector3.ZERO
## Flagged sockets produce a validation warning when left empty.
@export var required := false
## When set to another socket's id, this socket has no independent content: it
## mirrors whatever is placed in the referenced socket, reflected across X.
## Placing something here explicitly breaks the symmetry link.
@export var mirror_of := ""
## Articulation allowance for whatever lands here.
@export var joint: PartJoint
## Sockets sharing a non-empty group are posed together by the inspector, so a
## quad-pod engine cluster can be swept as one unit.
@export var symmetry_group := ""


static func from_dict(d: Dictionary) -> PartSocket:
	var s := PartSocket.new()
	s.id = String(d.get("id", ""))
	s.display_name = String(d.get("name", s.id.capitalize()))
	for c: Variant in d.get("accepts", []):
		s.accepts.append(String(c))
	for c: Variant in d.get("sizes", []):
		s.size_classes.append(String(c))
	if d.has("pos"):
		var p: Array = d["pos"]
		s.position = Vector3(p[0], p[1], p[2])
	if d.has("rot"):
		var r: Array = d["rot"]
		s.rotation_deg = Vector3(r[0], r[1], r[2])
	s.required = bool(d.get("required", false))
	s.mirror_of = String(d.get("mirror_of", ""))
	s.symmetry_group = String(d.get("group", ""))
	s.joint = PartJoint.from_dict(d.get("joint", {}))
	return s


## The socket's frame relative to the owning part's origin.
func local_transform() -> Transform3D:
	return Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(rotation_deg.x), deg_to_rad(rotation_deg.y), deg_to_rad(rotation_deg.z)
		)),
		position
	)


## True when this socket is a passive mirror of another socket.
func is_mirror() -> bool:
	return mirror_of != ""


func accepts_category(category: String) -> bool:
	return accepts.is_empty() or accepts.has(category)


func accepts_size(size_class: String) -> bool:
	return size_classes.is_empty() or size_classes.has(size_class)


func accepts_part(part: ShipPart) -> bool:
	if part == null:
		return false
	return accepts_category(part.category) and accepts_size(part.size_class)


## Why a part was rejected, for a UI that explains itself instead of just
## refusing the drop.
func rejection_reason(part: ShipPart) -> String:
	if part == null:
		return "No part"
	if not accepts_category(part.category):
		return "%s takes %s, not %s" % [display_name, _humanise(accepts), part.category]
	if not accepts_size(part.size_class):
		return "%s is a %s mount; %s is %s class" % [
			display_name, _humanise(size_classes), part.display_name, part.size_class
		]
	return ""


func _humanise(list: Array[String]) -> String:
	if list.is_empty():
		return "anything"
	return "/".join(list)
