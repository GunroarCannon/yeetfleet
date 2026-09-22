class_name VectorGrid
extends Node3D

## Warped Neon Vector Grid backdrop node for Vector Arcade / Wireframe mode.
## Spans across deep space and projects an undulating spacetime grid.

const SHADER_PATH := "res://modules/style/assets/vector_grid.gdshader"

var _mesh_inst: MeshInstance3D = null
var _material: ShaderMaterial = null


static func create(radius: float = 12000.0) -> Node3D:
	var script := load("res://modules/style/scripts/vector_grid.gd") as GDScript
	var vg: Node3D = script.new()
	vg.name = "VectorGridBackdrop"
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * (radius * 2.4)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var shader := load(SHADER_PATH) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = -15
		mi.material_override = mat
		vg._material = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = radius * 2.0
	vg.add_child(mi)
	vg._mesh_inst = mi
	return vg


func set_brightness(val: float) -> void:
	if _material != null:
		_material.set_shader_parameter("brightness", val)


func set_warp(val: float) -> void:
	if _material != null:
		_material.set_shader_parameter("warp_intensity", val)
