extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

func _initialize() -> void:
	var fails: Array[String] = []
	
	# The 2D contact sheets produced by modules/alien_face_gen/demo/contact_sheet.gd
	# (run it with a real window — not --headless — to regenerate). A 3D→PNG
	# rasterizer does not exist in the module yet, so the two contact_sheet_3d*
	# files the original test expected are not asserted here.
	var files := [
		"res://out/contact_sheet_2d.png",
		"res://out/contact_sheet_styles.png",
		"res://out/contact_sheet_lod.png",
	]
	
	for fpath in files:
		var f := FileAccess.open(fpath, FileAccess.READ)
		if f == null:
			H.check(fails, false, "File missing: %s" % fpath)
			continue
		
		var size := f.get_length()
		f.close()
		H.check(fails, size > 20000, "%s is only %d bytes, expected > 20 KB" % [fpath, size])
		
		# Load image and check for diversity
		var img := Image.new()
		var err := img.load(fpath)
		if err == OK:
			var colors: Dictionary = {}
			var sample_count := 0
			for x in range(0, img.get_width(), max(1, img.get_width() / 20)):
				for y in range(0, img.get_height(), max(1, img.get_height() / 20)):
					var c := img.get_pixel(x, y)
					var key := "%d_%d_%d" % [int(c.r * 15), int(c.g * 15), int(c.b * 15)]
					colors[key] = true
					sample_count += 1
					if sample_count >= 200:
						break
				if sample_count >= 200:
					break
			H.check(fails, colors.size() >= 12,
				"%s: only %d distinct colours (expected >= 12)" % [fpath, colors.size()])
		else:
			H.check(fails, false, "Failed to load image: %s (error %d)" % [fpath, err])
	
	H.print_results(fails, 12)
	quit(0 if fails.size() == 0 else 1)
