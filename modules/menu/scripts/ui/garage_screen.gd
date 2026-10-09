## GarageScreen: the pad, the ship turning on it, and what can be done with
## it.
##
## Two shelves behind two tabs. HANGAR is only the ships the player owns.
## SHOP is every ship not yet owned, in full paint. ◀ ▶ (or a swipe across the pad) shuffle; the panel
## shows the ship's name and type, four upgrade tracks (HULL, GUNS, SPEED,
## YEET) with capped pips and a + to buy the next one, and one big action:
## FLY THIS, FLYING, or BUY.
##
## Opened from a level's report ([member MenuRoot.ship_pick_level]) it is a
## ship picker: only the owned ships the level takes are on the shelf (no
## shop, no teasers, nothing it would refuse) — or, owning none of its type,
## the loaner it lends — and SELECT or back returns to that report.
class_name GarageScreen
extends MenuScreen

enum Shelf { HANGAR, SHOP }

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
	_bar.back_pressed.connect(func() -> void:
		if _picking():
			menu.finish_ship_pick()
		else:
			menu.go(MenuRoot.Screen.HOME))
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
		row.explain.connect(_explain_stat)
		_panel.add_child(row)
		_rows.append(row)
	_action = SlabButton.new()
	_action.pressed.connect(_on_action)
	_panel.add_child(_action)
	_explain = GraffitiStyle.label("", 22, Color.WHITE, 5)
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_explain.modulate.a = 0.0
	# A plate behind the line: words alone over the 3D pad were hard to read.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.17, 0.13, 0.25, 0.94)
	plate.border_color = GraffitiStyle.INK
	plate.set_border_width_all(3)
	plate.border_width_top = 6
	plate.set_corner_radius_all(6)
	plate.content_margin_left = 16
	plate.content_margin_right = 16
	plate.content_margin_top = 10
	plate.content_margin_bottom = 10
	plate.shadow_color = Color(0, 0, 0, 0.5)
	plate.shadow_offset = Vector2(5, 6)
	_explain.add_theme_stylebox_override("normal", plate)
	add_child(_explain)
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
	_bar.set_title("PICK A SHIP" if _picking() else "GARAGE")
	var start := Campaign.current_ship()
	if _picking():
		start = String(Campaign.ship_for(menu.ship_pick_level)["id"])
	_tabs.visible = not _picking()
	_rebuild_list(start)
	layout()
	_action.grab_focus.call_deferred()
	# The very first visit: two cards on what the garage sells and what the bars mean.
	if not Campaign.nudge_seen("intro") and not _picking():
		Campaign.mark_nudge("intro")
		_intro_cards()
		return
	# Right after the upgrade hint: other ships can be bought too.
	if Campaign.nudge_seen("upgrade") and not Campaign.nudge_seen("ships") and not _picking():
		Campaign.mark_nudge("ships")
		add_child(NudgePopup.make("MORE SHIPS",
			"You can also buy other ships here. Tap the SHOP tab to see what each one does.",
			"GOT IT", false))


## What each upgrade track does, in one line (the first-visit cards, and a
## tap on a track's name).
const STAT_WORDS := {
	"hull": "How much damage you take before you wreck.",
	"guns": "How hard your shots hit.",
	"speed": "How fast you fly, and how far a launch carries.",
	"yeet": "How hard you hit when you ram or fling into something.",
}

## The explain line over the panel (a tap on a track's name), and its fade.
var _explain: Label
var _explain_tw: Tween


## First-visit cards, one idea each: what coins buy, then each bar, then
## stars. Short on purpose: a phone screen of text is skipped, not read.
func _intro_cards() -> void:
	var cards: Array = [["SPEND YOUR COINS", "Coins from levels buy upgrades for your ship. The SHOP tab sells new ships."]]
	for i in ShipCatalog.STATS.size():
		var stat := String(ShipCatalog.STATS[i])
		cards.append(["%s  %d/%d" % [ShipCatalog.STAT_NAMES[i], i + 1, ShipCatalog.STATS.size()], String(STAT_WORDS.get(stat, ""))])
	cards.append(["MORE STARS, MORE COINS", "Win fast, keep your hull high and guard what you're given."])
	_show_card(cards, 0)


func _show_card(cards: Array, i: int) -> void:
	var last := i == cards.size() - 1
	var card := NudgePopup.make(String(cards[i][0]), String(cards[i][1]), "GOT IT" if last else "NEXT", false)
	if not last:
		card.chosen.connect(_show_card.bind(cards, i + 1))
	add_child(card)


## One line on what [param stat] does, just over the panel, fading after a
## few seconds.
func _explain_stat(stat: String) -> void:
	var i := ShipCatalog.STATS.find(stat)
	if i < 0:
		return
	GameAudio.ui(&"tap")
	_explain.text = "%s: %s" % [ShipCatalog.STAT_NAMES[i], String(STAT_WORDS.get(stat, ""))]
	# Over the pad, clear of the panel: under the ship in landscape, just
	# above the panel in portrait.
	var vp := viewport_size()
	var fs := int(clampf(24.0 * unit(), 16.0, 30.0))
	_explain.add_theme_font_size_override("font_size", fs)
	var w := vp.x - 40.0 if portrait() else _panel.position.x - 60.0
	_explain.custom_minimum_size = Vector2(w, 0)
	_explain.size = Vector2(w, 0)
	# Measured from the font: a wrapping Label's own minimum size lags a
	# frame behind its new width.
	var font := _explain.get_theme_font("font")
	var h := font.get_multiline_string_size(_explain.text, HORIZONTAL_ALIGNMENT_CENTER, w - 32.0, fs).y + 28.0
	_explain.size = Vector2(w, h)
	if portrait():
		_explain.position = Vector2(20.0, _panel.position.y - h - 10.0)
	else:
		_explain.position = Vector2(30.0, vp.y - h - 24.0)
	_explain.modulate.a = 1.0
	if _explain_tw != null:
		_explain_tw.kill()
	_explain_tw = create_tween()
	_explain_tw.tween_interval(3.5)
	_explain_tw.tween_property(_explain, "modulate:a", 0.0, 0.4)


func back() -> bool:
	if _shelf == Shelf.SHOP:
		_set_shelf(Shelf.HANGAR)
		return true
	if _picking():
		menu.finish_ship_pick()
		return true
	return false


## Picking the ship for a level (opened from its report).
func _picking() -> bool:
	return menu != null and not menu.ship_pick_level.is_empty()


## Whether the level being picked for takes [param id] (any ship when it
## names no type).
func _allowed(id: String) -> bool:
	if not _picking():
		return true
	var want := Campaign.required_type(menu.ship_pick_level)
	return want < 0 or ShipCatalog.type_of(id) == want


func _set_shelf(shelf: int) -> void:
	_shelf = shelf
	_rebuild_list(current_id())


func _rebuild_list(keep: String) -> void:
	_list.clear()
	if _picking():
		for id in Campaign.owned_ids():
			if _allowed(id):
				_list.append(id)
		if _list.is_empty():
			_list.append(String(Campaign.ship_for(menu.ship_pick_level)["id"]))
	elif _shelf == Shelf.HANGAR:
		_list = Campaign.owned_ids()
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
	GameAudio.ui(&"ship")
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
	_panel.set_rank(Campaign.rank_tier(id) if id != "" else -1)
	var owned := id != "" and Campaign.owns(id)
	# The shop shows the paint it is selling (and
	# a picker's loaner is shown in full: it is the ship flown).
	if menu != null and id != "":
		menu.stage.show_pad_ship(id, not owned and _shelf == Shelf.HANGAR and not _picking())
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
	if _picking() and not owned:
		# The level lends this one: nothing of its type in the hangar.
		_action.text = "FLY THE LOANER"
		_action.icon = ""
		_action.fill = GraffitiStyle.LIME
		_action.text_color = GraffitiStyle.INK
		_action.disabled = false
	elif owned and _picking():
		var ok := _allowed(id)
		_action.text = "SELECT SHIP" if ok else "NOT ALLOWED"
		_action.icon = ""
		_action.fill = GraffitiStyle.LIME if ok else Color("3a3150")
		_action.text_color = GraffitiStyle.INK if ok else Color.WHITE
		_action.disabled = not ok
		if not ok:
			_action.sub = "NEEDS " + ShipCatalog.type_name(Campaign.required_type(menu.ship_pick_level))
	elif owned:
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
	if _picking() and not Campaign.owns(id):
		menu.finish_ship_pick()
		return
	if Campaign.owns(id):
		if _picking():
			if _allowed(id):
				Campaign.select_ship(id)
				menu.finish_ship_pick()
			return
		if Campaign.current_ship() != id:
			Campaign.select_ship(id)
	elif Campaign.buy_ship(id):
		# Bought: it lives in the hangar now, and it is the one flying.
		_shelf = Shelf.HANGAR
		_rebuild_list(id)
		Juice.pop(_panel, 0.15)
		GameAudio.ui(&"buy")


func _on_buy_pip(stat: String) -> void:
	var id := current_id()
	var before := Campaign.rank_tier(id)
	if Campaign.buy_pip(id, stat):
		GameAudio.ui(&"upgrade", 0.08)
		var after := Campaign.rank_tier(id)
		if after != before:
			_panel.rank_up(before, after)
			GameAudio.ui(&"power_up", 0.02)
			_shake(0.3, 9.0)


## A short screen shake: the whole garage jolts and settles.
func _shake(time: float, power: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		var k := (1.0 - v) * power
		position = Vector2(randf_range(-k, k), randf_range(-k, k)), 0.0, 1.0, time)
	tw.tween_callback(func() -> void: position = Vector2.ZERO)


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
		var name_w := minf(tf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x * 0.62)
		_draw_rank(Vector2(24.0 + name_w + fs * 1.1, size.y * 0.13 - fs * 0.32), fs)
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
		# On the type chip's row, clear of the rank stamp beside the name.
		GraffitiStyle.draw_text(self, status, Vector2(size.x - 70, chip.get_center().y), cfs, col, 4)

	# --- Rank stamp ---
	## The rank step shown now, the one it replaces, and how far the swap is
	## (0 = just started, 1 = done).
	var rank := -1
	var _old_rank := -1
	var _swap := 1.0
	## The stamp's tilt: a new rank lands at a random angle.
	var _rot := -0.16

	## Show [param tier] straight away (a ship change or a refresh).
	func set_rank(tier: int) -> void:
		if _swap < 1.0:
			rank = tier
			return
		if tier != rank:
			_rot = -0.16
		rank = tier
		_old_rank = tier
		queue_redraw()

	## Swap [param from] for [param to]: the old stamp swells and fades while the
	## new one drops in from bigger and fades in.
	func rank_up(from: int, to: int) -> void:
		_old_rank = from
		rank = to
		_rot = randf_range(-0.5, 0.5)
		_swap = 0.0
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_swap = v
			queue_redraw(), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw_rank(at: Vector2, fs: int) -> void:
		if rank < 0:
			return
		if _swap < 1.0 and _old_rank != rank:
			_stamp(at, fs, _old_rank, 1.0 + _swap * 1.4, 1.0 - _swap)
			_stamp(at, fs, rank, lerpf(2.2, 1.0, _swap), clampf(_swap * 1.6, 0.0, 1.0))
		else:
			_stamp(at, fs, rank, 1.0, 1.0)

	func _stamp(at: Vector2, fs: int, tier: int, k: float, alpha: float) -> void:
		var text := ShipCatalog.rank_name(tier)
		var cols: Array[Color] = [Color("a49cbc"), Color("7fa8ff"), GraffitiStyle.LIME, GraffitiStyle.CYAN,
			GraffitiStyle.SUN, GraffitiStyle.ORANGE, GraffitiStyle.HOT, GraffitiStyle.VIOLET, Color("fff3a8")]
		var col := cols[ShipCatalog.rank_family(tier)]
		col.a = alpha
		var ink := GraffitiStyle.INK
		ink.a = alpha
		var f := GraffitiStyle.title_font()
		var sfs := int(fs * 0.8 * k)
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_set_transform(at, _rot if tier == rank else -0.16)
		var box := Rect2(Vector2(-tw * 0.5 - sfs * 0.28, -sfs * 0.9), Vector2(tw + sfs * 0.56, sfs * 1.15))
		draw_rect(box, Color(ink, alpha * 0.55))
		draw_rect(box, col, false, maxf(3.0, sfs * 0.09))
		draw_string_outline(f, Vector2(-tw * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 6, ink)
		draw_string(f, Vector2(-tw * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, col)
		draw_set_transform(Vector2.ZERO)


## One upgrade track: its name, the ship's own rating as grey blocks, the
## bought pips as lime blocks out of [constant ShipCatalog.MAX_PIPS], and a
## + slab with the next pip's price (or MAX).
class _StatRow:
	extends Control
	signal buy(stat: String)
	## The track's name was tapped: say what it does.
	signal explain(stat: String)
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

	func _gui_input(event: InputEvent) -> void:
		# A tap on the name (left of the bar) explains the track.
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.position.x < size.x * 0.28:
			explain.emit(stat)
			accept_event()

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
		# A small "?": the name explains itself when tapped.
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(8 + lw, h * 0.62), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.7), GraffitiStyle.CYAN)
		var base := ShipCatalog.rating(ship_id, stat)
		var pips := Campaign.pips(ship_id, stat)
		var x := size.x * 0.28
		var avail := size.x - x - clampf(size.x * 0.3, 92.0, 150.0) - 20.0
		# One scale for every ship: ten cells, always. A ship's own rating plus the
		# pips it can buy fills some of them; the rest stay empty (and the ones it
		# can never reach are drawn fainter), so a full bar on a small ship is never
		# mistaken for a full bar on a big one. The total is written under it.
		var cells := 10
		var cell := minf(avail / (float(cells) + 2.4), h * 0.5)
		var reach := mini(base + ShipCatalog.MAX_PIPS, cells)
		for i in cells:
			var r := Rect2(Vector2(x + i * cell * 1.05, h * 0.5 - cell * 0.5), Vector2(cell * 0.86, cell))
			var col := Color(1, 1, 1, 0.18) if i < reach else Color(1, 1, 1, 0.05)
			if i < base:
				col = Color("8f86a8")
			elif i < base + pips:
				col = GraffitiStyle.LIME
			draw_rect(r.grow(1.5), GraffitiStyle.INK if i < reach else Color(0, 0, 0, 0.35))
			draw_rect(r, col)
		# The total, x50 so a strong hull reads as heavy, under the bar in the
		# small dim type the upgrade gain used to use.
		var total := mini(base + pips, cells)
		f.draw_string(get_canvas_item(), Vector2(x, h * 0.98), str(total * 50), HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.2), GraffitiStyle.DIM)
