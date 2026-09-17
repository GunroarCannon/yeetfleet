## Turns a part mesh recipe into geometry.
##
## Parts ship no art. Each part carries a `mesh` dictionary naming a generator and
## its parameters, and this factory builds the mesh at load time. That keeps the
## repo tiny, makes new parts a data edit rather than a modelling job, and means
## every part automatically obeys the shared colour-channel convention.
##
## Generators also report named markers (muzzles, exhaust nozzles, cockpit eye
## points) so the systems simulation can attach real behaviour to real geometry
## without a hand-placed node per part.
class_name PartMeshFactory
extends RefCounted

## Result of building one part.
class Built extends RefCounted:
	var mesh: ArrayMesh
	var aabb := AABB()
	## marker name -> Array[Transform3D] in part-local space.
	var markers: Dictionary = {}

	func marker_list(key: String) -> Array:
		return markers.get(key, [])


## Keyed "part_id|mirror|style". Meshes are immutable once built and shared
## between every instance of that part, so a fifty-part ship still holds a handful
## of meshes.
##
## The style token is part of the key rather than a reason to throw the cache away.
## The geometry dials (roundness, chunkiness, rock_potato) change the mesh a part
## resolves to, so a look switch has to hand back different geometry — but keying
## on the look means switching to cartoony and back to grounded are both cache
## hits after the first time, instead of rebuilding every hull on every flip. The
## cost is one mesh per part per look actually used, which is nothing next to
## regenerating the geometry each switch.
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


## The current geometry look, for the cache key.
##
## Only dials that change mesh *topology* belong here. A shading dial — bands,
## outline width, specular — is a uniform on a material and has no business
## invalidating geometry, so it deliberately earns no token: dragging the toon
## ramp slider must not rebuild a single hull.
static func style_token() -> String:
	var style := StyleManager.instance().current_profile
	if style == null:
		return "default"
	return "%.3f_%.3f_%.3f" % [style.roundness, style.chunkiness, style.rock_potato]


static func build(part: ShipPart, mirrored := false) -> Built:
	var key := "%s|%d|%s" % [part.id, 1 if mirrored else 0, style_token()]
	if _cache.has(key):
		return _cache[key]
	var built := _generate(part, mirrored)
	_cache[key] = built
	return built


static func _generate(part: ShipPart, mirrored: bool) -> Built:
	var lp := LowPoly.new()
	lp.mirror = mirrored
	var spec := part.mesh_spec
	var kind := String(spec.get("kind", "box"))
	var markers := {}
	match kind:
		"hull_spine": markers = _hull_spine(lp, spec)
		"segment": markers = _segment(lp, spec)
		"canopy": markers = _canopy(lp, spec)
		"nacelle": markers = _nacelle(lp, spec)
		"wing": markers = _wing(lp, spec)
		"pod": markers = _pod(lp, spec)
		"gun": markers = _gun(lp, spec)
		"plate": markers = _plate(lp, spec)
		"greeble": markers = _greeble(lp, spec)
		_: markers = _box(lp, spec)

	var built := Built.new()
	var mesh := lp.commit(part.id)
	var style := StyleManager.instance().current_profile
	if style and (style.roundness > 0.0 or style.chunkiness > 0.0):
		var rounding := MeshRounding.new()
		rounding.roundness = style.roundness
		rounding.chunkiness = style.chunkiness
		mesh = rounding.apply(mesh) as ArrayMesh
	built.mesh = mesh
	# Chunkiness moves vertices, so the cached AABB is read back off the final
	# mesh rather than off [LowPoly]'s pre-rounding bounds.
	built.aabb = mesh.get_aabb()
	built.markers = _mirror_markers(markers, mirrored)
	return built


## Mirrored meshes need mirrored markers, or the right-hand gun fires from the
## left-hand barrel.
static func _mirror_markers(markers: Dictionary, mirrored: bool) -> Dictionary:
	if not mirrored:
		return markers
	var out := {}
	for key: Variant in markers:
		var list := []
		for t: Transform3D in markers[key]:
			list.append(ShipDesign.reflect_x(t))
		out[key] = list
	return out


# --- Parameter helpers ------------------------------------------------------

static func _f(spec: Dictionary, key: String, default: float) -> float:
	return float(spec.get(key, default))


static func _i(spec: Dictionary, key: String, default: int) -> int:
	return int(spec.get(key, default))


static func _s(spec: Dictionary, key: String, default: String) -> String:
	return String(spec.get(key, default))


static func _v3(spec: Dictionary, key: String, default: Vector3) -> Vector3:
	if not spec.has(key):
		return default
	var a: Variant = spec[key]
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return default


## Marker pointing along a direction, used for exhaust and muzzle transforms.
static func _marker(origin: Vector3, forward: Vector3) -> Transform3D:
	var f := forward.normalized() if forward.length_squared() > 0.0 else Vector3.FORWARD
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(f, up), origin)


# --- Generators -------------------------------------------------------------
# Convention: forward is -Z, up is +Y, and a part's origin is its mount point.
# Wings and other sided parts are built extending toward -X (the left side); the
# right-hand copy comes from socket mirroring.

## Tapered fuselage. The backbone of fighter and freighter chassis.
static func _hull_spine(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 6.0)
	var width := _f(spec, "width", 1.6)
	var height := _f(spec, "height", 1.1)
	var corner := _f(spec, "corner", 0.28)
	var nose := _f(spec, "nose", 0.30)
	var tail := _f(spec, "tail", 0.72)
	var profile := LowPoly.chamfered_rect(width, height, corner)

	# (z as a fraction of length, uniform scale) from tail to nose.
	var sections := [
		Vector2(0.50, tail),
		Vector2(0.30, 1.0),
		Vector2(-0.05, 0.97),
		Vector2(-0.30, 0.70),
		Vector2(-0.50, nose),
	]
	var rings := []
	for s in sections:
		rings.append(LowPoly.ring(profile, length * s.x, Vector2(s.y, s.y)))
	lp.add_loft(rings, LowPoly.CH_PRIMARY)

	# Dorsal accent stripe, following the taper so it sits flush.
	_hull_stripe(lp, sections, length, width, height, _f(spec, "stripe", 0.34))

	# Recessed engine deck at the tail reads as an exhaust plenum.
	var tail_h := height * tail
	lp.add_box(
		Vector3(0.0, 0.0, length * 0.5 - 0.06),
		Vector3(width * tail * 0.78, tail_h * 0.78, 0.12),
		LowPoly.CH_TRIM
	)
	# Belly sensor blister.
	if _f(spec, "belly", 1.0) > 0.5:
		lp.add_box(
			Vector3(0.0, -height * 0.52, length * -0.02),
			Vector3(width * 0.42, height * 0.16, length * 0.34),
			LowPoly.CH_TRIM
		)
	# Panel greebles along the spine, at fixed positions so the mesh stays cached.
	for i in 3:
		var z := length * (0.18 - 0.19 * float(i))
		lp.add_box(
			Vector3(width * 0.30, height * 0.30, z),
			Vector3(width * 0.10, height * 0.08, length * 0.06),
			LowPoly.CH_TRIM
		)
		lp.add_box(
			Vector3(-width * 0.30, height * 0.30, z),
			Vector3(width * 0.10, height * 0.08, length * 0.06),
			LowPoly.CH_TRIM
		)
	return {}


## Accent band laid over a lofted hull, following its taper.
static func _hull_stripe(
	lp: LowPoly, sections: Array, length: float, width: float, height: float, ratio: float
) -> void:
	if ratio <= 0.0:
		return
	lp.begin_shape()
	for i in sections.size() - 1:
		var a: Vector2 = sections[i]
		var b: Vector2 = sections[i + 1]
		var z0 := length * a.x
		var z1 := length * b.x
		var y0 := height * 0.5 * a.y + 0.012
		var y1 := height * 0.5 * b.y + 0.012
		var x0 := width * 0.5 * a.y * ratio
		var x1 := width * 0.5 * b.y * ratio
		lp.add_decal_quad(
			Vector3(-x0, y0, z0), Vector3(x0, y0, z0),
			Vector3(x1, y1, z1), Vector3(-x1, y1, z1),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)


## Repeatable capital-ship hull block. Chaining these through their fore/aft
## sockets is how multi-segment capitals are assembled from one part.
static func _segment(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 3.0)
	var width := _f(spec, "width", 2.4)
	var height := _f(spec, "height", 1.8)
	var corner := _f(spec, "corner", 0.4)
	var taper := _f(spec, "taper", 1.0)
	var profile := LowPoly.chamfered_rect(width, height, corner)
	lp.add_loft([
		LowPoly.ring(profile, length * 0.5, Vector2.ONE),
		LowPoly.ring(profile, length * 0.16, Vector2.ONE),
		LowPoly.ring(profile, -length * 0.16, Vector2(taper, taper)),
		LowPoly.ring(profile, -length * 0.5, Vector2(taper, taper)),
	], LowPoly.CH_PRIMARY)

	# Structural ribs: thin oversized bands that break up the slab silhouette.
	var ribs := _i(spec, "ribs", 2)
	for i in ribs:
		var t := (float(i) + 1.0) / (float(ribs) + 1.0)
		var z := lerpf(length * 0.5, -length * 0.5, t)
		var s := lerpf(1.0, taper, t) * 1.05
		lp.add_loft([
			LowPoly.ring(profile, z + length * 0.035, Vector2(s, s)),
			LowPoly.ring(profile, z - length * 0.035, Vector2(s, s)),
		], LowPoly.CH_TRIM, false, false)
	# Side accent panels.
	lp.begin_shape()
	for sx: float in [-1.0, 1.0]:
		lp.add_decal_quad(
			Vector3(sx * (width * 0.5 + 0.01), height * 0.18, length * 0.42),
			Vector3(sx * (width * 0.5 + 0.01), height * 0.18, -length * 0.42),
			Vector3(sx * (width * 0.5 + 0.01), -height * 0.10, -length * 0.42),
			Vector3(sx * (width * 0.5 + 0.01), -height * 0.10, length * 0.42),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)
	return {}


## Ring of points in the XZ plane, for domes and other Y-stacked lofts.
static func _ring_xz(y: float, rx: float, rz: float, sides: int, z_off := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(sides, 3)
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector3(cos(a) * rx, y, sin(a) * rz + z_off))
	return out


## Cockpit / bridge. Markers include the pilot eye point, which the flight module
## can use as a cockpit camera anchor without any extra authoring.
static func _canopy(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 1.4)
	var width := _f(spec, "width", 1.0)
	var height := _f(spec, "height", 0.7)
	var sides := _i(spec, "sides", 8)
	var style := _s(spec, "style", "bubble")

	match style:
		"wedge":
			var profile := LowPoly.wedge(width, height, 0.4)
			var off := Vector3(0.0, height * 0.5, 0.0)
			lp.add_loft([
				LowPoly.ring(profile, length * 0.5, Vector2.ONE, off),
				LowPoly.ring(profile, -length * 0.12, Vector2(0.94, 0.94), off),
				LowPoly.ring(profile, -length * 0.5, Vector2(0.52, 0.62), off),
			], LowPoly.CH_PRIMARY)
			# Forward-facing viewport.
			lp.begin_shape()
			lp.add_decal_quad(
				Vector3(-width * 0.30, height * 0.30, -length * 0.30),
				Vector3(width * 0.30, height * 0.30, -length * 0.30),
				Vector3(width * 0.22, height * 0.74, -length * 0.02),
				Vector3(-width * 0.22, height * 0.74, -length * 0.02),
				LowPoly.CH_ACCENT
			)
			lp.end_shape(false)
		"nose":
			var profile := LowPoly.ngon(sides, width * 0.5, 0.8)
			lp.add_loft([
				LowPoly.ring(profile, length * 0.5, Vector2.ONE, Vector3(0, height * 0.3, 0)),
				LowPoly.ring(profile, -length * 0.1, Vector2(0.8, 0.8), Vector3(0, height * 0.3, 0)),
				LowPoly.ring(profile, -length * 0.5, Vector2(0.14, 0.14), Vector3(0, height * 0.3, 0)),
			], LowPoly.CH_PRIMARY)
			# Sensor bands.
			for i in 2:
				var z := -length * (0.12 + 0.16 * float(i))
				var s := lerpf(0.8, 0.4, float(i) / 2.0) * 1.08
				lp.add_loft([
					LowPoly.ring(profile, z + 0.03, Vector2(s, s), Vector3(0, height * 0.3, 0)),
					LowPoly.ring(profile, z - 0.03, Vector2(s, s), Vector3(0, height * 0.3, 0)),
				], LowPoly.CH_ACCENT, false, false)
		_:
			# Bubble dome: rings stacked in Y on a hemispherical falloff.
			var steps := 4
			var rings := []
			for i in steps + 1:
				var t := float(i) / float(steps) * 0.94
				var r := cos(t * PI * 0.5)
				rings.append(_ring_xz(height * sin(t * PI * 0.5), width * 0.5 * r, length * 0.5 * r, sides))
			lp.add_loft(rings, LowPoly.CH_PRIMARY, true, true)
			# Canopy frame band.
			var frame := _ring_xz(height * 0.30, width * 0.5 * 0.96, length * 0.5 * 0.96, sides)
			var frame2 := _ring_xz(height * 0.38, width * 0.5 * 0.93, length * 0.5 * 0.93, sides)
			lp.add_loft([frame, frame2], LowPoly.CH_TRIM, false, false)
			# Forward visor.
			lp.begin_shape()
			lp.add_decal_quad(
				Vector3(-width * 0.26, height * 0.20, -length * 0.42),
				Vector3(width * 0.26, height * 0.20, -length * 0.42),
				Vector3(width * 0.20, height * 0.66, -length * 0.20),
				Vector3(-width * 0.20, height * 0.66, -length * 0.20),
				LowPoly.CH_ACCENT
			)
			lp.end_shape(false)

	return {"eye": [_marker(Vector3(0.0, height * 0.52, -length * 0.08), Vector3.FORWARD)]}


## Engine pod. Body runs from the mount at z=0 rearward to +z, so exhaust exits
## behind the ship regardless of which socket it lands in.
static func _nacelle(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 2.2)
	var radius := _f(spec, "radius", 0.42)
	var sides := _i(spec, "sides", 8)
	var intake := _f(spec, "intake", 0.86)
	var nozzle := _f(spec, "nozzle", 1.08)
	var profile := LowPoly.ngon(sides, radius, _f(spec, "squash", 1.0))

	lp.add_loft([
		LowPoly.ring(profile, 0.0, Vector2(intake, intake)),
		LowPoly.ring(profile, length * 0.12, Vector2.ONE),
		LowPoly.ring(profile, length * 0.66, Vector2.ONE),
		LowPoly.ring(profile, length * 0.83, Vector2(0.76, 0.76)),
		LowPoly.ring(profile, length, Vector2(nozzle, nozzle)),
	], LowPoly.CH_PRIMARY)

	# Intake lip and hot-section band.
	lp.add_loft([
		LowPoly.ring(profile, length * 0.02, Vector2(intake * 1.10, intake * 1.10)),
		LowPoly.ring(profile, length * 0.10, Vector2(intake * 1.10, intake * 1.10)),
	], LowPoly.CH_TRIM, false, false)
	lp.add_loft([
		LowPoly.ring(profile, length * 0.86, Vector2(0.80, 0.80)),
		LowPoly.ring(profile, length * 0.95, Vector2(nozzle * 0.94, nozzle * 0.94)),
	], LowPoly.CH_ACCENT, false, false)
	# Recessed nozzle throat.
	lp.add_loft([
		LowPoly.ring(profile, length * 0.985, Vector2(nozzle * 0.72, nozzle * 0.72)),
		LowPoly.ring(profile, length * 0.90, Vector2(nozzle * 0.55, nozzle * 0.55)),
	], LowPoly.CH_TRIM, false, true)

	# Cooling fins, drawn as flat double-sided blades: cheap and readable.
	var fins := _i(spec, "fins", 3)
	if fins > 0:
		lp.begin_shape()
		for i in fins:
			var a := TAU * float(i) / float(fins) + PI * 0.5
			var dir := Vector3(cos(a), sin(a), 0.0)
			var inner := dir * radius * 0.92
			var outer := dir * radius * (1.0 + _f(spec, "fin_size", 0.55))
			lp.add_decal_quad(
				inner + Vector3(0, 0, length * 0.24),
				outer + Vector3(0, 0, length * 0.34),
				outer + Vector3(0, 0, length * 0.62),
				inner + Vector3(0, 0, length * 0.70),
				LowPoly.CH_TRIM
			)
		lp.end_shape(false)

	# Marker -Z axis points the way the plume travels.
	return {
		"exhaust": [_marker(Vector3(0.0, 0.0, length * 1.01), Vector3.BACK)],
		"exhaust_radius": [Transform3D(Basis().scaled(Vector3.ONE * radius * nozzle), Vector3.ZERO)],
	}


## Airfoil cross-section perpendicular to the span axis (X).
static func _airfoil_ring(x: float, chord: float, thickness: float, z_center: float, y_center: float) -> PackedVector3Array:
	var pts := [
		Vector2(-0.50, 0.00), Vector2(-0.26, 0.50), Vector2(0.16, 0.40),
		Vector2(0.50, 0.04), Vector2(0.16, -0.34), Vector2(-0.26, -0.44),
	]
	var out := PackedVector3Array()
	for p: Vector2 in pts:
		out.append(Vector3(x, y_center + p.y * thickness, z_center + p.x * chord))
	return out


## Wing or fin, built extending toward -X. Sweep, dihedral and taper are all
## parameters, so one generator covers stub wings, swept fins and long gliders.
static func _wing(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var span := _f(spec, "span", 2.6)
	var root_chord := _f(spec, "root_chord", 1.6)
	var tip_chord := _f(spec, "tip_chord", 0.7)
	var sweep := _f(spec, "sweep", 0.9)
	var thickness := _f(spec, "thickness", 0.18)
	var dihedral := _f(spec, "dihedral", 0.1)
	var winglet := _f(spec, "winglet", 0.0)

	var mid := 0.55
	var mid_chord := lerpf(root_chord, tip_chord, mid * 0.8)
	lp.add_loft([
		_airfoil_ring(0.0, root_chord, thickness, 0.0, 0.0),
		_airfoil_ring(-span * mid, mid_chord, thickness * 0.85, sweep * mid, dihedral * mid),
		_airfoil_ring(-span, tip_chord, thickness * 0.6, sweep, dihedral),
	], LowPoly.CH_PRIMARY)

	# Upper-surface accent flash.
	lp.begin_shape()
	lp.add_decal_quad(
		Vector3(-span * 0.08, thickness * 0.28, -root_chord * 0.10),
		Vector3(-span * 0.08, thickness * 0.28, root_chord * 0.22),
		Vector3(-span * 0.92, dihedral * 0.92 + thickness * 0.20, sweep * 0.92 + tip_chord * 0.16),
		Vector3(-span * 0.92, dihedral * 0.92 + thickness * 0.20, sweep * 0.92 - tip_chord * 0.20),
		LowPoly.CH_ACCENT
	)
	lp.end_shape(false)

	if winglet > 0.001:
		lp.begin_shape()
		lp.add_decal_quad(
			Vector3(-span, dihedral, sweep - tip_chord * 0.42),
			Vector3(-span, dihedral, sweep + tip_chord * 0.34),
			Vector3(-span, dihedral + winglet, sweep + tip_chord * 0.10),
			Vector3(-span, dihedral + winglet, sweep - tip_chord * 0.28),
			LowPoly.CH_TRIM
		)
		lp.end_shape(false)
	return {}


## Cargo canister / utility pod, centred on its mount so it reads as slung
## alongside the hull rather than growing out of it.
static func _pod(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 2.0)
	var radius := _f(spec, "radius", 0.55)
	var sides := _i(spec, "sides", 6)
	var caps := _f(spec, "caps", 0.58)
	var profile := LowPoly.ngon(sides, radius, _f(spec, "squash", 1.0), PI / float(maxi(sides, 3)))

	lp.add_loft([
		LowPoly.ring(profile, -length * 0.5, Vector2(caps, caps)),
		LowPoly.ring(profile, -length * 0.40, Vector2.ONE),
		LowPoly.ring(profile, length * 0.40, Vector2.ONE),
		LowPoly.ring(profile, length * 0.5, Vector2(caps, caps)),
	], LowPoly.CH_PRIMARY)

	# Binding ribs.
	var ribs := _i(spec, "ribs", 2)
	for i in ribs:
		var t := (float(i) + 1.0) / (float(ribs) + 1.0)
		var z := lerpf(-length * 0.36, length * 0.36, t)
		lp.add_loft([
			LowPoly.ring(profile, z - length * 0.03, Vector2(1.07, 1.07)),
			LowPoly.ring(profile, z + length * 0.03, Vector2(1.07, 1.07)),
		], LowPoly.CH_TRIM, false, false)
	# Cap rings in accent so pods read as containers at a glance.
	for sz: float in [-1.0, 1.0]:
		lp.add_loft([
			LowPoly.ring(profile, sz * length * 0.44, Vector2(1.02, 1.02)),
			LowPoly.ring(profile, sz * length * 0.49, Vector2(caps * 1.02, caps * 1.02)),
		], LowPoly.CH_ACCENT, false, false)
	# Dorsal hatch.
	lp.begin_shape()
	lp.add_decal_quad(
		Vector3(-radius * 0.34, radius * 1.01, -length * 0.16),
		Vector3(radius * 0.34, radius * 1.01, -length * 0.16),
		Vector3(radius * 0.34, radius * 1.01, length * 0.16),
		Vector3(-radius * 0.34, radius * 1.01, length * 0.16),
		LowPoly.CH_TRIM
	)
	lp.end_shape(false)
	return {"hatch": [_marker(Vector3(0.0, radius, 0.0), Vector3.UP)]}


## Weapon. Reports one muzzle marker per barrel/tube, which is what the systems
## test fires projectiles from — so a twin cannon really does fire twice.
static func _gun(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 1.2)
	var caliber := _f(spec, "caliber", 0.11)
	var housing := _v3(spec, "housing", Vector3(0.42, 0.32, 0.5))
	var count := maxi(_i(spec, "barrels", 1), 1)
	var style := _s(spec, "style", "barrel")
	var muzzles := []

	lp.add_box(Vector3(0.0, 0.0, -housing.z * 0.5), housing, LowPoly.CH_PRIMARY)
	# Mount collar.
	lp.add_box(Vector3(0.0, 0.0, -0.03), Vector3(housing.x * 1.12, housing.y * 1.12, 0.09), LowPoly.CH_TRIM)

	match style:
		"rack":
			# Missile rack: a cradle of tubes rather than barrels.
			var rows := maxi(_i(spec, "rows", 2), 1)
			var per_row := maxi(count / rows, 1)
			for r in rows:
				for c in per_row:
					var x := (float(c) - float(per_row - 1) * 0.5) * caliber * 2.8
					var y := (float(r) - float(rows - 1) * 0.5) * caliber * 2.8
					var tube := LowPoly.ngon(6, caliber, 1.0)
					lp.add_loft([
						LowPoly.ring(tube, -housing.z, Vector2.ONE, Vector3(x, y, 0)),
						LowPoly.ring(tube, -length, Vector2(0.92, 0.92), Vector3(x, y, 0)),
					], LowPoly.CH_TRIM, false, false)
					# Missile nose peeking out of the tube.
					lp.add_loft([
						LowPoly.ring(tube, -length + 0.02, Vector2(0.8, 0.8), Vector3(x, y, 0)),
						LowPoly.ring(tube, -length - caliber * 1.6, Vector2(0.12, 0.12), Vector3(x, y, 0)),
					], LowPoly.CH_ACCENT, false, true)
					muzzles.append(_marker(Vector3(x, y, -length - caliber * 1.7), Vector3.FORWARD))
		"beam":
			# Mining/beam emitter: fat barrel, emitter crystal at the tip.
			var barrel := LowPoly.ngon(8, caliber * 1.6, 1.0)
			lp.add_loft([
				LowPoly.ring(barrel, -housing.z * 0.6, Vector2.ONE),
				LowPoly.ring(barrel, -length * 0.85, Vector2(0.86, 0.86)),
				LowPoly.ring(barrel, -length, Vector2(1.15, 1.15)),
			], LowPoly.CH_PRIMARY)
			lp.add_loft([
				LowPoly.ring(barrel, -length * 0.98, Vector2(0.95, 0.95)),
				LowPoly.ring(barrel, -length * 0.88, Vector2(0.62, 0.62)),
			], LowPoly.CH_ACCENT, false, true)
			muzzles.append(_marker(Vector3(0.0, 0.0, -length - 0.02), Vector3.FORWARD))
		_:
			for i in count:
				var x := (float(i) - float(count - 1) * 0.5) * caliber * 3.0
				var barrel := LowPoly.ngon(6, caliber, 1.0)
				lp.add_loft([
					LowPoly.ring(barrel, -housing.z * 0.7, Vector2(1.35, 1.35), Vector3(x, 0, 0)),
					LowPoly.ring(barrel, -length * 0.78, Vector2.ONE, Vector3(x, 0, 0)),
					LowPoly.ring(barrel, -length, Vector2(1.18, 1.18), Vector3(x, 0, 0)),
				], LowPoly.CH_PRIMARY)
				# Muzzle band.
				lp.add_loft([
					LowPoly.ring(barrel, -length * 0.93, Vector2(1.24, 1.24), Vector3(x, 0, 0)),
					LowPoly.ring(barrel, -length * 0.86, Vector2(1.24, 1.24), Vector3(x, 0, 0)),
				], LowPoly.CH_ACCENT, false, false)
				muzzles.append(_marker(Vector3(x, 0.0, -length - 0.02), Vector3.FORWARD))

	return {"muzzle": muzzles}


## Armour plate. The socket normal is -Z, so thickness runs along Z and the plate
## lies flush against whatever it is bolted to.
static func _plate(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var w := _f(spec, "w", 1.2)
	var h := _f(spec, "h", 0.8)
	var t := _f(spec, "t", 0.14)
	var bevel := _f(spec, "bevel", 0.14)
	var profile := LowPoly.chamfered_rect(w, h, bevel)
	lp.add_loft([
		LowPoly.ring(profile, 0.0, Vector2(0.90, 0.90)),
		LowPoly.ring(profile, -t * 0.30, Vector2.ONE),
		LowPoly.ring(profile, -t * 0.80, Vector2.ONE),
		LowPoly.ring(profile, -t, Vector2(0.88, 0.88)),
	], LowPoly.CH_PRIMARY)

	# Diagonal accent flash plus corner rivets.
	lp.begin_shape()
	lp.add_decal_quad(
		Vector3(-w * 0.44, -h * 0.10, -t - 0.008),
		Vector3(-w * 0.20, -h * 0.42, -t - 0.008),
		Vector3(w * 0.44, h * 0.10, -t - 0.008),
		Vector3(w * 0.20, h * 0.42, -t - 0.008),
		LowPoly.CH_ACCENT
	)
	lp.end_shape(false)
	if _f(spec, "rivets", 1.0) > 0.5:
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				lp.add_box(
					Vector3(sx * w * 0.38, sy * h * 0.34, -t - 0.01),
					Vector3(w * 0.07, w * 0.07, t * 0.35),
					LowPoly.CH_TRIM
				)
	return {}


## Cosmetic detail. Cheap silhouette-breakers with no stat cost, so players can
## dress a hull without paying for it.
static func _greeble(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var size := _f(spec, "size", 0.4)
	var style := _s(spec, "style", "antenna")
	match style:
		"dish":
			var profile := LowPoly.ngon(10, size, 1.0)
			lp.add_loft([
				LowPoly.ring(profile, -size * 0.75, Vector2.ONE),
				LowPoly.ring(profile, -size * 0.30, Vector2(0.52, 0.52)),
				LowPoly.ring(profile, -size * 0.10, Vector2(0.16, 0.16)),
			], LowPoly.CH_TRIM, false, true)
			lp.add_box(Vector3(0, 0, -size * 0.05), Vector3(size * 0.12, size * 0.12, size * 0.3), LowPoly.CH_ACCENT)
		"vent":
			lp.add_box(Vector3(0, 0, -size * 0.22), Vector3(size * 1.5, size * 0.9, size * 0.44), LowPoly.CH_PRIMARY)
			for i in 3:
				var y := (float(i) - 1.0) * size * 0.26
				lp.add_box(
					Vector3(0, y, -size * 0.46),
					Vector3(size * 1.24, size * 0.12, size * 0.06),
					LowPoly.CH_TRIM
				)
		"fin":
			# A real thin solid rather than a single plane. A plane has no volume, so
			# it gives the pick box nothing to work with and vanishes when viewed from
			# its back face.
			var half := maxf(size * 0.05, 0.012)
			var root_fwd := size * 0.3
			var root_aft := -size * 0.7
			var tip_fwd := size * 0.15
			var tip_aft := -size * 0.35
			var tip_y := size * 1.1
			var root_tip_y := size * 0.95
			for side: float in [-1.0, 1.0]:
				var x := half * side
				# Wind each face outward so both read as front-facing.
				if side < 0.0:
					lp.add_quad(
						Vector3(x, 0.0, root_fwd), Vector3(x, 0.0, root_aft),
						Vector3(x, tip_y, tip_aft), Vector3(x, root_tip_y, tip_fwd),
						LowPoly.CH_TRIM
					)
				else:
					lp.add_quad(
						Vector3(x, root_tip_y, tip_fwd), Vector3(x, tip_y, tip_aft),
						Vector3(x, 0.0, root_aft), Vector3(x, 0.0, root_fwd),
						LowPoly.CH_TRIM
					)
			# Leading edge, trailing edge and the swept top, in the accent channel so
			# a fin reads as a panel with a bright edge.
			lp.add_quad(
				Vector3(-half, 0.0, root_fwd), Vector3(half, 0.0, root_fwd),
				Vector3(half, root_tip_y, tip_fwd), Vector3(-half, root_tip_y, tip_fwd),
				LowPoly.CH_ACCENT
			)
			lp.add_quad(
				Vector3(half, 0.0, root_aft), Vector3(-half, 0.0, root_aft),
				Vector3(-half, tip_y, tip_aft), Vector3(half, tip_y, tip_aft),
				LowPoly.CH_ACCENT
			)
			lp.add_quad(
				Vector3(-half, root_tip_y, tip_fwd), Vector3(half, root_tip_y, tip_fwd),
				Vector3(half, tip_y, tip_aft), Vector3(-half, tip_y, tip_aft),
				LowPoly.CH_ACCENT
			)
		"light":
			lp.add_box(Vector3(0, 0, -size * 0.12), Vector3(size * 0.5, size * 0.3, size * 0.24), LowPoly.CH_TRIM)
			lp.add_box(Vector3(0, 0, -size * 0.26), Vector3(size * 0.34, size * 0.18, size * 0.06), LowPoly.CH_ACCENT)
		_:
			# Antenna: tapered mast with a tip bead.
			var mast := LowPoly.ngon(4, size * 0.10, 1.0)
			lp.add_loft([
				LowPoly.ring(mast, 0.0, Vector2(1.4, 1.4)),
				LowPoly.ring(mast, -size * 2.2, Vector2(0.35, 0.35)),
			], LowPoly.CH_TRIM)
			var bead := LowPoly.ngon(6, size * 0.14, 1.0)
			lp.add_loft([
				LowPoly.ring(bead, -size * 2.05, Vector2(0.5, 0.5)),
				LowPoly.ring(bead, -size * 2.30, Vector2.ONE),
				LowPoly.ring(bead, -size * 2.55, Vector2(0.5, 0.5)),
			], LowPoly.CH_ACCENT)
	return {}


static func _box(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var size := _v3(spec, "size", Vector3.ONE)
	lp.add_box(Vector3(0, 0, -size.z * 0.5), size, LowPoly.CH_PRIMARY)
	return {}
