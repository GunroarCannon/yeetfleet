class_name FaceRNG extends RefCounted

enum Stream { SKULL, EYES, NOSE, MOUTH, BROW_EAR, CREST, SURFACE, GEAR, COLOR, GLOBAL }

var _base: int

# splitmix64 constants. Godot ints are signed 64-bit, so the usual unsigned
# literals (0xff51afd7ed558ccd etc.) overflow and cannot be parsed. Their
# two's-complement negatives have the same low 64 bits, which is all a
# wrap-around multiply uses, so the hash is bit-identical to the original.
const _M1 := -49064778989728563   # 0xff51afd7ed558ccd
const _M2 := -4265267296055464877  # 0xc4ceb9fe1a85ec53
const _GAMMA := -7046029254386353131  # 0x9e3779b97f4a7c15

func _init(species_id: StringName, seed_value: int) -> void:
	_base = mix64(hash(String(species_id)) ^ mix64(seed_value))

static func mix64(x: int) -> int:
	x = (x ^ (x >> 33)) * _M1
	x = (x ^ (x >> 33)) * _M2
	return x ^ (x >> 33)

func stream(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = mix64(_base ^ mix64(s * _GAMMA))
	return r
