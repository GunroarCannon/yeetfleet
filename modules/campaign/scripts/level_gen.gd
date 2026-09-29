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
## Stars a level asks for (in total, across the whole campaign) per level
## number — gates to make a player go back for better runs now and then.
const STAR_GATE_PER_LEVEL := 1.15

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
	Turf.WILDS: {"race": 3, "salvage": 3, "courier": 2, "survive": 1, "duel": 1},
	Turf.PIRATE: {"skirmish": 3, "ambush": 2, "escort": 2, "duel": 2, "assault": 1},
	Turf.TRADE: {"courier": 3, "salvage": 2, "dock": 2, "escort": 2, "race": 1},
	Turf.MILITARY: {"battle": 3, "capital": 2, "assault": 2, "survive": 1, "skirmish": 1},
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
	"survive": ShipCatalog.Type.TANK,
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
}

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
	"capital": "carrier", "assault": "boom",
}

## The first sector is the tutorial road: the same five kinds in order for
## everyone, one idea each (level-setup.md §3).
const ONBOARDING: Array[String] = ["practice", "courier", "race", "duel", "salvage", "skirmish"]

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
	# 0 at level 1, 1 around level 40; keeps creeping after that.
	var d := clampf(float(number - 1) / 40.0, 0.0, 1.6)
	var foes: Array = THEME_FOES[theme]
	var arch := String(foes[r.randi_range(0, foes.size() - 1)])
	var o := _overrides(kind, d, r, arch)
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
		"danger": clampi(1 + int(d * 3.0) + (1 if kind in ["ambush", "assault", "capital"] else 0), 1, 5),
		"ship_type": ship_type,
		"stars_req": maxi(0, int(float(number - 3) * STAR_GATE_PER_LEVEL)) if number > 3 else 0,
		"unlocks": (sector_graph(route)[index] as Array).duplicate(),
		"par": _par_time(kind, o),
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
	var o := {
		"enemy_hp": snappedf(lerpf(0.6, 1.5, d / 1.6), 0.05),
		"enemy_damage": snappedf(lerpf(0.5, 1.4, d / 1.6), 0.05),
		"enemy_arch": arch,
	}
	var extra := int(d * 3.0)
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
		"assault":
			o["enemies"] = 2 + extra
			o["allies"] = 2
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
		"waves", "battle":
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
