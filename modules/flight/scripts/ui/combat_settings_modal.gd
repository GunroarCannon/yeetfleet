## CombatSettingsModal: Decoupled modal panel for combat controls and tactics.
##
## Manages targeting preferences, tactical headlights, AI fleet deployment,
## dynamic in-world incidents, and planetary destruction settings.
class_name CombatSettingsModal
extends PanelContainer

signal setting_changed(setting_name: String, value: Variant)
signal action_triggered(action_name: String, params: Dictionary)

var _target_lock_btn: Button
var _headlights_check: CheckBox
var _face_target_check: CheckBox
var _lead_reticle_check: CheckBox
var _fineness_slider: HSlider
var _glow_check: CheckBox


func _ready() -> void:
	custom_minimum_size = Vector2(380.0, 420.0)
	_build_ui()


func _build_ui() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.92)
	sb.border_color = Color("ff4d4d", 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0.8, 0.1, 0.1, 0.25)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "🎯 COMBAT & TACTICAL SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ff5252"))
	header_hbox.add_child(title)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header_hbox.add_child(close_btn)

	# Targeting section
	_target_lock_btn = Button.new()
	_target_lock_btn.text = "Lock Nearest Target (T)"
	_target_lock_btn.pressed.connect(func() -> void: action_triggered.emit("toggle_lock", {}))
	vbox.add_child(_target_lock_btn)

	_face_target_check = CheckBox.new()
	_face_target_check.text = "Auto-Face Locked Target"
	_face_target_check.toggled.connect(func(on: bool) -> void: setting_changed.emit("facing_target", on))
	vbox.add_child(_face_target_check)

	_lead_reticle_check = CheckBox.new()
	_lead_reticle_check.text = "Predictive Target Lead Reticle"
	_lead_reticle_check.button_pressed = true
	_lead_reticle_check.toggled.connect(func(on: bool) -> void: setting_changed.emit("lead_reticle", on))
	vbox.add_child(_lead_reticle_check)

	# Tactical searchlights / Headlights toggle
	_headlights_check = CheckBox.new()
	_headlights_check.text = "Ship High-Beam Headlights (L)"
	_headlights_check.button_pressed = Session.ship_headlights
	_headlights_check.toggled.connect(func(on: bool) -> void:
		Session.ship_headlights = on
		setting_changed.emit("ship_headlights", on)
	)
	vbox.add_child(_headlights_check)

	vbox.add_child(HSeparator.new())

	# Quick AI fleet spawners
	var fleet_label := Label.new()
	fleet_label.text = "AI Traffic Spawner"
	fleet_label.add_theme_font_size_override("font_size", 12)
	fleet_label.add_theme_color_override("font_color", BuilderTheme.warn())
	vbox.add_child(fleet_label)

	var hbox_spawn := HBoxContainer.new()
	hbox_spawn.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox_spawn)

	var b1 := Button.new(); b1.text = "+1 Ship"; b1.pressed.connect(func() -> void: action_triggered.emit("spawn_ai", {"count": 1}))
	var b3 := Button.new(); b3.text = "+3 Squad"; b3.pressed.connect(func() -> void: action_triggered.emit("spawn_ai", {"count": 3}))
	var b6 := Button.new(); b6.text = "+6 Fleet"; b6.pressed.connect(func() -> void: action_triggered.emit("spawn_ai", {"count": 6}))
	hbox_spawn.add_child(b1)
	hbox_spawn.add_child(b3)
	hbox_spawn.add_child(b6)

	var b_mother := Button.new()
	b_mother.text = "🚀 Launch Dreadnought / Mother Ship"
	b_mother.pressed.connect(func() -> void: action_triggered.emit("spawn_mother", {}))
	vbox.add_child(b_mother)

	var b_clear := Button.new()
	b_clear.text = "✕ Clear All AI Ships"
	b_clear.pressed.connect(func() -> void: action_triggered.emit("clear_ai", {}))
	vbox.add_child(b_clear)

	vbox.add_child(HSeparator.new())

	# Planetary destruction dials
	var dest_label := Label.new()
	dest_label.text = "Planetary Destruction"
	dest_label.add_theme_font_size_override("font_size", 12)
	dest_label.add_theme_color_override("font_color", Color("ff6f40"))
	vbox.add_child(dest_label)

	_glow_check = CheckBox.new()
	_glow_check.text = "Radiant Debris Glow"
	_glow_check.button_pressed = Session.planet_debris_glow
	_glow_check.toggled.connect(func(on: bool) -> void:
		Session.planet_debris_glow = on
		setting_changed.emit("debris_glow", on)
	)
	vbox.add_child(_glow_check)

	var b_shatter := Button.new()
	b_shatter.text = "💥 Shatter Nearest Planet (Shift+P)"
	b_shatter.pressed.connect(func() -> void: action_triggered.emit("shatter_planet", {}))
	vbox.add_child(b_shatter)


func update_state(locked: bool, facing: bool, lights: bool) -> void:
	if _target_lock_btn:
		_target_lock_btn.text = "Release Lock (T)" if locked else "Lock Nearest Target (T)"
	if _face_target_check:
		_face_target_check.set_pressed_no_signal(facing)
	if _headlights_check:
		_headlights_check.set_pressed_no_signal(lights)
