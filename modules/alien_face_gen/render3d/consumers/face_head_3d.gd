class_name FaceHead3D extends Node3D

var _mesh_instance: MeshInstance3D
var _sprite: Sprite3D
var _current_lod: int = Lod.LOD_STANDARD


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	
	_sprite = Sprite3D.new()
	_sprite.visible = false
	add_child(_sprite)


func set_mesh_data(md: MeshData, style: StyleBase3D, palette: FacePalette, genome: FaceGenome) -> void:
	if _mesh_instance == null:
		_ensure_children()
	var mesh := ArrayMeshBuilder.build(md, style, palette, genome)
	_mesh_instance.mesh = mesh
	_sprite.visible = false


func _ensure_children() -> void:
	if _mesh_instance != null:
		return
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_sprite = Sprite3D.new()
	_sprite.visible = false
	add_child(_sprite)


func set_lod(lod: int) -> void:
	_current_lod = lod
	if lod == Lod.LOD_GLYPH:
		_mesh_instance.visible = false
		_sprite.visible = true
	else:
		_mesh_instance.visible = true
		_sprite.visible = false


func set_billboard_texture(texture: Texture2D) -> void:
	_sprite.texture = texture
