## The Art Studio, opened and driven: a screenshot of the whole studio, then
## RANDOMISE ALL and the icon picture, each saved — a smoke that the scene
## builds, the panel works and SAVE writes a file. Windowed (the headless
## renderer draws nothing):
##
##     godot --path . --audio-driver Dummy --resolution 1600x900 --script modules/art_studio/tools/art_studio_shot.gd [-- <out_dir>]
##
## Writes studio.png, studio_random.png and studio_icon.png into <out_dir>
## (default res://debug_shots/art_studio).
extends SceneTree

var _out := "res://debug_shots/art_studio"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	var studio := (load("res://modules/art_studio/art_studio.tscn") as PackedScene).instantiate() as ArtStudio
	root.add_child(studio)
	current_scene = studio
	await _idle(studio)
	await _shot("studio")
	studio._randomise()
	await _idle(studio)
	await _shot("studio_random")
	studio.set_param("mode", "icon")
	await _wait(0.6)
	await _idle(studio)
	await _shot("studio_icon")
	studio._save(false)
	var saved := FileAccess.file_exists("res://launch/studio/icon_%d.png" % int(studio.params["seed"]))
	print("[art studio shot] saved png: ", saved)
	print("PASS art_studio_shot" if saved else "FAIL art_studio_shot: SAVE wrote nothing")
	quit()


## Until the studio has finished building (and a beat more for the blasts).
func _idle(studio: ArtStudio) -> void:
	await _wait(0.8)
	while studio._building or studio._rebuild_at > 0.0:
		await process_frame
	await _wait(0.5)


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(ProjectSettings.globalize_path(path))
	print("[art studio shot] ", path)
