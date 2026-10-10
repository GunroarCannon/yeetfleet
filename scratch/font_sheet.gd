extends SceneTree
func _initialize() -> void:
	var fonts := ["Graffiti.ttf", "Vandal On The Fluid.ttf", "Nervous.ttf", "funkymuskrat.ttf", "FOO.ttf", "Bo_Toy.otf", "orange juice 2.0.ttf", "ka1.ttf"]
	var bg := ColorRect.new(); bg.color = Color(0.1, 0.1, 0.2); bg.size = Vector2(1280, 1300); root.add_child(bg)
	var y := 10.0
	for f in fonts:
		var l := Label.new()
		l.text = f.get_basename() + ":  YEETFLEET  Campaign 123"
		l.add_theme_font_override("font", load("res://assets/fonts/" + f))
		l.add_theme_font_size_override("font_size", 44)
		l.position = Vector2(10, y); root.add_child(l); y += 70
	await process_frame; await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scratch/font_sheet.png")
	quit()
