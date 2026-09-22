extends SceneTree

const SCENE_PATH := "res://modules/flight/flight_test.tscn"

var _root: FlightRoot
var _frames := 0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as FlightRoot
	root.add_child(_root)
	_root.get_node("Ui/Coach").visible = false


func _process(_d: float) -> bool:
	_frames += 1
	if _frames != 15:
		return false
	var mm: MultiMesh = _root._motes.multimesh
	print("instance_count=", mm.instance_count, " transform_format=", mm.transform_format,
		" use_colors=", mm.use_colors)
	print("_mote_positions.size()=", _root._mote_positions.size())
	for i in mini(4, _root._mote_positions.size()):
		print("  base[", i, "]=", _root._mote_positions[i])
	for i in mini(4, mm.instance_count):
		print("  xform[", i, "]=", mm.get_instance_transform(i).origin)
	print("_mote_stretch=", _root._mote_stretch, " written=", _root._mote_stretch_written,
		" writing_streak=", _root._mote_writing_streak)
	print("motes node pos=", _root._motes.global_position, " visible=", _root._motes.visible)
	print("drift_field_on=", _root.drift_field_on())
	quit(0)
	return true
