## The first thing on screen after the engine's own boot splash: the same
## picture ([constant SPLASH], also [code]application/boot_splash/image[/code],
## so the hand-over is seamless), then a jolt — the screen shakes, the logo
## cracks into [constant CRITBOX] and the studio's name slams in underneath in
## the graffiti face — and on to the menu.
##
## The menu scene is loaded on a worker thread while this plays, so the splash
## is the loading time rather than extra time; if it is not ready when the
## show is over, a small bar says so until it is. Launched with
## [code]--module=[/code] or headless (tools), it goes straight on.
extends Control

const SPLASH := "res://assets/splash.png"
const CRITBOX := "res://assets/critbox_splash.png"
const MENU := "res://modules/menu/menu.tscn"
const NAME := "CRITBOX"
## Seconds the plain logo holds before the jolt.
const HOLD := 0.35
## Seconds the shake lasts, and how far it throws the picture (fraction of the
## short screen side).
const SHAKE_TIME := 0.45
const SHAKE_SIZE := 0.03
## Least seconds the cracked logo and the name stay up.
const SHOW := 1.5
const BG := Color.BLACK
const INK := Color("f3f2f8ff")
## Frames the boot card stays over the menu while it builds its 3D stage.
const BOOT_HOLD_FRAMES := 40

var _pic: TextureRect
var _name: Label
var _shake := 0.0
var _shown := false
var _loading := false
var _t := 0.0

var _fade: ColorRect



func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_fade.z_index = 100
	
	_pic = TextureRect.new()
	_pic.texture = load(SPLASH) as Texture2D
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pic)
	_name = Label.new()
	_name.text = NAME
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_override("font", GraffitiStyle.title_font())
	_name.add_theme_color_override("font_color", INK)
	_name.modulate.a = 0.0
	add_child(_name)
	resized.connect(_layout)
	_layout()
	_loading = ResourceLoader.load_threaded_request(MENU) == OK
	var straight := DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--module="):
			straight = true
	if straight:
		_shown = true
		return
	var tw := create_tween()
	tw.tween_interval(HOLD)
	tw.tween_callback(_jolt)
	tw.tween_interval(SHOW)
	tw.tween_callback(func() -> void: _shown = true)


func _layout() -> void:
	var short := minf(size.x, size.y)
	var fs := int(short * 0.11)
	_name.add_theme_font_size_override("font_size", fs)
	_name.size = Vector2(size.x, fs * 1.4)
	# Under the logo: the pictures centre their mark, about a fifth of the
	# screen tall.
	_name.position = Vector2(0.0, size.y * 0.5 + short * 0.24)
	_name.pivot_offset = _name.size * 0.5


## The crack: shake, swap to the broken logo, slam the name in.
func _jolt() -> void:
	_pic.texture = load(CRITBOX) as Texture2D
	_shake = 1.0
	_name.scale = Vector2(1.8, 1.8)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_name, "modulate:a", 1.0, 0.12)
	tw.tween_property(_name, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if _shake > 0.0:
		_shake = maxf(_shake - delta / SHAKE_TIME, 0.0)
		var amp := minf(size.x, size.y) * SHAKE_SIZE * _shake * _shake
		var jolt := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp
		_pic.position = jolt
		_name.position.x = jolt.x * 0.6
	if _shown:
		_go()
	queue_redraw()


func _draw() -> void:
	# Still loading after the show: a slim bar under the name.
	if not _shown or not _loading:
		return
	var progress := []
	ResourceLoader.load_threaded_get_status(MENU, progress)
	var p := float(progress[0]) if not progress.is_empty() else 0.0
	var w := size.x * 0.3
	var r := Rect2(Vector2((size.x - w) * 0.5, _name.position.y + _name.size.y + 12.0), Vector2(w, 6.0))
	draw_rect(r, Color(INK, 0.15))
	draw_rect(Rect2(r.position, Vector2(w * p, r.size.y)), INK)


## The show is over: cross-fade into the graffiti loading card, which loads
## the menu with its music, sounds and pictures ([method
## LoadingScreen.boot_paths]), swaps the menu in underneath itself and fades
## only once the menu has drawn — no black screen while it builds, and no
## hitch the first time a song or a card picture comes up.
func _go() -> void:
	set_process(false)
	var straight := DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--module="):
			straight = true
	if straight:
		# Tools and --module launches: no card, straight on.
		if _loading and ResourceLoader.load_threaded_get_status(MENU) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(MENU)
		get_tree().change_scene_to_file(MENU)
		return
	var card := LoadingScreen.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.hold_frames = BOOT_HOLD_FRAMES
	card.modulate.a = 0.0
	add_child(card)
	# The menu's load was started with the splash; asking again joins it.
	card.start(MENU, "", LoadingScreen.boot_paths())
	create_tween().tween_property(card, "modulate:a", 1.0, 0.35)
