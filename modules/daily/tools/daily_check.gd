extends SceneTree
## Headless check of the Daily Sortie: the day's level is stable per date and
## its own key (the campaign never counts it), points keep wins above losses,
## practice works offline and a ranked run doesn't, a result is taken before
## the campaign looks and kept locally (best, streak). Then against the real
## Worker code on localhost (test/dev_server.js, the mock wallet as a Genesis
## pilot): one ranked run with no RETRY, sent and ranked; the second refused;
## practice on the open board. The daily screen builds and lays out.
##   "$GD" --headless --path . --audio-driver Dummy --script modules/daily/tools/daily_check.gd

const PORT := 8798
const CAMPAIGN_SCRATCH := "user://daily_check_campaign.json"
const CHAIN_SCRATCH := "user://daily_check_chain.cfg"
const DAILY_SCRATCH := "user://daily_check.cfg"

var _fails := 0
var _pid := -1
var _replies: Array = []


func _initialize() -> void:
	Campaign.save_path = CAMPAIGN_SCRATCH
	Campaign.reset()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for p in [CHAIN_SCRATCH, DAILY_SCRATCH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Chain.save_path = CHAIN_SCRATCH
	Chain.api_url = ""
	Chain.reset(true)
	_tune()
	DailySortie.save_path = DAILY_SCRATCH
	DailySortie.reset()
	DailySortie.notifier.submitted.connect(func(r: Dictionary) -> void: _replies.append(r))

	# --- The level ---
	var a := DailySortie.level("2026-10-08")
	var b := DailySortie.level("2026-10-08")
	var c := DailySortie.level("2026-10-09")
	_expect(a.hash() == b.hash(), "the same day gives the same level")
	_expect(a.key == "daily:2026-10-08" and c.key == "daily:2026-10-09", "keyed by its day")
	_expect(a.hash() != c.hash(), "another day, another level")
	_expect(float(a.par) > 0.0 and String(a.preset) != "" and int(a.number) >= 13, "a real mid-campaign level")
	_expect(LevelGen.from_key(String(a.key)).is_empty(), "the campaign can't read a daily key")

	# --- Points ---
	var win := {"won": true, "time": float(a.par), "kills": 6, "hull": 0.9, "guard": -1.0, "fight": 0.8}
	var p_win := DailySortie.points_for(a, win)
	var p_best := DailySortie.points_for(a, {"won": true, "time": 1.0, "kills": 9, "hull": 1.0, "guard": 1.0, "fight": 1.0})
	var p_loss := DailySortie.points_for(a, {"won": false, "time": 30.0, "kills": 1000})
	_expect(p_win >= 1000 and p_win <= 2000 and p_best <= 2000, "a win scores 1000–2000 (%d, %d)" % [p_win, p_best])
	_expect(p_loss < 1000, "a loss scores under any win (%d)" % p_loss)

	# --- Offline ---
	var r := await DailySortie.start(true)
	_expect(not r.ok and r.code == "not_seeker", "offline: no ranked run")
	r = await DailySortie.start(false)
	_expect(r.ok and r.run_id == "" and String(Session.pending_level.get("key")) == "daily:" + DailySortie.today(),
			"offline: practice sets the day's level up")
	_expect(not bool(Session.pending_level.get("one_shot", true)) and not Session.pending_ship.is_empty(), "practice keeps RETRY, flies a ship")
	var coins := Campaign.coins()
	Session.level_result = {"key": Session.pending_level.key, "won": true, "time": 40.0, "kills": 4, "hull": 0.7}
	var got := DailySortie.take_result()
	_expect(not got.is_empty() and got.points >= 1000 and not got.ranked, "the result is the daily's")
	_expect(Session.level_result.is_empty() and Campaign.take_result().is_empty() and Campaign.coins() == coins,
			"the campaign never sees it")
	_expect(DailySortie.local_best(DailySortie.today(), false) == got.points and DailySortie.local_streak() == 1,
			"kept locally: best and a 1-day streak")
	_expect(_replies.is_empty(), "no ticket, nothing sent")

	# --- With the Worker ---
	var out: Array = []
	if OS.execute("node", ["--version"], out) != 0:
		print("  skip  Worker part (node not on PATH)")
		return _finish()
	_pid = OS.create_process("node", [ProjectSettings.globalize_path("res://services/leaderboard-worker/test/dev_server.js"), str(PORT)])
	var base := "http://127.0.0.1:%d" % PORT
	Chain.api_url = base
	var up := false
	for i in 40:
		if (await Chain.server_get("/health")).ok:
			up = true
			break
		await create_timer(0.25).timeout
	_expect(up, "the dev Worker is up")
	if not up:
		return _finish()
	await Chain.sign_in("Ace")
	await DailySortie.refresh()
	_expect(Chain.has_genesis() and DailySortie.ranked_left() == 1, "a Genesis pilot has one ranked run")
	# Arm the sling: the wallet signs the ticket. Backing out costs nothing.
	Chain.client().mock.next_error = "cancelled"
	r = await DailySortie.start(true)
	await DailySortie.refresh()
	_expect(not r.ok and r.code == "cancelled" and DailySortie.ranked_left() == 1,
			"backing out of the wallet's arm prompt keeps today's ranked run")
	r = await DailySortie.start(true)
	var signed := ""
	for q: Array in Chain.client().mock.requests_seen:
		if q[0] == "sign_messages":
			signed = Marshalls.base64_to_utf8(String(q[1]["messages"][0]))
	_expect(signed.begins_with("Yeetfleet: arm the sling") and signed.contains(Chain.pubkey()),
			"the wallet signs the run's arm message")
	_expect(r.ok and r.run_id != "" and bool(Session.pending_level.get("one_shot", false)), "ranked: a ticket, and no RETRY")
	await create_timer(1.2).timeout
	# A win under 3 s is refused by the Worker; inside the ticket's open time
	# plus its 5 s of clock slack is fine.
	Session.level_result = {"key": Session.pending_level.key, "won": true, "time": 4.0, "kills": 3, "hull": 1.0}
	got = DailySortie.take_result()
	_expect(got.ranked, "the result counts as ranked")
	await _reply()
	_expect(_replies.size() == 1 and _replies[0].ok and int(_replies[0].rank) == 1 and _replies[0].board == "ranked",
			"the Worker takes it: rank 1 on the ranked board")
	await DailySortie.refresh()
	_expect(DailySortie.ranked_left() == 0 and DailySortie.streak() == 1, "no ranked run left; the streak is the server's")
	r = await DailySortie.start(true)
	_expect(not r.ok and r.code == "no_attempts", "a second ranked run is refused")
	r = await DailySortie.start(false)
	await create_timer(1.2).timeout
	Session.level_result = {"key": Session.pending_level.key, "won": false, "time": 1.0, "kills": 2}
	DailySortie.take_result()
	await _reply()
	var board := await DailySortie.leaderboard("open")
	_expect(board.ok and board.rows.size() == 1 and board.rows[0].name == "Ace" and board.me.rank == 1,
			"practice goes on the open board, under the pilot's name")
	var ranked := await DailySortie.leaderboard("ranked")
	_expect(ranked.ok and ranked.rows.size() == 1 and int(ranked.rows[0].points) == int(got.points), "the ranked board has the ranked run")

	# --- The screen ---
	var screen := DailyScreen.new()
	root.add_child(screen)
	await process_frame
	screen.layout()
	screen._refresh()
	_expect(screen._ranked.disabled and screen._ranked.sub == "USED TODAY", "RANKED RUN says it's used today")
	_expect(screen._result.text.begins_with("PRACTICE RUN: LOST") and screen._result.text.contains("RANK 1"),
			"the screen shows the last run and its rank")
	screen.queue_free()
	_finish()


func _reply() -> void:
	var n := _replies.size()
	var until := Time.get_ticks_msec() + 5000
	while _replies.size() == n and Time.get_ticks_msec() < until:
		await process_frame


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	for p in [CHAIN_SCRATCH, DAILY_SCRATCH, CAMPAIGN_SCRATCH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("daily_check: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _tune() -> void:
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
