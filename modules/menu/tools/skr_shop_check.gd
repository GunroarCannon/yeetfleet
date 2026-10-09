extends SceneTree
## Headless check of the SKR shop UI against the real Worker code on
## localhost (test/dev_server.js, the mock wallet as a Genesis pilot): the
## STORE's SKR tab signed out, then signed in; buying a livery from its card
## (granted, worn, the toast); +1 RANKED RUN on the daily screen once today's
## run is used; a tip from the board's tip card. Needs `node` on PATH.
##   "$GD" --headless --path . --audio-driver Dummy --script modules/menu/tools/skr_shop_check.gd

const PORT := 8796
const CHAIN_SCRATCH := "user://skr_shop_check_chain.cfg"
const DAILY_SCRATCH := "user://skr_shop_check_daily.cfg"
const CAMPAIGN_SCRATCH := "user://skr_shop_check_campaign.json"
const OTHER := "GE7bEoKnVEkPQ7U7sQswPqq2AbZfNWEgMxcQiYjyHLdK"

var _fails := 0
var _pid := -1
var _toasts: Array = []


func _initialize() -> void:
	Campaign.save_path = CAMPAIGN_SCRATCH
	Campaign.reset()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for p in [CHAIN_SCRATCH, DAILY_SCRATCH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var out: Array = []
	if OS.execute("node", ["--version"], out) != 0:
		print("skr_shop_check: SKIP (node not on PATH)")
		quit(0)
		return
	_pid = OS.create_process("node", [ProjectSettings.globalize_path("res://services/leaderboard-worker/test/dev_server.js"), str(PORT)])
	Chain.save_path = CHAIN_SCRATCH
	Chain.api_url = "http://127.0.0.1:%d" % PORT
	Chain.reset(true)
	_tune()
	DailySortie.save_path = DAILY_SCRATCH
	DailySortie.reset()
	var up := false
	for i in 40:
		if (await Chain.server_get("/health")).ok:
			up = true
			break
		await create_timer(0.25).timeout
	_expect(up, "the dev Worker is up")
	if not up:
		return _finish()

	# --- The SKR tab ---
	var panel := SkrShopPanel.new()
	panel.size = Vector2(1200, 560)
	root.add_child(panel)
	panel.toast.connect(func(t: String, _c: Color) -> void: _toasts.append(t))
	await process_frame
	panel.place(1.0, false)
	await panel.opened()
	_expect(panel._sign_in.visible and panel._head.text.begins_with("SIGN IN"), "signed out: the header asks to sign in")
	_expect(panel._cards[1]._slab.disabled and panel._cards[1]._slab.sub == "SIGN IN", "and the cards wait for it")
	await panel._on_sign_in()
	_expect(Chain.has_session() and not panel._sign_in.visible, "SIGN IN opens the session")
	var gold: Variant = panel._cards[ITEM_INDEX("paint:skr_gold")]
	_expect(gold._slab.text == "50 SKR" and not gold._slab.disabled, "a livery card shows its price")
	await panel._on_act("paint:skr_gold")
	_expect(Chain.owns("paint:skr_gold") and Chain.livery() == "skr_gold", "buying it grants it and wears it")
	_expect(_toasts == ["24 KARAT!"] and gold._slab.text == "WORN ✓", "a toast, and the card says WORN")
	await panel._on_act("paint:skr_gold")
	_expect(Chain.livery() == "" and gold._slab.text == "WEAR", "pressing WORN takes it off")
	var attempt: Variant = panel._cards[0]
	_expect(not attempt._slab.disabled and attempt._slab.text == "25 SKR", "a Genesis pilot can buy an extra ranked run")
	panel.queue_free()

	# --- The daily screen: +1 RANKED RUN, then a tip ---
	await DailySortie.refresh()
	var r := await DailySortie.start(true)
	_expect(r.ok, "today's ranked run is started")
	await DailySortie.refresh()
	var screen := DailyScreen.new()
	root.add_child(screen)
	await process_frame
	screen.layout()
	screen._refresh()
	_expect(screen._extra.visible and screen._ranked.sub == "USED TODAY", "used today: +1 RANKED RUN shows")
	await screen._on_extra()
	_expect(DailySortie.ranked_left() == 1 and not screen._extra.visible and not screen._ranked.disabled,
			"bought: RANKED RUN is back")
	screen._open_tip(OTHER, "Bee")
	_expect(screen._tip_card != null, "TIP opens the tip card")
	await screen._send_tip(OTHER, "Bee", Chain.TIP_PRESETS[0])
	var spec := _last_transfer()
	_expect(spec.get("to") == OTHER and spec.get("amount") == "10000000" and screen._tip_card == null,
			"a tip goes from this wallet straight to the pilot's")
	_expect(screen._note.text.begins_with("Tipped Bee"), "and says so")
	screen.queue_free()
	_finish()


## Index of [param item] in [constant SkrShopPanel.ITEMS].
func ITEM_INDEX(item: String) -> int:
	return SkrShopPanel.ITEMS.find(item)


func _last_transfer() -> Dictionary:
	var seen: Array = Chain.client().mock.requests_seen
	for i in range(seen.size() - 1, -1, -1):
		if seen[i][0] == "transfer":
			return seen[i][1].get("transfer", {})
	return {}


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	for p in [CHAIN_SCRATCH, DAILY_SCRATCH, CAMPAIGN_SCRATCH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("skr_shop_check: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _tune() -> void:
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
