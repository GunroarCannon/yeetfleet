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
## SKR payments go to [constant TREASURY] and only count once they are
## confirmed on chain; the leaderboard Worker re-checks each one before it
## grants anything (milestone G4).
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
## What things cost, in whole SKR (about $0.02 each on 2026-10-08; the
## reasoning is in docs/decisions/2026-10-06-solana-seeker-plan.md).
const PRICES := {
	"extra_attempt": 25,
	"paint": 50,
	"decal": 75,
	"trail": 100,
}
## The tip buttons on a leaderboard row, in whole SKR.
const TIP_PRESETS: Array[int] = [10, 50, 100]
const SAVE_PATH := "user://chain.cfg"


## Emits [signal Notifier.connected] (the pilot's public key), [signal
## Notifier.disconnected], [signal Notifier.paid] (what was bought or
## "tip", and the confirmed signature) and [signal Notifier.failed] (what was
## tried and the client's failure code; "cancelled" is the pilot backing out,
## not an error worth a word).
class Notifier:
	extends RefCounted
	signal connected(pubkey: String)
	signal disconnected
	signal paid(what: String, signature: String)
	signal failed(what: String, code: String)


static var notifier := Notifier.new()
## Where the session is kept between launches (the checks point it elsewhere).
static var save_path := SAVE_PATH
static var _client: SolanaMobileClient = null


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


## A Solana Seeker. Its Genesis Token is checked by the Worker, not here (G2).
static func is_seeker() -> bool:
	return bool(device().get("seeker", false))


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
		"tx_failed":
			return "The payment failed on chain. Nothing was taken"
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


## Connect and Sign-In-With-Solana in one prompt. The result's
## [code]sign_in[/code] ([code]signed_message[/code], [code]signature[/code],
## base64) is what the Worker verifies (G2).
static func sign_in() -> Dictionary:
	return _after("sign_in", await client().sign_in(SIWS_DOMAIN, SIWS_STATEMENT))


## Revoke the session in the wallet, and forget it here either way.
static func disconnect_wallet() -> Dictionary:
	var r := await client().disconnect_wallet()
	_save()
	return r


## The pilot's SKR, in whole SKR; -1 when the RPC can't be reached.
static func skr_balance() -> float:
	var b := await client().token_balance(skr_mint())
	return float(b.get("ui", -1.0)) if not b.is_empty() else -1.0


# --- SKR ---

## Pay [constant PRICES] of [param item] to the treasury. [param memo] carries
## the Worker's order nonce once there is one (G4).
static func buy(item: String, memo := "") -> Dictionary:
	if not PRICES.has(item):
		return _fail(item, "invalid_request", "No price for '%s'" % item)
	return await pay_skr(item, int(PRICES[item]), memo)


## Pay [param amount] whole SKR to the treasury, for [param what].
static func pay_skr(what: String, amount: int, memo := "") -> Dictionary:
	return await _send(what, TREASURY, amount, memo if memo != "" else "yeetfleet:" + what)


## Send [param amount] whole SKR straight to another pilot: no custody, the
## treasury never touches it.
static func tip(to: String, amount: int) -> Dictionary:
	return await _send("tip", to, amount, "yeetfleet:tip")


# --- Plumbing ---

static func _make(force_mock: bool) -> void:
	if _client != null and _client.account_changed.is_connected(_on_account_changed):
		_client.account_changed.disconnect(_on_account_changed)
	_client = SolanaMobileClient.new(APP_NAME, IDENTITY_URI, ICON, cluster(), force_mock)
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
	notifier.paid.emit(what, sig)
	return r


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
	if key == "":
		notifier.disconnected.emit()
	else:
		notifier.connected.emit(key)


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "auth_token", _client.auth_token)
	cfg.set_value("wallet", "public_key", _client.public_key)
	cfg.save(save_path)


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	_client.auth_token = String(cfg.get_value("wallet", "auth_token", ""))
	_client.public_key = String(cfg.get_value("wallet", "public_key", ""))
