## GameAudio: playlists found, music starts and crossfades, buses exist,
## every one-shot and Sfx id loads. Headless:
##     godot --headless --path . --audio-driver Dummy --script scratch/audio_check.gd
extends SceneTree

var _bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for pl in ["main", "submenus", "gameplay"]:
		var t := GameAudio.tracks(pl)
		print("[audio] ", pl, ": ", t.map(func(p: String) -> String: return p.get_file()))
		_check(not t.is_empty(), "no tracks for " + pl)
	GameAudio.music("main")
	for i in 5:
		await process_frame
	_check(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"SFX") >= 0, "buses missing")
	var host := root.get_node_or_null("GameAudio")
	_check(host != null, "no host")
	var playing := 0
	for c in host.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing and (c as AudioStreamPlayer).bus == &"Music":
			playing += 1
	_check(playing == 1, "main music not playing (%d)" % playing)
	GameAudio.music("gameplay")
	await create_timer(1.6).timeout
	for id in GameAudio.UI:
		for f in GameAudio.UI[id]:
			_check(ResourceLoader.exists(f), "missing " + f)
		GameAudio.ui(id)
	for id in Sfx.ids():
		_check(not Sfx.streams(id).is_empty(), "sfx id loads nothing: " + String(id))
		for f in Sfx.FILES[id]:
			_check(not String(f).contains("SciFi Sound Library"), "old library used")
	print("[audio] %s" % ("PASS" if _bad == 0 else "FAIL %d" % _bad))
	quit(1 if _bad else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_bad += 1
		print("[audio] FAIL ", msg)
