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
## Difficulty: the presets of [Difficulty] (its table is edited in the workbench).
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
## The help card for the row being hovered, focused or tapped: bottom right,
## or along the bottom on a portrait screen.
var _tip_card: PanelContainer
var _tip_label: Label
var _tip_tween: Tween = null


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
	_build_tip()
	layout()


## Hover/long-press help for each row, keyed by its label.
const TIPS := {
	"CONTROLS": "How you steer: swipe, slingshot or first-person. Tap to cycle.",
	"SOUND": "Effects volume.",
	"MUSIC": "Music volume.",
	"SHAKE": "FULL shakes the screen on hits; LESS tones the camera shake down.",
	"GAMEPLAY": "Camera distances, fling feel, kill cam and control details.",
	"PERFORMANCE": "Graphics quality and battery settings.",
	"DIFFICULTY": "How hard the fights are: Easy, Normal or Hard.",
	"ACCESSIBILITY": "Flashes, slow-motion, freeze frames and callouts.",
	"STATS": "Time played, yeets, planets destroyed, ships bought and more.",
	"RESET PROGRESS": "Wipes coins, ships and level records. Asks twice.",
	"WORKBENCH": "Developer builder and labs.",
	"SHIP FACES": "Little faces on ships that react to the fight.",
	"GRAPHICS": "Overall look: higher is prettier, lower is faster.",
	"BATTERY SAVER": "Caps the frame rate and trims effects to save battery.",
	"SHADOWS": "Off, sun only, or all lights casting shadows.",
	"GLOW": "Bloom glow on bright things like engines and shots.",
	"RESOLUTION": "Render scale. Lower is faster but softer.",
	"MAX SHIPS": "Most AI ships alive at once.",
	"EFFECTS": "How many particle effects can play at once.",
	"WRECKAGE": "How many wreck pieces stay around.",
	"CAMERA AT REST": "How far back the camera sits while you are aiming.",
	"CAMERA CLOSEST": "How close the camera can get to your ship.",
	"FLING ZOOM OUT": "How far the camera pulls out as you stretch the sling.",
	"CAMERA FURTHEST": "Farthest the camera drifts out at speed.",
	"LOOK AHEAD": "Camera leans toward where you are heading.",
	"LOOK AHEAD TIME": "How many seconds ahead the camera looks.",
	"AIM LOOK AHEAD": "Camera leans along your aim while you pull back.",
	"AIM ZOOM OUT": "Extra zoom out while aiming.",
	"EASE IN NEAR SHIPS": "Camera eases in when other ships are close.",
	"FLING POWER": "How hard a full pull launches your ship.",
	"FLING AIM": "Aim style: classic, dome or smart.",
	"AIM INTO SCREEN": "How much of your aim goes into the screen (depth).",
	"GRAB AREA": "How big the touch area around your ship is.",
	"LAUNCH MAGNET": "Pulls your launch toward the nearest enemy.",
	"CAMERA SWING SPEED": "How quickly camera gestures turn the view.",
	"CAMERA BEHIND IN FLIGHT": "Keeps the camera behind your ship while you fly.",
	"CAMERA TURN SPEED": "Fastest the camera may rotate, in degrees per second.",
	"KILL CAM": "Slow-motion replay of big kills.",
	"KILL CAM CHANCE": "How often a kill gets the kill cam.",
	"KILL CAM LENGTH": "How long the kill cam lasts.",
	"KILL CAM SLOW-MO": "How slow time runs during the kill cam.",
	"PINCH ZOOM": "Pinch with two fingers to zoom the camera.",
	"DRAG TO LOOK": "Drag away from your ship to turn the camera.",
	"AIM ASSIST": "Nudges your shots toward targets.",
	"AUTO AIM": "Tapping the sling picks a target for you.",
	"AUTO FIRE": "Guns fire by themselves: off, when aimed, or always.",
	"POWER-UPS": "Pickups that drop from wrecks.",
	"FLASHES": "Screen flashes on kills and hits.",
	"SLOW-MO": "Brief slow-motion on near misses.",
	"FREEZE FRAMES": "A split-second freeze on kills.",
	"CALLOUTS": "Spoken-style text callouts during the fight.",
}

# --- Pages ------------------------------------------------------------------------

func _main_rows() -> Array:
	var rows := [
		_spec("CONTROLS", GraffitiStyle.CYAN, _controls_word, _cycle_controls),
		_spec("SCREEN", GraffitiStyle.SUN, _orientation_word, _cycle_orientation),
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
		_spec("STATS", GraffitiStyle.LIME, func() -> String: return "YOUR RECORD  >",
			func() -> void: _open_sub("STATS")),
		_spec("RESET PROGRESS", GraffitiStyle.HOT, func() -> String:
			return "SURE? TAP AGAIN" if _reset_armed else "WIPES COINS & SHIPS", _on_reset),
	]
	if Session.debug_mode:
		rows.append(_spec("WORKBENCH", Color("3a3150"), func() -> String: return "BUILDER & LABS",
			func() -> void: menu.open_workbench()))
	rows.append(_spec("SHIP FACES", GraffitiStyle.SUN, func() -> String:
		return "ON" if JuiceSettings.player_emotes or JuiceSettings.enemy_emotes else "OFF", _toggle_faces))
	return rows


func _sub_rows(which: String) -> Array:
	match which:
		"STATS":
			return [
				_stat_row("TIME PLAYED", GraffitiStyle.SUN, "time_played", true),
				_stat_row("FLIGHTS", GraffitiStyle.CYAN, "flights"),
				_stat_row("LEVELS WON", GraffitiStyle.LIME, "wins"),
				_stat_row("SHIPS WRECKED", GraffitiStyle.HOT, "kills"),
				_stat_row("YEETS", GraffitiStyle.ORANGE, "yeets"),
				_stat_row("PLANETS DESTROYED", GraffitiStyle.VIOLET, "planets_destroyed"),
				_stat_row("SHIPS BOUGHT", GraffitiStyle.SUN, "ships_bought"),
				_stat_row("UPGRADES BOUGHT", GraffitiStyle.CYAN, "upgrades_bought"),
				_stat_row("TIMES WRECKED", GraffitiStyle.HOT, "deaths"),
			]
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


## A read-only slab on the STATS page.
func _stat_row(text: String, col: Color, key: String, as_time := false) -> Dictionary:
	return _spec(text, col, func() -> String:
		var v := Campaign.stat_value(key)
		if as_time:
			var secs := int(v)
			return "%dH %02dM" % [secs / 3600, (secs % 3600) / 60] if secs >= 3600 else "%dM %02dS" % [secs / 60, secs % 60]
		return str(int(v)), func() -> void: pass)


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
		var tip := String(TIPS.get(b.text, ""))
		if tip != "":
			b.mouse_entered.connect(_show_tip.bind(tip))
			b.mouse_exited.connect(_hide_tip)
			b.focus_entered.connect(_show_tip.bind(tip))
			b.focus_exited.connect(_hide_tip)
			# Touch has no hover: a tap shows the tip too.
			b.pressed.connect(_show_tip.bind(tip))
		b.fill = spec["color"]
		b.pass_drag = true
		b.text_color = Color.WHITE
		b.pressed.connect(_on_row.bind(b))
		content.add_child(b)
		_rows[b] = spec
	return sc


# --- Tip card -------------------------------------------------------------------

func _build_tip() -> void:
	_tip_card = PanelContainer.new()
	_tip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_card.modulate.a = 0.0
	_tip_card.z_index = 10
	var box := StyleBoxFlat.new()
	box.bg_color = GraffitiStyle.INK
	box.border_color = GraffitiStyle.SUN
	box.set_border_width_all(4)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(14)
	box.shadow_color = GraffitiStyle.SHADOW
	box.shadow_size = 8
	box.shadow_offset = Vector2(4, 6)
	_tip_card.add_theme_stylebox_override("panel", box)
	_tip_label = GraffitiStyle.label("", 22, Color.WHITE, 0)
	_tip_label.add_theme_font_override("font", GraffitiStyle.tip_font())
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_card.add_child(_tip_label)
	add_child(_tip_card)


func _show_tip(text: String) -> void:
	if _tip_card == null:
		return
	_tip_label.text = text
	_place_tip()
	if _tip_tween != null:
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_card, "modulate:a", 1.0, 0.12)
	# A tap leaves no mouse-exit behind, so the card lets go by itself.
	_tip_tween.tween_interval(3.5)
	_tip_tween.tween_property(_tip_card, "modulate:a", 0.0, 0.4)


func _hide_tip() -> void:
	if _tip_card == null:
		return
	if _tip_tween != null:
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_card, "modulate:a", 0.0, 0.2)


func _place_tip() -> void:
	var vp := viewport_size()
	var u := unit()
	var port := portrait()
	var w := vp.x - 40.0 if port else clampf(vp.x * 0.34, 280.0, 520.0 * u)
	_tip_label.add_theme_font_size_override("font_size", int(clampf(vp.y * (0.034 if port else 0.04), 18.0, 30.0 * u)))
	_tip_label.custom_minimum_size.x = w - 28.0
	_tip_card.custom_minimum_size = Vector2(w, 0)
	_tip_card.reset_size()
	_tip_card.pivot_offset = _tip_card.size * 0.5
	_tip_card.rotation = 0.0 if port else -0.03
	var margin := 20.0
	_tip_card.position = Vector2(vp.x - _tip_card.size.x - margin, vp.y - _tip_card.size.y - margin)


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
	if _tip_card != null and _tip_card.modulate.a > 0.0:
		_place_tip()
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


func _orientation_word() -> String:
	return "PORTRAIT" if bool(Session.pref("portrait", false)) else "LANDSCAPE (DEFAULT)"


func _cycle_orientation() -> void:
	Session.prefs["portrait"] = not bool(Session.pref("portrait", false))
	Session.save_to_disk()
	MenuRoot.apply_orientation()


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
	Difficulty.v("player_hull")
	return Difficulty.preset


## Easy / Normal / Hard: which preset of the shipped difficulty table is played.
func _cycle_difficulty() -> void:
	Difficulty.set_preset((Difficulty.preset + 1) % Difficulty.PRESET_NAMES.size())


func _cycle_aim_assist() -> void:
	var steps := [0.0, 0.5, 1.0]
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - JuiceSettings.aim_assist_strength) < 0.05:
			i = k
	JuiceSettings.set_aim_assist_strength(steps[(i + 1) % steps.size()])
