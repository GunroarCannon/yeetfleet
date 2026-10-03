## ShipCatalog: every ship the garage can show — which preset hull it flies,
## which paint it wears, what type it is, what it costs and what each of its
## upgrade pips is worth.
##
## Pure data. A ship here is a preset id from `data/presets/ship_families.json`
## plus a faction paint, so the garage, the level report and the flight scene
## all build the exact same hull from two strings. Adding a ship is one row.
class_name ShipCatalog
extends RefCounted

## The ship types a level can ask for. Same order as [constant TYPE_NAMES].
enum Type { SCOUT, FIGHTER, TANK, HAULER, TITAN }

const TYPE_NAMES: Array[String] = ["SCOUT", "FIGHTER", "TANK", "HAULER", "TITAN"]
## One colour per type: the chip behind the type name everywhere it is shown.
const TYPE_COLORS: Array[Color] = [
	Color("35e0ff"), Color("ff5b3a"), Color("9d6bff"), Color("ffc61a"), Color("7dff3a"),
]

## The four upgrade tracks, in display order.
const STATS: Array[String] = ["hull", "guns", "speed", "yeet"]
const STAT_NAMES: Array[String] = ["HULL", "GUNS", "SPEED", "YEET"]
## Pips per track. The last pip is the cap.
const MAX_PIPS := 5

## How much one pip adds, per type and track — the same pip is worth a
## different amount on a different hull: a scout's speed pip is big, a titan's
## small, and the other way round for hull.
const PIP_GAIN := {
	Type.SCOUT: {"hull": 0.08, "guns": 0.08, "speed": 0.10, "yeet": 0.10},
	Type.FIGHTER: {"hull": 0.10, "guns": 0.14, "speed": 0.07, "yeet": 0.10},
	Type.TANK: {"hull": 0.16, "guns": 0.10, "speed": 0.05, "yeet": 0.14},
	Type.HAULER: {"hull": 0.14, "guns": 0.06, "speed": 0.06, "yeet": 0.20},
	Type.TITAN: {"hull": 0.20, "guns": 0.12, "speed": 0.04, "yeet": 0.16},
}
## What a pip costs: pip n (0-based) costs this × (n + 1) × the ship's tier.
const PIP_BASE_COST := 60

## Every ship, in garage order. `price` 0 = owned from the start.
## `base` is the ship's own 1–5 rating per track before any pips — the bars
## the garage draws. `tier` scales upgrade prices.
const SHIPS: Array[Dictionary] = [
	{
		"id": "kestrel", "name": "Kestrel", "preset": "kestrel_courier",
		"paint": "neon_turbo", "type": Type.SCOUT, "price": 0, "tier": 1,
		"base": {"hull": 1, "guns": 2, "speed": 4, "yeet": 2},
	},
	{
		"id": "lance", "name": "Lance", "preset": "lance_interceptor",
		"paint": "crimson_toybox", "type": Type.FIGHTER, "price": 0, "tier": 1,
		"base": {"hull": 2, "guns": 3, "speed": 3, "yeet": 2},
	},
	{
		"id": "mule", "name": "Mule", "preset": "mule_freighter",
		"paint": "vega_industrial", "type": Type.HAULER, "price": 350, "tier": 1,
		"base": {"hull": 3, "guns": 1, "speed": 2, "yeet": 4},
	},
	{
		"id": "bulwark", "name": "Bulwark", "preset": "bulwark_patrol",
		"paint": "cobalt_vanguard", "type": Type.TANK, "price": 600, "tier": 2,
		"base": {"hull": 4, "guns": 3, "speed": 2, "yeet": 3},
	},
	{
		"id": "zipper", "name": "Zipper", "preset": "kestrel_courier",
		"paint": "cyber_teal", "type": Type.SCOUT, "price": 800, "tier": 2,
		"base": {"hull": 2, "guns": 2, "speed": 5, "yeet": 3},
	},
	{
		"id": "stinger", "name": "Stinger", "preset": "lance_interceptor",
		"paint": "amethyst_void", "type": Type.FIGHTER, "price": 1100, "tier": 2,
		"base": {"hull": 2, "guns": 4, "speed": 4, "yeet": 2},
	},
	{
		"id": "privateer", "name": "Privateer", "preset": "mule_privateer",
		"paint": "solar_raiders", "type": Type.HAULER, "price": 1400, "tier": 2,
		"base": {"hull": 3, "guns": 3, "speed": 2, "yeet": 5},
	},
	{
		"id": "digger", "name": "Digger", "preset": "bulwark_prospector",
		"paint": "emerald_warlords", "type": Type.TANK, "price": 1900, "tier": 3,
		"base": {"hull": 5, "guns": 3, "speed": 2, "yeet": 4},
	},
	{
		"id": "hotrod", "name": "Hot Rod", "preset": "lance_interceptor",
		"paint": "solar_raiders", "type": Type.FIGHTER, "price": 2600, "tier": 3,
		"base": {"hull": 3, "guns": 5, "speed": 4, "yeet": 3},
	},
	{
		"id": "keel", "name": "Keel", "preset": "keel_dreadnought",
		"paint": "kethral_compact", "type": Type.TITAN, "price": 4000, "tier": 4,
		"base": {"hull": 5, "guns": 5, "speed": 1, "yeet": 5},
	},
	{
		"id": "bigboy", "name": "Big Boy", "preset": "keel_dreadnought",
		"paint": "crimson_toybox", "type": Type.TITAN, "price": 6500, "tier": 5,
		"base": {"hull": 5, "guns": 5, "speed": 2, "yeet": 5},
	},
]


## Every ship id, in garage order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for s in SHIPS:
		out.append(String(s["id"]))
	return out


## The row for [param id], or an empty dictionary when unknown.
static func get_ship(id: String) -> Dictionary:
	for s in SHIPS:
		if String(s["id"]) == id:
			return s
	return {}


static func has(id: String) -> bool:
	return not get_ship(id).is_empty()


static func type_of(id: String) -> int:
	return int(get_ship(id).get("type", Type.FIGHTER))


static func type_name(t: int) -> String:
	return TYPE_NAMES[clampi(t, 0, TYPE_NAMES.size() - 1)]


static func type_color(t: int) -> Color:
	return TYPE_COLORS[clampi(t, 0, TYPE_COLORS.size() - 1)]


## The cheapest ship of type [param t] — the loaner a level hands out when
## the player owns nothing of the type it asks for.
static func loaner_for(t: int) -> String:
	var best := ""
	var best_price := 1 << 30
	for s in SHIPS:
		if int(s["type"]) == t and int(s["price"]) < best_price:
			best = String(s["id"])
			best_price = int(s["price"])
	return best


## What pip number [param pip] (0-based) of [param stat] costs on [param id].
static func pip_cost(id: String, stat: String, pip: int) -> int:
	var s := get_ship(id)
	var tier := int(s.get("tier", 1))
	# Guns and hull are the popular ones; they cost a little more.
	var weight := 1.2 if stat in ["hull", "guns"] else 1.0
	return int(round(PIP_BASE_COST * (pip + 1) * tier * weight / 10.0)) * 10


## The flight multiplier [param pips] upgrade pips of [param stat] give ship
## [param id], on top of what its design already flies like.
static func stat_mult(id: String, stat: String, pips: int) -> float:
	var t := type_of(id)
	var gain := float((PIP_GAIN.get(t, {}) as Dictionary).get(stat, 0.1))
	return 1.0 + gain * clampi(pips, 0, MAX_PIPS)


## The bar the garage draws for a track: the ship's own rating plus a
## fraction per pip, out of [constant MAX_PIPS] + its base.
static func rating(id: String, stat: String) -> int:
	return int((get_ship(id).get("base", {}) as Dictionary).get(stat, 1))


# --- Rank --------------------------------------------------------------------

## The rank letters, worst to best; each has a plain, + and ++ step.
const RANK_LETTERS: Array[String] = ["F", "E", "D", "C", "B", "A", "AA", "S", "SSS"]
## How much each track counts toward the rank: hull and guns matter most.
const RANK_WEIGHTS := {"hull": 1.3, "guns": 1.3, "speed": 1.0, "yeet": 0.8}


## The rank step (0 = F … 26 = SSS++) of ship [param id] with [param pips]
## ({stat: bought pips}). The weighted total of its tracks (rating + pips, out
## of ten) spread across every step, so a pip is worth a step or less.
static func rank_tier(id: String, pips: Dictionary) -> int:
	var sum := 0.0
	var weight := 0.0
	for st: String in STATS:
		var w := float(RANK_WEIGHTS.get(st, 1.0))
		sum += w * minf(float(rating(id, st) + int(pips.get(st, 0))), 10.0) / 10.0
		weight += w
	var steps := RANK_LETTERS.size() * 3
	return clampi(int(sum / maxf(weight, 0.001) * steps), 0, steps - 1)


## "B+", "SSS++" … for a rank step.
static func rank_name(tier: int) -> String:
	var t := clampi(tier, 0, RANK_LETTERS.size() * 3 - 1)
	return RANK_LETTERS[t / 3] + ["", "+", "++"][t % 3]


## The letter family's index (0 = F … 8 = SSS), for colouring.
static func rank_family(tier: int) -> int:
	return clampi(tier, 0, RANK_LETTERS.size() * 3 - 1) / 3
