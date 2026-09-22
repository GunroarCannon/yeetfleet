extends SceneTree

func _init() -> void:
	_run()

func _run() -> void:
	var scene: PackedScene = load("res://modules/flight/flight_test.tscn")
	if scene == null:
		print("ERROR: could not load flight_test.tscn")
		quit()
		return
	var root_node = scene.instantiate()
	root.add_child(root_node)
	
	var hud: FlightHud = null
	var stack = [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is FlightHud:
			hud = n
			break
		for c in n.get_children():
			stack.append(c)
	if hud == null:
		print("ERROR: FlightHud not found under root")
		quit()
		return

	await process_frame
	await process_frame

	print("AFTER FRAMES: Found FlightHud! Children count: ", hud.get_child_count())
	var btn: Button = hud.get_node("TopBar/Toolbar").get_child(0) as Button
	print("First toolbar button: ", btn.name, " | tooltip: ", btn.tooltip_text, " | global_rect: ", Rect2(btn.global_position, btn.size))
	var clicked := false
	btn.pressed.connect(func() -> void: clicked = true)
	
	var click_point: Vector2 = btn.global_position + btn.size * 0.5
	print("Click point: ", click_point)
	var under_ctrl: Control = null
	# Check through all controls recursively
	var all_controls: Array[Control] = []
	var c_stack: Array[Node] = [root_node]
	while not c_stack.is_empty():
		var curr = c_stack.pop_back()
		if curr is Control and curr.is_visible_in_tree():
			all_controls.append(curr)
		for child in curr.get_children():
			c_stack.append(child)
	
	print("\nAll visible controls containing click_point (in tree order):")
	for c in all_controls:
		if c.get_global_rect().has_point(click_point):
			var mf_name = ["STOP", "PASS", "IGNORE"][c.mouse_filter]
			print(" -> %s (%s) | z: %d | filter: %s | rect: %s" % [c.name, c.get_class(), c.z_index, mf_name, c.get_global_rect()])
	
	quit()
