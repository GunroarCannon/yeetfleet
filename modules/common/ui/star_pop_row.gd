## StarPopRow: a level's three stars, revealed with some juice. All three
## sit there grey first; then, one by one, the stars earned pop in — a gold
## star slams down from oversize with a white flash, a ring of sparks and a
## little haptic tick, the middle one biggest.
##
## Timed on the wall clock, not game time: the end of a level often runs in
## slow motion or a kill-cam freeze, and the reveal must not stall with it.
class_name StarPopRow
extends Control

## Stars to reveal (0–3).
@export var count := 0
## Seconds before the first star, and between stars.
@export var delay := 0.35
@export var gap := 0.38

var _start_ms := 0
var _fired := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_ms = Time.get_ticks_msec()


## Start the reveal over (e.g. when the card is shown again).
func replay(n: int) -> void:
	count = n
	_fired = 0
	_start_ms = Time.get_ticks_msec()
	set_process(true)


func _process(_delta: float) -> void:
	var t := (Time.get_ticks_msec() - _start_ms) / 1000.0
	# A tick for each star as it lands.
	while _fired < count and t >= delay + _fired * gap:
		_fired += 1
		Juice.haptic(Juice.HapticKind.LIGHT)
		Juice.nudge(self, Vector2(0, 6))
	queue_redraw()
	if t > delay + count * gap + 1.0:
		set_process(false)


func _draw() -> void:
	var t := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var s := minf(size.y, size.x / 3.6)
	for i in 3:
		var big := 1.18 if i == 1 else 1.0
		var c := Vector2(size.x * 0.5 + (i - 1) * s * 1.15, size.y * 0.5 - (s * 0.12 if i == 1 else 0.0))
		GraffitiIcons.draw(self, "star_empty", c, s * big)
		if i >= count:
			continue
		var age := t - (delay + i * gap)
		if age < 0.0:
			continue
		# Slam: from 2.2x down past 1 and back (a back-out ease), with a flash.
		var k := clampf(age / 0.28, 0.0, 1.0)
		var scale := lerpf(2.2, 1.0, ease(k, 0.4)) + sin(k * PI) * 0.12
		GraffitiIcons.draw(self, "star", c, s * big * scale)
		var flash := 1.0 - clampf(age / 0.18, 0.0, 1.0)
		if flash > 0.0:
			draw_circle(c, s * 0.55 * big, Color(1, 1, 1, flash * 0.75))
		# Spark ring flying out and fading.
		var ring := clampf(age / 0.45, 0.0, 1.0)
		if ring < 1.0:
			for k2 in 8:
				var a := TAU * k2 / 8.0 + i
				var d0 := s * (0.45 + ring * 0.7)
				var d1 := d0 + s * 0.22 * (1.0 - ring)
				var col := GraffitiStyle.SUN
				col.a = 1.0 - ring
				draw_line(c + Vector2(cos(a), sin(a)) * d0, c + Vector2(cos(a), sin(a)) * d1, col, maxf(2.0, s * 0.06))
