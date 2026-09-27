## ChevronArrow3D: a glowing arrow of scrolling chevrons laid in the 3D world —
## the swipe profile's heading and the slingshot's launch aim.
##
## A flat ribbon from [param from] to [param to] that turns about its own
## length to face the camera, so it reads at any angle while still pointing
## through real 3D space (it shrinks with distance and foreshortens). The look
## is all in `chevron_arrow.gdshader`; this only places it.
class_name ChevronArrow3D
extends MeshInstance3D

const SHADER := preload("res://modules/flight/shaders/chevron_arrow.gdshader")

var _mat := ShaderMaterial.new()


func _init() -> void:
	name = "ChevronArrow"
	mesh = _ribbon()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed every frame from interpolated positions: no second interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false


## Lay the arrow from [param from] to [param to], [param width] metres wide,
## facing [param cam]. [param strength] 0..1 scales its glow.
func place(from: Vector3, to: Vector3, width: float, cam: Camera3D, tint: Color, strength := 1.0) -> void:
	var dir := to - from
	var length := dir.length()
	if cam == null or length < 0.01 or width <= 0.0 or strength <= 0.001:
		visible = false
		return
	var fwd := dir / length
	var to_cam := cam.global_position - (from + to) * 0.5
	var side := fwd.cross(to_cam)
	if side.length_squared() < 1e-8:
		side = cam.global_transform.basis.x
	side = side.normalized()
	var normal := side.cross(fwd).normalized()
	global_transform = Transform3D(Basis(side * width, normal, -fwd * length), from)
	_mat.set_shader_parameter("length_ratio", length / width)
	_mat.set_shader_parameter("color", tint)
	_mat.set_shader_parameter("intensity", strength)
	visible = true


func hide_arrow() -> void:
	visible = false


## A unit ribbon: 1 wide along X, from z = 0 (tail, UV.y 0) to z = -1 (tip).
static func _ribbon() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0),
		Vector3(0.5, 0.0, -1.0), Vector3(-0.5, 0.0, -1.0),
	])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Stretched by its transform every frame; never let the tiny unit box cull it.
	m.custom_aabb = AABB(Vector3(-0.5, -0.5, -1.0), Vector3(1.0, 1.0, 1.0))
	return m
