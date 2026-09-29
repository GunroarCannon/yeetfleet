## WalletChip: the pilot's name and coins on a white card with ink boxes —
## the reference map's top-right strip. Rolls the number when coins change.
class_name WalletChip
extends Control

var _shown := -1.0
var _target := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Campaign.notifier.changed.connect(_refresh)
	_refresh()
	_shown = _target


func _refresh() -> void:
	var before := _target
	_target = float(Campaign.coins())
	if _shown >= 0.0 and _target != before:
		_flash = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if absf(_shown - _target) > 0.5 or _flash > 0.0:
		_shown = move_toward(_shown, _target, maxf(absf(_target - _shown) * 5.0, 30.0) * delta)
		_flash = maxf(_flash - delta * 1.5, 0.0)
		queue_redraw()


func _draw() -> void:
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
