## Headless check for the campaign module: levels are deterministic and
## valid for hundreds of levels down every branch, forks never offer the same
## theme twice, the save round-trips, and the garage spends coins correctly.
##
##     godot --headless --path . --audio-driver Dummy --script modules/campaign/tools/campaign_check.gd
##
## Saves to a scratch file, never the player's real campaign.
extends SceneTree

const SCRATCH := "user://campaign_check_scratch.json"

var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── campaign check ─────────────────────────────────────")
	Campaign.save_path = SCRATCH
	Campaign.reset()
	_check_determinism()
	_check_many_levels()
	_check_forks()
	_check_progress_and_pay()
	_check_garage()
	_check_save_roundtrip()
	_check_handoff()
	_check_systems_and_next()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	if _failures.is_empty():
		print("PASS campaign_check")
	else:
		for f in _failures:
			print("  FAIL: " + f)
		print("FAIL campaign_check (%d)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _done(label: String) -> void:
	print("  %-46s %s" % [label, "ok" if _failures.size() == _reported else "FAILED"])
	_reported = _failures.size()


func _check_determinism() -> void:
	var route := [0, 1, 2]
	var a := LevelGen.level(route, 3)
	var b := LevelGen.level(route, 3)
	_check(JSON.stringify(a) == JSON.stringify(b), "same key gave two different levels")
	_check(LevelGen.from_key(String(a["key"]))["title"] == a["title"], "from_key does not round-trip")
	var c := LevelGen.level([0, 1, 3], 3)
	_check(String(c["key"]) != String(a["key"]), "different routes share a key")
	# A pinned expectation: if this changes, every player's campaign changed.
	# Bump LevelGen.GRAMMAR_VERSION on purpose, then update this line.
	var first := LevelGen.level([0], 0)
	_check(String(first["preset"]) == "practice", "level 1 is not the practice range")
	_check(int(first["number"]) == 1, "level 1 is not numbered 1")
	print("    e.g. %s  %s  %s  %s" % [a["key"], a["title"], a["kind"], a["pic"]])
	_done("same key, same level")


func _check_many_levels() -> void:
	var kinds := {}
	var themes := [0, 1, 2, 3, 4]
	for depth in 40:
		var route: Array = [0]
		for i in depth:
			route.append(themes[(i * 7 + depth) % themes.size()])
		for idx in LevelGen.LEVELS_PER_SECTOR:
			var l := LevelGen.level(route, idx)
			kinds[l["kind"]] = true
			var o: Dictionary = l["overrides"]
			_check(int(o.get("enemies", 0)) + int(o.get("allies", 0)) <= 24, "level %s over the ship cap" % l["key"])
			_check(float(l["par"]) > 0.0, "level %s has no par" % l["key"])
			_check(int(l["danger"]) >= 1 and int(l["danger"]) <= 5, "level %s danger out of range" % l["key"])
			_check(String(l["title"]).length() > 3, "level %s has no name" % l["key"])
		var sec := LevelGen.sector(route)
		_check(String(sec["name"]) != "", "sector %s has no name" % sec["key"])
	_check(kinds.size() >= 10, "only %d level kinds turn up in 200 levels" % kinds.size())
	_done("200 levels generate, all in range")


func _check_forks() -> void:
	for t in 5:
		for style in 5:
			var route := [0, t]
			var f := LevelGen.fork_options(route, style)
			_check(f.size() == 2 and f[0] != f[1], "fork %s gives a duplicate" % [route])
			_check(not t in f, "fork after %d offers the same theme again" % t)
	_done("forks: two different, never a repeat")


func _check_progress_and_pay() -> void:
	Campaign.reset()
	var secs := Campaign.sectors()
	var l0: Dictionary = secs[0]["levels"][0]
	var l1: Dictionary = secs[0]["levels"][1]
	_check(Campaign.is_unlocked(l0), "level 1 locked on a fresh save")
	# Stars, not wins, open levels: the first few are free, later ones are not.
	_check(Campaign.is_unlocked(l1), "level 2 (free) is locked")
	var l4: Dictionary = secs[0]["levels"][3]
	_check(not Campaign.is_unlocked(l4), "level 4 open with no stars")
	var prev := 0
	for n in range(1, 61):
		var need := LevelGen.stars_needed(n)
		_check(need >= prev and need <= 3 * (n - 1), "star gate %d for level %d is not climbable" % [need, n])
		prev = need
	_check(LevelGen.stars_needed(3) == 0 and LevelGen.stars_needed(10) >= 8 and LevelGen.stars_needed(10) <= 16, "star curve off (level 10 wants %d)" % LevelGen.stars_needed(10))
	var coins := Campaign.coins()
	var lost := Campaign.apply_result(l0, {"won": false, "time": 30.0, "kills": 1, "attempts": 2})
	_check(int(lost["coins"]) == 0 and Campaign.coins() == coins, "a loss paid out")
	_check(Campaign.record(l0["key"])["attempts"] == 2, "attempts not counted")
	var win := Campaign.apply_result(l0, {"won": true, "time": 1.0, "kills": 4, "hull": 0.9})
	_check(int(win["stars"]) == 3, "a fast full-hull win is not 3 stars (%d)" % int(win["stars"]))
	_check(Campaign.coins() == coins + int(l0["reward"]) + 3 * Campaign.star_bonus(), "first win paid the wrong amount")
	_check(Campaign.is_unlocked(l4), "3 stars did not open level 4")
	_check(Campaign.total_stars() == 3, "total stars not counted (%d)" % Campaign.total_stars())
	var again := Campaign.apply_result(l0, {"won": true, "time": 1.0, "kills": 0, "hull": 0.9})
	_check(int(again["coins"]) == int(float(l0["reward"]) * Campaign.replay_pay()), "replay paid the wrong amount")
	# Finish the sector: the fork appears and choosing it extends the road.
	_check(not Campaign.at_fork(), "fork before the sector is done")
	for lvl in secs[0]["levels"]:
		Campaign.apply_result(lvl, {"won": true, "time": 999.0, "kills": 9, "hull": 0.1})
	_check(Campaign.at_fork(), "no fork after the whole sector is won")
	var opts := Campaign.fork_options()
	Campaign.choose_fork(opts[1])
	_check(Campaign.route().size() == 2 and Campaign.route()[1] == opts[1], "fork choice not taken")
	var next: Dictionary = Campaign.sectors()[1]["levels"][0]
	_check(Campaign.is_unlocked(next), "the new sector's first level is locked")
	_check(Campaign.style_theme() == LevelGen.Turf.PIRATE, "a wreck-happy pilot is not DANGEROUS")
	_done("unlocks, stars, pay, forks, style")


func _check_garage() -> void:
	Campaign.reset()
	var cur := Campaign.current_ship()
	_check(Campaign.owns(cur), "current ship not owned")
	_check(not Campaign.buy_ship("keel"), "bought a 4000 ship with starting coins")
	Campaign.add_coins(5000)
	var before := Campaign.coins()
	_check(Campaign.buy_ship("keel"), "could not buy the keel with 5000+")
	_check(Campaign.coins() == before - 4000 and Campaign.current_ship() == "keel", "buying did not charge or select")
	var cost := Campaign.next_pip_cost("keel", "hull")
	_check(Campaign.buy_pip("keel", "hull") and Campaign.pips("keel", "hull") == 1, "pip not bought")
	_check(Campaign.coins() == before - 4000 - cost, "pip charged wrong")
	var m := Campaign.flight_ship("keel")
	_check(float(m["mults"]["hull"]) > 1.0 and is_equal_approx(float(m["mults"]["speed"]), 1.0), "pip did not reach the flight mults")
	for i in 10:
		Campaign.add_coins(100000)
		Campaign.buy_pip("keel", "speed")
	_check(Campaign.pips("keel", "speed") == ShipCatalog.MAX_PIPS and Campaign.next_pip_cost("keel", "speed") == -1, "pips not capped")
	# A level that wants a type the player lacks hands out a loaner.
	var want := {"ship_type": ShipCatalog.Type.HAULER}
	var pick := Campaign.ship_for(want)
	_check(bool(pick["loaner"]) and ShipCatalog.type_of(String(pick["id"])) == ShipCatalog.Type.HAULER, "no hauler loaner")
	_check(is_equal_approx(float(Campaign.flight_ship("mule", true)["mults"]["hull"]), 1.0), "a loaner flies with pips")
	_done("buy, select, pips, cap, loaners")


func _check_save_roundtrip() -> void:
	var coins := Campaign.coins()
	var owned := Campaign.owned_ids()
	Campaign.load_from_disk()
	_check(Campaign.coins() == coins and Campaign.owned_ids() == owned, "save did not round-trip")
	# A garbage file is a fresh start, not a crash.
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string("not json {")
	f.close()
	Campaign.load_from_disk()
	_check(Campaign.coins() == Campaign.START_COINS, "a broken save did not start fresh")
	_done("save round-trip, broken file")


func _check_handoff() -> void:
	Campaign.reset()
	var l0: Dictionary = Campaign.sectors()[0]["levels"][0]
	Campaign.launch(l0)
	_check(String(Session.pending_level["key"]) == String(l0["key"]), "launch did not hand over the key")
	_check(String(Session.pending_ship["preset"]) != "", "launch did not hand over a hull")
	Session.level_result = {"key": l0["key"], "won": true, "time": 20.0, "kills": 3, "hull": 1.0, "attempts": 1}
	var got := Campaign.take_result()
	_check(bool(got.get("won", false)) and Session.level_result.is_empty(), "take_result did not fold the result in once")
	_check(Campaign.take_result().is_empty(), "take_result counted twice")
	Session.pending_level = {}
	Session.pending_ship = {}
	_done("menu → flight → menu handoff")


## Every level has its own system (the same every time), the sandbox rolls a
## new one with incidents, guard levels bring wingmen, and a launch lists
## what NEXT can go to.
func _check_systems_and_next() -> void:
	Campaign.reset()
	var r := [LevelGen.Turf.WILDS, LevelGen.Turf.PIRATE]
	var a := LevelGen.level(r, 2)
	_check(a["space"] == LevelGen.level(r, 2)["space"], "a level's system is not the same every time")
	_check(a["space"] != LevelGen.level(r, 3)["space"], "two levels share one system")
	_check(String((a["space"]["looks"] as Array)[0]) in LevelGen.THEME_LOOKS[LevelGen.Turf.PIRATE], "the main world ignores the theme")
	var s1 := LevelGen.random_space(1)
	_check(s1 != LevelGen.random_space(2) and not (s1["events"] as Array).is_empty(), "the sandbox system does not vary or has no incidents")
	var guards := 0
	var with_allies := 0
	for i in 200:
		var l := LevelGen.level([LevelGen.Turf.PIRATE, LevelGen.Turf.TRADE, i % 5], i % LevelGen.LEVELS_PER_SECTOR)
		if String(l["kind"]) in ["escort", "capital"]:
			guards += 1
			if int((l["overrides"] as Dictionary).get("allies", 0)) > 0:
				with_allies += 1
	_check(guards > 0 and with_allies * 10 >= guards * 6, "guard levels rarely bring wingmen (%d/%d)" % [with_allies, guards])
	var l0: Dictionary = Campaign.sectors()[0]["levels"][0]
	Campaign.launch(l0)
	var nxt: Array = Session.pending_level["next"]
	_check(not nxt.is_empty() and String(nxt[0]["key"]) == String(Campaign.sectors()[0]["levels"][1]["key"]), "NEXT does not offer the level this win opens")
	_check(not Session.space_setup.is_empty(), "a launch does not hand over its system")
	Campaign.launch_sandbox()
	_check(Session.pending_level.is_empty() and not Session.space_setup.is_empty(), "the sandbox has no system of its own")
	var coins := Campaign.coins()
	Session.level_result = {"key": "sandbox", "coins": 12}
	Campaign.take_result()
	_check(Campaign.coins() == coins + 12, "sandbox points did not pay out")
	Session.pending_level = {}
	Session.pending_ship = {}
	Session.space_setup = {}
	_done("level systems, sandbox systems, guard wingmen, NEXT")
