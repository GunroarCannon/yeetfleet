class_name Lod

const LOD_CINEMATIC := 0
const LOD_STANDARD := 1
const LOD_COMPACT := 2
const LOD_GLYPH := 3

const _CURVE_SAMPLES := [16, 10, 6, 3]

const _PX_SIZE := [512, 256, 96, 32]

const _MESH_RES := [
	Vector2i(12, 16),  # Cinematic: 12 rings × 16 segments
	Vector2i(9, 12),   # Standard
	Vector2i(6, 8),    # Compact
	Vector2i(1, 1)     # Glyph: billboard
]

# Features culled at each LOD tier (cumulative)
const _CULLED_SLOTS := {
	LOD_STANDARD: [&"wrinkle", &"scar", &"pore", &"plate_seam", &"tooth_detail",
		&"tongue", &"iris_gradient", &"garment_trim"],
	LOD_COMPACT: [&"nose", &"ear", &"brow", &"lip_thickness", &"marking_extra",
		&"crest_individual", &"collar_detail"],
	LOD_GLYPH: [&"cheek", &"eye_socket", &"eye_sclera", &"eye_iris", &"eye_pupil",
		&"nose", &"mouth", &"mandible", &"marking", &"headgear", &"ocular_gear",
		&"collar", &"neck", &"head_shade", &"ear_l", &"ear_r", &"brow_l", &"brow_r"]
}


static func curve_samples(lod: int) -> int:
	return _CURVE_SAMPLES[clampi(lod, 0, 3)]


static func px_size(lod: int) -> int:
	return _PX_SIZE[clampi(lod, 0, 3)]


static func mesh_res(lod: int) -> Vector2i:
	return _MESH_RES[clampi(lod, 0, 3)]


static func culled_slots(lod: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for tier in range(LOD_CINEMATIC, lod + 1):
		if _CULLED_SLOTS.has(tier):
			for slot in _CULLED_SLOTS[tier]:
				if slot not in result:
					result.append(slot)
	return result
