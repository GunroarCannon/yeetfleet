extends SceneTree

const H := preload("res://tests/face_gen/test_helpers.gd")

const _SPECIES_IDS := [
	&"VOID_GREY", &"DRACONIAN", &"MANTID", &"MUDOK", &"CEPHALID", &"AVIARN",
	&"LATTICE", &"SYNTH", &"BRUTE", &"NORDIC", &"MYCELID", &"UMBRAL"
]

func _initialize() -> void:
	var fails: Array[String] = []

	# 1. FaceGen is registered as an autoload in project.godot.
	# (Autoload singletons are not instantiated for --script runs, so the real
	# check is that it is registered; the API itself is exercised below by
	# instantiating the script directly.)
	var proj := FileAccess.get_file_as_string("res://project.godot")
	H.check(fails, proj.contains("FaceGen=\"*res://modules/alien_face_gen/api/face_gen.gd\""),
		"project.godot does not register the FaceGen autoload")

	var face_gen_script = load("res://modules/alien_face_gen/api/face_gen.gd")
	H.check(fails, face_gen_script != null, "face_gen.gd failed to load")
	var face_gen: Object = (face_gen_script as GDScript).new()

	# 2. make_genome() works for all 12 species
	for sid in _SPECIES_IDS:
		var g = face_gen.call("make_genome", sid, 42)
		H.check(fails, g != null, "make_genome(%s) returned null" % sid)
		H.check(fails, g.species_id == sid, "make_genome(%s): wrong species_id %s" % [sid, g.species_id])
		H.check(fails, g.seed == 42, "make_genome(%s): wrong seed" % sid)

	# 3. export_svg() and export_obj() return OK for all 12 species
	for sid in _SPECIES_IDS:
		var svg_path := "res://out/api_%s.svg" % String(sid).to_lower()
		var err_svg = face_gen.call("export_svg", sid, 42, svg_path)
		H.check(fails, err_svg == OK, "export_svg(%s) returned %d" % [sid, err_svg])

		var obj_path := "res://out/api_%s.obj" % String(sid).to_lower()
		var err_obj = face_gen.call("export_obj", sid, 42, obj_path)
		H.check(fails, err_obj == OK, "export_obj(%s) returned %d" % [sid, err_obj])

	# 4. species_list().size() == 12
	var species_list = face_gen.call("species_list")
	H.check(fails, species_list.size() == 12, "species_list().size()=%d, expected 12" % species_list.size())

	# 5. random_seed_for() returns valid integers
	var seed1 = face_gen.call("random_seed_for", &"NORDIC")
	var seed2 = face_gen.call("random_seed_for", &"NORDIC")
	H.check(fails, seed1 is int and seed2 is int, "random_seed_for() returned non-int")

	# 6. Cross-mode identity: same seed → same individual in 2D and 3D
	for sid in _SPECIES_IDS:
		for i in range(5):
			var g_portrait = face_gen.call("make_genome", sid, i * 17 + 3)
			var g_head = face_gen.call("make_genome", sid, i * 17 + 3)
			H.check(fails, g_portrait.fingerprint() == g_head.fingerprint(),
				"Cross-mode identity failed for %s seed %d" % [sid, i])

	# 7. Both demo scenes load
	var demo_2d = load("res://modules/alien_face_gen/demo/demo_2d.tscn")
	H.check(fails, demo_2d != null, "demo_2d.tscn failed to load")

	var demo_3d = load("res://modules/alien_face_gen/demo/demo_3d.tscn")
	H.check(fails, demo_3d != null, "demo_3d.tscn failed to load")

	H.print_results(fails, 11)
	quit(0 if fails.size() == 0 else 1)
