## Screenshots of the flight end cards: the sandbox points card, a lost
## level ("ESCORT LOST") and a won one with NEXT. Windowed:
##     godot --path . --audio-driver Dummy --resolution 960x540 --script scratch/cards_shot.gd -- <out_dir> [w h cw ch]
extends SceneTree

const SCRATCH := "user://cards_shot_scratch.json"
var _out := "res://debug_shots/cards"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	if args.size() >= 5:
		# Window w h, laid out as a phone canvas cw ch (see menu_shot).
		root.size = Vector2i(int(args[1]), int(args[2]))
		DisplayServer.window_set_size(root.size)
		root.content_scale_size = Vector2i(int(args[3]), int(args[4]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	Campaign.save_path = SCRATCH
	Campaign.reset()
	_run.call_deferred()


func _run() -> void:
	# Sandbox: wrecked with some points.
	Campaign.launch_sandbox()
	Session.space_setup["events"] = []
	var f := await _flight()
	f.score = 700
	f.campaign_overlay._life_t = 40.0
	f.campaign_overlay.player_wrecked()
	await _wait(2.6)
	await _shot("card_sandbox")
	f.queue_free()
	await _wait(0.4)
	# A level: lost (escort), then won with NEXT.
	var lvl: Dictionary = Campaign.sectors()[0]["levels"][0]
	Campaign.launch(lvl)
	f = await _flight()
	f.campaign_overlay._show_card({"won": false, "time": 50.0, "kills": 2, "hull": 0.0, "reason": "ESCORT LOST"})
	await _wait(1.0)
	await _shot("card_lost")
	f.campaign_overlay._card.queue_free()
	f.campaign_overlay._card = null
	f.campaign_overlay._show_card({"won": true, "time": 30.0, "kills": 4, "hull": 0.8, "reason": ""})
	await _wait(1.6)
	await _shot("card_won")
	f.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	quit()


func _flight() -> FlightRoot:
	var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(f)
	current_scene = f
	await _wait(4.0)
	return f


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[cards_shot] ", name)


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
