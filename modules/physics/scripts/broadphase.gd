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


const FORWARD_OFFSETS: Array[Vector3i] = [
	Vector3i(1, -1, -1), Vector3i(1, -1, 0), Vector3i(1, -1, 1),
	Vector3i(1, 0, -1),  Vector3i(1, 0, 0),  Vector3i(1, 0, 1),
	Vector3i(1, 1, -1),  Vector3i(1, 1, 0),  Vector3i(1, 1, 1),
	Vector3i(0, 1, -1),  Vector3i(0, 1, 0),  Vector3i(0, 1, 1),
	Vector3i(0, 0, 1)
]

static var _cells_cache: Dictionary = {}
static var _cell_dyn: Dictionary = {}
static var _cell_kin: Dictionary = {}
static var _cell_pool: Array[Array] = []
static var _out_pairs: Array = []
static var _pair_item_pool: Array[Array] = []


## All candidate pairs in the world this step, each as [body_i, body_j] with
## i < j. `bodies` is the live [PhysWorld] roster. A pair where both sides are
## kinematic (two rocks of scenery, a planet against a station) is never worth
## resolving — two infinite masses cannot move each other — and is dropped at
## generation, so a scenery wall cannot eat the world's pair budget.
static func pairs(bodies: Array[PhysBody]) -> Array:
	_recycle_pairs()
	if bodies.size() < 2:
		return _out_pairs
	_build_cells(bodies)
	_neighbour_pairs(bodies)
	return _out_pairs


static func _recycle_pairs() -> void:
	for p in _out_pairs:
		_pair_item_pool.append(p as Array)
	_out_pairs.clear()


## Map of cell coord (Vector3i) -> indices into `bodies`. Dynamic and kinematic
## bodies are separated per cell so clumps of kinematic scenery rocks never
## loop or check against each other.
static func _build_cells(bodies: Array[PhysBody]) -> void:
	for k in _cell_dyn:
		var arr: Array = _cell_dyn[k]
		arr.clear()
		_cell_pool.append(arr)
	for k in _cell_kin:
		var arr: Array = _cell_kin[k]
		arr.clear()
		_cell_pool.append(arr)
	_cells_cache.clear()
	_cell_dyn.clear()
	_cell_kin.clear()

	var cell := _cell_size(bodies)
	for i in bodies.size():
		var b: PhysBody = bodies[i]
		var key := Vector3i(
			floori(b.position().x / cell),
			floori(b.position().y / cell),
			floori(b.position().z / cell)
		)
		var target_dict := _cell_kin if b.kinematic else _cell_dyn
		var arr: Array
		if target_dict.has(key):
			arr = target_dict[key]
		else:
			arr = [] if _cell_pool.is_empty() else _cell_pool.pop_back()
			target_dict[key] = arr
			_cells_cache[key] = true
		arr.append(i)


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
static func _neighbour_pairs(bodies: Array[PhysBody]) -> void:
	for key in _cells_cache:
		var k: Vector3i = key
		var dyn_here: Array = _cell_dyn.get(k, [])
		var kin_here: Array = _cell_kin.get(k, [])

		# 1. Same cell:
		# Dynamic vs Dynamic
		for i in dyn_here.size():
			for j in range(i + 1, dyn_here.size()):
				_emit_pair_raw(dyn_here[i], dyn_here[j])
		# Dynamic vs Kinematic
		for d in dyn_here:
			for kin in kin_here:
				_emit_pair_raw(d, kin)
		# (Kinematic vs Kinematic is completely skipped!)

		# 2. Forward neighbours:
		for o in FORWARD_OFFSETS:
			var other_key := k + o
			if not _cells_cache.has(other_key):
				continue
			var dyn_other: Array = _cell_dyn.get(other_key, [])
			var kin_other: Array = _cell_kin.get(other_key, [])

			# Dynamic here vs Dynamic other
			for d1 in dyn_here:
				for d2 in dyn_other:
					_emit_pair_raw(d1, d2)
			# Dynamic here vs Kinematic other
			for d1 in dyn_here:
				for k2 in kin_other:
					_emit_pair_raw(d1, k2)
			# Kinematic here vs Dynamic other
			for k1 in kin_here:
				for d2 in dyn_other:
					_emit_pair_raw(k1, d2)
			# (Kinematic here vs Kinematic other is completely skipped!)


## (dx, dy, dz) cell offsets that visit each neighbour pair once. Kept for backwards
## compatibility and tooling.
static func _forward_offsets() -> Array[Vector3i]:
	return FORWARD_OFFSETS


static func _same_cell_pairs(indices: Array, bodies: Array[PhysBody]) -> void:
	for i in indices.size():
		for j in range(i + 1, indices.size()):
			_emit_pair(indices[i], indices[j], bodies)


static func _cross_cell_pairs(a: Array, b: Array, bodies: Array[PhysBody]) -> void:
	for i in a:
		for j in b:
			_emit_pair(i, j, bodies)


static func _emit_pair(i: int, j: int, bodies: Array[PhysBody]) -> void:
	if bodies[i].kinematic and bodies[j].kinematic:
		return
	_emit_pair_raw(i, j)


static func _emit_pair_raw(i: int, j: int) -> void:
	var first := mini(i, j)
	var second := maxi(i, j)
	if _pair_item_pool.is_empty():
		_out_pairs.append([first, second])
	else:
		var p: Array = _pair_item_pool.pop_back()
		p[0] = first
		p[1] = second
		_out_pairs.append(p)

