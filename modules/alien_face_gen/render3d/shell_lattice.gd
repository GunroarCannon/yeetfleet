class_name ShellLattice

## Builds the head as a round, closed egg-of-revolution swept crown → chin.
## There is no neck: the shell ends at the chin and is capped off, and the
## cross-section is a full circle (head depth == head width) so the silhouette
## reads round rather than faceted/flat or "diamond".
##
## `half_width(y)` is the shared source of truth for the silhouette, so facial
## features seat on the exact same surface via `surface_point()`.

const _DEPTH_BIAS := 1.0  # round cross-section (was 0.6 → flattened egg)


static func build(lm: FaceLandmarks, g: FaceGenome, style: StyleBase3D, lod: int, palette: FacePalette) -> MeshData:
	var md := MeshData.new()
	var res := Lod.mesh_res(lod)
	var rings: int = res.x
	var segs: int = res.y

	var y_top := lm.crown.y
	var y_bottom := lm.chin.y

	# Vertex rings.
	var all_verts: Array[Vector3] = []
	for r in range(rings):
		var t := float(r) / maxf(rings - 1, 1)
		var y := lerpf(y_top, y_bottom, t)
		var w := half_width(y, lm)
		for s in range(segs):
			var a := TAU * s / segs
			all_verts.append(Vector3(w * cos(a), y, w * _DEPTH_BIAS * sin(a)))

	# Side quads.
	for r in range(rings - 1):
		for s in range(segs):
			var s_next := (s + 1) % segs
			var i00 := r * segs + s
			var i01 := r * segs + s_next
			var i10 := (r + 1) * segs + s
			var i11 := (r + 1) * segs + s_next
			_emit_tri(md, all_verts[i00], all_verts[i01], all_verts[i10], palette.skin_base)
			_emit_tri(md, all_verts[i01], all_verts[i11], all_verts[i10], palette.skin_base)

	# Top cap (rounded dome over the crown).
	var top_center := Vector3(0.0, y_top - 0.02, 0.0)
	for s in range(segs):
		var s_next := (s + 1) % segs
		_emit_tri(md, top_center, all_verts[s_next], all_verts[s], palette.skin_base)

	# Bottom cap (closes under the chin — no neck).
	var bottom_center := Vector3(0.0, y_bottom + 0.02, 0.0)
	var bottom_ring := (rings - 1) * segs
	for s in range(segs):
		var s_next := (s + 1) % segs
		_emit_tri(md, bottom_center, all_verts[bottom_ring + s],
			all_verts[bottom_ring + s_next], palette.skin_base)

	md.surfaces.append({
		"name": &"shell", "start": 0, "count": md.indices.size(), "material_hint": &"shell"
	})
	return md


## Front-shell surface point for a face-space landmark (x, y).
static func surface_point(x: float, y: float, lm: FaceLandmarks, _g: FaceGenome) -> Vector3:
	var w := half_width(y, lm)
	var ax := clampf(x / maxf(w, 0.001), -1.0, 1.0)
	var a := acos(ax)
	return Vector3(ax * w, y, w * _DEPTH_BIAS * sin(a))


## Outward unit normal on the shell at a landmark (used to orient features).
static func surface_normal(x: float, y: float, lm: FaceLandmarks) -> Vector3:
	var w := half_width(y, lm)
	var ax := clampf(x / maxf(w, 0.001), -1.0, 1.0)
	var a := acos(ax)
	var n := Vector3(cos(a), 0.0, sin(a))
	return n.normalized()


static func half_width(y: float, lm: FaceLandmarks) -> float:
	# Species head radius. Driven by the temple width (which the genome already
	# scales/pinches), floored so narrow species still read as a head.
	var base := maxf(absf(lm.temple_l.x), absf(lm.temple_r.x)) * 0.9
	base = maxf(base, 0.28)
	var centre := (lm.crown.y + lm.chin.y) * 0.5
	var half_h := maxf((lm.chin.y - lm.crown.y) * 0.5, 0.001)
	var rel := clampf((y - centre) / (half_h * 1.1), -1.0, 1.0)
	# Smooth egg profile: widest near the eyes, gently tapering top and chin.
	return base * sqrt(maxf(0.05, 1.0 - rel * rel))


static func _emit_tri(md: MeshData, a: Vector3, b: Vector3, c: Vector3, albedo: Color) -> void:
	# Flat shading: emit 3 unique verts with the face normal.
	var n := (b - a).cross(c - a).normalized()

	# Bake a soft directional light into the vertex colour. Materials consume the
	# vertex colour as albedo (unshaded), so this is the whole look — no
	# double-darkening, no dependence on scene lights.
	var light_dir := Vector3(0.35, -0.35, 0.9).normalized()
	var fac := clampf(n.dot(light_dir), 0.0, 1.0)
	var light := 0.14 + fac * 0.86
	var final_col := Color(albedo.r * light, albedo.g * light, albedo.b * light, albedo.a)

	var uv_a := Vector2(a.x + 0.5, a.y + 0.5)
	var uv_b := Vector2(b.x + 0.5, b.y + 0.5)
	var uv_c := Vector2(c.x + 0.5, c.y + 0.5)

	var base_idx := md.verts.size()
	md.verts.append(a)
	md.verts.append(b)
	md.verts.append(c)
	md.normals.append(n)
	md.normals.append(n)
	md.normals.append(n)
	md.uvs.append(uv_a)
	md.uvs.append(uv_b)
	md.uvs.append(uv_c)
	md.colors.append(final_col)
	md.colors.append(final_col)
	md.colors.append(final_col)
	md.indices.append(base_idx)
	md.indices.append(base_idx + 1)
	md.indices.append(base_idx + 2)
