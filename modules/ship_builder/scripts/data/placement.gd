## One resolved part instance in ship space.
##
## The design tree is recursive, but everything downstream (rendering, picking,
## stats, the systems sim, and eventually the flight module) wants a flat list.
## [ShipDesign.collect_placements] flattens the tree into these, each carrying a
## ship-space transform, so the assembler can parent every mesh directly under
## the ship root. That keeps rebuilds cheap and avoids a deep node hierarchy that
## GL Compatibility would have to walk every frame.
class_name Placement
extends RefCounted

## The part being placed.
var part: ShipPart
## "/"-joined socket ids from the chassis down, e.g. "wing_l/pylon_1".
## Empty string for the chassis itself. This is the stable identity used by
## selection, undo and the socket tree.
var path := ""
## Path of the parent placement ("" for the chassis, which has no parent).
var parent_path := ""
## The socket this part sits in — null for the chassis.
var socket: PartSocket
## The design node backing this placement. For auto-mirrored placements this is
## the *source* attachment, shared with the placement it mirrors.
var attachment: PartAttachment
## Transform relative to the ship origin.
var xform := Transform3D.IDENTITY
## True when this placement's geometry is reflected across X.
##
## This is a property of the *socket*, not of the data: any part sitting in a
## mirror socket is reflected so it reads as the twin of its counterpart, whether
## its attachment was inherited from the source socket or overridden. It is kept
## separate from [member shadow] because the two answer different questions —
## "which way round is the mesh" versus "who owns the data".
var mirrored := false
## True when this placement has no attachment of its own and is drawn from the
## source side of a mirrored pair. Shadows cannot be selected or edited directly;
## everything routes to [member data_path], which keeps symmetric ships painless
## to build and keeps one attachment as the single source of truth.
var shadow := false
## The path whose attachment backs this placement. Equal to [member path] unless
## this is a shadow, in which case it names the authored counterpart — including
## for nested children, where every ancestor segment is rewritten, not just the
## last one.
var data_path := ""
## For a shadow, the path of the mirror socket where the shadowing began — the
## one place symmetry can be broken. Empty when this placement is not a shadow.
## Breaking there is always legal because that socket's parent is real data; a
## socket deeper inside a shadow subtree has no data parent to write to yet.
var shadow_root := ""
## Depth in the tree; 0 for the chassis.
var depth := 0


func _init(p_part: ShipPart = null, p_path := "", p_xform := Transform3D.IDENTITY) -> void:
	part = p_part
	path = p_path
	data_path = p_path
	xform = p_xform


## Path that owns this placement's data — itself, unless it is a shadow, in which
## case edits route to the authored side of the mirrored pair. The walk computes
## this as it descends, so it stays correct however deep the shadow subtree goes.
func editable_path() -> String:
	return data_path


func display_label() -> String:
	if part == null:
		return "(empty)"
	# The glyph marks a generated twin. Deliberately not shown for a part that is
	# merely reflected — an explicitly placed starboard part is a real, editable
	# part and should not look second-class.
	var suffix := "  ⟲" if shadow else ""
	return part.display_name + suffix


func is_chassis() -> bool:
	return path == ""
