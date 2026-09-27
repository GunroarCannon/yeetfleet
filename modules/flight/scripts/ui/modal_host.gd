## FlightModalHost: one rule for every debug/settings panel on the flight HUD.
##
## A panel handed to [method manage] gets, whenever it is shown:
## - a see-through backdrop behind it that closes it on any tap outside its box
##   (the same [FlightMenu.BackdropShade] the toolbar popups use);
## - one-at-a-time: showing it hides any other managed panel;
## - a fit to the screen: when its minimum size is bigger than the viewport
##   (portrait phones, small screens) it is scaled down around its centre, so
##   no panel ever hangs off the edge.
##
## Panels keep their own show/hide code (`visible = …`); the host only watches
## [signal CanvasItem.visibility_changed]. [method close_top] is what Back and
## Escape call.
class_name FlightModalHost
extends RefCounted

## Most of the screen a panel may cover.
const FIT := Vector2(0.94, 0.92)

var _parent: Control
var _backdrop: FlightMenu.BackdropShade
var _panels: Array[Control] = []
## The panel the backdrop currently sits under.
var _top: Control = null


func _init(parent: Control) -> void:
	_parent = parent
	_backdrop = FlightMenu.BackdropShade.new()
	_backdrop.name = "ModalBackdrop"
	_backdrop.visible = false
	_backdrop.tapped.connect(close_top)
	_parent.add_child(_backdrop)
	_parent.get_viewport().size_changed.connect(_refit_open)


## Start managing [param panel] (already a child of the HUD).
func manage(panel: Control) -> void:
	if panel in _panels:
		return
	_panels.append(panel)
	# Over the top bar (z 10) and the rest of the HUD.
	panel.z_index = maxi(panel.z_index, 20)
	panel.visibility_changed.connect(_on_visibility.bind(panel))
	if panel.visible:
		_on_visibility(panel)


## True while any managed panel is open.
func any_open() -> bool:
	return _top != null and is_instance_valid(_top) and _top.visible


## Close the open panel. Returns true if one was closed.
func close_top() -> bool:
	if not any_open():
		return false
	_top.visible = false
	return true


# --- Internals ---

func _on_visibility(panel: Control) -> void:
	if panel.visible:
		for other in _panels:
			if other != panel and is_instance_valid(other) and other.visible:
				other.visible = false
		_top = panel
		# Tree order is input order: backdrop, then the panel, on top of the HUD.
		_parent.move_child(_backdrop, -1)
		_parent.move_child(panel, -1)
		_backdrop.z_index = panel.z_index
		_backdrop.visible = true
		_fit.call_deferred(panel)
	elif panel == _top:
		_top = null
		_backdrop.visible = false


func _refit_open() -> void:
	if any_open():
		_fit.call_deferred(_top)


func _fit(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.visible:
		return
	var view := _parent.get_viewport_rect().size
	var want := panel.get_combined_minimum_size()
	want = Vector2(maxf(want.x, panel.size.x), maxf(want.y, panel.size.y))
	var k := 1.0
	if want.x > 0.0 and want.y > 0.0:
		k = minf(1.0, minf(view.x * FIT.x / want.x, view.y * FIT.y / want.y))
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(k, k)
