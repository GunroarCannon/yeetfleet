## HomeScreen: the title over the frozen fight, and the way into everything.
##
## Landscape: the spray-painted title top-left, a staggered cascade of
## slanted comic panels down the right (CAMPAIGN, SANDBOX, GARAGE, SETTINGS,
## EXIT) and the wallet top-right. Portrait: title on top, the panels
## zig-zagging under it. Just big words — no icons, no small print.
##
## EXIT (and Back on the home screen) never quits straight away: it asks
## QUIT? with STAY and QUIT.
class_name HomeScreen
extends MenuScreen

var _title: GraffitiTitle
## Holds the panels; they are placed by hand in a staggered, tilted cascade
## (a container would line them up in a neat, dull column).
var _column: Control
var _buttons: Array[SlabButton] = []
var _wallet: WalletChip
## Debug mode only (Settings > DEBUG): the jump-anywhere chip.
var _debug: DebugJump = null
var _campaign: SlabButton
## Bottom-left: coin packs for real money.
var _store: SlabButton
## The QUIT? card, while it is up.
var _quit_card: Control = null


func _ready() -> void:
	_title = GraffitiTitle.new()
	# The name keeps getting re-sprayed in another graffiti face.
	_title.cycle = true
	add_child(_title)
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_campaign = _panel("CAMPAIGN", GraffitiStyle.HOT, _on_campaign)
	var sandbox := _panel("SANDBOX", GraffitiStyle.CYAN, _on_sandbox)
	# A brand-new pilot starts in flight school; the rest unlocks after it.
	if not Campaign.tutorial_done():
		sandbox.disabled = true
		sandbox.tooltip_text = "Finish flight school first."
	_panel("GARAGE", GraffitiStyle.SUN, func() -> void: menu.go(MenuRoot.Screen.GARAGE))
	_panel("SETTINGS", GraffitiStyle.VIOLET, func() -> void: menu.go(MenuRoot.Screen.SETTINGS))
	# Web and iOS have no "quit"; the browser tab or the home swipe is the exit.
	if not OS.has_feature("web") and not OS.has_feature("ios"):
		_panel("EXIT", Color("3a3150"), _ask_quit)
	_wallet = WalletChip.new()
	add_child(_wallet)
	_store = SlabButton.new()
	_store.text = "STORE"
	_store.fill = GraffitiStyle.SUN
	_store.text_color = GraffitiStyle.INK
	_store.skew = 10.0
	_store.pressed.connect(func() -> void: menu.go(MenuRoot.Screen.STORE))
	add_child(_store)
	if Session.debug_mode:
		_debug = DebugJump.new()
		_debug.menu = menu
		_debug.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_debug)
	layout()


## One home panel: a big word on a loud slab, nothing else — the home screen
## is the title and the fight, and the panels stay out of their way.
func _panel(label: String, col: Color, on_press: Callable) -> SlabButton:
	var b := SlabButton.new()
	b.text = label
	b.fill = col
	b.rich = true
	b.skew = 9.0
	# White with a fat ink outline on every slab: ink words on the yellow and
	# cyan slabs sank into their own shadows.
	b.text_color = Color.WHITE
	b.pressed.connect(on_press)
	_column.add_child(b)
	_buttons.append(b)
	return b


func opened() -> void:
	layout()
	# Entrance: title drops in, panels slide in from the right one by one.
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.25, 1.25)
	_title.modulate.a = 0.0
	var tt := create_tween().set_parallel()
	tt.tween_property(_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_title, "modulate:a", 1.0, 0.25)
	for i in _buttons.size():
		var b := _buttons[i]
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.12 + i * 0.07)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
	_buttons[0].grab_focus.call_deferred()


func layout() -> void:
	if _column == null:
		return
	var vp := viewport_size()
	var port := portrait()
	var n := _buttons.size()
	var u := unit()
	var bw := clampf(vp.x * (0.8 if port else 0.36), 280.0, 560.0 * u)
	var bh := clampf(vp.y * (0.085 if port else 0.125), 64.0, 112.0 * u)
	var wallet_h := clampf(minf(vp.x, vp.y) * 0.075, 44.0, 64.0 * u)
	# Short screens (a phone in landscape, after its DPI scale): shrink the
	# panels until the whole column fits under the wallet, EXIT included.
	# Portrait: the STORE slab sits under the column, so the column leaves it
	# room (landscape has it off to the side).
	var store_h := clampf(vp.y * (0.06 if port else 0.1), 48.0, 76.0 * u)
	var reserve := store_h + 24.0 if port else 0.0
	var room := vp.y * (0.55 if port else 1.0) - (0.0 if port else wallet_h + 26.0) - 14.0 - reserve
	bh = maxf(minf(bh, room / (n + (n - 1) * 0.36 + 0.34 + 0.16)), 38.0)
	var gap := bh * 0.36
	_wallet.size = Vector2(clampf(vp.x * (0.7 if port else 0.34), 250.0, 440.0 * u), wallet_h)
	_wallet.position = Vector2(vp.x - _wallet.size.x - 18, 14)
	var col_h := n * bh + (n - 1) * gap
	var top: float
	if port:
		_title.position = Vector2(-vp.x * 0.02, wallet_h + 16)
		_title.size = Vector2(vp.x * 1.04, vp.y * 0.24)
		top = maxf(minf(vp.y * 0.43, vp.y - col_h - 36.0 - reserve), _title.position.y + _title.size.y)
	else:
		_title.position = Vector2(vp.x * 0.005, vp.y * 0.02)
		_title.size = Vector2(vp.x * 0.6, vp.y * 0.38)
		top = clampf((vp.y - col_h) * 0.5 + 30.0, wallet_h + 26.0, maxf(vp.y - col_h - bh * 0.5 - 14.0, wallet_h + 26.0))
	_column.position = Vector2.ZERO
	_column.size = vp
	_store.custom_minimum_size = Vector2(clampf(vp.x * 0.16, 150.0, 230.0 * u), store_h)
	_store.size = _store.custom_minimum_size
	_store.font_size = int(_store.size.y * 0.42)
	_store.position = Vector2(18, vp.y - _store.size.y - 18)
	_store.pivot_offset = _store.size * 0.5
	_store.rotation = -0.03
	if _debug != null:
		_debug.menu = menu
		_debug.place(vp, _store.position.x + _store.size.x + 16.0)
	for i in n:
		var b := _buttons[i]
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = b.custom_minimum_size
		b.font_size = int(bh * 0.44)
		# The first panel is the big one: CAMPAIGN is what most taps want.
		if i == 0:
			b.size = Vector2(bw * 1.06, bh * 1.18)
			b.font_size = int(bh * 0.5)
		var x: float
		if port:
			# Zig-zag: panels hang off alternate edges.
			x = 14.0 if i % 2 == 0 else vp.x - b.size.x - 14.0
		else:
			# A cascade stepping down and a little to the left, like stacked
			# stickers, kept close to the right edge.
			x = vp.x - b.size.x - maxf(20.0, vp.x * 0.018) - i * bh * 0.2
		var y := top + i * (bh + gap) + (bh * 0.16 if i > 0 else 0.0)
		b.position = Vector2(x, y)
		b.pivot_offset = b.size * 0.5
		b.rotation = [-0.018, 0.012, -0.01, 0.015, -0.012][i % 5]


## Back on the home screen: close the QUIT? card, or ask it.
func back() -> bool:
	if _quit_card != null and is_instance_valid(_quit_card):
		_close_quit()
	elif not OS.has_feature("web") and not OS.has_feature("ios"):
		_ask_quit()
	return true


## QUIT? over a greyed-out home: STAY (the default) or QUIT.
func _ask_quit() -> void:
	if _quit_card != null and is_instance_valid(_quit_card):
		return
	var u := unit()
	_quit_card = ColorRect.new()
	(_quit_card as ColorRect).color = Color(0.03, 0.01, 0.07, 0.84)
	_quit_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_quit_card)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_card.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(26 * u))
	center.add_child(box)
	var q := GraffitiStyle.label("QUIT?", int(110 * u), GraffitiStyle.SUN, int(16 * u))
	q.add_theme_font_override("font", GraffitiStyle.title_font())
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(24 * u))
	box.add_child(row)
	var stay := SlabButton.new()
	stay.text = "STAY"
	stay.fill = GraffitiStyle.LIME
	stay.text_color = GraffitiStyle.INK
	stay.custom_minimum_size = Vector2(200, 72) * u
	stay.font_size = int(32 * u)
	stay.pressed.connect(_close_quit)
	row.add_child(stay)
	var go := SlabButton.new()
	go.text = "QUIT"
	go.fill = GraffitiStyle.HOT
	go.custom_minimum_size = Vector2(200, 72) * u
	go.font_size = int(32 * u)
	go.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(go)
	box.pivot_offset = box.get_combined_minimum_size() * 0.5
	box.scale = Vector2(0.7, 0.7)
	box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stay.grab_focus.call_deferred()


func _close_quit() -> void:
	if _quit_card != null and is_instance_valid(_quit_card):
		_quit_card.queue_free()
	_quit_card = null


func _on_campaign() -> void:
	if not Campaign.tutorial_done():
		menu.launch_tutorial()
		return
	menu.go(MenuRoot.Screen.MAP)


func _on_sandbox() -> void:
	menu.launch_sandbox()
