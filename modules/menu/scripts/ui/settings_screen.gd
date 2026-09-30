## SettingsScreen: the things a player wants to change before flying, as big
## slabs that cycle their value on each tap — no sliders to hit with a thumb.
##
## A scrolling main page (CONTROLS, SOUND, SHAKE, four submenus, RESET
## PROGRESS, WORKBENCH, DEBUG and SHIP FACES at the bottom). GAMEPLAY (the
## fling camera and the controls' feel), PERFORMANCE, DIFFICULTY and
## ACCESSIBILITY open submenus: the main page slides off to
## the left with a bounce while the submenu slides in from the right, and
## Back reverses it.
class_name SettingsScreen
extends MenuScreen

## Only these two: the other profiles are dev tools (FlightRoot.MoveProfile).
const PROFILE_SWIPE := 1
const PROFILE_SLING := 2
const VOLUMES: Array[float] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0]
const SLIDE_TIME := 0.42
const GRAPHICS: Array[String] = ["Smoothest", "Balanced", "Best quality"]
const GRAPHICS_WORDS: Array[String] = ["SMOOTH", "BALANCED", "BEST"]
## Difficulty: [damage the player takes, enemy hull].
## NORMAL used to be 1.0 / 1.0, which played too easy.
const DIFFICULTY := [[0.7, 0.85], [1.25, 1.2], [1.9, 1.6]]
const DIFFICULTY_WORDS: Array[String] = ["EASY", "NORMAL", "HARD"]
## [member JuiceSettings.sling_aim_style]: opposite the pull, round the dome, smart.
const AIM_STYLE_WORDS: Array[String] = ["CLASSIC", "DOME", "SMART"]
## [member JuiceSettings.sling_auto_shoot]: never, one volley per launch, the whole flight.
const AUTO_SHOOT_WORDS: Array[String] = ["OFF", "ONCE", "ALWAYS"]

var _bar: TopBar
## A big tag sprayed on the empty side of the wall, so the screen is not one
## lonely column of buttons.
var _tag: GraffitiTitle
## The clip the pages slide inside.
var _clip: Control
var _main: ScrollContainer
## The open submenu page, or null.
var _sub: ScrollContainer = null
var _sub_name := ""
var _slide: Tween = null
var _reset_armed := false
## Every row on screen → its spec {text, color, sub: Callable, press: Callable}.
var _rows := {}


func _ready() -> void:
	_bar = TopBar.new()
	_bar.title = "SETTINGS"
	_bar.back_pressed.connect(func() -> void:
		if not back():
			menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_tag = GraffitiTitle.new()
	_tag.text = "TWEAK IT"
	add_child(_tag)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_main = _page(_main_rows())
	_clip.add_child(_main)
	layout()


# --- Pages ------------------------------------------------------------------------

func _main_rows() -> Array:
	var rows := [
		_spec("CONTROLS", GraffitiStyle.CYAN, _controls_word, _cycle_controls),
		_spec("SOUND", GraffitiStyle.SUN, _sound_word, _cycle_sound),
		_spec("MUSIC", GraffitiStyle.HOT, _music_word, _cycle_music),
		_spec("SHAKE", GraffitiStyle.VIOLET, func() -> String:
			return "LESS" if JuiceSettings.reduce_motion else "FULL",
			func() -> void: JuiceSettings.set_reduce_motion(not JuiceSettings.reduce_motion)),
		_spec("GAMEPLAY", GraffitiStyle.SUN, func() -> String: return "CAMERA, CONTROLS  >",
			func() -> void: _open_sub("GAMEPLAY")),
		_spec("PERFORMANCE", GraffitiStyle.LIME, func() -> String: return "GRAPHICS, BATTERY  >",
			func() -> void: _open_sub("PERFORMANCE")),
		_spec("DIFFICULTY", GraffitiStyle.ORANGE, func() -> String: return DIFFICULTY_WORDS[_difficulty()] + "  >",
			func() -> void: _open_sub("DIFFICULTY")),
		_spec("ACCESSIBILITY", GraffitiStyle.CYAN, func() -> String: return "FLASHES, SLOW-MO  >",
			func() -> void: _open_sub("ACCESSIBILITY")),
		_spec("RESET PROGRESS", GraffitiStyle.HOT, func() -> String:
			return "SURE? TAP AGAIN" if _reset_armed else "WIPES COINS & SHIPS", _on_reset),
	]
	if Session.debug_mode:
		rows.append(_spec("WORKBENCH", Color("3a3150"), func() -> String: return "BUILDER & LABS",
			func() -> void: menu.open_workbench()))
	rows.append(_spec("DEBUG", Color("3a3150"), func() -> String: return "ON" if Session.debug_mode else "OFF",
		_toggle_debug))
	rows.append(_spec("SHIP FACES", GraffitiStyle.SUN, func() -> String:
		return "ON" if JuiceSettings.player_emotes or JuiceSettings.enemy_emotes else "OFF", _toggle_faces))
	return rows


func _sub_rows(which: String) -> Array:
	match which:
		"PERFORMANCE":
			return [
				_spec("GRAPHICS", GraffitiStyle.LIME, func() -> String: return GRAPHICS_WORDS[_graphics()], _cycle_graphics),
				_spec("BATTERY SAVER", GraffitiStyle.SUN, _perf_word.bind("battery_saver"), _perf_toggle.bind("battery_saver")),
				_spec("SHADOWS", GraffitiStyle.VIOLET, func() -> String:
					return ["OFF", "SUN ONLY", "ALL"][PerformanceSettings.shadows],
					_perf_cycle.bind("shadows", [0, 1, 2])),
				_spec("GLOW", GraffitiStyle.CYAN, _perf_word.bind("glow"), _perf_toggle.bind("glow")),
				_spec("RESOLUTION", GraffitiStyle.HOT, func() -> String:
					return "%d%%" % roundi(PerformanceSettings.render_scale * 100.0),
					_perf_cycle.bind("render_scale", [1.0, 0.85, 0.7])),
				_spec("MAX SHIPS", GraffitiStyle.ORANGE, func() -> String: return str(PerformanceSettings.max_ai_ships),
					_perf_cycle.bind("max_ai_ships", [6, 12, 20])),
				_spec("EFFECTS", GraffitiStyle.LIME, func() -> String: return str(PerformanceSettings.vfx_budget),
					_perf_cycle.bind("vfx_budget", [12, 32, 64])),
				_spec("WRECKAGE", GraffitiStyle.VIOLET, func() -> String: return str(PerformanceSettings.max_debris),
					_perf_cycle.bind("max_debris", [40, 120, 250])),
			]
		"GAMEPLAY":
			# Each row cycles a dial through a few steps; the fling camera
			# first, then how the controls feel.
			return [
				_dial("CAMERA AT REST", GraffitiStyle.CYAN, "sling_rest_distance", [1.0, 1.2, 1.35, 1.6, 2.0], "×%.2f"),
				_dial("CAMERA CLOSEST", GraffitiStyle.VIOLET, "sling_cam_min", [0.7, 0.85, 1.0, 1.2, 1.5], "×%.2f"),
				_dial("FLING ZOOM OUT", GraffitiStyle.HOT, "sling_zoom", [0.6, 0.9, 1.2, 1.6, 2.0], "×%.1f"),
				_dial("CAMERA FURTHEST", GraffitiStyle.ORANGE, "swipe_cam_max", [1.8, 2.2, 2.6, 3.2, 4.0], "×%.1f"),
				_dial("LOOK AHEAD", GraffitiStyle.LIME, "sling_look_ahead", [0.0, 0.3, 0.6, 0.9, 1.2], "×%.1f"),
				_dial("LOOK AHEAD TIME", GraffitiStyle.SUN, "sling_look_ahead_time", [0.2, 0.45, 0.8, 1.2], "%.2fS"),
				_dial("AIM LOOK AHEAD", GraffitiStyle.CYAN, "sling_aim_look", [0.0, 0.4, 0.7, 1.0, 1.4], "×%.1f"),
				_dial("AIM ZOOM OUT", GraffitiStyle.VIOLET, "sling_aim_zoom", [0.0, 0.15, 0.3, 0.5, 0.8], "×%.2f"),
				_dial("EASE IN NEAR SHIPS", GraffitiStyle.HOT, "sling_close_zoom", [0.0, 0.2, 0.35, 0.5], "%.0f%%", 100.0),
				_dial("FLING POWER", GraffitiStyle.ORANGE, "sling_power", [2.0, 2.5, 3.0, 3.5, 4.0], "×%.1f"),
				_spec("FLING AIM", GraffitiStyle.SUN, func() -> String:
					return AIM_STYLE_WORDS[clampi(roundi(JuiceSettings.sling_aim_style), 0, 2)],
					_juice_cycle.bind("sling_aim_style", [0.0, 1.0, 2.0])),
				_dial("AIM INTO SCREEN", GraffitiStyle.LIME, "sling_aim_depth", [0.0, 0.4, 0.75, 1.0], "%.0f%%", 100.0),
				_dial("GRAB AREA", GraffitiStyle.SUN, "grab_radius_scale", [0.7, 1.0, 1.3, 1.6], "×%.1f"),
				_dial("LAUNCH MAGNET", GraffitiStyle.CYAN, "magnet_strength", [0.0, 0.4, 0.85, 1.0], "%.0f%%", 100.0),
				_dial("CAMERA SWING SPEED", GraffitiStyle.VIOLET, "cam_gesture_speed", [0.6, 1.0, 1.4, 1.8], "×%.1f"),
				_spec("CAMERA BEHIND IN FLIGHT", GraffitiStyle.ORANGE, _juice_word.bind("sling_cam_follow_flight"), _juice_toggle.bind("sling_cam_follow_flight")),
				_dial("CAMERA TURN SPEED", GraffitiStyle.HOT, "cam_max_turn_deg", [40.0, 60.0, 75.0, 110.0, 180.0], "%.0f°/S"),
				_spec("KILL CAM", GraffitiStyle.LIME, _juice_word.bind("kill_cam"), _juice_toggle.bind("kill_cam")),
				_dial("KILL CAM CHANCE", GraffitiStyle.SUN, "kill_cam_odds", [0.0, 0.3, 0.5, 0.7, 1.0], "%.0f%%", 100.0),
				_dial("KILL CAM LENGTH", GraffitiStyle.CYAN, "kill_cam_length", [0.3, 0.45, 0.6, 0.8, 1.0], "×%.2f"),
				_dial("KILL CAM SLOW-MO", GraffitiStyle.VIOLET, "kill_cam_time_scale", [0.04, 0.15, 0.3, 0.5, 1.0], "×%.2f"),
				_spec("PINCH ZOOM", GraffitiStyle.HOT, _juice_word.bind("cam_pinch_zoom"), _juice_toggle.bind("cam_pinch_zoom")),
				_spec("DRAG TO LOOK", GraffitiStyle.ORANGE, _juice_word.bind("cam_twist_rotate"), _juice_toggle.bind("cam_twist_rotate")),
			]
		"DIFFICULTY":
			return [
				_spec("DIFFICULTY", GraffitiStyle.ORANGE, func() -> String: return DIFFICULTY_WORDS[_difficulty()], _cycle_difficulty),
				_spec("AIM ASSIST", GraffitiStyle.CYAN, func() -> String:
					return "OFF" if JuiceSettings.aim_assist_strength <= 0.01 else ("LOW" if JuiceSettings.aim_assist_strength < 0.75 else "HIGH"),
					_cycle_aim_assist),
				_spec("AUTO AIM", GraffitiStyle.LIME, _juice_word.bind("sling_tap_auto_aim"), _juice_toggle.bind("sling_tap_auto_aim")),
				_spec("AUTO FIRE", GraffitiStyle.SUN, func() -> String:
					return AUTO_SHOOT_WORDS[clampi(roundi(JuiceSettings.sling_auto_shoot), 0, 2)],
					_juice_cycle.bind("sling_auto_shoot", [0.0, 1.0, 2.0])),
				_spec("POWER-UPS", GraffitiStyle.VIOLET, _juice_word.bind("power_ups"), _juice_toggle.bind("power_ups")),
			]
		"ACCESSIBILITY":
			return [
				_spec("FLASHES", GraffitiStyle.SUN, func() -> String:
					return "FULL" if JuiceSettings.kill_flash >= 0.9 else ("SOFT" if JuiceSettings.kill_flash > 0.05 else "OFF"),
					_cycle_flashes),
				_spec("SLOW-MO", GraffitiStyle.CYAN, _juice_word.bind("near_miss_slowmo"), _juice_toggle.bind("near_miss_slowmo")),
				_spec("KILL CAM", GraffitiStyle.HOT, _juice_word.bind("kill_cam"), _juice_toggle.bind("kill_cam")),
				_spec("FREEZE FRAMES", GraffitiStyle.VIOLET, _juice_word.bind("freeze_on_kill"), _toggle_freezes),
				_spec("CALLOUTS", GraffitiStyle.LIME, _juice_word.bind("player_callouts"), _juice_toggle.bind("player_callouts")),
			]
	return []


func _spec(text: String, col: Color, sub: Callable, press: Callable) -> Dictionary:
	return {"text": text, "color": col, "sub": sub, "press": press}


## A scrolling page of slabs, placed by hand in a tilted cascade inside the
## scroll's content (a container would reset every slab's tilt).
func _page(specs: Array) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(content)
	for spec: Dictionary in specs:
		var b := SlabButton.new()
		b.text = spec["text"]
		b.fill = spec["color"]
		b.pass_drag = true
		b.text_color = Color.WHITE
		b.pressed.connect(_on_row.bind(b))
		content.add_child(b)
		_rows[b] = spec
	return sc


func _on_row(b: SlabButton) -> void:
	var spec: Dictionary = _rows.get(b, {})
	if spec.is_empty():
		return
	(spec["press"] as Callable).call()
	_refresh()


func opened() -> void:
	_reset_armed = false
	if _sub != null:
		_sub.queue_free()
		_sub = null
		_sub_name = ""
	_main.position.x = 0.0
	_refresh()
	layout()
	var first := _first_button(_main)
	if first != null:
		first.grab_focus.call_deferred()


func _refresh() -> void:
	PerformanceSettings.ensure_loaded()
	JuiceSettings.ensure_loaded()
	for b: SlabButton in _rows:
		if is_instance_valid(b):
			b.sub = String((_rows[b]["sub"] as Callable).call())


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var port := portrait()
	var bar_h := bar_height()
	var u := unit()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	var bw := clampf(vp.x * (0.84 if port else 0.46), 290.0, 600.0 * u)
	var top := bar_h + 20.0
	if port:
		# The tag goes on top; the rows fill what is left.
		_tag.position = Vector2(0, bar_h + 4)
		_tag.size = Vector2(vp.x, vp.y * 0.14)
		top += _tag.size.y
	else:
		# The tag leans on the right half, the rows cascade down the left.
		_tag.position = Vector2(vp.x * 0.52, vp.y * 0.28)
		_tag.size = Vector2(vp.x * 0.46, vp.y * 0.4)
	_tag.pivot_offset = _tag.size * 0.5
	_tag.rotation = -0.12 if not port else -0.04
	var clip_w := bw + 90.0 * u if not port else vp.x
	_clip.position = Vector2(0, top)
	_clip.size = Vector2(clip_w, vp.y - top)
	var bh := clampf(vp.y * (0.075 if port else 0.105), 56.0, 84.0 * u)
	for page in [_main, _sub]:
		if page != null:
			_lay_page(page as ScrollContainer, bw, bh, port)


func _lay_page(page: ScrollContainer, bw: float, bh: float, port: bool) -> void:
	page.size = _clip.size
	var content := page.get_child(0) as Control
	var rows := content.get_children()
	var gap := bh * 0.3
	var x0 := maxf(30.0, _clip.size.x * 0.05)
	for i in rows.size():
		var b := rows[i] as SlabButton
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = b.custom_minimum_size
		b.font_size = int(bh * 0.4)
		var x := (14.0 if i % 2 == 0 else _clip.size.x - bw - 14.0) if port else x0 + (i % 3) * bh * 0.25
		b.position = Vector2(x, 14.0 + i * (bh + gap))
		b.pivot_offset = b.size * 0.5
		b.rotation = [0.02, -0.025, 0.015, -0.02, 0.028, -0.015][i % 6]
	# Room under the last slab for its drips and shadow.
	content.custom_minimum_size = Vector2(_clip.size.x, 14.0 + rows.size() * (bh + gap) + bh * 0.6)


# --- Submenus -------------------------------------------------------------------

func _open_sub(which: String) -> void:
	if _sub != null:
		return
	_sub_name = which
	_sub = _page(_sub_rows(which))
	_clip.add_child(_sub)
	_bar.set_title(which)
	GameAudio.ui(&"open")
	_refresh()
	layout()
	var w := _clip.size.x
	_sub.position.x = w
	_kill_slide()
	_slide = create_tween().set_parallel()
	_slide.tween_property(_main, "position:x", -w, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	_slide.tween_property(_sub, "position:x", 0.0, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	var first := _first_button(_sub)
	if first != null:
		first.grab_focus.call_deferred()


func _close_sub() -> void:
	if _sub == null:
		return
	var going := _sub
	_sub = null
	_sub_name = ""
	for b in going.get_child(0).get_children():
		_rows.erase(b)
	_bar.set_title("SETTINGS")
	GameAudio.ui(&"close")
	var w := _clip.size.x
	_kill_slide()
	_slide = create_tween().set_parallel()
	_slide.tween_property(going, "position:x", w, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	_slide.tween_property(_main, "position:x", 0.0, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	_slide.chain().tween_callback(going.queue_free)
	_refresh()
	var first := _first_button(_main)
	if first != null:
		first.grab_focus.call_deferred()


func _kill_slide() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()


## Back: out of a submenu first.
func back() -> bool:
	if _sub != null:
		_close_sub()
		return true
	return false


func _first_button(page: ScrollContainer) -> SlabButton:
	var content := page.get_child(0)
	return content.get_child(0) as SlabButton if content.get_child_count() > 0 else null


# --- Values -----------------------------------------------------------------------

func _controls_word() -> String:
	return "SWIPE" if Session.move_profile == PROFILE_SWIPE else "SLINGSHOT (DEFAULT)"


func _cycle_controls() -> void:
	Session.move_profile = PROFILE_SLING if Session.move_profile == PROFILE_SWIPE else PROFILE_SWIPE
	Session.save_to_disk()


func _sound_word() -> String:
	var vol := float(Session.pref("master_volume", GameAudio.DEFAULT_VOLUME))
	return "OFF" if vol <= 0.001 else "%d%%" % roundi(vol * 100.0)


func _cycle_sound() -> void:
	var vol := float(Session.pref("master_volume", GameAudio.DEFAULT_VOLUME))
	var i := 0
	for k in VOLUMES.size():
		if absf(VOLUMES[k] - vol) < 0.01:
			i = k
	Session.prefs["master_volume"] = VOLUMES[(i + 1) % VOLUMES.size()]
	Session.save_to_disk()
	MenuRoot.apply_volume()


func _music_word() -> String:
	var vol := float(Session.pref("music_volume", GameAudio.DEFAULT_VOLUME))
	return "OFF" if vol <= 0.001 else "%d%%" % roundi(vol * 100.0)


func _cycle_music() -> void:
	var vol := float(Session.pref("music_volume", GameAudio.DEFAULT_VOLUME))
	var i := 0
	for k in VOLUMES.size():
		if absf(VOLUMES[k] - vol) < 0.01:
			i = k
	Session.prefs["music_volume"] = VOLUMES[(i + 1) % VOLUMES.size()]
	Session.save_to_disk()
	MenuRoot.apply_volume()


func _toggle_debug() -> void:
	Session.debug_mode = not Session.debug_mode
	Session.save_to_disk()
	# WORKBENCH comes and goes with it: rebuild the main page.
	for b in _main.get_child(0).get_children():
		_rows.erase(b)
	_main.queue_free()
	_main = _page(_main_rows())
	_clip.add_child(_main)
	_clip.move_child(_main, 0)
	layout()


func _toggle_faces() -> void:
	var on := not (JuiceSettings.player_emotes or JuiceSettings.enemy_emotes)
	JuiceSettings.set_effect("player_emotes", on)
	JuiceSettings.set_effect("enemy_emotes", on)


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		return
	_reset_armed = false
	Campaign.reset()


func _perf_word(field: String) -> String:
	return "ON" if bool(PerformanceSettings.get_value(field)) else "OFF"


func _perf_toggle(field: String) -> void:
	PerformanceSettings.set_value(field, not bool(PerformanceSettings.get_value(field)))
	PerformanceSettings.apply(get_tree())


func _perf_cycle(field: String, steps: Array) -> void:
	var now: Variant = PerformanceSettings.get_value(field)
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - float(now)) < 0.01:
			i = k
	PerformanceSettings.set_value(field, steps[(i + 1) % steps.size()])
	PerformanceSettings.apply(get_tree())


## Which graphics preset the dials match best (by shadows and resolution).
func _graphics() -> int:
	if PerformanceSettings.shadows == 0 and PerformanceSettings.render_scale < 0.9:
		return 0
	if PerformanceSettings.shadows == 2 and PerformanceSettings.msaa > 0:
		return 2
	return 1


func _cycle_graphics() -> void:
	PerformanceSettings.apply_preset(GRAPHICS[(_graphics() + 1) % GRAPHICS.size()])
	PerformanceSettings.apply(get_tree())


## A row cycling the float dial [param field] through [param steps] (the next
## step up from its value, wrapping), shown with [param fmt] × [param show].
func _dial(text: String, col: Color, field: String, steps: Array, fmt: String, show := 1.0) -> Dictionary:
	return _spec(text, col, func() -> String: return fmt % (JuiceSettings.get_float(field) * show),
		_juice_cycle.bind(field, steps))


func _juice_cycle(field: String, steps: Array) -> void:
	var now := JuiceSettings.get_float(field)
	var next := float(steps[0])
	for v in steps:
		if float(v) > now + 0.001:
			next = float(v)
			break
	JuiceSettings.set_float(field, next)


func _juice_word(field: String) -> String:
	return "ON" if JuiceSettings.get_effect(field) else "OFF"


func _juice_toggle(field: String) -> void:
	JuiceSettings.set_effect(field, not JuiceSettings.get_effect(field))


func _toggle_freezes() -> void:
	var on := not JuiceSettings.freeze_on_kill
	JuiceSettings.set_effect("freeze_on_kill", on)
	JuiceSettings.set_effect("freeze_on_player_hit", on)


func _cycle_flashes() -> void:
	var steps := [1.0, 0.4, 0.0]
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - JuiceSettings.kill_flash) < 0.05:
			i = k
	JuiceSettings.set_float("kill_flash", steps[(i + 1) % steps.size()])


func _difficulty() -> int:
	var best := 1
	var bd := INF
	for i in DIFFICULTY.size():
		var d := absf(float(DIFFICULTY[i][0]) - JuiceSettings.player_damage_taken_mult)
		if d < bd:
			bd = d
			best = i
	return best


func _cycle_difficulty() -> void:
	var nxt: Array = DIFFICULTY[(_difficulty() + 1) % DIFFICULTY.size()]
	JuiceSettings.set_float("player_damage_taken_mult", float(nxt[0]))
	JuiceSettings.set_float("enemy_hp_mult", float(nxt[1]))


func _cycle_aim_assist() -> void:
	var steps := [0.0, 0.5, 1.0]
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - JuiceSettings.aim_assist_strength) < 0.05:
			i = k
	JuiceSettings.set_aim_assist_strength(steps[(i + 1) % steps.size()])
