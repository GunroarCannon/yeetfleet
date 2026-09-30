extends SceneTree
func _initialize() -> void:
	var names := ["home", "map", "report", "garage", "settings", "fork"]
	var w := 540 / 2
	var h := 960 / 2
	var sheet := Image.create(w * names.size(), h, false, Image.FORMAT_RGBA8)
	for i in names.size():
		var img := Image.load_from_file("res://debug_shots/scratch/portrait/%s.png" % names[i])
		if img == null: continue
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * w, 0))
	sheet.save_png("res://debug_shots/scratch/portrait/tile.png")
	quit()
