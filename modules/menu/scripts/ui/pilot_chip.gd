## PilotChip: the pilot's Solana wallet on one dark slanted slab, the Pilot
## ID. Signed out it reads CONNECT WALLET and a tap is one Sign-In-With-Solana
## prompt ([method Chain.sign_in]). While the wallet is open it reads
## WAITING… and a tap cancels. Signed in it shows the short key, the SKR
## balance and a tag: GENESIS when the leaderboard found a Seeker Genesis
## Token (ranked play), SEEKER on a Seeker without that check yet. A tap
## opens the Pilot ID card (copy the key, disconnect).
##
## A failure shows on the chip itself for a few seconds, in plain words
## ([method Chain.say]); backing out of the wallet shows nothing.
class_name PilotChip
extends Control

## How long a failure stays on the chip.
const SAY_SEC := 3.5

## The pilot's SKR, or -1 while unknown (not fetched, or no RPC).
var _skr := -1.0
## The failure being shown, and for how much longer.
var _said := ""
var _said_left := 0.0
## The Pilot ID card, while it is up.
var _card: CanvasLayer = null
## Bumped by every balance fetch; an older answer arriving late is dropped.
var _fetch := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Chain.notifier.connected.connect(_on_connected)
	Chain.notifier.disconnected.connect(_on_disconnected)
	Chain.notifier.paid.connect(_on_paid)
	Chain.notifier.failed.connect(_on_failed)
	Chain.notifier.session_changed.connect(queue_redraw)
	if Chain.is_connected_wallet():
		refresh_balance()


func _exit_tree() -> void:
	close_card()


## Fetch the SKR balance again (an RPC read, no wallet prompt).
func refresh_balance() -> void:
	_fetch += 1
	var mine := _fetch
	var skr := await Chain.skr_balance()
	if mine == _fetch and is_inside_tree():
		_skr = skr
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	accept_event()
	if Chain.busy():
		GameAudio.ui(&"back")
		Chain.cancel()
	elif Chain.is_connected_wallet():
		GameAudio.ui(&"open")
		_open_card()
	else:
		GameAudio.ui(&"tap")
		_sign_in()


func _sign_in() -> void:
	_said_left = 0.0
	queue_redraw()
	await Chain.sign_in(Campaign.pilot_name())
	queue_redraw()


func _on_connected(_key: String) -> void:
	_skr = -1.0
	refresh_balance()
	queue_redraw()


func _on_disconnected() -> void:
	_skr = -1.0
	_fetch += 1
	close_card()
	queue_redraw()


func _on_paid(_what: String, _sig: String) -> void:
	refresh_balance()


func _on_failed(_what: String, code: String) -> void:
	var words := Chain.say(code)
	if words == "":
		queue_redraw()
		return
	_said = words
	_said_left = SAY_SEC
	queue_redraw()


func _process(delta: float) -> void:
	# The WAITING… dots, and the failure fading out.
	if Chain.busy() or _said_left > 0.0:
		_said_left = maxf(_said_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var lean := h * 0.3
	var r := Rect2(Vector2.ZERO, size)
	var connected := Chain.is_connected_wallet()
	var busy := Chain.busy()
	var fill := Color("2b2140")
	if _said_left > 0.0:
		fill = fill.lerp(GraffitiStyle.HOT.darkened(0.35), minf(_said_left, 1.0))
	elif not connected and not busy:
		fill = GraffitiStyle.VIOLET.darkened(0.25)
	GraffitiStyle.draw_slab(self, r, fill, lean, 3.0, Vector2(4, 5))
	var mid := Vector2(size.x * 0.5, h * 0.5)
	var room := size.x - lean * 2.0 - 12.0
	if _said_left > 0.0:
		_text_fit(_said, mid, int(h * 0.34), room, Color.WHITE)
	elif busy:
		var dots := ".".repeat(1 + int(Time.get_ticks_msec() / 350) % 3)
		_text_fit("WAITING FOR WALLET" + dots, mid, int(h * 0.36), room, GraffitiStyle.SUN)
	elif not connected:
		_text_fit("CONNECT WALLET", mid, int(h * 0.42), room, GraffitiStyle.LIME)
	else:
		# Key | SKR, with the tag tucked under the key.
		var cut := size.x * 0.52
		draw_line(Vector2(cut + lean * 0.35, h * 0.16), Vector2(cut - lean * 0.35, h * 0.84), GraffitiStyle.CYAN, maxf(3.0, h * 0.07))
		var tag := _tag()
		var key_mid := Vector2(cut * 0.5 + lean * 0.2, h * (0.4 if tag != "" else 0.5))
		_text_fit(Chain.short_key(Chain.pubkey()), key_mid, int(h * 0.38), cut - lean - 10.0, GraffitiStyle.LIME)
		if tag != "":
			_text_fit(tag, Vector2(key_mid.x, h * 0.8), int(h * 0.24), cut - lean, GraffitiStyle.SUN if Chain.has_genesis() else GraffitiStyle.DIM)
		var skr := "…" if _skr < 0.0 else _amount(_skr)
		_text_fit(skr + " SKR", Vector2((cut + size.x - lean * 0.5) * 0.5, h * 0.52), int(h * 0.4),
				size.x - cut - lean - 10.0, GraffitiStyle.SUN, GraffitiStyle.number_font())


## GENESIS (the Worker found the token), SEEKER (the phone says so), or "".
func _tag() -> String:
	if Chain.has_genesis():
		return "GENESIS"
	return "SEEKER" if Chain.is_seeker() else ""


## [param text] centred on [param at], shrunk until it fits [param width].
func _text_fit(text: String, at: Vector2, fs: int, width: float, col: Color, font: Font = null) -> void:
	var f := font if font != null else GraffitiStyle.head_font()
	while fs > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	GraffitiStyle.draw_text(self, text, at, fs, col, 5, font)


## Whole SKR, with a decimal only when it is small: "1,240", "12.5".
static func _amount(skr: float) -> String:
	if skr < 100.0 and absf(skr - roundf(skr)) > 0.05:
		return "%.1f" % skr
	var s := str(int(roundf(skr)))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


# --- Pilot ID card ---

## Over everything (its own canvas layer): the full key, the SKR, the Seeker
## tag, and COPY / DISCONNECT / CLOSE. A tap outside closes it.
func _open_card() -> void:
	if _card != null and is_instance_valid(_card):
		return
	var vp := get_viewport_rect().size
	var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
	_card = CanvasLayer.new()
	_card.layer = 90
	get_tree().root.add_child(_card)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.07, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		var b := e as InputEventMouseButton
		if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
			GameAudio.ui(&"close")
			close_card())
	_card.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(18 * u))
	var plate := SlabCard.wrap(box, GraffitiStyle.SUN, u)
	center.add_child(plate)
	var head := GraffitiStyle.label("PILOT ID", int(64 * u), GraffitiStyle.SUN, int(12 * u))
	head.add_theme_font_override("font", GraffitiStyle.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	# The whole key, wrapped: it is the pilot's address, worth seeing once.
	var key := GraffitiStyle.label(Chain.pubkey(), int(24 * u), GraffitiStyle.LIME, int(5 * u))
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	key.custom_minimum_size.x = minf(560.0 * u, vp.x * 0.86 - plate.frame_width())
	box.add_child(key)
	var facts := "%s SKR   ·   %s" % ["?" if _skr < 0.0 else _amount(_skr), Chain.cluster().to_upper()]
	if _tag() != "":
		facts += "   ·   " + _tag()
	if Chain.api_url != "":
		facts += "
" + ("RANKED" if Chain.has_genesis() else "SIGNED IN, UNRANKED" if Chain.has_session() else "LEADERBOARD OFFLINE")
	var line := GraffitiStyle.label(facts, int(30 * u), GraffitiStyle.SUN, int(6 * u))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(18 * u))
	box.add_child(row)
	var copy := _card_button("COPY", GraffitiStyle.CYAN, GraffitiStyle.INK, u)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Chain.pubkey())
		copy.text = "COPIED")
	row.add_child(copy)
	var off := _card_button("DISCONNECT", GraffitiStyle.HOT, Color.WHITE, u)
	off.pressed.connect(_disconnect)
	row.add_child(off)
	var close := _card_button("CLOSE", GraffitiStyle.LIME, GraffitiStyle.INK, u)
	close.pressed.connect(close_card)
	box.add_child(close)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.pivot_offset = plate.get_combined_minimum_size() * 0.5
	plate.scale = Vector2(0.7, 0.7)
	plate.create_tween().tween_property(plate, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	close.grab_focus.call_deferred()
	refresh_balance()


func _card_button(label: String, col: Color, ink: Color, u: float) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.fill = col
	b.text_color = ink
	b.custom_minimum_size = Vector2(maxf(200.0, label.length() * 26.0), 72) * u
	b.font_size = int(30 * u)
	return b


func _disconnect() -> void:
	close_card()
	await Chain.disconnect_wallet()
	queue_redraw()


## True while the Pilot ID card is up (Back closes it first).
func card_open() -> bool:
	return _card != null and is_instance_valid(_card)


## Close the Pilot ID card, if it is up.
func close_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null
