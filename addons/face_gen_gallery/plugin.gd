@tool
extends EditorPlugin

var dock: Control = null


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Load and instantiate the gallery dock
	var dock_scene = load("res://addons/face_gen_gallery/gallery_dock.gd")
	if dock_scene:
		dock = dock_scene.new()
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
