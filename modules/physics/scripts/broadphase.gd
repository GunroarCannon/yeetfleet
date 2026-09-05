## Broadphase: the uniform spatial hash that turns O(n²) "check every rock"
## into "check the rocks near me".
##
## Cell size is twice the largest body radius in the world, so any two bodies
## that could possibly touch — centres closer than r_a + r_b ≤ 2·max_r — are
## guaranteed to sit in cells that are neighbours. Candidate pairs are then
## gathered by walking each occupied cell against itself and its forward
## neighbours, so a pair is produced exactly once. That is the whole design:
## a cheap prune that the real [ImpulseSolver] does the expensive work on.
class_name Broadphase
extends RefCounted


## All candidate pairs in the world this step, each as [body_i, body_j] with
## i < j. `bodies` is the live [PhysWorld] roster.
static func pairs(bodies: Array[PhysBody]) -> Array:
	if bodies.size() < 2:
		return []
	var cells := _build_cells(bodies)
	return _neighbour_pairs(cells)


## Map of cell coord (Vector3i) -> indices into `bodies`. Bodies are keyed by
## index, not by object, so the pair list below can stay a list of ints.
static func _build_cells(bodies: Array[PhysBody]) -> Dictionary:
	var cell := _cell_size(bodies)
	var cells := {}
	for i in bodies.size():
		var b: PhysBody = bodies[i]
		var key := Vector3i(
			floori(b.position().x / cell),
			floori(b.position().y / cell),
			floori(b.position().z / cell)
		)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(i)
	return cells


## 2 × the largest radius, with a floor so a world of specks still gets usable
## cells. Radius can never be negative, so a body that forgot to set one cannot
## silently shrink the cell to nothing.
static func _cell_size(bodies: Array[PhysBody]) -> float:
	var max_r := 0.0
	for b in bodies:
		max_r = maxf(max_r, b.radius)
	return maxf(max_r * 2.0, 1.0)


## For every occupied cell, pair its bodies internally (i < j) and against the
## "forward" neighbours — the 13 offsets (dx,dy,dz) chosen so each unordered
## pair of cells is visited exactly once: dx>0, or dx==0 and dy>0, or dx==0 and
## dy==0 and dz>0.
static func _neighbour_pairs(cells: Dictionary) -> Array:
	var out: Array = []
	var offsets := _forward_offsets()
	for key in cells:
		var here := cells[key] as Array
		_same_cell_pairs(here, out)
		var k: Vector3i = key
		for o in offsets:
			var other_key := k + (o as Vector3i)
			if cells.has(other_key):
				_cross_cell_pairs(here, cells[other_key] as Array, out)
	return out


## (dx, dy, dz) cell offsets that visit each neighbour pair once. The 13 are
## +x; same-x +y; same-x same-y +z.
static func _forward_offsets() -> Array[Vector3i]:
	var offsets: Array[Vector3i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if dx > 0 or (dx == 0 and (dy > 0 or (dy == 0 and dz > 0))):
					offsets.append(Vector3i(dx, dy, dz))
	return offsets


static func _same_cell_pairs(indices: Array, out: Array) -> void:
	for i in indices.size():
		for j in range(i + 1, indices.size()):
			out.append([indices[i], indices[j]])


static func _cross_cell_pairs(a: Array, b: Array, out: Array) -> void:
	for i in a:
		for j in b:
			out.append([i, j])
