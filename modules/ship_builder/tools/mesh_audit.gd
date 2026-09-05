## Geometry audit: finds inside-out and open geometry, the two causes of parts
## that look see-through under back-face culling.
##
##     godot --headless --path . --script modules/ship_builder/tools/mesh_audit.gd
extends SceneTree


func _initialize() -> void:
	var library := PartLibrary.new()
	library.load_all()
	print("── Mesh audit ────────────────────────────────────────────")
	var ids := []
	for id: Variant in library.parts:
		ids.append(String(id))
	ids.sort()
	for id: String in ids:
		var part := library.get_part(id)
		var built := PartMeshFactory.build(part, false)
		_audit(id, built.mesh)
	quit(0)


func _audit(id: String, mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() == 0:
		print("  %-22s EMPTY" % id)
		return
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tris := v.size() / 3

	# Signed volume of the whole soup. Negative means net inside-out.
	var vol := 0.0
	var inward := 0
	var degenerate := 0
	var normal_mismatch := 0
	# Edge parity: an edge used by an odd count means a hole.
	var edges := {}
	var centroid := Vector3.ZERO
	for p in v:
		centroid += p
	centroid /= float(maxi(v.size(), 1))

	for t in tris:
		var a := v[t * 3]
		var b := v[t * 3 + 1]
		var c := v[t * 3 + 2]
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-12:
			degenerate += 1
			continue
		vol += (a - centroid).dot((b - centroid).cross(c - centroid)) / 6.0
		# Does the stored normal agree with the winding?
		if cr.normalized().dot(n[t * 3]) < 0.9:
			normal_mismatch += 1
		# Does the winding point away from the mesh centroid?
		var fc := (a + b + c) / 3.0
		if cr.normalized().dot((fc - centroid).normalized()) < -0.15:
			inward += 1
		for pair in [[a, b], [b, c], [c, a]]:
			var k := "%.4v|%.4v" % [pair[0], pair[1]]
			var rk := "%.4v|%.4v" % [pair[1], pair[0]]
			if edges.has(rk):
				edges[rk] = int(edges[rk]) - 1
				if int(edges[rk]) == 0:
					edges.erase(rk)
			else:
				edges[k] = int(edges.get(k, 0)) + 1
	var open_edges := 0
	for k: Variant in edges:
		open_edges += absi(int(edges[k]))

	var flags := []
	if vol < 0.0:
		flags.append("NET-INSIDE-OUT")
	if normal_mismatch > 0:
		flags.append("normal!=winding:%d" % normal_mismatch)
	if inward > 0:
		flags.append("inward:%d/%d" % [inward, tris])
	if open_edges > 0:
		flags.append("open-edges:%d" % open_edges)
	if degenerate > 0:
		flags.append("degen:%d" % degenerate)
	print("  %-22s tris:%-5d vol:%+8.3f  %s" % [
		id, tris, vol, "ok" if flags.is_empty() else " ".join(flags)
	])
