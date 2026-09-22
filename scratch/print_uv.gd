extends SceneTree
func _initialize():
	var img := Image.load_from_file("scratch/grid_test.png")
	print("Size: ", img.get_size())
	print("Top-Left: ", img.get_pixel(0, 0))
	print("Top-Right: ", img.get_pixel(639, 0))
	print("Bottom-Left: ", img.get_pixel(0, 359))
	print("Bottom-Right: ", img.get_pixel(639, 359))
	print("Center: ", img.get_pixel(320, 180))
	quit()
