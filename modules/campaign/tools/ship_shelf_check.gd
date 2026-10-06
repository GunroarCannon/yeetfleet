## Headless check for the garage's ship list: every catalog ship's hull
## preset builds, and the top shelf really is top — A-class and above before
## any pips (S and SSS among them), priced high, and faster/tougher in flight
## than a starter ([method ShipCatalog.class_mult]).
##
##     godot --path . --headless --audio-driver Dummy --script modules/campaign/tools/ship_shelf_check.gd
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	print("── ship shelf check ──────────────────────────────────────")
	var lib := PartLibrary.instance()
	lib.load_all()
	var built := 0
	for id in ShipCatalog.ids():
		var s := ShipCatalog.get_ship(id)
		var d := lib.build_preset_design(String(s["preset"]))
		if d == null:
			_report("%s's hull (%s) builds" % [id, s["preset"]], false)
		else:
			built += 1
	_report("every catalog hull builds (%d)" % built, built == ShipCatalog.ids().size())
	var families := {}
	for id in ShipCatalog.ids():
		var tier := ShipCatalog.rank_tier(id, {})
		families[ShipCatalog.RANK_LETTERS[ShipCatalog.rank_family(tier)]] = true
		print("  %-10s %-6s %7d coins" % [id, ShipCatalog.rank_name(tier), int(ShipCatalog.get_ship(id)["price"])])
	_report("the shop sells A-class ships", families.has("A") or families.has("AA"))
	_report("the shop sells S-class ships", families.has("S"))
	_report("and an SSS", families.has("SSS"))
	_report("the best costs six figures", int(ShipCatalog.get_ship("sovereign")["price"]) >= 100000)
	_report("a top-shelf hull is tougher in flight", ShipCatalog.class_mult("sovereign", "hull") > 1.4 and ShipCatalog.class_mult("lance", "hull") == 1.0)
	_report("a rated-9 track has room for one pip", _room("cruiser", "hull") == 1)
	_finish()


func _room(id: String, stat: String) -> int:
	return mini(ShipCatalog.MAX_PIPS, 10 - ShipCatalog.rating(id, stat))


func _report(label: String, ok: bool) -> void:
	print("  %-60s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	print("── %s ─────────────────────────────────────────" % ("PASS" if _failures.is_empty() else "FAIL (%d)" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)
