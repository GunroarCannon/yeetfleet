## Store art generator: a Play Store feature graphic (1024×500) — a frozen
## blast in the middle of a fight, the ships round it, YEETFLEET sprayed over
## it — and the app icon (512×512), both drawn by the game's own code, so
## they follow the look whenever it changes.
##
## The picture is built by the Art Studio's scene builder
## (modules/art_studio/scripts/art_scene.gd); open the Art Studio (DEBUG →
## MODULES) to set every part of it by hand. From here every setting is the
## seed's pick, and any of them can be fixed with key=value:
##
##     godot --path . --audio-driver Dummy --script launch/tools/banner_gen.gd [-- seed=1234] [-- icon] [-- blast=nuke fighters=8 glare=1.4]
##
## Windowed (the headless renderer draws nothing). Writes
## launch/banners/feature_<seed>.png and copies it to
## launch/feature_graphic.png; with "icon", launch/icons/icon_<seed>.png and
## launch/icon_512.png.
extends SceneTree

const ArtScene := preload("res://modules/art_studio/scripts/art_scene.gd")
const OUT := "res://launch"

var _p := ArtScene.settings()


func _initialize() -> void:
	_p["seed"] = int(Time.get_unix_time_from_system()) % 100000
	for a in OS.get_cmdline_user_args():
		if a == "icon":
			_p["mode"] = "icon"
		elif a.contains("="):
			var k := a.get_slice("=", 0)
			var v := a.get_slice("=", 1)
			if _p.has(k):
				var old: Variant = _p[k]
				_p[k] = int(v) if old is int else (float(v) if old is float else (v == "true" if old is bool else v))
	_run.call_deferred()


func _run() -> void:
	var size := ArtScene.size_of(_p)
	root.size = size
	# Draw the overlay in real pixels, not stretched from the 1280x720 base.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = size
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var built := ArtScene.build(world, Vector2(size), _p)
	await process_frame
	var layer := CanvasLayer.new()
	layer.layer = 2
	root.add_child(layer)
	var over := Control.new()
	over.size = Vector2(size)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(over)
	ArtScene.overlay(over, Vector2(size), _p, built["sun_screen"])
	# Let the sky bake and every mesh land.
	for i in 12:
		await process_frame
	await ArtScene.booms(self, world, _p)
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var icon := String(_p["mode"]) == "icon"
	var dir := "icons" if icon else "banners"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(dir)))
	var one := OUT.path_join(dir).path_join("%s_%d.png" % ["icon" if icon else "feature", int(_p["seed"])])
	img.save_png(ProjectSettings.globalize_path(one))
	var main := OUT.path_join("icon_512.png" if icon else "feature_graphic.png")
	img.save_png(ProjectSettings.globalize_path(main))
	print("[banner] seed %d -> %s and %s" % [int(_p["seed"]), one, main])
	quit()
