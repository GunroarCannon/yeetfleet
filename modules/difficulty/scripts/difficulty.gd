## Difficulty: how hard the game is, as one shipped table of dials.
##
## Unlike every settings class (Session, JuiceSettings…), there is no
## [code]user://[/code] layer here: the values live only in
## [constant DATA_PATH], a file inside the project, so what is tuned is what
## every build ships and every device plays — a phone cannot keep its own
## copy. [method save] writes that file from a desktop run of the project
## (the flight test's 🎚 Difficulty panel); anywhere else (an exported build,
## a phone, a headless check) edits last only for the session.
##
## The dials cover the player's hull and how hard enemy shots bite, the
## per-level climb (hull, damage, size, aggression, weapon class, how many
## may shoot at once), who enemies go for on guard missions, the lone ace,
## the star bars and when dreadnoughts turn up. [method for_level] turns
## them into a level's scenario overrides; the flight scene reads the rest
## with [method v]. Pure data: no module dependency.
class_name Difficulty
extends RefCounted

const DATA_PATH := "res://modules/difficulty/data/difficulty.json"

## Every dial: [default, min, max, group, what it does]. The panel is built
## from this, in this order.
const SCHEMA := {
	# --- Player ---
	"player_hull": [0.6, 0.2, 2.0, "Player", "Player's hull, × the ship's own."],
	"enemy_bite": [2.2, 0.2, 6.0, "Player", "Enemy shots on the player, × their tuned damage."],
	"max_hit_share": [0.25, 0.05, 1.0, "Player", "Most of the player's hull one enemy hit can take."],
	# --- The climb, per level number ---
	"enemy_hp_growth": [0.06, 0.0, 0.3, "Level climb", "Enemy hull added per level (level 11 = 1 + 10×this)."],
	"enemy_damage_growth": [0.045, 0.0, 0.3, "Level climb", "Enemy damage added per level."],
	"enemy_size_growth": [0.015, 0.0, 0.1, "Level climb", "Enemy size added per level."],
	"enemy_size_max": [1.8, 1.0, 4.0, "Level climb", "Biggest the climb makes an ordinary enemy."],
	"extra_enemy_every": [5.0, 1.0, 20.0, "Level climb", "One more enemy every this many levels."],
	"threat_growth": [0.04, 0.0, 0.3, "Level climb", "Aggression per level: shorter rests, faster fire and yeets."],
	"threat_max": [2.5, 1.0, 5.0, "Level climb", "Most aggression the climb reaches."],
	"attackers_start": [2.0, 1.0, 8.0, "Level climb", "Enemies that may shoot at the player at once, level 1."],
	"attackers_every": [6.0, 1.0, 30.0, "Level climb", "One more of them every this many levels."],
	"attackers_max": [5.0, 1.0, 12.0, "Level climb", "Most that may ever shoot at once."],
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
	"ace_hp": [2.6, 1.0, 8.0, "Ace", "The ace's hull, × a level enemy's."],
	"ace_threat": [1.8, 1.0, 4.0, "Ace", "The ace's aggression, × the level's."],
	"ace_gun_bonus": [1.0, 0.0, 3.0, "Ace", "Gun classes above the level's the ace carries."],
	# --- Stars ---
	"fight_weight": [2.0, 0.0, 5.0, "Stars", "Fight levels: weight of your own share of the kills."],
	"star_bar_bonus": [0.08, 0.0, 0.3, "Stars", "Added to both star bars on every level."],
	# --- Dreadnoughts ---
	"boss_dreadnought": [1.0, 0.0, 1.0, "Dreadnought", "Bosses fly the dreadnought hull (1 = yes)."],
	"dreadnought_from": [8.0, 1.0, 80.0, "Dreadnought", "Level heavy dreadnoughts join fights from."],
	"dreadnought_chance": [0.4, 0.0, 1.0, "Dreadnought", "Chance a fight level brings one."],
	"dreadnought_size": [2.4, 1.0, 6.0, "Dreadnought", "A heavy dreadnought's size, fighter sizes."],
	"dreadnought_hp": [5.0, 1.0, 20.0, "Dreadnought", "Its hull, × a level enemy's."],
}
## The hull preset the dreadnoughts fly (ship_families.json).
const DREADNOUGHT_PRESET := "keel_dreadnought"
## Weapon classes, lowest first (SystemsSim.WEAPON_SIZE_TIERS).
const GUN_CLASSES: Array[String] = ["fighter", "corvette", "hauler", "capital"]
## The fight kinds (LevelGen ids) that grade the player's share of kills.
const KILL_GRADED: Array[String] = ["duel", "skirmish", "ambush", "battle", "waves", "assault", "boss"]

static var _values: Dictionary = {}
static var _loaded := false


## A dial's value (its schema default when the file does not set it).
static func v(dial: String) -> float:
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


## Every dial back to its schema default (not saved).
static func reset() -> void:
	_values.clear()
	_loaded = true


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
	var out := {}
	for k: String in SCHEMA:
		out[k] = v(k)
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Difficulty: cannot write %s" % DATA_PATH)
		return false
	f.store_string(JSON.stringify(out, "\t"))
	return true


## Re-read [constant DATA_PATH] (drops unsaved edits).
static func reload() -> void:
	_values.clear()
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		for k: String in (parsed as Dictionary):
			if SCHEMA.has(k):
				set_dial(k, float(parsed[k]))


static func _ensure() -> void:
	if not _loaded:
		reload()


# --- Levels ---------------------------------------------------------------------

## How aggressive enemies are at level [param number] (1 = level 1's).
static func threat(number: int) -> float:
	return minf(1.0 + v("threat_growth") * float(maxi(number - 1, 0)), v("threat_max"))


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
		"hp_mult": 1.0 + v("enemy_hp_growth") * n,
		"damage_mult": 1.0 + v("enemy_damage_growth") * n,
		"enemy_size": snappedf(minf(1.0 + v("enemy_size_growth") * n, v("enemy_size_max")), 0.01),
		"threat": snappedf(threat(number), 0.01),
		"gun_class": gun_class(number),
		"heavy_share": v("heavy_share"),
		"max_attackers": mini(int(v("attackers_start")) + int(n / maxf(v("attackers_every"), 1.0)), int(v("attackers_max"))),
		"extra_enemies": int(n / maxf(v("extra_enemy_every"), 1.0)),
	}
	if kind == "boss":
		o["boss_gun_class"] = 3 if number >= int(v("boss_capital_from")) else maxi(gun_class(number), 2)
		if v("boss_dreadnought") >= 0.5:
			o["boss_preset"] = DREADNOUGHT_PRESET
	if kind == "duel":
		o["ace"] = true
		o["ace_hp"] = v("ace_hp")
		o["threat"] = snappedf(float(o["threat"]) * v("ace_threat"), 0.01)
		o["gun_class"] = mini(int(o["gun_class"]) + int(v("ace_gun_bonus")), 3)
		o["heavy_share"] = 1.0
	if kind in ["skirmish", "ambush", "battle", "assault", "boss", "capital"] \
			and number >= int(v("dreadnought_from")) and roll < v("dreadnought_chance"):
		o["dreadnoughts"] = 1
		o["dreadnought_size"] = v("dreadnought_size")
		o["dreadnought_hp"] = v("dreadnought_hp")
	return o
