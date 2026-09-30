## StoreScreen: coin packs for real money ([CoinStore]) — a row of four
## crates under the top bar (a 2×2 grid in portrait), each a big word, a
## heap of coins and its price on a slab. A buy shows a toast and rolls the
## wallet; a failed one says so in a word or two; a cancel says nothing.
class_name StoreScreen
extends MenuScreen

var _bar: TopBar
var _cards: Array[_PackCard] = []
var _toast: Control = null


func _ready() -> void:
	_bar = TopBar.new()
	_bar.title = "STORE"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	for p in CoinStore.PACKS:
		var c := _PackCard.new()
		c.pack = p
		c.buy.connect(_on_buy)
		add_child(c)
		_cards.append(c)
	CoinStore.notifier.purchased.connect(_on_purchased)
	CoinStore.notifier.failed.connect(_on_failed)
	CoinStore.notifier.prices_changed.connect(_refresh)
	layout()


func opened() -> void:
	CoinStore.start()
	layout()
	_refresh()
	for i in _cards.size():
		var c := _cards[i]
		c.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.06 + i * 0.07)
		tw.tween_property(c, "modulate:a", 1.0, 0.18)
	if not _cards.is_empty():
		_cards[0].focus.call_deferred()


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var bar_h := bar_height()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	var top := bar_h + 26.0
	var area := Rect2(Vector2(18, top), Vector2(vp.x - 36, vp.y - top - 20))
	var cols := 2 if portrait() else 4
	var rows := ceili(_cards.size() / float(cols))
	var gap := 18.0 * unit()
	var cw := (area.size.x - gap * (cols - 1)) / cols
	var ch := minf((area.size.y - gap * (rows - 1)) / rows, cw * 1.5)
	for i in _cards.size():
		var c := _cards[i]
		var col := i % cols
		var row := i / cols
		c.position = area.position + Vector2(col * (cw + gap), row * (ch + gap))
		c.size = Vector2(cw, ch)
		c.pivot_offset = c.size * 0.5
		c.rotation = [-0.02, 0.015, -0.012, 0.02][i % 4]
		c.place()


func _refresh() -> void:
	var open := CoinStore.available()
	for c in _cards:
		c.refresh(open)


func _on_buy(id: String) -> void:
	GameAudio.ui(&"tap")
	CoinStore.buy(id)
	_refresh()


func _on_purchased(_id: String, coins: int) -> void:
	GameAudio.ui(&"coin")
	_show_toast("+%d COINS!" % coins, GraffitiStyle.LIME)
	_refresh()


func _on_failed(_id: String, reason: String) -> void:
	_refresh()
	if reason != "":
		GameAudio.ui(&"locked")
		_show_toast(reason, GraffitiStyle.HOT)


func _show_toast(text: String, col: Color) -> void:
	if not visible:
		return
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	var vp := viewport_size()
	var u := unit()
	var fs := int(40 * u)
	var l := GraffitiStyle.label(text, fs, col, int(10 * u))
	l.add_theme_font_override("font", GraffitiStyle.title_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(vp.x, fs * 1.6)
	l.position = Vector2(0, vp.y * 0.5 - fs)
	l.pivot_offset = l.size * 0.5
	l.rotation = -0.03
	l.scale = Vector2(0.4, 0.4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_toast = l
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


## One pack: a dark card, the pack's word, a heap of coins and the amount,
## a bonus sticker, and the price slab that buys it.
class _PackCard:
	extends Control
	signal buy(id: String)
	var pack := {}
	var _price: SlabButton

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_price = SlabButton.new()
		_price.fill = GraffitiStyle.LIME
		_price.text_color = GraffitiStyle.INK
		_price.skew = 10.0
		_price.pressed.connect(func() -> void: buy.emit(String(pack["id"])))
		add_child(_price)

	func place() -> void:
		if _price == null:
			return
		_price.custom_minimum_size = Vector2(size.x * 0.8, clampf(size.y * 0.18, 44.0, 84.0))
		_price.size = _price.custom_minimum_size
		_price.font_size = int(_price.size.y * 0.42)
		_price.position = Vector2((size.x - _price.size.x) * 0.5, size.y - _price.size.y - size.y * 0.06)
		queue_redraw()

	func refresh(open: bool) -> void:
		if _price == null:
			return
		var waiting := CoinStore.busy()
		_price.text = CoinStore.price_text(String(pack["id"])) if open else "CLOSED"
		_price.disabled = not open or waiting
		queue_redraw()

	func focus() -> void:
		if _price != null:
			_price.grab_focus()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		GraffitiStyle.draw_slab(self, r, Color("2b2140"), size.x * 0.06, 4.0, Vector2(6, 8))
		var h := size.y
		GraffitiStyle.draw_text(self, String(pack["word"]), Vector2(size.x * 0.5, h * 0.14), int(minf(h * 0.12, size.x * 0.16)), GraffitiStyle.SUN, 6, GraffitiStyle.title_font())
		# The heap: more coins for a bigger pack.
		# Rows of coins, widest at the bottom: 3, then 4+2, 4+3, 4+3+2.
		var rows_of: Array = [[3], [4, 2], [4, 3], [4, 3, 2]]
		var rows: Array = rows_of[clampi(CoinStore.PACKS.find(pack), 0, 3)]
		var cs := minf(size.x * 0.22, h * 0.16)
		var base := Vector2(size.x * 0.5, h * 0.5 + cs * 0.3)
		for row in rows.size():
			var count := int(rows[row])
			var span := (count - 1) * cs * 0.55
			for k in count:
				var at := base + Vector2(-span * 0.5 + k * cs * 0.55, -row * cs * 0.42)
				GraffitiIcons.draw(self, "coin", at, cs)
		GraffitiStyle.draw_text(self, str(int(pack["coins"])), Vector2(size.x * 0.5, h * 0.68), int(minf(h * 0.11, size.x * 0.17)), Color.WHITE, 6, GraffitiStyle.number_font())
		if pack.has("bonus"):
			var sticker := Rect2(Vector2(size.x * 0.58, h * 0.24), Vector2(size.x * 0.38, h * 0.1))
			draw_set_transform(sticker.get_center(), 0.18)
			GraffitiStyle.draw_slab(self, Rect2(-sticker.size * 0.5, sticker.size), GraffitiStyle.HOT, 8.0, 3.0, Vector2(3, 4))
			GraffitiStyle.draw_text(self, String(pack["bonus"]), Vector2.ZERO, int(sticker.size.y * 0.55), Color.WHITE, 4, GraffitiStyle.number_font())
			draw_set_transform(Vector2.ZERO)
