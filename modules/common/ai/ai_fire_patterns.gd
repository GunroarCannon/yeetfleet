## Bullet-hell firing styles for AI ships.
##
## A weapon says *what* a gun shoots (a bolt, a beam, a missile); a pattern
## says *how* a particular ship uses it — a steady stream, short bursts, slow
## fans the player weaves through, big lazy orbs, a turning spiral, a patient
## sniper. Every AI ship rolls one at spawn, plus its own cadence, so a fight
## is a mix of rhythms instead of every gun chattering at its weapon's flat rate.
##
## A pattern is a plain [Dictionary] so [SystemsSim] (ship_builder) can read it
## without depending on this module; the keys it reads are documented on
## [method make]. Gated by [member JuiceSettings.ai_fire_patterns].
class_name AiFirePatterns
extends RefCounted

## The catalogue, in roll order. Weights are relative.
const STYLES := {
	"stream": {
		"weight": 3.0, "rate_mult": 1.7, "speed_mult": 0.75, "size_mult": 1.0,
		"aim_error_deg": 1.2, "burst_on": Vector2(1.4, 3.0), "burst_off": Vector2(1.4, 2.6),
		"sound_gap_mult": 1.6,
	},
	"burst": {
		"weight": 3.0, "rate_mult": 2.6, "speed_mult": 1.0, "size_mult": 1.0,
		"aim_error_deg": 0.8, "burst_on": Vector2(0.3, 0.6), "burst_off": Vector2(0.7, 1.5),
		"sound_gap_mult": 0.8,
	},
	"fan": {
		"weight": 2.0, "rate_mult": 0.4, "speed_mult": 0.4, "size_mult": 1.7, "life_mult": 2.4,
		"fan": 5, "fan_deg": 40.0, "orb": true,
		"aim_error_deg": 0.0, "burst_on": Vector2(1.5, 3.0), "burst_off": Vector2(1.2, 2.4),
		"sound_gap_mult": 1.0,
	},
	"orbs": {
		"weight": 2.0, "rate_mult": 0.5, "speed_mult": 0.26, "size_mult": 2.8, "life_mult": 3.4,
		"orb": true,
		"aim_error_deg": 2.5, "burst_on": Vector2(2.0, 4.0), "burst_off": Vector2(1.0, 2.0),
		"sound_gap_mult": 1.2, "pitch_mult": 0.75,
	},
	"spiral": {
		"weight": 1.5, "rate_mult": 1.3, "speed_mult": 0.45, "size_mult": 1.5, "life_mult": 2.2,
		"fan": 3, "fan_deg": 22.0, "ring": true, "spiral_deg": 21.0, "orb": true,
		"aim_error_deg": 0.0, "burst_on": Vector2(2.0, 3.5), "burst_off": Vector2(1.5, 2.8),
		"sound_gap_mult": 2.0, "pitch_mult": 1.15,
	},
	"sniper": {
		"weight": 1.0, "rate_mult": 0.28, "speed_mult": 1.5, "size_mult": 1.5,
		"aim_error_deg": 0.0, "burst_on": Vector2(2.5, 4.0), "burst_off": Vector2(1.5, 3.0),
		"sound_gap_mult": 1.0, "pitch_mult": 0.85,
	},
	"classic": {
		"weight": 1.5, "rate_mult": 1.0, "speed_mult": 1.0, "size_mult": 1.0,
		"aim_error_deg": 0.5, "burst_on": Vector2(1.2, 2.2), "burst_off": Vector2(1.6, 3.2),
		"sound_gap_mult": 1.0,
	},
}


## Roll a pattern for one ship. [param variety] is
## [member JuiceSettings.ai_fire_variety]: 0 keeps every multiplier at 1 (the
## weapon's own rhythm), 1 is the catalogue as written, 2 exaggerates it.
##
## Keys [SystemsSim] reads: [code]rate_mult speed_mult size_mult life_mult[/code]
## (floats, 1 = the weapon's own), [code]fan[/code] (shots per trigger per gun),
## [code]fan_deg[/code] (total arc), [code]ring[/code] (fan laid out round the
## aim line instead of side to side), [code]spiral_deg[/code] (the fan's turn
## per volley), [code]aim_error_deg[/code], [code]orb[/code] (draw as a glowing
## ball — reads as a bullet-hell shot), [code]sound_gap_mult pitch_mult[/code].
## [AiShip] reads [code]burst_on burst_off[/code] for its fire/rest rhythm.
static func make(rng: RandomNumberGenerator, variety: float, style := "") -> Dictionary:
	if style == "" or not STYLES.has(style):
		style = _roll_style(rng)
	var src: Dictionary = STYLES[style]
	var p := src.duplicate()
	p["name"] = style
	# The ship's own cadence on top of the style's, so two "stream" ships are
	# still not in step.
	var own_rate := rng.randf_range(0.6, 1.6)
	for key: String in ["rate_mult", "speed_mult", "size_mult", "life_mult", "sound_gap_mult", "pitch_mult"]:
		var v := float(p.get(key, 1.0))
		if key == "rate_mult":
			v *= own_rate
		p[key] = maxf(lerpf(1.0, v, variety), 0.05)
	p["aim_error_deg"] = float(p.get("aim_error_deg", 0.0)) * variety
	p["fan_deg"] = float(p.get("fan_deg", 0.0)) * clampf(variety, 0.0, 1.5)
	if variety <= 0.01:
		p["fan"] = 1
		p["orb"] = false
	return p


static func style_names() -> Array[String]:
	var out: Array[String] = []
	for k: String in STYLES.keys():
		out.append(k)
	return out


static func _roll_style(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in STYLES.keys():
		total += float(STYLES[k]["weight"])
	var pick := rng.randf() * total
	for k: String in STYLES.keys():
		pick -= float(STYLES[k]["weight"])
		if pick <= 0.0:
			return k
	return "classic"
