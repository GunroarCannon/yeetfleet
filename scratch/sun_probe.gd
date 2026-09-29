extends SceneTree
class LateAim extends Node:
	var cam: Camera3D
	var sun: Node3D
	func _process(_d: float) -> void:
		cam.look_at(sun.global_position)
		cam.fov = 14.0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate()
	root.add_child(f)
	current_scene = f
	for i in 30:
		await process_frame
	var sun := f.find_child("ToySun", true, false) as Node3D
	var aim := LateAim.new()
	aim.cam = f.camera_rig.camera
	aim.sun = sun
	aim.process_priority = 10000
	f.add_child(aim)
	for t in [0.3, 6.0]:
		var until := Time.get_ticks_msec() + int(t * 1000.0)
		while Time.get_ticks_msec() < until:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://scratch/shots/sun_%s.png" % str(t))
	quit()
