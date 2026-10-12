extends SceneTree
## Headless check of the Chain façade on the addon's mock wallet: Sign-In-With-
## Solana, the session kept across launches, cancel, a failed confirmation,
## tips, buying needing the leaderboard, no wallet, disconnect. No network,
## no phone. (Buying with the leaderboard: chain_server_check.)
##   "$GD" --headless --path . --audio-driver Dummy --script modules/chain/tools/chain_check.gd

const CHECK_SAVE := "user://chain_check.cfg"
## Another valid key (Keypair.fromSeed(32 × 7) is the mock's own; this is the
## System Program's, which is fine as a tip target for the mock).
const OTHER := "11111111111111111111111111111111"

var _fails := 0
var _connected: Array[String] = []
var _disconnects := 0
var _paid: Array = []
var _failed: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	Chain.save_path = CHECK_SAVE
	Chain.api_url = ""
	Chain.reset(true)
	Chain.notifier.connected.connect(_on_connected)
	Chain.notifier.disconnected.connect(_on_disconnected)
	Chain.notifier.paid.connect(_on_paid)
	Chain.notifier.failed.connect(_on_failed)
	_tune()

	_expect(not Chain.is_native() and not Chain.is_connected_wallet(), "starts on the mock, signed out")
	_expect(Chain.cluster() == "devnet" and Chain.skr_mint() == Chain.SKR_DEVNET, "devnet and dSKR until mainnet")

	var r := await Chain.sign_in()
	var key := Chain.client().mock.public_key
	_expect(r.ok and Chain.pubkey() == key, "sign in sets the pilot's key")
	_expect(_connected == [key], "connected is emitted once")
	var text := Marshalls.base64_to_utf8(r.sign_in.signed_message) if r.ok else ""
	_expect(text.begins_with(Chain.siws_domain()) and text.contains(Chain.SIWS_STATEMENT),
			"the SIWS message names our domain and statement")

	Chain.reset(true)
	_tune()
	_expect(Chain.pubkey() == key and Chain.client().auth_token != "", "the session survives a relaunch")

	Chain.api_url = ""
	r = await Chain.buy("paint:skr_gold")
	_expect(not r.ok and r.code == "no_session" and _last_transfer().is_empty(),
			"buying needs the leaderboard: nothing is paid without it")
	_failed.clear()

	Chain.client().mock.next_error = "cancelled"
	r = await Chain.tip(OTHER, Chain.TIP_PRESETS[0])
	_expect(not r.ok and r.code == "cancelled", "a cancelled payment reports cancelled")
	_expect(_failed.size() == 1 and _failed[0] == ["tip", "cancelled"], "failed names what and the code")
	_expect(_paid.is_empty(), "nothing is paid for a cancel")

	Chain.client().mock.next_confirm_error = "tx_failed"
	r = await Chain.tip(OTHER, Chain.TIP_PRESETS[0])
	_expect(not r.ok and r.code == "tx_failed" and _paid.is_empty(), "a failed transaction isn't paid")

	r = await Chain.tip(OTHER, Chain.TIP_PRESETS[0])
	var spec := _last_transfer()
	_expect(r.ok and r.has("slot"), "a payment is confirmed before it counts")
	_expect(spec.get("to") == OTHER and spec.get("mint") == Chain.SKR_DEVNET and spec.get("amount") == "10000000"
			and int(spec.get("decimals", 0)) == 6, "a tip goes straight to the pilot, in dSKR base units")
	_expect(_paid.size() == 1 and _paid[0][0] == "tip", "paid is emitted once")
	r = await Chain.tip("not-a-key", 10)
	_expect(not r.ok and r.code == "invalid_request", "a tip to a bad key is refused before the wallet opens")

	r = await Chain.disconnect_wallet()
	_expect(not Chain.is_connected_wallet() and _disconnects == 1, "disconnect forgets the pilot")
	Chain.reset(true)
	_tune()
	_expect(not Chain.is_connected_wallet(), "and stays signed out after a relaunch")

	Chain.client().mock.wallet_installed = false
	r = await Chain.connect_wallet()
	_expect(not r.ok and r.code == "no_wallet", "no wallet installed -> no_wallet")

	_expect(Chain.TREASURY.length() >= 32 and not Chain.use_mainnet, "treasury set; mainnet only in a mainnet export")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	print("chain_check: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## A quick mock, and an RPC that fails at once so nothing leaves the machine.
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


func _on_connected(key: String) -> void:
	_connected.append(key)


func _on_disconnected() -> void:
	_disconnects += 1


func _on_paid(what: String, sig: String) -> void:
	_paid.append([what, sig])


func _on_failed(what: String, code: String) -> void:
	_failed.append([what, code])


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
