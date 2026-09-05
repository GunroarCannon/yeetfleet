## The selected part: what it is, how it is posed, how it is painted.
##
## Rebuilt from scratch on every selection change. That is a deliberate trade: a
## few dozen controls are nothing next to a mesh rebuild, and it removes the entire
## class of bug where a slider still holds the previous part's limits.
##
## Every control here writes through [BuilderRoot], never into the design directly,
## and continuous controls (sliders, colour pickers) wrap their drag in a history
## transaction so scrubbing a wing sweep is one undo step rather than four hundred.
class_name PartInspector
extends VBoxContainer

## Slider rows to build per joint axis: pose key, label, unit, and the predicate
## that says whether this joint actually allows it.
const AXES: Array[Dictionary] = [
	{"key": "yaw", "label": "Swivel", "unit": "°"},
	{"key": "pitch", "label": "Tilt", "unit": "°"},
	{"key": "roll", "label": "Bank", "unit": "°"},
	{"key": "slide", "label": "Slide", "unit": " m"},
	{"key": "scale", "label": "Scale", "unit": "×"},
]

var _root: BuilderRoot
var _body: VBoxContainer
var _dragging := false


func _ready() -> void:
	_root = owner as BuilderRoot
	var header := Label.new()
	header.text = "SELECTED PART"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(header)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	add_child(_body)

	_root.selection_changed.connect(func(_p: String) -> void: refresh())
	_root.design_rebuilt.connect(func(_v: ShipView) -> void: refresh())


func refresh() -> void:
	if _root == null:
		return
	for child in _body.get_children():
		child.queue_free()
	var placement := _root.selected_placement()
	if placement == null:
		_add_hint("Nothing selected.\nClick a part in the viewport, or pick a mount from the list above.")
		return
	_add_identity(placement)
	_add_pose(placement)
	_add_symmetry(placement)
	_add_paint(placement)
	_add_actions(placement)


func _add_hint(text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_body.add_child(hint)


func _add_identity(placement: Placement) -> void:
	var title := Label.new()
	title.text = placement.part.display_name
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(title)

	var bits: Array[String] = [placement.part.category_label(), placement.part.size_class]
	if placement.socket != null:
		bits.append("in " + (placement.socket.display_name if placement.socket.display_name != "" else placement.socket.id))
	var subtitle := Label.new()
	subtitle.text = " · ".join(bits)
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", BuilderTheme.text_dim())
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(subtitle)

	if placement.part.description != "":
		var desc := Label.new()
		desc.text = placement.part.description
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", BuilderTheme.text_dim())
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(desc)


# --- Joint -----------------------------------------------------------------

func _add_pose(placement: Placement) -> void:
	if placement.is_chassis():
		return
	var joint := _joint_for(placement)
	var row := HBoxContainer.new()
	_body.add_child(row)
	var caption := Label.new()
	caption.text = "ARTICULATION"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(caption)

	if joint == null or not joint.is_articulated():
		var rigid := Label.new()
		rigid.text = "Rigid mount — bolted in place."
		rigid.add_theme_font_size_override("font_size", 11)
		rigid.add_theme_color_override("font_color", BuilderTheme.text_dim())
		rigid.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(rigid)
		return

	var reset := Button.new()
	reset.text = "Reset"
	reset.add_theme_font_size_override("font_size", 11)
	reset.tooltip_text = "Return this part to its neutral pose"
	var reset_path := placement.editable_path()
	reset.pressed.connect(func() -> void: _root.reset_pose(reset_path))
	row.add_child(reset)

	for axis in AXES:
		var key := String(axis["key"])
		var range_v := _range_for(joint, key)
		if is_equal_approx(range_v.x, range_v.y):
			continue
		_add_slider(placement, key, String(axis["label"]), String(axis["unit"]), range_v)

	if placement.mirrored and joint.mirror_negates_yaw and joint.has_yaw():
		var mirror_note := Label.new()
		mirror_note.text = "Swivel is mirrored on this side, so the pair stays symmetric."
		mirror_note.add_theme_font_size_override("font_size", 10)
		mirror_note.add_theme_color_override("font_color", BuilderTheme.text_dim())
		mirror_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(mirror_note)


## Mirror sockets share the source socket's limits, which is what keeps a broken
## symmetry pair posable within the same envelope as its twin.
func _joint_for(placement: Placement) -> PartJoint:
	if placement.socket == null:
		return null
	if placement.socket.is_mirror() and placement.parent_path != "":
		var parent := _root.placement_at(placement.parent_path)
		if parent != null:
			var source := parent.part.get_socket(placement.socket.mirror_of)
			if source != null and source.joint != null:
				return source.joint
	return placement.socket.joint


static func _range_for(joint: PartJoint, key: String) -> Vector2:
	match key:
		"yaw": return joint.yaw_range
		"pitch": return joint.pitch_range
		"roll": return joint.roll_range
		"slide": return joint.slide_range
		"scale": return joint.scale_range
		_: return Vector2.ZERO


func _add_slider(placement: Placement, key: String, label: String, unit: String, range_v: Vector2) -> void:
	var path := placement.editable_path()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_body.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 11)
	top.add_child(name_label)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", BuilderTheme.accent())
	top.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minf(range_v.x, range_v.y)
	slider.max_value = maxf(range_v.x, range_v.y)
	slider.step = 0.01 if key == "scale" else (0.02 if key == "slide" else 0.5)
	slider.value = placement.attachment.get_pose_value(key)
	# A slider is a 4px-tall grab handle by default, which is unusable on a phone
	# and awkward with a trackpad. Give it a real target.
	slider.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 16
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "%s: %.2f to %.2f%s" % [label, slider.min_value, slider.max_value, unit]
	box.add_child(slider)

	var formatter := func(v: float) -> String:
		if key == "scale":
			return "%.2f%s" % [v, unit]
		if unit == "°":
			return "%+.0f%s" % [v, unit]
		return "%+.2f%s" % [v, unit]
	value_label.text = String(formatter.call(slider.value))

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = String(formatter.call(v))
		_root.set_pose(path, key, v, _dragging)
	)
	slider.drag_started.connect(func() -> void:
		_dragging = true
		_root.begin_continuous("Pose " + placement.part.display_name)
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		_root.end_continuous()
	)


# --- Symmetry --------------------------------------------------------------

func _add_symmetry(placement: Placement) -> void:
	if placement.is_chassis() or placement.socket == null:
		return
	var is_pair := placement.socket.is_mirror() or placement.shadow_root != "" \
		or _has_mirror_twin(placement)
	if not is_pair:
		return

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BuilderTheme.flat(BuilderTheme.panel_alt_bg(), BuilderTheme.border(), 4))
	_body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	box.add_child(status)

	var button := Button.new()
	button.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
	box.add_child(button)
	var path := placement.path

	if placement.shadow or placement.shadow_root != "":
		status.text = "Mirrored pair — both sides share this fit."
		status.add_theme_color_override("font_color", BuilderTheme.text_dim())
		button.text = "Break symmetry"
		button.tooltip_text = "Give this side its own part, pose and paint (M)"
		button.pressed.connect(func() -> void: _root.break_symmetry(path))
	elif placement.socket.is_mirror():
		status.text = "This side is independent of its twin."
		status.add_theme_color_override("font_color", BuilderTheme.warn())
		button.text = "Restore symmetry"
		button.tooltip_text = "Discard this side's part and follow the other side again (M)"
		button.pressed.connect(func() -> void: _root.restore_symmetry(path))
	else:
		status.text = "Fitted here, mirrored to the other side automatically."
		status.add_theme_color_override("font_color", BuilderTheme.text_dim())
		button.text = "Break symmetry on far side"
		button.tooltip_text = "Let the mirrored side carry a different part"
		button.pressed.connect(func() -> void: _root.toggle_symmetry_at(path))


## True when the parent part declares a socket that mirrors this one, i.e. fitting
## here filled two mounts.
func _has_mirror_twin(placement: Placement) -> bool:
	if placement.parent_path == "" and placement.path == "":
		return false
	var parent := _root.placement_at(placement.parent_path)
	if parent == null:
		return false
	for socket in parent.part.sockets:
		if socket.mirror_of == placement.socket.id:
			return true
	return false


# --- Paint -----------------------------------------------------------------

func _add_paint(placement: Placement) -> void:
	var caption := Label.new()
	caption.text = "PART PAINT"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_body.add_child(caption)

	var hint := Label.new()
	hint.text = "Overrides the ship palette for this part only."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", BuilderTheme.text_dim())
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hint)

	var path := placement.editable_path()
	var overrides: Dictionary = placement.attachment.color_overrides
	for channel in ShipDesign.CHANNELS:
		var row := HBoxContainer.new()
		_body.add_child(row)
		var label := Label.new()
		label.text = String(ShipDesign.CHANNEL_LABELS.get(channel, channel))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		var overridden: bool = overrides.has(channel)
		label.add_theme_color_override(
			"font_color", BuilderTheme.accent() if overridden else BuilderTheme.text_dim()
		)
		row.add_child(label)

		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(52, BuilderTheme.TOUCH_MIN - 14)
		picker.edit_alpha = false
		picker.color = overrides.get(channel, _root.design.get_color(channel))
		picker.tooltip_text = "Paint this part's %s channel" % channel
		row.add_child(picker)
		picker.color_changed.connect(func(c: Color) -> void:
			_root.set_part_color(path, channel, c, true)
		)
		picker.pressed.connect(func() -> void:
			_root.begin_continuous("Paint " + placement.part.display_name)
		)
		picker.popup_closed.connect(func() -> void: _root.end_continuous())

		var clear := Button.new()
		clear.text = "↺"
		clear.disabled = not overridden
		clear.custom_minimum_size = Vector2(30, 0)
		clear.tooltip_text = "Use the ship palette for this channel"
		clear.pressed.connect(func() -> void: _root.clear_part_color(path, channel))
		row.add_child(clear)


# --- Actions ---------------------------------------------------------------

func _add_actions(placement: Placement) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BuilderTheme.GAP)
	_body.add_child(row)

	if not placement.is_chassis():
		var parent_button := Button.new()
		parent_button.text = "Parent"
		parent_button.tooltip_text = "Select the part this is mounted on (\\)"
		parent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent_button.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
		parent_button.pressed.connect(_root.select_parent)
		row.add_child(parent_button)

		var remove := Button.new()
		remove.text = "Remove"
		remove.tooltip_text = "Detach this part and everything on it (Delete)"
		remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		remove.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
		remove.add_theme_color_override("font_color", BuilderTheme.bad())
		remove.mouse_entered.connect(func() -> void: _root.preview_removal(placement.path))
		remove.mouse_exited.connect(_root.clear_preview)
		remove.pressed.connect(_root.remove_selected)
		row.add_child(remove)
	else:
		var strip := Button.new()
		strip.text = "Strip to bare hull"
		strip.tooltip_text = "Remove every fitted part, keeping the chassis"
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
		strip.pressed.connect(_root.strip_design)
		row.add_child(strip)
