extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); we.environment = MenuProps.environment(); w.add_child(we)
	var box := MeshInstance3D.new(); box.mesh = BoxMesh.new(); w.add_child(box)
	var cam := Camera3D.new(); w.add_child(cam); cam.position = Vector3(0, 6, 30); cam.look_at(Vector3(0,3,0)); cam.make_current()
	await process_frame
	var b := MenuProps.frozen_blast(w, MenuProps.GROUND_BLAST, Vector3(-8, 0, 0), 3.2, 5.0)
	var r := ExplosionRegistry.spawn_effect(w, "binbun_air_explosion", Vector3(8, 3, 0), Vector3.UP, 3.0)
	print("registry node ", r)
	for i in 8:
		await process_frame
	for c in b.get_children():
		if c is GPUParticles3D:
			print(c.name, " emit=", c.emitting, " amount=", c.amount, " vis=", c.visible, " spd=", c.speed_scale)
		if c is AnimationPlayer:
			print("anim ", c.current_animation, " pos ", c.current_animation_position, " playing ", c.is_playing())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://debug_shots/scratch/shots/blast_p2.png")
	quit()
