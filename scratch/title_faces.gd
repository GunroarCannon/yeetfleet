## Every face the home title cycles through, stacked into one sheet. Windowed:
##     godot --path . --audio-driver Dummy --resolution 900x1400 --script scratch/title_faces.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1030")
	bg.size = Vector2(900, 1400)
	root.add_child(bg)
	var faces := GraffitiTitle.faces("YEETFLEET")
	print("[faces] ", faces.size(), " ", faces)
	var i := 0
	for p in faces:
		var t := GraffitiTitle.new()
		root.add_child(t)
		t.font = load(p) as Font
		t.position = Vector2(20, 10 + i * 170)
		t.size = Vector2(860, 170)
		i += 1
	for k in 8:
		await process_frame
	root.get_texture().get_image().save_png("res://debug_shots/title_faces.png")
	quit()
