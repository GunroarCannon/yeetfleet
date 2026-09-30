## GoalPointer3D: one chunky 3D arrowhead riding at the top-centre of the
## view, turning in 3D to point at the current objective — through the
## screen when the goal is ahead, round to the side or back toward the
## camera when it is behind.
##
## A child of the camera, so it never lags a frame behind the view; its size
## is kept to a fixed share of the screen whatever the field of view. Drawn
## over the world (no depth test) and lit, so it reads as a solid object,
## not a HUD sticker. [method point_at] each frame; [method hide_pointer]
## when there is nothing to point at.
class_name GoalPointer3D
extends Node3D

## Where it sits: this far down from the top of the view (share of height).
const SCREEN_Y := 0.25
## Its length as a share of the view's height.
const SCREEN_SIZE := 0.085
## Metres in front of the camera (near, so nothing in the world is between).
const DEPTH := 3.0
## Goals straight ahead point partly up the screen instead of dead into it,
## so the head never shows as a bare dot.
const FLATTEN := 0.55

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _arrowhead()
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.25, 0.6, 1.0)
	_mat.emission_enabled = true
	_mat.emission = Color(0.1, 0.35, 1.0)
	_mat.emission_energy_multiplier = 1.4
	_mat.roughness = 0.35
	_mat.no_depth_test = true
	_mat.render_priority = 40
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var ink := MeshInstance3D.new()
	ink.mesh = _mesh.mesh
	var ink_mat := StandardMaterial3D.new()
	ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink_mat.albedo_color = Color(0.03, 0.02, 0.08)
	ink_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	ink_mat.no_depth_test = true
	ink_mat.render_priority = 39
	ink_mat.grow = true
	ink_mat.grow_amount = 0.07
	ink.material_override = ink_mat
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ink)
	visible = false


## Point from [param from] at [param goal] (world), seen by [param cam] (the
## parent camera). [param col] tints it.
func point_at(cam: Camera3D, from: Vector3, goal: Vector3, delta: float, col := Color(0.25, 0.6, 1.0)) -> void:
	var to := goal - from
	if to.length() < 1.0 or cam == null:
		hide_pointer()
		return
	_t += delta
	var half := tan(deg_to_rad(cam.fov) * 0.5)
	position = Vector3(0.0, DEPTH * half * (1.0 - 2.0 * SCREEN_Y), -DEPTH)
	var size := DEPTH * half * 2.0 * SCREEN_SIZE * (1.0 + 0.06 * sin(_t * 5.0))
	var local := cam.global_basis.orthonormalized().inverse() * to.normalized()
	local.z *= FLATTEN
	if local.length() < 1e-3:
		local = Vector3.UP
	local = local.normalized()
	var up := Vector3.BACK if absf(local.dot(Vector3.BACK)) < 0.95 else Vector3.UP
	var want := Basis.looking_at(local, up)
	if not visible:
		basis = want
	else:
		basis = Basis(basis.orthonormalized().get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-14.0 * delta)))
	basis = basis.scaled(Vector3.ONE * size)
	_mat.albedo_color = col
	_mat.emission = col * 0.8
	visible = true


func hide_pointer() -> void:
	visible = false


## A fat dart pointing down -Z, one unit long: a tip, two swept-back barbs and
## a notch between them, with thickness so it turns like a solid thing.
static func _arrowhead() -> ArrayMesh:
	var tip := Vector3(0, 0, -0.6)
	var wl := Vector3(-0.42, 0, 0.4)
	var wr := Vector3(0.42, 0, 0.4)
	var notch := Vector3(0, 0, 0.12)
	var top := Vector3(0, 0.14, -0.05)
	var bot := Vector3(0, -0.14, -0.05)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each face as a fan off the ridge (top) or keel (bottom): tip, barbs, notch.
	var rim: Array[Vector3] = [tip, wr, notch, wl]
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		_tri(st, top, a, b)
		_tri(st, bot, b, a)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
