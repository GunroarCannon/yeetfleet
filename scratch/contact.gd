extends SceneTree
func _initialize() -> void:
	var files := DirAccess.get_files_at("res://assets/picset")
	var list: Array[String] = []
	for f in files:
		if f.ends_with(".webp"):
			list.append(f)
	list.sort()
	var cell := Vector2i(200, 160)
	var cols := 8
	var rows := int(ceil(list.size() / float(cols)))
	var sheet := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.35, 0.4))
	for i in list.size():
		var img := Image.load_from_file("res://assets/picset/" + list[i])
		img.convert(Image.FORMAT_RGBA8)
		img.resize(cell.x - 8, cell.y - 8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cell.x + 4, (i / cols) * cell.y + 4))
	sheet.save_png("res://scratch/shots/contact.png")
	print(list)
	quit()
