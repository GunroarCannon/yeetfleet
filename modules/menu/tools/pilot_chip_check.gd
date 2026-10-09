extends SceneTree
## Headless check of the Pilot ID chip on the addon's mock wallet: a tap
## signs in, a tap while the wallet is open cancels it, a failure shows on the
## chip in plain words (a cancel shows nothing), a signed-in tap opens the
## Pilot ID card, and DISCONNECT signs out and closes it. Then the home screen
## carries the chip and Back closes its card first.
##   "$GD" --headless --path . --audio-driver Dummy --script modules/menu/tools/pilot_chip_check.gd

const CHECK_SAVE := "user://pilot_chip_check.cfg"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	Chain.save_path = CHECK_SAVE
	Chain.api_url = ""
	Chain.reset(true)
	_tune()

	var chip := PilotChip.new()
	chip.size = Vector2(360, 60)
	root.add_child(chip)
	await process_frame
	await process_frame
	_expect(not Chain.is_connected_wallet(), "starts signed out")

	_tap(chip)
	_expect(Chain.busy(), "a tap signed out asks the wallet")
	_tap(chip)
	await _settle()
	_expect(not Chain.busy() and not Chain.is_connected_wallet(), "a tap while it waits cancels")
	_expect(chip._said_left == 0.0, "a cancel shows no words")

	Chain.client().mock.next_error = "declined"
	_tap(chip)
	await _settle()
	_expect(chip._said == Chain.say("declined") and chip._said_left > 0.0, "a refusal shows on the chip")

	_tap(chip)
	await _settle()
	_expect(Chain.is_connected_wallet(), "a tap signs in")
	_expect(not chip.card_open(), "signing in opens no card")

	_tap(chip)
	await process_frame
	_expect(chip.card_open(), "a tap signed in opens the Pilot ID card")
	chip._disconnect()
	await _settle()
	_expect(not Chain.is_connected_wallet() and not chip.card_open(), "DISCONNECT signs out and closes the card")
	chip.queue_free()

	# The home screen carries it, and Back closes its card before asking QUIT?.
	await Chain.sign_in()
	var home := HomeScreen.new()
	root.add_child(home)
	await process_frame
	await process_frame
	home.layout()
	var pilot := home._pilot
	_expect(pilot != null and pilot.is_inside_tree(), "home shows the Pilot ID")
	var vp := home.viewport_size()
	_expect(pilot != null and pilot.get_rect().end.x <= vp.x and pilot.get_rect().end.y <= vp.y
			and not pilot.get_rect().intersects(home._store.get_rect()), "it fits beside STORE")
	pilot._open_card()
	await process_frame
	home.back()
	await process_frame
	_expect(not pilot.card_open() and home._quit_card == null, "Back closes the card, not the game")
	home.queue_free()

	await Chain.disconnect_wallet()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_SAVE))
	print("pilot_chip_check: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## A quick mock, and an RPC that fails at once so nothing leaves the machine.
func _tune() -> void:
	Chain.client().mock.delay_sec = 0.05
	Chain.client().rpc_url = "http://127.0.0.1:9"


## A left click released on the chip, as a tap arrives.
func _tap(chip: PilotChip) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	chip._gui_input(mb)


## Long enough for the mock wallet to answer.
func _settle() -> void:
	var until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < until:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
