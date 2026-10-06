## Difficulty: how hard the game is, as one shipped table of dials.
##
## Unlike every settings class (Session, JuiceSettings…), there is no
## [code]user://[/code] layer for the table: the values live only in
## [constant DATA_PATH], a file inside the project (and the export's include
## filter), so what is tuned is what every build ships and every device plays —
## a phone cannot keep its own copy. [method save] writes that file from a
## desktop run of the project (the 🎚 Difficulty panel in the workbench and the
## flight test); anywhere else (an exported build, a phone, a headless check)
## edits last only for the session. The one thing a player keeps is which
## PRESET (Easy / Normal / Hard) they picked — see [method set_preset].
##
## The file holds four things:
## [br]- [code]dials[/code]: the base table ([constant SCHEMA]).
## [br]- [code]presets[/code]: per preset, a multiplier on any dial (missing = ×1).
## [br]- [code]curves[/code]: per-level multipliers on the climb, as
## [code][level, ×][/code] points joined by straight lines ([constant CURVES]).
## [br]- [code]text[/code]: the ship-recommendation wording.
##
## The dials cover the player's hull and how hard enemy shots bite, the
## per-level climb (hull, damage, size, aggression, weapon class, how many
## may shoot at once), who enemies go for on guard missions, the lone ace,
## the star bars, when dreadnoughts turn up, what levels pay and whether a
## level may force a type of ship. [method for_level] turns them into a
## level's scenario overrides; the rest of the game reads them with [method v].
## Pure data: no module dependency.
class_name Difficulty
extends RefCounted

const DATA_PATH := "res://modules/difficulty/data/difficulty.json"
## Which preset the player chose (the only per-device part).
const PREF_PATH := "user://difficulty_pref.cfg"

## Every dial: [default, min, max, group, what it does]. The panel is built
## from this, in this order.
const SCHEMA := {
	# --- Player ---
	"player_hull": [0.6, 0.2, 2.0, "Player", "Player's hull, × the ship's own."],
	"enemy_bite": [2.2, 0.2, 6.0, "Player", "Enemy shots on the player, × their tuned damage."],
	"ram_max_share": [0.34, 0.05, 1.0, "Player", "Most of an enemy's hull one ram (the player's crash into it) can take. Stops a fast launch from one-shotting an ace."],
	"ram_gap": [0.7, 0.0, 3.0, "Player", "Seconds before the same enemy can take another ram."],
	"max_hit_share": [0.25, 0.05, 1.0, "Player", "Most of the player's hull one enemy hit can take."],
	# --- Game-wide (on top of the Juice dials) ---
	"damage_taken": [1.0, 0.1, 5.0, "Game-wide", "All damage the player takes, × (on top of the Juice dial). Presets use this."],
	"enemy_hp": [1.0, 0.1, 5.0, "Game-wide", "Every enemy's hull, × (on top of the Juice dial). Presets use this."],
	# --- The climb, per level number ---
	"enemy_size_max": [1.8, 1.0, 4.0, "Level climb", "Biggest the climb makes an ordinary enemy."],
	"extra_enemy_every": [5.0, 1.0, 20.0, "Level climb", "One more enemy every this many levels."],
	"threat_max": [2.5, 1.0, 5.0, "Level climb", "Most aggression the climb reaches."],
	"attackers_start": [2.0, 1.0, 8.0, "Level climb", "Enemies that may shoot at the player at once, level 1."],
	"attackers_every": [6.0, 1.0, 30.0, "Level climb", "One more of them every this many levels."],
	"attackers_max": [5.0, 1.0, 12.0, "Level climb", "Most that may ever shoot at once."],
	# --- Level growth: value(n) = (start + (end - start) * t^shape) * era^eras(n) * curve, t = (n-1)/(growth_span-1) ---
	"growth_span": [40.0, 5.0, 200.0, "Growth: timing", "The level where each stat reaches its END value."],
	"era_start": [20.0, 1.0, 200.0, "Growth: timing", "First level of era 1 (eras compound a stat by its ERA step)."],
	"era_levels": [10.0, 1.0, 50.0, "Growth: timing", "Levels per era."],
	"hp_start": [1.0, 0.2, 40.0, "Growth: Enemy hull", "Enemy hull at level 1."],
	"hp_end": [5.0, 0.2, 40.0, "Growth: Enemy hull", "Enemy hull at the growth_span level (× a level-1 enemy's hull)."],
	"hp_shape": [1.1, 0.3, 3.0, "Growth: Enemy hull", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"hp_era": [1.12, 1.0, 1.5, "Growth: Enemy hull", "Multiplier added for every era past the first (1 = none)."],
	"damage_start": [0.85, 0.2, 30.0, "Growth: Enemy damage", "Enemy damage at level 1."],
	"damage_end": [3.6, 0.2, 30.0, "Growth: Enemy damage", "Enemy damage at the growth_span level (× enemy damage)."],
	"damage_shape": [1.05, 0.3, 3.0, "Growth: Enemy damage", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"damage_era": [1.07, 1.0, 1.5, "Growth: Enemy damage", "Multiplier added for every era past the first (1 = none)."],
	"threat_start": [1.0, 0.5, 6.0, "Growth: Enemy aggression", "Enemy aggression at level 1."],
	"threat_end": [2.5, 0.5, 6.0, "Growth: Enemy aggression", "Enemy aggression at the growth_span level (shorter rests, faster fire and yeets)."],
	"threat_shape": [1.0, 0.3, 3.0, "Growth: Enemy aggression", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"threat_era": [1.0, 1.0, 1.5, "Growth: Enemy aggression", "Multiplier added for every era past the first (1 = none)."],
	"size_start": [1.0, 0.5, 4.0, "Growth: Enemy size", "Enemy size at level 1."],
	"size_end": [1.6, 0.5, 4.0, "Growth: Enemy size", "Enemy size at the growth_span level (× an ordinary enemy's size)."],
	"size_shape": [1.0, 0.3, 3.0, "Growth: Enemy size", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"size_era": [1.0, 1.0, 1.5, "Growth: Enemy size", "Multiplier added for every era past the first (1 = none)."],
	"boss_hp_start": [0.7, 0.2, 40.0, "Growth: Boss hull", "Boss hull at level 1."],
	"boss_hp_end": [1.9, 0.2, 40.0, "Growth: Boss hull", "Boss hull at the growth_span level (× the boss's base hull)."],
	"boss_hp_shape": [1.0, 0.3, 3.0, "Growth: Boss hull", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"boss_hp_era": [1.1, 1.0, 1.5, "Growth: Boss hull", "Multiplier added for every era past the first (1 = none)."],
	"boss_size_start": [6.5, 2.0, 30.0, "Growth: Boss size", "Boss size at level 1."],
	"boss_size_end": [10.0, 2.0, 30.0, "Growth: Boss size", "Boss size at the growth_span level (in fighter sizes (a boss must out-size everything else))."],
	"boss_size_shape": [1.0, 0.3, 3.0, "Growth: Boss size", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"boss_size_era": [1.0, 1.0, 1.5, "Growth: Boss size", "Multiplier added for every era past the first (1 = none)."],
	"ace_hp_start": [2.6, 1.0, 12.0, "Growth: Ace hull", "Ace hull at level 1."],
	"ace_hp_end": [3.2, 1.0, 12.0, "Growth: Ace hull", "Ace hull at the growth_span level (× a level enemy's hull (duel levels))."],
	"ace_hp_shape": [1.0, 0.3, 3.0, "Growth: Ace hull", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"ace_hp_era": [1.0, 1.0, 1.5, "Growth: Ace hull", "Multiplier added for every era past the first (1 = none)."],
	"ace_threat_start": [1.8, 1.0, 4.0, "Growth: Ace aggression", "Ace aggression at level 1."],
	"ace_threat_end": [2.2, 1.0, 4.0, "Growth: Ace aggression", "Ace aggression at the growth_span level (× the level's aggression (duel levels))."],
	"ace_threat_shape": [1.0, 0.3, 3.0, "Growth: Ace aggression", "Curve: 1 = straight line, above 1 = slow start then steep, below 1 = fast start then flat."],
	"ace_threat_era": [1.0, 1.0, 1.5, "Growth: Ace aggression", "Multiplier added for every era past the first (1 = none)."],
	# --- Enemy guns ---
	"corvette_from": [3.0, 1.0, 60.0, "Enemy guns", "Level corvette guns (lasers, seekers) start."],
	"hauler_from": [9.0, 1.0, 60.0, "Enemy guns", "Level hauler guns (gauss, hellfire) start."],
	"capital_from": [20.0, 1.0, 80.0, "Enemy guns", "Level capital guns (railgun, planet-buster) start."],
	"heavy_share": [0.3, 0.0, 1.0, "Enemy guns", "Share of enemies carrying the heaviest class allowed."],
	"boss_capital_from": [6.0, 1.0, 80.0, "Enemy guns", "Level bosses carry capital guns (planet-buster) from."],
	# --- Who enemies go for ---
	"player_focus": [0.6, 0.2, 1.0, "Targeting", "Enemies treat the player as this much nearer than they are (lower = hunt the player)."],
	"ally_damage": [0.4, 0.0, 1.5, "Targeting", "Wingmen's damage, × — so they can't win the fight for you."],
	"escort_max_attackers": [2.0, 0.0, 8.0, "Targeting", "Most enemies attacking the guarded ship at once."],
	"escort_player_range": [450.0, 0.0, 2000.0, "Targeting", "An enemy this close to the player goes for the player, not the guarded ship (m)."],
	"protect_escort_share": [0.5, 0.0, 1.0, "Targeting", "Protect missions: share of enemies that want the hauler (rest want you)."],
	# --- The lone ace (duel) ---
	"ace_gun_bonus": [1.0, 0.0, 3.0, "Ace", "Gun classes above the level's the ace carries."],
	# --- Stars ---
	"fight_weight": [2.0, 0.0, 5.0, "Stars", "Fight levels: weight of your own share of the kills."],
	"star_fast": [0.6, 0.2, 1.5, "Stars", "Speed scores full marks at or under this share of a level's par time."],
	"star_slow": [1.5, 0.8, 4.0, "Stars", "...and nothing at this share of par. Lower = stricter."],
	"star_two_base": [0.45, 0.0, 0.95, "Stars", "Score needed for 2 stars on the easiest level."],
	"star_two_rise": [0.2, 0.0, 0.5, "Stars", "How much the 2-star score rises by the hardest level."],
	"star_three_base": [0.72, 0.0, 0.95, "Stars", "Score needed for 3 stars on the easiest level."],
	"star_three_rise": [0.2, 0.0, 0.5, "Stars", "How much the 3-star score rises by the hardest level."],
	"star_bar_bonus": [0.08, 0.0, 0.3, "Stars", "Added to both star bars on every level."],
	# --- Dreadnoughts ---
	"boss_dreadnought": [1.0, 0.0, 1.0, "Dreadnought", "Bosses fly the dreadnought hull (1 = yes)."],
	"dreadnought_from": [8.0, 1.0, 80.0, "Dreadnought", "Level heavy dreadnoughts join fights from."],
	"dreadnought_chance": [0.4, 0.0, 1.0, "Dreadnought", "Chance a fight level brings one."],
	"dreadnought_size": [3.0, 1.0, 12.0, "Dreadnought", "A heavy dreadnought's size, fighter sizes."],
	"dreadnought_hp": [5.0, 1.0, 20.0, "Dreadnought", "Its hull, × a level enemy's."],
	# --- Megastructures (LargeCraftGenerator warships: turrets, launch bays) ---
	"mega_boss_from": [8.0, 1.0, 80.0, "Megastructures", "Level a sector boss may be a megastructure warship from."],
	"mega_boss_chance": [0.5, 0.0, 1.0, "Megastructures", "Chance a boss from then on is one."],
	"mega_assault_from": [5.0, 1.0, 80.0, "Megastructures", "Level an assault's carrier is a megastructure mothership from."],
	"mega_planet_chance": [0.35, 0.0, 1.0, "Megastructures", "Chance a megastructure is planet-sized."],
	"mega_sun_chance": [0.2, 0.0, 1.0, "Megastructures", "Chance a megastructure is sun-sized."],
	"backdrop_chance": [0.4, 0.0, 1.0, "Megastructures", "Chance a level without a fight has a megastructure in the distance (often sun-sized)."],
	"boss_size_spread": [2.6, 1.0, 6.0, "Megastructures", "Big-ship bosses vary from their level's size up to this many times it."],
	# --- Rewards ---
	"reward_base": [40.0, 0.0, 500.0, "Rewards", "Coins a level's first win pays before the climb."],
	"reward_per_level": [12.0, 0.0, 100.0, "Rewards", "Coins added per level number."],
	"reward_mult": [1.0, 0.0, 5.0, "Rewards", "All level pay, ×. Presets use this."],
	"replay_pay": [0.25, 0.0, 1.0, "Rewards", "Share of the pay a replayed win gets."],
	"star_bonus": [25.0, 0.0, 200.0, "Rewards", "Coins per new star."],
	# --- Ship choice ---
	"force_ship": [1.0, 0.0, 1.0, "Ship choice", "Levels may force a ship type (1 = yes). 0: you fly the ship you equipped and the level only recommends one."],
	"force_chance": [0.3, 0.0, 1.0, "Ship choice", "Chance a level past the first sector names a ship type (forced, or recommended with force off)."],
}
## The scaled-by-level multipliers: id → [what it scales, default points].
## Points are [level number, ×], joined by straight lines, flat past the ends.
const CURVES := {
	"hp": ["Enemy hull", [[1, 1.0], [40, 1.0]]],
	"damage": ["Enemy damage", [[1, 1.0], [40, 1.0]]],
	"threat": ["Aggression", [[1, 1.0], [40, 1.0]]],
	"size": ["Enemy size", [[1, 1.0], [40, 1.0]]],
	"boss_hp": ["Boss hull", [[1, 1.0], [40, 1.0]]],
	"boss_size": ["Boss size", [[1, 1.0], [40, 1.0]]],
	"ace_hp": ["Ace hull", [[1, 1.0], [40, 1.0]]],
	"ace_threat": ["Ace aggression", [[1, 1.0], [40, 1.0]]],
	"reward": ["Level pay", [[1, 1.0], [40, 1.0]]],
}
## The stats that grow with the level, in panel order: id → label. Each has
## `<id>_start`, `<id>_end`, `<id>_shape` and `<id>_era` dials (see [method stat]).
const GROWTH := {
	"hp": "Enemy hull", "damage": "Enemy damage", "threat": "Enemy aggression", "size": "Enemy size",
	"boss_hp": "Boss hull", "boss_size": "Boss size", "ace_hp": "Ace hull", "ace_threat": "Ace aggression",
}
const PRESET_NAMES: Array[String] = ["EASY", "NORMAL", "HARD"]
const NORMAL := 1
## Preset multipliers shipped until the file says otherwise (Normal changes nothing).
const PRESET_DEFAULTS := {
	"EASY": {"damage_taken": 0.56, "enemy_hp": 0.71},
	"NORMAL": {},
	"HARD": {"damage_taken": 1.52, "enemy_hp": 1.33},
}
## The ship types a level can recommend (ShipCatalog.TYPE_NAMES).
const HINT_TYPES: Array[String] = ["SCOUT", "FIGHTER", "TANK", "HAULER", "TITAN"]
## The recommendation wording, until the file says otherwise.
const TEXT_DEFAULTS := {
	"prefix": "BEST WITH",
	"hints": {
		"SCOUT": "SPEED", "FIGHTER": "GUNS & AGILITY", "TANK": "A TOUGH HULL",
		"HAULER": "ROOM & STEADY HANDS", "TITAN": "BRUTE FORCE",
	},
}
## A megastructure's size ([enum FlightRoot.CraftSize]: 1 default, 2 planet,
## 3 sun) for a 0..1 roll.
static func mega_size(r: float) -> int:
	if r < v("mega_sun_chance"):
		return 3
	if r < v("mega_sun_chance") + v("mega_planet_chance"):
		return 2
	return 1


## The other big hulls a boss can fly (ship_families.json).
const BOSS_PRESETS: Array[String] = ["segment_cruiser", "bulwark_warden", "mule_juggernaut", "keel_sovereign"]
## The hull preset the dreadnoughts fly (ship_families.json).
const DREADNOUGHT_PRESET := "keel_dreadnought"
## Weapon classes, lowest first (SystemsSim.WEAPON_SIZE_TIERS).
const GUN_CLASSES: Array[String] = ["fighter", "corvette", "hauler", "capital"]
## The fight kinds (LevelGen ids) that grade the player's share of kills.
const KILL_GRADED: Array[String] = ["duel", "skirmish", "ambush", "battle", "waves", "assault", "boss"]

## The chosen preset (index into [constant PRESET_NAMES]).
static var preset := NORMAL

static var _values: Dictionary = {}
static var _presets: Dictionary = {}
static var _curves: Dictionary = {}
static var _text: Dictionary = {}
static var _loaded := false


# --- Dials ----------------------------------------------------------------------

## A dial's value as the game plays it: the table's value × the chosen preset's
## multiplier. (Its schema default when the file does not set it.)
static func v(dial: String) -> float:
	_ensure()
	return base(dial) * preset_mult(PRESET_NAMES[preset], dial)


## A dial's value in the table, before any preset.
static func base(dial: String) -> float:
	_ensure()
	if _values.has(dial):
		return float(_values[dial])
	return float((SCHEMA.get(dial, [0.0]) as Array)[0])


## Set a dial (clamped to its range). Call [method save] to keep it.
static func set_dial(dial: String, value: float) -> void:
	_ensure()
	if not SCHEMA.has(dial):
		return
	var s: Array = SCHEMA[dial]
	_values[dial] = clampf(value, float(s[1]), float(s[2]))


## Every dial, preset, curve and word back to the defaults (not saved).
static func reset() -> void:
	_values.clear()
	_presets.clear()
	_curves.clear()
	_text.clear()
	_loaded = true


# --- Presets --------------------------------------------------------------------

## Preset [param name]'s multiplier on [param dial] (1 when it does not touch it).
static func preset_mult(name: String, dial: String) -> float:
	_ensure()
	var p: Dictionary = _presets.get(name, PRESET_DEFAULTS.get(name, {}))
	return float(p.get(dial, 1.0))


## Set preset [param name]'s multiplier on [param dial] (1 removes it).
static func set_preset_mult(name: String, dial: String, mult: float) -> void:
	_ensure()
	if not _presets.has(name):
		_presets[name] = (PRESET_DEFAULTS.get(name, {}) as Dictionary).duplicate()
	if absf(mult - 1.0) < 0.0001:
		(_presets[name] as Dictionary).erase(dial)
	else:
		(_presets[name] as Dictionary)[dial] = clampf(mult, 0.05, 20.0)


static func set_preset(index: int) -> void:
	_ensure()
	preset = clampi(index, 0, PRESET_NAMES.size() - 1)
	if DisplayServer.get_name() != "headless":
		var cfg := ConfigFile.new()
		cfg.set_value("difficulty", "preset", preset)
		cfg.save(PREF_PATH)


static func preset_name() -> String:
	return PRESET_NAMES[preset]


# --- Curves ---------------------------------------------------------------------

## Curve [param id]'s multiplier at level [param number]: its points joined by
## straight lines, flat before the first and after the last.
static func curve(id: String, number: int) -> float:
	var pts := curve_points(id)
	if pts.is_empty():
		return 1.0
	var n := float(number)
	if n <= float((pts[0] as Array)[0]):
		return float((pts[0] as Array)[1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if n <= float(b[0]):
			var span := maxf(float(b[0]) - float(a[0]), 0.0001)
			return lerpf(float(a[1]), float(b[1]), (n - float(a[0])) / span)
	return float((pts[pts.size() - 1] as Array)[1])


## Curve [param id]'s points, sorted by level (a copy).
static func curve_points(id: String) -> Array:
	_ensure()
	if _curves.has(id):
		return (_curves[id] as Array).duplicate(true)
	return ((CURVES.get(id, ["", []]) as Array)[1] as Array).duplicate(true)


## Replace curve [param id]'s points ([level, ×] pairs; sorted and clamped here).
static func set_curve_points(id: String, pts: Array) -> void:
	_ensure()
	if not CURVES.has(id):
		return
	var out: Array = []
	for p: Array in pts:
		out.append([maxi(1, int(p[0])), clampf(float(p[1]), 0.05, 20.0)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	_curves[id] = out


# --- Ship choice ----------------------------------------------------------------

## Whether a level's ship type is forced (else it is only recommended and the
## player flies the ship they equipped).
static func forces_ship() -> bool:
	return v("force_ship") >= 0.5


## Level-pay maths, shared by the level maker and the pay-out.
static func level_reward(number: int) -> int:
	var raw := (v("reward_base") + v("reward_per_level") * float(number)) * v("reward_mult")
	return int(raw * curve("reward", number))


## The line a level's card shows for a recommended ship type, e.g.
## "BEST WITH SPEED".
static func ship_hint(type_name: String) -> String:
	_ensure()
	var t: Dictionary = _text.get("hints", {})
	var hints: Dictionary = TEXT_DEFAULTS["hints"]
	var what := String(t.get(type_name, hints.get(type_name, "")))
	var pre := String(_text.get("prefix", TEXT_DEFAULTS["prefix"]))
	return ("%s %s" % [pre, what]).strip_edges()


## The wording behind [method ship_hint]: [param type_name] "" is the prefix.
static func hint_text(type_name: String) -> String:
	_ensure()
	if type_name == "":
		return String(_text.get("prefix", TEXT_DEFAULTS["prefix"]))
	var t: Dictionary = _text.get("hints", {})
	return String(t.get(type_name, (TEXT_DEFAULTS["hints"] as Dictionary).get(type_name, "")))


static func set_hint_text(type_name: String, text: String) -> void:
	_ensure()
	if type_name == "":
		_text["prefix"] = text
		return
	if not _text.has("hints"):
		_text["hints"] = (TEXT_DEFAULTS["hints"] as Dictionary).duplicate()
	(_text["hints"] as Dictionary)[type_name] = text


# --- The file -------------------------------------------------------------------

## True when [method save] can write the shipped file: a desktop run from
## the project, with a window.
static func can_save() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web") or OS.has_feature("template"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("editor")


## Write the table into the project ([constant DATA_PATH]). Returns false
## where the project cannot be written (see [method can_save]).
static func save() -> bool:
	if not can_save():
		return false
	var dials := {}
	for k: String in SCHEMA:
		dials[k] = base(k)
	var presets := {}
	for p in PRESET_NAMES:
		var m := {}
		for k: String in SCHEMA:
			var x := preset_mult(p, k)
			if absf(x - 1.0) > 0.0001:
				m[k] = snappedf(x, 0.001)
		presets[p] = m
	var curves := {}
	for id: String in CURVES:
		curves[id] = curve_points(id)
	var text := {"prefix": hint_text(""), "hints": {}}
	for t in HINT_TYPES:
		(text["hints"] as Dictionary)[t] = hint_text(t)
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Difficulty: cannot write %s" % DATA_PATH)
		return false
	f.store_string(JSON.stringify({"dials": dials, "presets": presets, "curves": curves, "text": text}, "\t"))
	return true


## Re-read [constant DATA_PATH] (drops unsaved edits) and the player's preset.
static func reload() -> void:
	reset()
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			# The old file was the flat table.
			var dials: Dictionary = d.get("dials", d)
			for k: String in dials:
				if SCHEMA.has(k):
					set_dial(k, float(dials[k]))
			var ps: Variant = d.get("presets", {})
			if ps is Dictionary:
				for name: String in (ps as Dictionary):
					for k: String in (ps[name] as Dictionary):
						if SCHEMA.has(k):
							set_preset_mult(name, k, float(ps[name][k]))
			var cs: Variant = d.get("curves", {})
			if cs is Dictionary:
				for id: String in (cs as Dictionary):
					if CURVES.has(id) and cs[id] is Array:
						set_curve_points(id, cs[id])
			var tx: Variant = d.get("text", {})
			if tx is Dictionary:
				if (tx as Dictionary).has("prefix"):
					set_hint_text("", String(tx["prefix"]))
				var hs: Variant = (tx as Dictionary).get("hints", {})
				if hs is Dictionary:
					for t: String in (hs as Dictionary):
						set_hint_text(t, String(hs[t]))
	var cfg := ConfigFile.new()
	if cfg.load(PREF_PATH) == OK:
		preset = clampi(int(cfg.get_value("difficulty", "preset", NORMAL)), 0, PRESET_NAMES.size() - 1)


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		reload()


# --- Level growth ---------------------------------------------------------------

## Eras passed by level [param number]: 0 before `era_start`, then one more
## every `era_levels`.
static func era_of(number: int) -> int:
	if float(number) < v("era_start"):
		return 0
	return 1 + int((float(number) - v("era_start")) / maxf(v("era_levels"), 1.0))


## Growth stat [param id] at level [param number] — the one formula for every
## stat that climbs:
## [code](start + (end - start) * t^shape) * era^eras * curve[/code], with
## [code]t = (level - 1) / (growth_span - 1)[/code]. Past the span it keeps
## following the same power law.
static func stat(id: String, number: int) -> float:
	var t := float(maxi(number - 1, 0)) / maxf(v("growth_span") - 1.0, 1.0)
	var s := v(id + "_start")
	var e := v(id + "_end")
	var x := s + (e - s) * pow(t, v(id + "_shape"))
	return x * pow(v(id + "_era"), float(era_of(number))) * curve(id, number)


## The formula for [param id] as text, numbers filled in.
static func formula_text(id: String) -> String:
	return "(%s + (%s - %s) x t^%s) x %s^eras   t = (level-1)/(%d-1)" % [
		_n(v(id + "_start")), _n(v(id + "_end")), _n(v(id + "_start")),
		_n(v(id + "_shape")), _n(v(id + "_era")), int(v("growth_span"))]


static func _n(x: float) -> String:
	return str(snappedf(x, 0.01 if absf(x) < 100.0 else 1.0))


## Everything a level of kind [param kind] at [param number] throws at the
## player, as plain numbers for the panel: `{label: value}` in display order.
## Enemy hull is shown in the flight scene's own units (150–700 per fighter,
## before the Juice dials); the boss's base hull is 2600.
static func level_stats(number: int, kind: String) -> Array:
	var hp := stat("hp", number)
	var dmg := stat("damage", number)
	var rows: Array = [
		["Enemy hull ×", "%.2f   (typical fighter %d hp)" % [hp, int(425.0 * hp * v("enemy_hp"))]],
		["Enemy damage ×", "%.2f   (hits the player at ×%.2f)" % [dmg, dmg * v("enemy_bite")]],
		["Aggression", "%.2f of %.1f max" % [minf(stat("threat", number), v("threat_max")), v("threat_max")]],
		["Enemy size ×", "%.2f" % minf(stat("size", number), v("enemy_size_max"))],
		["Gun class", GUN_CLASSES[gun_class(number)]],
		["Shooting at once", "%d" % mini(int(v("attackers_start")) + int(float(maxi(number - 1, 0)) / maxf(v("attackers_every"), 1.0)), int(v("attackers_max")))],
		["Era", "%d" % era_of(number)],
		["Level pay", "%d coins" % level_reward(number)],
	]
	if kind == "duel":
		rows.append(["Ace hull", "%d hp  (x%.2f a fighter)" % [int(425.0 * hp * stat("ace_hp", number) * v("enemy_hp")), stat("ace_hp", number)]])
		rows.append(["Ace aggression", "%.2f" % (minf(stat("threat", number), v("threat_max")) * stat("ace_threat", number))])
		rows.append(["Ace guns", GUN_CLASSES[mini(gun_class(number) + int(v("ace_gun_bonus")), 3)]])
	if kind == "boss":
		rows.append(["Boss hull", "%d hp" % int(2600.0 * stat("boss_hp", number) * hp * v("enemy_hp"))])
		rows.append(["Boss size", "x%.1f a fighter" % stat("boss_size", number)])
		rows.append(["Boss guns", GUN_CLASSES[3 if number >= int(v("boss_capital_from")) else maxi(gun_class(number), 2)]])
	return rows


# --- Levels ---------------------------------------------------------------------

## How aggressive enemies are at level [param number] (1 = level 1's).
static func threat(number: int) -> float:
	return minf(stat("threat", number), v("threat_max"))


## The heaviest gun class (index into [constant GUN_CLASSES]) enemies may
## carry at level [param number].
static func gun_class(number: int) -> int:
	var c := 0
	if number >= int(v("corvette_from")):
		c = 1
	if number >= int(v("hauler_from")):
		c = 2
	if number >= int(v("capital_from")):
		c = 3
	return c


## The scenario overrides the climb adds to level [param number] of kind
## [param kind] (LevelGen ids), on top of the level's own: multipliers for
## enemy hull and damage (×, applied to LevelGen's), size, aggression, gun
## classes, attack slots and any dreadnought. [param roll] is the level's
## own 0..1 roll, so the same level always gets the same answer.
static func for_level(number: int, kind: String, roll: float) -> Dictionary:
	var n := float(maxi(number - 1, 0))
	var o := {
		"hp_mult": stat("hp", number),
		"damage_mult": stat("damage", number),
		"enemy_size": snappedf(minf(stat("size", number), v("enemy_size_max")), 0.01),
		"threat": snappedf(threat(number), 0.01),
		"gun_class": gun_class(number),
		"heavy_share": v("heavy_share"),
		"max_attackers": mini(int(v("attackers_start")) + int(n / maxf(v("attackers_every"), 1.0)), int(v("attackers_max"))),
		"extra_enemies": int(n / maxf(v("extra_enemy_every"), 1.0)),
	}
	# Two more rolls from the level's one, so the old numbers stay put.
	var roll_b := fposmod(roll * 7.31 + 0.13, 1.0)
	var roll_c := fposmod(roll * 13.7 + 0.41, 1.0)
	if kind == "boss":
		o["boss_gun_class"] = 3 if number >= int(v("boss_capital_from")) else maxi(gun_class(number), 2)
		o["boss_hp"] = snappedf(stat("boss_hp", number), 0.05)
		# Bosses come in every size: most near their level's, now and then
		# several times it.
		o["boss_size"] = snappedf(stat("boss_size", number) * lerpf(1.0, v("boss_size_spread"), pow(roll_b, 1.6)), 0.1)
		if v("boss_dreadnought") >= 0.5:
			o["boss_preset"] = DREADNOUGHT_PRESET if roll_c < 0.55 else BOSS_PRESETS[int(roll_b * BOSS_PRESETS.size()) % BOSS_PRESETS.size()]
		if number >= int(v("mega_boss_from")) and roll_c < v("mega_boss_chance"):
			o["mega_boss"] = true
			o["mega_kind"] = 0 if roll_b < 0.6 else 1
			o["mega_size"] = mega_size(roll_b)
	if kind == "assault" and number >= int(v("mega_assault_from")):
		o["mega"] = true
		o["mega_size"] = mega_size(roll_c)
	if kind == "duel":
		o["ace"] = true
		o["ace_hp"] = stat("ace_hp", number)
		o["threat"] = snappedf(float(o["threat"]) * stat("ace_threat", number), 0.01)
		o["gun_class"] = mini(int(o["gun_class"]) + int(v("ace_gun_bonus")), 3)
		o["heavy_share"] = 1.0
	if kind in ["skirmish", "ambush", "battle", "assault", "boss", "capital"] \
			and number >= int(v("dreadnought_from")) and roll < v("dreadnought_chance"):
		o["dreadnoughts"] = 1
		# Never as big as the boss of the same level.
		o["dreadnought_size"] = minf(v("dreadnought_size"), stat("boss_size", number) * 0.6) if kind == "boss" else v("dreadnought_size")
		o["dreadnought_hp"] = v("dreadnought_hp")
	return o
