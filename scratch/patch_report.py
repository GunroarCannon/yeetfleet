p = 'modules/menu/scripts/ui/report_panel.gd'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b)


# Dim the map behind the sheet.
rep('''var _paper: _Paper
''', '''var _paper: _Paper
## Greys the map out while the sheet is up.
var _dim: ColorRect
''')
rep('''	visible = false
	_paper = _Paper.new()''', '''	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.05, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_paper = _Paper.new()''')
rep('''	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", size.x + 40.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)''', '''	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", size.x + 40.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_dim, "modulate:a", 0.0, 0.22)''')
rep('''	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", rest, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)''', '''	_tween = create_tween()
	_tween.tween_property(_paper, "position:x", rest, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_dim, "modulate:a", 1.0, 0.2)''')
rep('''	if not _open:
		_paper.position.x = size.x + 40.0''', '''	if not _open:
		_paper.position.x = size.x + 40.0
		_dim.modulate.a = 0.0''')

# The photo: cropped to fit, subject contained.
rep('''		var pic: Dictionary = lvl["pic"]
		var bg := PicSet.bg(String(pic["bg"]), int(pic["roll"]))
		if bg != null:
			draw_texture_rect(bg, pr, false)
		var fg := PicSet.fg(String(pic["fg"]), int(pic["roll"]))
		if fg != null:
			draw_texture_rect(fg, pr, false)''', '''		var pic: Dictionary = lvl["pic"]
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
			draw_texture_rect(fg, Rect2(pr.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), false)''')

# Rows: words and numbers; the only pictures are the 3D stars and coin.
i = s.index('		# Job + danger.')
j = s.index('		# The ship.')
s = s[:i] + '''		var dimc := GraffitiStyle.DIM.darkened(0.3)
		var lab := int(fs * 0.8)
		# Job + danger, as words.
		draw_string(f, Vector2(x0, y), String(lvl["word"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol.darkened(0.25))
		var danger: String = ["EASY", "OK", "HARD", "NASTY", "INSANE"][clampi(int(lvl["danger"]) - 1, 0, 4)]
		draw_string(f, Vector2(x1, y), danger, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GraffitiStyle.HOT)
		y += row_h
		# Tries · wins.
		draw_string(f, Vector2(x0, y), "TRIES", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(f, Vector2(x0 + fs * 3.2, y), str(int(rec["attempts"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		draw_string(f, Vector2(x1, y), "WINS", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(f, Vector2(x1 + fs * 2.8, y), str(int(rec["wins"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		y += row_h
		# Stars · best.
		for i in 3:
			GraffitiIcons.draw(self, "star" if i < int(rec["stars"]) else "star_empty", Vector2(x0 + fs * 0.6 + i * fs * 1.35, y - fs * 0.35), fs * 1.2)
		var best := float(rec["best"])
		draw_string(f, Vector2(x1, y), "BEST", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(f, Vector2(x1 + fs * 2.8, y), _clock(best) if best > 0.0 else "--", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		y += row_h
		# Par · pay.
		draw_string(f, Vector2(x0, y), "PAR", HORIZONTAL_ALIGNMENT_LEFT, -1, lab, dimc)
		draw_string(f, Vector2(x0 + fs * 2.4, y), _clock(float(lvl["par"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var pay := int(lvl["reward"]) if int(rec["wins"]) == 0 else int(float(lvl["reward"]) * Campaign.REPLAY_PAY)
		GraffitiIcons.draw(self, "coin", Vector2(x1 + fs * 0.5, y - fs * 0.35), fs)
		draw_string(f, Vector2(x1 + fs * 1.3, y), "+%d" % pay, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
''' + s[j:]
rep('''		else:
			GraffitiIcons.draw(self, "ship", pbox.get_center(), pbox.size.y * 0.7, ShipCatalog.type_color(ShipCatalog.type_of(id)))
''', '')
rep('''			GraffitiIcons.draw(self, String(info["icon"]), Vector2(w * 0.16, y - sfs * 0.35), sfs * 1.1, col)
			draw_string(f, Vector2(w * 0.24, y), String(info["word"])''', '''			draw_string(f, Vector2(w * 0.14, y), String(info["word"])''')
open(p, 'w', encoding='utf-8').write(s)

# Wallet: name, total stars, coins. No badge.
p = 'modules/menu/scripts/ui/wallet_chip.gd'
s = open(p, encoding='utf-8').read()
i = s.index('func _draw() -> void:')
s = s[:i] + '''func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	GraffitiStyle.draw_slab(self, r, Color.WHITE, 8.0, 3.0, Vector2(4, 5))
	var h := size.y
	var pad := h * 0.14
	# Three boxes: the pilot's name, stars earned, coins.
	var widths := [0.46, 0.24, 0.30]
	var x := pad + 4.0
	var boxes: Array[Rect2] = []
	for wf in widths:
		var bw := (size.x - pad * 2.0 - 16.0) * float(wf)
		boxes.append(Rect2(Vector2(x, pad), Vector2(bw - 6.0, h - pad * 2)))
		x += bw
	for b in boxes:
		draw_rect(b, Color("f1eee6"))
		draw_rect(b, GraffitiStyle.INK, false, 2.0)
	var fs := int(h * 0.36)
	# A long name shrinks to fit its box rather than spilling out.
	var name := Campaign.pilot_name()
	var nfs := fs
	var f := GraffitiStyle.head_font()
	while nfs > 8 and f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > boxes[0].size.x - 10.0:
		nfs -= 1
	GraffitiStyle.draw_text(self, name, boxes[0].get_center(), nfs, GraffitiStyle.INK, 0)
	GraffitiIcons.draw(self, "star", boxes[1].position + Vector2(h * 0.28, boxes[1].size.y * 0.5), h * 0.42)
	GraffitiStyle.draw_text(self, str(Campaign.total_stars()), boxes[1].get_center() + Vector2(h * 0.22, 0), fs, GraffitiStyle.INK, 0)
	GraffitiIcons.draw(self, "coin", boxes[2].position + Vector2(h * 0.28, boxes[2].size.y * 0.5), h * 0.42)
	var col := GraffitiStyle.INK.lerp(GraffitiStyle.LIME.darkened(0.3), _flash)
	GraffitiStyle.draw_text(self, str(int(round(_shown))), boxes[2].get_center() + Vector2(h * 0.22, 0), fs, col, 0)
'''
open(p, 'w', encoding='utf-8').write(s)
print("ok")
