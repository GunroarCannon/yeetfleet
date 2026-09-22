## WeaponSelector: Decoupled modular weapon selection & status widget.
##
## Displays active weapon info (name, damage, speed, energy cost, ammo/heat),
## with forward/backward cycling and responsive touch targets for mobile/Steam Deck.
class_name WeaponSelector
extends HBoxContainer

signal weapon_changed(index: int, weapon_data: Dictionary)
signal fire_mode_toggled(mode: int)

var _prev_btn: Button
var _weapon_btn: Button
var _next_btn: Button
var _active_idx := 0
var _weapons: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", 6)
	_build_ui()


func _build_ui() -> void:
	# Previous weapon button
	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.custom_minimum_size = Vector2(36.0, BuilderTheme.TOUCH_MIN)
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.pressed.connect(_on_prev_pressed)
	add_child(_prev_btn)

	# Active weapon main button
	_weapon_btn = Button.new()
	_weapon_btn.text = "WEAPON: —"
	_weapon_btn.custom_minimum_size = Vector2(160.0, BuilderTheme.TOUCH_MIN)
	_weapon_btn.focus_mode = Control.FOCUS_NONE
	_weapon_btn.pressed.connect(_on_next_pressed)
	add_child(_weapon_btn)

	# Next weapon button
	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.custom_minimum_size = Vector2(36.0, BuilderTheme.TOUCH_MIN)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_on_next_pressed)
	add_child(_next_btn)


func configure(weapons: Array, initial_index: int = 0) -> void:
	_weapons = weapons
	set_active_index(initial_index)


func set_active_index(idx: int) -> void:
	if _weapons.is_empty():
		return
	_active_idx = clampi(idx, 0, _weapons.size() - 1)
	var w: Dictionary = _weapons[_active_idx]
	var w_name: String = w.get("name", "Laser")
	var w_type: String = w.get("type", "laser")
	_weapon_btn.text = "%s [F]" % w_name
	_weapon_btn.tooltip_text = "%s (%s)\nDamage: %.0f | Speed: %.0f m/s | Cost: %.1f" % [
		w_name, w_type,
		float(w.get("damage", 25.0)),
		float(w.get("speed", 900.0)),
		float(w.get("cost", 1.0))
	]
	weapon_changed.emit(_active_idx, w)


func cycle_forward() -> void:
	_on_next_pressed()


func cycle_backward() -> void:
	_on_prev_pressed()


func _on_next_pressed() -> void:
	if _weapons.is_empty():
		return
	var next := (_active_idx + 1) % _weapons.size()
	set_active_index(next)


func _on_prev_pressed() -> void:
	if _weapons.is_empty():
		return
	var prev := (_active_idx - 1 + _weapons.size()) % _weapons.size()
	set_active_index(prev)
