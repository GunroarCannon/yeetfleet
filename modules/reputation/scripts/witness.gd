## Witness: determines whether a faction ship actually observed an act.
##
## This is the design-critical part of M5 (TECHNICAL_PLAN §M5):
##   "Ram a hauler with nobody watching and nothing happens."
##
## A Witness is a lightweight helper — it holds no state beyond its
## configuration. Call [method get_observers] before recording a grudge;
## only record if the returned list is non-empty.
##
## Works in both 3D scene mode (nodes in tree, [method Node3D.global_position]
## available) and headless smoke mode (positions passed directly).
class_name Witness
extends RefCounted

# --- Configuration --------------------------------------------------------

## Maximum range (metres) within which a ship can witness an act.
const WITNESS_RANGE_M := 800.0

## PhysicsDirectSpaceState3D query exclusion list — filled by caller.
## If null, LOS check is skipped (permissive: any in-range ship witnesses).
var space_state: PhysicsDirectSpaceState3D = null

# --- Public API -----------------------------------------------------------

## Return a list of [Dictionary] {"node": Node3D, "faction_id": String} for
## every candidate observer that is within [constant WITNESS_RANGE_M] of
## [param act_position] AND has line-of-sight (if space_state is set).
##
## [param candidates] is an Array of Dictionaries {"node": Node3D, "faction_id": String}.
## Typically built by the IncidentDirector scanning its active incident actors.
func get_observers(act_position: Vector3, candidates: Array) -> Array:
	var result: Array = []
	for c in candidates:
		if not c is Dictionary:
			continue
		var node: Node3D = c.get("node", null)
		var faction: String = c.get("faction_id", "")
		if node == null or faction.is_empty():
			continue
		var pos: Vector3 = _safe_position(node)
		if pos.distance_to(act_position) > WITNESS_RANGE_M:
			continue
		if space_state != null and not _has_los(pos, act_position):
			continue
		result.append(c)
	return result


## Convenience overload for headless tests: pass positions as Vector3 directly
## instead of Node3D references. Each candidate is {position: Vector3,
## faction_id: String, id: String}.
func get_observers_positional(act_position: Vector3, candidates: Array) -> Array:
	var result: Array = []
	for c in candidates:
		if not c is Dictionary:
			continue
		var pos: Vector3 = c.get("position", Vector3.ZERO)
		var faction: String = c.get("faction_id", "")
		if faction.is_empty():
			continue
		if pos.distance_to(act_position) > WITNESS_RANGE_M:
			continue
		result.append(c)
	return result

# --- Private helpers ------------------------------------------------------

func _safe_position(node: Node3D) -> Vector3:
	if node.is_inside_tree():
		return node.global_position
	return node.position


func _has_los(from_pos: Vector3, to_pos: Vector3) -> bool:
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collide_with_areas = false
	var hit := space_state.intersect_ray(query)
	# LOS is clear if no solid geometry interrupted the ray.
	return hit.is_empty()
