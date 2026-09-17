func _draw_edge_indicators(camera: Camera3D, centre: Vector2) -> void:
	if _root._ai_spawner == null:
		return
	var player_ship = _root.active_ship_node()
	if player_ship == null:
		return
		
	var max_range := 3000.0
	var player_pos := player_ship.global_position
	
	for ship in _root._ai_spawner._ships:
		if not is_instance_valid(ship) or not ship._alive or ship == player_ship:
			continue
			
		var dist := player_pos.distance_to(ship.global_position)
		if dist > max_range:
			continue
			
		var point := camera.unproject_position(ship.global_position)
		var is_behind := camera.is_position_behind(ship.global_position)
		var screen_rect := Rect2(Vector2.ZERO, size)
		
		if is_behind or not screen_rect.grow(-10.0).has_point(point):
			var dir_to_ship = (ship.global_position - camera.global_position).normalized()
			var local_dir = camera.global_transform.basis.inverse() * dir_to_ship
			
			var angle = atan2(local_dir.y, local_dir.x)
			var arrow_dir = Vector2(cos(angle), -sin(angle))
			
			# Edge clamp
			var edge_margin := 30.0
			var half_size = size * 0.5 - Vector2(edge_margin, edge_margin)
			var scale_x = half_size.x / abs(arrow_dir.x) if arrow_dir.x != 0 else 9999.0
			var scale_y = half_size.y / abs(arrow_dir.y) if arrow_dir.y != 0 else 9999.0
			var clamp_scale = minf(scale_x, scale_y)
			
			var edge_pos = centre + arrow_dir * clamp_scale
			
			var col = BuilderTheme.warn()
			if ship.team == 1:
				col = BuilderTheme.good()
			
			col.a = clampf(1.0 - (dist / max_range), 0.2, 0.8)
			_draw_indicator_arrow(edge_pos, arrow_dir.angle() + PI*0.5, 8.0, col, Color.BLACK)

func _draw_minimap(camera: Camera3D) -> void:
	var player_ship = _root.active_ship_node()
	if player_ship == null:
		return
		
	var r := 75.0
	var centre := Vector2(size.x - r - 20.0, r + 70.0) # Down a bit from top-right to avoid menu
	var max_range := 5000.0
	
	_overlay.draw_circle(centre, r, Color(0, 0, 0, 0.4))
	_overlay.draw_arc(centre, r, 0.0, TAU, 32, BuilderTheme.text_dim(), 1.0, true)
	
	# Draw player
	_overlay.draw_circle(centre, 3.0, BuilderTheme.text_strong_color())
	
	var player_pos := player_ship.global_position
	# For minimap rotation, we want up to be player forward
	var player_fwd := -player_ship.global_transform.basis.z
	var player_right := player_ship.global_transform.basis.x
	
	# Draw AI ships
	if _root._ai_spawner != null:
		for ship in _root._ai_spawner._ships:
			if not is_instance_valid(ship) or not ship._alive or ship == player_ship:
				continue
			var dist := player_pos.distance_to(ship.global_position)
			if dist > max_range:
				continue
			
			var offset_world = ship.global_position - player_pos
			# Project to XZ plane relative to player
			var dot_fwd = offset_world.dot(player_fwd)
			var dot_right = offset_world.dot(player_right)
			
			var map_pos = centre + Vector2(dot_right, -dot_fwd) / max_range * r
			if map_pos.distance_to(centre) <= r:
				var col = BuilderTheme.good() if ship.team == 1 else BuilderTheme.warn()
				_overlay.draw_circle(map_pos, 2.5, col)
				
	# Draw planets
	for landmark in _root.landmarks():
		var pos: Vector3 = landmark["position"]
		var dist := player_pos.distance_to(pos)
		var offset_world = pos - player_pos
		var dot_fwd = offset_world.dot(player_fwd)
		var dot_right = offset_world.dot(player_right)
		var dir = Vector2(dot_right, -dot_fwd).normalized()
		
		var col: Color = landmark["color"]
		if dist <= max_range:
			var map_pos = centre + dir * (dist / max_range * r)
			_overlay.draw_circle(map_pos, 4.0, col)
		else:
			# Draw on edge
			var map_pos = centre + dir * r
			_overlay.draw_arc(map_pos, 3.0, 0.0, TAU, 8, col, 1.5, true)
