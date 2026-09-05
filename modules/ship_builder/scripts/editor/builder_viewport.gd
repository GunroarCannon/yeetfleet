## The 3D view: picking, camera control, and the drop target for parts dragged out
## of the palette.
##
## A [SubViewportContainer] rather than a bare [Camera3D] over the whole window, so
## the 3D area is exactly the rectangle between the panels. That matters for
## picking (screen coordinates map straight into the viewport) and for framing (a
## ship centred in the viewport is centred in the space the player can see, not
## hidden behind the inspector).
##
## Input is deliberately mode-based rather than modifier-based. A hidden
## "ctrl-drag to articulate" would be undiscoverable and impossible on a
## touchscreen, so the drag mode is a visible three-way toggle and every mode is
## reachable with one tap.
class_name BuilderViewport
extends SubViewportContainer

## What a left-drag starting on a part does.
enum DragMode {
	## Drag orbits the camera; parts are only selected by tapping.
	LOOK,
	## Drag articulates the part's joint within its limits.
	POSE,
	## Drag lifts the part and drops it into another compatible socket.
	MOVE,
}

const DRAG_MODE_LABELS := {
	DragMode.LOOK: "Look",
	DragMode.POSE: "Pose",
	DragMode.MOVE: "Move",
}

const DRAG_MODE_HINTS := {
	DragMode.LOOK: "Drag to orbit · tap a part to select it",
	DragMode.POSE: "Drag a part to swing it in its joint · Shift for slide/scale",
	DragMode.MOVE: "Drag a part to another socket to move it",
}

## Pixels of movement before a press counts as a drag rather than a tap. Generous
## because a finger never holds perfectly still.
const DRAG_THRESHOLD := 6.0

## Degrees of joint travel per pixel dragged.
const POSE_SENSITIVITY := 0.45

signal drag_mode_changed(mode: int)
signal status_changed(text: String)

var drag_mode := DragMode.LOOK
var socket_labels_on := false

var _root: BuilderRoot
var _camera: OrbitCamera
var _ghost: GhostPreview
var _view: ShipView

# Pointer state. Tracked by hand rather than with Godot's built-in drag because
# the same gesture has to work for mouse, pen and touch, and because a drag that
# starts on a part means something different from one that starts on empty space.
var _pressed := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _dragging := false
var _drag_kind := ""
var _drag_path := ""
var _pose_axis_h := ""
var _pose_axis_v := ""

## Active touch index -> position, for pinch-zoom and two-finger pan.
var _touches: Dictionary = {}
var _pinch_distance := 0.0

## Index into the sorted socket list for keyboard cycling.
var _socket_cursor := -1

## The part the socket markers are currently filtered to, so a drag re-filters
## once when it starts rather than on every motion event.
var _drag_filter_part: ShipPart = null


func _ready() -> void:
	_root = owner as BuilderRoot
	_camera = %Camera
	_ghost = %Ghost
	_root.design_rebuilt.connect(_on_design_rebuilt)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_emit_status()


func _on_design_rebuilt(view: ShipView) -> void:
	_view = view
	_socket_cursor = -1
	if _ghost != null:
		_ghost.clear()


# --- Picking ---------------------------------------------------------------

## Raycast into the scene. [param layers] is a physics mask: 1 = parts,
## 2 = sockets, 3 = either.
func _pick(local_pos: Vector2, layers: int) -> Dictionary:
	if _camera == null:
		return {}
	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(local_pos)
	var dir := _camera.project_ray_normal(local_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = layers
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.get("collider") as Node
	if collider == null or not collider.has_meta("kind"):
		return {}
	return {
		"kind": String(collider.get_meta("kind")),
		"path": String(collider.get_meta("path")),
		"raw_path": String(collider.get_meta("raw_path", collider.get_meta("path"))),
		"position": hit.get("position", Vector3.ZERO),
	}


## Sockets get priority over parts while sockets are shown, because a socket
## marker sits inside the hull's own pick box and would otherwise be unclickable.
func _pick_best(local_pos: Vector2) -> Dictionary:
	if _view != null and _view.sockets_visible():
		var socket_hit := _pick(local_pos, ShipAssembler.LAYER_SOCKETS)
		if not socket_hit.is_empty():
			return socket_hit
	return _pick(local_pos, ShipAssembler.LAYER_PARTS)


# --- Input ---------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_camera.zoom(1.0)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_camera.zoom(-1.0)
			accept_event()
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_begin_press(mb.position, mb.shift_pressed)
			else:
				_end_press(mb.position)
			accept_event()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			# Both always orbit/pan regardless of drag mode, so the camera is never
			# locked away behind a mode.
			if mb.pressed:
				_pressed = true
				_dragging = true
				_drag_kind = "pan" if mb.button_index == MOUSE_BUTTON_MIDDLE else "orbit"
				_last_pos = mb.position
			else:
				_pressed = false
				_dragging = false
				_drag_kind = ""
			accept_event()


func _begin_press(pos: Vector2, shift: bool) -> void:
	_pressed = true
	_press_pos = pos
	_last_pos = pos
	_dragging = false
	_drag_kind = ""
	_drag_path = ""
	var hit := _pick_best(pos)
	if hit.is_empty():
		_drag_kind = "pan" if shift else "orbit"
		return
	# What the press is *over* decides what a drag would do; the drag itself does
	# not start until the pointer actually moves.
	if String(hit["kind"]) == "socket":
		_drag_kind = "socket"
		_drag_path = String(hit["path"])
		return
	_drag_path = String(hit["path"])
	match drag_mode:
		DragMode.POSE:
			_drag_kind = "pose"
		DragMode.MOVE:
			_drag_kind = "move"
		_:
			_drag_kind = "orbit_or_select"


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if not _pressed:
		_hover_at(mm.position)
		return
	var delta := mm.position - _last_pos
	_last_pos = mm.position
	if not _dragging:
		if mm.position.distance_to(_press_pos) < DRAG_THRESHOLD:
			return
		_dragging = true
		_on_drag_started()
	_apply_drag(delta, mm.position, mm.shift_pressed)
	accept_event()


func _on_drag_started() -> void:
	match _drag_kind:
		"pose":
			_start_pose_drag()
		"move":
			_start_move_drag()
		"orbit_or_select", "socket":
			# Dragging off a part or a socket just moves the camera.
			_drag_kind = "orbit"


func _apply_drag(delta: Vector2, pos: Vector2, shift: bool) -> void:
	match _drag_kind:
		"orbit":
			_camera.orbit(delta)
		"pan":
			_camera.pan(delta, size.y)
		"pose":
			_apply_pose_drag(delta, shift)
		"move":
			_update_move_drag(pos)


func _end_press(pos: Vector2) -> void:
	var was_dragging := _dragging
	_pressed = false
	_dragging = false
	if not was_dragging:
		_click_at(pos)
	else:
		match _drag_kind:
			"pose":
				_root.end_continuous()
				_emit_status()
			"move":
				_finish_move_drag(pos)
	_drag_kind = ""
	_drag_path = ""


func _click_at(pos: Vector2) -> void:
	var hit := _pick_best(pos)
	if hit.is_empty():
		_root.select("")
		return
	var path := String(hit["path"])
	if String(hit["kind"]) == "socket":
		# Tapping a socket is the keyboard/touch-friendly alternative to dragging:
		# it filters the palette to what fits, so the next tap fits a part.
		_focus_socket(path)
		return
	_root.select(path)


func _hover_at(pos: Vector2) -> void:
	var hit := _pick_best(pos)
	if hit.is_empty():
		_root.hover("")
		if _view != null:
			_view.emphasise_socket("")
		status_changed.emit(DRAG_MODE_HINTS[drag_mode])
		return
	var path := String(hit["path"])
	if String(hit["kind"]) == "socket":
		_root.hover("")
		if _view != null:
			_view.emphasise_socket(path)
		var entry := _view.resolution.find_open_socket(path)
		if not entry.is_empty():
			var socket := entry["socket"] as PartSocket
			var label := socket.display_name if socket.display_name != "" else socket.id
			status_changed.emit("%s — accepts %s" % [label, ", ".join(socket.accepts)])
		return
	if _view != null:
		_view.emphasise_socket("")
	_root.hover(path)
	var placement := _root.placement_at(path)
	if placement != null:
		var extra := "  ⟲ mirrored from the other side" if placement.shadow else ""
		status_changed.emit(placement.part.display_name + extra)


# --- Pose dragging -------------------------------------------------------

func _start_pose_drag() -> void:
	var placement := _root.placement_at(_drag_path)
	if placement == null or placement.socket == null:
		_drag_kind = "orbit"
		return
	var joint := _effective_joint(placement)
	if joint == null or not joint.is_articulated():
		_drag_kind = "orbit"
		status_changed.emit("%s is rigidly mounted — nothing to pose" % placement.part.display_name)
		_root.coach().show_tip(
			"rigid_mount",
			"That mount does not move",
			"Pose mode swings a part inside the travel its mount allows — and most "
			+ "mounts allow none. Hardpoints and pylons swivel; armour plate and "
			+ "cockpits are bolted down. The Part tab tells you which, and gives you "
			+ "exact numbers for the ones that do move.",
			"The status line under the ship names the joint whenever a part has one."
		)
		return
	# Map the two screen axes onto the two most useful joint axes available, so a
	# drag always does something rather than silently no-oping on a slide-only mount.
	_pose_axis_h = "yaw" if joint.has_yaw() else ("roll" if joint.has_roll() else "")
	_pose_axis_v = "pitch" if joint.has_pitch() else ("slide" if joint.has_slide() else "")
	_root.begin_continuous("Pose " + placement.part.display_name)
	status_changed.emit("Posing %s — %s" % [placement.part.display_name, joint.describe()])


## The limits that apply to a placement. A mirrored pair shares one joint, and the
## resolver already substituted the source socket's, so this is just a null guard.
func _effective_joint(placement: Placement) -> PartJoint:
	if placement.socket == null:
		return null
	return placement.socket.joint


func _apply_pose_drag(delta: Vector2, shift: bool) -> void:
	var placement := _root.placement_at(_drag_path)
	if placement == null:
		return
	var joint := _effective_joint(placement)
	if joint == null:
		return
	var data_path := _root.data_path_of(_drag_path)
	var attachment := _root.design.get_attachment(data_path)
	if attachment == null:
		return

	# Shift swaps the vertical axis over to the linear controls, which are the ones
	# players reach for least often but need for hardpoint spacing.
	var v_axis := _pose_axis_v
	if shift:
		if joint.has_slide():
			v_axis = "slide"
		elif joint.has_scale():
			v_axis = "scale"

	if _pose_axis_h != "" and not is_zero_approx(delta.x):
		var sign_h := -1.0 if placement.mirrored and joint.mirror_negates_yaw else 1.0
		_bump_pose(data_path, attachment, joint, _pose_axis_h, delta.x * POSE_SENSITIVITY * sign_h)
	if v_axis != "" and not is_zero_approx(delta.y):
		var scale_step := 0.004 if v_axis == "scale" else (0.02 if v_axis == "slide" else POSE_SENSITIVITY)
		_bump_pose(data_path, attachment, joint, v_axis, -delta.y * scale_step)

	var joint_desc := "%s %.1f" % [_pose_axis_h, attachment.get_pose_value(_pose_axis_h)] if _pose_axis_h != "" else ""
	if v_axis != "":
		joint_desc += "   %s %.2f" % [v_axis, attachment.get_pose_value(v_axis)]
	status_changed.emit(joint_desc)


func _bump_pose(
	data_path: String, attachment: PartAttachment, joint: PartJoint, key: String, amount: float
) -> void:
	var current := attachment.get_pose_value(key)
	var wanted := current + amount
	# Clamp through the joint so the drag stops dead at the limit instead of
	# accumulating an invisible overshoot the player has to drag back out of.
	var probe := attachment.pose.duplicate()
	probe[key] = wanted
	var clamped: Dictionary = joint.clamp_pose(probe)
	_root.set_pose(data_path, key, float(clamped.get(key, current)), true)


# --- Move dragging -------------------------------------------------------

func _start_move_drag() -> void:
	var placement := _root.placement_at(_drag_path)
	if placement == null or placement.is_chassis():
		_drag_kind = "orbit"
		return
	if placement.shadow:
		_drag_kind = "orbit"
		status_changed.emit("Mirrored parts follow their twin — move the other side")
		return
	_drag_filter_part = placement.part
	_view.show_sockets(true, placement.part)
	_ghost.show_part(placement.part, placement.xform, true)
	if _view.resolution.sockets_accepting(placement.part).is_empty():
		status_changed.emit(
			"Nowhere else to put %s — %s" % [
				placement.part.display_name,
				_view.resolution.explain_no_socket(placement.part)
			]
		)
	else:
		status_changed.emit(
			"Moving %s — drop it on a glowing mount" % placement.part.display_name
		)


func _update_move_drag(pos: Vector2) -> void:
	var placement := _root.placement_at(_drag_path)
	if placement == null:
		return
	var target := _best_socket_for(pos, placement.part)
	if target.is_empty():
		_view.emphasise_socket("")
		_ghost.show_part(placement.part, _cursor_plane_transform(pos, placement.xform), false)
		return
	_view.emphasise_socket(String(target["path"]))
	_ghost.show_part(placement.part, target["xform"] as Transform3D, true)


func _finish_move_drag(pos: Vector2) -> void:
	var placement := _root.placement_at(_drag_path)
	_ghost.clear()
	_view.show_sockets(false)
	if placement == null:
		return
	_drag_filter_part = null
	var target := _best_socket_for(pos, placement.part)
	if target.is_empty():
		status_changed.emit("Put back — %s was not dropped on a mount" % placement.part.display_name)
		return
	_root.move_part(_drag_path, String(target["path"]))


## Nearest open socket that accepts [param part], preferring a direct hit and
## falling back to the closest one on screen within a forgiving radius.
func _best_socket_for(pos: Vector2, part: ShipPart) -> Dictionary:
	var hit := _pick(pos, ShipAssembler.LAYER_SOCKETS)
	if not hit.is_empty():
		var entry := _view.resolution.find_open_socket(String(hit["path"]))
		if not entry.is_empty() and (entry["socket"] as PartSocket).accepts_part(part):
			return entry
	var best: Dictionary = {}
	# Forgiving, and forgiving in proportion to the screen: 90 logical pixels is
	# a comfortable thumb's worth on a desktop window and a mean target on a
	# phone, where the whole viewport may be 400 wide.
	var best_dist := maxf(90.0, minf(size.x, size.y) * 0.20)
	for entry in _view.resolution.sockets_accepting(part):
		var world: Vector3 = (entry["xform"] as Transform3D).origin
		if _camera.is_position_behind(world):
			continue
		var screen := _camera.unproject_position(world)
		var d := screen.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = entry
	return best


## Where to draw a ghost that is not over any socket: on the plane through the
## part's current position, facing the camera.
func _cursor_plane_transform(pos: Vector2, reference: Transform3D) -> Transform3D:
	var from := _camera.project_ray_origin(pos)
	var dir := _camera.project_ray_normal(pos)
	var plane := Plane(_camera.global_transform.basis.z, reference.origin)
	var point: Variant = plane.intersects_ray(from, dir)
	var out := reference
	if point is Vector3:
		out.origin = point
	return out


## Say something useful the moment a part is picked up with nowhere to put it.
##
## This is the failure the builder used to handle worst. Markers appeared on the
## hull, none of them accepted the part, the drop was refused without saying why,
## and the reasonable conclusion was that the snapping did not work. Now the
## markers that appear are only the ones that will take it — so if none appear at
## all, that silence needs explaining out loud.
func _warn_if_nowhere_to_go(part: ShipPart) -> void:
	if _view == null or not _view.resolution.sockets_accepting(part).is_empty():
		return
	var reason := _view.resolution.explain_no_socket(part)
	status_changed.emit(reason)
	_root.coach().show_tip(
		"no_socket",
		"Nothing lit up",
		"A mount only glows when it will actually take what you are carrying, so an "
		+ "unlit hull means this part has nowhere to go on this ship yet. "
		+ reason + ".",
		"Tap a mount first and the parts list narrows to what fits it — the "
		+ "quickest way to find out what a hull will accept."
	)


# --- Palette drag and drop ----------------------------------------------

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or String((data as Dictionary).get("type", "")) != "part":
		return false
	var part := _root.library.get_part(String((data as Dictionary)["part_id"]))
	if part == null:
		return false
	if part.category == "chassis":
		# A chassis has no socket to land in; dropping one anywhere swaps the hull.
		_ghost.clear()
		_view.emphasise_socket("")
		status_changed.emit("Drop to swap the hull for " + part.display_name)
		return true
	# Re-filter unconditionally, not just when the markers were off. Sockets left
	# on from the G key are an unfiltered set, and leaving that set up during a
	# drag is what puts markers on mounts this part can never use.
	if _drag_filter_part != part:
		_drag_filter_part = part
		_view.show_sockets(true, part)
		_warn_if_nowhere_to_go(part)
	var target := _best_socket_for(at_position, part)
	if target.is_empty():
		_ghost.show_invalid(part, _cursor_plane_transform(at_position, Transform3D()))
		_view.emphasise_socket("")
		status_changed.emit(_view.resolution.explain_no_socket(part))
		# Still accept the drop so the release lands on this control and clears
		# state, rather than being swallowed as a failed drag with sockets left on.
		return true
	_view.emphasise_socket(String(target["path"]))
	_ghost.show_part(part, target["xform"] as Transform3D, true)
	var socket := target["socket"] as PartSocket
	var mirrored: bool = bool(target.get("shadow", false)) or socket.is_mirror()
	var label := socket.display_name if socket.display_name != "" else socket.id
	status_changed.emit("Fit %s to %s%s" % [
		part.display_name, label, "  (both sides)" if mirrored else ""
	])
	_root.preview_fit(String(target["path"]), part.id)
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var part_id := String((data as Dictionary).get("part_id", ""))
	var part := _root.library.get_part(part_id)
	_ghost.clear()
	_view.show_sockets(false)
	_root.clear_preview()
	if part == null:
		return
	if part.category == "chassis":
		_root.swap_chassis(part_id)
		return
	var target := _best_socket_for(at_position, part)
	if target.is_empty():
		_root.notice.emit(_view.resolution.explain_no_socket(part), "error")
		return
	_root.place_part(String(target["path"]), part_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Godot does not tell a control that a drag it was previewing went
		# elsewhere, so clean up unconditionally when any drag ends.
		if _ghost != null:
			_ghost.clear()
		_drag_filter_part = null
		if _view != null and _view.sockets_visible() and not socket_labels_on:
			_view.show_sockets(false)
		elif _view != null and _view.sockets_visible():
			# Labels are on, so the markers stay — but unfiltered again, since
			# nothing is being carried any more.
			_view.show_sockets(true)
			_view.set_socket_labels_visible(true)
		if _root != null:
			_root.clear_preview()
		_emit_status()
	elif what == NOTIFICATION_MOUSE_EXIT:
		if _root != null:
			_root.hover("")


# --- Keyboard ------------------------------------------------------------

func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if key.is_action("build_next_socket"):
		cycle_socket(1)
		accept_event()
	elif key.is_action("build_prev_socket"):
		cycle_socket(-1)
		accept_event()
	elif key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT:
		_camera.nudge_orbit(-15.0 if key.keycode == KEY_LEFT else 15.0, 0.0)
		accept_event()
	elif key.keycode == KEY_UP or key.keycode == KEY_DOWN:
		_camera.nudge_orbit(0.0, -10.0 if key.keycode == KEY_UP else 10.0)
		accept_event()
	elif key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
		_camera.zoom(1.0)
		accept_event()
	elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
		_camera.zoom(-1.0)
		accept_event()


## Step through the open sockets, showing markers and focusing one. This is the
## whole keyboard building flow: cycle to a socket, then pick a part from the
## palette, which is filtered to what fits.
func cycle_socket(direction: int) -> void:
	if _view == null or _view.resolution.open_sockets.is_empty():
		status_changed.emit("No empty sockets")
		return
	_view.show_sockets(true)
	socket_labels_on = true
	_view.set_socket_labels_visible(true)
	var count := _view.resolution.open_sockets.size()
	_socket_cursor = posmod(_socket_cursor + direction, count)
	_focus_socket(String(_view.resolution.open_sockets[_socket_cursor]["path"]))


func _focus_socket(path: String) -> void:
	var entry := _view.resolution.find_open_socket(path)
	if entry.is_empty():
		return
	_socket_cursor = _view.resolution.open_sockets.find(entry)
	_view.show_sockets(true)
	_view.emphasise_socket(path)
	var socket := entry["socket"] as PartSocket
	var label := socket.display_name if socket.display_name != "" else socket.id
	var required := "  (required)" if socket.required else ""
	status_changed.emit("%s%s — accepts %s, size %s" % [
		label, required, ", ".join(socket.accepts), ", ".join(socket.size_classes)
	])
	# Tell the palette to filter itself to parts that fit here, which is what turns
	# a 72-part catalogue into a short list of real choices.
	(%PartPalette as PartPalette).filter_to_socket(entry)


## Focus a mount from outside the viewport — the socket tree calls this so
## clicking a row in the list behaves exactly like tapping the marker in 3D.
func focus_socket(path: String) -> void:
	if _view == null:
		return
	_focus_socket(path)


func focused_socket() -> String:
	return _view.emphasised_socket() if _view != null else ""


# --- Touch --------------------------------------------------------------

func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_touches[touch.index] = touch.position
		if _touches.size() == 1:
			grab_focus()
			_begin_press(touch.position, false)
		elif _touches.size() == 2:
			# A second finger cancels whatever the first was doing and starts a
			# pinch, so a mis-started orbit never turns into an accidental edit.
			if _drag_kind == "pose":
				_root.end_continuous()
			elif _drag_kind == "move":
				_ghost.clear()
				_view.show_sockets(false)
			_pressed = false
			_dragging = false
			_drag_kind = ""
			var keys := _touches.keys()
			_pinch_distance = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
	else:
		_touches.erase(touch.index)
		if _touches.is_empty():
			if _pressed:
				_end_press(touch.position)
			_pinch_distance = 0.0
	accept_event()


func _handle_screen_drag(drag: InputEventScreenDrag) -> void:
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		var keys := _touches.keys()
		var a := _touches[keys[0]] as Vector2
		var b := _touches[keys[1]] as Vector2
		var dist := a.distance_to(b)
		if _pinch_distance > 0.0:
			# Pinch zooms, and the midpoint's motion pans, so both happen in one
			# gesture the way they do in a map app.
			var ratio := dist / maxf(_pinch_distance, 1.0)
			_camera.zoom(log(maxf(ratio, 0.01)) / log(0.88) * -1.0)
			_camera.pan(drag.relative * 0.5, size.y)
		_pinch_distance = dist
		accept_event()
		return
	if not _pressed:
		return
	if not _dragging:
		if drag.position.distance_to(_press_pos) < DRAG_THRESHOLD:
			return
		_dragging = true
		_on_drag_started()
	_last_pos = drag.position
	_apply_drag(drag.relative, drag.position, false)
	accept_event()


# --- Toggles -----------------------------------------------------------

func set_drag_mode(mode: int) -> void:
	drag_mode = mode
	drag_mode_changed.emit(mode)
	_emit_status()


func cycle_drag_mode() -> void:
	set_drag_mode((int(drag_mode) + 1) % DRAG_MODE_LABELS.size())


func toggle_sockets() -> void:
	if _view == null:
		return
	var showing := not _view.sockets_visible()
	_view.show_sockets(showing)
	if not showing:
		socket_labels_on = false
		_view.set_socket_labels_visible(false)
	status_changed.emit("Sockets %s" % ("shown" if showing else "hidden"))


func toggle_socket_labels() -> void:
	if _view == null:
		return
	socket_labels_on = not socket_labels_on
	if socket_labels_on:
		_view.show_sockets(true)
	_view.set_socket_labels_visible(socket_labels_on)
	status_changed.emit("Socket names %s" % ("shown" if socket_labels_on else "hidden"))


func frame_ship() -> void:
	if _view != null:
		_camera.frame(_view.aabb, maxf(size.x, 1.0) / maxf(size.y, 1.0))


func _emit_status() -> void:
	status_changed.emit(DRAG_MODE_HINTS[drag_mode])
