## Flat-shaded low-poly mesh builder.
##
## Every face gets its own vertices carrying the face normal, which is what gives
## the faceted look the art direction calls for and avoids needing smoothing
## groups or imported normals. Vertex colour is not a colour at all here: the red
## channel carries a *mask index* selecting primary / accent / trim, so one shared
## shader can retint any part instantly with no texture work.
##
## Winding is decided in two steps, because with back-face culling a single wrong
## face is a hole you can see straight through. Generators wind faces
## *consistently* -- every primitive below has a fixed winding rule, so a whole
## loft comes out all-outward or all-inward together -- and then
## [method end_shape] settles the absolute sign once, from the sub-shape's signed
## volume. Volume is exact for a closed surface, unlike testing each face against
## the shape centroid, which misfires on anything long or flat.
class_name LowPoly
extends RefCounted

## Mask values written into COLOR.r. The shader thresholds between them.
const CH_PRIMARY := 0.0
const CH_ACCENT := 0.5
const CH_TRIM := 1.0

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()

## When true, X is negated and winding reversed as faces are added, producing a
## true mirrored mesh instead of a negative-scale instance (which would break
## lighting under GL Compatibility).
var mirror := false

var _shape_start := 0


func vertex_count() -> int:
	return _verts.size()


# --- Sub-shape orientation --------------------------------------------------

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


# --- Primitives -------------------------------------------------------------

func add_tri(a: Vector3, b: Vector3, c: Vector3, channel := CH_PRIMARY) -> void:
	if mirror:
		a.x = -a.x
		b.x = -b.x
		c.x = -c.x
		var t := b
		b = c
		c = t
	var n := (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
	for v: Vector3 in [a, b, c]:
		_verts.append(v)
		_normals.append(n)
		_colors.append(Color(channel, 1.0, 1.0, 1.0))
		_uvs.append(Vector2(v.x, v.z) * 0.5 + Vector2(0.5, 0.5))


## Quad given in order around its perimeter.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, channel := CH_PRIMARY) -> void:
	add_tri(a, b, c, channel)
	add_tri(a, c, d, channel)


## A flat quad visible from both sides, for stripes and decals lying on a hull.
func add_decal_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, channel := CH_ACCENT) -> void:
	add_tri(a, b, c, channel)
	add_tri(a, c, d, channel)
	add_tri(a, c, b, channel)
	add_tri(a, d, c, channel)


func add_box(center: Vector3, size: Vector3, channel := CH_PRIMARY) -> void:
	var h := size * 0.5
	var p := []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				p.append(center + Vector3(h.x * sx, h.y * sy, h.z * sz))
	# index bits: x<<2 | y<<1 | z. These six quads are wound outward by hand, so
	# the orientation check only ever confirms them.
	begin_shape()
	add_quad(p[0], p[1], p[3], p[2], channel)  # -X
	add_quad(p[4], p[6], p[7], p[5], channel)  # +X
	add_quad(p[0], p[4], p[5], p[1], channel)  # -Y
	add_quad(p[2], p[3], p[7], p[6], channel)  # +Y
	add_quad(p[0], p[2], p[6], p[4], channel)  # -Z
	add_quad(p[1], p[5], p[7], p[3], channel)  # +Z
	end_shape()


## Connect two rings of equal length with quads (the walls of a loft).
##
## The winding here is fixed, never guessed. With a counter-clockwise profile and
## [param ring_b] ahead of [param ring_a] along the loft, every quad faces
## outward; run the loft the other way and they all come out inward *together*,
## which is the property [method end_shape] leans on to fix the sign with a single
## test instead of one per face.
func add_ring_wall(ring_a: PackedVector3Array, ring_b: PackedVector3Array, channel := CH_PRIMARY) -> void:
	var n := mini(ring_a.size(), ring_b.size())
	for i in n:
		var j := (i + 1) % n
		add_quad(ring_a[i], ring_a[j], ring_b[j], ring_b[i], channel)


## Fan-triangulate a ring into a flat cap. [param reverse] winds it the other
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
			add_tri(centroid, ring[i], ring[j], channel)


## Loft a series of rings into a hull. Rings must all have the same vertex count.
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
	return out


# --- Profiles ---------------------------------------------------------------
# Profiles are 2D outlines in the XY plane, extruded along Z. Ship forward is -Z,
# matching Godot camera convention, so noses point at -Z.

## Regular polygon. [param squash] flattens it vertically, which is how a round
## nacelle profile becomes a slab-sided hull without a second generator.
static func ngon(sides: int, radius: float, squash := 1.0, phase := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(sides, 3)
	for i in n:
		var a := TAU * (float(i) / float(n)) + phase
		out.append(Vector2(cos(a) * radius, sin(a) * radius * squash))
	return out


## Rectangle with chamfered corners. [param corner] is the cut size in metres.
static func chamfered_rect(width: float, height: float, corner := 0.0) -> PackedVector2Array:
	var hw := width * 0.5
	var hh := height * 0.5
	var c := clampf(corner, 0.0, minf(hw, hh) * 0.95)
	if c <= 0.0:
		return PackedVector2Array([
			Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)
		])
	return PackedVector2Array([
		Vector2(hw, -hh + c), Vector2(hw, hh - c), Vector2(hw - c, hh),
		Vector2(-hw + c, hh), Vector2(-hw, hh - c), Vector2(-hw, -hh + c),
		Vector2(-hw + c, -hh), Vector2(hw - c, -hh),
	])


## Flat-bottomed peaked outline, for canopies and fuselage tops.
static func wedge(width: float, height: float, shoulder := 0.35) -> PackedVector2Array:
	var hw := width * 0.5
	return PackedVector2Array([
		Vector2(hw, -height * 0.5),
		Vector2(hw * 0.82, -height * 0.5 + height * shoulder),
		Vector2(0.0, height * 0.5),
		Vector2(-hw * 0.82, -height * 0.5 + height * shoulder),
		Vector2(-hw, -height * 0.5),
	])


## Place a profile at a Z depth, scaled and offset. Returns a ring ready for
## [method add_loft].
static func ring(profile: PackedVector2Array, z: float, scale := Vector2.ONE, offset := Vector3.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in profile:
		out.append(Vector3(p.x * scale.x, p.y * scale.y, z) + offset)
	return out


# --- Output -----------------------------------------------------------------

func commit(name_hint := "") -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if name_hint != "":
		mesh.resource_name = name_hint
	return mesh


## Bounding box of everything built so far, used to size pick colliders and to
## frame the camera on a finished ship.
func bounds() -> AABB:
	if _verts.is_empty():
		return AABB()
	var box := AABB(_verts[0], Vector3.ZERO)
	for v in _verts:
		box = box.expand(v)
	return box


# --- Line meshes ------------------------------------------------------------
# Used for selection brackets, socket rings and the reference grid. Lines are
# cheap and read clearly at any zoom, which matters more than fidelity for
# builder affordances.

static func line_mesh(points: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


## Corner brackets rather than a full wireframe box: reads as a selection marker
## instead of competing with the ship silhouette.
static func selection_brackets(box: AABB, corner_ratio := 0.25) -> ArrayMesh:
	var pts := PackedVector3Array()
	var mn := box.position
	var mx := box.end
	var leg := box.size * clampf(corner_ratio, 0.05, 0.5)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var corner := Vector3(
					mn.x if ix == 0 else mx.x,
					mn.y if iy == 0 else mx.y,
					mn.z if iz == 0 else mx.z
				)
				var dir := Vector3(
					1.0 if ix == 0 else -1.0,
					1.0 if iy == 0 else -1.0,
					1.0 if iz == 0 else -1.0
				)
				pts.append(corner)
				pts.append(corner + Vector3(leg.x * dir.x, 0, 0))
				pts.append(corner)
				pts.append(corner + Vector3(0, leg.y * dir.y, 0))
				pts.append(corner)
				pts.append(corner + Vector3(0, 0, leg.z * dir.z))
	return line_mesh(pts)


## Flat ring of line segments, used for socket markers.
static func ring_lines(radius: float, segments := 16, axis := Vector3.FORWARD) -> ArrayMesh:
	var pts := PackedVector3Array()
	var basis := Basis()
	if axis.abs() != Vector3.UP.abs():
		basis = Basis.looking_at(axis, Vector3.UP)
	else:
		basis = Basis.looking_at(axis, Vector3.FORWARD)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		pts.append(basis * Vector3(cos(a0) * radius, sin(a0) * radius, 0.0))
		pts.append(basis * Vector3(cos(a1) * radius, sin(a1) * radius, 0.0))
	return line_mesh(pts)


## Three-axis cross, drawn with socket rings so an empty mount is visible even
## edge-on where a flat ring would vanish.
static func axis_cross(size: float) -> ArrayMesh:
	var pts := PackedVector3Array([
		Vector3(-size, 0, 0), Vector3(size, 0, 0),
		Vector3(0, -size, 0), Vector3(0, size, 0),
		Vector3(0, 0, -size), Vector3(0, 0, size),
	])
	return line_mesh(pts)


## Ground reference grid for the builder viewport.
static func grid_lines(half_extent: float, step: float) -> ArrayMesh:
	var pts := PackedVector3Array()
	var x := -half_extent
	while x <= half_extent + 0.001:
		pts.append(Vector3(x, 0, -half_extent))
		pts.append(Vector3(x, 0, half_extent))
		pts.append(Vector3(-half_extent, 0, x))
		pts.append(Vector3(half_extent, 0, x))
		x += step
	return line_mesh(pts)
