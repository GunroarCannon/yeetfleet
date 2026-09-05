import io

p = 'modules/ship_builder/scripts/build/lowpoly.gd'
s = open(p, encoding='utf-8').read()

# --- 1. Header note about how winding is decided -----------------------------
old_head = """## Winding is handled by [method begin_shape] / [method end_shape]: faces added
## between the two are re-oriented to face away from that sub-shape centroid.
## Generators therefore do not have to reason about winding for the convex blocks
## they are made of, which removes the most common source of inside-out geometry."""
new_head = """## Winding is decided in two steps, because with back-face culling a single wrong
## face is a hole you can see straight through. Generators wind faces
## *consistently* -- every primitive below has a fixed winding rule, so a whole
## loft comes out all-outward or all-inward together -- and then
## [method end_shape] settles the absolute sign once, from the sub-shape's signed
## volume. Volume is exact for a closed surface, unlike testing each face against
## the shape centroid, which misfires on anything long or flat."""
assert old_head in s
s = s.replace(old_head, new_head)

# --- 2. Replace the whole orientation section --------------------------------
old_orient = s[s.index('# --- Sub-shape orientation'):s.index('# --- Primitives')]
new_orient = '''# --- Sub-shape orientation --------------------------------------------------

func begin_shape() -> void:
	_shape_start = _verts.size()


## Close the sub-shape opened by [method begin_shape], flipping it as a whole if
## it came out inside-out.
##
## The test is the signed volume of everything added since [method begin_shape]:
## for a closed surface that is positive only when the faces face outward, which
## makes this exact rather than a guess. It relies on the sub-shape being closed
## and consistently wound, which the primitives below guarantee.
##
## Pass false for geometry with no meaningful inside: flat decals, open plumes,
## anything double-sided. Their volume is ~0 and carries no signal.
func end_shape(auto_orient := true) -> void:
	if not auto_orient or _verts.size() - _shape_start < 3:
		_shape_start = _verts.size()
		return
	if _signed_volume(_shape_start, _verts.size()) < 0.0:
		flip_range(_shape_start, _verts.size())
	_shape_start = _verts.size()


## The enclosed volume, summed as tetrahedra from the vertex centroid.
## Origin-independent for a closed surface; the centroid shift only keeps the
## arithmetic well conditioned for shapes far from the origin.
func _signed_volume(from_index: int, to_index: int) -> float:
	var centroid := Vector3.ZERO
	for i in range(from_index, to_index):
		centroid += _verts[i]
	centroid /= float(maxi(to_index - from_index, 1))
	var vol := 0.0
	var i := from_index
	while i + 2 < to_index:
		vol += (_verts[i] - centroid).dot(
			(_verts[i + 1] - centroid).cross(_verts[i + 2] - centroid)
		)
		i += 3
	return vol / 6.0


## Reverse the winding of a run of triangles, flipping their normals with them.
func flip_range(from_index: int, to_index: int) -> void:
	var i := from_index
	while i + 2 < to_index:
		var v := _verts[i + 1]
		_verts[i + 1] = _verts[i + 2]
		_verts[i + 2] = v
		var t := _uvs[i + 1]
		_uvs[i + 1] = _uvs[i + 2]
		_uvs[i + 2] = t
		for k in 3:
			_normals[i + k] = -_normals[i + k]
		i += 3


static func ring_centroid(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in ring:
		c += v
	return c / float(maxi(ring.size(), 1))


## Best-fit plane normal of a ring (Newell's method), so it also holds for the
## slightly non-planar rings a lofted dome produces.
static func ring_normal(ring: PackedVector3Array) -> Vector3:
	var n := Vector3.ZERO
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		n += Vector3(
			(a.y - b.y) * (a.z + b.z),
			(a.z - b.z) * (a.x + b.x),
			(a.x - b.x) * (a.y + b.y)
		)
	return n.normalized() if n.length_squared() > 0.0 else Vector3.BACK


'''
s = s.replace(old_orient, new_orient)

# --- 3. add_cap gains an explicit winding direction -------------------------
old_cap = '''## Fan-triangulate a ring into a flat cap.
func add_cap(ring: PackedVector3Array, channel := CH_PRIMARY) -> void:
	if ring.size() < 3:
		return
	var centroid := Vector3.ZERO
	for v in ring:
		centroid += v
	centroid /= float(ring.size())
	for i in ring.size():
		var j := (i + 1) % ring.size()
		add_tri(centroid, ring[i], ring[j], channel)'''
new_cap = '''## Fan-triangulate a ring into a flat cap. [param reverse] winds it the other
## way, which is what the *start* of a loft needs: the two ends of a tube face
## opposite directions, so they cannot share one winding rule.
func add_cap(ring: PackedVector3Array, channel := CH_PRIMARY, reverse := false) -> void:
	if ring.size() < 3:
		return
	var centroid := ring_centroid(ring)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		if reverse:
			add_tri(centroid, ring[j], ring[i], channel)
		else:
			add_tri(centroid, ring[i], ring[j], channel)'''
assert old_cap in s
s = s.replace(old_cap, new_cap)

# --- 4. Document the ring-wall rule -----------------------------------------
old_wall = '''## Connect two rings of equal length with quads (the walls of a loft).
func add_ring_wall'''
new_wall = '''## Connect two rings of equal length with quads (the walls of a loft).
##
## The winding here is fixed, never guessed. With a counter-clockwise profile and
## [param ring_b] ahead of [param ring_a] along the loft, every quad faces
## outward; run the loft the other way and they all come out inward *together*,
## which is the property [method end_shape] leans on to fix the sign with a single
## test instead of one per face.
func add_ring_wall'''
assert old_wall in s
s = s.replace(old_wall, new_wall)

# --- 5. add_loft: correct cap winding, deterministic sign for open lofts -----
old_loft = '''## Loft a series of rings into a closed hull. Rings must all have the same
## vertex count. This is the workhorse behind hulls, nacelles, pods and barrels.
func add_loft(rings: Array, channel := CH_PRIMARY, cap_start := true, cap_end := true) -> void:
	if rings.size() < 2:
		return
	begin_shape()
	for i in rings.size() - 1:
		add_ring_wall(rings[i], rings[i + 1], channel)
	if cap_start:
		add_cap(rings[0], channel)
	if cap_end:
		add_cap(rings[rings.size() - 1], channel)
	end_shape()'''
new_loft = '''## Loft a series of rings into a hull. Rings must all have the same vertex count.
## This is the workhorse behind hulls, nacelles, pods and barrels.
##
## A capped loft is closed, so signed volume settles its orientation. An uncapped
## one is an open tube with no volume to measure, so its sign comes from the
## geometry instead: whether the first ring's own normal already points along the
## loft. Prefer closed lofts -- an open tube shows its hollow interior the moment
## the camera catches its rim.
func add_loft(rings: Array, channel := CH_PRIMARY, cap_start := true, cap_end := true) -> void:
	if rings.size() < 2:
		return
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	begin_shape()
	for i in rings.size() - 1:
		add_ring_wall(rings[i], rings[i + 1], channel)
	if cap_start:
		add_cap(first, channel, true)
	if cap_end:
		add_cap(last, channel, false)
	if cap_start and cap_end:
		end_shape()
		return
	var axis := ring_centroid(last) - ring_centroid(first)
	if axis.length_squared() < 1e-9:
		axis = ring_normal(first)
	if ring_normal(first).dot(axis.normalized()) < 0.0:
		flip_range(_shape_start, _verts.size())
	end_shape(false)


## A raised band wrapping a body: structural rib, intake lip, hull collar.
##
## Built as a closed shell -- outer wall, both rims, and a disc sealing each inner
## edge -- rather than the open tube two rings alone would give. The inner discs
## sit buried inside the host body where nothing can see them, and in exchange the
## band never shows a hollow interior when the camera catches its edge.
## [param inset] is the inner radius as a fraction of the band, so 0.85 leaves a
## band one-sixth of its radius thick.
func add_shell_band(
	ring_a: PackedVector3Array, ring_b: PackedVector3Array, inset := 0.85, channel := CH_TRIM
) -> void:
	if ring_a.size() < 3 or ring_a.size() != ring_b.size():
		return
	add_loft([
		scale_ring(ring_a, inset), ring_a, ring_b, scale_ring(ring_b, inset)
	], channel, true, true)


## Shrink a ring toward its own centroid, keeping it in its own plane.
static func scale_ring(ring: PackedVector3Array, factor: float) -> PackedVector3Array:
	var c := ring_centroid(ring)
	var out := PackedVector3Array()
	for v in ring:
		out.append(c + (v - c) * factor)
	return out'''
assert old_loft in s
s = s.replace(old_loft, new_loft)

s = s.replace('''	# index bits: x<<2 | y<<1 | z
	begin_shape()''', '''	# index bits: x<<2 | y<<1 | z. These six quads are wound outward by hand, so
	# the orientation check only ever confirms them.
	begin_shape()''')

open(p, 'w', encoding='utf-8').write(s)
print("lowpoly.gd rewritten OK")
