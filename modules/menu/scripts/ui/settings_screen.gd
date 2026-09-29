## SettingsScreen: the few things a player wants to change before flying,
## as big slabs that cycle their value on each tap — no sliders to hit with
## a thumb. Everything else lives in the flight scene's own panels.
##
## CONTROLS (the movement profile), SOUND, BATTERY SAVER, SHAKE, RESET
## PROGRESS (tap twice), and WORKBENCH — the old module launcher with the
## builder and the labs.
class_name SettingsScreen
extends MenuScreen

const PROFILES: Array[String] = ["CLASSIC", "SWIPE", "SLINGSHOT", "FPS"]
const VOLUMES: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]

var _bar: TopBar
var _column: Control
## A big tag sprayed on the empty side of the wall, so the screen is not one
## lonely column of buttons.
var _tag: GraffitiTitle
var _controls: SlabButton
var _sound: SlabButton
var _battery: SlabButton
var _shake: SlabButton
var _reset: SlabButton
var _bench: SlabButton
var _reset_armed := false


func _ready() -> void:
	_bar = TopBar.new()
	_bar.title = "SETTINGS"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_tag = GraffitiTitle.new()
	_tag.text = "TWEAK IT"
	add_child(_tag)
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_controls = _row("CONTROLS", GraffitiStyle.CYAN, _cycle_controls)
	_sound = _row("SOUND", GraffitiStyle.SUN, _cycle_sound)
	_battery = _row("BATTERY SAVER", GraffitiStyle.LIME, _toggle_battery)
	_shake = _row("SHAKE", GraffitiStyle.VIOLET, _toggle_shake)
	_reset = _row("RESET PROGRESS", GraffitiStyle.HOT, _on_reset)
	_bench = _row("WORKBENCH", Color("3a3150"), func() -> void: menu.open_workbench())
	layout()


func _row(label: String, col: Color, on_press: Callable) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.fill = col
	b.text_color = GraffitiStyle.INK if col in [GraffitiStyle.CYAN, GraffitiStyle.SUN, GraffitiStyle.LIME] else Color.WHITE
	b.pressed.connect(on_press)
	_column.add_child(b)
	return b


func opened() -> void:
	_reset_armed = false
	_refresh()
	layout()
	_controls.grab_focus.call_deferred()


func _refresh() -> void:
	_controls.sub = PROFILES[clampi(Session.move_profile, 0, PROFILES.size() - 1)]
	var vol := float(Session.pref("master_volume", 1.0))
	_sound.sub = "OFF" if vol <= 0.001 else "%d%%" % roundi(vol * 100.0)
	PerformanceSettings.ensure_loaded()
	_battery.sub = "ON" if PerformanceSettings.battery_saver else "OFF"
	JuiceSettings.ensure_loaded()
	_shake.sub = "LESS" if JuiceSettings.reduce_motion else "FULL"
	_reset.sub = "SURE? TAP AGAIN" if _reset_armed else "WIPES COINS & SHIPS"
	_bench.sub = "BUILDER & LABS"


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var port := portrait()
	var bar_h := bar_height()
	var u := unit()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	var rows := _column.get_children()
	var n := rows.size()
	var bw := clampf(vp.x * (0.84 if port else 0.46), 290.0, 600.0 * u)
	var avail := vp.y - bar_h - 36.0
	if port:
		# The tag goes on top; the rows fill what is left.
		_tag.position = Vector2(0, bar_h + 4)
		_tag.size = Vector2(vp.x, vp.y * 0.16)
		avail -= _tag.size.y
	else:
		# The tag leans on the right half, the rows cascade down the left.
		_tag.position = Vector2(vp.x * 0.52, vp.y * 0.28)
		_tag.size = Vector2(vp.x * 0.46, vp.y * 0.4)
	_tag.pivot_offset = _tag.size * 0.5
	_tag.rotation = -0.12 if not port else -0.04
	var bh := clampf(avail / n - 16.0, 56.0, 96.0 * u)
	var gap := clampf((avail - n * bh) / maxf(n - 1, 1), 8.0, bh * 0.4)
	var top := bar_h + 26.0 + (_tag.size.y if port else 0.0)
	_column.position = Vector2.ZERO
	_column.size = vp
	for i in n:
		var b := rows[i] as SlabButton
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = b.custom_minimum_size
		b.font_size = int(bh * 0.4)
		var x: float
		if port:
			x = 14.0 if i % 2 == 0 else vp.x - bw - 14.0
		else:
			x = maxf(30.0, vp.x * 0.04) + i * bh * 0.3
		b.position = Vector2(x, top + i * (bh + gap))
		b.pivot_offset = b.size * 0.5
		b.rotation = [0.02, -0.025, 0.015, -0.02, 0.028, -0.015][i % 6]


func _cycle_controls() -> void:
	Session.move_profile = (Session.move_profile + 1) % PROFILES.size()
	Session.save_to_disk()
	_refresh()


func _cycle_sound() -> void:
	var vol := float(Session.pref("master_volume", 1.0))
	var i := 0
	for k in VOLUMES.size():
		if absf(VOLUMES[k] - vol) < 0.01:
			i = k
	Session.prefs["master_volume"] = VOLUMES[(i + 1) % VOLUMES.size()]
	Session.save_to_disk()
	MenuRoot.apply_volume()
	_refresh()


func _toggle_battery() -> void:
	PerformanceSettings.set_value("battery_saver", not PerformanceSettings.battery_saver)
	PerformanceSettings.apply(get_tree())
	_refresh()


func _toggle_shake() -> void:
	JuiceSettings.set_reduce_motion(not JuiceSettings.reduce_motion)
	_refresh()


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	Campaign.reset()
	_refresh()
