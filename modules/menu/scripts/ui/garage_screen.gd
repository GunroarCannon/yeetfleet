## GarageScreen: the pad, the ship turning on it, and what can be done with
## it.
##
## Two shelves behind two tabs. HANGAR is the ships the player owns — with
## the next couple they could buy mixed in as dark silhouettes and a price,
## so shuffling through always dangles something. SHOP is every ship not yet
## owned, in full paint. ◀ ▶ (or a swipe across the pad) shuffle; the panel
## shows the ship's name and type, four upgrade tracks (HULL, GUNS, SPEED,
## YEET) with capped pips and a + to buy the next one, and one big action:
## FLY THIS, FLYING, or BUY.
class_name GarageScreen
extends MenuScreen

enum Shelf { HANGAR, SHOP }

## How many not-yet-owned ships the hangar teases.
const TEASERS := 2

var _bar: TopBar
var _tabs: HBoxContainer
var _tab_hangar: SlabButton
var _tab_shop: SlabButton
var _prev: SlabButton
var _next: SlabButton
var _panel: _Panel
var _action: SlabButton
var _rows: Array[_StatRow] = []
var _shelf: int = Shelf.HANGAR
var _list: Array[String] = []
var _index := 0
var _swipe_from := Vector2.ZERO
var _swiping := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bar = TopBar.new()
	_bar.title = "GARAGE"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 22)
	add_child(_tabs)
	_tab_hangar = _tab("HANGAR", Shelf.HANGAR)
	_tab_shop = _tab("SHOP", Shelf.SHOP)
	_prev = _arrow("<", -1)
	_next = _arrow(">", 1)
	_panel = _Panel.new()
	_panel.garage = self
	add_child(_panel)
	for i in ShipCatalog.STATS.size():
		var row := _StatRow.new()
		row.stat = ShipCatalog.STATS[i]
		row.label = ShipCatalog.STAT_NAMES[i]
		row.buy.connect(_on_buy_pip)
		_panel.add_child(row)
		_rows.append(row)
	_action = SlabButton.new()
	_action.pressed.connect(_on_action)
	_panel.add_child(_action)
	Campaign.notifier.changed.connect(func() -> void:
		if visible:
			_refresh())
	layout()


func _tab(label: String, shelf: int) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.skew = 10.0
	b.pressed.connect(func() -> void: _set_shelf(shelf))
	_tabs.add_child(b)
	return b


func _arrow(glyph: String, step: int) -> SlabButton:
	var b := SlabButton.new()
	b.text = glyph
	b.text_color = GraffitiStyle.INK
	b.fill = GraffitiStyle.CYAN
	b.skew = 8.0
	b.pressed.connect(func() -> void: _step(step))
	add_child(b)
	return b


func opened() -> void:
	_shelf = Shelf.HANGAR
	_rebuild_list(Campaign.current_ship())
	layout()
	_action.grab_focus.call_deferred()


func back() -> bool:
	if _shelf == Shelf.SHOP:
		_set_shelf(Shelf.HANGAR)
		return true
	return false


func _set_shelf(shelf: int) -> void:
	_shelf = shelf
	_rebuild_list(current_id())


func _rebuild_list(keep: String) -> void:
	_list.clear()
	if _shelf == Shelf.HANGAR:
		_list = Campaign.owned_ids()
		var teased := 0
		for id in _cheapest_unowned():
			if teased >= TEASERS:
				break
			_list.append(id)
			teased += 1
	else:
		_list = _cheapest_unowned()
	_index = maxi(0, _list.find(keep))
	_refresh()


func _cheapest_unowned() -> Array[String]:
	var out: Array[String] = []
	for id in ShipCatalog.ids():
		if not Campaign.owns(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(ShipCatalog.get_ship(a)["price"]) < int(ShipCatalog.get_ship(b)["price"]))
	return out


func current_id() -> String:
	if _list.is_empty():
		return ""
	return _list[clampi(_index, 0, _list.size() - 1)]


func _step(d: int) -> void:
	if _list.size() < 2:
		return
	_index = posmod(_index + d, _list.size())
	_refresh()
	_panel.position.x += 30.0 * d
	create_tween().tween_property(_panel, "position:x", _panel_rest_x(), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh() -> void:
	_tab_hangar.fill = GraffitiStyle.SUN if _shelf == Shelf.HANGAR else Color("3a3150")
	_tab_hangar.text_color = GraffitiStyle.INK if _shelf == Shelf.HANGAR else Color.WHITE
	_tab_shop.fill = GraffitiStyle.SUN if _shelf == Shelf.SHOP else Color("3a3150")
	_tab_shop.text_color = GraffitiStyle.INK if _shelf == Shelf.SHOP else Color.WHITE
	var id := current_id()
	var many := _list.size() > 1
	_prev.visible = many
	_next.visible = many
	_panel.ship_id = id
	var owned := id != "" and Campaign.owns(id)
	# Hangar teasers are shadows; the shop shows the paint it is selling.
	if menu != null and id != "":
		menu.stage.show_pad_ship(id, not owned and _shelf == Shelf.HANGAR)
	for row in _rows:
		row.ship_id = id
		row.visible = id != ""
		row.refresh()
	if id == "":
		_action.visible = false
		_panel.queue_redraw()
		return
	_action.visible = true
	_action.sub = ""
	if owned:
		var flying := Campaign.current_ship() == id
		_action.text = "FLYING" if flying else "FLY THIS"
		_action.icon = ""
		_action.fill = GraffitiStyle.LIME if flying else GraffitiStyle.HOT
		_action.text_color = GraffitiStyle.INK if flying else Color.WHITE
		# Not greyed out: FLYING is good news, it just has nothing to do.
		_action.disabled = false
	else:
		var price := int(ShipCatalog.get_ship(id)["price"])
		var short := price - Campaign.coins()
		_action.text = "BUY %d" % price
		_action.icon = "coin"
		_action.icon_color = GraffitiStyle.SUN
		_action.fill = GraffitiStyle.CYAN
		_action.text_color = GraffitiStyle.INK
		_action.disabled = short > 0
		_action.sub = ("NEED %d MORE" % short) if short > 0 else ""
	_panel.queue_redraw()


func _on_action() -> void:
	var id := current_id()
	if id == "":
		return
	if Campaign.owns(id):
		if Campaign.current_ship() != id:
			Campaign.select_ship(id)
	elif Campaign.buy_ship(id):
		# Bought: it lives in the hangar now, and it is the one flying.
		_shelf = Shelf.HANGAR
		_rebuild_list(id)
		Juice.pop(_panel, 0.15)


func _on_buy_pip(stat: String) -> void:
	Campaign.buy_pip(current_id(), stat)


func _gui_input(event: InputEvent) -> void:
	# A swipe across the pad shuffles, like the arrows.
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_swipe_from = mb.position
			_swiping = true
		elif _swiping:
			_swiping = false
			var d := mb.position - _swipe_from
			if absf(d.x) > 60.0 and absf(d.x) > absf(d.y) * 1.5:
				_step(-1 if d.x > 0.0 else 1)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)


func _panel_rest_x() -> float:
	var vp := viewport_size()
	return (vp.x - _panel.size.x) * 0.5 if portrait() else vp.x - _panel.size.x - 28.0


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var port := portrait()
	var bar_h := bar_height()
	var u := unit()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	var tab_h := clampf(vp.y * 0.07, 44.0, 60.0 * u)
	for t in [_tab_hangar, _tab_shop]:
		(t as SlabButton).custom_minimum_size = Vector2(clampf(vp.x * 0.16, 130.0, 200.0 * u), tab_h)
		(t as SlabButton).font_size = int(tab_h * 0.46)
	_tabs.position = Vector2(26, bar_h + 22)
	var aw := clampf(minf(vp.x, vp.y) * 0.1, 56.0, 84.0 * u)
	for a in [_prev, _next]:
		(a as SlabButton).custom_minimum_size = Vector2(aw, aw)
		(a as SlabButton).size = Vector2(aw, aw)
	if port:
		_panel.size = Vector2(vp.x - 20.0, clampf(vp.y * 0.46, 340.0, 620.0 * u))
		_panel.position = Vector2(_panel_rest_x(), vp.y - _panel.size.y - 14.0)
		var mid_y := (bar_h + tab_h + _panel.position.y) * 0.5 + 20.0
		_prev.position = Vector2(14, mid_y - aw * 0.5)
		_next.position = Vector2(vp.x - aw - 14, mid_y - aw * 0.5)
	else:
		_panel.size = Vector2(clampf(vp.x * 0.38, 330.0, 520.0 * u), clampf(vp.y * 0.72, 330.0, 560.0 * u))
		_panel.position = Vector2(_panel_rest_x(), bar_h + 28.0 + (vp.y - bar_h - 28.0 - _panel.size.y) * 0.5)
		var mid := vp.y * 0.55
		_prev.position = Vector2(24, mid - aw * 0.5)
		_next.position = Vector2(_panel.position.x - aw - 30, mid - aw * 0.5)
	# Inside the panel: header (drawn), four stat rows, the action slab.
	var p := _panel.size
	var head := p.y * 0.26
	var row_h := (p.y - head - p.y * 0.22) / 4.0
	for i in _rows.size():
		_rows[i].position = Vector2(18, head + i * row_h)
		_rows[i].size = Vector2(p.x - 36, row_h - 6)
		_rows[i].place()
	var bh := clampf(p.y * 0.15, 54.0, 80.0 * u)
	_action.custom_minimum_size = Vector2(p.x * 0.66, bh)
	_action.size = _action.custom_minimum_size
	_action.font_size = int(bh * 0.44)
	_action.position = Vector2((p.x - _action.size.x) * 0.5, p.y - bh - 16)


## The card behind the stats: name in spray paint, type chip, owned/price.
class _Panel:
	extends Control
	var garage: GarageScreen
	var ship_id := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bg := GraffitiStyle.INK
		bg.a = 0.86
		GraffitiStyle.draw_slab(self, r, bg, 16.0, 4.0, Vector2(8, 9))
		if ship_id == "":
			GraffitiStyle.draw_text(self, "SOLD OUT!", size * Vector2(0.5, 0.4), int(size.y * 0.1), GraffitiStyle.LIME)
			GraffitiStyle.draw_text(self, "YOU OWN THEM ALL", size * Vector2(0.5, 0.55), int(size.y * 0.05), Color.WHITE, 4)
			return
		var row := ShipCatalog.get_ship(ship_id)
		var t := int(row["type"])
		var tf := GraffitiStyle.title_font()
		var fs := int(size.y * 0.1)
		var name := String(row["name"]).to_upper()
		draw_string_outline(tf, Vector2(24, size.y * 0.13), name, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.62, fs, 8, Color.BLACK)
		draw_string(tf, Vector2(24, size.y * 0.13), name, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.62, fs, GraffitiStyle.LIME)
		var f := GraffitiStyle.head_font()
		var cfs := int(size.y * 0.042)
		var tname := ShipCatalog.type_name(t)
		var tw := f.get_string_size(tname, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var chip := Rect2(Vector2(26, size.y * 0.165), Vector2(tw + 18, cfs * 1.5))
		GraffitiStyle.draw_slab(self, chip, ShipCatalog.type_color(t), 5.0, 2.0, Vector2(2, 2))
		GraffitiStyle.draw_text(self, tname, chip.get_center(), cfs, GraffitiStyle.INK, 0)
		var status := ""
		var col := Color.WHITE
		if Campaign.owns(ship_id):
			status = "OWNED"
			col = GraffitiStyle.LIME
		else:
			status = "LOCKED"
			col = GraffitiStyle.HOT
		GraffitiStyle.draw_text(self, status, Vector2(size.x - 70, size.y * 0.1), cfs, col, 4)


## One upgrade track: its name, the ship's own rating as grey blocks, the
## bought pips as lime blocks out of [constant ShipCatalog.MAX_PIPS], and a
## + slab with the next pip's price (or MAX).
class _StatRow:
	extends Control
	signal buy(stat: String)
	var stat := ""
	var label := ""
	var ship_id := ""
	var _plus: SlabButton

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_plus = SlabButton.new()
		_plus.icon = "coin"
		_plus.icon_color = GraffitiStyle.SUN
		_plus.fill = GraffitiStyle.HOT
		_plus.skew = 8.0
		_plus.centered = false
		_plus.pressed.connect(func() -> void: buy.emit(stat))
		add_child(_plus)

	func place() -> void:
		if _plus == null:
			return
		var h := size.y
		_plus.custom_minimum_size = Vector2(clampf(size.x * 0.3, 92.0, 150.0), h * 0.7)
		_plus.size = _plus.custom_minimum_size
		_plus.font_size = int(h * 0.3)
		_plus.position = Vector2(size.x - _plus.size.x - 6, h * 0.15)
		queue_redraw()

	func refresh() -> void:
		if _plus == null:
			return
		var owned := ship_id != "" and Campaign.owns(ship_id)
		var cost := Campaign.next_pip_cost(ship_id, stat) if owned else -1
		_plus.visible = owned
		if cost < 0:
			_plus.text = "MAX"
			_plus.icon = "star"
			_plus.disabled = true
		else:
			_plus.text = "+%d" % cost
			_plus.icon = "coin"
			_plus.disabled = Campaign.coins() < cost
		queue_redraw()

	func _draw() -> void:
		if ship_id == "":
			return
		var h := size.y
		var f := GraffitiStyle.head_font()
		var fs := int(h * 0.34)
		draw_string_outline(f, Vector2(4, h * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, GraffitiStyle.INK)
		draw_string(f, Vector2(4, h * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var base := ShipCatalog.rating(ship_id, stat)
		var pips := Campaign.pips(ship_id, stat)
		var x := size.x * 0.28
		var avail := size.x - x - clampf(size.x * 0.3, 92.0, 150.0) - 20.0
		var cell := minf(avail / 10.5, h * 0.5)
		for i in 10:
			var r := Rect2(Vector2(x + i * cell * 1.05, h * 0.5 - cell * 0.5), Vector2(cell * 0.86, cell))
			var col := Color(1, 1, 1, 0.1)
			if i < base:
				col = Color("8f86a8")
			elif i < base + pips:
				col = GraffitiStyle.LIME
			elif i < base + ShipCatalog.MAX_PIPS:
				col = Color(1, 1, 1, 0.18)
			draw_rect(r.grow(1.5), GraffitiStyle.INK)
			draw_rect(r, col)
		# What a pip is worth on this hull, as a percentage.
		var gain := int(round((ShipCatalog.stat_mult(ship_id, stat, 1) - 1.0) * 100.0))
		f.draw_string(get_canvas_item(), Vector2(x, h * 0.98), "+%d%% EACH" % gain, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.2), GraffitiStyle.DIM)
