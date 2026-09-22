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
		"truss_spine": markers = _truss_spine(lp, spec)
		"city_slab": markers = _city_slab(lp, spec)
		"biosphere_dome": markers = _biosphere_dome(lp, spec)
		"energy_ring": markers = _energy_ring(lp, spec)
		"plasma_core": markers = _plasma_core(lp, spec)
		"saucer_sector": markers = _saucer_sector(lp, spec)
		"fuel_cluster": markers = _fuel_cluster(lp, spec)
		"radiator_wing": markers = _radiator_wing(lp, spec)
		"hangar_bay": markers = _hangar_bay(lp, spec)
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


static func _rect_xz(y: float, width: float, depth: float, corner := 0.0) -> PackedVector3Array:
	var hw := width * 0.5
	var hd := depth * 0.5
	var c := clampf(corner, 0.0, minf(hw, hd) * 0.95)
	if c <= 0.0:
		return PackedVector3Array([
			Vector3(hw, y, -hd), Vector3(hw, y, hd), Vector3(-hw, y, hd), Vector3(-hw, y, -hd)
		])
	return PackedVector3Array([
		Vector3(hw, y, -hd + c), Vector3(hw, y, hd - c), Vector3(hw - c, y, hd),
		Vector3(-hw + c, y, hd), Vector3(-hw, y, hd - c), Vector3(-hw, y, -hd + c),
		Vector3(-hw + c, y, -hd), Vector3(hw - c, y, -hd),
	])


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


## Open 4-column structural lattice girder with cross-ties and diagonal bracing.
## Extrudes along -Z from z=0 to z=-length.
static func _truss_spine(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 20.0)
	var width := _f(spec, "width", 4.0)
	var height := _f(spec, "height", 4.0)
	var chord_thick := maxf(minf(width, height) * 0.12, 0.2)
	var bays := maxi(_i(spec, "bays", 4), 1)
	var hw := (width - chord_thick) * 0.5
	var hh := (height - chord_thick) * 0.5

	# 4 continuous longitudinal chords running the full length
	var corners := [
		Vector3(hw, hh, 0.0),
		Vector3(-hw, hh, 0.0),
		Vector3(-hw, -hh, 0.0),
		Vector3(hw, -hh, 0.0),
	]
	for c in corners:
		lp.add_box(Vector3(c.x, c.y, -length * 0.5), Vector3(chord_thick, chord_thick, length), LowPoly.CH_TRIM)

	# Cross-ties per bay
	var bay_len := length / float(bays)
	for b in bays + 1:
		var z := -float(b) * bay_len
		lp.add_box(Vector3(0.0, hh, z), Vector3(width, chord_thick, chord_thick), LowPoly.CH_TRIM)
		lp.add_box(Vector3(0.0, -hh, z), Vector3(width, chord_thick, chord_thick), LowPoly.CH_TRIM)
		lp.add_box(Vector3(hw, 0.0, z), Vector3(chord_thick, height, chord_thick), LowPoly.CH_TRIM)
		lp.add_box(Vector3(-hw, 0.0, z), Vector3(chord_thick, height, chord_thick), LowPoly.CH_TRIM)

	# Diagonal cross braces along each bay
	var diag_len := Vector2(width, bay_len).length()
	for b in bays:
		var z0 := -float(b) * bay_len
		var z1 := -float(b + 1) * bay_len
		var z_mid := (z0 + z1) * 0.5
		lp.begin_shape()
		lp.add_box(Vector3(0.0, hh, z_mid), Vector3(chord_thick * 0.8, chord_thick * 0.8, diag_len * 0.95), LowPoly.CH_PRIMARY)
		lp.add_box(Vector3(0.0, -hh, z_mid), Vector3(chord_thick * 0.8, chord_thick * 0.8, diag_len * 0.95), LowPoly.CH_PRIMARY)
		lp.add_box(Vector3(hw, 0.0, z_mid), Vector3(chord_thick * 0.8, chord_thick * 0.8, diag_len * 0.95), LowPoly.CH_PRIMARY)
		lp.add_box(Vector3(-hw, 0.0, z_mid), Vector3(chord_thick * 0.8, chord_thick * 0.8, diag_len * 0.95), LowPoly.CH_PRIMARY)
		lp.end_shape(false)

	# Center transit conduit / power pipe running down the core
	var core_r := minf(width, height) * 0.22
	var core_prof := LowPoly.ngon(6, core_r, 1.0)
	lp.add_loft([
		LowPoly.ring(core_prof, 0.0, Vector2.ONE),
		LowPoly.ring(core_prof, -length, Vector2.ONE),
	], LowPoly.CH_ACCENT, true, true)
	return {}


## Stepped cantilevered habitat block with chamfered profile and glowing window strips.
## Built upright (local +Y is height, X is width, Z is depth) matching tower and spire conventions.
static func _city_slab(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var width := _f(spec, "width", 14.0)
	var height := _f(spec, "height", 8.0)
	var depth := _f(spec, "depth", 12.0)
	var chamfer := _f(spec, "chamfer", width * 0.15)
	var taper := _f(spec, "taper", 0.85)

	# Base mounting terrace collar (CH_TRIM)
	var base_ring_0 := _rect_xz(0.0, width * 1.06, depth * 1.06, chamfer)
	var base_ring_1 := _rect_xz(height * 0.12, width * 1.06, depth * 1.06, chamfer)
	lp.add_loft([base_ring_0, base_ring_1], LowPoly.CH_TRIM, true, false)

	# Main tiered block loft (CH_PRIMARY)
	var r0 := _rect_xz(height * 0.10, width, depth, chamfer)
	var r1 := _rect_xz(height * 0.50, width * 0.96, depth * 0.96, chamfer)
	var r2 := _rect_xz(height * 0.85, width * taper, depth * taper, chamfer * taper)
	var r3 := _rect_xz(height, width * taper * 0.95, depth * taper * 0.95, chamfer * taper * 0.95)
	lp.add_loft([r0, r1, r2, r3], LowPoly.CH_PRIMARY, false, true)

	# Lit window bands (CH_ACCENT) wrapping horizontally around the tiers
	var window_tiers := _i(spec, "windows", 3)
	lp.begin_shape()
	for i in window_tiers:
		var t := (float(i) + 0.5) / float(window_tiers)
		var y_win := height * lerpf(0.22, 0.82, t)
		var s := lerpf(1.0, taper, t)
		var hw := width * s * 0.5 + 0.02
		var hd := depth * s * 0.5 + 0.02
		var h_win := height * 0.04
		# Front face (+Z)
		lp.add_decal_quad(
			Vector3(-hw * 0.8, y_win - h_win, hd),
			Vector3(hw * 0.8, y_win - h_win, hd),
			Vector3(hw * 0.8, y_win + h_win, hd),
			Vector3(-hw * 0.8, y_win + h_win, hd),
			LowPoly.CH_ACCENT
		)
		# Back face (-Z)
		lp.add_decal_quad(
			Vector3(hw * 0.8, y_win - h_win, -hd),
			Vector3(-hw * 0.8, y_win - h_win, -hd),
			Vector3(-hw * 0.8, y_win + h_win, -hd),
			Vector3(hw * 0.8, y_win + h_win, -hd),
			LowPoly.CH_ACCENT
		)
		# Right face (+X)
		lp.add_decal_quad(
			Vector3(hw, y_win - h_win, hd * 0.8),
			Vector3(hw, y_win - h_win, -hd * 0.8),
			Vector3(hw, y_win + h_win, -hd * 0.8),
			Vector3(hw, y_win + h_win, hd * 0.8),
			LowPoly.CH_ACCENT
		)
		# Left face (-X)
		lp.add_decal_quad(
			Vector3(-hw, y_win - h_win, -hd * 0.8),
			Vector3(-hw, y_win - h_win, hd * 0.8),
			Vector3(-hw, y_win + h_win, hd * 0.8),
			Vector3(-hw, y_win + h_win, -hd * 0.8),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)

	# Cantilevered observation terrace on front (+Z face)
	var terrace_w := width * 0.45
	var terrace_d := depth * 0.25
	var terrace_y := height * 0.5
	var t_z0 := depth * 0.5
	var t_z1 := depth * 0.5 + terrace_d
	var tr0 := _rect_xz(terrace_y, terrace_w, terrace_d, terrace_w * 0.1)
	var tr1 := _rect_xz(terrace_y - height * 0.1, terrace_w * 0.9, terrace_d * 0.9, terrace_w * 0.1)
	for idx in tr0.size():
		tr0[idx].z += terrace_d * 0.5 + depth * 0.48
		tr1[idx].z += terrace_d * 0.5 + depth * 0.48
	lp.add_loft([tr0, tr1], LowPoly.CH_TRIM, true, true)

	# Heavy cantilever under-bracket ribs (CH_TRIM)
	var rib_w := width * 0.16
	var rib_h := height * 0.25
	lp.add_box(Vector3(width * 0.25, -rib_h * 0.4, 0.0), Vector3(rib_w, rib_h, depth * 0.7), LowPoly.CH_TRIM)
	lp.add_box(Vector3(-width * 0.25, -rib_h * 0.4, 0.0), Vector3(rib_w, rib_h, depth * 0.7), LowPoly.CH_TRIM)
	return {}


## Geodesic faceted biosphere dome with equatorial structural collar ring
## and glowing biome facet panes (CH_ACCENT).
static func _biosphere_dome(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var radius := _f(spec, "radius", 8.0)
	var sides := _i(spec, "sides", 14)
	var steps := maxi(_i(spec, "steps", 6), 3)
	var flip := _f(spec, "flip", 0.0) > 0.5
	var y_sign := -1.0 if flip else 1.0

	# Base structural collar ring
	var collar_r := radius * 1.08
	var collar_h := radius * 0.15
	var collar_outer := _ring_xz(0.0, collar_r, collar_r, sides)
	var collar_top := _ring_xz(collar_h * y_sign, collar_r, collar_r, sides)
	lp.add_loft([collar_outer, collar_top], LowPoly.CH_TRIM, true, false)

	# Faceted geodesic dome rings
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ang := t * PI * 0.5
		var r := cos(ang) * radius
		var y := (collar_h + sin(ang) * radius * 0.85) * y_sign
		rings.append(_ring_xz(y, r, r, sides))
	lp.add_loft(rings, LowPoly.CH_PRIMARY, false, true)

	# Glowing bio-luminescent window sectors on the dome
	var mid_step := steps / 2
	if mid_step < rings.size() - 1:
		var r_low: PackedVector3Array = rings[mid_step]
		var r_high: PackedVector3Array = rings[mid_step + 1]
		lp.begin_shape()
		for i in sides:
			if i % 2 == 0:
				var j := (i + 1) % sides
				lp.add_decal_quad(
					r_low[i] * 1.01, r_low[j] * 1.01,
					r_high[j] * 1.01, r_high[i] * 1.01,
					LowPoly.CH_ACCENT
				)
		lp.end_shape(false)

	# Geodesic meridional structural ribs running up to the apex
	for i in sides:
		if i % 2 == 0:
			var p_base: Vector3 = rings[0][i]
			var p_mid: Vector3 = rings[mid_step][i]
			var rib_len := (p_mid - p_base).length()
			lp.add_box((p_base + p_mid) * 0.5, Vector3(radius * 0.05, radius * 0.05, rib_len), LowPoly.CH_TRIM)
	return {}


## Circular energy conduit ring platform (portal accelerator ring or gravity wheel).
## Hoop faces Z so you can fly through it.
static func _energy_ring(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var radius := _f(spec, "radius", 18.0)
	var tube_radius := _f(spec, "tube_radius", 1.8)
	var sides := _i(spec, "sides", 10)
	var segments := maxi(_i(spec, "segments", 16), 8)

	# Outer structural ring (CH_TRIM)
	var outer_r := radius + tube_radius * 0.4
	var outer_tube := tube_radius * 0.6
	var tube_profile := LowPoly.ngon(sides, outer_tube, 1.2)
	var rings: Array = []
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var centre := Vector3(cos(a) * outer_r, sin(a) * outer_r, 0.0)
		var tangent := Vector3(-sin(a), cos(a), 0.0)
		var normal := Vector3(0.0, 0.0, 1.0)
		var binormal := tangent.cross(normal)
		var ring_pts := PackedVector3Array()
		for p in tube_profile:
			ring_pts.append(centre + binormal * p.x + normal * p.y)
		rings.append(ring_pts)
	lp.add_loft(rings, LowPoly.CH_TRIM, false, false)

	# Inner glowing accelerator track (CH_ACCENT)
	var inner_r := radius - tube_radius * 0.5
	var inner_tube := tube_radius * 0.4
	var inner_profile := LowPoly.ngon(8, inner_tube, 0.8)
	var inner_rings: Array = []
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var centre := Vector3(cos(a) * inner_r, sin(a) * inner_r, 0.0)
		var tangent := Vector3(-sin(a), cos(a), 0.0)
		var normal := Vector3(0.0, 0.0, 1.0)
		var binormal := tangent.cross(normal)
		var ring_pts := PackedVector3Array()
		for p in inner_profile:
			ring_pts.append(centre + binormal * p.x + normal * p.y)
		inner_rings.append(ring_pts)
	lp.add_loft(inner_rings, LowPoly.CH_ACCENT, false, false)

	# Radial structural brackets tying outer and inner rings
	var spoke_count := clampi(segments / 2, 4, 12)
	for i in spoke_count:
		var a := TAU * float(i) / float(spoke_count)
		var mid_r := (outer_r + inner_r) * 0.5
		var pos := Vector3(cos(a) * mid_r, sin(a) * mid_r, 0.0)
		var bracket_len := outer_r - inner_r + tube_radius * 0.5
		lp.add_box(pos, Vector3(tube_radius * 0.4, bracket_len, tube_radius * 0.8), LowPoly.CH_PRIMARY)
	return {}


## Ventral plasma super-core / reactor aperture with central glowing plasma emitter.
static func _plasma_core(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var radius := _f(spec, "radius", 12.0)
	var depth := _f(spec, "depth", 6.0)
	var sides := _i(spec, "sides", 14)

	# Stepped outer containment bevel rings stepping downward into the recess
	var r0 := _ring_xz(0.0, radius, radius, sides)
	var r1 := _ring_xz(-depth * 0.3, radius * 0.88, radius * 0.88, sides)
	var r2 := _ring_xz(-depth * 0.7, radius * 0.65, radius * 0.65, sides)
	var r3 := _ring_xz(-depth, radius * 0.42, radius * 0.42, sides)
	lp.add_loft([r0, r1, r2, r3], LowPoly.CH_TRIM, true, true)

	# Central glowing plasma sphere / column (CH_ACCENT)
	var core_r := radius * 0.35
	var core_h := depth * 0.6
	var c_base := _ring_xz(-depth, core_r * 0.9, core_r * 0.9, sides)
	var c_mid := _ring_xz(-depth * 0.3, core_r, core_r, sides)
	var c_tip := _ring_xz(core_h * 0.2, core_r * 0.2, core_r * 0.2, sides)
	lp.add_loft([c_base, c_mid, c_tip], LowPoly.CH_ACCENT, true, true)

	# Magnetic containment vanes (radial fins)
	var fin_count := 6
	for i in fin_count:
		var a := TAU * float(i) / float(fin_count)
		var fin_mid := Vector3(cos(a) * radius * 0.6, -depth * 0.5, sin(a) * radius * 0.6)
		lp.add_box(fin_mid, Vector3(radius * 0.08, depth * 0.5, radius * 0.35), LowPoly.CH_PRIMARY)
	return {}


## Concentric stepped disc wedge for the colossal saucer mothership (Ref 5).
static func _saucer_sector(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var center_angle := _f(spec, "center_angle", 0.0)
	var angle_span := _f(spec, "angle_span", PI * 0.25)
	var inner_r := _f(spec, "inner_r", 6.0)
	var mid_r := _f(spec, "mid_r", 18.0)
	var outer_r := _f(spec, "outer_r", 30.0)
	var height := _f(spec, "height", 8.0)
	var steps := maxi(_i(spec, "steps", 5), 2)

	# Construct the wedge volumes using add_quad
	lp.begin_shape()
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var ang0 := center_angle - angle_span * 0.5 + angle_span * t0
		var ang1 := center_angle - angle_span * 0.5 + angle_span * t1
		var d0 := Vector3(cos(ang0), 0.0, sin(ang0))
		var d1 := Vector3(cos(ang1), 0.0, sin(ang1))

		# Inner tier: y from -height*0.2 to +height*0.5
		var in_top0 := d0 * mid_r + Vector3(0, height * 0.35, 0)
		var in_top1 := d1 * mid_r + Vector3(0, height * 0.35, 0)
		var in_core0 := d0 * inner_r + Vector3(0, height * 0.5, 0)
		var in_core1 := d1 * inner_r + Vector3(0, height * 0.5, 0)
		lp.add_quad(in_core0, in_core1, in_top1, in_top0, LowPoly.CH_PRIMARY)

		# Outer armor tier: y from -height*0.3 to +height*0.12
		var out_mid0 := d0 * mid_r + Vector3(0, height * 0.12, 0)
		var out_mid1 := d1 * mid_r + Vector3(0, height * 0.12, 0)
		var out_rim0 := d0 * outer_r + Vector3(0, 0.0, 0)
		var out_rim1 := d1 * outer_r + Vector3(0, 0.0, 0)
		lp.add_quad(out_mid0, out_mid1, out_rim1, out_rim0, LowPoly.CH_PRIMARY)

		# Trench step wall between inner and outer decks
		lp.add_quad(in_top0, in_top1, out_mid1, out_mid0, LowPoly.CH_TRIM)

		# Ventral keel slope
		var bot_core0 := d0 * inner_r + Vector3(0, -height * 0.45, 0)
		var bot_core1 := d1 * inner_r + Vector3(0, -height * 0.45, 0)
		var bot_rim0 := d0 * outer_r + Vector3(0, -height * 0.15, 0)
		var bot_rim1 := d1 * outer_r + Vector3(0, -height * 0.15, 0)
		lp.add_quad(bot_rim0, bot_rim1, bot_core1, bot_core0, LowPoly.CH_PRIMARY)

		# Outer edge vertical band
		lp.add_quad(out_rim0, out_rim1, bot_rim1, bot_rim0, LowPoly.CH_TRIM)

		# Inner core vertical collar
		lp.add_quad(in_core1, in_core0, bot_core0, bot_core1, LowPoly.CH_TRIM)

	# Radial start end cap
	var d_start := Vector3(cos(center_angle - angle_span * 0.5), 0.0, sin(center_angle - angle_span * 0.5))
	var s_in_top := d_start * mid_r + Vector3(0, height * 0.35, 0)
	var s_in_core := d_start * inner_r + Vector3(0, height * 0.5, 0)
	var s_out_mid := d_start * mid_r + Vector3(0, height * 0.12, 0)
	var s_out_rim := d_start * outer_r + Vector3(0, 0.0, 0)
	var s_bot_core := d_start * inner_r + Vector3(0, -height * 0.45, 0)
	var s_bot_rim := d_start * outer_r + Vector3(0, -height * 0.15, 0)
	lp.add_quad(s_in_top, s_in_core, s_bot_core, s_out_mid, LowPoly.CH_TRIM)
	lp.add_quad(s_out_mid, s_bot_core, s_bot_rim, s_out_rim, LowPoly.CH_TRIM)

	# Radial end cap
	var d_end := Vector3(cos(center_angle + angle_span * 0.5), 0.0, sin(center_angle + angle_span * 0.5))
	var e_in_top := d_end * mid_r + Vector3(0, height * 0.35, 0)
	var e_in_core := d_end * inner_r + Vector3(0, height * 0.5, 0)
	var e_out_mid := d_end * mid_r + Vector3(0, height * 0.12, 0)
	var e_out_rim := d_end * outer_r + Vector3(0, 0.0, 0)
	var e_bot_core := d_end * inner_r + Vector3(0, -height * 0.45, 0)
	var e_bot_rim := d_end * outer_r + Vector3(0, -height * 0.15, 0)
	lp.add_quad(e_in_core, e_in_top, e_out_mid, e_bot_core, LowPoly.CH_TRIM)
	lp.add_quad(e_bot_core, e_out_mid, e_out_rim, e_bot_rim, LowPoly.CH_TRIM)
	lp.end_shape(false)

	# Window stripe decals on the trench step wall
	lp.begin_shape()
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var ang0 := center_angle - angle_span * 0.5 + angle_span * t0
		var ang1 := center_angle - angle_span * 0.5 + angle_span * t1
		var d0 := Vector3(cos(ang0), 0.0, sin(ang0))
		var d1 := Vector3(cos(ang1), 0.0, sin(ang1))
		var w_top0 := d0 * (mid_r + 0.02) + Vector3(0, height * 0.28, 0)
		var w_top1 := d1 * (mid_r + 0.02) + Vector3(0, height * 0.28, 0)
		var w_bot0 := d0 * (mid_r + 0.02) + Vector3(0, height * 0.18, 0)
		var w_bot1 := d1 * (mid_r + 0.02) + Vector3(0, height * 0.18, 0)
		lp.add_decal_quad(w_top0, w_top1, w_bot1, w_bot0, LowPoly.CH_ACCENT)

		# Outer rim navigation beacon stripes on alternating segments
		if i % 2 == 0:
			var r_top0 := d0 * (outer_r + 0.02) + Vector3(0, -height * 0.02, 0)
			var r_top1 := d1 * (outer_r + 0.02) + Vector3(0, -height * 0.02, 0)
			var r_bot0 := d0 * (outer_r + 0.02) + Vector3(0, -height * 0.12, 0)
			var r_bot1 := d1 * (outer_r + 0.02) + Vector3(0, -height * 0.12, 0)
			lp.add_decal_quad(r_top0, r_top1, r_bot1, r_bot0, LowPoly.CH_ACCENT)
	lp.end_shape(false)
	return {}


## Propellant tank cluster with mounting cradle and manifold piping.
static func _fuel_cluster(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var length := _f(spec, "length", 16.0)
	var tank_r := _f(spec, "tank_radius", 2.2)
	var count := clampi(_i(spec, "count", 4), 2, 6)
	var spread := tank_r * 2.1

	# End bulkheads / cradles
	lp.add_box(Vector3(0, 0, 0.5), Vector3(spread * float(count) * 0.6, spread * 1.5, 1.2), LowPoly.CH_TRIM)
	lp.add_box(Vector3(0, 0, -length - 0.5), Vector3(spread * float(count) * 0.6, spread * 1.5, 1.2), LowPoly.CH_TRIM)

	# Cylindrical tanks
	var tank_prof := LowPoly.ngon(8, tank_r, 1.0)
	for i in count:
		var x_off := (float(i) - float(count - 1) * 0.5) * spread
		lp.add_loft([
			LowPoly.ring(tank_prof, 0.0, Vector2.ONE, Vector3(x_off, 0, 0)),
			LowPoly.ring(tank_prof, -length * 0.1, Vector2(1.05, 1.05), Vector3(x_off, 0, 0)),
			LowPoly.ring(tank_prof, -length * 0.9, Vector2(1.05, 1.05), Vector3(x_off, 0, 0)),
			LowPoly.ring(tank_prof, -length, Vector2.ONE, Vector3(x_off, 0, 0)),
		], LowPoly.CH_PRIMARY, true, true)
		lp.add_box(Vector3(x_off, 0, -length * 0.35), Vector3(tank_r * 2.15, tank_r * 2.15, 0.4), LowPoly.CH_ACCENT)
		lp.add_box(Vector3(x_off, 0, -length * 0.65), Vector3(tank_r * 2.15, tank_r * 2.15, 0.4), LowPoly.CH_ACCENT)
	return {}


## Industrial cooling radiator wing with corrugated slats and coolant conduits.
static func _radiator_wing(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var span := _f(spec, "span", 18.0)
	var chord := _f(spec, "chord", 10.0)
	var thickness := _f(spec, "thickness", 0.6)
	var side := signf(_f(spec, "side", 1.0))
	if is_zero_approx(side):
		side = 1.0

	# Heavy structural root mount spar
	lp.add_box(Vector3(side * span * 0.5, 0, 0), Vector3(span, thickness * 1.5, thickness * 2.0), LowPoly.CH_TRIM)

	# Radiator panel slab
	var panel_w := span * 0.9
	var panel_d := chord * 0.85
	lp.add_box(
		Vector3(side * (span * 0.5 + 0.5), 0, -panel_d * 0.5),
		Vector3(panel_w, thickness * 0.5, panel_d),
		LowPoly.CH_PRIMARY
	)

	# Glowing coolant conduit pipe along trailing edge
	lp.add_box(
		Vector3(side * span * 0.5, thickness * 0.4, -panel_d),
		Vector3(span * 0.95, thickness * 0.6, thickness * 0.6),
		LowPoly.CH_ACCENT
	)

	# Radiator cooling corrugation ribs
	var rib_count := 5
	for i in rib_count:
		var t := (float(i) + 0.5) / float(rib_count)
		var x := side * lerpf(span * 0.15, span * 0.9, t)
		lp.add_box(Vector3(x, thickness * 0.3, -panel_d * 0.5), Vector3(0.3, thickness * 0.4, panel_d * 0.95), LowPoly.CH_TRIM)
	return {}


## Inset open-mouth docking cavity with landing guide lights.
static func _hangar_bay(lp: LowPoly, spec: Dictionary) -> Dictionary:
	var width := _f(spec, "width", 8.0)
	var height := _f(spec, "height", 5.0)
	var depth := _f(spec, "depth", 12.0)
	var frame_thick := _f(spec, "frame", 0.8)

	var hw := width * 0.5
	var hh := height * 0.5
	lp.add_box(Vector3(0, hh + frame_thick * 0.5, 0), Vector3(width + frame_thick * 2.0, frame_thick, frame_thick * 2.0), LowPoly.CH_TRIM)
	lp.add_box(Vector3(0, -hh - frame_thick * 0.5, 0), Vector3(width + frame_thick * 2.0, frame_thick, frame_thick * 2.0), LowPoly.CH_TRIM)
	lp.add_box(Vector3(hw + frame_thick * 0.5, 0, 0), Vector3(frame_thick, height, frame_thick * 2.0), LowPoly.CH_TRIM)
	lp.add_box(Vector3(-hw - frame_thick * 0.5, 0, 0), Vector3(frame_thick, height, frame_thick * 2.0), LowPoly.CH_TRIM)

	lp.add_box(Vector3(0, -hh + 0.1, -depth * 0.5), Vector3(width, 0.2, depth), LowPoly.CH_PRIMARY)
	lp.add_box(Vector3(0, hh - 0.1, -depth * 0.5), Vector3(width, 0.2, depth), LowPoly.CH_PRIMARY)
	lp.add_box(Vector3(hw - 0.1, 0, -depth * 0.5), Vector3(0.2, height, depth), LowPoly.CH_PRIMARY)
	lp.add_box(Vector3(-hw + 0.1, 0, -depth * 0.5), Vector3(0.2, height, depth), LowPoly.CH_PRIMARY)
	lp.add_box(Vector3(0, 0, -depth), Vector3(width, height, 0.4), LowPoly.CH_TRIM)

	lp.add_box(Vector3(0, -hh + 0.22, -depth * 0.5), Vector3(width * 0.15, 0.05, depth * 0.85), LowPoly.CH_ACCENT)
	# Ceiling approach guidance light strip
	lp.add_box(Vector3(0, hh - 0.22, -depth * 0.5), Vector3(width * 0.15, 0.05, depth * 0.85), LowPoly.CH_ACCENT)

	# Gateway entrance portal indicator chevrons
	lp.begin_shape()
	for sx in [-1.0, 1.0]:
		lp.add_decal_quad(
			Vector3(sx * (hw + frame_thick * 0.2), hh + frame_thick * 0.8, 0.02),
			Vector3(sx * (hw + frame_thick * 0.8), hh + frame_thick * 0.8, 0.02),
			Vector3(sx * (hw + frame_thick * 0.8), hh + frame_thick * 0.2, 0.02),
			Vector3(sx * (hw + frame_thick * 0.2), hh + frame_thick * 0.2, 0.02),
			LowPoly.CH_ACCENT
		)
	lp.end_shape(false)

	return {"dock": [_marker(Vector3(0.0, -hh + 0.3, -depth * 0.6), Vector3.FORWARD)]}

