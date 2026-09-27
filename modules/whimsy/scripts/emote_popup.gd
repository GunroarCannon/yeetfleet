## EmotePopup: a one-shot reaction icon that pops out from a ship, shoots
## outward, fades, and frees itself.
##
## Built by [method Whimsy.emote], never by hand. Unlike [code]FaceSticker[/code]
## (a face glued flush to a hull surface, resting there indefinitely) this is a
## transient, always-camera-facing billboard that leaves the thing that spawned
## it behind -- replacing the old permanently-mounted ship face per playtest
## feedback: it read as an emote reacting to a moment, not a sticker.
extends Node3D

## World-space speed at launch, scaled by the popup's own size -- a bigger
## (mothership-scale) emote shoots off just as fast relative to itself as a
## small fighter's.
const LAUNCH_SPEED := 2.4
## How hard the launch velocity bleeds off, per second -- the popup drifts to
## a stop rather than flying off screen before it finishes fading.
const LAUNCH_DRAG := 1.6
const POP_IN_TIME := 0.12
## Fraction of the lifetime spent fully visible before the fade-out begins.
const HOLD_FRACTION := 0.35

var quad: MeshInstance3D = null

var _mat: ShaderMaterial = null
var _velocity := Vector3.ZERO
## The ship this emote pops off. The popup rides along with it (position only,
## so it stays upright while the hull rolls or tumbles), drifting outward from
## it by [member _offset]. It used to be left at a fixed world point, and a
## ship doing 100–500 m/s was tens of metres past it within a tenth of a
## second, so the player never saw their own emotes.
var follow: Node3D = null
var _offset := Vector3.ZERO
var _life := 1.0
var _age := 0.0
var _size := 1.0


func _init() -> void:
	quad = MeshInstance3D.new()
	quad.name = "Emote"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = Whimsy.face_shader()
	_mat.render_priority = 1
	_mat.set_shader_parameter("billboard", 1.0)
	_mat.set_shader_parameter("push", 0.0)
	quad.material_override = _mat
	quad.scale = Vector3.ZERO
	add_child(quad)


## Ride along with [param ship] from where the popup is now (see [member
## follow]). Call after placing the popup.
func ride_along(ship: Node3D) -> void:
	follow = ship
	_offset = global_position - ship.global_position


## Launch this popup. [param launch_dir] need not be normalised; [param size]
## is its world-space scale; [param lifetime] is seconds from pop-in to fully
## faded, at which point the node frees itself.
func launch(expression: String, launch_dir: Vector3, size: float, lifetime: float) -> void:
	var tex := Whimsy.face_texture(expression)
	if tex != null:
		_mat.set_shader_parameter("face_tex", tex)
	_size = maxf(size, 0.1)
	_life = maxf(lifetime, 0.1)
	var dir := launch_dir
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	_velocity = dir.normalized() * LAUNCH_SPEED * _size


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		_offset += _velocity * delta
		# The drawn (interpolated) position, so the icon doesn't shudder
		# against the hull between physics ticks.
		global_position = follow.get_global_transform_interpolated().origin + _offset
	else:
		global_position += _velocity * delta
	_velocity *= clampf(1.0 - LAUNCH_DRAG * delta, 0.0, 1.0)

	# Pop in fast, hold at full size/opacity, then fade -- scale and opacity
	# each ease on their own schedule so the icon reads clearly before it
	# starts dissolving, rather than shrinking and fading at the same time.
	var pop_t := clampf(_age / POP_IN_TIME, 0.0, 1.0)
	quad.scale = Vector3.ONE * _size * lerpf(0.2, 1.0, ease(pop_t, 0.3))

	var t := _age / _life
	var opacity := 1.0
	if t > HOLD_FRACTION:
		opacity = 1.0 - (t - HOLD_FRACTION) / (1.0 - HOLD_FRACTION)
	_mat.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
