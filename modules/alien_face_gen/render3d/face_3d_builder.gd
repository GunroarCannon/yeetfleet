class_name Face3DBuilder


static func build(g: FaceGenome, lm: FaceLandmarks, p: FacePalette,
		style: StyleBase3D, lod: int) -> MeshData:
	var md := MeshData.new()
	var culled := Lod.culled_slots(lod)
	
	# Shell first
	var shell := ShellLattice.build(lm, g, style, lod, p)
	md.merge(shell)
	
	# Then each non-culled feature
	if &"eye_sclera" not in culled and g.eye_present:
		var eyes := FeatureMeshes.build_eyes(lm, g, p)
		md.merge(eyes)
	
	if &"nose" not in culled and g.nose_present:
		var nose := FeatureMeshes.build_nose(lm, g, p)
		md.merge(nose)
	
	if &"mouth" not in culled and g.mouth_present:
		var mouth := FeatureMeshes.build_mouth(lm, g, p)
		md.merge(mouth)
	
	if &"mandible" not in culled and g.mouth_present:
		var mandibles := FeatureMeshes.build_mandibles(lm, g, p)
		md.merge(mandibles)
	
	if &"crest" not in culled:
		var crest := FeatureMeshes.build_crest(lm, g, p)
		md.merge(crest)
	
	if &"ear" not in culled:
		var ears := FeatureMeshes.build_ears(lm, g, p)
		md.merge(ears)
	
	if &"headgear" not in culled:
		var headgear := FeatureMeshes.build_headgear(lm, g, p)
		md.merge(headgear)
	
	return md
