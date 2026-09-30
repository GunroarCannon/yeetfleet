## LevelMapView: the campaign as a linked graph of polaroids.
##
## Each level is a tilted photo card (its [PicSet] picture, three stars on the
## photo, "Level N" on the white border). A sector's levels are laid out in
## columns by their links ([method LevelGen.graph_layers]): a level that opens
## two splits the road, and the roads rejoin at the sector's last level. A
## spray-painted name hangs over each sector and hand-drawn marker lines run
## along every link. Locked levels show no picture, just LOCKED and the stars
## they want; tapping one shakes it (and the map says how to open it). The road ends in the fork sign (two
## sectors to choose from) or a locked "???" card.
##
## One custom-drawn Control rather than a node per card: the whole board pans
## as one (drag, wheel, keys) and draws in a single pass. Taps are told apart
## from drags by distance and hit-tested against each card's rectangle.
class_name LevelMapView
extends Control

signal level_tapped(lvl: Dictionary)
signal fork_tapped(theme: int)
## A locked card was tapped: the map toasts what opens it.
signal locked_tapped(lvl: Dictionary)

## Pixels a press can move and still count as a tap.
const TAP_SLOP := 14.0

var _sectors: Array[Dictionary] = []
var _fork: Array[int] = []
## Laid-out cards: {rect, angle, lvl | fork, sector}. Board coordinates.
var _cards: Array[Dictionary] = []
## Links to draw between cards: (from card index, to card index).
var _links: Array[Vector2i] = []
## Level key -> seconds of shake left (a tap on a locked card).
var _shake := {}
## Sector labels: {pos, text, color, angle}.
var _labels: Array[Dictionary] = []
var _board := Rect2()
var _offset := Vector2.ZERO
var _vel := Vector2.ZERO
var _press := false
var _press_at := Vector2.ZERO
var _moved := 0.0
var _t := 0.0
var _card_w := 150.0
var _next_key := ""
var _tex := {}
var _fg := {}
## Pixels at the top that the screen's bar covers. The view itself runs to the
## top of the screen (one tint, nothing sliced at the bar's edge); the board
## only settles below this line.
var top_inset := 0.0
## Colour grades a card's background can be printed in (picked by its roll).
const GRADES: Array[Color] = [
	Color(1, 1, 1), Color(1.08, 0.92, 0.78), Color(0.82, 0.95, 1.12),
	Color(1.08, 0.82, 1.06), Color(0.88, 1.08, 0.86), Color(1.1, 1.0, 0.7),
]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


func _ready() -> void:
	resized.connect(rebuild)


## Re-read the campaign and lay the board out again.
func rebuild() -> void:
	_sectors = Campaign.sectors()
	_fork.clear()
	if Campaign.at_fork():
		_fork = Campaign.fork_options()
	_next_key = ""
	for s in _sectors:
		for l in s["levels"]:
			if _next_key == "" and Campaign.is_unlocked(l) and int(Campaign.record(String(l["key"]))["wins"]) == 0:
				_next_key = String(l["key"])
	_layout()
	queue_redraw()


## Pan so the next level to play (or the fork) is in view.
func focus_next(instant := false) -> void:
	var target := Vector2.ZERO
	for c in _cards:
		if c.has("fork") or (c.has("lvl") and String(c["lvl"]["key"]) == _next_key):
			target = (c["rect"] as Rect2).get_center()
			break
	var want := Vector2(size.x * 0.5, top_inset + (size.y - top_inset) * 0.5) - target
	_offset = _clamp(want) if instant else _offset
	if not instant:
		var tw := create_tween()
		tw.tween_method(func(v: Vector2) -> void:
			_offset = v
			queue_redraw(), _offset, _clamp(want), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _portrait() -> bool:
	return size.y > size.x


func _layout() -> void:
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
		# A name is drawn up from its baseline: take in its whole height.
		_board = _board.expand(l["pos"])
		_board = _board.expand((l["pos"] as Vector2) - Vector2(0, cw * 0.4))
	_board = _board.grow(cw * 0.6)
	_offset = _clamp(_offset)


func _clamp(o: Vector2) -> Vector2:
	# The visible area: the whole view below the bar.
	var area := Rect2(Vector2(0, top_inset), size - Vector2(0, top_inset))
	var lo := area.end - _board.end
	var hi := area.position - _board.position
	return Vector2(
		clampf(o.x, minf(lo.x, hi.x), maxf(lo.x, hi.x)) if _board.size.x > area.size.x else area.position.x + (area.size.x - _board.size.x) * 0.5 - _board.position.x,
		clampf(o.y, minf(lo.y, hi.y), maxf(lo.y, hi.y)) if _board.size.y > area.size.y else area.position.y + (area.size.y - _board.size.y) * 0.5 - _board.position.y,
	)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for k in _shake.keys():
		_shake[k] = float(_shake[k]) - delta
		if float(_shake[k]) <= 0.0:
			_shake.erase(k)
	if not _press and _vel.length() > 5.0:
		_offset = _clamp(_offset + _vel * delta)
		_vel = _vel.lerp(Vector2.ZERO, clampf(delta * 4.0, 0.0, 1.0))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = true
				_press_at = mb.position
				_moved = 0.0
				_vel = Vector2.ZERO
			elif _press:
				_press = false
				if _moved < TAP_SLOP:
					_tap(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var step := 90.0 * (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1.0)
			_offset = _clamp(_offset + (Vector2(0, step) if _portrait() else Vector2(step, 0)))
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _press:
		_moved += mm.relative.length()
		_offset = _clamp(_offset + mm.relative)
		_vel = mm.relative / maxf(get_process_delta_time(), 0.001)
		accept_event()
		return
	if event.is_action_pressed("ui_right"):
		_offset = _clamp(_offset + Vector2(-160, 0))
	elif event.is_action_pressed("ui_left"):
		_offset = _clamp(_offset + Vector2(160, 0))
	elif event.is_action_pressed("ui_down"):
		_offset = _clamp(_offset + Vector2(0, -160))
	elif event.is_action_pressed("ui_up"):
		_offset = _clamp(_offset + Vector2(0, 160))
	elif event.is_action_pressed("ui_accept"):
		for c in _cards:
			if c.has("lvl") and String(c["lvl"]["key"]) == _next_key:
				level_tapped.emit(c["lvl"])
				return
			if c.has("fork"):
				fork_tapped.emit(int(c["fork"]))
				return


func _tap(at: Vector2) -> void:
	var p := at - _offset
	for i in range(_cards.size() - 1, -1, -1):
		var c: Dictionary = _cards[i]
		if not (c["rect"] as Rect2).grow(6.0).has_point(p):
			continue
		if c.has("lvl"):
			if bool(c["unlocked"]):
				level_tapped.emit(c["lvl"])
			else:
				# Locked: a shake says "not yet", and a toast says how.
				_shake[String(c["lvl"]["key"])] = 0.4
				locked_tapped.emit(c["lvl"])
		elif c.has("fork"):
			fork_tapped.emit(int(c["fork"]))
		return


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	var tint := Color(0.04, 0.02, 0.1, 0.38)
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	draw_set_transform(_offset)
	_draw_roads()
	for l in _labels:
		_draw_label(l)
	var view := Rect2(-_offset, size).grow(_card_w)
	for c in _cards:
		if not view.intersects(c["rect"]):
			continue
		if c.has("lvl"):
			_draw_level(c)
		elif c.has("fork"):
			_draw_fork(c)
		else:
			_draw_teaser(c)
	draw_set_transform(Vector2.ZERO)


## A marker line along every link, wobbly as if drawn by hand, with a
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


func _doodle_star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var a := -PI * 0.5 + TAU * i / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.35))
	draw_polyline(pts, GraffitiStyle.INK, 5.0, true)
	draw_polyline(pts, GraffitiStyle.PAPER, 2.0, true)


func _draw_label(l: Dictionary) -> void:
	var f := GraffitiStyle.title_font()
	var fs := int(_card_w * 0.3)
	draw_set_transform(_offset + (l["pos"] as Vector2), float(l["angle"]))
	var text := String(l["text"])
	draw_string_outline(f, Vector2(4, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.22), Color(0, 0, 0, 0.55))
	draw_string_outline(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.22), GraffitiStyle.INK)
	draw_string(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, l["color"] as Color)
	draw_set_transform(_offset)


## A polaroid: shadow, white frame, the photo (background + subject), three
## stars on the photo, the level's number on the border.
func _draw_level(c: Dictionary) -> void:
	var lvl: Dictionary = c["lvl"]
	var r: Rect2 = c["rect"]
	var key := String(lvl["key"])
	var unlocked := bool(c["unlocked"])
	var rec: Dictionary = c["rec"]
	var is_next := key == _next_key
	var lift := sin(_t * 3.0) * 4.0 if is_next else 0.0
	var shake := float(_shake.get(key, 0.0))
	var ctr := r.get_center() + Vector2(sin(_t * 70.0) * 9.0 * (shake / 0.4), lift)
	draw_set_transform(_offset + ctr, float(c["angle"]))
	var half := r.size * 0.5
	var frame := Rect2(-half, r.size)
	draw_rect(Rect2(frame.position + Vector2(6, 8), frame.size), Color(0, 0, 0, 0.45))
	if is_next:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(frame.grow(6.0 + pulse * 3.0), GraffitiStyle.LIME)
	draw_rect(frame, Color("f7f4ec"))
	var pad := r.size.x * 0.07
	var photo := Rect2(frame.position + Vector2(pad, pad), Vector2(r.size.x - pad * 2, r.size.y * 0.7))
	var pic: Dictionary = lvl["pic"]
	if not unlocked:
		# Locked: no picture at all, only what stands in the way.
		draw_rect(photo, Color("1c1628"))
		var lfs := int(r.size.x * 0.15)
		GraffitiStyle.draw_text(self, "LOCKED", photo.get_center() - Vector2(0, lfs * 0.5), lfs, GraffitiStyle.DIM, 4)
		var need := int(lvl["stars_req"])
		if need > Campaign.total_stars():
			# Stars are the key: show how many it wants.
			var sc := photo.get_center() + Vector2(-lfs * 0.7, lfs * 0.75)
			GraffitiIcons.draw(self, "star", sc, lfs * 1.1)
			GraffitiStyle.draw_text(self, str(need), sc + Vector2(lfs * 1.35, 0), lfs, GraffitiStyle.SUN, 4, GraffitiStyle.number_font())
	else:
		_draw_cover(_bg_tex(lvl), photo, int(pic["roll"]))
		var fg := _fg_tex(lvl)
		if fg != null:
			# Fit the square subject inside the photo: never stretched.
			var side := minf(photo.size.x, photo.size.y) * 0.96
			var fr := Rect2(photo.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			draw_texture_rect(fg, fr, false)
		var st := photo.size.x * 0.2
		for i in 3:
			var sc2 := Vector2(photo.get_center().x + (i - 1) * st * 1.05, photo.end.y - st * 0.55 - (st * 0.1 if i == 1 else 0.0))
			GraffitiIcons.draw(self, "star" if i < int(rec["stars"]) else "star_empty", sc2, st)
	draw_rect(photo, GraffitiStyle.INK, false, 2.0)
	# A required ship type: a chip over the photo's top-right corner.
	var want := int(lvl["ship_type"])
	if want >= 0:
		var tname := ShipCatalog.type_name(want)
		var tfs := int(r.size.x * 0.1)
		var tw := GraffitiStyle.head_font().get_string_size(tname, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var chip := Rect2(Vector2(photo.end.x - tw - 12, photo.position.y - tfs * 0.4), Vector2(tw + 10, tfs * 1.3))
		GraffitiStyle.draw_slab(self, chip, ShipCatalog.type_color(want), 4.0, 2.0, Vector2(2, 2))
		GraffitiStyle.draw_text(self, tname, chip.get_center(), tfs, GraffitiStyle.INK, 0)
	var label_fs := int(r.size.x * 0.16)
	var label := "Level %d" % int(lvl["number"])
	var f := GraffitiStyle.number_font()
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x
	var ly := photo.end.y + (frame.end.y - photo.end.y) * 0.5 + label_fs * 0.35
	draw_string(f, Vector2(-lw * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs, GraffitiStyle.INK)
	if is_next:
		var tag := Rect2(Vector2(-half.x * 0.55, -half.y - label_fs * 1.5), Vector2(half.x * 1.1, label_fs * 1.3))
		GraffitiStyle.draw_slab(self, tag, GraffitiStyle.HOT, 8.0, 3.0, Vector2(3, 3))
		GraffitiStyle.draw_text(self, "NEXT!", tag.get_center(), label_fs, Color.WHITE, 4)
	draw_set_transform(_offset)


## One side of the fork: a road sign in the theme's colour.
func _draw_fork(c: Dictionary) -> void:
	var r: Rect2 = c["rect"]
	var theme := int(c["fork"])
	var col := LevelGen.THEME_COLORS[theme]
	draw_set_transform(_offset + r.get_center() + Vector2(0, sin(_t * 2.0 + theme) * 3.0), float(c["angle"]))
	var frame := Rect2(-r.size * 0.5, r.size)
	GraffitiStyle.draw_slab(self, frame, col, r.size.x * 0.12, 4.0, Vector2(7, 8))
	GraffitiStyle.draw_halftone(self, frame.grow(-8), col.lightened(0.2), 9.0, true, r.size.x * 0.12)
	var fs := int(r.size.x * 0.13)
	GraffitiStyle.draw_text(self, LevelGen.THEME_NAMES[theme], Vector2(0, -r.size.y * 0.12), fs, GraffitiStyle.INK, 0)
	var sub := "THEY HEARD OF YOU" if bool(c["styled"]) else "UNCHARTED"
	GraffitiStyle.draw_text(self, sub, Vector2(0, r.size.y * 0.16), int(fs * 0.62), Color.WHITE, 4)
	draw_set_transform(_offset)


func _draw_teaser(c: Dictionary) -> void:
	var r: Rect2 = c["rect"]
	draw_set_transform(_offset + r.get_center(), float(c["angle"]))
	var frame := Rect2(-r.size * 0.5, r.size)
	draw_rect(Rect2(frame.position + Vector2(6, 8), frame.size), Color(0, 0, 0, 0.35))
	draw_rect(frame, Color(0.95, 0.93, 0.88, 0.25))
	draw_rect(frame, GraffitiStyle.PAPER, false, 3.0)
	GraffitiStyle.draw_text(self, "???", Vector2(0, -r.size.y * 0.05), int(r.size.x * 0.3), GraffitiStyle.PAPER, 6)
	draw_set_transform(_offset)


## Draw [param tex] filling [param dst], cropped to keep its aspect — and
## remixed by [param roll]: zoomed in up to 1.5× and panned to a different
## part, so one baked picture makes many different photos. (Not mirrored: a
## negative rect draws the region beside the card, not flipped.)
func _draw_cover(tex: Texture2D, dst: Rect2, roll: int) -> void:
	if tex == null:
		draw_rect(dst, Color("201838"))
		return
	var ts := tex.get_size()
	var want := dst.size.x / dst.size.y
	var have := ts.x / maxf(ts.y, 1.0)
	var src := Rect2(Vector2.ZERO, ts)
	if have > want:
		src.size.x = ts.y * want
	else:
		src.size.y = ts.x / want
	var zoom := 1.0 + float(posmod(roll, 5)) * 0.12
	src.size /= zoom
	var slack := ts - src.size
	src.position = Vector2(slack.x * float(posmod(int(roll / 5.0), 7)) / 6.0, slack.y * float(posmod(int(roll / 35.0), 5)) / 4.0)
	# And graded: the same picture warm on one card, cold or toxic on another.
	draw_texture_rect_region(tex, dst, src, GRADES[posmod(int(roll / 175.0), GRADES.size())])


func _bg_tex(lvl: Dictionary) -> Texture2D:
	var key := String(lvl["key"])
	if not _tex.has(key):
		var pic: Dictionary = lvl["pic"]
		_tex[key] = PicSet.bg(String(pic["bg"]), int(pic["roll"]))
	return _tex[key]


func _fg_tex(lvl: Dictionary) -> Texture2D:
	var key := String(lvl["key"])
	if not _fg.has(key):
		var pic: Dictionary = lvl["pic"]
		_fg[key] = PicSet.fg(String(pic["fg"]), int(pic["roll"]))
	return _fg[key]
