extends SceneTree
func _initialize() -> void:
	var sheet := Image.create(512, 128, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.15, 0.3))
	var i := 0
	for n in ["coin", "star", "star_empty", "badge"]:
		var img := Image.load_from_file("res://assets/picset/icon_%s.webp" % n)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * 128, 0))
		i += 1
	sheet.save_png("res://debug_shots/scratch/shots/icons.png")
	quit()
