## Screenshots the flight test's UI at any window size — portrait phones,
## small landscape screens — to check nothing hangs off the edge: the desktop
## HUD, a debug panel open over it, the debug column, the phone HUD, and the
## Controls panel, and the swipe (mid-swipe, with its 3D arrow), FPS and
## slingshot (mid-aim) profiles.
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy --script modules/flight/tools/portrait_ui_shot.gd -- out_dir [width] [height]
##
## Windowed (needs a real renderer). Writes `<out_dir>/ui_<w>x<h>_<name>.png`.
## Settings are changed in memory only.
extends SceneTree

var _out := "."
var _size := Vector2i(540, 960)
var _f: FlightRoot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = "." if args.is_empty() else String(args[0])
	if args.size() >= 3:
		_size = Vector2i(int(args[1]), int(args[2]))
	DisplayServer.window_set_size(_size)
	root.set_content_scale_size(_size)
	root.size = _size
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	_f = packed.instantiate() as FlightRoot
	root.add_child(_f)
	await _frames(30)
	_f.set_time_scale(1.0)
	_f.get_node("Ui/Coach").visible = false
	if _f.tutorial != null:
		_f.tutorial.queue_free()
	JuiceSettings.player_invulnerable = true
	var hud: FlightHud = _f._hud
	# Put back afterwards: a windowed run autosaves the session.
	var was_mobile := bool(Session.pref("mobile_layout", false))
	var was_profile := Session.move_profile
	hud.set_mobile_layout(false)
	_f.set_move_profile(FlightRoot.MoveProfile.CLASSIC)
	await _frames(20)
	_save("desktop")
	hud.toggle_juice_panel()
	await _frames(10)
	_save("juice_panel")
	hud.close_top_panel()
	hud.toggle_controls_panel()
	await _frames(10)
	_save("controls_panel")
	hud.close_top_panel()
	hud.toggle_log_census_panel()
	await _frames(10)
	_save("log_panel")
	hud.close_top_panel()
	hud.toggle_debug_panel()
	await _frames(10)
	_save("debug_column")
	hud.close_top_panel()
	hud.set_mobile_layout(true)
	await _frames(20)
	_save("phone_classic")
	_f.set_move_profile(FlightRoot.MoveProfile.SWIPE)
	await _frames(20)
	_save("phone_swipe")
	# Mid-swipe from the ship: the 3D chevron arrow.
	var sw := _f.pilot().ship_screen_pos()
	if sw != Vector2.INF:
		_touch(sw, true)
		await _frames(2)
		var d := InputEventScreenDrag.new()
		d.position = sw + Vector2(float(_size.x) * 0.25, -float(_size.y) * 0.12)
		_f._unhandled_input(d)
		await _frames(6)
		_save("phone_swipe_arrow")
		_touch(d.position, false)
		await _frames(4)
	_f.set_move_profile(FlightRoot.MoveProfile.FPS)
	await _frames(20)
	_save("phone_fps")
	_f.set_move_profile(FlightRoot.MoveProfile.SLINGSHOT)
	_f.model.halt()
	await _frames(20)
	var pilot := _f.pilot() as SlingshotPilot
	var s := pilot.ship_screen_pos()
	if s != Vector2.INF:
		_touch(s, true)
		await _frames(2)
		var e := InputEventScreenDrag.new()
		e.position = s + Vector2(-60.0, float(_size.y) * 0.18)
		_f._unhandled_input(e)
		await _frames(6)
	_save("phone_sling_aim")
	_f.set_move_profile(was_profile)
	hud.set_mobile_layout(was_mobile)
	Session.save_to_disk()
	quit(0)


func _touch(pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = down
	_f._unhandled_input(e)


func _save(tag: String) -> void:
	var path := _out.path_join("ui_%dx%d_%s.png" % [_size.x, _size.y, tag])
	root.get_texture().get_image().save_png(path)
	print("wrote ", path)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
