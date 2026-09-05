extends SceneTree

func _initialize() -> void:
	# A loft matching _hull_spine: CCW chamfered_rect profile, rings from +Z to -Z.
	var lp := LowPoly.new()
	var profile := LowPoly.chamfered_rect(1.6, 1.1, 0.28)
	print("profile signed area (XY): ", _area(profile))
	var rings := []
	for s: Vector2 in [Vector2(0.50, 0.72), Vector2(0.30, 1.0), Vector2(-0.05, 0.97), Vector2(-0.30, 0.70), Vector2(-0.50, 0.30)]:
		rings.append(LowPoly.ring(profile, 6.0 * s.x, Vector2(s.y, s.y)))
	lp.add_loft(rings, LowPoly.CH_PRIMARY)
	var mesh := lp.commit("t")
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Loft axis is Z. For a wall face, outward is radial: away from the axis.
	var bad := 0
	var tris := v.size() / 3
	for t in tris:
		var a := v[t*3]; var b := v[t*3+1]; var c := v[t*3+2]
		var n := (b-a).cross(c-a)
		if n.length_squared() < 1e-12: continue
		n = n.normalized()
		var fc := (a+b+c)/3.0
		# Radial outward at this z (axis is x=y=0).
		var radial := Vector3(fc.x, fc.y, 0.0)
		if radial.length() < 0.05:
			continue  # a cap tri near the axis; skip
		if n.dot(radial.normalized()) < -0.2:
			bad += 1
			if bad <= 6:
				print("  INWARD wall tri at z=%.2f  n=%.2v radial=%.2v" % [fc.z, n, radial.normalized()])
	print("inward wall tris: %d / %d" % [bad, tris])
	quit(0)

func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i+1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5
