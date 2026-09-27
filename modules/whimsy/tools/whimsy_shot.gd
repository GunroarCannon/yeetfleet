## Screenshots the flight test bed framed for judging the *look*: toy lighting,
## faces, the advanced-lighting post pass.
##     godot --path . --rendering-driver opengl3 --script modules/whimsy/tools/whimsy_shot.gd -- out.png [view] [yaw] [advanced]
##
## [code]view[/code] is "orbit" (default: a close three-quarter look at the
## player's hull), "chase" (the camera the player actually flies with), "fleet"
## (AI ships parked in front of the camera, so their faces are on show), "pop"
## (the fleet, with the middle ship destroyed a moment before the shot: confetti
## and a dizzy emote), "rock" (the player parked beside a near-field rock) or
## "facecam" (triggers a "happy" emote on the player's own ship and places a
## camera looking straight at wherever [method Whimsy.emote] popped it out —
## for judging the pop/fade look on its own instead of hunting for the right
## orbit yaw to catch it mid-flight).
## [code]yaw[/code] is the orbit camera's yaw in degrees. [code]advanced[/code]
## is "on" or "off" and forces [member Session.cinematic_lighting] for the shot.
## A fifth argument names a [Palette] id to shoot under (not persisted).
##
## Always run it with [code]--audio-driver Dummy[/code]: a shot needs no sound.
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "whimsy.png" if args.is_empty() else String(args[0])
	var view := "orbit" if args.size() < 2 else String(args[1])
	var yaw := 150.0 if args.size() < 3 else float(args[2])
	if args.size() >= 4:
		Session.cinematic_lighting = String(args[3]) == "on"
		Session.enhanced_lighting = Session.cinematic_lighting
	if args.size() >= 5:
		var pal := Palette.find_by_id(String(args[4]))
		if pal != null:
			StyleManager.instance().set_palette(pal, false)
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var f := packed.instantiate() as FlightRoot
	root.add_child(f)
	await process_frame
	await process_frame
	f.get_node("Ui/Coach").visible = false
	# The HUD is judged by its own shots; here it only hides the hull.
	f.get_node("Ui").visible = false
	f.set_throttle(0.0)
	f.set_stick(Vector2.ZERO)
	f.model.halt()
	# Face the ship across the star so the key light rakes the hull from the side:
	# the angle that shows whether the shading has any form in it at all.
	var side := SpaceScene.SUN_DIR.cross(Vector3.UP).normalized()
	var at := f.model.global_position
	f.model.look_at_from_position(at, at + side, Vector3.UP)
	if view == "rock":
		_park_by_rock(f)
	if view == "facecam":
		f._emote("happy", 3.0)
		await process_frame
		var popup: Node3D = null
		for i in f.get_child_count():
			var c := f.get_child(i)
			if c.name.begins_with("Emote"):
				popup = c as Node3D
		if popup != null:
			var fp := popup.global_position
			var cam := Camera3D.new()
			root.add_child(cam)
			cam.look_at_from_position(fp + Vector3(0.0, 0.0, 4.0), fp, Vector3.UP)
			cam.make_current()
			print("facecam: emote at ", fp)
		else:
			print("facecam: no emote popup found!")
	if view == "orbit" or view == "fleet" or view == "pop":
		f.camera_rig.set_mode(FlightCamera.Mode.ORBIT)
		f.camera_rig._orbit_yaw = yaw
		f.camera_rig._orbit_pitch = 14.0
		f.camera_rig._orbit_distance = f.camera_rig.hull_length * (0.95 if view == "orbit" else 3.2)
	if (view == "fleet" or view == "pop") and f._ai_spawner != null:
		_park_fleet(f)
	for i in 40:
		await process_frame
	if view == "boom":
		# The addon explosion (GPU particles) right in front of the camera: the
		# case that used to black out the post pass.
		var cam := f.camera_rig.camera
		AddonVfx.explosion(f, cam.global_position - cam.global_basis.z * 30.0, 2.5, true, Color("ff8844"))
		var lumas := PackedFloat32Array()
		for i in 10:
			lumas.append(_mean_luma(root.get_texture().get_image()))
			await process_frame
		print("boom lumas: ", lumas)
	if view == "pop" and f._ai_spawner != null and f._ai_spawner.ships().size() > 1:
		var victim: AiShip = f._ai_spawner.ships()[1]
		victim.take_damage(victim.hp + 1.0)
		for i in 12:
			await process_frame
	var post := f.get_node_or_null("AdvancedLighting") as AdvancedLighting
	if post != null:
		var m := (post.get_node("Post") as ColorRect).material as ShaderMaterial
		print("post: enabled=%s sun_uv=%s visible=%s" % [post.enabled, m.get_shader_parameter("sun_uv"), m.get_shader_parameter("sun_visible")])
	print("state: dead=%s time_scale=%.2f hp=%.0f" % [f._player_dead, Engine.time_scale, f.player_hp])
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	# A black frame is a bug worth isolating: shoot again without the post pass
	# to tell a dead post shader from a dead 3D frame.
	if _mean_luma(img) < 0.01 and post != null:
		await process_frame
		await process_frame
		print("BLACK FRAME: two frames later, post still on, mean luma = %.3f" % _mean_luma(root.get_texture().get_image()))
		post.enabled = false
		await process_frame
		await process_frame
		var bare := root.get_texture().get_image()
		print("BLACK FRAME: without post pass mean luma = %.3f" % _mean_luma(bare))
		bare.save_png(out_path.get_basename() + "_nopost.png")
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)


## A camera of the shot's own, a few radii off a near-field rock that wears a
## face, looking straight at it.
func _park_by_rock(f: FlightRoot) -> void:
	for entry: Dictionary in f.space.asteroid_data:
		var anchor: Node3D = entry["node"]
		if anchor == null or anchor.get_node_or_null("WhimsyFace") == null:
			continue
		var r: float = entry["radius"]
		var rock_pos := anchor.global_position
		var cam := Camera3D.new()
		cam.far = 60000.0
		root.add_child(cam)
		cam.look_at_from_position(rock_pos + Vector3(r * 3.2, r * 1.1, r * 3.2), rock_pos, Vector3.UP)
		cam.make_current()
		return


## Freeze a few AI ships in a loose arc ahead of the player, noses toward the
## camera, so the shot shows hulls and faces rather than distant dots.
func _park_fleet(f: FlightRoot) -> void:
	var ships: Array = f._ai_spawner.ships()
	var basis := f.model.global_transform.basis
	var centre := f.model.global_position
	var cam_pos := f.camera_rig.camera.global_position if f.camera_rig.camera != null else centre + basis.z * 20.0
	var n := mini(ships.size(), 3)
	for i in n:
		var ship: AiShip = ships[i]
		if ship == null or ship.model == null:
			continue
		ship.set_physics_process(false)
		ship.model.set_physics_process(false)
		ship.model.clear_phys_world()
		var offset := basis.x * (float(i) - 1.0) * 9.0 + basis.y * 3.0 - basis.z * 6.0
		var pos := centre + offset
		ship.model.look_at_from_position(pos, cam_pos, Vector3.UP)
		ship.global_transform = ship.model.global_transform


func _mean_luma(img: Image) -> float:
	var small := img.duplicate() as Image
	small.resize(32, 18)
	var sum := 0.0
	for y in 18:
		for x in 32:
			sum += small.get_pixel(x, y).get_luminance()
	return sum / (32.0 * 18.0)
