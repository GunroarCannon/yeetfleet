class_name StyleBase2D extends RefCounted


func style_id() -> StringName:
	return &"base"


func silhouette_defining_slots() -> Array[StringName]:
	return []


func background(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	pass


func draw_feature(slot: StringName, dl: DrawList, g: FaceGenome, lm: FaceLandmarks,
		p: FacePalette, lod: int) -> void:
	pass


func post(dl: DrawList, g: FaceGenome, p: FacePalette, lod: int) -> void:
	pass
