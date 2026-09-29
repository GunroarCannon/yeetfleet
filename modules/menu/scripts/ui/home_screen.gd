## HomeScreen: the title over the frozen fight, and the way into everything.
##
## Landscape: the spray-painted title top-left, a staggered cascade of
## slanted comic panels down the right (CAMPAIGN, SANDBOX, GARAGE, SETTINGS,
## EXIT) and the wallet top-right. Portrait: title on top, the panels
## zig-zagging under it. Just big words — no icons, no small print.
class_name HomeScreen
extends MenuScreen

var _title: GraffitiTitle
## Holds the panels; they are placed by hand in a staggered, tilted cascade
## (a container would line them up in a neat, dull column).
var _column: Control
var _buttons: Array[SlabButton] = []
var _wallet: WalletChip
## Debug builds only: the jump-anywhere chip.
var _debug: DebugJump = null
var _campaign: SlabButton


func _ready() -> void:
	_title = GraffitiTitle.new()
	add_child(_title)
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_campaign = _panel("CAMPAIGN", GraffitiStyle.HOT, _on_campaign)
	_panel("SANDBOX", GraffitiStyle.CYAN, _on_sandbox)
	_panel("GARAGE", GraffitiStyle.SUN, func() -> void: menu.go(MenuRoot.Screen.GARAGE))
	_panel("SETTINGS", GraffitiStyle.VIOLET, func() -> void: menu.go(MenuRoot.Screen.SETTINGS))
	# Web and iOS have no "quit"; the browser tab or the home swipe is the exit.
	if not OS.has_feature("web") and not OS.has_feature("ios"):
		_panel("EXIT", Color("3a3150"), func() -> void: get_tree().quit())
	_wallet = WalletChip.new()
	add_child(_wallet)
	if OS.is_debug_build():
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
	b.text_color = GraffitiStyle.INK if col in [GraffitiStyle.SUN, GraffitiStyle.CYAN] else Color.WHITE
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
	var gap := bh * 0.36
	var wallet_h := clampf(minf(vp.x, vp.y) * 0.075, 44.0, 64.0 * u)
	_wallet.size = Vector2(clampf(vp.x * (0.62 if port else 0.3), 220.0, 380.0 * u), wallet_h)
	_wallet.position = Vector2(vp.x - _wallet.size.x - 18, 14)
	var col_h := n * bh + (n - 1) * gap
	var top: float
	if port:
		_title.position = Vector2(-vp.x * 0.02, wallet_h + 16)
		_title.size = Vector2(vp.x * 1.04, vp.y * 0.24)
		top = maxf(vp.y * 0.43, vp.y - col_h - 36.0)
	else:
		_title.position = Vector2(vp.x * 0.005, vp.y * 0.02)
		_title.size = Vector2(vp.x * 0.6, vp.y * 0.38)
		top = maxf(wallet_h + 48.0, (vp.y - col_h) * 0.5 + 30.0)
	_column.position = Vector2.ZERO
	_column.size = vp
	if _debug != null:
		_debug.menu = menu
		_debug.place(vp)
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
			# A cascade stepping down and to the left, like stacked stickers.
			x = vp.x - b.size.x - maxf(36.0, vp.x * 0.035) - i * bh * 0.32
		var y := top + i * (bh + gap) + (bh * 0.16 if i > 0 else 0.0)
		b.position = Vector2(x, y)
		b.pivot_offset = b.size * 0.5
		b.rotation = [-0.018, 0.012, -0.01, 0.015, -0.012][i % 5]


func _on_campaign() -> void:
	menu.go(MenuRoot.Screen.MAP)


func _on_sandbox() -> void:
	menu.launch_sandbox()
