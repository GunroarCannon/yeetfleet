## LoadingScreen: the card between the menu and a flight — the level's name
## sprayed big, a slim slanted progress bar with moving hazard stripes, and
## a one-line tip.
##
## The flight scene is loaded on a worker thread
## ([method ResourceLoader.load_threaded_request]) and the bar follows the
## real progress, eased so it only ever moves forward. Extra resources can
## ride along ([method start]'s [param extra]): the boot card after the
## splash loads the menu with its music, sounds and pictures this way
## ([method boot_paths]), and keeps them cached ([member kept]) so nothing
## hitches the first time it plays or shows. At 100% it holds a
## beat on "YEET!", swaps the scene in underneath itself and fades once the
## new scene has drawn a few frames.
class_name LoadingScreen
extends Control

## Frames the card stays over the new scene before it fades.
const HOLD_FRAMES := 14

## Short, no dashes: read in one glance.
const TIPS: Array[String] = [
	"DRAG YOUR SHIP TO SLING",
	"RAM FIRST, RAM HARD",
	"BOUNCE OFF PLANETS",
	"BE QUICK FOR GOLD",
	"KEEP YOUR HULL FOR STARS",
	"UPGRADE YEET TO RAM HARDER",
	"NEW SHIPS IN THE GARAGE",
]
## The tip on the first loading card ever (then [code]welcomed[/code] is set).
const WELCOME := "WELCOME TO THE UNION OF PEACE"
## Tags sprayed round the wall behind.
const TAGS: Array[String] = ["YEET", "BOOM", "ZAP", "POW", "FLEET", "WHAM", "GO"]

var _path := ""
var _title := ""
var _shown := 0.0
var _target := 0.0
var _done := false
var _t := 0.0
var _tip := ""
## Extra resources loading alongside the scene (see [method start]).
var _extra: Array[String] = []
## Frames the card stays over the new scene before it fades (a heavy scene,
## like the menu at boot, wants longer).
var hold_frames := HOLD_FRAMES
## Resources warmed by a loading card, held for the whole session so the
## cache keeps them.
static var kept: Array[Resource] = []
## The can's mist: a soft round falloff, drawn tinted under each splat.
static var _mist: Texture2D = null


## Start loading [param scene_path]; [param title] is the big line
## ("LEVEL 3 · RUSTY HEIST", or "SANDBOX").
func start(scene_path: String, title: String, extra: Array[String] = []) -> void:
	_path = scene_path
	_title = title
	_tip = TIPS[randi() % TIPS.size()]
	# The very first loading card a player ever sees greets them instead. (At
	# boot this runs before the menu starts the session: load it first, so
	# saving the flag can't write over the save with blanks.)
	Session.start()
	if not bool(Session.pref("welcomed", false)):
		_tip = WELCOME
		Session.prefs["welcomed"] = true
		Session.save_to_disk()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.load_threaded_request(_path) != OK:
		# Could not thread it: load in one go, the bar just jumps.
		_target = 1.0
	for p in extra:
		if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p, "", true) == OK:
			_extra.append(p)


## What the boot card warms before the menu: every menu and gameplay song,
## the menu's one-shots, the flight's sound library and the level-card
## pictures. Paths that are missing are skipped.
static func boot_paths() -> Array[String]:
	var out: Array[String] = []
	for playlist in ["main", "submenus", "garage", "gameplay"]:
		for t in GameAudio.tracks(playlist):
			if not t in out:
				out.append(t)
	for files: Array in GameAudio.UI.values():
		for f: String in files:
			if not f in out:
				out.append(f)
	for files: Array in Sfx.FILES.values():
		for f: String in files:
			var p := Sfx.DIR.path_join(f)
			if not p in out:
				out.append(p)
	for f in DirAccess.get_files_at(PicSet.DIR):
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension() == "webp" and not PicSet.DIR.path_join(name) in out:
			out.append(PicSet.DIR.path_join(name))
	return out


## 0..1: how far the extra resources have got, all together.
func _extra_progress() -> float:
	if _extra.is_empty():
		return 1.0
	var sum := 0.0
	for p in _extra:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			sum += float(prog[0]) if not prog.is_empty() else 0.0
		else:
			sum += 1.0
	return sum / _extra.size()


func _process(delta: float) -> void:
	_t += delta
	if _path != "" and not _done:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(_path, progress)
		var scene := 1.0
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			scene = float(progress[0]) if not progress.is_empty() else 0.0
		# Most of the wait is the scene (and whatever rides along); keep 10%
		# for building it.
		var extra := _extra_progress()
		var both := scene if _extra.is_empty() else scene * 0.6 + extra * 0.4
		if both >= 0.999:
			_target = 1.0
		else:
			_target = maxf(_target, both * 0.9)
	_shown = move_toward(_shown, _target, delta * 1.6)
	if not _done and _shown >= 0.999:
		_done = true
		_finish.call_deferred()
	queue_redraw()


func _finish() -> void:
	var tree := get_tree()
	await tree.create_timer(0.25).timeout
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_get_status(_path) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(_path) as PackedScene
	for p in _extra:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(p)
			if res != null:
				kept.append(res)
	_extra.clear()
	# The card stays up over the swap, on its own layer under the root: the
	# new scene builds and draws its first frames (and warms its blasts)
	# under it, instead of a bare grey window. Then it fades.
	var layer := CanvasLayer.new()
	layer.name = "LoadingCover"
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	reparent(layer, false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if packed != null:
		tree.change_scene_to_packed(packed)
	else:
		tree.change_scene_to_file(_path)
	for i in hold_frames:
		await tree.process_frame
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)


## A polygon's signed area (shoelace), pixels².
static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _mist_tex() -> Texture2D:
	if _mist == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_mist = t
	return _mist


func _draw() -> void:
	var vp := size
	var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
	draw_rect(Rect2(Vector2.ZERO, vp), Color("140a24"))
	var rng := RandomNumberGenerator.new()
	# Each level gets its own wall.
	rng.seed = hash(_title) if _title != "" else 5
	var bg := Color("140a24")
	# The wall: faint brick courses.
	var brick := Vector2(96.0, 40.0) * u
	var row := 0
	var y := 0.0
	while y < vp.y:
		var x := -brick.x * 0.5 * (row % 2)
		while x < vp.x:
			draw_rect(Rect2(Vector2(x, y), brick), Color(1, 1, 1, 0.025), false, 2.0)
			x += brick.x
		y += brick.y
		row += 1
	# Paint splats: the sprayed kind. A soft airbrushed halo where the can's
	# mist landed, an uneven blob with a wet highlight, drips run down and a
	# few flung drops. The blob is mixed into the wall, not see-through, so
	# where two meet the newer one covers the older.
	var cols := [GraffitiStyle.HOT, GraffitiStyle.VIOLET, GraffitiStyle.CYAN, GraffitiStyle.LIME, GraffitiStyle.SUN]
	for i in 10:
		var base: Color = cols[(i + rng.randi_range(0, 4)) % cols.size()]
		var c := bg.lerp(base, rng.randf_range(0.32, 0.5))
		var p := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var r0 := rng.randf_range(34, 90) * u
		var mist := base
		mist.a = 0.16
		draw_texture_rect(_mist_tex(), Rect2(p - Vector2.ONE * r0 * 1.9, Vector2.ONE * r0 * 3.8), false, mist)
		# An uneven edge: a few slow waves round the rim, no spikes.
		var ph: Array[float] = [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
		var amp: Array[float] = [rng.randf_range(0.06, 0.14), rng.randf_range(0.04, 0.1), rng.randf_range(0.02, 0.05)]
		var outline := PackedVector2Array()
		for k in 48:
			var a := TAU * k / 48.0
			var rr := r0 * (0.8 + amp[0] * sin(a * 2.0 + ph[0]) + amp[1] * sin(a * 3.0 + ph[1]) + amp[2] * sin(a * 7.0 + ph[2]))
			outline.append(p + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(outline, c)
		for k in rng.randi_range(1, 3):
			var dx := p.x + rng.randf_range(-0.5, 0.5) * r0
			var dl := rng.randf_range(0.6, 1.5) * r0
			var dw := rng.randf_range(5.0, 9.0) * u
			var top := p.y + r0 * 0.3
			# A drip narrows as it runs, and ends in a bead.
			draw_colored_polygon(PackedVector2Array([
				Vector2(dx - dw * 0.5, top), Vector2(dx + dw * 0.5, top),
				Vector2(dx + dw * 0.32, top + dl), Vector2(dx - dw * 0.32, top + dl),
			]), c)
			draw_circle(Vector2(dx, top + dl), dw * 0.55, c)
		# The wet sheen: a lighter smear toward the top-left.
		draw_circle(p + Vector2(-0.22, -0.26) * r0, r0 * 0.3, bg.lerp(base, 0.56))
		for k in rng.randi_range(3, 6):
			var a2 := rng.randf() * TAU
			draw_circle(p + Vector2(cos(a2), sin(a2)) * r0 * rng.randf_range(1.15, 1.8), rng.randf_range(2.5, 6.0) * u, c)
	# Throw-ups sprayed round the wall: fat letters, a dark outline, tilted.
	var tf := GraffitiStyle.title_font()
	for i in 7:
		var word: String = TAGS[rng.randi() % TAGS.size()]
		var at := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var c2: Color = bg.lerp(cols[(i + 2) % cols.size()], 0.38)
		draw_set_transform(at, rng.randf_range(-0.35, 0.35))
		var fs := int(rng.randf_range(44, 100) * u)
		draw_string_outline(tf, Vector2(5, 6) * u, word, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, int(fs * 0.2), bg.darkened(0.4))
		draw_string_outline(tf, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, int(fs * 0.2), bg.lerp(Color.WHITE, 0.12))
		draw_string(tf, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, c2)
	draw_set_transform(Vector2.ZERO)
	# The big word, letter by letter: each bounces on its own beat.
	var big := int(96 * u)
	var word2 := "YEET!" if _done else "LOADING"
	var ww := tf.get_string_size(word2, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var lx := (vp.x - ww) * 0.5
	for i in word2.length():
		var ch := word2.substr(i, 1)
		var cw := tf.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		var hop := absf(sin(_t * 5.0 - i * 0.55)) * 14.0 * u
		var c3: Color = [GraffitiStyle.LIME, GraffitiStyle.SUN, GraffitiStyle.HOT, GraffitiStyle.CYAN][i % 4]
		draw_set_transform(Vector2(lx + cw * 0.5, vp.y * 0.3 - hop), sin(i * 2.1) * 0.12)
		GraffitiStyle.draw_text(self, ch, Vector2.ZERO, big, c3, int(big * 0.16), tf)
		lx += cw
	draw_set_transform(Vector2.ZERO)
	# The level's name on a strip of tape, Orange Juice, a little crooked.
	if _title != "":
		var nf := GraffitiStyle.number_font()
		var ns := int(44 * u)
		var tw := nf.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
		var strip := Rect2(Vector2(-tw * 0.5 - 30.0 * u, -ns * 0.72), Vector2(tw + 60.0 * u, ns * 1.44))
		draw_set_transform(Vector2(vp.x * 0.5, vp.y * 0.47), -0.04)
		GraffitiStyle.draw_slab(self, strip, GraffitiStyle.HOT, 18.0 * u, 4.0, Vector2(6, 7))
		GraffitiStyle.draw_text(self, _title, Vector2.ZERO, ns, Color.WHITE, 8, nf)
		draw_set_transform(Vector2.ZERO)
	# The bar: a fat spray stroke on an ink slab, overspray off its front.
	var bw := minf(vp.x * 0.74, 720.0 * u)
	var bh := 34.0 * u
	var r := Rect2(Vector2((vp.x - bw) * 0.5, vp.y * 0.6), Vector2(bw, bh))
	GraffitiStyle.draw_slab(self, r, GraffitiStyle.INK, 16.0 * u, 4.0, Vector2(6, 7))
	var inner := r.grow(-5.0 * u)
	var fill_w := inner.size.x * _shown
	# Narrower than its slant, the slab folds over itself: wait for some fill.
	if fill_w > 20.0 * u:
		var fr := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		var pts := GraffitiStyle.slab_points(fr, 12.0 * u)
		draw_colored_polygon(pts, GraffitiStyle.LIME)
		# Diagonal stripes sliding along, clipped to the filled part.
		var stripe := 16.0 * u
		var off := fmod(_t * 70.0 * u, stripe * 2.0)
		var sx := fr.position.x - stripe * 2.0 + off
		while sx < fr.end.x:
			var band := PackedVector2Array([
				Vector2(sx, fr.end.y), Vector2(sx + stripe, fr.end.y),
				Vector2(sx + stripe + fr.size.y, fr.position.y), Vector2(sx + fr.size.y, fr.position.y),
			])
			for poly in Geometry2D.intersect_polygons(band, pts):
				# A clip at the bar's end can leave a sliver too thin to fill.
				if poly.size() >= 3 and absf(_area(poly)) > 1.0:
					draw_colored_polygon(poly, Color(0.1, 0.55, 0.2, 0.55))
			sx += stripe * 2.0
		# Overspray at the nozzle.
		var sp := RandomNumberGenerator.new()
		sp.seed = int(_t * 20.0)
		for k in 18:
			var p2 := Vector2(fr.end.x + sp.randf_range(-6.0, 26.0) * u, fr.position.y + sp.randf() * fr.size.y)
			var c4 := GraffitiStyle.LIME
			c4.a = sp.randf_range(0.3, 0.8)
			draw_circle(p2, sp.randf_range(1.0, 3.5) * u, c4)
	GraffitiStyle.draw_text(self, "%d%%" % roundi(_shown * 100.0), Vector2(r.end.x - 30.0 * u, r.position.y - 26.0 * u), int(34 * u), GraffitiStyle.SUN, 6, GraffitiStyle.number_font())
	# The tip on a sticker, in ka1.
	var kf := GraffitiStyle.tip_font()
	var ks := int(24 * u)
	var kw := kf.get_string_size(_tip, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
	var sticker := Rect2(Vector2(-kw * 0.5 - 22.0 * u, -ks * 0.85), Vector2(kw + 44.0 * u, ks * 1.7))
	draw_set_transform(Vector2(vp.x * 0.5, vp.y * 0.76), 0.03)
	GraffitiStyle.draw_slab(self, sticker, GraffitiStyle.SUN, 12.0 * u, 3.0, Vector2(5, 6))
	GraffitiStyle.draw_text(self, _tip, Vector2.ZERO, ks, GraffitiStyle.INK, 0, kf)
	draw_set_transform(Vector2.ZERO)
