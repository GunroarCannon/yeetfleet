## Temporary structural probe for the FlightMenu popup rework (scroll + outside
## tap). Not a permanent tool — verifies layout behaviour headlessly.
extends SceneTree


func _initialize() -> void:
	# 1) A tall popup must be capped to the screen and internally scrollable.
	var hud := Control.new()
	hud.name = "Hud"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(hud)
	# Give the hud a concrete size.
	var view := root as Viewport
	hud.size = view.get_visible_rect().size
	if hud.size.y < 400.0:
		hud.size = Vector2(480.0, 800.0)
	hud.position = Vector2.ZERO

	var popup := FlightMenu.DraggablePopup.new()
	hud.add_child(popup)
	popup.title = "Tall"
	for i in 60:
		popup.add_action_row("Row %d — a menu row that makes this long" % i, func() -> void: pass)
	# Simulate the real open path: let a layout frame run so row minimums are
	# real, then auto_fit (which is what _measure_open does).
	await process_frame
	popup.auto_fit(hud.size)
	print("POPUP tall: size=", popup.size, " screen=", hud.size)
	await process_frame
	await process_frame

	var problems := 0
	if popup.size.y > hud.size.y - 1.0:
		print("  FAIL: popup taller than screen"); problems += 1
	if popup.size.y < 200.0:
		print("  FAIL: tall popup measured as a sliver (y=%.0f)" % popup.size.y); problems += 1
	var scroll: ScrollContainer = null
	for child in popup.get_node("Body").get_children():
		if child is ScrollContainer:
			scroll = child
			break
	if scroll == null:
		print("  FAIL: no ScrollContainer in popup"); problems += 1
	elif scroll.get_v_scroll_bar().max_value <= 0.0:
		print("  FAIL: tall content is not scrollable (max=", scroll.get_v_scroll_bar().max_value, ")")
		problems += 1
	else:
		print("  ok: scrollbar max=%.0f px" % scroll.get_v_scroll_bar().max_value)
	popup.queue_free()

	# 2) A short popup should hug its rows (not cap to a tall window).
	var short := FlightMenu.DraggablePopup.new()
	hud.add_child(short)
	short.add_action_row("Only row", func() -> void: pass)
	short.auto_fit(hud.size)
	print("POPUP short: size=", short.size)
	await process_frame
	if short.size.y > 200.0:
		print("  FAIL: short popup did not hug content"); problems += 1
	short.queue_free()

	# 3) Opening a category shows a backdrop; closing hides it.
	var menu := FlightMenu.new()
	hud.add_child(menu)
	menu.attach(hud)
	menu.category_pressed.connect(func(_id: int) -> void: pass)
	menu.add_category(0, "batteries.png", "test")
	# Find the BackdropShade the menu created under the hud.
	await process_frame
	var backdrop: Control = null
	for child in hud.get_children():
		if child.name == "PopupBackdrop":
			backdrop = child
			break
	if backdrop == null:
		print("  FAIL: no backdrop created on attach"); problems += 1
	else:
		print("  ok: backdrop exists, visible before open=", backdrop.visible)
		menu._open(0)
		await process_frame
		print("  backdrop visible after open=", backdrop.visible)
		if not backdrop.visible:
			print("  FAIL: backdrop not shown on open"); problems += 1
		menu.close_all()
		await process_frame
		if backdrop.visible:
			print("  FAIL: backdrop still visible after close"); problems += 1

	print("")
	if problems == 0:
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % problems)
		quit(1)
