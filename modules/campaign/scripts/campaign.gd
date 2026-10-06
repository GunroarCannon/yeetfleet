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

## A replayed win pays this fraction of the level's reward ([Difficulty]'s dial).
static func replay_pay() -> float:
	return Difficulty.v("replay_pay")


## Coins per star earned for the first time ([Difficulty]'s dial).
static func star_bonus() -> int:
	return int(Difficulty.v("star_bonus"))


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


## Count something for the Settings > STATS page ([param amount] more of
## [param key]). Saved to disk at most every few seconds, so a stream of small
## counts (play time) costs nothing.
static func bump_stat(key: String, amount: float = 1.0) -> void:
	ensure_loaded()
	var st := _data["stats"] as Dictionary
	st[key] = st.get(key, 0) + amount
	var now := Time.get_ticks_msec()
	if now - _stat_saved_ms > 8000:
		_stat_saved_ms = now
		save_to_disk()


static var _stat_saved_ms := 0


## One counter from the stats page (0 when never counted).
static func stat_value(key: String) -> float:
	ensure_loaded()
	return float((_data["stats"] as Dictionary).get(key, 0))


## Wipe progress back to a fresh pilot (the Settings screen's reset).
static func reset() -> void:
	# The one-time pop-ups and the flight school are part of a fresh pilot too.
	for k in Session.prefs.keys():
		var key := String(k)
		if key.begins_with("nudge_") or key.begins_with("intro_") or key in ["tutorial_done", "welcomed"]:
			Session.prefs.erase(k)
	Session.save_to_disk()
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
		"stats": {"kills": 0, "fight_wins": 0, "cargo_wins": 0, "wins": 0, "flights": 0,
			"ships_bought": 0, "upgrades_bought": 0, "planets_destroyed": 0, "yeets": 0, "deaths": 0,
			"time_played": 0.0, "coins_earned": 0},
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


## The longest a pilot's name can be.
const NAME_MAX := 14


## Rename the pilot: trimmed, upper case, letters/digits/spaces only, at most
## [constant NAME_MAX] long. An empty result keeps the old name.
static func set_pilot_name(name: String) -> void:
	ensure_loaded()
	var clean := ""
	for ch in name.strip_edges().to_upper():
		if ch == " " or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			clean += ch
	clean = clean.strip_edges().left(NAME_MAX)
	if clean == "" or clean == pilot_name():
		return
	_data["pilot"] = clean
	save_to_disk()
	notifier.changed.emit()


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
	bump_stat("ships_bought")
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
	# The bar has ten cells: a top-shelf ship rated 8 has room for two pips.
	if have >= mini(ShipCatalog.MAX_PIPS, 10 - ShipCatalog.rating(id, stat)):
		return -1
	return ShipCatalog.pip_cost(id, stat, have)


## Losses in a row on campaign levels (a win resets it).
static func loss_streak() -> int:
	ensure_loaded()
	return int((_data["stats"] as Dictionary).get("loss_streak", 0))


## Whether the current ship has an upgrade the pilot can pay for right now.
static func can_afford_upgrade() -> bool:
	var id := current_ship()
	for st: String in ShipCatalog.STATS:
		var cost := next_pip_cost(id, st)
		if cost >= 0 and cost <= coins():
			return true
	return false


## One-time hints (kept in the saved prefs): has [param name] been shown?
static func nudge_seen(nudge: String) -> bool:
	return bool(Session.pref("nudge_" + nudge, false))


static func mark_nudge(nudge: String) -> void:
	Session.prefs["nudge_" + nudge] = true
	Session.save_to_disk()


## The rank step of ship [param id] with the upgrades bought so far.
static func rank_tier(id: String) -> int:
	ensure_loaded()
	return ShipCatalog.rank_tier(id, (_data["pips"] as Dictionary).get(id, {}))


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
	bump_stat("upgrades_bought")
	save_to_disk()
	notifier.changed.emit()
	return true


## The ship type [param lvl] makes the player fly (-1: any). Only when the
## difficulty table lets levels force one ([method Difficulty.forces_ship]);
## otherwise the level just recommends its `rec_type`/`ship_type`.
static func required_type(lvl: Dictionary) -> int:
	return int(lvl.get("ship_type", -1)) if Difficulty.forces_ship() else -1


## The ship type a level suits, forced or not (-1: no leaning).
static func recommended_type(lvl: Dictionary) -> int:
	var t := int(lvl.get("ship_type", -1))
	return t if t >= 0 else int(lvl.get("rec_type", -1))


## The ship a level will fly: the current ship when the level takes any type
## (or it is the right type), else the player's best owned ship of the type,
## else the type's loaner. `{"id", "loaner"}`.
static func ship_for(lvl: Dictionary) -> Dictionary:
	var want := required_type(lvl)
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
		mults[stat] = ShipCatalog.stat_mult(id, stat, 0 if loaner else pips(id, stat)) * ShipCatalog.class_mult(id, stat)
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
	# Stars alone open a level: beating the one before is not required.
	return total_stars() >= int(lvl.get("stars_req", 0))


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
	# Like a level, the fork opens on stars: enough for the next sector's first
	# level (or the boss beaten, for saves from before the star gate).
	var r := route()
	if record(LevelGen.level_key(r, LevelGen.LEVELS_PER_SECTOR - 1))["wins"] > 0:
		return true
	return total_stars() >= LevelGen.stars_needed(r.size() * LevelGen.LEVELS_PER_SECTOR + 1)


## Stars the next branch asks for: the first level of the sector it opens.
static func fork_stars_needed() -> int:
	return LevelGen.stars_needed(route().size() * LevelGen.LEVELS_PER_SECTOR + 1)


## Whether the pilot holds the stars to take a branch.
static func fork_open() -> bool:
	return total_stars() >= fork_stars_needed()


## The two themes the road forks into next.
static func fork_options() -> Array[int]:
	return LevelGen.fork_options(route(), style_theme())


## Take the fork toward [param theme].
static func choose_fork(theme: int) -> void:
	if not at_fork() or not fork_open() or not theme in fork_options():
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

## The level last flown, and whether the map has been shown yet this run (both
## survive the menu <-> flight scene changes): the map re-opens on the level
## just played, and on the newest unlocked one only the first time or after a
## fresh unlock.
static var last_played_key := ""
static var map_seen := false

## Hand a level to the flight scene: the scenario, the ship, and the key the
## result will come back under. The caller changes scene afterwards.
static func launch(lvl: Dictionary) -> void:
	last_played_key = String(lvl["key"])
	var pick := ship_for(lvl)
	Session.pending_level = {
		"key": String(lvl["key"]), "preset": String(lvl["preset"]),
		"overrides": (lvl["overrides"] as Dictionary).duplicate(true),
		"title": String(lvl["title"]), "number": int(lvl["number"]),
		"par": float(lvl["par"]),
		"grade": (lvl.get("grade", {}) as Dictionary).duplicate(true),
		"word": String(lvl["word"]),
		"brief": LevelGen.brief_for(String(lvl["kind"]), lvl.get("overrides", {})),
		# What NEXT on the win card can go to (see [method next_candidates]).
		"next": next_candidates(lvl),
		"stars_now": total_stars(),
		# Winning the last level on the road leaves a branch to choose on the map.
		"ends_road": String(lvl["key"]) == LevelGen.level_key(route(), LevelGen.LEVELS_PER_SECTOR - 1),
		"stars_here": int(record(String(lvl["key"]))["stars"]),
		# What the end card shows as the pay-out (see [method apply_result]).
		"reward": int(lvl["reward"]),
		"pay_base": int(lvl["reward"]) if int(record(String(lvl["key"]))["wins"]) == 0 else int(float(lvl["reward"]) * replay_pay()),
		"star_bonus": star_bonus(),
	}
	Session.pending_ship = flight_ship(String(pick["id"]), bool(pick["loaner"]))
	Session.space_setup = (lvl.get("space", {}) as Dictionary).duplicate(true)
	Session.level_result = {}


## Levels never won that are open now, or that winning [param lvl] would
## open — what the win card's NEXT can go to: `[{key, stars_req}]`, the
## ones [param lvl] opens first.
static func next_candidates(lvl: Dictionary) -> Array:
	var out: Array = []
	var r := LevelGen.parse_route(String(lvl.get("route", "")))
	var here := String(lvl.get("key", ""))
	for i in (lvl.get("unlocks", []) as Array):
		var nxt := LevelGen.level(r, int(i))
		if record(String(nxt["key"]))["wins"] == 0:
			out.append({"key": String(nxt["key"]), "stars_req": int(nxt["stars_req"])})
	for sec in sectors():
		for other: Dictionary in sec["levels"]:
			var k := String(other["key"])
			if k != here and record(k)["wins"] == 0 and is_unlocked(other) 					and not out.any(func(c: Dictionary) -> bool: return c["key"] == k):
				out.append({"key": k, "stars_req": int(other["stars_req"])})
	return out


## True once the pilot has finished flight school (set by the flight tutorial).
static func tutorial_done() -> bool:
	return bool(Session.pref("tutorial_done", false))


## The tutorial as a level on the map: flight school against a few drones,
## with the hand showing each move. Pays nothing, keeps no record.
static func launch_tutorial() -> void:
	Session.pending_level = {
		"key": "tutorial", "tutorial": true, "preset": "practice",
		"overrides": {"enemies": 3, "name": "Flight school"},
		"title": "Flight school", "number": 0, "par": 0.0,
		"word": "LEARN", "brief": "Learn the moves.",
	}
	Session.pending_ship = flight_ship(current_ship())
	Session.space_setup = {}
	Session.level_result = {}


## Sandbox: free flight in the player's own ship, no level.
static func launch_sandbox() -> void:
	Session.pending_level = {}
	Session.pending_ship = flight_ship(current_ship())
	# A new system every time: planets, sizes, colours and incidents.
	Session.space_setup = LevelGen.random_space(randi())
	Session.level_result = {}


## Fold a finished flight into the records and the wallet, once. Returns what
## happened for the map's pay-out card, or {} when there was nothing to take.
## The result is `{key, won, time, kills, hull}` from the flight scene.
static func take_result() -> Dictionary:
	var res := Session.level_result
	Session.level_result = {}
	if res.is_empty() or not res.has("key"):
		return {}
	# Sandbox pay-outs: points scored before being wrecked, as coins.
	if String(res["key"]) == "sandbox":
		var earned := maxi(0, int(res.get("coins", 0)))
		if earned > 0:
			add_coins(earned)
		return {}
	var lvl := LevelGen.from_key(String(res["key"]))
	if lvl.is_empty():
		return {}
	var out := apply_result(lvl, res)
	out["go_next"] = String(res.get("go_next", ""))
	return out


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
		# The shared rule the end card shows (see [StarRating]).
		stars = StarRating.stars(lvl.get("grade", {}), float(lvl["par"]), res)
		rec["wins"] = int(rec.get("wins", 0)) + 1
		var best := float(rec.get("best", 0.0))
		rec["best"] = time if best <= 0.0 else minf(best, time)
		rec["stars"] = maxi(old_stars, stars)
		pay = int(lvl["reward"]) if first_win else int(float(lvl["reward"]) * replay_pay())
		pay += maxi(0, stars - old_stars) * star_bonus()
		st["wins"] = int(st.get("wins", 0)) + 1
		var kind := String(lvl["kind"])
		if kind in ["courier", "race", "salvage", "dock", "escort", "capital", "protect", "voyage"]:
			st["cargo_wins"] = int(st.get("cargo_wins", 0)) + 1
		else:
			st["fight_wins"] = int(st.get("fight_wins", 0)) + 1
	else:
		# A loss still pays for the ships wrecked on the way.
		pay = StarRating.loss_coins(int(lvl.get("reward", 0)), kills)
	levels[key] = rec
	# RETRY on the loss card re-runs the level without leaving it, so a visit
	# can hold many losses: every try but a winning last one was a loss.
	st["loss_streak"] = 0 if won else int(st.get("loss_streak", 0)) + tries
	_data["coins"] = coins() + pay
	save_to_disk()
	notifier.changed.emit()
	return {
		"key": key, "won": won, "stars": stars, "new_stars": maxi(0, stars - old_stars),
		"coins": pay, "first_win": first_win, "time": time, "kills": kills,
	}
