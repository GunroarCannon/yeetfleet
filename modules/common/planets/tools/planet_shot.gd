## Take a screenshot of the planet editor with full shader.
extends SceneTree

var _frames := 0
var _planet: Planet
var _camera: Camera3D


func _initialize() -> void:
	var packed := load("res://modules/common/planets/planet_editor.tscn") as PackedScene
	var root_node := packed.instantiate()
	root.add_child(root_node)
	# Find nodes
	_planet = root.find_child("PreviewPlanet", true, false) as Planet
	_camera = root.find_child("Camera3D", true, false) as Camera3D


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		if _camera != null and _planet != null:
			# Force camera to look at origin
			_camera.position = Vector3(0, 3, 12)
			_camera.look_at(Vector3.ZERO, Vector3.UP)
			print("Camera pos: %s" % _camera.global_position)
			print("Camera forward: %s" % -_camera.global_basis.z)
			var body := _planet.body()
			if body != null:
				print("Planet body pos: %s" % body.global_position)
				print("Planet body mesh surface count: %d" % body.mesh.get_surface_count())
			else:
				print("ERROR: Planet body is null!")
	if _frames >= 45:
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png("C:/tmp/planet_final.png")
			var w := img.get_width()
			var h := img.get_height()
			for x in [w/6, w/3, w/2, 2*w/3, 5*w/6]:
				var c := img.get_pixel(x, h/2)
				print("Pixel at (%d,%d): R=%.3f G=%.3f B=%.3f" % [x, h/2, c.r, c.g, c.b])
			print("Saved %dx%d" % [w, h])
		quit(0)
	return false
