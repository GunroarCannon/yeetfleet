## The module launcher (modules/core/core.tscn): the front door of the project.
##
## Before this existed the run/main_scene was the ship builder and scene
## switching was four hardcoded paths scattered across three scene roots. Now
## the project boots here, [Session] reads the command line, and this node
## either jumps straight into the module `--module=<id>` named (the editor's
## main_run_args, so pressing Play still lands in the ship builder) or shows a
## picker built from [ModuleRegistry].
##
## The picker is deliberately a single centered column: the same layout has to
## serve a phone and a desktop, and a menu of three buttons needs no drawers or
## columns — it just needs to be tall enough to hit with a thumb, which
## [BuilderTheme]'s density scale arranges before this builds anything.
class_name CoreRoot
extends Control

## Half-width of the menu column in the project's density-corrected units.
## Wide enough that the longest module description wraps to two lines, narrow
## enough that a phone in either orientation keeps it comfortably on screen.
const COLUMN_WIDTH := 480.0


func _enter_tree() -> void:
	# The saved look and palette have to be live *before* the theme is built: the
	# interface's colours are palette roles, so a palette loaded after the theme
	# would leave the whole UI on the previous one until something rebuilt it.
	StyleManager.instance().load_saved()
	# The window theme and density scale must exist before any Control under
	# this root reads its theme, and they live on the window, not the scene.
	get_window().theme = BuilderTheme.build()
	BuilderTheme.apply_density_scale(get_window())
	get_viewport().size_changed.connect(
		func() -> void: BuilderTheme.apply_density_scale(get_window())
	)


func _ready() -> void:
	Session.start()
	if _try_auto_boot():
		return
	_build_picker()


## Jump straight into the module the command line named, if it named one.
## Returns false when there is nothing to boot (or the id is unknown), so the
## caller falls through to the picker.
func _try_auto_boot() -> bool:
	if not Session.boot_requested:
		return false
	var id := Session.boot_module
	var path := ModuleRegistry.scene_path(id)
	if path == "":
		print("[launcher] --module=%s names no module — showing the picker" % id)
		return false
	print("[launcher] booting module '%s' (%s)" % [id, path])
	get_tree().change_scene_to_file(path)
	return true


## Build the picker into this node. Everything is made in code because the
## registry is the source of the list, so a .tscn would just be this list
## frozen at authoring time — duplicate data with a second place to update.
func _build_picker() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = BuilderTheme.bg_deep()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 12)
	centre.add_child(stack)

	var title := _add_label("Project Nebula", 26, BuilderTheme.text_strong_color())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var subtitle := _add_label(
		"Pick a workbench. Each one keeps its own autosaves.",
		14, BuilderTheme.text_dim()
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(subtitle)

	stack.add_child(_spacer(10))

	for id in ModuleRegistry.ids():
		stack.add_child(_module_card(id))

	stack.add_child(_spacer(10))

	var hint := _add_label(
		"Run with --module=<id> to skip this screen — or give --seed=<n> to make a run reproducible.",
		12, BuilderTheme.text_dim()
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)

	var forced := " (forced)" if Session.seed_forced else ""
	var seed_line := _add_label(
		"Session seed %d%s" % [Session.seed, forced],
		12, BuilderTheme.text_dim().darkened(0.2)
	)
	seed_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(seed_line)


## A one-card row for a module: the name over a dimmed one-line description,
## the whole card one Button so the hover, focus and press states come from the
## theme for free. The labels let events through to the button underneath.
func _module_card(id: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(COLUMN_WIDTH, 64)
	card.tooltip_text = ModuleRegistry.scene_path(id)
	card.focus_mode = Control.FOCUS_ALL
	card.pressed.connect(func() -> void: _open_module(id))

	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.offset_left = 16.0
	lines.offset_right = -16.0
	lines.offset_top = 8.0
	lines.offset_bottom = -8.0
	lines.add_theme_constant_override("separation", 2)
	card.add_child(lines)

	var name := _add_label(ModuleRegistry.display_name(id), 17, BuilderTheme.text_strong_color())
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(name)

	var tagline := _add_label(ModuleRegistry.tagline(id), 12, BuilderTheme.text_dim())
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(tagline)

	return card


func _open_module(id: String) -> void:
	var path := ModuleRegistry.scene_path(id)
	if path == "":
		print("[launcher] no such module '%s'" % id)
		return
	print("[launcher] opening module '%s' (%s)" % [id, path])
	get_tree().change_scene_to_file(path)


func _add_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(px: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, px)
	return s
