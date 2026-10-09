## Chain: the pilot's Solana wallet, through Mobile Wallet Adapter.
##
## The module's façade over the [code]addons/solana_mobile[/code] addon
## ([SolanaMobileClient]). On Android with the plugin exported it talks to the
## wallet app on the phone (Phantom, Solflare, the Seeker's Seed Vault);
## everywhere else the addon's mock wallet answers, so the menus and the checks
## run on desktop and headless.
##
## Every wallet call is awaitable and returns the client's Dictionary:
## [code]{ok = true, …}[/code] or [code]{ok = false, code, message}[/code]. The
## same outcome also goes out on [member notifier], for UI that only listens.
## SKR purchases ([method buy]) go through the leaderboard Worker: it opens
## an order (the price and a memo), the wallet pays [constant TREASURY] with
## that memo, and the Worker finds the payment on chain before it grants
## anything. A payment the Worker hasn't seen yet is kept and asked about
## again ([method retry_pending]), so SKR taken is never lost. Tips go
## straight from wallet to wallet.
##
## With [constant WORKER_URL] set, [method sign_in] also opens a session with
## the leaderboard Worker (a server nonce in the signed message, checked
## there, plus the Seeker Genesis Token check). Without it, or when the Worker
## can't be reached, the wallet still signs in and play is unranked.
##
## A static façade like [CoinStore]: the signals live on [member notifier].
class_name Chain
extends RefCounted

## Off until the mainnet launch (G6): devnet and the test mint dSKR until then.
const USE_MAINNET := false
const APP_NAME := "Yeetfleet"
## The dApp identity wallets show, and the domain Sign-In-With-Solana names.
## It must serve /.well-known/assetlinks.json for the APK, or Phantom asks for
## approval again on every reconnect.
const IDENTITY_URI := "https://gunroarcannon.github.io"
const SIWS_DOMAIN := "gunroarcannon.github.io"
const SIWS_STATEMENT := "Sign in to Yeetfleet as this pilot"
## Relative to [constant IDENTITY_URI].
const ICON := "favicon.ico"
## SKR on mainnet (classic SPL Token, 6 decimals) and dSKR, our devnet stand-in
## with the same decimals (minted by us; see docs/solana-wallets.md).
const SKR_MAINNET := "SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3"
const SKR_DEVNET := "J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK"
const SKR_DECIMALS := 6
## Where SKR payments go: the same address on devnet and mainnet
## (docs/solana-wallets.md).
const TREASURY := "2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1"
## What things cost, in whole SKR, by kind (about $0.02 each on 2026-10-08;
## the reasoning is in docs/decisions/2026-10-06-solana-seeker-plan.md). The
## Worker's order sets the real amount; these are for showing.
const PRICES := {
	"extra_attempt": 25,
	"paint": 50,
	"trail": 100,
}
## What SKR buys besides extra ranked runs: liveries (factions in
## data/factions.json, worn over every hull) and sling trails (the player's
## trail colour in flight). Kept for good once bought.
const COSMETICS := {
	"paint:skr_solana": {"name": "SOLANA", "colors": ["9945ff", "14f195", "0e0e16"]},
	"paint:skr_seeker": {"name": "SEEKER", "colors": ["f2f2ea", "1df2c4", "1b1d24"]},
	"paint:skr_gold": {"name": "24 KARAT", "colors": ["ffc21a", "fff1b0", "3a2a08"]},
	"trail:mint": {"name": "MINT TRAIL", "colors": ["14f195"]},
	"trail:violet": {"name": "VIOLET TRAIL", "colors": ["b061ff"]},
	"trail:gold": {"name": "GOLD TRAIL", "colors": ["ffc21a"]},
}
## The tip buttons on a leaderboard row, in whole SKR.
const TIP_PRESETS: Array[int] = [10, 50, 100]
const SAVE_PATH := "user://chain.cfg"
## The leaderboard Worker (services/leaderboard-worker), deployed on
## Cloudflare; "" keeps everything offline and unranked.
const WORKER_URL := "https://yeetfleet.yeetfleet-leaderboard-worker.workers.dev"

const Api := preload("res://modules/chain/scripts/chain_api.gd")


## Emits [signal Notifier.connected] (the pilot's public key), [signal
## Notifier.disconnected], [signal Notifier.paid] (what was bought or
## "tip", and the confirmed signature) and [signal Notifier.failed] (what was
## tried and the client's failure code; "cancelled" is the pilot backing out,
## not an error worth a word). [signal Notifier.session_changed]: the
## leaderboard session opened or closed ([method has_session]).
class Notifier:
	extends RefCounted
	signal connected(pubkey: String)
	signal disconnected
	signal session_changed
	signal paid(what: String, signature: String)
	signal failed(what: String, code: String)


static var notifier := Notifier.new()
## Where the session is kept between launches (the checks point it elsewhere).
static var save_path := SAVE_PATH
## The Worker's address ([constant WORKER_URL]; the checks point it at a
## local one).
static var api_url := WORKER_URL
static var _client: SolanaMobileClient = null
## The leaderboard session: {token, expires (unix s), seeker, name}; empty
## when there is none.
static var _session := {}
## Payments made but not yet granted by the Worker: [{order_id, signature,
## item}]. Kept on disk until the Worker answers either way.
static var _pending: Array = []
## Cosmetics the Worker says this pilot owns (COSMETICS keys), and the one
## worn of each kind: {"paint": key or "", "trail": key or ""}.
static var _owned: Array = []
static var _equipped := {"paint": "", "trail": ""}


## The addon client, made on first use with the saved session restored.
static func client() -> SolanaMobileClient:
	if _client == null:
		_make(false)
	return _client


## Start over with a fresh client: the mock wallet when [param force_mock],
## even on a phone. For the checks.
static func reset(force_mock := false) -> void:
	_make(force_mock)


static func cluster() -> String:
	return "mainnet-beta" if USE_MAINNET else "devnet"


## The SKR mint for [method cluster].
static func skr_mint() -> String:
	return SKR_MAINNET if USE_MAINNET else SKR_DEVNET


static func pubkey() -> String:
	return client().public_key


static func is_connected_wallet() -> bool:
	return client().is_connected_wallet()


## True when a real wallet answers (Android with the plugin), false on the mock.
static func is_native() -> bool:
	return client().is_native()


## True while a wallet request is open (the buttons wait).
static func busy() -> bool:
	return client().is_busy()


## [code]{manufacturer, model, solana_mobile, seeker, seed_vault, …}[/code].
static func device() -> Dictionary:
	return client().device_info()


## A Solana Seeker, by the phone's own word. The Genesis Token is what
## counts for ranked play: [method has_genesis].
static func is_seeker() -> bool:
	return bool(device().get("seeker", false))


## Signed in with the leaderboard Worker, and the session hasn't run out.
static func has_session() -> bool:
	return _session.get("token", "") != "" and int(_session.get("expires", 0)) > int(Time.get_unix_time_from_system())


## The session's bearer token for the Worker ("" without one).
static func session_token() -> String:
	return String(_session.get("token", "")) if has_session() else ""


## The Worker found a Seeker Genesis Token in the pilot's wallet: ranked play.
static func has_genesis() -> bool:
	return has_session() and bool(_session.get("seeker", false))


## GET [param path] from the leaderboard Worker, with the session's token
## when there is one. [code]{ok, …body}[/code] or [code]{ok = false, code}[/code]
## ("offline" when it can't be reached or isn't set up).
static func server_get(path: String) -> Dictionary:
	return await Api.fetch(api_url, path, session_token())


## POST [param body] to the leaderboard Worker (see [method server_get]).
static func server_post(path: String, body: Dictionary) -> Dictionary:
	return await Api.post(api_url, path, body, session_token())


## Ends the open wallet request as "cancelled".
static func cancel() -> void:
	client().cancel()


## A wallet key as the menus show it: "GE7b…HLdK".
static func short_key(key: String) -> String:
	return "" if key.length() < 9 else key.left(4) + "…" + key.right(4)


## A failure code in a few plain words for the pilot; "" for "cancelled"
## (backing out needs no reply).
static func say(code: String) -> String:
	match code:
		"cancelled":
			return ""
		"no_wallet":
			return "Get a Solana wallet first (Phantom, Solflare)"
		"declined":
			return "The wallet said no"
		"timeout", "connection_failed":
			return "The wallet didn't answer. Try again"
		"unauthorized":
			return "Sign in again"
		"busy":
			return "The wallet is already open"
		"server_offline":
			return "Leaderboard offline. Playing unranked"
		"server_refused":
			return "The leaderboard refused the sign-in. Try again"
		"tx_failed":
			return "The payment failed on chain. Nothing was taken"
		"no_session":
			return "Sign in first (the Pilot ID)"
		"not_seeker":
			return "Extra ranked runs are for Seeker Genesis pilots"
		"owned":
			return "Already yours"
		"paid_pending":
			return "Paid. It's added as soon as the leaderboard sees the payment"
		"wrong_memo", "underpaid", "order_paid", "sig_used":
			return "That payment didn't match the order. Nothing granted"
		"not_confirmed":
			return "Not confirmed yet. Check again soon"
		"not_submitted":
			return "The wallet couldn't send it. Enough SKR and SOL?"
		"cluster_not_supported":
			return "Switch the wallet to devnet (Testnet mode)" if not USE_MAINNET else "Switch the wallet to mainnet"
		"rpc_error":
			return "No connection to Solana"
	return "Wallet trouble (%s)" % code


# --- Wallet ---

## Connect, or reconnect silently with the saved session.
static func connect_wallet() -> Dictionary:
	return _after("connect", await client().connect_wallet())


## Connect and Sign-In-With-Solana in one prompt, and open the leaderboard
## session: the Worker's nonce goes into the signed message and the Worker
## checks it. [param pilot_name] is the name the leaderboard shows. When the
## Worker is away the wallet still signs in; the result then has
## [code]server[/code] set to the reason, and play is unranked.
static func sign_in(pilot_name := "") -> Dictionary:
	if api_url == "":
		return _after("sign_in", await client().sign_in(SIWS_DOMAIN, SIWS_STATEMENT))
	var ch := await Api.post(api_url, "/auth/challenge", {})
	if not ch.ok:
		var local := _after("sign_in", await client().sign_in(SIWS_DOMAIN, SIWS_STATEMENT))
		if local.ok:
			local["server"] = ch.code
			notifier.failed.emit("server", "server_offline")
		return local
	var r := _after("sign_in", await client().sign_in(String(ch.domain), SIWS_STATEMENT, ch.fields))
	if not r.ok:
		return r
	var v := await Api.post(api_url, "/auth/verify", {
		"public_key": client().public_key,
		"signed_message": r.sign_in.signed_message,
		"signature": r.sign_in.signature,
		"name": pilot_name,
	})
	if not v.ok:
		r["server"] = v.code
		notifier.failed.emit("server", "server_offline" if v.code == "offline" else "server_refused")
		return r
	_session = {
		"token": v.token,
		"expires": int(Time.get_unix_time_from_system()) + int(v.get("expires_in", 3600)) - 60,
		"seeker": bool(v.pilot.get("seeker", false)),
		"name": String(v.pilot.get("name", "")),
	}
	_save()
	notifier.session_changed.emit()
	r["pilot"] = v.pilot
	# Anything paid for while the server was away, and what this pilot owns.
	await retry_pending()
	await refresh_shop()
	return r


## Revoke the session in the wallet, and forget it here either way.
static func disconnect_wallet() -> Dictionary:
	var r := await client().disconnect_wallet()
	_end_session()
	return r


## The pilot's SKR, in whole SKR; -1 when the RPC can't be reached.
static func skr_balance() -> float:
	var b := await client().token_balance(skr_mint())
	return float(b.get("ui", -1.0)) if not b.is_empty() else -1.0


# --- SKR ---

## Buy [param item] (a [constant COSMETICS] key, or "extra_attempt") with
## SKR: an order from the Worker, the payment with its memo, then the Worker
## checks it on chain and grants it. Needs the leaderboard session. Returns
## [code]{ok, item, signature, owned, ranked_left?}[/code]. On "paid_pending"
## the SKR went out but the Worker hasn't seen it yet: it is kept and asked
## about again ([method retry_pending]).
static func buy(item: String) -> Dictionary:
	if not has_session():
		return _fail(item, "no_session", "Sign in first")
	var o := await server_post("/order/new", {"item": item})
	if not o.ok:
		return _fail(item, String(o.code), String(o.get("message", "")))
	if String(o.mint) != skr_mint() or String(o.to) != TREASURY:
		return _fail(item, "cluster_mismatch", "The leaderboard wants another token or treasury")
	var r := await _send(item, String(o.to), int(o.price), String(o.memo))
	if not r.ok:
		return r
	var pay := {"order_id": String(o.order_id), "signature": String(r.signatures[0]), "item": item}
	_pending.append(pay)
	_save()
	return await _verify(pay)


## Ask the Worker again about payments it hadn't seen. Returns how many were
## granted.
static func retry_pending() -> int:
	var n := 0
	for pay: Dictionary in _pending.duplicate():
		if has_session() and (await _verify(pay, 1)).ok:
			n += 1
	return n


## Payments waiting for the Worker.
static func pending_count() -> int:
	return _pending.size()


## The Worker's catalog and, signed in, what this pilot owns: [code]{ok,
## catalog, owned?}[/code].
static func refresh_shop() -> Dictionary:
	var r := await server_get("/shop")
	if r.ok and r.has("owned"):
		_owned = r.owned
		for kind: String in _equipped:
			if _equipped[kind] != "" and not _owned.has(_equipped[kind]):
				_equipped[kind] = ""
		_save()
	return r


static func owns(item: String) -> bool:
	return _owned.has(item)


## Owned cosmetics, as [constant COSMETICS] keys.
static func owned() -> Array:
	return _owned.duplicate()


## What [param item] costs, in whole SKR (its kind's price).
static func price_of(item: String) -> int:
	return int(PRICES.get(item.get_slice(":", 0), 0))


## Wear [param item], an owned cosmetic (one of each kind at a time).
static func equip(item: String) -> bool:
	var kind := item.get_slice(":", 0)
	if not _equipped.has(kind) or not owns(item):
		return false
	_equipped[kind] = item
	_save()
	return true


## Take off the worn cosmetic of [param kind].
static func unequip(kind: String) -> void:
	if _equipped.has(kind):
		_equipped[kind] = ""
		_save()


## The worn cosmetic of [param kind] ("paint" or "trail"): its key, or "".
static func equipped(kind: String) -> String:
	client()
	return String(_equipped.get(kind, ""))


## The worn livery's faction id ("skr_gold"), or "".
static func livery() -> String:
	var k := equipped("paint")
	return k.get_slice(":", 1) if k != "" else ""


## The worn sling trail's colour, or transparent without one.
static func trail_color() -> Color:
	var k := equipped("trail")
	return Color(String(COSMETICS[k]["colors"][0])) if COSMETICS.has(k) else Color(0, 0, 0, 0)


## Send [param amount] whole SKR straight to another pilot: no custody, the
## treasury never touches it.
static func tip(to: String, amount: int) -> Dictionary:
	var r := await _send("tip", to, amount, "yeetfleet:tip")
	if r.ok:
		notifier.paid.emit("tip", String(r.signatures[0]))
	return r


# --- Plumbing ---

static func _make(force_mock: bool) -> void:
	if _client != null and _client.account_changed.is_connected(_on_account_changed):
		_client.account_changed.disconnect(_on_account_changed)
	_client = SolanaMobileClient.new(APP_NAME, IDENTITY_URI, ICON, cluster(), force_mock)
	_session = {}
	_pending = []
	_owned = []
	_equipped = {"paint": "", "trail": ""}
	_load()
	_client.account_changed.connect(_on_account_changed)


## Transfer, then wait for the chain: a wallet's ok only means "submitted".
static func _send(what: String, to: String, amount: int, memo: String) -> Dictionary:
	if amount <= 0:
		return _fail(what, "invalid_request", "Nothing to pay")
	var base := amount * int(pow(10, SKR_DECIMALS))
	var r := _after(what, await client().transfer(to, base, skr_mint(), SKR_DECIMALS, memo))
	if not r.ok:
		return r
	var sig: String = r.signatures[0]
	var c := await client().confirm(sig)
	if not c.ok:
		return _fail(what, c.code, c.message)
	r["slot"] = c.slot
	return r


## Codes from /order/verify that mean "not seen yet, ask again later".
const _NOT_YET := ["tx_not_found", "rpc_error", "offline", "server_error", "no_session"]


## Ask the Worker to grant [param pay], up to [param tries] times while it
## hasn't seen the payment (2 s apart). Emits paid once granted. A payment it
## still hasn't seen stays pending; one it refuses is dropped.
static func _verify(pay: Dictionary, tries := 8) -> Dictionary:
	var item := String(pay["item"])
	var v := {}
	for i in tries:
		v = await server_post("/order/verify", {"order_id": pay["order_id"], "signature": pay["signature"]})
		if v.ok or not v.code in _NOT_YET:
			break
		if i < tries - 1:
			await (Engine.get_main_loop() as SceneTree).create_timer(2.0, true, false, true).timeout
	if not v.ok and v.code in _NOT_YET:
		return _fail(item, "paid_pending", "Paid; not granted yet")
	_pending.erase(pay)
	if not v.ok:
		_save()
		return _fail(item, String(v.code), String(v.get("message", "")))
	_owned = v.get("owned", _owned)
	_save()
	notifier.paid.emit(item, String(pay["signature"]))
	v["signature"] = pay["signature"]
	return v


## Save the session after any wallet call (its token may have changed) and
## report a failure.
static func _after(what: String, r: Dictionary) -> Dictionary:
	_save()
	if not r.ok:
		notifier.failed.emit(what, String(r.code))
	return r


static func _fail(what: String, code: String, message: String) -> Dictionary:
	notifier.failed.emit(what, code)
	return {"ok": false, "code": code, "message": message}


static func _on_account_changed(key: String) -> void:
	# Another account (or none) can't keep the old pilot's session.
	if key != _session.get("pubkey", key):
		_end_session()
	if key == "":
		notifier.disconnected.emit()
	else:
		notifier.connected.emit(key)


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shop", "pending", _pending)
	cfg.set_value("shop", "owned", _owned)
	cfg.set_value("shop", "equipped", _equipped)
	cfg.set_value("wallet", "auth_token", _client.auth_token)
	cfg.set_value("wallet", "public_key", _client.public_key)
	if not _session.is_empty():
		_session["pubkey"] = _client.public_key
		cfg.set_value("server", "session", _session)
	cfg.save(save_path)


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	_client.auth_token = String(cfg.get_value("wallet", "auth_token", ""))
	_client.public_key = String(cfg.get_value("wallet", "public_key", ""))
	_pending = cfg.get_value("shop", "pending", [])
	_owned = cfg.get_value("shop", "owned", [])
	var eq: Variant = cfg.get_value("shop", "equipped", {})
	if eq is Dictionary:
		_equipped.merge(eq, true)
	var saved: Variant = cfg.get_value("server", "session", {})
	_session = saved if saved is Dictionary and saved.get("pubkey", "") == _client.public_key else {}


static func _end_session() -> void:
	var had := not _session.is_empty()
	_session = {}
	# What's owned is the signed-in pilot's; payments waiting stay (SKR spent).
	_owned = []
	_equipped = {"paint": "", "trail": ""}
	if _client != null:
		_save()
	if had:
		notifier.session_changed.emit()
