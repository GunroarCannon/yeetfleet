## ControlsPanel: every control-related toggle and dial in one place, opened
## from the 🎮 Controls chip on the top bar or the D debug column.
##
## The movement profile (classic, swipe, slingshot, FPS), the camera gestures
## the one-thumb profiles use, each profile's own dials, aim assist and the AI
## slingshot. Rows write straight through to [JuiceSettings] (saved on every
## change and baked into the shipped defaults like the rest), the profile
## through [method FlightRoot.set_move_profile].
class_name ControlsPanel
extends JuiceSettingsPanel

var _root: FlightRoot = null
var _profile_buttons: Array[Button] = []


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	panel_title = "🎮 CONTROLS"
	accent = Color("5ee0ff")
	super._ready()
	visibility_changed.connect(_sync_profile)


func _build_rows(vbox: VBoxContainer) -> void:
	_section(vbox, "Movement profile (U)", Color("5ee0ff"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	vbox.add_child(row)
	var group := ButtonGroup.new()
	for i in FlightRoot.MOVE_PROFILE_NAMES.size():
		var b := Button.new()
		b.text = String(FlightRoot.MOVE_PROFILE_NAMES[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(88.0, float(BuilderTheme.TOUCH_MIN))
		b.pressed.connect(func() -> void:
			if _root != null:
				_root.set_move_profile(i)
		)
		row.add_child(b)
		_profile_buttons.append(b)
	_sync_profile()
	_note(vbox,
		"Classic: stick, throttle and buttons. Swipe: swipe from your ship to fly that way, tap to shoot, "
		+ "hold to boost (longer: warp). Slingshot: drag back from your ship and let go. "
		+ "FPS: the stick moves you (push further = faster), drag the screen to look.")

	_section(vbox, "Camera gestures & dynamic camera (swipe & slingshot)", Color("9ad0ff"))
	_float_row(vbox, "Dynamic camera: closest it comes in (× normal distance)", "swipe_cam_min", 0.05, "×%.2f")
	_float_row(vbox, "Dynamic camera: furthest it pulls out (× normal distance)", "swipe_cam_max", 0.1, "×%.1f")
	_check(vbox, "Two fingers pinch to zoom (mouse wheel on PC)", "cam_pinch_zoom", JuiceSettings.cam_pinch_zoom)
	_check(vbox, "Drag off the ship / twist two fingers to swing the camera round it (right-drag on PC)", "cam_twist_rotate", JuiceSettings.cam_twist_rotate)
	_float_row(vbox, "Swing speed", "cam_gesture_speed", 0.05, "×%.2f")
	_check(vbox, "Glowing 3D arrows for the heading and the launch", "move_arrows", JuiceSettings.move_arrows)
	_float_row(vbox, "\"On the ship\" grab area", "grab_radius_scale", 0.05, "×%.2f")

	_section(vbox, "Launch magnet (swipe & slingshot)", Color("b890ff"))
	_float_row(vbox, "Bend onto a ship ahead", "magnet_strength", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "  looks this far off the line", "magnet_cone_deg", 1.0, "%.0f°")
	_float_row(vbox, "  the ship drifts into your path", "magnet_pull", 5.0, "%.0f m/s²")
	_check(vbox, "Friendly and harmless ships too (enemies first)", "magnet_friendlies", JuiceSettings.magnet_friendlies)
	_float_row(vbox, "Chain pull toward the next enemy after a kill", "chain_magnet", 0.05, "%.0f%%", 100.0)

	_section(vbox, "Swipe profile", Color("5ee0ff"))
	_check(vbox, "Only a swipe from the ship moves it (elsewhere swings the camera)", "swipe_from_ship", JuiceSettings.swipe_from_ship)
	_float_row(vbox, "Camera further out", "swipe_cam_zoom", 0.05, "+%.0f%%", 100.0)
	_float_row(vbox, "  looks ahead while moving / dashing", "swipe_look_ahead", 0.05, "×%.2f")
	_float_row(vbox, "Profile speed", "swipe_speed_mult", 0.05, "×%.2f")
	_float_row(vbox, "Cruise after a dash", "swipe_cruise", 0.05, "×%.2f top speed")
	_float_row(vbox, "Longest dash", "swipe_dash", 0.1, "×%.1f top speed")
	_float_row(vbox, "Turn to a new heading", "swipe_turn_rate", 0.5, "%.1f rad/s")
	_float_row(vbox, "Dash fades", "swipe_drag", 0.1, "%.1f /s")
	_float_row(vbox, "Course correction cone", "swipe_assist_cone_deg", 1.0, "%.0f°")
	_float_row(vbox, "  bend onto the target", "swipe_assist_strength", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Ram damage you deal (swipe & sling)", "move_ram_dealt", 0.1, "×%.1f")
	_float_row(vbox, "Ram damage you take (swipe & sling)", "move_ram_taken", 0.05, "×%.2f")
	_float_row(vbox, "Hull strength in a ram (swipe & sling)", "move_durability", 0.05, "×%.2f")

	_section(vbox, "Slingshot profile", Color("ffcf5e"))
	_check(vbox, "Camera follows the flight smoothly (not the hull's spin)", "sling_steady_cam", JuiceSettings.sling_steady_cam)
	_check(vbox, "Camera holds still while aiming (the aim never drifts)", "sling_aim_cam_hold", JuiceSettings.sling_aim_cam_hold)
	_float_row(vbox, "Launch speed at a full pull", "sling_power", 0.1, "×%.1f top speed")
	_float_row(vbox, "Pull down throws into the screen", "sling_aim_depth", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Camera looks ahead", "sling_look_ahead", 0.05, "×%.2f")
	_float_row(vbox, "Camera eases in (slow / near ships)", "sling_close_zoom", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Speed kept per bounce", "sling_bounce_keep", 0.01, "%.0f%%", 100.0)
	_float_row(vbox, "Bounce seeks the next body", "sling_bounce_seek", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Run ends below", "sling_end_speed", 0.05, "×%.2f top speed")
	_float_row(vbox, "Run ends after", "sling_max_time", 0.5, "%.1f s")
	_float_row(vbox, "Drag in flight", "sling_drag", 0.05, "%.2f /s")
	_float_row(vbox, "Camera pull-out", "sling_zoom", 0.05, "×%.2f")
	_float_row(vbox, "Launch tumble", "sling_spin", 0.5, "%.1f rad/s")
	_check(vbox, "Flies like a rocket (nose first, rolling) instead of tumbling", "sling_rocket_spin", JuiceSettings.sling_rocket_spin)
	_check(vbox, "Tap while flying shoots toward the tap", "sling_tap_fire", JuiceSettings.sling_tap_fire)
	_check(vbox, "Touch the flying ship to catch it", "sling_catch", JuiceSettings.sling_catch)

	_section(vbox, "FPS profile", Color("7dffb0"))
	_float_row(vbox, "Look sensitivity", "fps_look_speed", 0.05, "×%.2f")
	_check(vbox, "Invert look (drag up looks down)", "fps_invert_y", JuiceSettings.fps_invert_y)
	_float_row(vbox, "Speed at a full stick", "fps_speed_mult", 0.05, "×%.2f top speed")
	_float_row(vbox, "Pick-up (how fast it reaches that speed)", "fps_accel", 0.1, "%.1f /s")
	_float_row(vbox, "Boost when the stick is past", "fps_boost_at", 0.01, "%.0f%%", 100.0)
	_float_row(vbox, "Camera further out", "fps_cam_zoom", 0.05, "+%.0f%%", 100.0)

	_section(vbox, "Aim", Color("ffb03a"))
	_check(vbox, "Aim assist (crosshair magnetism)", "aim_assist_enabled", JuiceSettings.aim_assist_enabled)
	_slider_row(vbox, "Aim assist strength", 0.0, 1.0, 0.05, JuiceSettings.aim_assist_strength, JuiceSettings.set_aim_assist_strength)
	_float_row(vbox, "Your shots never slower than", "player_min_shot_speed", 25.0, "%.0f m/s")

	_section(vbox, "AI", Color("ff6f60"))
	_check(vbox, "AI ships fight by slingshot too (any profile)", "ai_slingshot", JuiceSettings.ai_slingshot)
	_float_row(vbox, "  share of AI ships", "ai_sling_share", 0.05, "%.0f%%", 100.0)
	_check(vbox, "Yeet combat: ships you can see dash at you (faster one in the clash wins)", "yeet_combat", JuiceSettings.yeet_combat)
	_float_row(vbox, "  seconds between a ship's dashes", "yeet_interval", 0.25, "%.2f s")
	_float_row(vbox, "  dash speed", "yeet_speed", 0.1, "×%.1f top speed")
	_float_row(vbox, "  ships dashing at once", "yeet_max_ships", 1.0, "%.0f")
	_float_row(vbox, "  wind-up before a dash", "yeet_windup", 0.05, "%.2f s")

	_section(vbox, "Planet pinball (ram a planet)", Color("ffb03a"))
	_float_row(vbox, "Ram speed that shatters a planet (1 km planet, average hull)", "planet_smash_speed", 10.0, "%.0f m/s")
	_float_row(vbox, "Ram speed that knocks a planet off its spot", "planet_knock_speed", 5.0, "%.0f m/s")
	_float_row(vbox, "  how far the knock sends it", "planet_knock", 0.05, "×%.2f")


func _sync_profile() -> void:
	if _root == null:
		return
	for i in _profile_buttons.size():
		_profile_buttons[i].set_pressed_no_signal(i == _root.move_profile)


func _note(vbox: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(l)
