## Minimal test: camera + light + plain sphere + Planet side by side.
extends SceneTree

var _frames := 0
var _planet: Planet


func _initialize() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 10)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 50
	root.add_child(cam)

	var light := DirectionalLight3D.new()
	light.light_energy = 2.0
	root.add_child(light)

	var env := Environment.new()
	env.background_mode = 1
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = 2
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = 2
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# Plain sphere
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.mesh.radius = 3.0
	sphere.mesh.height = 6.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.4, 0.2)
	sphere.material_override = mat
	sphere.position = Vector3(-5, 0, 0)
	root.add_child(sphere)

	# Planet
	_planet = Planet.new()
	_planet.name = "TestPlanet"
	_planet.position = Vector3(5, 0, 0)
	root.add_child(_planet)
	var d := PlanetData.new()
	d.planet_radius = 3.0
	d.sphere_resolution = 32
	d.primary_color = Color(0.3, 0.6, 0.9)
	d.secondary_color = Color(0.1, 0.2, 0.4)
	_planet.configure(d)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 30:
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png("C:/tmp/planet_minimal.png")
			var w := img.get_width()
			var h := img.get_height()
			for x in [w/4, w/2, 3*w/4]:
				var c := img.get_pixel(x, h/2)
				print("Pixel at (%d,%d): R=%.3f G=%.3f B=%.3f" % [x, h/2, c.r, c.g, c.b])
			var body := _planet.body()
			print("Planet body: %s" % (body != null))
			if body != null:
				print("Mesh surfaces: %d" % body.mesh.get_surface_count())
			print("Saved %dx%d" % [w, h])
		quit(0)
	return false
