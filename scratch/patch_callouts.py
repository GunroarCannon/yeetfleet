p = 'modules/flight/scripts/ui/player_callouts.gd'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b)


rep('''## Events that happen *to* the player — a part torn off, a power-up picked
## up, the shield bubble popping, the hull running low — come out of the
## ship as a slanted black slab with a red offset shadow and white text,
## hanging off a tail that points at the hull.''', '''## Events that happen *to* the player — a part torn off, a power-up picked
## up, the shield bubble popping, the hull running low — come out of the
## ship as a ransom-note shout: every letter cut out on its own tilted chip,
## white on ink and ink on white by turns, the first letter big, on an ink
## slab over a jagged burst of the callout's colour, hanging off a tail that
## points at the hull. Two short words at most ([constant MAX_WORDS]).''')
rep('''const MAX_SHOWN := 3''', '''const MAX_SHOWN := 3
## Callouts are shouts, not sentences: longer text is cut to this many words.
const MAX_WORDS := 2''')
rep('''	_last_text = text
	_last_ms = now
	_shown.append({"text": text.to_upper(), "col": col, "t": 0.0, "seed": randi()})''', '''	_last_text = text
	_last_ms = now
	_shown.append({"text": shorten(text), "col": col, "t": 0.0, "seed": randi()})''')
rep('''## How many are on screen (for checks).''', '''## [param text] as a shout: upper case, dashes and filler dropped, at most
## [constant MAX_WORDS] words (the "!" is kept).
static func shorten(text: String) -> String:
	var bang := text.ends_with("!")
	var words: Array[String] = []
	for w in text.to_upper().replace("—", " ").replace("-", " ").replace("!", "").split(" ", false):
		if w in ["THE", "A", "AN", "IS", "YOUR"]:
			continue
		words.append(w)
		if words.size() >= MAX_WORDS:
			break
	return " ".join(words) + ("!" if bang else "")


## How many are on screen (for checks).''')

i = s.index('func _draw_callout(')
j = s.index('## A slanted slab with slightly jagged corners')
s = s[:i] + '''func _draw_callout(c: Dictionary, at: Vector2, tail_to: Vector2, u: float, font: Font) -> void:
	var t := float(c["t"])
	var zoom := 1.0
	var alpha := 1.0
	if t < IN_TIME:
		var k := t / IN_TIME
		zoom = lerpf(1.7, 1.0, MobileHud._ease_back(k) if k < 1.0 else 1.0)
		alpha = k
	elif t > IN_TIME + HOLD_TIME:
		var k := clampf((t - IN_TIME - HOLD_TIME) / OUT_TIME, 0.0, 1.0)
		zoom = lerpf(1.0, 1.6, k * k)
		alpha = 1.0 - k
	if alpha <= 0.01:
		return
	var text := String(c["text"])
	var fs := maxi(roundi(u * 0.046 * MobileHudProfiles.style("size_title")), 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["seed"])
	# Lay the letters out first: each on its own chip, jittered.
	var chips: Array[Dictionary] = []
	var x := 0.0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == " ":
			x += fs * 0.45
			continue
		var big := 1.35 if i == 0 else rng.randf_range(0.88, 1.12)
		var cfs := int(fs * big)
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x + fs * 0.24
		chips.append({"ch": ch, "fs": cfs, "x": x, "w": cw, "tilt": rng.randf_range(-0.2, 0.2),
			"dy": rng.randf_range(-0.12, 0.12) * fs, "white": (i + int(c["seed"])) % 2 == 0})
		x += cw * 0.9
	var w := x + fs * 0.4
	var h := fs * 1.7
	var col: Color = c["col"]
	var ink := Color(0.03, 0.02, 0.05)
	# The tail first, under everything, from the slab to the ship.
	if tail_to != Vector2.INF and alpha > 0.2:
		var root_a := at + Vector2(-w * 0.2, h * 0.3)
		var root_b := at + Vector2(-w * 0.05, h * 0.3)
		var tip := at.lerp(tail_to, 0.75)
		draw_colored_polygon(PackedVector2Array([root_a, root_b, tip]), Color(col, alpha * 0.9))
		draw_colored_polygon(PackedVector2Array([root_a + Vector2(3, 0), root_b - Vector2(3, 0), tip.lerp(at, 0.08)]), Color(ink, alpha))
	draw_set_transform_matrix(Transform2D(deg_to_rad(-6.0), Vector2(zoom, zoom), 0.0, at))
	# A jagged burst of the callout's colour, bigger and tilted the other way.
	var burst := PackedVector2Array()
	var spikes := 14
	for k in spikes * 2:
		var a := TAU * k / (spikes * 2)
		var r := (1.0 if k % 2 == 0 else 0.78) * rng.randf_range(0.92, 1.08)
		burst.append(Vector2(cos(a) * (w * 0.62) * r, sin(a) * (h * 0.95) * r) + Vector2(u * 0.01, u * 0.012))
	draw_colored_polygon(burst, Color(col, alpha))
	# The ink slab with a white rim.
	var slab := _jag_quad(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h), int(c["seed"]), u)
	draw_colored_polygon(slab, Color(ink, alpha))
	var edge := slab.duplicate()
	edge.append(slab[0])
	draw_polyline(edge, Color(Color.WHITE, alpha), maxf(2.5, u * 0.006), true)
	# The letters, each on its chip.
	for chip in chips:
		var cx := -w * 0.5 + fs * 0.3 + float(chip["x"])
		var cfs := int(chip["fs"])
		var cw := float(chip["w"])
		var ch_h := cfs * 1.15
		var white := bool(chip["white"])
		var xf := Transform2D(deg_to_rad(-6.0), Vector2(zoom, zoom), 0.0, at) * Transform2D(float(chip["tilt"]), Vector2(cx + cw * 0.5, float(chip["dy"])))
		draw_set_transform_matrix(xf)
		var box := Rect2(Vector2(-cw * 0.5, -ch_h * 0.55), Vector2(cw, ch_h))
		draw_rect(box, Color(Color.WHITE if white else ink, alpha))
		if not white:
			draw_rect(box, Color(Color.WHITE, alpha), false, 2.0)
		var gw := font.get_string_size(String(chip["ch"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var pos := Vector2(-gw * 0.5, cfs * 0.34)
		draw_string(font, pos, String(chip["ch"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(ink if white else Color.WHITE, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)


''' + s[j:]
open(p, 'w', encoding='utf-8').write(s)

p = 'modules/flight/scripts/flight_root.gd'
s = open(p, encoding='utf-8').read()
rep('''		player_callout("%s — gone!" % broken.part_name)''', '''		# A shout, not a sentence: the part's first word ("WING LOST!").
		player_callout("%s LOST!" % String(broken.part_name).get_slice(" ", 0))''')
open(p, 'w', encoding='utf-8').write(s)

p = 'modules/flight/scripts/power_ups.gd'
s = open(p, encoding='utf-8').read()
rep('''"EMP — FREEZE!"''', '''"FREEZE!"''')
rep('''"POWER BOOST!"''', '''"BOOST!"''')
open(p, 'w', encoding='utf-8').write(s)
print("ok")
