extends SceneTree

const OUT := "C:/Users/hmmm/AppData/Local/Temp/claude/C--Users-hmmm-Documents-elite-clone/3cd1fd94-10a2-4b57-b698-723dda6c8f37/scratchpad/"


func _initialize() -> void:
	Campaign.save_path = "user://shot_scratch.json"
	Campaign.reset()
	_run.call_deferred()


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var lvl: Dictionary = Campaign.sectors()[0]["levels"][2]
	print("level kind ", lvl["kind"])
	Campaign.launch(lvl)
	change_scene_to_file(ModuleRegistry.scene_path("flight"))
	await _secs(6.0)
	var flight := current_scene as FlightRoot
	await _snap("f_play")
	var ob: ScenarioObjectives = flight.scenarios._objectives
	print("objectives ", ob, " running ", flight.scenarios.is_running(), " locked ", flight.controls_locked())
	if ob != null:
		print("arrow ", ob._arrow, " vis ", ob._arrow.visible if ob._arrow else null, " parent ", ob._arrow.get_parent() if ob._arrow else null, " goal ", ob.goal_position(), " kind ", ob.kind)
		print("arrow xf ", ob._arrow.transform)
	if flight.incident_director != null:
		flight.incident_director.trigger_incident("faction_skirmish")
	await _secs(0.12)
	for b in root.find_children("*", "EventBubble", true, false):
		print("bubble ", b.position, b.size, b.modulate, b.scale, b.visible, b.get_parent())
	await _snap("f_bubble")
	flight.campaign_overlay.toggle_pause()
	await _secs(0.12)
	await _snap("f_pause")
	flight.campaign_overlay.toggle_pause()
	change_scene_to_file(ModuleRegistry.scene_path("font_lab"))
	await _secs(1.0)
	await _snap("f_fontlab")
	var lab := current_scene as FontLab
	lab._open_picker(lab._mock.get_child(0) as Button)
	await _secs(0.3)
	await _snap("f_fontpick")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shot_scratch.json"))
	quit()
