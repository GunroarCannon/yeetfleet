## The flattened result of resolving a [ShipDesign] against a [PartLibrary].
##
## Produced fresh on every design change. Holds everything the renderer, the
## socket tree, the drag targeting and the systems sim need, so none of them has
## to walk the recursive design tree themselves.
class_name DesignResolution
extends RefCounted

## Every resolved part, chassis first, in depth-first order.
var placements: Array[Placement] = []
## Fast lookup by placement path.
var by_path: Dictionary = {}
## Empty sockets that can accept a part. Each entry is a Dictionary with keys:
## path (marker identity and position), data_path (where a drop must be written —
## these differ inside a mirrored subtree, so dropping on either side of a
## symmetric ship fills both), socket ([PartSocket]), xform ([Transform3D] in
## ship space), parent_path, mirror_sign (1 or -1, so a ghost preview is reflected
## the same way the real part will be), and shadow.
var open_sockets: Array[Dictionary] = []
## Aggregated performance and validation.
var stats: ShipStats = null
## Missing part ids and similar data faults, surfaced rather than swallowed so a
## typo in a JSON file is visible immediately instead of silently dropping a part.
var content_errors: Array[String] = []


func get_placement(path: String) -> Placement:
	return by_path.get(path, null) as Placement


func find_open_socket(path: String) -> Dictionary:
	for entry in open_sockets:
		if String(entry["path"]) == path:
			return entry
	return {}


## Open sockets that would accept the given part, nearest-first ordering left to
## the caller (which knows about the camera).
func sockets_accepting(part: ShipPart) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in open_sockets:
		var socket := entry["socket"] as PartSocket
		if socket.accepts_part(part):
			out.append(entry)
	return out


## Why [param part] has nowhere to go on this ship, in the player's terms.
##
## "Nothing here takes that part" is true and useless. There are three different
## situations behind it and they call for three different next moves: the hull
## has no mount of that kind at all (change hull, or fit the pylon that carries
## one), every mount of that kind is already occupied (remove something, or drag
## onto the fitted part to swap it), or the mounts exist and are free but are
## sized for a different class of ship (pick the same part a size down).
func explain_no_socket(part: ShipPart) -> String:
	if part == null:
		return "No part"
	var free_wrong_size := 0
	var occupied_right_kind := 0
	var exists_at_all := false
	for entry in open_sockets:
		var socket := entry["socket"] as PartSocket
		if not socket.accepts_category(part.category):
			continue
		exists_at_all = true
		if not socket.accepts_size(part.size_class):
			free_wrong_size += 1
	for placement in placements:
		if placement.socket == null or not placement.socket.accepts_category(part.category):
			continue
		exists_at_all = true
		if placement.socket.accepts_size(part.size_class):
			occupied_right_kind += 1
	var label := part.display_name
	if not exists_at_all:
		return "%s has no %s mount — try another hull" % [
			chassis_name(), part.category_label().to_lower()
		]
	if occupied_right_kind > 0:
		return "Every %s mount is full — drop %s onto a fitted one to swap it" % [
			part.category_label().to_lower(), label
		]
	if free_wrong_size > 0:
		return "%s is %s class; the free mounts here are a different size" % [
			label, part.size_class
		]
	return "No free mount on this hull takes %s" % label


## The hull's name, for messages that need to blame something concrete.
func chassis_name() -> String:
	if placements.is_empty() or placements[0].part == null:
		return "This hull"
	return placements[0].part.display_name


## Selectable placements only — auto-generated twins are edited via their source,
## so they are filtered out here and the socket tree never shows a row the player
## cannot act on. A part explicitly placed on the mirror side is *not* a shadow
## and stays selectable, which is the whole point of breaking symmetry.
func selectable_placements() -> Array[Placement]:
	var out: Array[Placement] = []
	for p in placements:
		if not p.shadow:
			out.append(p)
	return out


## Where a drop on [param socket_path] must be written. Differs from the marker
## path only inside a mirrored subtree; returns the input unchanged if the path is
## not a known open socket, so callers can pass either kind of path safely.
func data_path_for_socket(socket_path: String) -> String:
	var entry := find_open_socket(socket_path)
	if entry.is_empty():
		return socket_path
	return String(entry.get("data_path", socket_path))


## Total resolved part count including generated twins, for the stat panel.
func part_count() -> int:
	return placements.size()
