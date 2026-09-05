## Trauma-based screen shake: sources add trauma, trauma decays, and displacement
## is trauma squared times amplitude. The squaring is what makes a small hit read
## as small and a big hit read as big — twelve guns firing at once do not produce
## twelve times the shake, because trauma itself is clamped to 1 well before that.
##
## Translation and rotation are sampled from independent, out-of-phase noise
## channels so the two never lock into a visible repeating pattern, and rotation
## carries most of the amplitude on purpose: translating a chase camera at flight
## speed reads as a glitch, rotating it reads as an impact.
##
## A directional kick (recoil, an impact from a known direction) rides on top as
## its own critically-damped offset, decaying independently and faster than
## trauma, so a shot's recoil punts the view and lets go rather than blending
## into the general rattle.
class_name JuiceShake
extends RefCounted

const TRAUMA_DECAY := 1.8
const TRAUMA_EPSILON := 0.001

const KICK_DECAY := 7.0
const KICK_EPSILON := 0.001

const FREQUENCY := 14.0

## Metres. Deliberately small — see the class doc comment.
const MAX_TRANSLATE := Vector3(0.35, 0.35, 0.18)
## Radians.
const MAX_ROTATE := Vector3(deg_to_rad(4.0), deg_to_rad(5.5), deg_to_rad(3.0))
## 2D HUD shake, in pixels, driven by the same trauma so a hit rattles the whole
## frame and not just the 3D view.
const MAX_OFFSET_2D := Vector2(10.0, 7.0)

var trauma := 0.0

var _kick := Vector3.ZERO
var _time := 0.0
var _noise_a := FastNoiseLite.new()
var _noise_b := FastNoiseLite.new()


func _init() -> void:
	_noise_a.seed = 1901
	_noise_b.seed = 4027


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_kick(world_dir: Vector3, strength: float) -> void:
	if world_dir.length_squared() < 0.0001:
		return
	_kick -= world_dir.normalized() * strength


func update(delta: float) -> void:
	_time += delta
	trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	if trauma < TRAUMA_EPSILON:
		trauma = 0.0
	_kick = _kick.lerp(Vector3.ZERO, clampf(KICK_DECAY * delta, 0.0, 1.0))
	if _kick.length() < KICK_EPSILON:
		_kick = Vector3.ZERO


func offset_3d() -> Vector3:
	var amount := trauma * trauma
	if amount <= 0.0 and _kick == Vector3.ZERO:
		return Vector3.ZERO
	var t := _time * FREQUENCY
	return Vector3(
		_noise_a.get_noise_1d(t) * MAX_TRANSLATE.x,
		_noise_b.get_noise_1d(t + 41.0) * MAX_TRANSLATE.y,
		_noise_a.get_noise_1d(t + 83.0) * MAX_TRANSLATE.z
	) * amount + _kick


func rotation_3d() -> Vector3:
	var amount := trauma * trauma
	if amount <= 0.0:
		return Vector3.ZERO
	var t := _time * FREQUENCY
	return Vector3(
		_noise_b.get_noise_1d(t + 17.0) * MAX_ROTATE.x,
		_noise_a.get_noise_1d(t + 59.0) * MAX_ROTATE.y,
		_noise_b.get_noise_1d(t + 97.0) * MAX_ROTATE.z
	) * amount


func offset_2d() -> Vector2:
	var amount := trauma * trauma
	if amount <= 0.0:
		return Vector2.ZERO
	var t := _time * FREQUENCY
	return Vector2(
		_noise_a.get_noise_1d(t + 131.0) * MAX_OFFSET_2D.x,
		_noise_b.get_noise_1d(t + 173.0) * MAX_OFFSET_2D.y
	) * amount


func reset() -> void:
	trauma = 0.0
	_kick = Vector3.ZERO
