## Four pooled [OmniLight3D]s — the whole light budget under `gl_compatibility`,
## where every extra light is real per-pixel cost. [method pop] steals the
## next slot round-robin when all four are lit, so a busy frame degrades to
## fewer simultaneous pops rather than an ever-growing light count.
class_name FxLight
extends Node3D

const COUNT := 4

var _lights: Array[OmniLight3D] = []
var _remaining: PackedFloat32Array = []
var _decay: PackedFloat32Array = []
var _base_energy: PackedFloat32Array = []
var _cursor := 0


func _ready() -> void:
	top_level = true
	_remaining.resize(COUNT)
	_decay.resize(COUNT)
	_base_energy.resize(COUNT)
	for i in COUNT:
		var light := OmniLight3D.new()
		light.name = "FxLight%d" % i
		light.visible = false
		light.shadow_enabled = false
		light.omni_range = 12.0
		add_child(light)
		_lights.append(light)
	set_process(true)


func pop(position: Vector3, color: Color, energy: float, decay: float) -> void:
	var slot := _cursor
	_cursor = (_cursor + 1) % COUNT
	var light := _lights[slot]
	light.global_position = position
	light.light_color = color
	light.light_energy = energy
	light.visible = true
	_base_energy[slot] = energy
	_decay[slot] = maxf(decay, 0.01)
	_remaining[slot] = decay


func _process(delta: float) -> void:
	for i in COUNT:
		if _remaining[i] <= 0.0:
			continue
		_remaining[i] -= delta
		if _remaining[i] <= 0.0:
			_lights[i].visible = false
			continue
		_lights[i].light_energy = _base_energy[i] * (_remaining[i] / _decay[i])
