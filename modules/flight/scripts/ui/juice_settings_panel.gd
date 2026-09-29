## JuiceSettingsPanel: every game-feel dial in one place, opened from the 🎬
## Juice chip on the flight HUD's top bar.
##
## Camera zoom, kill cam, freeze frames, explosions, emotes, hit feel, sound
## and AI pacing (player/enemy stats are the 🧪 Stats panel's). Each row
## writes straight through to [JuiceSettings], which saves on every change, so
## a tweak made here survives restarts and there is nothing to apply or submit.
class_name JuiceSettingsPanel
extends PanelContainer


## Title and accent colour; a subclass (e.g. [CombatStatsPanel]) swaps them
## and overrides [method _build_rows], reusing the row helpers below.
var panel_title := "🎬 JUICE & FEEL"
var accent := Color("46ff9b")


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 520.0)
	_build_ui()


func _build_ui() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d121c", 0.94)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(accent, 0.2)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = panel_title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)
	_build_rows(vbox)


func _build_rows(vbox: VBoxContainer) -> void:
	_section(vbox, "Overall", Color("46ff9b"))
	_slider_row(vbox, "Juice intensity (everything)", JuiceSettings.INTENSITY_MIN, JuiceSettings.INTENSITY_MAX, 0.05, JuiceSettings.intensity, JuiceSettings.set_intensity)
	var rm := CheckBox.new()
	rm.text = "Reduce motion (no shake, freeze, slow-mo, kill cam)"
	rm.button_pressed = JuiceSettings.reduce_motion
	rm.toggled.connect(JuiceSettings.set_reduce_motion)
	vbox.add_child(rm)

	_section(vbox, "Camera", Color("6ec6ff"))
	_check(vbox, "Zoom out on hits & crashes", "collision_bump_zoom", JuiceSettings.collision_bump_zoom)
	_float_row(vbox, "Zoom-out distance", "cam_zoom_amount", 0.05, "+%.0f%%", 100.0)
	_float_row(vbox, "Zoom-out time", "cam_zoom_out_time", 0.05, "%.2f s")
	_float_row(vbox, "Hold after last hit", "cam_zoom_hold", 0.05, "%.2f s")
	_float_row(vbox, "Ease-back time", "cam_zoom_return_time", 0.1, "%.1f s")
	_check(vbox, "Screen shake on taking a hit", "hit_screen_shake", JuiceSettings.hit_screen_shake)
	_float_row(vbox, "Hit shake strength", "hit_shake_strength", 0.05, "×%.2f")

	_section(vbox, "Chase camera feel", Color("6ec6ff"))
	_float_row(vbox, "Turn-follow speed (lower = ship swings in frame)", "cam_follow_rate", 0.5, "%.1f /s")
	_float_row(vbox, "Position smoothing (lower = floatier)", "cam_position_smooth", 0.25, "%.2f /s")
	_float_row(vbox, "Aim smoothing (lower = floatier)", "cam_aim_smooth", 0.25, "%.2f /s")
	_float_row(vbox, "Look into turns", "cam_turn_lead", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Swing wide in turns", "cam_turn_swing", 0.05, "×%.2f")
	_float_row(vbox, "Bank into turns", "cam_bank_mult", 0.05, "×%.2f")
	_float_row(vbox, "Speed FOV stretch", "cam_speed_fov", 0.5, "+%.1f°")

	_section(vbox, "Combat feel", Color("ff9a1f"))
	_float_row(vbox, "Weapon energy floor (keeps guns firing)", "weapon_sustain", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Explosions shove you", "player_blast_push", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Explosions spin you out", "player_blast_spin", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Recoil on your ship", "player_recoil", 0.05, "%.0f%%", 100.0)
	_check(vbox, "Combo counter (x2, x3 …) for kills chained close together", "combo_counter", JuiceSettings.combo_counter)
	_float_row(vbox, "  chain window", "chain_window", 0.1, "%.1f s")
	_check(vbox, "POW! / BAM! pop where the hit happened (not on the HUD)", "world_hit_words", JuiceSettings.world_hit_words)

	_section(vbox, "Power-ups & shields", Color("3fa9ff"))
	_check(vbox, "Kills drop power-ups (EMP, boost, shield)", "power_ups", JuiceSettings.power_ups)
	_float_row(vbox, "  drop chance", "powerup_drop_chance", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "  orbs float for", "powerup_life", 1.0, "%.0f s")
	_float_row(vbox, "  EMP freeze", "powerup_emp_time", 0.5, "%.1f s")
	_float_row(vbox, "  EMP reach", "powerup_emp_radius", 50.0, "%.0f m")
	_float_row(vbox, "  boost lasts", "powerup_boost_time", 0.5, "%.1f s")
	_float_row(vbox, "  boost attack", "powerup_boost_power", 0.1, "×%.2f")
	_float_row(vbox, "  boost speed", "powerup_boost_speed", 0.05, "×%.2f")
	_float_row(vbox, "  shield lasts", "powerup_shield_time", 1.0, "%.0f s")
	_float_row(vbox, "  shield strength (× hull)", "powerup_shield_hp", 0.05, "×%.2f")
	_check(vbox, "Old always-on shield from the ship design", "design_shields", JuiceSettings.design_shields)
	_check(vbox, "Some enemies wear a shield veil", "enemy_shields", JuiceSettings.enemy_shields)
	_float_row(vbox, "  shielded share", "enemy_shield_chance", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "  veil strength (× hull)", "enemy_shield_hp", 0.05, "×%.2f")
	_section(vbox, "Callouts & marks", Color("ff2a4a"))
	_check(vbox, "Persona-style callouts from your ship", "player_callouts", JuiceSettings.player_callouts)
	_check(vbox, "Enemies pop ! and ?", "enemy_marks", JuiceSettings.enemy_marks)
	_float_row(vbox, "  one ship's gap between marks", "enemy_mark_cooldown", 0.5, "%.1f s")
	_check(vbox, "Tutorial on the first flight", "tutorial_on", JuiceSettings.tutorial_on)

	_section(vbox, "Kill cam", Color("ff5fa2"))
	_check(vbox, "Kill cam: pause & zoom in on ships you destroy", "kill_cam", JuiceSettings.kill_cam)
	_float_row(vbox, "Kill cam chance", "kill_cam_chance", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Hold on the wreck", "kill_cam_hold", 0.05, "%.2f s")
	_float_row(vbox, "Swoop in / out time", "kill_cam_blend", 0.05, "%.2f s")
	_float_row(vbox, "Swoop in slower by", "kill_cam_ease_in", 0.1, "×%.1f")
	_float_row(vbox, "Game speed during kill cam (0 = paused)", "kill_cam_time_scale", 0.01, "%.0f%%", 100.0)
	_float_row(vbox, "Camera distance (hull radii)", "kill_cam_distance", 0.1, "×%.1f")
	_float_row(vbox, "Cooldown between kill cams", "kill_cam_cooldown", 0.5, "%.1f s")

	_section(vbox, "Freeze frames", Color("ffe14d"))
	_check(vbox, "Freeze frames (master switch)", "kill_freeze_frame", JuiceSettings.kill_freeze_frame)
	_float_row(vbox, "Freeze depth (100% = full stop)", "freeze_depth", 0.01, "%.0f%%", 100.0)
	_check(vbox, "Freeze when you get hit", "freeze_on_player_hit", JuiceSettings.freeze_on_player_hit)
	_float_row(vbox, "  length", "freeze_hit_ms", 5.0, "%.0f ms")
	_float_row(vbox, "  only hits bigger than (% of hull)", "freeze_hit_threshold", 0.01, "%.0f%%", 100.0)
	_check(vbox, "Freeze when you hit an enemy", "freeze_on_enemy_hit", JuiceSettings.freeze_on_enemy_hit)
	_float_row(vbox, "  length", "freeze_enemy_hit_ms", 5.0, "%.0f ms")
	_check(vbox, "Freeze on your kills (and your death)", "freeze_on_kill", JuiceSettings.freeze_on_kill)
	_float_row(vbox, "  length", "freeze_kill_ms", 5.0, "%.0f ms")

	_section(vbox, "Explosions", Color("ff8844"))
	_check(vbox, "Secondary blast on ship death", "enemy_death_random_explosion", JuiceSettings.enemy_death_random_explosion)
	_float_row(vbox, "Secondary blast chance", "kill_explosion_chance", 0.01, "%.0f%%", 100.0)
	_float_row(vbox, "Death explosion size", "kill_explosion_size", 0.05, "×%.2f")
	_float_row(vbox, "Kill screen shake", "kill_shake", 0.05, "×%.2f")
	_float_row(vbox, "Kill screen flash", "kill_flash", 0.05, "×%.2f")
	_float_row(vbox, "Hit spark / explosion size", "hit_vfx_scale", 0.05, "×%.2f")
	_float_row(vbox, "Shield forcefield flash", "shield_fx_intensity", 0.05, "%.0f%%", 100.0)

	_section(vbox, "Emotes", Color("7df9ff"))
	_check(vbox, "Your ship emotes", "player_emotes", JuiceSettings.player_emotes)
	_float_row(vbox, "  chance per reaction", "player_emote_chance", 0.05, "%.0f%%", 100.0)
	_check(vbox, "Enemy ships emote", "enemy_emotes", JuiceSettings.enemy_emotes)
	_float_row(vbox, "  chance per reaction", "enemy_emote_chance", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Emote size (0 = off)", "emote_size", 0.1, "×%.1f")

	_section(vbox, "Hit feel", Color("ffb347"))
	_check(vbox, "Squash & stretch on hit", "hit_squash_stretch", JuiceSettings.hit_squash_stretch)
	_float_row(vbox, "Squash depth", "squash_strength", 0.05, "×%.2f")
	_check(vbox, "Knockback on hit", "hit_knockback", JuiceSettings.hit_knockback)
	_check(vbox, "Knockback moves the hull only (no jitter)", "knockback_visual", JuiceSettings.knockback_visual)
	_float_row(vbox, "Knockback strength", "hit_knockback_strength", 0.05, "×%.2f")
	_float_row(vbox, "Knockback spring-back time", "knockback_return_time", 0.02, "%.2f s")
	_check(vbox, "Near-miss slow-mo", "near_miss_slowmo", JuiceSettings.near_miss_slowmo)

	_section(vbox, "Sound", Color("c9a0ff"))
	_check(vbox, "Shot sounds at their own pace (no overlap)", "shot_sound_interval", JuiceSettings.shot_sound_interval)
	_float_row(vbox, "Gap between shot sounds", "shot_sound_interval_pct", 5.0, "%.0f%% of length")

	_section(vbox, "Enemy AI", Color("ff6f60"))
	_check(vbox, "Attack in bursts, take turns on the player", "ai_attack_pacing", JuiceSettings.ai_attack_pacing)
	_float_row(vbox, "Max ships shooting you at once", "ai_max_attackers", 1.0, "%.0f")
	_float_row(vbox, "Rest between bursts", "ai_rest_mult", 0.05, "×%.2f")
	_check(vbox, "Stay in front once spotted", "ai_flank_enabled", JuiceSettings.ai_flank_enabled)
	_check(vbox, "Flankers match your speed (even reverse)", "ai_speed_match", JuiceSettings.ai_speed_match)
	_slider_row(vbox, "Flank chance", 0.0, 1.5, 0.05, JuiceSettings.ai_flank_chance_mult, JuiceSettings.set_ai_flank_chance_mult)
	_check(vbox, "Popcorn enemies (weak ships pop on ram)", "popcorn_enemies_enabled", JuiceSettings.popcorn_enemies_enabled)

	_section(vbox, "Enemy fire patterns (bullet hell)", Color("ff5fd2"))
	_check(vbox, "Each enemy fires its own style (streams, fans, orbs, spirals…)", "ai_fire_patterns", JuiceSettings.ai_fire_patterns)
	_float_row(vbox, "Style variety (0 = weapon's own rhythm)", "ai_fire_variety", 0.05, "×%.2f")
	_check(vbox, "Enemy shots are real (dodge them)", "ai_real_projectiles", JuiceSettings.ai_real_projectiles)
	_float_row(vbox, "Enemy shot damage", "enemy_shot_damage_scale", 0.01, "%.0f%%", 100.0)
	var pat_note := Label.new()
	pat_note.text = "Style changes apply to ships that spawn from now on."
	pat_note.add_theme_font_size_override("font_size", 10)
	pat_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	vbox.add_child(pat_note)

	_section(vbox, "Cheats in your favour", Color("7dffb0"))
	_check(vbox, "Ships you can't see barely shoot at you", "cheat_offscreen_mercy", JuiceSettings.cheat_offscreen_mercy)
	_float_row(vbox, "  shots each, while out of view", "offscreen_shots", 1.0, "%.0f")
	_float_row(vbox, "  per (seconds out of view)", "offscreen_window", 1.0, "%.0f s")
	_check(vbox, "Ships you chase keep ahead (carried at your speed)", "cheat_chase_assist", JuiceSettings.cheat_chase_assist)
	_float_row(vbox, "  only within", "chase_assist_range", 10.0, "%.0f m")
	_float_row(vbox, "  share of your speed", "chase_assist_strength", 0.05, "%.0f%%", 100.0)

	_section(vbox, "Target markers", Color("ff3b3b"))
	_check(vbox, "Spray-paint targets on ships you've tangled with", "interaction_markers", JuiceSettings.interaction_markers)
	_check(vbox, "  and red ones on shoot-on-sight ships as soon as they're on screen", "markers_show_hostile", JuiceSettings.markers_show_hostile)
	_float_row(vbox, "  remember a ship for", "interaction_memory", 1.0, "%.0f s")
	_float_row(vbox, "  size up close", "marker_max_scale", 0.05, "×%.2f")
	_float_row(vbox, "  size far away", "marker_min_scale", 0.05, "×%.2f")

	_section(vbox, "Hit explosions", Color("ff8844"))
	_check(vbox, "Hits blow chunks off hulls (not just deaths)", "hit_explosions", JuiceSettings.hit_explosions)
	_float_row(vbox, "  chance on a light hit", "hit_explosion_chance", 0.01, "%.0f%%", 100.0)
	_float_row(vbox, "  size", "hit_explosion_size", 0.05, "×%.2f")

	_section(vbox, "Aim", Color("ffb03a"))
	_check(vbox, "Guns fire from the steady ship frame (not the wobbling hull)", "shot_stable_frame", JuiceSettings.shot_stable_frame)
	_float_row(vbox, "How far a gun may bend to the sight", "muzzle_convergence_deg", 1.0, "%.0f°")
	_check(vbox, "Side & rear guns hold fire (no shots through the hull)", "offaxis_guns_hold", JuiceSettings.offaxis_guns_hold)
	_float_row(vbox, "Your spread", "player_spread_mult", 0.05, "×%.2f")
	_float_row(vbox, "Enemy spread", "enemy_spread_mult", 0.05, "×%.2f")
	_float_row(vbox, "Your weapon cooldown", "player_cooldown_mult", 0.05, "×%.2f")

	_section(vbox, "Respawn", Color("46ff9b"))
	_float_row(vbox, "Can't be hurt after respawning for", "respawn_grace", 0.5, "%.1f s")

	_section(vbox, "Performance", Color("9ad0ff"))
	_float_row(vbox, "Enemy shots in the air (whole game)", "max_enemy_shots", 10.0, "%.0f")
	_float_row(vbox, "Explosions at once", "max_live_explosions", 1.0, "%.0f")
	_check(vbox, "Skip effects you can't see (off-screen, far away)", "cull_offscreen_fx", JuiceSettings.cull_offscreen_fx)
	_check(vbox, "Reuse shot objects (pooling)", "shot_pooling", JuiceSettings.shot_pooling)
	var note := Label.new()
	note.text = "Health, damage and enemy stats live in the 🧪 Stats panel; movement profiles, camera gestures and aim assist in 🎮 Controls."
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)


func _section(vbox: VBoxContainer, text: String, color: Color) -> void:
	vbox.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)


## A bool effect toggle, saved through [method JuiceSettings.set_effect].
func _check(vbox: VBoxContainer, text: String, field: String, value: bool) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = value
	check.toggled.connect(func(on: bool) -> void: JuiceSettings.set_effect(field, on))
	vbox.add_child(check)


## A slider for one of [constant JuiceSettings.FLOAT_RANGES]' dials, saved
## through [method JuiceSettings.set_float]. [param display_mult] only scales
## the readout (e.g. 0.7 shown as "+70%").
func _float_row(
	vbox: VBoxContainer, text: String, field: String, step: float, fmt: String,
	display_mult := 1.0
) -> void:
	var r: Vector2 = JuiceSettings.FLOAT_RANGES[field]
	_slider_row(
		vbox, text, r.x, r.y, step, JuiceSettings.get_float(field),
		func(v: float) -> void: JuiceSettings.set_float(field, v), fmt, display_mult
	)


## One label + slider + live value row. The initial value is set without a
## signal so opening the panel never re-saves a dial nobody touched.
func _slider_row(
	vbox: VBoxContainer, label_text: String, min_v: float, max_v: float,
	step: float, value: float, setter: Callable, fmt: String = "×%.2f",
	display_mult := 1.0
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170.0, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	slider.set_value_no_signal(value)
	var value_label := Label.new()
	value_label.text = fmt % (value * display_mult)
	value_label.custom_minimum_size = Vector2(80.0, 0.0)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		if is_instance_valid(value_label):
			value_label.text = fmt % (v * display_mult)
	)

