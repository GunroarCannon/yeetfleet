class_name StyleBase3D extends RefCounted


func style_id() -> StringName:
	return &"base_3d"


func build_feature(slot: StringName, md: MeshData, g: FaceGenome, lm: FaceLandmarks,
		p: FacePalette, lod: int) -> void:
	pass


func material_for(hint: StringName, p: FacePalette, g: FaceGenome) -> Material:
	return StandardMaterial3D.new()
