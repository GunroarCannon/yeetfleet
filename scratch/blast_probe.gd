extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); we.environment = MenuProps.environment(); w.add_child(we)
	var box := MeshInstance3D.new(); box.mesh = BoxMesh.new(); w.add_child(box)
	var cam := Camera3D.new(); w.add_child(cam); cam.position = Vector3(0, 6, 30); cam.look_at(Vector3(0,3,0)); cam.make_current()
	var l := DirectionalLight3D.new(); w.add_child(l); l.rotation_degrees = Vector3(-40, 30, 0)
	var b := MenuProps.frozen_blast(w, MenuProps.GROUND_BLAST, Vector3(-8, 0, 0), 3.2, 0.5)
	var b2 := MenuProps.frozen_blast(w, MenuProps.AIR_BLAST, Vector3(8, 3, 0), 3.2, 0.35)
	print("blast ", b, " ", b2)
	for t in [0.2, 0.6, 1.5]:
		var until := Time.get_ticks_msec() + int(t * 1000.0)
		while Time.get_ticks_msec() < until:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://debug_shots/scratch/shots/blast_%s.png" % str(t))
	quit()
