extends SceneTree
## Headless check of Chain against the real leaderboard Worker code, served
## locally by Node (services/leaderboard-worker/test/dev_server.js) with the
## addon's mock wallet: the server nonce goes into the signed message, the
## session opens with the Genesis status, survives a relaunch and ends on
## disconnect, and a missing server still signs in, unranked. Needs `node`
## (22.5+) on PATH; without it the check says SKIP.
##   "$GD" --headless --path . --audio-driver Dummy --script modules/chain/tools/chain_server_check.gd

const CHECK_SAVE := "user://chain_server_check.cfg"
const PORT := 8799

var _fails := 0
var _pid := -1
var _session_changes := 0
var _failed: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var out: Array = []
	if OS.execute("node", ["--version"], out) != 0:
		print("chain_server_check: SKIP (node not on PATH)")
		quit(0)
		return
	_pid = OS.create_process("node", [ProjectSettings.globalize_path("res://services/leaderboard-worker/test/dev_server.js"), str(PORT)])
	var base := "http://127.0.0.1:%d" % PORT
	var up := false
	for i in 40:
		var h: Dictionary = await Chain.Api.fetch(base, "/health")
		if h.ok:
			up = true
			break
		await create_timer(0.25).timeout
	_expect(up, "the dev Worker answers /health")
	if not up:
		return _finish()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	Chain.save_path = CHECK_SAVE
	Chain.api_url = base
	Chain.reset(true)
	_tune()
	Chain.notifier.session_changed.connect(func() -> void: _session_changes += 1)
	Chain.notifier.failed.connect(_on_failed)

	var r := await Chain.sign_in("Ace")
	var asked: Dictionary = Chain.client().mock.requests_seen[-1][1].get("sign_in", {})
	_expect(String(asked.get("nonce", "")).length() == 32, "the wallet is asked to sign the server's nonce")
	_expect(r.ok and not r.has("server"), "sign in opens a leaderboard session")
	_expect(Chain.has_session() and Chain.session_token() != "", "a session token is kept")
	_expect(Chain.has_genesis(), "the dev Worker counts the mock wallet as a Genesis holder")
	_expect(r.get("pilot", {}).get("name") == "Ace", "the pilot's name reaches the leaderboard")
	_expect(_session_changes == 1, "session_changed is emitted once")

	var me: Dictionary = await Chain.Api.fetch(base, "/me", Chain.session_token())
	_expect(me.ok and me.pilot.public_key == Chain.pubkey(), "the token opens /me")

	Chain.reset(true)
	_tune()
	_expect(Chain.has_session() and Chain.has_genesis(), "the session survives a relaunch")

	# --- SKR (G4): order → payment with the order's memo → checked → granted ---
	var shop := await Chain.refresh_shop()
	_expect(shop.ok and shop.mint == Chain.skr_mint() and shop.treasury == Chain.TREASURY and Chain.owned().is_empty(),
			"the Worker's shop names our mint and treasury; nothing owned yet")
	var paid: Array = []
	Chain.notifier.paid.connect(func(what: String, _sig: String) -> void: paid.append(what))
	r = await Chain.buy("paint:skr_gold")
	var spec := _last_transfer()
	_expect(r.ok and Chain.owns("paint:skr_gold") and paid == ["paint:skr_gold"], "a livery is paid, checked and granted")
	_expect(spec.get("to") == Chain.TREASURY and spec.get("mint") == Chain.SKR_DEVNET and spec.get("amount") == "50000000",
			"50 dSKR to the treasury, in base units")
	_expect(String(spec.get("memo", "")).begins_with("yeetfleet:") and String(spec.get("memo", "")).length() > 20,
			"the memo is the Worker's order")
	_expect(Chain.equip("paint:skr_gold") and Chain.livery() == "skr_gold", "worn: the livery every hull flies in")
	_expect(String(Campaign.flight_ship("kestrel").get("paint", "")) == "skr_gold",
			"a flight's ship wears it")
	_expect(not Chain.equip("trail:mint"), "only owned things can be worn")
	r = await Chain.buy("paint:skr_gold")
	_expect(not r.ok and r.code == "owned", "a cosmetic is bought once")

	Chain.client().mock.next_confirm_error = "tx_failed"
	r = await Chain.buy("trail:violet")
	_expect(not r.ok and r.code == "tx_failed" and not Chain.owns("trail:violet") and Chain.pending_count() == 0,
			"a failed payment grants nothing and leaves nothing waiting")

	var day: Dictionary = await Chain.server_get("/daily")
	var before := int(day.me.ranked_left)
	r = await Chain.buy("extra_attempt")
	_expect(r.ok and int(r.ranked_left) == before + 1, "an extra ranked run is granted for today")

	# Paid while the Worker was away: kept, and granted on the next try.
	var o: Dictionary = await Chain.server_post("/order/new", {"item": "trail:gold"})
	Chain._pending.append({"order_id": o.order_id, "signature": "MockSigPending", "item": "trail:gold"})
	Chain._save()
	Chain.reset(true)
	_tune()
	_expect(Chain.pending_count() == 1, "a payment not yet granted survives a relaunch")
	_expect(await Chain.retry_pending() == 1 and Chain.owns("trail:gold") and Chain.pending_count() == 0,
			"and is granted when the Worker sees it")
	_expect(Chain.equip("trail:gold") and Chain.trail_color().is_equal_approx(Color("ffc21a")), "a trail is worn in its colour")
	_expect(String(Campaign.flight_ship("kestrel").get("trail", "")) != "",
			"a flight's ship carries the trail")

	await Chain.disconnect_wallet()
	_expect(Chain.livery() == "" and Chain.owned().is_empty(), "signed out, nothing is worn")
	_expect(not Chain.has_session(), "disconnect ends the session")
	Chain.reset(true)
	_tune()
	_expect(not Chain.has_session(), "and it stays ended after a relaunch")

	# The server away: the wallet still signs in, play is unranked.
	Chain.api_url = "http://127.0.0.1:9"
	_failed.clear()
	r = await Chain.sign_in("Ace")
	_expect(r.ok and r.get("server") == "offline" and Chain.is_connected_wallet(), "no server: still signed in to the wallet")
	_expect(not Chain.has_session() and _failed.has(["server", "server_offline"]), "no server: no session, and the chip is told")
	await Chain.disconnect_wallet()
	_finish()


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	print("chain_server_check: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## A quick mock, and a Solana RPC that fails at once so nothing leaves the machine.
func _tune() -> void:
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"


## The transfer spec of the mock's latest request.
func _last_transfer() -> Dictionary:
	var seen: Array = Chain.client().mock.requests_seen
	for i in range(seen.size() - 1, -1, -1):
		if seen[i][0] == "transfer":
			return seen[i][1].get("transfer", {})
	return {}


func _on_failed(what: String, code: String) -> void:
	_failed.append([what, code])


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
