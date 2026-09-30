## BigNotice: the moment-stopping headline — a power-up grabbed, a planet
## wrecked. A slanted band of colour slams across the middle of the screen,
## a huge graffiti word lands on it with a smaller line under, it holds, and
## the band whips off the other way.
##
## Its own [CanvasLayer] over both HUD layouts. Runs on real time: it is
## usually shown during a freeze, which is the point — the game stops, the
## word says why. Fed through [method FlightRoot.big_notice].
class_name BigNotice
extends CanvasLayer

const IN_TIME := 0.22
const OUT_TIME := 0.25

var _root_ctl: _Band


func _ready() -> void:
	layer = 18
	_root_ctl = _Band.new()
	_root_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctl)


## Show [param word] (and [param sub] under it) on a [param col] band for
## [param hold] seconds. A new notice replaces the one showing.
func show_notice(word: String, sub: String, col: Color, hold := 1.2) -> void:
	_root_ctl.word = word.to_upper()
	_root_ctl.sub = sub.to_upper()
	_root_ctl.col = col
	_root_ctl.hold = hold
	_root_ctl.start_ms = Time.get_ticks_msec()
	_root_ctl.set_process(true)


class _Band:
	extends Control
	var word := ""
	var sub := ""
	var col := Color.WHITE
	var hold := 1.2
	var start_ms := -1

	func _ready() -> void:
		set_process(false)

	func _process(_delta: float) -> void:
		queue_redraw()
		if _t() > IN_TIME + hold + OUT_TIME:
			start_ms = -1
			set_process(false)
			queue_redraw()

	func _t() -> float:
		return (Time.get_ticks_msec() - start_ms) / 1000.0

	func _draw() -> void:
		if start_ms < 0:
			return
		var t := _t()
		var vp := size
		var u := maxf(minf(vp.x, vp.y) / 720.0, 0.5)
		# Slide: in from the left, hold, off to the right.
		var slide := 0.0
		if t < IN_TIME:
			slide = -1.0 + ease(t / IN_TIME, 0.3)
		elif t > IN_TIME + hold:
			slide = ease(clampf((t - IN_TIME - hold) / OUT_TIME, 0.0, 1.0), 2.5)
		var dx := slide * vp.x * 1.3
		var cy := vp.y * 0.42
		# A slim band, see-through inside: the fight stays readable under it.
		var bh := 112.0 * u
		var lean := bh * 0.5
		var band := PackedVector2Array([
			Vector2(-lean + dx, cy - bh * 0.5), Vector2(vp.x + lean + dx, cy - bh * 0.62),
			Vector2(vp.x + dx, cy + bh * 0.5), Vector2(-lean * 2.0 + dx, cy + bh * 0.62),
		])
		var shadow := PackedVector2Array()
		for p in band:
			shadow.append(p + Vector2(10, 14) * u)
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
		draw_colored_polygon(band, col)
		var inner := PackedVector2Array([
			band[0].lerp(band[3], 0.12), band[1].lerp(band[2], 0.12),
			band[2].lerp(band[1], 0.12), band[3].lerp(band[0], 0.12),
		])
		draw_colored_polygon(inner, Color(col.darkened(0.6), 0.45))
		# The word lands a beat after the band, from oversize.
		var wk := clampf((t - IN_TIME * 0.6) / 0.2, 0.0, 1.0)
		if wk <= 0.0:
			return
		var zoom := lerpf(1.8, 1.0, ease(wk, 0.4))
		var tf := GraffitiStyle.title_font()
		var fs := int(80.0 * u * zoom)
		GraffitiStyle.draw_text(self, word, Vector2(vp.x * 0.5 + dx, cy - bh * 0.06), fs, col.lightened(0.35), int(fs * 0.14), tf)
		if sub != "":
			GraffitiStyle.draw_text(self, sub, Vector2(vp.x * 0.5 + dx, cy + bh * 0.36), int(30.0 * u), Color.WHITE, 6)
