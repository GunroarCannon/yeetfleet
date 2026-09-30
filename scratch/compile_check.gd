## Loads the scripts named on the command line (or every modified one given)
## and reports which fail to compile. Headless:
##     godot --headless --path . --script scratch/compile_check.gd -- res://a.gd res://b.gd
extends SceneTree


func _initialize() -> void:
	var bad := 0
	for path in OS.get_cmdline_user_args():
		var s := load(path) as Script
		if s == null or not s.can_instantiate():
			print("[compile] FAIL ", path)
			bad += 1
		else:
			print("[compile] ok   ", path)
	print("[compile] %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	quit(1 if bad > 0 else 0)
