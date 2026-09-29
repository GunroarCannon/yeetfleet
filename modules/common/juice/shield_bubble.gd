## ShieldBubble: the see-through blue sphere round a shielded ship.
##
## The player's shield power-up and an enemy's shield veil both use it: it
## grows in, flashes when the shield soaks a hit (only when
## [member PerformanceSettings.shield_ripples] is on — the per-hit ripple is a
## performance setting), and pops out when the shield breaks or runs out.
## A low-poly sphere (see the mote lesson in the perf notes): 24 × 12.
class_name ShieldBubble
extends MeshInstance3D

const SHADER := preload("res://modules/common/juice/shaders/shield_bubble.gdshader")
## Seconds to grow in / pop out.
const GROW_TIME := 0.35
const POP_TIME := 0.3

var _mat: ShaderMaterial
var _flash := 0.0


## A bubble of [param radius] metres, tinted [param tint], hung under
## [param parent] (a ship's hull node, so it rides along and interpolates
## with it).
## [param strength] scales how opaque it is (the player's own reads stronger).
static func attach(parent: Node3D, radius: float, tint := Color(0.35, 0.72, 1.0), strength := 1.0) -> ShieldBubble:
	var b := ShieldBubble.new()
	b.name = "ShieldBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	b.mesh = sphere
	b._mat = ShaderMaterial.new()
	b._mat.shader = SHADER
	b._mat.set_shader_parameter("tint", tint)
	b._mat.set_shader_parameter("base_alpha", 0.07 * strength)
	b._mat.set_shader_parameter("rim_alpha", minf(0.6 * strength, 1.0))
	b._mat.set_shader_parameter("band_alpha", 0.05 * strength)
	b.material_override = b._mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.scale = Vector3.ONE * 0.01
	parent.add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3.ONE * radius, GROW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return b


## The shield soaked a hit: a brief brighten, if ripples are on.
func hit_flash() -> void:
	PerformanceSettings.ensure_loaded()
	if not PerformanceSettings.shield_ripples:
		return
	_flash = 1.0
	set_process(true)


## Grow a little, fade and free.
func pop_out() -> void:
	if is_queued_for_deletion() or has_meta("popping"):
		return
	set_meta("popping", true)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", scale * 1.35, POP_TIME).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_fade, 1.0, 0.0, POP_TIME)
	tw.chain().tween_callback(queue_free)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_mat.set_shader_parameter("flash", _flash)
	if _flash <= 0.0:
		set_process(false)


func _set_fade(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("fade", v)
