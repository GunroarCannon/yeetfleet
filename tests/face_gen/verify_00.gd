extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

func _initialize() -> void:
	var fails: Array[String] = []
	
	# Check Godot version
	var ver = Engine.get_version_info()
	H.check(fails, ver["major"] == 4, "Expected Godot 4.x, got %d" % ver["major"])
	H.check(fails, ver["minor"] >= 4, "Expected Godot 4.4+, got 4.%d" % ver["minor"])
	
	# Check all required directories exist
	var dirs := [
		"res://modules/alien_face_gen/core",
		"res://modules/alien_face_gen/render2d",
		"res://modules/alien_face_gen/render2d/styles",
		"res://modules/alien_face_gen/render2d/consumers",
		"res://modules/alien_face_gen/render3d",
		"res://modules/alien_face_gen/render3d/styles",
		"res://modules/alien_face_gen/render3d/shaders",
		"res://modules/alien_face_gen/render3d/consumers",
		"res://modules/alien_face_gen/data",
		"res://modules/alien_face_gen/data/palettes",
		"res://modules/alien_face_gen/data/species",
		"res://modules/alien_face_gen/cache",
		"res://modules/alien_face_gen/api",
		"res://addons/face_gen_gallery",
		"res://tests/face_gen",
		"res://modules/alien_face_gen/demo",
		"res://out",
	]
	
	for d in dirs:
		H.check(fails, DirAccess.dir_exists_absolute(d), "Directory missing: %s" % d)
	
	# Check .gitignore has out/
	var gitignore = FileAccess.get_file_as_string("res://.gitignore")
	H.check(fails, gitignore != null and gitignore.contains("out/"), ".gitignore must contain 'out/'")
	
	H.print_results(fails, 0)
	quit(0 if fails.size() == 0 else 1)
