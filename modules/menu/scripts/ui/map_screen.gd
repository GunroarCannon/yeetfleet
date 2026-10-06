## MapScreen: the campaign — the board of level polaroids ([LevelMapView])
## under the top bar, the paper report sliding in from the right when a card
## is tapped ([ReportPanel]), and the pay-out card after a level.
class_name MapScreen
extends MenuScreen

var _bar: TopBar
var _map: LevelMapView
var _report: ReportPanel
var _payout: Control = null
## The how-to-unlock toast, while it is up.
var _toast: Control = null
var _tutorial: SlabButton


func _ready() -> void:
	_map = LevelMapView.new()
	_map.level_tapped.connect(_on_level)
	_map.fork_tapped.connect(_on_fork)
	_map.locked_tapped.connect(_on_locked)
	add_child(_map)
	# Flight school, any time: the moves shown by a hand, against drones.
	_tutorial = SlabButton.new()
	_tutorial.text = "TUTORIAL"
	_tutorial.fill = GraffitiStyle.LIME
	_tutorial.text_color = GraffitiStyle.INK
	_tutorial.skew = 10.0
	_tutorial.pressed.connect(func() -> void: menu.launch_tutorial())
	add_child(_tutorial)
	_bar = TopBar.new()
	_bar.title = "CAMPAIGN"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_report = ReportPanel.new()
	_report.set_anchors_preset(Control.PRESET_FULL_RECT)
	_report.fly.connect(func(lvl: Dictionary) -> void: menu.launch_level(lvl))
	_report.choose_fork.connect(_on_choose_fork)
	_report.pick_ship.connect(func(lvl: Dictionary) -> void:
		_report.close()
		menu.pick_ship_for(lvl))
	add_child(_report)
	Campaign.notifier.changed.connect(func() -> void:
		if visible:
			_map.rebuild())
	layout()


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var bar_h := bar_height()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	# The board runs under the bar, so a sector's name panned up to the top
	# slides behind the bar rather than being sliced off at its edge.
	_map.top_inset = bar_h + 8
	_map.position = Vector2.ZERO
	_map.size = vp
	var u := unit()
	_tutorial.custom_minimum_size = Vector2(190, 62) * u
	_tutorial.size = _tutorial.custom_minimum_size
	_tutorial.font_size = int(26 * u)
	_tutorial.position = Vector2(18, vp.y - _tutorial.size.y - 22)
	_tutorial.pivot_offset = _tutorial.size * 0.5
	_tutorial.rotation = -0.03


func opened() -> void:
	layout()
	_map.rebuild()
	# The newest unlocked level on the first look this run, or when the flight
	# just opened something new; otherwise the level that was just played.
	var fresh := not Campaign.map_seen or bool(menu.last_result.get("first_win", false)) or bool(menu.last_result.get("won", false))
	Campaign.map_seen = true
	_map.focus_level("" if fresh else Campaign.last_played_key, true)
	_map.grab_focus.call_deferred()
	# Back from picking a ship for a level: its report again.
	if not menu.reopen_level.is_empty():
		_report.show_level(menu.reopen_level)
		menu.reopen_level = {}
	# No pay-out card here: the coins are on the flight's win / fail card, and
	# the way back to the map is just the map.
	if not menu.last_result.is_empty() and not bool(menu.last_result.get("won", false)) and Campaign.loss_streak() >= 2 			and not Campaign.nudge_seen("upgrade") and Campaign.can_afford_upgrade():
		_nudge_upgrade()
	menu.last_result = {}


## Losing run + coins in hand, once: the only way on is the garage, hand pointing.
func _nudge_upgrade() -> void:
	Campaign.mark_nudge("upgrade")
	var pop := NudgePopup.make("STUCK?",
		"You have coins to spend. Upgrade your ship's hull, guns or speed and the fights get a lot easier.",
		"TO THE GARAGE", true)
	pop.chosen.connect(func() -> void: menu.go(MenuRoot.Screen.GARAGE))
	add_child(pop)


func back() -> bool:
	if _payout != null and is_instance_valid(_payout):
		_payout.queue_free()
		_payout = null
		return true
	if _report.is_open():
		_report.close()
		return true
	return false


## A tap on a locked card: a toast of what opens it, that pops in and fades.
func _on_locked(lvl: Dictionary) -> void:
	GameAudio.ui(&"locked")
	var more := int(lvl.get("stars_req", 0)) - Campaign.total_stars()
	_show_toast("GET %d MORE STAR%s" % [more, "" if more == 1 else "S"])


func _show_toast(text: String) -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	var vp := viewport_size()
	var u := unit()
	var t := _Toast.new()
	t.text = text
	var fs := int(34 * u)
	var w := GraffitiStyle.head_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 90.0 * u
	t.font_size = fs
	t.size = Vector2(minf(w, vp.x - 24.0), fs * 2.1)
	t.position = Vector2((vp.x - t.size.x) * 0.5, vp.y * 0.72)
	t.pivot_offset = t.size * 0.5
	t.rotation = -0.025
	t.scale = Vector2(0.5, 0.5)
	add_child(t)
	_toast = t
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_property(t, "modulate:a", 0.0, 0.5)
	tw.tween_callback(t.queue_free)


## The toast: an ink slab with a hot rim and the words on it.
class _Toast:
	extends Control
	var text := ""
	var font_size := 30

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		GraffitiStyle.draw_slab(self, r.grow(4.0), GraffitiStyle.HOT, 16.0, 0.0, Vector2(7, 8))
		GraffitiStyle.draw_slab(self, r, GraffitiStyle.INK, 16.0, 3.0, Vector2.ZERO)
		GraffitiStyle.draw_text(self, text, size * 0.5, font_size, GraffitiStyle.SUN, 6)


func _on_level(lvl: Dictionary) -> void:
	_report.show_level(lvl)


func _on_fork(theme: int) -> void:
	if not Campaign.fork_open():
		GameAudio.ui(&"locked")
		var more := Campaign.fork_stars_needed() - Campaign.total_stars()
		_show_toast("GET %d MORE STAR%s" % [more, "" if more == 1 else "S"])
		return
	_report.show_fork(theme, theme == Campaign.fork_options()[1])


func _on_choose_fork(theme: int) -> void:
	Campaign.choose_fork(theme)
	_report.close()
	_map.rebuild()
	_map.focus_next()


## What the level just flown paid: YEET! and the coins, or WRECKED.
func _show_payout(res: Dictionary) -> void:
	var won := bool(res.get("won", false))
	_payout = Control.new()
	_payout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_payout.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_payout)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_payout.add_child(dim)
	var card := _PayoutCard.new()
	card.res = res
	var vp := viewport_size()
	card.size = Vector2(clampf(vp.x * 0.5, 300.0, 560.0), clampf(vp.y * 0.42, 220.0, 320.0))
	card.position = (vp - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	card.rotation = -0.03
	card.scale = Vector2(0.3, 0.3)
	_payout.add_child(card)
	if won:
		var stars := StarPopRow.new()
		stars.count = int(res.get("stars", 0))
		stars.delay = 0.45
		stars.size = Vector2(card.size.x * 0.7, card.size.y * 0.3)
		stars.position = Vector2(card.size.x * 0.15, card.size.y * 0.4)
		card.add_child(stars)
	card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_payout.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _payout != null:
			_payout.queue_free()
			_payout = null)
	get_tree().create_timer(3.5 if won else 2.5).timeout.connect(func() -> void:
		if _payout != null and is_instance_valid(_payout):
			_payout.queue_free()
			_payout = null)


class _PayoutCard:
	extends Control
	var res := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var won := bool(res.get("won", false))
		var r := Rect2(Vector2.ZERO, size)
		GraffitiStyle.draw_slab(self, r, GraffitiStyle.LIME if won else GraffitiStyle.HOT, 24.0, 5.0, Vector2(9, 10))
		GraffitiStyle.draw_halftone(self, r.grow(-10), Color(1, 1, 1, 0.18), 10.0, true, 24.0)
		var tf := GraffitiStyle.title_font()
		var head := "YEET!" if won else "WRECKED"
		var fs := int(size.y * 0.3)
		GraffitiStyle.draw_text(self, head, Vector2(size.x * 0.5, size.y * 0.24), fs, Color.WHITE, 12, tf)
		if won:
			var coins := int(res.get("coins", 0))
			GraffitiIcons.draw(self, "coin", Vector2(size.x * 0.36, size.y * 0.82), size.y * 0.14, GraffitiStyle.SUN)
			GraffitiStyle.draw_text(self, "+%d" % coins, Vector2(size.x * 0.54, size.y * 0.82), int(size.y * 0.17), Color.WHITE, 6, GraffitiStyle.number_font())
		else:
			GraffitiStyle.draw_text(self, "TRY AGAIN", Vector2(size.x * 0.5, size.y * 0.62), int(size.y * 0.13), Color.WHITE, 6)
			GraffitiStyle.draw_text(self, "WRECKS %d" % int(res.get("kills", 0)), Vector2(size.x * 0.5, size.y * 0.82), int(size.y * 0.1), GraffitiStyle.INK, 0)
