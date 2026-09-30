## ReportPanel: the mission report — a sheet of paper that slides in from
## the right when a level card is tapped.
##
## Symbols and single words, no sentences: the level's photo clipped on, its
## name, what kind of job it is, danger skulls, tries / wins / stars / best
## time, the pay, and the ship that will fly it — the current ship, or a
## LOANER stamp when the level wants a type the player does not own. Tapping
## the ship (or GARAGE) picks another in the garage ([signal pick_ship]). FLY!
## launches; a tap outside the sheet closes it. Also shows the fork's
## "set course" card.
class_name ReportPanel
extends Control

signal fly(lvl: Dictionary)
signal choose_fork(theme: int)
## The ship box (or GARAGE) was tapped: pick the ship for [param lvl].
signal pick_ship(lvl: Dictionary)
signal closed

var _paper: _Paper
## Greys the map out while the sheet is up.
var _dim: ColorRect
var _fly: SlabButton
var _garage: SlabButton
var _open := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.05, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_paper = _Paper.new()
	add_child(_paper)
	_fly = SlabButton.new()
	_fly.fill = GraffitiStyle.HOT
	_fly.pressed.connect(_on_fly)
	_paper.add_child(_fly)
	_garage = SlabButton.new()
	_garage.text = "GARAGE"
	_garage.fill = GraffitiStyle.SUN
	_garage.text_color = GraffitiStyle.INK
	_garage.pressed.connect(func() -> void:
		if not _paper.lvl.is_empty():
			pick_ship.emit(_paper.lvl))
	_paper.add_child(_garage)
	_paper.ship_tapped.connect(func() -> void:
		if not _paper.lvl.is_empty():
			pick_ship.emit(_paper.lvl))
	resized.connect(_place)


func is_open() -> bool:
	return _open


## Show the report for a level.
func show_level(lvl: Dictionary) -> void:
	_paper.lvl = lvl
	_paper.fork = -1
	var locked := not Campaign.is_unlocked(lvl)
	_fly.text = "LOCKED" if locked else "FLY!"
	_fly.disabled = locked
	var pick := Campaign.ship_for(lvl)
	_garage.visible = bool(pick["loaner"])
	_slide_in()


## Show the fork choice for [param theme].
func show_fork(theme: int, styled: bool) -> void:
	_paper.lvl = {}
	_paper.fork = theme
	_paper.styled = styled
	_fly.text = "GO THIS WAY"
	_fly.disabled = false
	_garage.visible = false
	_slide_in()


func close() -> void:
	if not _open:
		return
	_open = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", size.x + 40.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_dim, "modulate:a", 0.0, 0.22)
	_tween.tween_callback(func() -> void:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE)
	closed.emit()


func _slide_in() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_place()
	_paper.queue_redraw()
	var rest := _paper.position.x
	if not _open:
		_paper.position.x = size.x + 40.0
		_dim.modulate.a = 0.0
	_open = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", rest, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_dim, "modulate:a", 1.0, 0.2)
	if not _fly.disabled:
		_fly.grab_focus.call_deferred()


func _place() -> void:
	var port := size.y > size.x
	var u := maxf(minf(size.x, size.y) / 720.0, 0.5)
	var w := clampf(size.x * (0.94 if port else 0.4), 300.0, 520.0 * u)
	# Below the top bar, so the back slab and the wallet stay visible.
	var top := clampf(size.y * 0.11, 58.0, 92.0 * u) + 16.0
	# Never taller than the screen: a phone in landscape can be ~430 tall.
	var h := clampf(size.y - top - 12.0, minf(300.0, size.y - top - 8.0), 760.0 * u)
	_paper.size = Vector2(w, h)
	_paper.position = Vector2(size.x - w - (size.x - w) * (0.5 if port else 0.0) - (0.0 if port else 24.0), top)
	_paper.pivot_offset = _paper.size * 0.5
	_paper.rotation = -0.02
	var bh := ReportPanel.fly_height(h, u)
	_fly.size = Vector2(w * 0.56, bh)
	_fly.custom_minimum_size = _fly.size
	_fly.font_size = int(bh * 0.46)
	_fly.position = Vector2(w - _fly.size.x - 28, h - bh - 26)
	_garage.size = Vector2(w * 0.32, bh * 0.8)
	_garage.custom_minimum_size = _garage.size
	_garage.font_size = int(bh * 0.3)
	_garage.position = Vector2(24, h - bh - 18)


## The FLY slab's height on a pad [param h] tall (the pad's rows are laid
## out above it).
static func fly_height(h: float, u: float) -> float:
	return clampf(h * 0.11, 44.0, 80.0 * u)


func _gui_input(event: InputEvent) -> void:
	# A tap anywhere off the paper closes the report.
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _paper.get_global_rect().has_point(mb.global_position):
			close()
			accept_event()


func _on_fly() -> void:
	if _paper.fork >= 0:
		choose_fork.emit(_paper.fork)
	elif not _paper.lvl.is_empty():
		fly.emit(_paper.lvl)


## The sheet itself: drawn by hand, the buttons are its children.
class _Paper:
	extends Control
	signal ship_tapped
	var lvl := {}
	var fork := -1
	var styled := false
	## Where the ship box was drawn (a tap there picks another ship).
	var ship_rect := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
				and fork < 0 and not lvl.is_empty() and ship_rect.has_point(mb.position):
			accept_event()
			ship_tapped.emit()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2(8, 10), size), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(Vector2.ZERO, size), GraffitiStyle.PAPER)
		# Faint ruled lines and a red margin: a report pad.
		var y := h * 0.3
		while y < h - 20:
			draw_line(Vector2(14, y), Vector2(w - 14, y), Color(0.35, 0.55, 0.85, 0.18), 1.5)
			y += 28.0
		draw_line(Vector2(w * 0.08, 0), Vector2(w * 0.08, h), Color(0.9, 0.3, 0.35, 0.35), 2.0)
		# Tape on the top corners.
		for tx in [w * 0.12, w * 0.8]:
			draw_set_transform(Vector2(tx, 4), 0.25 if tx < w * 0.5 else -0.3)
			draw_rect(Rect2(-36, -12, 72, 24), Color(1.0, 0.93, 0.55, 0.7))
			draw_set_transform(Vector2.ZERO)
		if fork >= 0:
			_draw_fork(w, h)
		elif not lvl.is_empty():
			_draw_level(w, h)

	func _draw_level(w: float, h: float) -> void:
		var f := GraffitiStyle.head_font()
		var ink := GraffitiStyle.INK
		var rec := Campaign.record(String(lvl["key"]))
		var theme := int(lvl["theme"])
		var tcol := LevelGen.THEME_COLORS[theme]
		# The photo, clipped on at a tilt.
		# On a short pad (a phone in landscape) the photo and name shrink so the
		# rows keep their room.
		var ph_h := minf(w * 0.3, h * 0.22)
		var ph := Rect2(Vector2(w * 0.1, h * 0.05), Vector2(ph_h * 4.0 / 3.0, ph_h))
		draw_set_transform(ph.get_center(), -0.06)
		var pr := Rect2(-ph.size * 0.5, ph.size)
		draw_rect(pr.grow(8), Color.WHITE)
		draw_rect(pr.grow(8), Color(0, 0, 0, 0.2), false, 2.0)
		var pic: Dictionary = lvl["pic"]
		var bg := PicSet.bg(String(pic["bg"]), int(pic["roll"]))
		if bg != null:
			var ts := bg.get_size()
			var want := pr.size.x / pr.size.y
			var src := Rect2(Vector2.ZERO, ts)
			if ts.x / ts.y > want:
				src.size.x = ts.y * want
				src.position.x = (ts.x - src.size.x) * 0.5
			else:
				src.size.y = ts.x / want
				src.position.y = (ts.y - src.size.y) * 0.5
			draw_texture_rect_region(bg, pr, src)
		var fg := PicSet.fg(String(pic["fg"]), int(pic["roll"]))
		if fg != null:
			var side := minf(pr.size.x, pr.size.y)
			draw_texture_rect(fg, Rect2(pr.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		draw_set_transform(Vector2.ZERO)
		# LEVEL N stamp, rotated, in the theme colour.
		var stamp_fs := int(w * 0.07)
		draw_set_transform(Vector2(w * 0.76, h * 0.11), 0.18)
		var nf := GraffitiStyle.number_font()
		var sw := nf.get_string_size("LEVEL %d" % int(lvl["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_fs).x
		draw_rect(Rect2(-sw * 0.5 - 10, -stamp_fs * 0.9, sw + 20, stamp_fs * 1.3), tcol.darkened(0.2), false, 4.0)
		draw_string(nf, Vector2(-sw * 0.5, stamp_fs * 0.2), "LEVEL %d" % int(lvl["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_fs, tcol.darkened(0.2))
		draw_set_transform(Vector2.ZERO)
		# Name in Orange Juice (the game's face for level names and numbers).
		var tf := GraffitiStyle.number_font()
		var title_fs := int(minf(w * 0.095, h * 0.075))
		var ty := h * 0.05 + ph_h + title_fs + 16
		draw_string_outline(tf, Vector2(w * 0.1, ty), String(lvl["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w * 0.86, title_fs, 8, ink)
		draw_string(tf, Vector2(w * 0.1, ty), String(lvl["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w * 0.86, title_fs, tcol)
		# The ship box sits on top of the FLY slab; the rows share what is
		# left between the name and it.
		var u := maxf(minf(get_viewport_rect().size.x, get_viewport_rect().size.y) / 720.0, 0.5)
		var box_h := clampf(h * 0.15, 48.0, 110.0 * u)
		var box_y := h - ReportPanel.fly_height(h, u) - 30.0 - box_h - 12.0
		var fs := int(clampf(minf(w * 0.05, (box_y - ty) / 8.6), 12.0, 30.0))
		var row_h := (box_y - ty) / 4.6
		var y := ty + row_h * 0.95
		var x0 := w * 0.12
		var x1 := w * 0.5
		var dimc := GraffitiStyle.DIM.darkened(0.3)
		var lab := int(fs * 0.8)
		# Job + danger, as words.
		draw_string(f, Vector2(x0, y), String(lvl["word"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol.darkened(0.25))
		var danger: String = ["EASY", "OK", "HARD", "NASTY", "INSANE"][clampi(int(lvl["danger"]) - 1, 0, 4)]
		draw_string(f, Vector2(x1, y), danger, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GraffitiStyle.HOT)
		y += row_h
		# Tries · wins.
		draw_string(f, Vector2(x0, y), "TRIES", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(nf, Vector2(x0 + fs * 3.2, y), str(int(rec["attempts"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		draw_string(f, Vector2(x1, y), "WINS", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(nf, Vector2(x1 + fs * 2.8, y), str(int(rec["wins"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		y += row_h
		# Stars · best.
		for i in 3:
			GraffitiIcons.draw(self, "star" if i < int(rec["stars"]) else "star_empty", Vector2(x0 + fs * 0.6 + i * fs * 1.35, y - fs * 0.35), fs * 1.2)
		var best := float(rec["best"])
		draw_string(f, Vector2(x1, y), "BEST", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(nf, Vector2(x1 + fs * 2.8, y), _clock(best) if best > 0.0 else "--", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		y += row_h
		# Par · pay.
		draw_string(f, Vector2(x0, y), "PAR", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(nf, Vector2(x0 + fs * 2.4, y), _clock(float(lvl["par"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var pay := int(lvl["reward"]) if int(rec["wins"]) == 0 else int(float(lvl["reward"]) * Campaign.REPLAY_PAY)
		GraffitiIcons.draw(self, "coin", Vector2(x1 + fs * 0.5, y - fs * 0.35), fs)
		draw_string(nf, Vector2(x1 + fs * 1.3, y), "+%d" % pay, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		# The ship.
		var pick := Campaign.ship_for(lvl)
		var id := String(pick["id"])
		var sbox := Rect2(Vector2(x0 - 6, box_y), Vector2(w * 0.8, box_h))
		ship_rect = sbox
		draw_rect(sbox, Color(0.08, 0.06, 0.14, 0.9))
		# It's a button: a SWAP tab on its right edge.
		var tab_fs := int(fs * 0.7)
		var tab_w := f.get_string_size("SWAP", HORIZONTAL_ALIGNMENT_LEFT, -1, tab_fs).x + 18.0
		var tab := Rect2(Vector2(sbox.end.x - tab_w * 0.4, sbox.position.y + sbox.size.y * 0.5 - tab_fs), Vector2(tab_w, tab_fs * 2.0))
		GraffitiStyle.draw_slab(self, tab, GraffitiStyle.CYAN, 5.0, 2.0, Vector2(3, 3))
		GraffitiStyle.draw_text(self, "SWAP", tab.get_center(), tab_fs, GraffitiStyle.INK, 0)
		var port := PicSet.ship(id)
		var pbox := Rect2(sbox.position + Vector2(6, 4), Vector2(sbox.size.y * 1.35, sbox.size.y - 8))
		if port != null:
			draw_texture_rect(port, pbox, false)
		var nfs := int(fs * 0.95)
		var nx := pbox.end.x + 10
		draw_string(f, Vector2(nx, sbox.position.y + sbox.size.y * 0.42), String(ShipCatalog.get_ship(id).get("name", id)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color.WHITE)
		var t := ShipCatalog.type_of(id)
		var tname := ShipCatalog.type_name(t)
		var tw := f.get_string_size(tname, HORIZONTAL_ALIGNMENT_LEFT, -1, int(nfs * 0.7)).x
		var chip := Rect2(Vector2(nx, sbox.position.y + sbox.size.y * 0.56), Vector2(tw + 14, nfs * 0.95))
		GraffitiStyle.draw_slab(self, chip, ShipCatalog.type_color(t), 4.0, 2.0, Vector2.ZERO)
		GraffitiStyle.draw_text(self, tname, chip.get_center(), int(nfs * 0.7), ink, 0)
		if int(lvl["ship_type"]) >= 0:
			var need := "NEEDS " + ShipCatalog.type_name(int(lvl["ship_type"]))
			draw_string(f, Vector2(chip.end.x + 12, chip.get_center().y + nfs * 0.25), need, HORIZONTAL_ALIGNMENT_LEFT, -1, int(nfs * 0.7), GraffitiStyle.SUN)
		if bool(pick["loaner"]):
			draw_set_transform(sbox.end - Vector2(w * 0.14, sbox.size.y * 0.55), -0.22)
			var lfs := int(fs * 1.05)
			var lw := f.get_string_size("LOANER", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
			draw_rect(Rect2(-lw * 0.5 - 8, -lfs * 0.85, lw + 16, lfs * 1.25), GraffitiStyle.HOT, false, 4.0)
			draw_string(f, Vector2(-lw * 0.5, lfs * 0.2), "LOANER", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, GraffitiStyle.HOT)
			draw_set_transform(Vector2.ZERO)

	func _draw_fork(w: float, h: float) -> void:
		var f := GraffitiStyle.head_font()
		var col := LevelGen.THEME_COLORS[fork]
		var tf := GraffitiStyle.title_font()
		var fs := int(minf(w * 0.1, h * 0.09))
		draw_string_outline(tf, Vector2(w * 0.1, h * 0.2), LevelGen.THEME_NAMES[fork], HORIZONTAL_ALIGNMENT_LEFT, w * 0.85, fs, 8, GraffitiStyle.INK)
		draw_string(tf, Vector2(w * 0.1, h * 0.2), LevelGen.THEME_NAMES[fork], HORIZONTAL_ALIGNMENT_LEFT, w * 0.85, fs, col)
		# The list shares what is left above the button (a short pad squeezes it).
		var kinds: Dictionary = LevelGen.THEME_KINDS[fork]
		var list_end := h - ReportPanel.fly_height(h, 1.0) - 44.0
		var sfs := int(clampf(minf(w * 0.05, (list_end - h * 0.36) / (kinds.size() * 1.8 + 1.6)), 10.0, 40.0))
		var why := ("YOU PLAY " + Campaign.style_word()) if styled else "UNCHARTED"
		draw_string(f, Vector2(w * 0.12, h * 0.3), why, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, GraffitiStyle.INK)
		# What the sector holds: the kinds of job, as words.
		var y := h * 0.36 + sfs * 1.4
		for k in kinds:
			var info: Dictionary = LevelGen.KIND_INFO[k]
			draw_string(f, Vector2(w * 0.14, y), String(info["word"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, GraffitiStyle.INK)
			y += sfs * 1.8
		draw_string(f, Vector2(w * 0.12, minf(h * 0.8, y + sfs * 0.4)), "NO WAY BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, int(sfs * 0.8), GraffitiStyle.HOT)

	static func _clock(sec: float) -> String:
		var s := roundi(sec)
		return "%d:%02d" % [int(s / 60.0), s % 60]
