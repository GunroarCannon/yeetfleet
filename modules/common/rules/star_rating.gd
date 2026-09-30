## StarRating: how many stars (1–3) a won level earns — one rule, shared by
## the campaign (which pays and records them) and the flight's end card
## (which shows them), so the two can never disagree.
##
## A win is one star. The run then gets a score (0–1) from a few criteria,
## each weighted per level ([method grade_for], seeded, so one level cares
## most about hull, another about speed):
## - [b]hull[/b]: how much of the player's hull is left;
## - [b]time[/b]: how fast against the level's par — 1 at 70% of par or
##   quicker, falling to 0 at 1.8× par;
## - [b]guard[/b]: how much of the guarded ship's hull is left (escort,
##   protect);
## - [b]fight[/b]: the player's own share of the kills (fight levels), so
##   sitting back while the wingmen win is one star, not three.
## Two stars at [code]bar[0][/code], three at [code]bar[1][/code]; both bars
## rise with the level's difficulty, so a late level's third star is earned.
class_name StarRating
extends RefCounted

## At or under this share of par, speed scores full marks…
const FAST := 0.7
## …and at this share, none.
const SLOW := 1.8
## The bars at difficulty 0 and how much they rise at the top (d = 1.6).
const BAR_TWO := Vector2(0.4, 0.2)
const BAR_THREE := Vector2(0.66, 0.24)
## Kinds with a ship to guard.
const GUARD_KINDS: Array[String] = ["escort", "capital", "protect"]
## Kinds that are about getting somewhere fast: speed is always weighted.
const SPEED_KINDS: Array[String] = ["race", "courier", "salvage", "voyage", "dock"]


## A level's grading: {weights: {hull, time, guard}, bar: [two, three],
## focus: the criterion weighted most}. [param d] is its difficulty (0..1.6),
## [param seed] its own seed. [param fight_weight] > 0 grades the player's
## share of the kills; [param bar_bonus] is added to both bars.
static func grade_for(kind: String, d: float, seed: int, fight_weight := 0.0, bar_bonus := 0.0) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var w := {"hull": r.randf_range(0.5, 1.5), "time": r.randf_range(0.5, 1.5)}
	if kind in SPEED_KINDS:
		w["time"] = float(w["time"]) + 0.8
	if kind in GUARD_KINDS:
		w["guard"] = r.randf_range(1.0, 1.8)
	if kind in ["survive", "protect"]:
		# A clock you can't beat: speed means nothing there.
		w.erase("time")
	if fight_weight > 0.0:
		w["fight"] = fight_weight
	var focus := ""
	var most := -1.0
	for k: String in w:
		if float(w[k]) > most:
			most = float(w[k])
			focus = k
	var k2 := clampf(d / 1.6, 0.0, 1.0)
	return {
		"weights": w,
		"bar": [snappedf(BAR_TWO.x + BAR_TWO.y * k2 + bar_bonus, 0.01),
			snappedf(minf(BAR_THREE.x + BAR_THREE.y * k2 + bar_bonus, 0.94), 0.01)],
		"focus": focus,
	}


## The run's score (0..1) under [param grade], for a level with par
## [param par] seconds. [param run]: {hull, time, guard (-1 = none),
## fight (the player's share of the kills, 0..1; missing = not graded)}.
static func score(grade: Dictionary, par: float, run: Dictionary) -> float:
	var w: Dictionary = grade.get("weights", {"hull": 1.0, "time": 1.0})
	var total := 0.0
	var sum := 0.0
	for k: String in w:
		var v := 0.0
		match k:
			"hull":
				v = clampf(float(run.get("hull", 0.0)), 0.0, 1.0)
			"time":
				if par <= 0.0:
					continue
				var share := float(run.get("time", 0.0)) / par
				v = clampf((SLOW - share) / (SLOW - FAST), 0.0, 1.0)
			"guard":
				var g := float(run.get("guard", -1.0))
				if g < 0.0:
					continue
				v = clampf(g, 0.0, 1.0)
			"fight":
				if not run.has("fight"):
					continue
				v = clampf(float(run["fight"]), 0.0, 1.0)
		sum += v * float(w[k])
		total += float(w[k])
	return sum / total if total > 0.0 else 1.0


## Stars for a run: 0 for a loss, else 1–3 by [method score] against the bars.
static func stars(grade: Dictionary, par: float, run: Dictionary) -> int:
	if not bool(run.get("won", false)):
		return 0
	var bar: Array = grade.get("bar", [0.4, 0.66])
	var s := score(grade, par, run)
	return 3 if s >= float(bar[1]) else (2 if s >= float(bar[0]) else 1)


## A few words on what this level grades most, for the cards.
static func focus_words(grade: Dictionary) -> String:
	match String(grade.get("focus", "")):
		"hull":
			return "STARS FOR HULL LEFT"
		"time":
			return "STARS FOR SPEED"
		"guard":
			return "STARS FOR ITS HULL"
		"fight":
			return "STARS FOR YOUR KILLS"
	return ""
