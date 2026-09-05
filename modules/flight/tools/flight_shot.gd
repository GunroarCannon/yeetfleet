## Screenshots the live flight test bed.
##     godot --path . --rendering-driver opengl3 --script modules/flight/tools/flight_shot.gd -- out.png [frames] [w] [h]
##
## Same reasoning as `ui_shot.gd`: the width and height are the point as much as
## the picture is, and flight has to hold together from a 960x432 phone to a
## 1280x720 desktop just as much as the builder does.
##
## A fifth argument picks what is going on: "all" (default), "boost", "fire", or
## "planet" — which parks the ship off Tarn IV's shoulder for a look at what the
## planet renderer is putting on screen.
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "flight.png" if args.is_empty() else String(args[0])
	var warm := 60 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)
	if args.size() >= 4:
		size = Vector2i(int(args[2]), int(args[3]))
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	# One frame before touching anything the tree owns: node readiness for a
	# child added while the [SceneTree] is still inside [method _initialize] is
	# not visible until the first frame turns over, the same reason `ui_shot.gd`
	# never reaches into the scene until after its own warm-up loop starts.
	await process_frame
	f.get_node("Ui/Coach").visible = false
	# Throttle up and hold a turn so the shot shows the thing in motion, not a
	# ship sitting still at the spawn point — motion is most of what these
	# reference shots are about.
	f.set_throttle(1.0)
	f.set_stick(Vector2(0.3, -0.1))
	# A fourth argument selects what else is active, for isolating one system's
	# visuals from another; "all" (the default) exercises everything at once,
	# which is also the harshest combination for anything that could clip the
	# camera — see [constant SystemsSim.BOOST_STRETCH].
	var extra := "all" if args.size() < 5 else String(args[4])
	if extra == "all" or extra == "boost":
		f.set_boosting(true)
	if extra == "all" or extra == "fire":
		f.set_firing(true)
	if extra == "planet":
		# Parked off the planet's shoulder instead of flown at it. This shot is
		# about the surface [Planet] draws — continents, waterline, terminator,
		# atmosphere — and a ship at full throttle would have crossed half the
		# system before the last warm-up frame.
		f.set_throttle(0.0)
		f.set_stick(Vector2.ZERO)
		f.set_boosting(false)
		f.set_firing(false)
		var eye := SpaceScene.PLANET_CENTRE + Vector3(0.95, 0.34, 1.1).normalized() * (
			SpaceScene.PLANET_RADIUS * 3.4
		)
		f.model.look_at_from_position(eye, SpaceScene.PLANET_CENTRE, Vector3.UP)
		# Generation runs on a worker pool, so without this the shot can catch a
		# planet that has no surfaces yet — a black hole where the world should be.
		var body := f.space.get_node_or_null("Planet/Body") as Planet
		if body != null:
			await body.wait_for_build()
	for i in warm:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
