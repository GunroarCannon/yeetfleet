## SkrShopPanel: the STORE's SKR tab ([Chain]). One card per thing SKR buys:
## an extra ranked Daily Sortie run (Seeker Genesis pilots), three liveries
## worn over every hull, three sling trails, and the Genesis livery (free to
## Seeker Genesis holders, not for sale). A card's slab buys it ("50 SKR"),
## then wears it (WEAR / WORN).
##
## A buy is one wallet prompt; after it the slabs wait while the leaderboard
## finds the payment on chain. The line under the header says what's going
## on and, after a failure, why, in plain words. Signed out, the header has
## a SIGN IN slab instead (the same sign-in as the Pilot ID).
class_name SkrShopPanel
extends Control

## A buy went through (or failed loudly): the store shows it big.
signal toast(text: String, color: Color)

const ITEMS: Array[String] = [
	"extra_attempt",
	"paint:skr_solana", "paint:skr_seeker", "paint:skr_gold",
	"trail:mint", "trail:violet", "trail:gold",
	"paint:skr_genesis",
]

var _head: Label
var _note: Label
var _sign_in: SlabButton
var _cards: Array[_SkrCard] = []
var _balance := -1.0
## What's happening ("" when idle): shown on the note line, and the slabs wait.
var _doing := ""
const _WAITING := "WAITING FOR WALLET…"
## Card size and spacing, from [method place].
var _unit := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head = GraffitiStyle.label("", 26, GraffitiStyle.SUN, 5)
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_head)
	_note = GraffitiStyle.label("", 20, GraffitiStyle.DIM, 4)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	_sign_in = SlabButton.new()
	_sign_in.text = "SIGN IN"
	_sign_in.fill = GraffitiStyle.LIME
	_sign_in.text_color = GraffitiStyle.INK
	_sign_in.skew = 10.0
	_sign_in.pressed.connect(_on_sign_in)
	add_child(_sign_in)
	for item in ITEMS:
		var c := _SkrCard.new()
		c.item = item
		c.act.connect(_on_act)
		add_child(c)
		_cards.append(c)
	Chain.notifier.session_changed.connect(refresh)
	DailySortie.notifier.changed.connect(refresh)


func _process(_delta: float) -> void:
	# The wallet opens a moment after the tap: follow it so the slab can offer
	# CANCEL, and drop back when it closes.
	if _doing != _WAITING or not visible or not _sign_in.visible:
		return
	if (_sign_in.text == "CANCEL") != Chain.busy():
		refresh()


## The tab came up: fetch the balance, what's owned, any payment still
## waiting, and today's ranked runs.
func opened() -> void:
	_note.text = ""
	refresh()
	if Chain.has_session():
		await Chain.retry_pending()
		await Chain.refresh_shop()
		DailySortie.refresh()
	refresh()
	_fetch_balance()


func focus() -> void:
	if _sign_in.visible:
		_sign_in.grab_focus()
	elif not _cards.is_empty():
		_cards[0].focus()


## Lay the header and a grid of cards into this panel's size.
func place(u: float, port: bool) -> void:
	_unit = u
	var fs := int(clampf(26.0 * u, 18.0, 34.0))
	_head.add_theme_font_size_override("font_size", fs)
	_note.add_theme_font_size_override("font_size", int(fs * 0.78))
	_head.position = Vector2.ZERO
	_head.size = Vector2(size.x * 0.6, fs * 1.4)
	_sign_in.custom_minimum_size = Vector2(200, 54) * u
	_sign_in.size = _sign_in.custom_minimum_size
	_sign_in.font_size = int(fs)
	_sign_in.position = Vector2(size.x - _sign_in.size.x - 4.0, 0)
	var head_h := maxf(fs * 1.4, _sign_in.size.y)
	_note.position = Vector2(0, head_h + 2.0)
	_note.size = Vector2(size.x, fs * 1.1)
	var top := head_h + fs * 1.3 + 8.0
	var cols := 2 if port else 4
	var rows := ceili(_cards.size() / float(cols))
	var gap := 14.0 * u
	var cw := (size.x - gap * (cols - 1)) / cols
	var ch := minf((size.y - top - gap * (rows - 1)) / rows, cw * 1.3)
	for i in _cards.size():
		var c := _cards[i]
		c.position = Vector2((i % cols) * (cw + gap), top + (i / cols) * (ch + gap))
		c.size = Vector2(cw, ch)
		c.pivot_offset = c.size * 0.5
		c.rotation = [-0.015, 0.012, -0.01, 0.015][i % 4]
		c.place()


func refresh() -> void:
	if _head == null:
		return
	var signed := Chain.has_session()
	_sign_in.visible = not signed and Chain.api_url != ""
	# While the wallet is open the same slab backs out of it: the wallet app can
	# be left without answering, and nothing else would end that request.
	var waiting := _doing == _WAITING and Chain.busy()
	_sign_in.text = "CANCEL" if waiting else "SIGN IN"
	_sign_in.disabled = (Chain.busy() or _doing != "") and not waiting
	if Chain.api_url == "":
		_head.text = "SKR SHOP OFFLINE"
	elif not signed and Chain.is_connected_wallet():
		_head.text = "WALLET CONNECTED, NOT SIGNED IN"
	elif not signed:
		_head.text = "SIGN IN TO SHOP WITH SKR"
	else:
		_head.text = "SKR  %s" % (_skr_text(_balance) if _balance >= 0.0 else "…")
	if _doing != "":
		_note.text = _doing
		_note.add_theme_color_override("font_color", GraffitiStyle.CYAN)
	elif _note.text == "" and Chain.pending_count() > 0:
		_note.text = "A payment is waiting for the leaderboard. It's added once seen."
		_note.add_theme_color_override("font_color", GraffitiStyle.SUN)
	elif _note.text == "" and not signed and Chain.api_url != "":
		# What to do here: one tap, one approval in the wallet, back in the shop.
		_note.text = "Tap SIGN IN, approve in your wallet, then come back here."
		_note.add_theme_color_override("font_color", GraffitiStyle.DIM)
	for c in _cards:
		c.refresh(signed, _doing != "" or Chain.busy())


func _fetch_balance() -> void:
	if not Chain.is_connected_wallet():
		return
	_balance = await Chain.skr_balance()
	if is_inside_tree():
		refresh()


func _on_sign_in() -> void:
	if _doing != "":
		# The slab reads CANCEL while the wallet is open.
		Chain.cancel()
		return
	_doing = _WAITING
	refresh()
	var r := await Chain.sign_in(Campaign.pilot_name())
	_doing = ""
	_say(r)
	refresh()
	_fetch_balance()


func _on_act(item: String) -> void:
	if Chain.owns(item):
		var kind := item.get_slice(":", 0)
		if Chain.equipped(kind) == item:
			Chain.unequip(kind)
		else:
			Chain.equip(item)
			GameAudio.ui(&"coin")
		refresh()
		return
	_note.text = ""
	_doing = _WAITING
	refresh()
	var r := await _buy(item)
	_doing = ""
	if r.ok:
		GameAudio.ui(&"coin")
		if item == "extra_attempt":
			toast.emit("+1 RANKED RUN!", GraffitiStyle.LIME)
			DailySortie.refresh()
		else:
			Chain.equip(item)
			toast.emit("%s!" % String(Chain.COSMETICS[item]["name"]), GraffitiStyle.LIME)
		_note.text = ""
		_fetch_balance()
	else:
		_say(r)
		if r.code == "paid_pending":
			_fetch_balance()
	refresh()


## [method Chain.buy], with the note line following along: the wallet first,
## then the leaderboard's look at the chain.
func _buy(item: String) -> Dictionary:
	var phase := func() -> void:
		# The wallet has answered once Chain isn't busy: from then on it's
		# the leaderboard looking for the payment.
		var opened := false
		while _doing != "" and is_inside_tree():
			opened = opened or Chain.busy()
			if opened and not Chain.busy() and _doing == _WAITING:
				_doing = "CHECKING THE PAYMENT ON CHAIN…"
				refresh()
			await get_tree().process_frame
	phase.call()
	return await Chain.buy(item)


func _say(r: Dictionary) -> void:
	if r.ok:
		# The wallet signed, but the leaderboard didn't open a session: without
		# a word here the shop just asked to sign in again, as if nothing happened.
		var server := String(r.get("server", ""))
		if server != "":
			_note.text = Chain.say("server_offline" if server == "offline" else "server_refused")
			_note.add_theme_color_override("font_color", GraffitiStyle.ORANGE)
			GameAudio.ui(&"locked")
		else:
			_note.text = ""
		return
	var words := Chain.say(String(r.code))
	_note.text = words
	_note.add_theme_color_override("font_color", GraffitiStyle.SUN if r.code == "paid_pending" else GraffitiStyle.ORANGE)
	if words != "":
		GameAudio.ui(&"locked")


static func _skr_text(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.2f" % v


## One thing SKR buys: a dark card with its look (stripes for a livery, a
## streak for a trail, a big +1 for a ranked run), its name, and the slab.
class _SkrCard:
	extends Control
	signal act(item: String)
	var item := ""
	var _slab: SlabButton
	var _blocked := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_slab = SlabButton.new()
		_slab.skew = 9.0
		_slab.pressed.connect(func() -> void: act.emit(item))
		add_child(_slab)

	func place() -> void:
		if _slab == null:
			return
		_slab.custom_minimum_size = Vector2(size.x * 0.84, clampf(size.y * 0.2, 42.0, 78.0))
		_slab.size = _slab.custom_minimum_size
		_slab.font_size = int(_slab.size.y * 0.4)
		_slab.position = Vector2((size.x - _slab.size.x) * 0.5, size.y - _slab.size.y - size.y * 0.05)
		queue_redraw()

	func focus() -> void:
		if _slab != null:
			_slab.grab_focus()

	func refresh(signed: bool, waiting: bool) -> void:
		if _slab == null:
			return
		var owned := Chain.owns(item)
		var worn := owned and Chain.equipped(item.get_slice(":", 0)) == item
		_blocked = ""
		if not signed:
			_blocked = "SIGN IN"
		elif (item == "extra_attempt" or Chain.COSMETICS.get(item, {}).get("genesis", false)) and not Chain.has_genesis():
			_blocked = "SEEKER GENESIS ONLY"
		if owned:
			_slab.text = "WORN ✓" if worn else "WEAR"
			_slab.fill = GraffitiStyle.SUN if worn else GraffitiStyle.CYAN
		elif Chain.COSMETICS.get(item, {}).get("genesis", false):
			# Never sold: it comes with the Genesis Token.
			_slab.text = "GENESIS"
			_slab.fill = Color("3a3150")
			_blocked = "SEEKER GENESIS ONLY" if signed else _blocked
		else:
			_slab.text = "%d SKR" % Chain.price_of(item)
			_slab.fill = GraffitiStyle.LIME
		_slab.text_color = GraffitiStyle.INK
		_slab.sub = _blocked if not owned else ""
		_slab.disabled = waiting or (_blocked != "" and not owned)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		GraffitiStyle.draw_slab(self, r, Color("2b2140"), size.x * 0.05, 4.0, Vector2(5, 7))
		var h := size.y
		# Top to bottom: the name, the look, (tall cards) what it is, the slab.
		var slab_top := _slab.position.y if _slab != null else h * 0.75
		var name := "+1 RANKED RUN" if item == "extra_attempt" else String(Chain.COSMETICS[item]["name"])
		var name_fs := int(clampf(minf(h * 0.12, size.x * 0.1), 14.0, 34.0))
		GraffitiStyle.draw_text(self, name, Vector2(size.x * 0.5, h * 0.06 + name_fs * 0.6), name_fs, Color.WHITE, 5, GraffitiStyle.head_font())
		var tall := h > 200.0
		var look_top := h * 0.06 + name_fs * 1.3
		var look_bot := slab_top - (h * 0.14 if tall else h * 0.06)
		var look := Rect2(Vector2(size.x * 0.14, look_top), Vector2(size.x * 0.72, maxf(look_bot - look_top, 8.0)))
		if item == "extra_attempt":
			GraffitiStyle.draw_text(self, "+1", look.get_center(), int(look.size.y * 0.95), GraffitiStyle.HOT, 7, GraffitiStyle.number_font())
		else:
			var cols: Array = Chain.COSMETICS[item]["colors"]
			if item.begins_with("paint:"):
				_draw_stripes(look, cols)
			else:
				_draw_streak(look, Color(String(cols[0])))
		if tall:
			var kind := "TODAY'S DAILY" if item == "extra_attempt" else ("LIVERY, EVERY HULL" if item.begins_with("paint:") else "SLING TRAIL")
			if Chain.COSMETICS.get(item, {}).get("genesis", false):
				kind = "SEEKER GENESIS PILOTS"
			GraffitiStyle.draw_text(self, kind, Vector2(size.x * 0.5, slab_top - h * 0.07), int(clampf(h * 0.05, 12.0, 22.0)), GraffitiStyle.DIM, 3)

	## A livery: its three colours as slanted bands.
	func _draw_stripes(r: Rect2, cols: Array) -> void:
		var w := r.size.x / cols.size()
		var lean := r.size.y * 0.35
		for i in cols.size():
			var x := r.position.x + i * w
			var pts := PackedVector2Array([
				Vector2(x + lean, r.position.y), Vector2(x + w + lean, r.position.y),
				Vector2(x + w, r.end.y), Vector2(x, r.end.y)])
			draw_colored_polygon(pts, Color(String(cols[i])))
		draw_polyline(PackedVector2Array([r.position + Vector2(lean, 0), Vector2(r.end.x + lean, r.position.y),
			r.end, Vector2(r.position.x, r.end.y), r.position + Vector2(lean, 0)]), GraffitiStyle.INK, 4.0)

	## A sling trail: a swoosh fading out behind a dot.
	func _draw_streak(r: Rect2, col: Color) -> void:
		var n := 24
		var prev := Vector2.ZERO
		for i in n + 1:
			var t := i / float(n)
			var p := Vector2(r.position.x + r.size.x * t, r.get_center().y + sin(t * PI * 1.6) * r.size.y * 0.32)
			if i > 0:
				draw_line(prev, p, Color(col.r, col.g, col.b, t), 3.0 + t * r.size.y * 0.18, true)
			prev = p
		draw_circle(prev, r.size.y * 0.16, Color.WHITE)
		draw_circle(prev, r.size.y * 0.11, col)
