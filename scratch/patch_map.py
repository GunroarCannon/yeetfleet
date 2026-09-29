p = 'modules/menu/scripts/ui/level_map_view.gd'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b)


rep('''## LevelMapView: the campaign road as a board of polaroids.
##
## Each level is a tilted photo card (its [PicSet] picture, three stars on the
## photo, "Level N" on the white border), sectors are groups of five under a
## spray-painted name, and hand-drawn ink lines with doodled stars join them
## in order. The road ends in the fork sign (two sectors to choose from) or a
## locked "???" card.''', '''## LevelMapView: the campaign as a linked graph of polaroids.
##
## Each level is a tilted photo card (its [PicSet] picture, three stars on the
## photo, "Level N" on the white border). A sector's levels are laid out in
## columns by their links ([method LevelGen.graph_layers]): a level that opens
## two splits the road, and the roads rejoin at the sector's last level. A
## spray-painted name hangs over each sector and hand-drawn marker lines run
## along every link. Locked levels show no picture, just LOCKED and the stars
## they want; tapping one shakes it. The road ends in the fork sign (two
## sectors to choose from) or a locked "???" card.''')
rep('''## Laid-out cards: {rect, angle, lvl | fork, sector}. Board coordinates.
var _cards: Array[Dictionary] = []''', '''## Laid-out cards: {rect, angle, lvl | fork, sector}. Board coordinates.
var _cards: Array[Dictionary] = []
## Links to draw between cards: (from card index, to card index).
var _links: Array[Vector2i] = []
## Level key -> seconds of shake left (a tap on a locked card).
var _shake := {}''')

i = s.index('func _layout() -> void:')
j = s.index('func _clamp(o: Vector2) -> Vector2:')
s = s[:i] + '''func _layout() -> void:
	_cards.clear()
	_labels.clear()
	_links.clear()
	var port := _portrait()
	var u := maxf(minf(size.x, size.y) / 720.0, 0.5)
	_card_w = clampf((size.x * 0.3) if port else (size.y * 0.25), 104.0, 176.0 * u)
	var cw := _card_w
	var ch := cw * 1.2
	# Generous room between cards: the links should read as roads.
	var step_layer := (ch * 1.7) if port else (cw * 2.05)
	var step_lane := (cw * 1.55) if port else (ch * 1.3)
	var cursor := Vector2(cw * 0.6, cw * 0.4)
	var prev_boss := -1
	for s in _sectors:
		var rng := RandomNumberGenerator.new()
		rng.seed = LevelGen.seed_of("map/" + String(s["key"]))
		var route: Array = s["route"]
		var layers := LevelGen.graph_layers(route)
		var graph := LevelGen.sector_graph(route)
		var levels: Array = s["levels"]
		var max_layer := 0
		for l in layers:
			max_layer = maxi(max_layer, l)
		var widest := 1
		for k in max_layer + 1:
			widest = maxi(widest, layers.count(k))
		_labels.append({"pos": cursor, "text": String(s["name"]), "color": s["color"], "angle": rng.randf_range(-0.06, 0.03)})
		var origin := cursor + Vector2(0, cw * 0.55)
		var mid := origin + (Vector2(step_lane * (widest - 1) * 0.5, 0) if port else Vector2(0, step_lane * (widest - 1) * 0.5 + ch * 0.5))
		var first := _cards.size()
		for i in levels.size():
			var layer := layers[i]
			var lane_list: Array[int] = []
			for k in levels.size():
				if layers[k] == layer:
					lane_list.append(k)
			var lane := float(lane_list.find(i)) - (lane_list.size() - 1) * 0.5
			var jitter := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * cw * 0.12
			var p: Vector2
			if port:
				p = mid + Vector2(lane * step_lane, layer * step_layer + ch * 0.5) + jitter
			else:
				p = mid + Vector2(layer * step_layer + cw * 0.5, lane * step_lane) + jitter
			_cards.append({
				"rect": Rect2(p - Vector2(cw, ch) * 0.5, Vector2(cw, ch)), "angle": rng.randf_range(-0.08, 0.08),
				"lvl": levels[i], "sector": s,
				# Read once per layout, not per frame: the board redraws every frame.
				"rec": Campaign.record(String(levels[i]["key"])),
				"unlocked": Campaign.is_unlocked(levels[i]),
				"road": Campaign.road_open(levels[i]),
			})
		for i in graph.size():
			for j in (graph[i] as Array):
				_links.append(Vector2i(first + i, first + int(j)))
		if prev_boss >= 0:
			_links.append(Vector2i(prev_boss, first))
		prev_boss = first + levels.size() - 1
		var span := (max_layer + 1) * step_layer
		if port:
			cursor = Vector2(cursor.x, origin.y + step_lane * 0.0 + span + ch * 0.4)
		else:
			cursor = Vector2(origin.x + span + cw * 0.3, cursor.y)
	# The end of the road: the fork, or a locked teaser.
	var tail := cursor + Vector2(0, cw * 0.55)
	if not _fork.is_empty():
		_labels.append({"pos": cursor, "text": "FORK!", "color": GraffitiStyle.SUN, "angle": -0.05})
		for i in _fork.size():
			var p2 := tail + (Vector2(i * cw * 1.6, 0) if port else Vector2(0, i * ch * 1.1))
			_links.append(Vector2i(prev_boss, _cards.size()))
			_cards.append({"rect": Rect2(p2, Vector2(cw * 1.2, ch * 0.8)), "angle": -0.05 + i * 0.1, "fork": _fork[i], "styled": i == 1})
	else:
		_links.append(Vector2i(prev_boss, _cards.size()))
		_cards.append({"rect": Rect2(tail, Vector2(cw, ch)), "angle": 0.06, "teaser": true})
	_board = Rect2()
	for c in _cards:
		_board = (c["rect"] as Rect2) if _board.size == Vector2.ZERO else _board.merge(c["rect"])
	for l in _labels:
		_board = _board.expand(l["pos"])
	_board = _board.grow(cw * 0.6)
	_offset = _clamp(_offset)


''' + s[j:]

i = s.index('## Ink lines between consecutive cards')
j = s.index('func _doodle_star(')
s = s[:i] + '''## A marker line along every link, wobbly as if drawn by hand, with a
## doodled star at some of them. Cream where the road has been driven (the
## level it leaves is won), dashed where it is still ahead.
func _draw_roads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for link in _links:
		if link.x < 0 or link.y >= _cards.size():
			continue
		var from: Dictionary = _cards[link.x]
		var a := (from["rect"] as Rect2).get_center()
		var b := (_cards[link.y]["rect"] as Rect2).get_center()
		var mid := a.lerp(b, 0.5) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _card_w * 0.18
		var pts := PackedVector2Array()
		for k in 17:
			var t := k / 16.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		var won := from.has("lvl") and int(from["rec"]["wins"]) > 0
		draw_polyline(pts, GraffitiStyle.INK, 9.0, true)
		if won:
			draw_polyline(pts, GraffitiStyle.PAPER, 4.5, true)
		else:
			for k in range(0, pts.size() - 1, 2):
				draw_line(pts[k], pts[k + 1], GraffitiStyle.DIM, 4.0, true)
		if rng.randf() < 0.5:
			_doodle_star(mid + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _card_w * 0.2, _card_w * rng.randf_range(0.07, 0.11))


''' + s[j:]

rep('''		if c.has("lvl"):
			level_tapped.emit(c["lvl"])
		elif c.has("fork"):
			fork_tapped.emit(int(c["fork"]))
		return''', '''		if c.has("lvl"):
			if bool(c["unlocked"]):
				level_tapped.emit(c["lvl"])
			else:
				# Locked: a shake says "not yet". No sheet, no words.
				_shake[String(c["lvl"]["key"])] = 0.4
		elif c.has("fork"):
			fork_tapped.emit(int(c["fork"]))
		return''')
rep('''	_t += delta
	if not _press and _vel.length() > 5.0:''', '''	_t += delta
	for k in _shake.keys():
		_shake[k] = float(_shake[k]) - delta
		if float(_shake[k]) <= 0.0:
			_shake.erase(k)
	if not _press and _vel.length() > 5.0:''')
rep('''	var lift := sin(_t * 3.0) * 4.0 if is_next else 0.0
	var ctr := r.get_center() + Vector2(0, lift)''', '''	var lift := sin(_t * 3.0) * 4.0 if is_next else 0.0
	var shake := float(_shake.get(key, 0.0))
	var ctr := r.get_center() + Vector2(sin(_t * 70.0) * 9.0 * (shake / 0.4), lift)''')

i = s.index('	var pic: Dictionary = lvl["pic"]\n	_draw_cover(')
j = s.index('	# A required ship type:')
s = s[:i] + '''	var pic: Dictionary = lvl["pic"]
	if not unlocked:
		# Locked: no picture at all, only what stands in the way.
		draw_rect(photo, Color("1c1628"))
		var lfs := int(r.size.x * 0.15)
		GraffitiStyle.draw_text(self, "LOCKED", photo.get_center() - Vector2(0, lfs * 0.5), lfs, GraffitiStyle.DIM, 4)
		var need := int(lvl["stars_req"])
		if bool(c["road"]) and need > Campaign.total_stars():
			# The road is open, the stars are not: show how many it wants.
			var sc := photo.get_center() + Vector2(-lfs * 0.7, lfs * 0.75)
			GraffitiIcons.draw(self, "star", sc, lfs * 1.1)
			GraffitiStyle.draw_text(self, str(need), sc + Vector2(lfs * 1.35, 0), lfs, GraffitiStyle.SUN, 4)
	else:
		_draw_cover(_bg_tex(lvl), photo, int(pic["roll"]))
		var fg := _fg_tex(lvl)
		if fg != null:
			# Fit the square subject inside the photo: never stretched.
			var side := minf(photo.size.x, photo.size.y) * 0.96
			var fr := Rect2(photo.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			if bool(pic["flip"]):
				fr = Rect2(Vector2(fr.end.x, fr.position.y), Vector2(-fr.size.x, fr.size.y))
			draw_texture_rect(fg, fr, false)
		var st := photo.size.x * 0.2
		for i in 3:
			var sc2 := Vector2(photo.get_center().x + (i - 1) * st * 1.05, photo.end.y - st * 0.55 - (st * 0.1 if i == 1 else 0.0))
			GraffitiIcons.draw(self, "star" if i < int(rec["stars"]) else "star_empty", sc2, st)
	draw_rect(photo, GraffitiStyle.INK, false, 2.0)
''' + s[j:]

# the kind icon next to "Level N", the fork arrow and teaser lock go
for line in s.split('\n'):
    pass
s = '\n'.join(l for l in s.split('\n') if not ('GraffitiIcons.draw(self, String(lvl["icon"])' in l or '"arrow_r"' in l or '"lock"' in l))
rep('''	draw_string(f, Vector2(-lw * 0.5 + label_fs * 0.4, ly), label''', '''	draw_string(f, Vector2(-lw * 0.5, ly), label''')
open(p, 'w', encoding='utf-8').write(s)
print("ok")
