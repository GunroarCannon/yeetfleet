extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); var env := MenuProps.environment(); env.background_color = Color(0.1,0.1,0.15); we.environment = env; w.add_child(we)
	var cam := Camera3D.new(); w.add_child(cam); cam.position = Vector3(0, 10, 60); cam.look_at(Vector3(0,5,0)); cam.make_current()
	var l := DirectionalLight3D.new(); w.add_child(l); l.rotation_degrees = Vector3(-40, 30, 0)
	await process_frame
	var xs := [-30.0, 0.0, 30.0]
	var sc := [2.0, 8.0, 20.0]
	for i in 3:
		MenuProps.frozen_blast(w, MenuProps.GROUND_BLAST, Vector3(xs[i], 0, 0), sc[i], 0.6)
	for t in [0.15, 0.4, 1.0]:
		var until := Time.get_ticks_msec() + int(t * 1000.0)
		while Time.get_ticks_msec() < until:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://scratch/shots/blast3_%s.png" % str(t))
	quit()
