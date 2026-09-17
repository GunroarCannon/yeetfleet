## Turns a large-craft part spec into geometry, the same division of labour as
## [code]ship_builder/scripts/build/PartMeshFactory[/code]: parts ship no art,
## just a `kind` + parameter dictionary, built at generate time with the
## shared [LowPoly] toolkit. Kept as this module's own generator set rather
## than reusing [PartMeshFactory] directly, since that one is tied to
## [ShipPart]/[ShipDesign] (sockets, channel-colour resources) which belong to
## ship_builder's player-facing part economy, not a procedural structure.
##
## Convention matches [PartMeshFactory]: forward is -Z, up is +Y, a part's
## origin is its mount point.
class_name LargeCraftPartFactory
extends RefCounted

## Result of building one part.
class Built extends RefCounted:
	var mesh: ArrayMesh
	var aabb := AABB()
	## marker name -> Array[Transform3D] in part-local space (e.g. "dock" on a
	## [code]dock_ramp[/code], the point and outward-facing normal a
	## [DockingPad] should sit at).
	var markers: Dictionary = {}


static func build(kind: String, spec: Dictionary) -> Built:
	var lp := LowPoly.new()
	var markers := {}
	match kind:
		"hull_segment": markers = _hull_segment(lp, spec)
		"dock_ramp": markers = _dock_ramp(lp, spec)
		"spire": markers = _spire(lp, spec)
		"strut": markers = _strut(lp, spec)
		"ring_segment": markers = _ring_segment(lp, spec)
		"dome": markers = _dome(lp, spec)
		"greeble_panel": markers = _greeble_panel(lp, spec)
		"greeble_vent": markers = _greeble_vent(lp, spec)
		"greeble_antenna": markers = _greeble_antenna(lp, spec)
		"greeble_dish": markers = _greeble_dish(lp, spec)
		"turret": markers = _turret(lp, spec)
		"wing": markers = _wing(lp, spec)
		"tail_fin": markers = _tail_fin(lp, spec)
		_: markers = _greeble_block(lp, spec)

	var built := Built.new()
	var mesh := lp.commit(kind)
	var style := StyleManager.instance().current_profile
	if style and (style.roundness > 0.0 or style.chunkiness > 0.0):
		var rounding := MeshRounding.new()
		rounding.roundness = style.roundness
		rounding.chunkiness = style.chunkiness
		mesh = rounding.apply(mesh) as ArrayMesh
	built.mesh = mesh
	built.aabb = mesh.get_aabb()
	built.markers = markers
	return built


static func _f(spec: Dictionary, key: String, default: float) -> float:
	return float(spec.get(key, default))


static func _i(spec: Dictionary, key: String, default: int) -> int:
	return int(spec.get(key, default))


static func _marker(origin: Vector3, forward: Vector3) -> Transform3D:
	var f := forward.normalized() if forward.length_squared() > 0.0 else Vector3.FORWARD
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(f, up), origin)


# --- Generators --------------------------------------------------------------

## Repeatable capital-hull block, chained along Z to build the mothership's
## spine — one call per segment, tapering handled by the caller scaling
## successive segments' `width`/`height`.
static func _hull_segment(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 6.0)
	var width := _f(spec, "width", 5.0)
	var height := _f(spec, "height", 4.0)
	var corner := _f(spec, "corner", 0.6)
	var taper := _f(spec, "taper", 0.92)
	var profile := LowPoly.chamfered_rect(width, height, corner)
	lp.add_loft([
		LowPoly.ring(profile, length * 0.5, Vector2.ONE),
		LowPoly.ring(profile, length * 0.1, Vector2.ONE),
		LowPoly.ring(profile, -length * 0.1, Vector2(taper, taper)),
		LowPoly.ring(profile, -length * 0.5, Vector2(taper, taper)),
	], LowPoly.CH_PRIMARY)

	# Structural ribs break up the slab silhouette a bare loft would have.
	var ribs := _i(spec, "ribs", 2)
	for i in ribs:
		var t := (float(i) + 1.0) / (float(ribs) + 1.0)
		var z := lerpf(length * 0.5, -length * 0.5, t)
		var s := lerpf(1.0, taper, t) * 1.04
		lp.add_loft([
			LowPoly.ring(profile, z + length * 0.04, Vector2(s, s)),
			LowPoly.ring(profile, z - length * 0.04, Vector2(s, s)),
		], LowPoly.CH_TRIM, false, false)

	# Panel accent bands, one per side, so a segment reads as plated hull.
	lp.begin_shape()
	for sx: float in [-1.0, 1.0]:
		lp.add_decal_quad(
			Vector3(sx * (width * 0.5 + 0.01), height * 0.20, length * 0.45),
			Vector3(sx * (width * 0.5 + 0.01), height * 0.20, -length * 0.45),
			Vector3(sx * (width * 0.5 + 0.01), -height * 0.12, -length * 0.45),
			Vector3(sx * (width * 0.5 + 0.01), -height * 0.12, length * 0.45),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)
	return {}


## A landing ramp extending outward from the hull. Reports a "dock" marker at
## the outer pad face — a [DockingPad] sits there, forward pointing away from
## the hull (the approach direction).
static func _dock_ramp(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 10.0)
	var width := _f(spec, "width", 3.0)
	var thickness := _f(spec, "thickness", 0.6)
	var pad_width := _f(spec, "pad_width", 6.0)

	# Arm: a tapered beam from the hull mount (z=0) out to the pad (z=-length).
	var arm_profile := LowPoly.chamfered_rect(width, thickness, thickness * 0.3)
	lp.add_loft([
		LowPoly.ring(arm_profile, 0.0, Vector2.ONE),
		LowPoly.ring(arm_profile, -length * 0.7, Vector2.ONE),
	], LowPoly.CH_PRIMARY)

	# Pad: a flat wide landing surface at the tip, raised approach-light rim.
	var pad_profile := LowPoly.chamfered_rect(pad_width, thickness * 0.6, thickness * 0.2)
	lp.add_loft([
		LowPoly.ring(arm_profile, -length * 0.68, Vector2.ONE, Vector3(0, -thickness * 0.2, 0)),
		LowPoly.ring(pad_profile, -length * 0.82, Vector2.ONE, Vector3(0, -thickness * 0.2, 0)),
		LowPoly.ring(pad_profile, -length, Vector2.ONE, Vector3(0, -thickness * 0.2, 0)),
	], LowPoly.CH_TRIM)

	# Corner beacons so the pad reads as a destination at a distance.
	lp.begin_shape()
	for sx: float in [-1.0, 1.0]:
		lp.add_decal_quad(
			Vector3(sx * pad_width * 0.42, thickness * 0.11, -length * 0.90),
			Vector3(sx * pad_width * 0.42, thickness * 0.11, -length * 0.98),
			Vector3(sx * pad_width * 0.30, thickness * 0.11, -length * 0.98),
			Vector3(sx * pad_width * 0.30, thickness * 0.11, -length * 0.90),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)

	return {"dock": [_marker(Vector3(0.0, thickness * 0.6, -length), Vector3.FORWARD)]}


## Tapered tower/turret greeble studding the hull — the "castle spire" look.
static func _spire(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var height := _f(spec, "height", 3.0)
	var base_r := _f(spec, "base_radius", 1.0)
	var sides := _i(spec, "sides", 6)
	# Vertical loft (Y-up), built directly rather than via the Z-extruded
	# ring() helper since spires stand upright off the hull normal.
	var base := _ring_xz(0.0, base_r, base_r, sides)
	var mid := _ring_xz(height * 0.6, base_r * 0.62, base_r * 0.62, sides)
	var tip := _ring_xz(height, base_r * 0.12, base_r * 0.12, sides)
	lp.add_loft([base, mid, tip], LowPoly.CH_PRIMARY)
	# Collar at the base.
	lp.add_loft([
		_ring_xz(0.02, base_r * 1.08, base_r * 1.08, sides),
		_ring_xz(0.22, base_r * 1.08, base_r * 1.08, sides),
	], LowPoly.CH_TRIM, false, false)
	return {}


static func _ring_xz(y: float, rx: float, rz: float, sides: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(sides, 3)
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector3(cos(a) * rx, y, sin(a) * rz))
	return out


## Thin connecting beam — links a dock arm's hull-side mount back to the
## spine so the arm doesn't read as floating.
static func _strut(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 2.0)
	var thickness := _f(spec, "thickness", 0.5)
	lp.add_box(Vector3(0, 0, -length * 0.5), Vector3(thickness, thickness, length), LowPoly.CH_TRIM)
	return {}


## Small cosmetic detail box — the plain fallback kind, and still the filler
## between the more distinctive [code]greeble_*[/code] shapes below. On its
## own, scattered by the hundred, this is what read as "just cubes" — the
## other kinds exist so a hull's clutter isn't one repeated shape.
static func _greeble_block(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var size := Vector3(_f(spec, "sx", 0.6), _f(spec, "sy", 0.6), _f(spec, "sz", 0.6))
	lp.add_box(Vector3.ZERO, size, LowPoly.CH_ACCENT)
	return {}


## A flat raised panel with a trim seam — reads as an access hatch or a plate
## seam rather than a solid block.
static func _greeble_panel(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var w := _f(spec, "sx", 0.8)
	var d := _f(spec, "sz", 0.8)
	var h := _f(spec, "sy", 0.6) * 0.35
	lp.add_box(Vector3.ZERO, Vector3(w, h, d), LowPoly.CH_ACCENT)
	lp.add_box(Vector3(0, h * 0.5 + 0.02, 0), Vector3(w * 0.08, 0.04, d * 0.85), LowPoly.CH_TRIM)
	return {}


## A base block with a few raised slats across the top — vents/radiators.
static func _greeble_vent(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var size := Vector3(_f(spec, "sx", 0.6), _f(spec, "sy", 0.6), _f(spec, "sz", 0.6))
	lp.add_box(Vector3.ZERO, size, LowPoly.CH_ACCENT)
	var slats := 3
	for i in slats:
		var t := (float(i) + 0.5) / float(slats) - 0.5
		lp.add_box(
			Vector3(0, size.y * 0.5 + 0.03, t * size.z * 0.8),
			Vector3(size.x * 0.9, 0.06, size.z * 0.12),
			LowPoly.CH_TRIM
		)
	return {}


## A thin mast with a bright ball tip — antenna/sensor clutter, upright like
## [method _spire] but much thinner and cheaper (two boxes, not a loft).
static func _greeble_antenna(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var height := _f(spec, "sy", 1.2) * 2.0
	var thickness := maxf(_f(spec, "sx", 0.6) * 0.15, 0.05)
	lp.add_box(Vector3(0, height * 0.5, 0), Vector3(thickness, height, thickness), LowPoly.CH_TRIM)
	var tip := thickness * 2.4
	lp.add_box(Vector3(0, height + tip * 0.5, 0), Vector3(tip, tip, tip), LowPoly.CH_ACCENT)
	return {}


## A shallow dish cap — sensor/comms clutter, cheaper than [method _dome]'s
## full hemisphere (one loft, two rings, no polar cap).
static func _greeble_dish(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var radius := _f(spec, "sx", 0.6)
	var depth := radius * 0.35
	var sides := 8
	var rim := _ring_xz(0.0, radius, radius, sides)
	var mid := _ring_xz(-depth, radius * 0.5, radius * 0.5, sides)
	# Rim stays open (the dish's own receiving face); back is capped, same
	# "open the mounted end, cap the free end" convention as [method _dome].
	lp.add_loft([rim, mid], LowPoly.CH_PRIMARY, false, true)
	return {}


## One wedge of a torus, built lying flat in the local XY plane (hoop-normal
## along local Z, so a ring you fly through faces the natural forward axis; a
## ring station instead rotates the whole part 90° about X when it places
## one — see [method LargeCraftGenerator._build_ring]). Several of these
## chained around a full [constant TAU] compose a ring one piece can be shot
## off without touching the rest, unlike one fused torus mesh.
##
## Absolute, not part-canonical: the wedge's own vertices already carry
## [code]center_angle[/code], so the part's local origin is the *ring's*
## centre, not the wedge's — every wedge of one ring can share the same
## [code]local_xform[/code] (just the ring's placement), matching how the
## caller already has to know the ring centre to lay wedges out in the first
## place.
static func _ring_segment(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var center_angle := _f(spec, "center_angle", 0.0)
	var angle_span := _f(spec, "angle_span", PI * 0.25)
	var radius := _f(spec, "radius", 20.0)
	var tube_radius := _f(spec, "tube_radius", 2.0)
	var sides := _i(spec, "sides", 8)
	var steps := maxi(_i(spec, "steps", 6), 2)
	var tube_profile := LowPoly.ngon(sides, tube_radius, 1.0)
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := center_angle - angle_span * 0.5 + angle_span * t
		var centre := Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		var tangent := Vector3(-sin(a), cos(a), 0.0)
		var normal := Vector3(0.0, 0.0, 1.0)
		var binormal := tangent.cross(normal)
		var ring_pts := PackedVector3Array()
		for p in tube_profile:
			ring_pts.append(centre + binormal * p.x + normal * p.y)
		rings.append(ring_pts)
	lp.add_loft(rings, LowPoly.CH_PRIMARY)
	return {}


## A weapon turret: a housing block with a barrel. Reports a "muzzle" marker
## at the barrel tip, forward pointing outward along the barrel — for a
## firing consumer to aim from (flight-side; this factory only builds
## geometry, same "combat-agnostic" split [DockingPad]'s "dock" marker uses).
static func _turret(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var base := _f(spec, "base", 1.2)
	var barrel := _f(spec, "barrel", 1.8)
	var barrel_r := _f(spec, "barrel_r", 0.22)
	lp.add_box(Vector3(0, base * 0.28, 0), Vector3(base, base * 0.55, base), LowPoly.CH_PRIMARY)
	lp.add_box(
		Vector3(0, base * 0.5, -(barrel * 0.5 + base * 0.35)),
		Vector3(barrel_r * 2.0, barrel_r * 2.0, barrel), LowPoly.CH_TRIM
	)
	var tip := Vector3(0, base * 0.5, -(barrel + base * 0.35))
	return {"muzzle": [_marker(tip, Vector3.FORWARD)]}


## A swept wing panel — thin diamond cross-section (leading/trailing edge
## taper) lofted from root (flush against the hull, at local origin) out to
## the tip along local X, sweeping back along -Z and rising along +Y as it
## goes. [param spec]'s "side" (±1) mirrors it for the other half of the
## aircraft: rather than mirroring the built mesh via a negative-scale
## transform (which silently inverts every face normal — a known Godot
## gotcha for custom flat-shaded meshes like [LowPoly]'s), every vertex is
## generated fresh with X already multiplied by `side`, and the ring's own
## point order is reversed to match — the winding a mirrored strip actually
## needs, worked out once here instead of trusted to a transform.
static func _wing(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var side := signf(_f(spec, "side", 1.0))
	if is_zero_approx(side):
		side = 1.0
	var span := _f(spec, "span", 8.0)
	var root_chord := _f(spec, "root_chord", 6.0)
	var tip_chord := _f(spec, "tip_chord", 2.0)
	var sweep := _f(spec, "sweep", 3.0)
	var dihedral := _f(spec, "dihedral", 0.6)
	var thickness := _f(spec, "thickness", 0.4)
	var steps := 3
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := side * span * t
		var chord := lerpf(root_chord, tip_chord, t)
		var z_off := -sweep * t
		var y_off := dihedral * t
		var half_c := chord * 0.5
		var half_t := thickness * 0.5 * (1.0 - t * 0.4)
		var ring := PackedVector3Array([
			Vector3(x, y_off, z_off + half_c),                # trailing edge
			Vector3(x, y_off + half_t, z_off + half_c * 0.15), # upper mid
			Vector3(x, y_off, z_off - half_c),                # leading edge
			Vector3(x, y_off - half_t, z_off + half_c * 0.15), # lower mid
		])
		if side < 0.0:
			ring.reverse()
		rings.append(ring)
	lp.add_loft(rings, LowPoly.CH_PRIMARY)
	# A trim stripe along the leading edge, both sides, purely cosmetic.
	lp.begin_shape()
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var x0 := side * span * t0
		var x1 := side * span * t1
		var c0 := lerpf(root_chord, tip_chord, t0) * 0.5
		var c1 := lerpf(root_chord, tip_chord, t1) * 0.5
		var y0 := dihedral * t0
		var y1 := dihedral * t1
		var z0 := -sweep * t0 - c0
		var z1 := -sweep * t1 - c1
		lp.add_decal_quad(
			Vector3(x0, y0 + 0.02, z0), Vector3(x1, y1 + 0.02, z1),
			Vector3(x1, y1 - 0.02, z1 + 0.3), Vector3(x0, y0 - 0.02, z0 + 0.3),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)
	return {}


## A vertical stabilizer — same diamond-cross-section sweep as [method _wing],
## just standing up off local Y instead of spanning local X, root at the
## hull, sweeping back along -Z as it rises. Single part, never mirrored.
static func _tail_fin(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var height := _f(spec, "height", 5.0)
	var root_chord := _f(spec, "root_chord", 5.0)
	var tip_chord := _f(spec, "tip_chord", 1.5)
	var sweep := _f(spec, "sweep", 2.5)
	var thickness := _f(spec, "thickness", 0.35)
	var steps := 3
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var y := height * t
		var chord := lerpf(root_chord, tip_chord, t)
		var z_off := -sweep * t
		var half_c := chord * 0.5
		var half_t := thickness * 0.5 * (1.0 - t * 0.3)
		rings.append(PackedVector3Array([
			Vector3(0.0, y, z_off + half_c),
			Vector3(half_t, y, z_off + half_c * 0.15),
			Vector3(0.0, y, z_off - half_c),
			Vector3(-half_t, y, z_off + half_c * 0.15),
		]))
	lp.add_loft(rings, LowPoly.CH_PRIMARY)
	return {}


## Hemisphere for a station hub — a mirrored pair (see [param flip]) forms a
## full sphere. Equator is left open ([code]cap_start=false[/code]) so it
## mounts flush against whatever it's bolted to (the hull, or its own mirror);
## only the pole is capped.
static func _dome(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var radius := _f(spec, "radius", 4.0)
	var sides := _i(spec, "sides", 10)
	var steps := maxi(_i(spec, "steps", 5), 2)
	var flip := _f(spec, "flip", 0.0) > 0.5
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ang := t * PI * 0.5
		var r := cos(ang) * radius
		var y := sin(ang) * radius * (-1.0 if flip else 1.0)
		rings.append(_ring_xz(y, r, r, sides))
	lp.add_loft(rings, LowPoly.CH_PRIMARY, false, true)
	# Panel seams, purely cosmetic.
	var band := _ring_xz(radius * 0.34 * (-1.0 if flip else 1.0), radius * 0.94, radius * 0.94, sides)
	var band2 := _ring_xz(radius * 0.40 * (-1.0 if flip else 1.0), radius * 0.90, radius * 0.90, sides)
	lp.add_loft([band, band2], LowPoly.CH_TRIM, false, false)
	return {}
