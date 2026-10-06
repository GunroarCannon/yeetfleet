## CoinStore: coin packs bought with real money, through RevenueCat.
##
## The module's façade. RevenueCat has no first-party Godot SDK; this talks to
## the GodotX RevenueCat plugin ([code]addons/godotx_revenue_cat[/code], the
## [code]GodotxRevenueCat[/code] Engine singleton, Godot 4.7+, Android and iOS)
## when the export carries it. Every coin pack is a consumable in-app product
## (see [constant PACKS]): bought, granted through [method Campaign.add_coins],
## and consumed by the SDK so it can be bought again.
##
## API keys: debug builds use RevenueCat's Test Store key ([constant
## TEST_API_KEY]), whose purchases are simulated by a RevenueCat dialog — no
## Play Console needed. Release builds use [constant ANDROID_API_KEY] /
## [constant IOS_API_KEY]; the SDK crashes on purpose if a release build is
## configured with a test key, so the test key is never used there, and with
## no release key the store simply reports itself closed.
##
## Without the plugin (the editor, desktop runs) a debug build fakes a
## successful purchase after a short pause, so the whole flow can be tried
## here; a release build without it shows the store as unavailable.
##
## A static façade like [GameAudio]: the signals live on [member notifier].
class_name CoinStore
extends RefCounted

## RevenueCat Test Store key (debug builds only).
const TEST_API_KEY := "test_gulPvTrQEctYxIyvcbHcvUBzPuG"
## RevenueCat → Project → API keys → the Google Play app's public key
## ("goog_…"). Empty: the release store stays closed.
const ANDROID_API_KEY := ""
## The App Store app's public key ("appl_…"), for an iOS release.
const IOS_API_KEY := ""
const SINGLETON := "GodotxRevenueCat"

## The packs, cheapest first: product id (the same id in RevenueCat, Play
## Console and App Store Connect), coins granted, the shelf word, and the
## price shown until the store reports the real, localised one.
const PACKS: Array[Dictionary] = [
	{"id": "yeetfleet_coins_small", "coins": 500, "word": "HANDFUL", "price": "$0.99"},
	{"id": "yeetfleet_coins_medium", "coins": 1500, "word": "SACK", "price": "$2.99", "bonus": "+20%"},
	{"id": "yeetfleet_coins_large", "coins": 4000, "word": "CRATE", "price": "$6.99", "bonus": "+40%"},
	{"id": "yeetfleet_coins_huge", "coins": 10000, "word": "VAULT", "price": "$14.99", "bonus": "+70%"},
]
## Seconds a faked purchase (debug, no plugin) takes.
const FAKE_DELAY := 0.6


## Emits [signal Notifier.purchased] (product id, coins granted), [signal
## Notifier.failed] (product id, a short reason; "" when the player
## cancelled) and [signal Notifier.prices_changed].
class Notifier:
	extends RefCounted
	signal purchased(id: String, coins: int)
	signal failed(id: String, reason: String)
	signal prices_changed


static var notifier := Notifier.new()
static var _rc: Object = null
static var _started := false
## Product id → the store's localised price text.
static var _prices := {}
## The pack being bought, while a purchase is open.
static var _pending := ""


## Start the SDK once (safe to call again): configure it with the key for
## this build and ask for the packs' prices.
static func start() -> void:
	if _started:
		return
	_started = true
	if not Engine.has_singleton(SINGLETON):
		return
	var key := _api_key()
	if key == "":
		return
	_rc = Engine.get_singleton(SINGLETON)
	_rc.connect("purchase_result", _on_purchase_result)
	_rc.connect("products", _on_products)
	_rc.call("initialize", key, "", OS.is_debug_build())
	var ids: Array[String] = []
	for p in PACKS:
		ids.append(String(p["id"]))
	_rc.call("fetch_products", ids)


## Whether the packs can be bought on this build.
static func available() -> bool:
	start()
	return _rc != null or OS.is_debug_build()


## Whether real-money buying is switched on: not yet in a shipped build, only
## with debug mode (the packs are not live for now).
static func purchases_enabled() -> bool:
	return Session.debug_mode and available()


## True while a purchase is open (the buttons wait).
static func busy() -> bool:
	return _pending != ""


## A pack by its product id, or {}.
static func pack(id: String) -> Dictionary:
	for p in PACKS:
		if String(p["id"]) == id:
			return p
	return {}


## What [param id] costs, as the store words it (or the fallback price).
static func price_text(id: String) -> String:
	return String(_prices.get(id, pack(id).get("price", "")))


## Buy the pack [param id]. The answer comes back on [member notifier].
static func buy(id: String) -> void:
	start()
	if busy() or pack(id).is_empty():
		return
	if not Session.debug_mode:
		notifier.failed.emit(id, "NOT AVAILABLE YET")
		return
	_pending = id
	if _rc != null:
		_rc.call("purchase", id)
	elif OS.is_debug_build():
		# No plugin here: pretend, so the flow can be tried on desktop.
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.create_timer(FAKE_DELAY, true, false, true).timeout.connect(
				_on_purchase_result.bind({"success": true, "fake": true}))
	else:
		_pending = ""
		notifier.failed.emit(id, "STORE CLOSED")


static func _api_key() -> String:
	if OS.is_debug_build():
		return TEST_API_KEY
	return IOS_API_KEY if OS.get_name() == "iOS" else ANDROID_API_KEY


static func _on_purchase_result(data: Dictionary) -> void:
	var id := _pending
	_pending = ""
	if id == "":
		return
	var err := String(data.get("error", ""))
	if err == "" and bool(data.get("success", true)):
		var coins := int(pack(id).get("coins", 0))
		Campaign.add_coins(coins)
		notifier.purchased.emit(id, coins)
		return
	# A cancelled purchase is not an error worth a word.
	var cancelled := bool(data.get("cancelled", false)) or err.to_lower().contains("cancel")
	notifier.failed.emit(id, "" if cancelled else "PURCHASE FAILED")


static func _on_products(data: Dictionary) -> void:
	var list: Variant = data.get("products", [])
	# The plugin hands Android's list over as a Java object; only a plain
	# array can be read here, and the fallback prices stand otherwise.
	if not (list is Array):
		return
	for p: Variant in list:
		if p is Dictionary and (p as Dictionary).has("id"):
			_prices[String(p["id"])] = String((p as Dictionary).get("price", ""))
	notifier.prices_changed.emit()
