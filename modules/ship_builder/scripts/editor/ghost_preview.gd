## The translucent preview of a part about to be fitted.
##
## Uses the same mesh the real part will use, not a box, because the whole point is
## to answer "will that actually fit there" before committing. Tinted cyan when the
## drop is legal and amber when it is not — the same pair used everywhere else in
## the module, and distinguishable without relying on hue alone since the invalid
## ghost also gets a wireframe cage.
class_name GhostPreview
extends Node3D

var _mesh_instance: MeshInstance3D
var _cage: MeshInstance3D
var _material: ShaderMaterial
var _invalid_material: ShaderMaterial
var _current_part: ShipPart = null
var _current_mirrored := false


func _ready() -> void:
	_material = ShipMaterials.make_ghost_material(true)
	_invalid_material = ShipMaterials.make_ghost_material(false)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GhostMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn after the ship so it always reads as an overlay rather than clipping
	# through whatever it is being offered to.
	_mesh_instance.sorting_offset = 1.0
	add_child(_mesh_instance)

	_cage = MeshInstance3D.new()
	_cage.name = "GhostCage"
	_cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cage.material_override = ShipMaterials.line_material(ShipMaterials.invalid_color())
	add_child(_cage)

	visible = false


## Show [param part] at [param xform]. [param valid] switches the tint and the
## cage.
func show_part(part: ShipPart, xform: Transform3D, valid: bool, mirrored := false) -> void:
	if part == null:
		clear()
		return
	if part != _current_part or mirrored != _current_mirrored:
		var built := PartMeshFactory.build(part, mirrored)
		_mesh_instance.mesh = built.mesh
		_cage.mesh = LowPoly.selection_brackets(built.aabb, 0.28)
		_current_part = part
		_current_mirrored = mirrored
	_mesh_instance.material_override = _material if valid else _invalid_material
	_cage.visible = not valid
	global_transform = xform
	visible = true


func show_invalid(part: ShipPart, xform: Transform3D) -> void:
	show_part(part, xform, false)


func clear() -> void:
	visible = false
	_current_part = null
