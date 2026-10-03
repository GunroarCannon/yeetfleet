## DifficultyLab: the workbench page for [Difficulty] — the [DifficultyPanel]
## full-screen, with a way back to the launcher. Saving writes the JSON the
## whole game (menus, level maker, flight) reads.
class_name DifficultyLab
extends Control


func _enter_tree() -> void:
	StyleManager.instance().load_saved()
	get_window().theme = BuilderTheme.build()
	BuilderTheme.apply_density_scale(get_window())


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BuilderTheme.bg_deep()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var panel := DifficultyPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.closed.connect(_back)
	margin.add_child(panel)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_back()


func _back() -> void:
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("menu") if Session.boot_requested else "res://modules/core/core.tscn")
