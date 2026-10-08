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

	await Chain.disconnect_wallet()
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


func _on_failed(what: String, code: String) -> void:
	_failed.append([what, code])


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
