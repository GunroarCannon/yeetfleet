## Fits compound collision hulls to part bounds.
##
## [member PhysBody.hull] is a list of `{offset, radius}` spheres in the body's own
## space. Something has to decide what those spheres are, and it should not be the
## module that happens to own the geometry: ships and large craft have the same
## problem — "cover this box with spheres, along its long axis" — and both should
## get the same answer from the same place. It lives here, next to the member that
## consumes it, so [code]ship_builder[/code] and [code]large_craft_gen[/code] reach
## it through the physics façade rather than one of them publishing a geometry
## helper the other imports.
##
## See [method PhysBody.set_hull] for how the result is used.
class_name HullFit
extends RefCounted

## How many spheres one part may contribute. A long part is covered by a chain
## running down its length; the cap keeps a sprawling design from handing the
## solver hundreds of spheres to cross-test.
const MAX_SPHERES_PER_PART := 6

## Below this, a part is too thin to fit a chain into and gets one sphere. Also the
## floor on a sphere radius, so a zero-thickness or degenerate box cannot produce a
## sphere the solver divides by.
const MIN_CROSS := 0.05


## The spheres covering [param box], in the box's own space.
##
## A compact part is a single sphere at its centre; an elongated one is a chain
## along its longest axis.
##
## Centres run between ±(half-length − cross-section radius) so a sphere never
## pokes past the part it stands for, and each sphere is at least half the gap to
## the next so the chain cannot come apart — which is what lets the count be capped
## without leaving a hole in the middle of a long hull.
static func spheres_for_box(box: AABB) -> Array[Dictionary]:
	var hull: Array[Dictionary] = []
	append_box_spheres(box, hull)
	return hull


## [method spheres_for_box] appending into an existing list.
##
## Separate so a caller covering many boxes — every part of a ship, every part of a
## mothership — can accumulate into one array instead of allocating and
## concatenating one per part.
static func append_box_spheres(box: AABB, hull: Array[Dictionary]) -> void:
	var size := box.size
	var center := box.get_center()
	var axis := Vector3.RIGHT
	var half_major := size.x * 0.5
	# The sphere enclosing the part's cross-section: how far the box reaches off
	# its own long axis.
	var cross := 0.0
	if size.y >= size.x and size.y >= size.z:
		axis = Vector3.UP
		half_major = size.y * 0.5
		cross = 0.5 * Vector2(size.x, size.z).length()
	elif size.z >= size.x and size.z >= size.y:
		axis = Vector3.BACK
		half_major = size.z * 0.5
		cross = 0.5 * Vector2(size.x, size.y).length()
	else:
		cross = 0.5 * Vector2(size.y, size.z).length()
	cross = maxf(cross, MIN_CROSS)
	var span := half_major - cross
	if span <= cross * 0.5:
		hull.append({"offset": center, "radius": maxf(half_major, cross)})
		return
	var count := clampi(int(ceil(span / cross)) + 1, 2, MAX_SPHERES_PER_PART)
	var step := span * 2.0 / float(count - 1)
	var radius := maxf(cross, step * 0.5)
	for i in count:
		hull.append({"offset": center + axis * (-span + step * float(i)), "radius": radius})


## The single sphere that encloses [param box], as a one-entry hull.
##
## The honest fallback for a part with no usable bounds — better a fat sphere than
## a hole in the collision, and [method PhysBody.set_hull] derives the enclosing
## radius from whatever it is given.
static func enclosing_sphere(box: AABB) -> Array[Dictionary]:
	return [{"offset": box.get_center(), "radius": maxf(box.size.length() * 0.5, MIN_CROSS)}]
