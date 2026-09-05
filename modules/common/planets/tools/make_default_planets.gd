## Authors the starter planets committed to the repo, so the flight scene has
## content out of the box and the editor's library is not empty on a fresh
## checkout.
##
##     godot --path . --script modules/common/planets/tools/make_default_planets.gd
##
## A tool rather than hand-written .tres files: a resource saved by the engine
## gets a valid uid and a class reference that survives a script move, and the
## numbers below are readable in a way a serialised property list is not.
##
## Radii are authored at [b]editor scale[/b] — a dozen metres, the size the
## preview camera frames — not at the flight scene's 1400 m. [SpaceScene] scales
## its copy up, because the flight scene's radius is pinned by the collision in
## [FlightModel] and must stay exactly [constant SpaceScene.PLANET_RADIUS]. Every
## other number here is a ratio or a colour, so both scales read the same.
extends SceneTree


func _initialize() -> void:
	print("── Default planets ───────────────────────────────────────")
	var err := DirAccess.make_dir_recursive_absolute(PlanetLibrary.PLANETS_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		printerr("could not create %s (%d)" % [PlanetLibrary.PLANETS_DIR, err])
		quit(1)
		return

	var ok := true
	ok = _write(_tarn_iv(), "tarn_iv") and ok
	ok = _write(_tarn_iv_moon(), "tarn_iv_moon") and ok
	_write_index()

	print("")
	if ok:
		print("── DONE ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAILED ────────────────────────────────────────────────")
		quit(1)


func _write(data: PlanetData, id: String) -> bool:
	var path := "%s/%s.tres" % [PlanetLibrary.PLANETS_DIR, id]
	var err := ResourceSaver.save(data, path)
	if err != OK:
		printerr("  could not write %s (%d)" % [path, err])
		return false
	print("  %-40s %s" % [data.planet_name, path])
	return true


## Rewrites the enumeration fallback, the same file [method PlanetLibrary.save]
## maintains — an exported build cannot always list a directory.
func _write_index() -> void:
	var dir := DirAccess.open(PlanetLibrary.PLANETS_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	for file_name in dir.get_files():
		if file_name.get_extension() == "tres":
			files.append(file_name)
	files.sort()
	var file := FileAccess.open(PlanetLibrary.INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"format": PlanetLibrary.INDEX_FORMAT, "planets": files,
	}, "  ") + "\n")
	file.close()
	print("  %-40s %s" % ["index", PlanetLibrary.INDEX_PATH])


## The planet the flight scene's HUD already calls Tarn IV: an ocean world with
## enough land to tell that it is turning.
func _tarn_iv() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Tarn IV"
	d.planet_type = PlanetData.PlanetType.ROCKY
	d.seed_value = 19870506
	d.planet_radius = 12.0
	d.sphere_resolution = 96
	# Continents big enough to be continents at this seed, with ridged mountain
	# ranges along their spines rather than scattered over the whole globe.
	d.terrain_height = 0.055
	d.continent_scale = 0.85
	d.mountain_scale = 4.2
	d.ridge_strength = 0.5
	d.sea_level = 0.5
	d.primary_color = Color(0.55, 0.51, 0.40)   # dry highland
	d.secondary_color = Color(0.27, 0.42, 0.24) # vegetated lowland
	d.water_color = Color(0.06, 0.19, 0.36)
	d.ice_amount = 0.42
	d.detail_strength = 0.20
	d.rotation_speed = 0.006
	# The glow that used to be SpaceScene's hand-built limb shell. Same shader,
	# now sized off the planet it belongs to.
	d.atmosphere_density = 0.55
	d.atmosphere_color = Color(0.45, 0.72, 1.0)
	return d


## Airless, cratered-looking and grey, so it reads as a moon next to the blue
## planet rather than as a second world. No sea, so no waterline: sea_level 0
## lets the generator displace the whole surface, which is what makes it lumpy.
func _tarn_iv_moon() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Tarn IV Moon"
	d.planet_type = PlanetData.PlanetType.ROCKY
	d.seed_value = 4471
	d.planet_radius = 2.6
	# Lower than the planet: it is a fifth the size on screen and never fills it.
	d.sphere_resolution = 48
	d.terrain_height = 0.045
	d.continent_scale = 1.6
	d.mountain_scale = 6.0
	d.ridge_strength = 0.7
	d.sea_level = 0.0
	d.primary_color = Color(0.46, 0.46, 0.49)
	d.secondary_color = Color(0.31, 0.31, 0.34)
	d.water_color = Color(0.20, 0.20, 0.22)
	d.ice_amount = 0.08
	d.detail_strength = 0.30
	d.rotation_speed = 0.003
	d.atmosphere_density = 0.0
	return d
