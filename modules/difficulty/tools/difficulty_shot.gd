## Screenshots of the Difficulty Lab's tabs (windowed): `"$GD" --path . --audio-driver Dummy
## --resolution 900x900 --script modules/difficulty/tools/difficulty_shot.gd -- res://debug_shots/difficulty`
extends SceneTree


func _initialize() -> void:
	var out := "res://debug_shots/difficulty"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var lab := (load("res://modules/difficulty/difficulty_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	for i in 6:
		await process_frame
	var tabs := _find_tabs(lab)
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		for f in 4:
			await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/tab_%d.png" % [out, i]))
	quit()


func _find_tabs(n: Node) -> TabContainer:
	if n is TabContainer:
		return n
	for c in n.get_children():
		var t := _find_tabs(c)
		if t != null:
			return t
	return null
