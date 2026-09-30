## LevelGen: the campaign's levels, generated from a seed instead of authored.
##
## A level is a seed plus a recipe ([code]level-setup.md[/code] §1): the seed
## comes from the level's key, the key comes from the route the player took
## to reach it, and the recipe is a flight scenario preset with overrides. The
## same key gives the same level on every device, forever — until
## [constant GRAMMAR_VERSION] is bumped, which is how a tuning change is
## allowed to reshuffle the whole campaign.
##
## The map is a chain of sectors of [constant LEVELS_PER_SECTOR] levels. Each
## sector has a theme; after a sector the road forks into two themes (see
## [method fork_options]): one the seed picks, one the player's own play
## style picks. So the campaign branches, but two players on the same branch
## still play identical levels.
##
## Pure data: the output is plain dictionaries, and scenario presets are named
## by id (flight's own [code]FlightScenarios[/code] ids), so nothing here
## depends on the flight module.
class_name LevelGen
extends RefCounted

## Bump to regenerate every level (names, picks, numbers). Saved progress is
## keyed by level key, so records survive — the levels behind them change.
const GRAMMAR_VERSION := 1
const LEVELS_PER_SECTOR := 6

## How a sector's levels link up: per level, the levels winning it opens.
## Some open two, so the road branches inside a sector and rejoins before the
## last level (the sector's boss, index 5). One template per sector, picked
## by its seed; the first sector is always the first template.
const SECTOR_GRAPHS: Array = [
	[[1, 2], [3], [3], [4], [5], []],
	[[1], [2, 3], [4], [4], [5], []],
	[[1, 2], [3], [4], [5], [5], []],
	[[1, 2], [3, 4], [4], [5], [5], []],
]
## Stars are the only key to a level: it opens once the campaign's total
## reaches [method stars_needed]. The first [constant FREE_LEVELS] are free;
## after that a level asks for a share of every star the levels before it
## could have paid (3 each), a share that climbs toward [constant
## STAR_SHARE_MAX] with time constant [constant STAR_SHARE_RAMP] levels. The
## result: level 4 wants 1, level 10 about 12, level 20 about 35, level 30
## about 56 — near two stars a level in the long run, so a pilot who scrapes
## through everything has to go back for better runs, and one who plays well
## can skip ahead.
const FREE_LEVELS := 3
## Eras: from level [constant ERA_START], every [constant ERA_LEVELS] levels
## the enemies step up at once — hull ×[constant ERA_HP_STEP] and damage
## ×[constant ERA_DAMAGE_STEP] per era, on top of the slow climb — so a
## starter ship with every pip bought starts to feel thin around level 20 and
## outclassed by 30, and the garage's bigger hulls earn their price.
const ERA_START := 20
const ERA_LEVELS := 10
const ERA_HP_STEP := 1.22
const ERA_DAMAGE_STEP := 1.12
const STAR_SHARE_MAX := 0.65
const STAR_SHARE_RAMP := 6.0

enum Turf { WILDS, PIRATE, TRADE, MILITARY, SWARM }

## One letter per theme: the route string is these letters joined by ".".
const THEME_CODES: Array[String] = ["W", "P", "T", "M", "S"]
const THEME_NAMES: Array[String] = ["THE WILDS", "PIRATE TURF", "TRADE LANES", "WAR ZONE", "BUG NEST"]
const THEME_COLORS: Array[Color] = [
	Color("7dff3a"), Color("ff3a6e"), Color("ffc61a"), Color("35a8ff"), Color("c65bff"),
]

## Scenario ids each theme draws from, with weights. The ids are the
## flight module's [code]FlightScenarios[/code] preset ids.
const THEME_KINDS := {
	Turf.WILDS: {"race": 3, "salvage": 3, "courier": 2, "voyage": 2, "survive": 1, "duel": 1},
	Turf.PIRATE: {"skirmish": 3, "ambush": 2, "escort": 2, "duel": 2, "assault": 1, "protect": 1},
	Turf.TRADE: {"courier": 3, "salvage": 2, "dock": 2, "escort": 2, "protect": 2, "race": 1, "voyage": 1},
	Turf.MILITARY: {"battle": 3, "capital": 2, "assault": 2, "survive": 1, "skirmish": 1, "protect": 1},
	Turf.SWARM: {"waves": 3, "survive": 2, "battle": 1, "ambush": 2},
}

## Who the enemies are, per theme ([code]FlightScenarios.FIGHTER_ARCHETYPES[/code] keys).
const THEME_FOES := {
	Turf.WILDS: ["Lone wolves", "Swarm"],
	Turf.PIRATE: ["Pirates", "Lone wolves"],
	Turf.TRADE: ["Pirates", "Police patrol"],
	Turf.MILITARY: ["Military squad", "Strike team"],
	Turf.SWARM: ["Swarm"],
}

## The type of ship a kind of level may ask for (when it asks at all).
const KIND_SHIP := {
	"courier": ShipCatalog.Type.SCOUT, "race": ShipCatalog.Type.SCOUT,
	"salvage": ShipCatalog.Type.HAULER, "dock": ShipCatalog.Type.HAULER,
	"escort": ShipCatalog.Type.TANK, "capital": ShipCatalog.Type.TANK,
	"assault": ShipCatalog.Type.TITAN, "duel": ShipCatalog.Type.FIGHTER,
	"skirmish": ShipCatalog.Type.FIGHTER, "ambush": ShipCatalog.Type.FIGHTER,
	"battle": ShipCatalog.Type.TANK, "waves": ShipCatalog.Type.FIGHTER,
	"survive": ShipCatalog.Type.TANK, "boss": ShipCatalog.Type.FIGHTER,
	"protect": ShipCatalog.Type.TANK, "voyage": ShipCatalog.Type.SCOUT,
}

## Short word + icon id for each kind: what the report and the card show.
const KIND_INFO := {
	"practice": {"word": "SHOOT", "icon": "target"},
	"duel": {"word": "DUEL", "icon": "target"},
	"skirmish": {"word": "FIGHT", "icon": "target"},
	"ambush": {"word": "AMBUSH", "icon": "target"},
	"battle": {"word": "BATTLE", "icon": "target"},
	"waves": {"word": "WAVES", "icon": "target"},
	"survive": {"word": "SURVIVE", "icon": "clock"},
	"courier": {"word": "DELIVER", "icon": "box"},
	"race": {"word": "RACE", "icon": "ring"},
	"salvage": {"word": "SALVAGE", "icon": "box"},
	"dock": {"word": "DOCK", "icon": "dock"},
	"escort": {"word": "ESCORT", "icon": "shield"},
	"capital": {"word": "ESCORT", "icon": "shield"},
	"assault": {"word": "WRECK IT", "icon": "target"},
	"boss": {"word": "BOSS", "icon": "target"},
	"protect": {"word": "PROTECT", "icon": "shield"},
	"voyage": {"word": "VOYAGE", "icon": "ring"},
}

## What to do, in a few words, for each kind: the pause card's brief.
const KIND_BRIEF := {
	"practice": "Wreck the target drones.",
	"duel": "Beat the lone pilot.",
	"skirmish": "Wreck every enemy ship.",
	"ambush": "They jumped you. Wreck them all.",
	"battle": "Big fight. Wreck their side.",
	"waves": "Wreck every wave.",
	"survive": "Stay alive till the clock runs out.",
	"courier": "Grab every cargo package. Any order.",
	"race": "Fly through every ring. Any order.",
	"salvage": "Grab all the cargo pods.",
	"dock": "Fly into the carrier's bay and stop.",
	"escort": "Keep the hauler alive. Guard it.",
	"capital": "Keep the big ship alive till it's home.",
	"assault": "Wreck the mothership.",
	"boss": "A huge warship blocks the road. Wreck it.",
	"protect": "A stranded hauler. Keep it alive till the clock runs out.",
	"voyage": "Fly all the way out to the far planet.",
}

## Planet looks (the flight scene's SpaceScene.LOOKS ids) a theme's main
## world is drawn from; the other two worlds take any look.
const THEME_LOOKS := {
	Turf.WILDS: ["ice", "rock", "lush", "ocean"],
	Turf.PIRATE: ["lava", "desert", "rock"],
	Turf.TRADE: ["lush", "ocean", "gas"],
	Turf.MILITARY: ["desert", "rock", "gas_blue"],
	Turf.SWARM: ["toxic", "candy", "lava"],
}
const ALL_LOOKS: Array[String] = ["lush", "desert", "ice", "lava", "toxic", "candy", "ocean", "rock", "gas", "gas_blue"]
## Incidents a sandbox system can have going on (the events module's ids).
const SANDBOX_EVENTS: Array[String] = ["pirate_raid", "meteor_strike", "faction_skirmish", "distress_call", "derelict_tumble", "rare_drift", "cargo_request"]

## Background and subject picture tags per theme and kind (see the menu
## module's PicSet, which maps a tag + roll to a baked picture).
const THEME_BG := {
	Turf.WILDS: ["belt", "planet", "ice"],
	Turf.PIRATE: ["sun", "belt", "planet"],
	Turf.TRADE: ["planet", "gas", "ice"],
	Turf.MILITARY: ["planet", "sun", "gas"],
	Turf.SWARM: ["nebula", "sun", "gas"],
}
const KIND_FG := {
	"practice": "ships", "duel": "ships", "skirmish": "boom", "ambush": "boom",
	"battle": "boom", "waves": "boom", "survive": "boom", "courier": "pods",
	"race": "rings", "salvage": "pods", "dock": "carrier", "escort": "carrier",
	"capital": "carrier", "assault": "boom", "boss": "boom", "protect": "carrier", "voyage": "ships",
}

## The first sector is the tutorial road: the same kinds in order for
## everyone, one idea each (level-setup.md §3), ending on its boss.
const ONBOARDING: Array[String] = ["practice", "courier", "race", "duel", "salvage", "boss"]
## The kinds that are a fight: they get the level's scenery and mixed foes.
const FIGHT_KINDS: Array[String] = [
	"duel", "skirmish", "ambush", "battle", "waves", "survive", "escort", "capital", "assault", "boss",
	"protect",
]
## Who else can turn up beside a level's main foes ([code]FlightScenarios.FIGHTER_ARCHETYPES[/code] keys).
const FOE_MIX := {
	"Pirates": ["Lone wolves", "Strike team"],
	"Lone wolves": ["Pirates"],
	"Swarm": ["Lone wolves", "Pirates"],
	"Police patrol": ["Strike team"],
	"Military squad": ["Strike team"],
	"Strike team": ["Military squad"],
}

const WORDS_ADJ := {
	Turf.WILDS: ["Drifty", "Lonely", "Wobbly", "Frosty", "Dusty", "Quiet"],
	Turf.PIRATE: ["Angry", "Rusty", "Greedy", "Sneaky", "Loud", "Salty"],
	Turf.TRADE: ["Fragile", "Late", "Heavy", "Shiny", "Lost", "Priority"],
	Turf.MILITARY: ["Iron", "Final", "Big", "Red", "Heavy", "Loud"],
	Turf.SWARM: ["Buzzing", "Hungry", "Itchy", "Endless", "Sticky", "Twitchy"],
}
const WORDS_NOUN := {
	Turf.WILDS: ["Drift", "Rocks", "Comet", "Void", "Moon", "Detour"],
	Turf.PIRATE: ["Heist", "Grudge", "Ruckus", "Plunder", "Cutlass", "Payday"],
	Turf.TRADE: ["Parcel", "Cargo", "Shortcut", "Run", "Delivery", "Haul"],
	Turf.MILITARY: ["Front", "Push", "Barrage", "Line", "Brass", "Salute"],
	Turf.SWARM: ["Hive", "Nest", "Swarm", "Buzz", "Brood", "Bloom"],
}
const SECTOR_WORDS := {
	Turf.WILDS: ["THE BELT", "DUST REACH", "COMET ROW", "COLD EDGE"],
	Turf.PIRATE: ["PIRATE COVE", "SCRAP ALLEY", "RED DOCKS", "SKULL RUN"],
	Turf.TRADE: ["OUTPOST", "CARGO LANE", "FREE PORT", "HUB"],
	Turf.MILITARY: ["FRONT LINE", "FORT", "BASTION", "NO FLY"],
	Turf.SWARM: ["NEBULA RUN", "THE NEST", "HIVE", "BUZZ BELT"],
}


# --- Keys & seeds ---------------------------------------------------------------

## The route string for a list of themes: "W.P.T".
static func route_code(route: Array) -> String:
	var parts: Array[String] = []
	for t in route:
		parts.append(THEME_CODES[clampi(int(t), 0, THEME_CODES.size() - 1)])
	return ".".join(parts)


## Parse a route string back into themes. Unknown letters are dropped.
static func parse_route(code: String) -> Array[int]:
	var out: Array[int] = []
	if code == "":
		return out
	for letter in code.split("."):
		var t := THEME_CODES.find(letter)
		if t >= 0:
			out.append(t)
	return out


## Stars the whole campaign must hold before level [param number] (1-based)
## opens. Never falls as the number rises (see [constant FREE_LEVELS]).
static func stars_needed(number: int) -> int:
	if number <= FREE_LEVELS:
		return 0
	var could_have := 3.0 * float(number - 1)
	var share := STAR_SHARE_MAX * (1.0 - exp(-float(number - FREE_LEVELS) / STAR_SHARE_RAMP))
	return maxi(1, roundi(could_have * share))


## Which era level [param number] is in: 0 before [constant ERA_START], then
## one more every [constant ERA_LEVELS] levels.
static func era_of(number: int) -> int:
	if number < ERA_START:
		return 0
	return 1 + (number - ERA_START) / ERA_LEVELS


## A level's key: the route that reaches its sector, then its index there.
static func level_key(route: Array, index: int) -> String:
	return "%s:%d" % [route_code(route), index]


## The deterministic seed for any string. [method String.hash] is djb2 —
## the same on every platform — mixed with the grammar version.
static func seed_of(text: String) -> int:
	return ("yeetfleet/v%d/%s" % [GRAMMAR_VERSION, text]).hash()


static func _rng(text: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_of(text)
	return r


# --- Sectors ------------------------------------------------------------------

## The theme every campaign starts in.
static func first_theme() -> int:
	return Turf.WILDS


## A sector reached by [param route] (its last entry is this sector's own
## theme): name, theme, depth, key and its levels.
static func sector(route: Array) -> Dictionary:
	var depth := route.size() - 1
	var theme := int(route[depth])
	var r := _rng("sector/" + route_code(route))
	var pool: Array = SECTOR_WORDS[theme]
	var name := String(pool[r.randi_range(0, pool.size() - 1)])
	# An outpost has a number, like the reference map's "OUTPOST 9".
	if name in ["OUTPOST", "FORT", "HUB"]:
		name += " %d" % r.randi_range(2, 99)
	if depth == 0:
		name = "THE BELT"
	var levels: Array[Dictionary] = []
	for i in LEVELS_PER_SECTOR:
		levels.append(level(route, i))
	return {
		"route": route.duplicate(), "key": route_code(route), "depth": depth,
		"theme": theme, "name": name, "color": THEME_COLORS[theme],
		"levels": levels,
	}


## The two themes the road forks into after the sector [param route] ends:
## one the seed picks, one [param style_theme] (the player's play style)
## picks. Never the same two, never both the theme just played.
static func fork_options(route: Array, style_theme: int) -> Array[int]:
	var here := int(route[route.size() - 1])
	var r := _rng("fork/" + route_code(route))
	var seeded := here
	while seeded == here:
		seeded = r.randi_range(0, Turf.size() - 1)
	var others: Array[int] = []
	for t in Turf.size():
		if t != here and t != seeded:
			others.append(t)
	var styled := style_theme if style_theme in others else others[r.randi_range(0, others.size() - 1)]
	var out: Array[int] = [seeded, styled]
	return out


## The link template of the sector reached by [param route].
static func sector_graph(route: Array) -> Array:
	if route.size() <= 1:
		return SECTOR_GRAPHS[0]
	var r := _rng("graph/" + route_code(route))
	return SECTOR_GRAPHS[r.randi_range(0, SECTOR_GRAPHS.size() - 1)]


## The levels in the same sector whose win opens level [param index].
static func predecessors(route: Array, index: int) -> Array[int]:
	var g := sector_graph(route)
	var out: Array[int] = []
	for i in g.size():
		if index in (g[i] as Array):
			out.append(i)
	return out


## Each level's column in its sector's graph (0 = the entry, rising by one
## per link), for laying the graph out.
static func graph_layers(route: Array) -> Array[int]:
	var g := sector_graph(route)
	var layer: Array[int] = []
	layer.resize(g.size())
	layer.fill(0)
	for i in g.size():
		for j in (g[i] as Array):
			layer[int(j)] = maxi(layer[int(j)], layer[i] + 1)
	return layer


# --- Levels -------------------------------------------------------------------

## Level [param index] of the sector reached by [param route]. Everything
## about it comes from its key's seed and its global number (difficulty).
static func level(route: Array, index: int) -> Dictionary:
	var depth := route.size() - 1
	var theme := int(route[depth])
	var key := level_key(route, index)
	var number := depth * LEVELS_PER_SECTOR + index + 1
	var r := _rng("level/" + key)
	var kind := ONBOARDING[index] if depth == 0 else _weighted(r, THEME_KINDS[theme])
	# The last level before the road forks is always the sector's boss.
	if index == LEVELS_PER_SECTOR - 1:
		kind = "boss"
	# 0 at level 1, 1 around level 40; keeps creeping after that.
	var d := clampf(float(number - 1) / 40.0, 0.0, 1.6)
	var foes: Array = THEME_FOES[theme]
	var arch := String(foes[r.randi_range(0, foes.size() - 1)])
	var o := _overrides(kind, d, r, arch)
	# The climb (see [Difficulty]): every level a step up — hull, damage,
	# size, aggression, gun class, how many may shoot at once, dreadnoughts.
	# Its own roll, so the level's other numbers are what they always were.
	var climb := Difficulty.for_level(number, kind, _rng("climb/" + key).randf())
	o["enemy_hp"] = snappedf(float(o["enemy_hp"]) * float(climb["hp_mult"]), 0.05)
	o["enemy_damage"] = snappedf(float(o["enemy_damage"]) * float(climb["damage_mult"]), 0.05)
	if int(o.get("enemies", 0)) > 0 and kind != "duel" and kind != "practice":
		o["enemies"] = int(o["enemies"]) + int(climb["extra_enemies"])
	for k: String in climb:
		if not k in ["hp_mult", "damage_mult", "extra_enemies"]:
			o[k] = climb[k]
	if climb.has("ace_hp"):
		o["enemy_hp"] = snappedf(float(o["enemy_hp"]) / 1.4 * float(climb["ace_hp"]), 0.05)
	var era := era_of(number)
	if era > 0:
		o["enemy_hp"] = snappedf(float(o["enemy_hp"]) * pow(ERA_HP_STEP, era), 0.05)
		o["enemy_damage"] = snappedf(float(o["enemy_damage"]) * pow(ERA_DAMAGE_STEP, era), 0.05)
		if o.has("boss_hp"):
			o["boss_hp"] = snappedf(float(o["boss_hp"]) * pow(ERA_HP_STEP, era), 0.05)
	# Guard missions come with wingmen most of the time. Its own roll, so
	# the level's other numbers are what they always were.
	if kind in ["escort", "capital"] and _rng("allies/" + key).randf() < 0.8:
		o["allies"] = maxi(int(o.get("allies", 0)), 2)
	# A fight is never just the fight: other kinds of foe, neutral giants
	# drifting through, a megastructure out in the distance. Their own roll.
	if kind in FIGHT_KINDS:
		if kind != "duel" and (depth > 0 or index >= 3):
			o["enemy_mix"] = FOE_MIX.get(arch, [])
		# No neutral giants drifting through: a big ship on screen should be
		# part of the job (the boss, the ship to guard), never scenery that
		# reads as a target. The far-off megastructure only frames a boss.
		o["bystanders"] = 0
		if kind == "boss":
			o["backdrop"] = 1
	# Some levels insist on a type of ship; never in the first sector.
	var ship_type := -1
	if depth > 0 and r.randf() < 0.3 and KIND_SHIP.has(kind):
		ship_type = int(KIND_SHIP[kind])
	var adj: Array = WORDS_ADJ[theme]
	var noun: Array = WORDS_NOUN[theme]
	var title := "%s %s" % [adj[r.randi_range(0, adj.size() - 1)], noun[r.randi_range(0, noun.size() - 1)]]
	var bgs: Array = THEME_BG[theme]
	var info: Dictionary = KIND_INFO.get(kind, {"word": "FLY", "icon": "target"})
	o["name"] = title
	return {
		"key": key, "route": route_code(route), "index": index, "number": number,
		"theme": theme, "kind": kind, "title": title,
		"word": String(info["word"]), "icon": String(info["icon"]),
		# 1–5 skulls: how hard the numbers make it.
		"danger": clampi(1 + int(d * 3.0) + era + (1 if kind in ["ambush", "assault", "capital", "boss"] else 0), 1, 5),
		"era": era,
		"ship_type": ship_type,
		"stars_req": stars_needed(number),
		"unlocks": (sector_graph(route)[index] as Array).duplicate(),
		"par": _par_time(kind, o),
		# How its stars are earned: hull, speed, the guarded ship — weighted
		# per level, with bars that rise with difficulty (see StarRating).
		"grade": StarRating.grade_for(kind, d, seed_of("grade/" + key),
			Difficulty.v("fight_weight") if kind in Difficulty.KILL_GRADED else 0.0, Difficulty.v("star_bar_bonus")),
		"reward": 40 + number * 12,
		"preset": kind,
		"overrides": o,
		"pic": {
			# Walk the theme's backgrounds through the sector, so neighbouring
			# cards never share a picture.
			"bg": String(bgs[(index + posmod(seed_of(route_code(route)), bgs.size())) % bgs.size()]),
			"fg": String(KIND_FG.get(kind, "ships")),
			"roll": r.randi_range(0, 9999),
			"flip": r.randf() < 0.5,
		},
		"space": space_setup(key, theme),
	}


## The system a level is flown in ([member Session.space_setup]): its own
## planets, sizes and layout from the level's key, the main world's look
## from the theme. The same key always gives the same system.
static func space_setup(key: String, theme: int) -> Dictionary:
	var r := _rng("space/" + key)
	var mains: Array = THEME_LOOKS.get(theme, ALL_LOOKS)
	return _space(r, String(mains[r.randi_range(0, mains.size() - 1)]))


## A fresh random system for the sandbox: any looks, any sizes, and a few
## incidents going on.
static func random_space(seed_val: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	var out := _space(r, ALL_LOOKS[r.randi_range(0, ALL_LOOKS.size() - 1)])
	var events: Array[String] = []
	for i in r.randi_range(1, 3):
		var e := SANDBOX_EVENTS[r.randi_range(0, SANDBOX_EVENTS.size() - 1)]
		if not e in events:
			events.append(e)
	out["events"] = events
	return out


static func _space(r: RandomNumberGenerator, main_look: String) -> Dictionary:
	return {
		"seed": r.randi(),
		"looks": [main_look, ALL_LOOKS[r.randi_range(0, ALL_LOOKS.size() - 1)], ALL_LOOKS[r.randi_range(0, ALL_LOOKS.size() - 1)], "rock"],
		"sizes": [r.randf_range(0.6, 1.5), r.randf_range(0.5, 1.8), r.randf_range(0.5, 1.8)],
		"yaw": r.randf_range(0.0, TAU),
		"rocks": r.randf_range(0.4, 1.6),
		"rings": r.randf() < 0.3,
	}


## The level a key names, or {} when the key does not parse.
static func from_key(key: String) -> Dictionary:
	var colon := key.rfind(":")
	if colon <= 0:
		return {}
	var route := parse_route(key.substr(0, colon))
	var idx := key.substr(colon + 1)
	if route.is_empty() or not idx.is_valid_int():
		return {}
	return level(route, clampi(idx.to_int(), 0, LEVELS_PER_SECTOR - 1))


## Scenario dial overrides for a kind at difficulty [param d] (0..1.6).
static func _overrides(kind: String, d: float, r: RandomNumberGenerator, arch: String) -> Dictionary:
	# Enemies start at full strength (they used to start at 0.6 hull and half
	# damage, which made the early game a walk) and keep climbing.
	var o := {
		"enemy_hp": snappedf(lerpf(1.0, 2.0, d / 1.6), 0.05),
		"enemy_damage": snappedf(lerpf(0.85, 1.7, d / 1.6), 0.05),
		"enemy_arch": arch,
	}
	var extra := 1 + int(d * 3.0)
	match kind:
		"practice":
			o["enemies"] = 4
			o["enemy_arch"] = "Swarm"
		"duel":
			o["enemies"] = 1
			o["enemy_hp"] = snappedf(o["enemy_hp"] * 1.4, 0.05)
		"skirmish":
			o["enemies"] = 2 + extra
			o["allies"] = 2
		"ambush":
			o["enemies"] = 4 + extra
			o["enemy_distance"] = r.randf_range(300.0, 450.0)
		"battle":
			o["enemies"] = 4 + extra
			o["allies"] = 3 + extra
		"waves":
			o["enemies"] = 2
			o["waves"] = 3 + extra
		"survive":
			o["enemies"] = 3 + extra
			o["survive_time"] = 45.0 + d * 40.0
		"courier":
			o["enemies"] = 0 if d < 0.3 else 1 + extra
			o["points"] = 2 + mini(extra, 3)
			# Only some deliveries are against the clock, and never early on.
			if d >= 0.3 and r.randf() < 0.35:
				o["time_limit"] = 200.0 + 60.0 * (o["points"] - 2)
		"race":
			# A race is a race: always timed, but generously.
			o["gates"] = 5 + mini(extra * 2, 6)
			o["time_limit"] = maxf(75.0, 100.0 + o["gates"] * 6.0 - d * 15.0)
		"salvage":
			o["pods"] = 4 + mini(extra, 4)
			o["enemies"] = 0 if d < 0.4 else 1 + extra
			if d >= 0.3 and r.randf() < 0.3:
				o["time_limit"] = 180.0
		"dock":
			o["route"] = r.randf_range(1800.0, 3000.0)
			o["enemies"] = 0 if d < 0.5 else 2
		"escort":
			o["enemies"] = 2 + extra
			o["wave_every"] = maxf(14.0, 26.0 - d * 8.0)
		"capital":
			o["enemies"] = 3 + extra
			o["allies"] = 2
			o["wave_every"] = maxf(16.0, 28.0 - d * 8.0)
		"protect":
			o["enemies"] = 2 + extra
			o["wave_every"] = maxf(12.0, 20.0 - d * 6.0)
			o["hold_time"] = roundf(55.0 + d * 30.0)
		"voyage":
			# Mostly a trip; later on, someone is out there too.
			o["enemies"] = 0 if d < 0.4 else extra
			if d >= 0.3 and r.randf() < 0.4:
				o["time_limit"] = 150.0
		"assault":
			o["enemies"] = 2 + extra
			o["allies"] = 2
		"boss":
			o["enemies"] = 1 + extra
			o["allies"] = 2
			o["boss_size"] = snappedf(3.0 + d * 1.5, 0.1)
			o["boss_hp"] = snappedf(lerpf(0.7, 1.8, d / 1.6), 0.05)
			o["boss_reinforce"] = maxf(16.0, 30.0 - d * 10.0)
	return o


## Seconds a clean run should take — the third star's bar.
static func _par_time(kind: String, o: Dictionary) -> float:
	if o.has("time_limit"):
		return roundf(float(o["time_limit"]) * 0.65)
	match kind:
		"survive":
			return float(o.get("survive_time", 60.0)) + 1.0
		"courier":
			return 70.0 + 35.0 * float(o.get("points", 2))
		"salvage":
			return 40.0 + 18.0 * float(o.get("pods", 4))
		"escort", "capital", "dock":
			return 150.0
		"waves", "battle", "boss":
			return 120.0
	return 75.0


static func _weighted(r: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0
	for k in table:
		total += int(table[k])
	var pick := r.randi_range(0, total - 1)
	for k in table:
		pick -= int(table[k])
		if pick < 0:
			return String(k)
	return String(table.keys()[0])
