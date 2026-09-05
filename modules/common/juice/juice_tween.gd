## Small, consistent motion helpers for UI feedback — a scale pop, a rejection
## nudge, a colour pulse, a rolling number — so every panel reaches for the same
## few numbers instead of inventing its own timing.
class_name JuiceTween
extends RefCounted

const POP_DURATION := 0.22
const NUDGE_DURATION := 0.18
const PULSE_DURATION := 0.16
const ROLL_DURATION := 0.4


## Scale punch that overshoots past 1.0 and settles — the placed-part, arrived
## feedback used across the builder.
static func pop(node: Control, amount := 0.12) -> void:
	if node == null or not node.is_inside_tree():
		return
	var base := node.scale
	node.scale = base * (1.0 - amount)
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, POP_DURATION)


## A short shove and return — the "no" feedback for a rejected drop.
static func nudge(node: Control, dir: Vector2) -> void:
	if node == null or not node.is_inside_tree():
		return
	var base := node.position
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", base + dir, NUDGE_DURATION * 0.4)
	tw.tween_property(node, "position", base, NUDGE_DURATION * 0.6)


## Flashes [param color] across [param node]'s modulate and back, [param times].
static func pulse(node: CanvasItem, color: Color, times := 1) -> void:
	if node == null or not node.is_inside_tree():
		return
	var base := node.modulate
	var tw := node.create_tween()
	for _i in times:
		tw.tween_property(node, "modulate", color, PULSE_DURATION * 0.5)
		tw.tween_property(node, "modulate", base, PULSE_DURATION * 0.5)


## Animates [param label]'s text from [param from] to [param to], formatted with
## [param fmt] (a `%`-style format string taking one float), over [param duration].
static func roll_number(
	label: Label, from: float, to: float, fmt: String, duration := ROLL_DURATION
) -> void:
	if label == null or not label.is_inside_tree():
		return
	label.text = fmt % from
	var tw := label.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(value: float) -> void: label.text = fmt % value, from, to, duration)
