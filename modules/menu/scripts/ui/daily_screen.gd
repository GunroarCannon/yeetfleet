## DailyScreen: today's Daily Sortie ([DailySortie]). The day's level on a
## card (its name, the job, how dangerous, when a new one comes), the
## pilot's streak, RANKED RUN and PRACTICE, and the day's board beside it
## (RANKED / OPEN tabs). Back from a daily run it opens here, with the run's
## points and, once the Worker has it, the rank.
##
## RANKED RUN says why when it can't go: sign in (the Pilot ID), a Seeker
## Genesis Token needed, or today's run used; then +1 RANKED RUN buys another
## with SKR ([method Chain.buy]). Each other pilot's row on the board has a
## TIP slab: SKR straight from this wallet to theirs ([method Chain.tip]).
class_name DailyScreen
extends MenuScreen

## Rows shown on the board.
const ROWS := 10

var _bar: TopBar
var _card: VBoxContainer
var _when: Label
var _title: Label
var _job: Label
var _streak: Label
var _result: Label
var _note: Label
var _ranked: SlabButton
var _practice: SlabButton
var _board: VBoxContainer
var _tabs: Array[SlabButton] = []
var _rows: VBoxContainer
var _me: Label
var _extra: SlabButton
var _tip_card: Control = null
var _which := "ranked"
## Bumped by every board fetch; an older answer arriving late is dropped.
var _fetch := 0


func _ready() -> void:
	_bar = TopBar.new()
	_bar.title = "DAILY SORTIE"
	_bar.back_pressed.connect(func() -> void: menu.go(MenuRoot.Screen.HOME))
	add_child(_bar)
	_card = VBoxContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_when = _line(_card, GraffitiStyle.DIM)
	_title = _line(_card, GraffitiStyle.LIME)
	_title.add_theme_font_override("font", GraffitiStyle.title_font())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job = _line(_card, Color.WHITE)
	_streak = _line(_card, GraffitiStyle.SUN)
	_result = _line(_card, GraffitiStyle.CYAN)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_card.add_child(row)
	_ranked = _button("RANKED RUN", GraffitiStyle.HOT, _on_ranked)
	row.add_child(_ranked)
	_practice = _button("PRACTICE", GraffitiStyle.CYAN, _on_practice)
	_practice.text_color = GraffitiStyle.INK
	row.add_child(_practice)
	_extra = _button("+1 RANKED RUN", GraffitiStyle.LIME, _on_extra)
	_extra.text_color = GraffitiStyle.INK
	_extra.sub = "%d SKR" % Chain.price_of("extra_attempt")
	_card.add_child(_extra)
	_note = _line(_card, GraffitiStyle.ORANGE)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_board = VBoxContainer.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_board.add_child(tabs)
	for t in ["ranked", "open"]:
		var b := _button(t.to_upper(), GraffitiStyle.VIOLET, _show_board.bind(t))
		tabs.add_child(b)
		_tabs.append(b)
	_rows = VBoxContainer.new()
	_board.add_child(_rows)
	_me = _line(_board, GraffitiStyle.SUN)
	DailySortie.notifier.changed.connect(_refresh)
	DailySortie.notifier.submitted.connect(_on_submitted)
	Chain.notifier.session_changed.connect(_on_session)
	layout()


func opened() -> void:
	layout()
	_note.text = ""
	_refresh()
	_show_board(_which)
	DailySortie.refresh()
	_practice.grab_focus.call_deferred()


func layout() -> void:
	if _bar == null:
		return
	var vp := viewport_size()
	var u := unit()
	var bar_h := bar_height()
	_bar.position = Vector2(0, 8)
	_bar.size = Vector2(vp.x, bar_h)
	var top := bar_h + 24.0
	var port := portrait()
	var card_w := vp.x - 36.0 if port else vp.x * 0.5
	_card.position = Vector2(18, top)
	_card.size = Vector2(card_w, 0)
	_card.add_theme_constant_override("separation", int(10 * u))
	var fs := clampf(minf(vp.x, vp.y) * 0.04, 16.0, 30.0 * u)
	for l: Label in [_when, _job, _streak, _result, _note, _me]:
		l.add_theme_font_size_override("font_size", int(fs))
		l.custom_minimum_size.x = card_w if l != _me else 0.0
	_title.add_theme_font_size_override("font_size", int(fs * 1.9))
	_title.custom_minimum_size.x = card_w
	var bw := minf((card_w - 16.0) * 0.5, 300.0 * u)
	for b in [_ranked, _practice]:
		b.custom_minimum_size = Vector2(bw, clampf(vp.y * 0.11, 56.0, 92.0 * u))
		b.font_size = int(fs * 1.1)
	_extra.custom_minimum_size = Vector2(bw, clampf(vp.y * 0.08, 48.0, 70.0 * u))
	_extra.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_extra.font_size = int(fs)
	if port:
		_board.position = Vector2(18, top + _card.get_combined_minimum_size().y + 40.0 * u)
		_board.size = Vector2(vp.x - 36.0, 0)
	else:
		_board.position = Vector2(vp.x * 0.5 + 36.0, top)
		_board.size = Vector2(vp.x * 0.5 - 54.0, 0)
	for b in _tabs:
		b.custom_minimum_size = Vector2(150, 48) * u
		b.font_size = int(fs)
	_board.set_meta("fs", fs)
	queue_redraw()


## Dark cards behind the day and the board: the text sits on the menu's
## live fight, which is too busy to read words off.
func _draw() -> void:
	if _card == null:
		return
	var bg := GraffitiStyle.INK
	bg.a = 0.82
	var pad := Vector2(14, 12) * unit()
	for c: Control in [_card, _board]:
		var r := Rect2(c.position - pad, Vector2(c.size.x, c.get_combined_minimum_size().y) + pad * 2.0)
		GraffitiStyle.draw_slab(self, r, bg, 12.0, 4.0, Vector2(7, 8))


# --- The day ---

func _refresh() -> void:
	if _card == null:
		return
	var lvl := DailySortie.level()
	var ends := DailySortie.ends_in_sec()
	_when.text = DailySortie.today() + ("   ·   NEW ONE IN %dH %02dM" % [ends / 3600, (ends % 3600) / 60] if ends > 0 else "")
	_title.text = String(lvl["title"]).to_upper()
	_job.text = "%s   ·   DANGER %s" % [String(lvl["word"]), "■".repeat(int(lvl["danger"])) + "□".repeat(5 - int(lvl["danger"]))]
	var s := DailySortie.streak()
	_streak.text = "STREAK: %d DAY%s" % [s, "" if s == 1 else "S"] if s > 0 else "FLY TODAY TO START A STREAK"
	_result.text = _result_words()
	_result.visible = _result.text != ""
	var why := _ranked_blocker()
	_ranked.disabled = why != ""
	_ranked.sub = why if why != "" else "%d LEFT TODAY" % DailySortie.ranked_left()
	_practice.sub = "AS MANY AS YOU LIKE"
	_extra.visible = why == "USED TODAY"
	_extra.disabled = Chain.busy()
	queue_redraw.call_deferred()


## Why RANKED RUN can't go, in a few words, or "".
func _ranked_blocker() -> String:
	if not Chain.has_session():
		return "SIGN IN FIRST" if Chain.api_url != "" else "LEADERBOARD OFFLINE"
	if not Chain.has_genesis():
		return "SEEKER GENESIS ONLY"
	if DailySortie.ranked_left() <= 0:
		return "USED TODAY"
	return ""


func _result_words() -> String:
	var l := DailySortie.last
	if l.is_empty() or l.get("day") != DailySortie.today():
		return ""
	var words := "%s RUN: %s   ·   %d PTS" % ["RANKED" if l.ranked else "PRACTICE", "WON" if l.won else "LOST", int(l.points)]
	var reply: Dictionary = l.get("reply", {})
	if reply.get("ok", false):
		words += "   ·   RANK %d" % int(reply.rank)
	elif not reply.is_empty():
		words += "   ·   NOT SENT (%s)" % String(reply.get("code", "?"))
	return words


func _on_ranked() -> void:
	await _go(true)


func _on_practice() -> void:
	await _go(false)


func _go(ranked: bool) -> void:
	_note.text = ""
	var r := await menu.launch_daily(ranked)
	if not r.ok:
		GameAudio.ui(&"locked")
		_note.text = _say(String(r.code))


func _on_extra() -> void:
	_note.text = "Waiting for the wallet…"
	_extra.disabled = true
	var r := await Chain.buy("extra_attempt")
	if r.ok:
		GameAudio.ui(&"coin")
		_note.text = "+1 ranked run. Good luck!"
		await DailySortie.refresh()
	else:
		_note.text = Chain.say(String(r.code))
		if _note.text != "":
			GameAudio.ui(&"locked")
	_refresh()


func _say(code: String) -> String:
	match code:
		"not_seeker":
			return "Ranked runs are for Seeker Genesis pilots. Practice is open to all."
		"no_attempts":
			return "Today's ranked run is flown. Back tomorrow!"
		"offline":
			return "The leaderboard can't be reached. Practice still works."
		"wrong_day":
			return "Your phone's date is off from the server's."
		"no_session":
			return "Sign in again (the Pilot ID on the home screen)."
	return "Couldn't start (%s)" % code


func _on_submitted(_reply: Dictionary) -> void:
	_refresh()
	_show_board(_which)


func _on_session() -> void:
	DailySortie.refresh()
	_refresh()


# --- The board ---

func _show_board(which: String) -> void:
	_which = which
	for i in _tabs.size():
		_tabs[i].fill = GraffitiStyle.SUN if ["ranked", "open"][i] == which else GraffitiStyle.VIOLET
		_tabs[i].text_color = GraffitiStyle.INK if ["ranked", "open"][i] == which else Color.WHITE
	_fetch += 1
	var mine := _fetch
	_fill_rows([], "…")
	var r := await DailySortie.leaderboard(which)
	if mine != _fetch or not is_inside_tree():
		return
	if not r.ok:
		_fill_rows([], "LEADERBOARD OFFLINE" if r.code == "offline" else "BOARD UNAVAILABLE (%s)" % r.code)
		return
	_fill_rows(r.rows, "NOBODY YET. BE FIRST!")
	var me: Variant = r.get("me")
	_me.text = "YOU: #%d   ·   %d PTS" % [int(me.rank), int(me.points)] if me is Dictionary else ""


func _fill_rows(rows: Array, empty: String) -> void:
	# The board's card follows its rows (freed ones go at the frame's end).
	queue_redraw.call_deferred()
	for c in _rows.get_children():
		c.queue_free()
	_me.text = ""
	var fs := int(_board.get_meta("fs", 22.0))
	if rows.is_empty():
		_rows.add_child(_cell(empty, GraffitiStyle.DIM, fs))
		return
	for row: Dictionary in rows.slice(0, ROWS):
		var name := String(row.get("name", ""))
		if name == "":
			name = Chain.short_key(String(row.get("pubkey", "")))
		var key := String(row.get("pubkey", ""))
		var mine := key == Chain.pubkey()
		var line := "%2d.  %s%s" % [int(row.rank), name, "  ◆" if row.get("seeker", false) else ""]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var l := _cell(line, GraffitiStyle.LIME if mine else Color.WHITE, fs)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_cell(str(int(row.points)), GraffitiStyle.SUN, fs))
		if not mine and key != "":
			var tip := _button("TIP", GraffitiStyle.CYAN, _open_tip.bind(key, name))
			tip.text_color = GraffitiStyle.INK
			tip.skew = 6.0
			tip.font_size = int(fs * 0.8)
			tip.custom_minimum_size = Vector2(fs * 3.4, fs * 1.6)
			h.add_child(tip)
		_rows.add_child(h)


# --- Tips ---

## A small card over the board: TIP <name>, the SKR presets, CANCEL.
func _open_tip(key: String, name: String) -> void:
	close_tip()
	var vp := viewport_size()
	var u := unit()
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2b2140")
	sb.set_border_width_all(4)
	sb.border_color = GraffitiStyle.INK
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18.0 * u)
	card.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(12 * u))
	card.add_child(box)
	var fs := int(clampf(28.0 * u, 18.0, 34.0))
	var head := _cell("TIP %s" % name, GraffitiStyle.SUN, fs)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var sub := _cell("SKR, wallet to wallet", GraffitiStyle.DIM, int(fs * 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * u))
	box.add_child(row)
	var first: SlabButton = null
	for amount in Chain.TIP_PRESETS:
		var b := _button("%d" % amount, GraffitiStyle.LIME, _send_tip.bind(key, name, amount))
		b.text_color = GraffitiStyle.INK
		b.sub = "SKR"
		b.font_size = fs
		b.custom_minimum_size = Vector2(110, 70) * u
		row.add_child(b)
		if first == null:
			first = b
	var cancel := _button("CANCEL", GraffitiStyle.VIOLET, close_tip)
	cancel.font_size = int(fs * 0.8)
	cancel.custom_minimum_size = Vector2(0, 50) * u
	box.add_child(cancel)
	add_child(card)
	_tip_card = card
	card.reset_size()
	card.position = (vp - card.get_combined_minimum_size()) * 0.5
	first.grab_focus.call_deferred()


## Close the tip card; false when none was open (Back goes on).
func close_tip() -> bool:
	if _tip_card == null or not is_instance_valid(_tip_card):
		_tip_card = null
		return false
	_tip_card.queue_free()
	_tip_card = null
	return true


func back() -> bool:
	return close_tip()


func _send_tip(key: String, name: String, amount: int) -> void:
	close_tip()
	_note.text = "Waiting for the wallet…"
	var r := await Chain.tip(key, amount)
	if r.ok:
		GameAudio.ui(&"coin")
		_note.text = "Tipped %s %d SKR!" % [name, amount]
	else:
		_note.text = Chain.say(String(r.code))


# --- Bits ---

func _line(parent: Control, col: Color) -> Label:
	var l := GraffitiStyle.label("", 24, col, 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _cell(text: String, col: Color, fs: int) -> Label:
	var l := GraffitiStyle.label(text, fs, col, 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(label: String, col: Color, on_press: Callable) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.fill = col
	b.skew = 9.0
	b.pressed.connect(on_press)
	return b
