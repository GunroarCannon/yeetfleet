## DailySortie: one level per UTC day, the same for every pilot.
##
## The level comes from the date's seed through [LevelGen], so every phone
## builds the same one with no download. Practice runs are unlimited; a
## [i]ranked[/i] run needs the leaderboard session with a Seeker Genesis
## Token ([method Chain.has_genesis]), is one a day per token (plus attempts
## bought with SKR), and has no RETRY. "Arm the sling": the wallet signs each
## ranked ticket before the flight (on a Seeker, the fingerprint), and only
## an armed run uses up the day's attempt.
##
## A run goes through the campaign's flight flow: [method start] fills
## [member Session.pending_level] with the key [code]daily:<day>[/code] (which
## the campaign ignores), the menu flies it, and on the way back the menu
## hands the result here first ([method take_result]). The points are kept
## locally (best, streak) and sent to the Worker when the run had a ticket.
##
## A static façade like [CoinStore]: the signals live on [member notifier].
class_name DailySortie
extends RefCounted

const KEY_PREFIX := "daily:"
## The sector depth the day's level is drawn from: mid-campaign numbers
## (levels 13–18), hard enough to separate pilots, fair to a newcomer.
const DEPTH := 2
## A win scores WIN_BASE plus up to WIN_BASE more ([method points_for]); a
## loss scores LOSS_PER_WRECK per wreck, under LOSS_MAX. The Worker checks
## the same ranges.
const WIN_BASE := 1000
const LOSS_PER_WRECK := 25
const LOSS_MAX := 900
const SAVE_PATH := "user://daily.cfg"


## Emits [signal Notifier.submitted] when the Worker has the run
## ([code]{ok, board, points, best, rank, streak}[/code], or a failure), and
## [signal Notifier.changed] when [method status] was refreshed.
class Notifier:
	extends RefCounted
	signal submitted(reply: Dictionary)
	signal changed


static var notifier := Notifier.new()
## Where the local record is kept (the checks point it elsewhere).
static var save_path := SAVE_PATH
## The Worker's /daily answer: {day, ends_in_sec, me?: {streak,
## ranked_left, best}}; {} until fetched or when offline.
static var _status := {}
## The run in the air: {day, ranked, run_id ("" without a ticket)}.
static var _run := {}
## The last run's outcome, for the daily screen: {day, ranked, won,
## points, best, reply?}.
static var last := {}


## Today, UTC, as the Worker says it (once asked) or this phone's clock.
static func today() -> String:
	if _status.has("day"):
		return String(_status["day"])
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))


## The day's level: a [method LevelGen.level] picked by the date's seed,
## keyed [code]daily:<day>[/code].
static func level(day := "") -> Dictionary:
	if day == "":
		day = today()
	var r := RandomNumberGenerator.new()
	r.seed = LevelGen.seed_of("daily/" + day)
	var route: Array[int] = []
	for i in DEPTH + 1:
		route.append(r.randi_range(0, LevelGen.THEME_CODES.size() - 1))
	var lvl := LevelGen.level(route, r.randi_range(0, LevelGen.LEVELS_PER_SECTOR - 1))
	lvl["key"] = KEY_PREFIX + day
	lvl["day"] = day
	return lvl


## Points for a finished run of [param lvl]: a win 1000–2000 by
## [method StarRating.score] (hull, speed, the guarded ship, the kills, as
## the level weighs them); a loss a little per wreck, always under any win.
static func points_for(lvl: Dictionary, run: Dictionary) -> int:
	if not bool(run.get("won", false)):
		return mini(int(run.get("kills", 0)) * LOSS_PER_WRECK, LOSS_MAX)
	var s := StarRating.score(lvl.get("grade", {}), float(lvl.get("par", 0.0)), run)
	return clampi(WIN_BASE + roundi(WIN_BASE * s), WIN_BASE, WIN_BASE * 2)


# --- Server status ---

## Ask the Worker for today and the pilot's numbers. Offline it keeps the
## phone's own day and the local record.
static func refresh() -> Dictionary:
	var r := await Chain.server_get("/daily")
	if r.ok:
		r.erase("ok")
		_status = r
	notifier.changed.emit()
	return r


## {streak, ranked_left, best: {ranked, open}} from the Worker, or {}.
static func status() -> Dictionary:
	return _status.get("me", {}) if _status.get("day", "") == today() else {}


## Seconds until the next day's level, as the Worker counts; -1 offline.
static func ends_in_sec() -> int:
	return int(_status.get("ends_in_sec", -1)) if _status.get("day", "") == today() else -1


## Ranked runs left today; 0 without a Genesis session.
static func ranked_left() -> int:
	return int(status().get("ranked_left", 0)) if Chain.has_genesis() else 0


## Days in a row with a run: the Worker's count when signed in, else the
## phone's own.
static func streak() -> int:
	if status().has("streak"):
		return int(status()["streak"])
	return local_streak()


# --- A run ---

## Get a ticket (ranked, or practice when signed in) and set the day's level
## up to fly. A ranked ticket is armed first: the wallet signs it. The menu
## flies it after an ok. Codes: "not_seeker", "no_attempts", "offline"
## (ranked needs the server), "wrong_day", "cancelled" (backed out of the
## wallet; nothing used), …
static func start(ranked: bool) -> Dictionary:
	if ranked and not Chain.has_genesis():
		return {"ok": false, "code": "not_seeker", "message": "Ranked runs need a Seeker Genesis Token"}
	var day := today()
	var run_id := ""
	if Chain.has_session():
		var t := await Chain.server_post("/run/start", {"day": day, "ranked": ranked})
		if t.ok:
			run_id = String(t.run_id)
		elif ranked:
			return t
		if ranked:
			var armed := await _arm(run_id, String(t.get("arm", "")))
			if not armed.ok:
				return armed
	elif ranked:
		return {"ok": false, "code": "offline", "message": "Ranked runs need the leaderboard"}
	var lvl := level(day)
	_run = {"day": day, "ranked": ranked, "run_id": run_id}
	var pick := Campaign.ship_for(lvl)
	Session.pending_level = {
		"key": String(lvl["key"]), "preset": String(lvl["preset"]),
		"overrides": (lvl["overrides"] as Dictionary).duplicate(true),
		"title": String(lvl["title"]), "number": int(lvl["number"]),
		"par": float(lvl["par"]),
		"grade": (lvl.get("grade", {}) as Dictionary).duplicate(true),
		"word": String(lvl["word"]),
		"brief": LevelGen.brief_for(String(lvl["kind"]), lvl.get("overrides", {})),
		# No NEXT, no branch, no coins: the board is the prize.
		"next": [], "stars_now": 0, "ends_road": false, "stars_here": 0,
		"reward": 0, "pay_base": 0, "star_bonus": 0,
		"one_shot": ranked,
	}
	Session.pending_ship = Campaign.flight_ship(String(pick["id"]), bool(pick["loaner"]))
	Session.space_setup = (lvl.get("space", {}) as Dictionary).duplicate(true)
	Session.level_result = {}
	return {"ok": true, "ranked": ranked, "run_id": run_id}


## Arm a ranked ticket: the wallet signs its message, the Worker checks it.
static func _arm(run_id: String, text: String) -> Dictionary:
	var s := await Chain.sign_message(text, "arm")
	if not s.ok:
		return s
	return await Chain.server_post("/run/arm", {"run_id": run_id, "signature": s.signature})


## True when [member Session.level_result] is a daily run's.
static func has_result() -> bool:
	return String(Session.level_result.get("key", "")).begins_with(KEY_PREFIX)


## Take a daily run's result off [member Session.level_result] (the menu
## calls this before the campaign looks): score it, keep it locally, send it
## to the Worker. Returns [member last], or {} when it wasn't a daily run.
static func take_result() -> Dictionary:
	if not has_result():
		return {}
	var res := Session.level_result
	Session.level_result = {}
	var day := String(res["key"]).trim_prefix(KEY_PREFIX)
	var ranked: bool = bool(_run.get("ranked", false)) and _run.get("day", "") == day
	var points := points_for(level(day), res)
	_record(day, ranked, points)
	last = {"day": day, "ranked": ranked, "won": bool(res.get("won", false)), "points": points,
		"best": local_best(day, ranked)}
	var run_id := String(_run.get("run_id", "")) if _run.get("day", "") == day else ""
	_run = {}
	if run_id != "":
		_submit(run_id, res, points)
	return last


static func _submit(run_id: String, res: Dictionary, points: int) -> void:
	var reply := await Chain.server_post("/run/finish", {
		"run_id": run_id, "won": bool(res.get("won", false)), "points": points,
		"time": snappedf(float(res.get("time", 0.0)), 0.01), "kills": int(res.get("kills", 0)),
	})
	last["reply"] = reply
	notifier.submitted.emit(reply)
	if reply.ok:
		refresh()


## The day's board: {rows: [{rank, name, pubkey, points, seeker}], me}
## ("ranked" or "open"), or a failure ("offline").
static func leaderboard(board: String, day := "") -> Dictionary:
	return await Chain.server_get("/leaderboard?board=%s&day=%s" % [board, day if day != "" else today()])


# --- Local record ---

## The phone's best for [param day] on that board, or -1.
static func local_best(day: String, ranked: bool) -> int:
	var cfg := _cfg()
	return int(cfg.get_value("best", "%s/%s" % [day, "ranked" if ranked else "open"], -1))


## Days in a row this phone has flown a daily run, ending today (or
## yesterday: today isn't over).
static func local_streak() -> int:
	var days: Array = _cfg().get_value("played", "days", [])
	var d := Time.get_unix_time_from_datetime_string(today() + "T00:00:00")
	if not days.has(today()):
		d -= 86400
	var n := 0
	while days.has(Time.get_date_string_from_unix_time(d)):
		n += 1
		d -= 86400
	return n


static func _record(day: String, ranked: bool, points: int) -> void:
	var cfg := _cfg()
	var k := "%s/%s" % [day, "ranked" if ranked else "open"]
	cfg.set_value("best", k, maxi(points, int(cfg.get_value("best", k, -1))))
	var days: Array = cfg.get_value("played", "days", [])
	if not days.has(day):
		days.append(day)
	# A year is plenty for a streak.
	while days.size() > 400:
		days.pop_front()
	cfg.set_value("played", "days", days)
	cfg.save(save_path)


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	return cfg


## Forget the in-memory state (the checks; a fresh launch starts empty).
static func reset() -> void:
	_status = {}
	_run = {}
	last = {}
