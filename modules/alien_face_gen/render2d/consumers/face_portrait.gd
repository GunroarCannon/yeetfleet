class_name FacePortrait extends Control

var _sub_viewport: SubViewport
var _canvas_drawer: CanvasDrawer
var _draw_list: DrawList = null
var _expression: StringName = &"neutral"
var _talking: bool = false
var _talking_phase: int = 0
var _lod: int = Lod.LOD_STANDARD


func _ready() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(256, 256)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sub_viewport.transparent_bg = true
	add_child(_sub_viewport)
	
	_canvas_drawer = CanvasDrawer.new()
	_sub_viewport.add_child(_canvas_drawer)
	_canvas_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)


func set_draw_list(dl: DrawList) -> void:
	_draw_list = dl
	_canvas_drawer.draw_list = dl
	_canvas_drawer.queue_redraw()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_expression(expr: StringName) -> void:
	_expression = expr


func set_talking(enabled: bool) -> void:
	_talking = enabled
	if _talking:
		_talking_phase = 0


func set_lod(lod: int) -> void:
	_lod = lod


func get_texture() -> Texture2D:
	return _sub_viewport.get_texture()
