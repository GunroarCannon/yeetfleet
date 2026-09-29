## Campaign: the player's progress through the generated campaign, and the
## garage behind it — coins, owned ships, upgrade pips, the route taken
## through the forks, and a record per level (attempts, wins, stars).
##
## The module's façade. The menu reads and spends through here; the flight
## scene never sees this class — a level is handed over as plain
## dictionaries on [Session] ([method launch]) and the result comes back the
## same way ([method take_result]).
##
## Saved as versioned JSON (`user://campaign.json`), migrated forward on load.
## Levels themselves are never saved: they regenerate from their keys
## ([LevelGen]), so only what the player did is on disk.
class_name Campaign
extends RefCounted

const SAVE_PATH := "user://campaign.json"
const SAVE_VERSION := 1
## Coins a fresh pilot starts with — enough to feel rich, not to buy much.
const START_COINS := 150
## A replayed win pays this fraction of the level's reward.
const REPLAY_PAY := 0.25
## Coins per star earned for the first time.
const STAR_BONUS := 25

## Emitted after anything a screen shows changes (coins, ships, records).
## A static class cannot own a signal, so this lives on a tiny notifier.
static var notifier := CampaignNotifier.new()

## Where saves go. A check points this at a scratch file.
static var save_path := SAVE_PATH

static var _data := {}
static var _loaded := false


# --- Load / save --------------------------------------------------------------

static func ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()


static func load_from_disk() -> void:
	_loaded = true
	_data = _fresh()
	if not FileAccess.file_exists(save_path):
		return
	var text := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Campaign: %s is not a save — starting fresh" % save_path)
		return
	var loaded := _migrate(parsed as Dictionary)
	# Fill anything a newer version added.
	for k in _data:
		if loaded.has(k):
			_data[k] = loaded[k]


static func save_to_disk() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Campaign: cannot write %s (%d)" % [save_path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()


## Wipe progress back to a fresh pilot (the Settings screen's reset).
static func reset() -> void:
	_data = _fresh()
	_loaded = true
	save_to_disk()
	notifier.changed.emit()


static func _fresh() -> Dictionary:
	var owned: Array = []
	for id in ShipCatalog.ids():
		if int(ShipCatalog.get_ship(id)["price"]) == 0:
			owned.append(id)
	return {
		"version": SAVE_VERSION,
		"pilot": "YEETERFLEETER",
		"coins": START_COINS,
		"owned": owned,
		"current": String(owned[0]) if not owned.is_empty() else "",
		"pips": {},
		"route": [LevelGen.THEME_CODES[LevelGen.first_theme()]],
		"levels": {},
		"stats": {"kills": 0, "fight_wins": 0, "cargo_wins": 0, "wins": 0, "flights": 0},
	}


## Old saves forward, one version at a time. Version 1 is the first; the
## ladder starts here so the next format change has somewhere to go.
static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		d["version"] = 1
	# The first builds named every pilot ACE.
	if String(d.get("pilot", "")) in ["", "ACE"]:
		d["pilot"] = "YEETERFLEETER"
	return d


# --- Wallet & pilot -----------------------------------------------------------

static func coins() -> int:
	ensure_loaded()
	return int(_data["coins"])


static func pilot_name() -> String:
	ensure_loaded()
	return String(_data["pilot"])


static func add_coins(amount: int) -> void:
	ensure_loaded()
	_data["coins"] = maxi(0, coins() + amount)
	save_to_disk()
	notifier.changed.emit()


# --- Garage -------------------------------------------------------------------

static func owns(id: String) -> bool:
	ensure_loaded()
	return id in (_data["owned"] as Array)


static func owned_ids() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	# Catalogue order, not purchase order, so the garage is stable.
	for id in ShipCatalog.ids():
		if owns(id):
			out.append(id)
	return out


static func current_ship() -> String:
	ensure_loaded()
	var id := String(_data["current"])
	if not owns(id):
		var list := owned_ids()
		id = list[0] if not list.is_empty() else ShipCatalog.ids()[0]
	return id


static func select_ship(id: String) -> bool:
	if not owns(id):
		return false
	_data["current"] = id
	save_to_disk()
	notifier.changed.emit()
	return true


## Buy [param id]. False (and nothing spent) when unaffordable or owned.
static func buy_ship(id: String) -> bool:
	ensure_loaded()
	if owns(id) or not ShipCatalog.has(id):
		return false
	var price := int(ShipCatalog.get_ship(id)["price"])
	if coins() < price:
		return false
	_data["coins"] = coins() - price
	(_data["owned"] as Array).append(id)
	_data["current"] = id
	save_to_disk()
	notifier.changed.emit()
	return true


static func pips(id: String, stat: String) -> int:
	ensure_loaded()
	return int(((_data["pips"] as Dictionary).get(id, {}) as Dictionary).get(stat, 0))


## What the next pip of [param stat] on [param id] costs, or -1 when maxed.
static func next_pip_cost(id: String, stat: String) -> int:
	var have := pips(id, stat)
	if have >= ShipCatalog.MAX_PIPS:
		return -1
	return ShipCatalog.pip_cost(id, stat, have)


static func buy_pip(id: String, stat: String) -> bool:
	ensure_loaded()
	var cost := next_pip_cost(id, stat)
	if cost < 0 or not owns(id) or coins() < cost:
		return false
	_data["coins"] = coins() - cost
	var all := _data["pips"] as Dictionary
	if not all.has(id):
		all[id] = {}
	(all[id] as Dictionary)[stat] = pips(id, stat) + 1
	save_to_disk()
	notifier.changed.emit()
	return true


## The ship a level will fly: the current ship when the level takes any type
## (or it is the right type), else the player's best owned ship of the type,
## else the type's loaner. `{"id", "loaner"}`.
static func ship_for(lvl: Dictionary) -> Dictionary:
	var want := int(lvl.get("ship_type", -1))
	var cur := current_ship()
	if want < 0 or ShipCatalog.type_of(cur) == want:
		return {"id": cur, "loaner": false}
	var best := ""
	for id in owned_ids():
		if ShipCatalog.type_of(id) == want:
			best = id
	if best != "":
		return {"id": best, "loaner": false}
	return {"id": ShipCatalog.loaner_for(want), "loaner": true}


## What the flight scene needs to build and tune [param id]: the preset hull,
## its paint and the upgrade multipliers. Loaners fly with no pips.
static func flight_ship(id: String, loaner := false) -> Dictionary:
	var s := ShipCatalog.get_ship(id)
	var mults := {}
	for stat in ShipCatalog.STATS:
		mults[stat] = ShipCatalog.stat_mult(id, stat, 0 if loaner else pips(id, stat))
	return {
		"id": id, "name": String(s.get("name", id)),
		"preset": String(s.get("preset", "")), "paint": String(s.get("paint", "")),
		"mults": mults,
	}


# --- Map ----------------------------------------------------------------------

static func route() -> Array[int]:
	ensure_loaded()
	var out: Array[int] = []
	for code in (_data["route"] as Array):
		var t := LevelGen.THEME_CODES.find(String(code))
		if t >= 0:
			out.append(t)
	if out.is_empty():
		out.append(LevelGen.first_theme())
	return out


## Every sector on the player's road so far, oldest first.
static func sectors() -> Array[Dictionary]:
	var r := route()
	var out: Array[Dictionary] = []
	for i in r.size():
		out.append(LevelGen.sector(r.slice(0, i + 1)))
	return out


## The record for a level key: attempts, wins, stars, best time.
static func record(key: String) -> Dictionary:
	ensure_loaded()
	var rec: Dictionary = (_data["levels"] as Dictionary).get(key, {})
	return {
		"attempts": int(rec.get("attempts", 0)), "wins": int(rec.get("wins", 0)),
		"stars": int(rec.get("stars", 0)), "best": float(rec.get("best", 0.0)),
	}


## Playable when its road is open (see [method road_open]) and the pilot has
## the stars it asks for.
static func is_unlocked(lvl: Dictionary) -> bool:
	return road_open(lvl) and total_stars() >= int(lvl.get("stars_req", 0))


## Whether a level linking into this one has been won: in its sector's graph,
## or — for a sector's first level — the previous sector's last. The very
## first level is always open.
static func road_open(lvl: Dictionary) -> bool:
	var idx := int(lvl.get("index", 0))
	var r := LevelGen.parse_route(String(lvl.get("route", "")))
	if idx > 0:
		for p in LevelGen.predecessors(r, idx):
			if record(LevelGen.level_key(r, p))["wins"] > 0:
				return true
		return false
	if r.size() <= 1:
		return true
	return record(LevelGen.level_key(r.slice(0, r.size() - 1), LevelGen.LEVELS_PER_SECTOR - 1))["wins"] > 0


## Stars earned across every level played.
static func total_stars() -> int:
	ensure_loaded()
	var n := 0
	for key in (_data["levels"] as Dictionary):
		n += int(((_data["levels"] as Dictionary)[key] as Dictionary).get("stars", 0))
	return n


## Whether the last sector on the road is finished, so the fork shows.
static func at_fork() -> bool:
	var r := route()
	return record(LevelGen.level_key(r, LevelGen.LEVELS_PER_SECTOR - 1))["wins"] > 0


## The two themes the road forks into next.
static func fork_options() -> Array[int]:
	return LevelGen.fork_options(route(), style_theme())


## Take the fork toward [param theme].
static func choose_fork(theme: int) -> void:
	if not at_fork() or not theme in fork_options():
		return
	(_data["route"] as Array).append(LevelGen.THEME_CODES[theme])
	save_to_disk()
	notifier.changed.emit()


## The theme the player's own play style earns: lots of wrecks and the pirates
## come looking; clean cargo runs and the traders call; otherwise the army.
static func style_theme() -> int:
	ensure_loaded()
	var st := _data["stats"] as Dictionary
	var wins := maxi(int(st.get("wins", 0)), 1)
	var kills_per_win := float(st.get("kills", 0)) / wins
	if kills_per_win >= 5.0:
		return LevelGen.Turf.PIRATE
	if int(st.get("cargo_wins", 0)) * 2 >= wins:
		return LevelGen.Turf.TRADE
	return LevelGen.Turf.MILITARY


## One word for the style, for the map's fork sign.
static func style_word() -> String:
	match style_theme():
		LevelGen.Turf.PIRATE:
			return "DANGEROUS"
		LevelGen.Turf.TRADE:
			return "RELIABLE"
	return "SOLDIER"


# --- Flights ------------------------------------------------------------------

## Hand a level to the flight scene: the scenario, the ship, and the key the
## result will come back under. The caller changes scene afterwards.
static func launch(lvl: Dictionary) -> void:
	var pick := ship_for(lvl)
	Session.pending_level = {
		"key": String(lvl["key"]), "preset": String(lvl["preset"]),
		"overrides": (lvl["overrides"] as Dictionary).duplicate(true),
		"title": String(lvl["title"]), "number": int(lvl["number"]),
		"par": float(lvl["par"]),
	}
	Session.pending_ship = flight_ship(String(pick["id"]), bool(pick["loaner"]))
	Session.level_result = {}


## Sandbox: free flight in the player's own ship, no level.
static func launch_sandbox() -> void:
	Session.pending_level = {}
	Session.pending_ship = flight_ship(current_ship())
	Session.level_result = {}


## Fold a finished flight into the records and the wallet, once. Returns what
## happened for the map's pay-out card, or {} when there was nothing to take.
## The result is `{key, won, time, kills, hull}` from the flight scene.
static func take_result() -> Dictionary:
	var res := Session.level_result
	Session.level_result = {}
	if res.is_empty() or not res.has("key"):
		return {}
	var lvl := LevelGen.from_key(String(res["key"]))
	if lvl.is_empty():
		return {}
	return apply_result(lvl, res)


## Split from [method take_result] so a check can feed results directly.
static func apply_result(lvl: Dictionary, res: Dictionary) -> Dictionary:
	ensure_loaded()
	var key := String(lvl["key"])
	var levels := _data["levels"] as Dictionary
	var rec: Dictionary = levels.get(key, {"attempts": 0, "wins": 0, "stars": 0, "best": 0.0})
	var st := _data["stats"] as Dictionary
	var won := bool(res.get("won", false))
	var time := float(res.get("time", 0.0))
	var kills := int(res.get("kills", 0))
	var tries := maxi(1, int(res.get("attempts", 1)))
	rec["attempts"] = int(rec.get("attempts", 0)) + tries
	st["flights"] = int(st.get("flights", 0)) + tries
	st["kills"] = int(st.get("kills", 0)) + kills
	var stars := 0
	var pay := 0
	var old_stars := int(rec.get("stars", 0))
	var first_win := won and int(rec.get("wins", 0)) == 0
	if won:
		stars = 1
		if float(res.get("hull", 0.0)) >= 0.5:
			stars += 1
		if time > 0.0 and time <= float(lvl["par"]):
			stars += 1
		rec["wins"] = int(rec.get("wins", 0)) + 1
		var best := float(rec.get("best", 0.0))
		rec["best"] = time if best <= 0.0 else minf(best, time)
		rec["stars"] = maxi(old_stars, stars)
		pay = int(lvl["reward"]) if first_win else int(float(lvl["reward"]) * REPLAY_PAY)
		pay += maxi(0, stars - old_stars) * STAR_BONUS
		st["wins"] = int(st.get("wins", 0)) + 1
		var kind := String(lvl["kind"])
		if kind in ["courier", "race", "salvage", "dock", "escort", "capital"]:
			st["cargo_wins"] = int(st.get("cargo_wins", 0)) + 1
		else:
			st["fight_wins"] = int(st.get("fight_wins", 0)) + 1
	levels[key] = rec
	_data["coins"] = coins() + pay
	save_to_disk()
	notifier.changed.emit()
	return {
		"key": key, "won": won, "stars": stars, "new_stars": maxi(0, stars - old_stars),
		"coins": pay, "first_win": first_win, "time": time, "kills": kills,
	}
