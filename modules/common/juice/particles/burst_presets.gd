## Tuning tables for [ParticleBurst]'s six presets. One dictionary of constants
## per look, read once when a pool is built.
class_name BurstPresets
extends RefCounted

enum Preset { SPARKS, DEBRIS, EMBERS, VAPOUR, STREAKS, RING_SPARK }

## Live-particle ceiling across the whole layer at once. Phone gets a third of
## desktop, per the plan's cost budget — see `juice-and-more.md` §1.6.
const DESKTOP_CAPACITY := 512
const MOBILE_CAPACITY := 192


static func capacity() -> int:
	return MOBILE_CAPACITY if OS.has_feature("mobile") else DESKTOP_CAPACITY


## Per-preset pool size and per-particle behaviour. [code]count[/code] is how
## many particles one [method Juice.burst] call spawns; [code]additive[/code]
## picks the blend mode; [code]stretch[/code] scales the mesh along its travel
## speed, which is what makes [constant Preset.STREAKS] and [constant
## Preset.SPARKS] read as motion instead of dust.
static func config(preset: Preset) -> Dictionary:
	match preset:
		Preset.SPARKS:
			return {
				"pool": 128, "count": 12, "life": Vector2(0.3, 0.6), "size": Vector2(0.06, 0.16),
				"speed": Vector2(3.0, 8.0), "gravity": 0.0, "spin": 6.0,
				"color_from": Color(1.2, 1.1, 1.0), "color_to": Color("ffb347"),
				"additive": true, "stretch": 2.5,
			}
		Preset.DEBRIS:
			return {
				"pool": 96, "count": 10, "life": Vector2(1.5, 3.0), "size": Vector2(0.08, 0.22),
				"speed": Vector2(1.5, 5.0), "gravity": 0.4, "spin": 3.5,
				"color_from": Color("6b7280"), "color_to": Color("2c313a"),
				"additive": false, "stretch": 1.0,
			}
		Preset.EMBERS:
			return {
				"pool": 96, "count": 10, "life": Vector2(2.0, 4.0), "size": Vector2(0.04, 0.09),
				"speed": Vector2(0.3, 1.2), "gravity": -0.05, "spin": 1.0,
				"color_from": Color("ffcf8a"), "color_to": Color("ff5b2e"),
				"additive": true, "stretch": 1.0,
			}
		Preset.VAPOUR:
			return {
				"pool": 64, "count": 8, "life": Vector2(0.8, 1.6), "size": Vector2(0.3, 0.7),
				"speed": Vector2(0.4, 1.0), "gravity": 0.0, "spin": 0.5,
				"color_from": Color(0.5, 0.52, 0.56, 0.5), "color_to": Color(0.5, 0.52, 0.56, 0.0),
				"additive": false, "stretch": 1.0,
			}
		Preset.STREAKS:
			# One "particle" per call is deliberate: streaks are placed as a field by
			# their caller (see `juice-and-more.md` §1.4), not scattered from a point.
			return {
				"pool": 729, "count": 1, "life": Vector2(3.0, 3.0), "size": Vector2(0.05, 0.05),
				"speed": Vector2(0.0, 0.0), "gravity": 0.0, "spin": 0.0,
				"color_from": Color(0.34, 0.39, 0.50), "color_to": Color(0.34, 0.39, 0.50),
				"additive": false, "stretch": 1.0,
			}
		Preset.RING_SPARK:
			return {
				"pool": 48, "count": 16, "life": Vector2(0.3, 0.6), "size": Vector2(0.04, 0.08),
				"speed": Vector2(1.0, 3.0), "gravity": 0.0, "spin": 4.0,
				"color_from": Color.WHITE, "color_to": Color("39c0ff"),
				"additive": true, "stretch": 1.6,
			}
		_:
			return {}
