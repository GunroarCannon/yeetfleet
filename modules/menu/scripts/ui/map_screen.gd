## MapScreen: the campaign — the board of level polaroids ([LevelMapView])
## under the top bar, the paper report sliding in from the right when a card
## is tapped ([ReportPanel]), and the pay-out card after a level.
class_name MapScreen
extends MenuScreen

var _bar: TopBar
var _map: LevelMapView
var _report: ReportPanel
var _payout: Control = null


func _ready() -> void:
	_map = LevelMapView.new()
	_map.level_tapped.connect(_on_level)
	_map.fork_tapped.connect(_on_fork)
	add_child(_map)
	_bar = TopBar.new()
	_bar.title = "CAMPAIGN"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_report = ReportPanel.new()
	_report.set_anchors_preset(Control.PRESET_FULL_RECT)
	_report.fly.connect(func(lvl: Dictionary) -> void: menu.launch_level(lvl))
	_report.choose_fork.connect(_on_choose_fork)
	_report.to_garage.connect(func() -> void:
		_report.close()
		menu.go(MenuRoot.Screen.GARAGE))
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
	_map.position = Vector2(0, bar_h + 8)
	_map.size = Vector2(vp.x, vp.y - bar_h - 8)


func opened() -> void:
	layout()
	_map.rebuild()
	_map.focus_next(true)
	_map.grab_focus.call_deferred()
	if not menu.last_result.is_empty():
		_show_payout(menu.last_result)
		menu.last_result = {}


func back() -> bool:
	if _payout != null and is_instance_valid(_payout):
		_payout.queue_free()
		_payout = null
		return true
	if _report.is_open():
		_report.close()
		return true
	return false


func _on_level(lvl: Dictionary) -> void:
	_report.show_level(lvl)


func _on_fork(theme: int) -> void:
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
			GraffitiStyle.draw_text(self, "+%d" % coins, Vector2(size.x * 0.54, size.y * 0.82), int(size.y * 0.15), Color.WHITE, 6)
		else:
			GraffitiStyle.draw_text(self, "TRY AGAIN", Vector2(size.x * 0.5, size.y * 0.62), int(size.y * 0.13), Color.WHITE, 6)
			GraffitiStyle.draw_text(self, "WRECKS %d" % int(res.get("kills", 0)), Vector2(size.x * 0.5, size.y * 0.82), int(size.y * 0.1), GraffitiStyle.INK, 0)
