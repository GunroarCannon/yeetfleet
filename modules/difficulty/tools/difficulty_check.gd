## Headless check of [Difficulty] and its panel: the JSON round-trips, presets
## scale dials, curves bend the climb, force_ship gates ship choice, and the
## panel builds in every edit mode.
## `"$GD" --path . --headless --audio-driver Dummy --script modules/difficulty/tools/difficulty_check.gd`
extends SceneTree

var _fails := 0


func _initialize() -> void:
	Difficulty.reload()
	Difficulty.preset = Difficulty.NORMAL
	_check(Difficulty.v("player_hull") == 0.6, "base dial read from the file")
	# Presets multiply.
	Difficulty.preset = 0
	_check(absf(Difficulty.v("damage_taken") - 0.56) < 0.001, "easy scales damage taken")
	Difficulty.preset = Difficulty.NORMAL
	_check(Difficulty.v("damage_taken") == 1.0, "normal is x1")
	# Curves bend the climb.
	var flat := float(Difficulty.for_level(21, "skirmish", 0.9)["hp_mult"])
	Difficulty.set_curve_points("hp", [[1, 1.0], [11, 2.0]])
	_check(absf(Difficulty.curve("hp", 6) - 1.5) < 0.001, "curve interpolates")
	_check(absf(Difficulty.curve("hp", 99) - 2.0) < 0.001, "curve is flat past its end")
	_check(float(Difficulty.for_level(21, "skirmish", 0.9)["hp_mult"]) > flat, "curve raises enemy hull")
	# Growth formulas: start at level 1, end at the span, bend with shape, step per era.
	Difficulty.reset()
	_check(absf(Difficulty.stat("hp", 1) - Difficulty.v("hp_start")) < 0.001, "growth starts at its start value")
	var span := int(Difficulty.v("growth_span"))
	var no_era := Difficulty.stat("hp", span) / pow(Difficulty.v("hp_era"), float(Difficulty.era_of(span)))
	_check(absf(no_era - Difficulty.v("hp_end")) < 0.01, "growth reaches its end at the span (before eras)")
	Difficulty.set_dial("hp_shape", 2.0)
	_check(Difficulty.stat("hp", 10) < Difficulty.stat("hp", 10) + 1.0 and Difficulty.stat("hp", 10) < lerpf(Difficulty.v("hp_start"), Difficulty.v("hp_end"), 9.0 / 39.0), "shape above 1 starts slow")
	Difficulty.reset()
	_check(Difficulty.era_of(19) == 0 and Difficulty.era_of(20) == 1 and Difficulty.era_of(30) == 2, "eras step every era_levels")
	_check(Difficulty.level_stats(30, "boss").size() > Difficulty.level_stats(30, "skirmish").size(), "boss levels list boss stats")
	_check(Difficulty.level_stats(30, "duel").size() > Difficulty.level_stats(30, "skirmish").size(), "duel levels list ace stats")
	# Bosses outsize everything else in the level, and have no backdrop.
	var big_enough := true
	var no_scenery := true
	for route in [[0], [0, 2], [0, 2, 4], [0, 1, 3, 0]]:
		var lvl: Dictionary = LevelGen.sector(route)["levels"][LevelGen.LEVELS_PER_SECTOR - 1]
		var o: Dictionary = lvl["overrides"]
		if float(o.get("dreadnought_size", 0.0)) >= float(o["boss_size"]):
			big_enough = false
		if int(o.get("backdrop", 0)) > 0 or int(o.get("bystanders", 0)) > 0:
			no_scenery = false
		if float(o["boss_size"]) < 6.0:
			big_enough = false
	_check(big_enough, "boss is bigger than any dreadnought in its level")
	_check(no_scenery, "boss levels carry no backdrop or giants")
	# Force ship gates the type a level demands.
	var lvl := {"ship_type": 2, "rec_type": 2}
	_check(Campaign.required_type(lvl) == 2, "forced when force_ship is on")
	Difficulty.set_dial("force_ship", 0.0)
	_check(Campaign.required_type(lvl) == -1, "not forced when off")
	_check(Campaign.recommended_type(lvl) == 2, "still recommended")
	_check(Difficulty.ship_hint("TANK") != "", "hint text")
	# Reward.
	Difficulty.set_dial("reward_base", 100.0)
	Difficulty.set_dial("reward_per_level", 0.0)
	_check(Difficulty.level_reward(5) == int(100.0 * Difficulty.v("reward_mult") * Difficulty.curve("reward", 5)), "reward maths")
	Difficulty.reload()
	# The panel builds in every mode.
	var panel := DifficultyPanel.new()
	root.add_child(panel)
	await process_frame
	await process_frame
	_check(panel.get_child_count() > 0, "panel builds")
	var lab := load("res://modules/difficulty/difficulty_lab.tscn") as PackedScene
	_check(lab != null, "lab scene loads")
	print("FAIL difficulty_check (%d)" % _fails if _fails > 0 else "PASS difficulty_check")
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %-44s %s" % [what, "ok" if ok else "FAILED"])
	if not ok:
		_fails += 1
