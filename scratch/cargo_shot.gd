## A courier level a few seconds in: the cargo packages ahead. Windowed:
##     godot --path . --audio-driver Dummy --resolution 960x540 --script scratch/cargo_shot.gd
extends SceneTree

const SCRATCH := "user://cargo_shot_scratch.json"


func _initialize() -> void:
	Campaign.save_path = SCRATCH
	Campaign.reset()
	_run.call_deferred()


func _run() -> void:
	var lvl := {}
	for l in Campaign.sectors()[0]["levels"]:
		if String(l["kind"]) == "courier":
			lvl = l
			break
	print("[cargo] level ", lvl.get("key", "none"))
	Campaign.launch(lvl)
	Session.space_setup["events"] = []
	var f := (load("res://modules/flight/flight_test.tscn") as PackedScene).instantiate() as FlightRoot
	root.add_child(f)
	current_scene = f
	var until := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < until:
		await process_frame
	var obj := f.scenarios._objectives if f.scenarios != null else null
	if obj != null:
		print("[cargo] points ", obj.points.size(), " dist ", f.model.global_position.distance_to(obj.goal_position()))
		# Look at the nearest package from nearer, as a player would on the way.
		f.model.global_position = obj.goal_position() + (f.model.global_position - obj.goal_position()).normalized() * 350.0
		f.model.velocity = Vector3.ZERO
		f.model.look_at(obj.goal_position(), Vector3.UP)
	until = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < until:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://debug_shots/cargo.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	quit()
