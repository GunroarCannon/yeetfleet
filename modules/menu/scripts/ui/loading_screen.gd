## LoadingScreen: the card between the menu and a flight — the level's name
## sprayed big, a chunky slanted progress bar with moving hazard stripes, and
## a one-line tip.
##
## The flight scene is loaded on a worker thread
## ([method ResourceLoader.load_threaded_request]) and the bar follows the
## real progress, eased so it only ever moves forward. At 100% it holds a
## beat on "YEET!" and swaps the scene in.
class_name LoadingScreen
extends Control

const TIPS: Array[String] = [
	"DRAG FROM YOUR SHIP TO SLING IT",
	"RAM THEM FASTER THAN THEY RAM YOU",
	"PLANETS BOUNCE YOU — USE THEM",
	"GOLD STAR: FINISH UNDER PAR TIME",
	"HALF A HULL LEFT = ONE MORE STAR",
	"UPGRADE YEET TO HIT HARDER BY RAMMING",
	"A LEVEL WANTS A SHIP TYPE? THE GARAGE HAS IT",
]

var _path := ""
var _title := ""
var _shown := 0.0
var _target := 0.0
var _done := false
var _t := 0.0
var _tip := ""


## Start loading [param scene_path]; [param title] is the big line
## ("LEVEL 3 · RUSTY HEIST", or "SANDBOX").
func start(scene_path: String, title: String) -> void:
	_path = scene_path
	_title = title
	_tip = TIPS[randi() % TIPS.size()]
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.load_threaded_request(_path) != OK:
		# Could not thread it: load in one go, the bar just jumps.
		_target = 1.0


func _process(delta: float) -> void:
	_t += delta
	if _path != "" and not _done:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_target = 1.0
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not progress.is_empty():
			# Most of the wait is the scene resource; keep 10% for building it.
			_target = maxf(_target, float(progress[0]) * 0.9)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_target = 1.0
	_shown = move_toward(_shown, _target, delta * 1.6)
	if not _done and _shown >= 0.999:
		_done = true
		_finish.call_deferred()
	queue_redraw()


func _finish() -> void:
	await get_tree().create_timer(0.25).timeout
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_get_status(_path) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(_path) as PackedScene
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(_path)


func _draw() -> void:
	var vp := size
	var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.02, 0.1, 0.94))
	# Paint splats behind.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 18:
		var c := GraffitiStyle.HOT if i % 3 else GraffitiStyle.VIOLET
		c.a = 0.12
		draw_circle(Vector2(rng.randf() * vp.x, rng.randf() * vp.y * 0.7), rng.randf_range(40, 160) * u, c)
	var tf := GraffitiStyle.title_font()
	var big := int(84 * u)
	var word := "YEET!" if _done else "LOADING"
	GraffitiStyle.draw_text(self, word, Vector2(vp.x * 0.5, vp.y * 0.34), big, GraffitiStyle.LIME, int(big * 0.16), tf)
	if _title != "":
		GraffitiStyle.draw_text(self, _title, Vector2(vp.x * 0.5, vp.y * 0.47), int(34 * u), Color.WHITE, 6)
	# The bar: an ink slab, filled with sliding hazard stripes.
	var bw := minf(vp.x * 0.8, 820.0 * u)
	var bh := 54.0 * u
	var r := Rect2(Vector2((vp.x - bw) * 0.5, vp.y * 0.58), Vector2(bw, bh))
	GraffitiStyle.draw_slab(self, r, GraffitiStyle.INK, 26.0 * u, 5.0, Vector2(8, 9))
	var inner := r.grow(-9.0 * u)
	var fill_w := inner.size.x * _shown
	if fill_w > 2.0:
		var fr := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		var pts := GraffitiStyle.slab_points(fr, 18.0 * u)
		draw_colored_polygon(pts, GraffitiStyle.SUN)
		# Diagonal ink stripes sliding along, clipped to the filled part.
		var stripe := 28.0 * u
		var off := fmod(_t * 60.0 * u, stripe * 2.0)
		var x := fr.position.x - stripe * 2.0 + off
		while x < fr.end.x:
			var band := PackedVector2Array([
				Vector2(x, fr.end.y), Vector2(x + stripe, fr.end.y),
				Vector2(x + stripe + fr.size.y, fr.position.y), Vector2(x + fr.size.y, fr.position.y),
			])
			var clipped := Geometry2D.intersect_polygons(band, pts)
			for poly in clipped:
				draw_colored_polygon(poly, Color(0.1, 0.07, 0.14, 0.85))
			x += stripe * 2.0
	GraffitiStyle.draw_text(self, "%d%%" % roundi(_shown * 100.0), Vector2(r.end.x - 60.0 * u, r.position.y - 24.0 * u), int(28 * u), GraffitiStyle.SUN, 5)
	GraffitiStyle.draw_text(self, "TIP: " + _tip, Vector2(vp.x * 0.5, vp.y * 0.75), int(24 * u), GraffitiStyle.PAPER, 5)
