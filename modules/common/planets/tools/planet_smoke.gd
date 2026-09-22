## Headless smoke test for the planet renderer, the editor and the saved planets.
##
##     godot --headless --path . --script modules/common/planets/tools/planet_smoke.gd
##
## The interesting checks here are the ones about whether the editor can be
## [i]used[/i], not whether it loads. An earlier version of this file asserted that
## the preview planet existed and had a mesh, and passed for weeks while the editor
## drew an opaque panel across the whole window: the planet was there, nobody could
## see it. So this now also asserts that nothing paints over the stage, that the
## camera the input code drives is really an [OrbitCamera], and that a terrain
## slider moves the mesh — the three things that were broken while the old test was
## green.
extends SceneTree

const EDITOR_SCENE := "res://modules/common/planets/planet_editor.tscn"

var _failures: Array[String] = []
# Failures already reported by an earlier section, so each line can say whether
# its own checks passed rather than whether the run as a whole has.
var _reported := 0


func _initialize() -> void:
	print("── Planet editor smoke test ──────────────────────────────")
	_check_planet_data()
	await _check_planet_mesh()
	await _check_editor_ui()
	await _check_editor_terrain_slider()
	_check_library_round_trip()
	await _check_flight_scene_planet()
	await _check_planet_palette_recolour()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Close one section of the report. Prints ok only if nothing failed inside it —
## a line that says ok next to a failure is worse than no line at all.
func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-46s %s" % [label, mark])


## Colours are stored as 8-bit hex, so a round-trip is only ever accurate to
## about 1/255 — [method Color.is_equal_approx] is far tighter than that and would
## fail on every colour that is not exactly on a byte boundary.
func _check_color(actual: Color, expected: Color, what: String) -> void:
	var off := maxf(
		maxf(absf(actual.r - expected.r), absf(actual.g - expected.g)),
		absf(actual.b - expected.b)
	)
	_check(off <= 1.0 / 255.0, "%s did not round-trip (off by %.4f)" % [what, off])


func _check_planet_data() -> void:
	var d := PlanetData.new()
	_check(d.planet_type == PlanetData.PlanetType.ROCKY, "default type not ROCKY")
	_check(d.planet_radius > 0.0, "default radius not positive")
	d.planet_type = PlanetData.PlanetType.GAS_GIANT
	_check(d.is_gas_giant(), "is_gas_giant failed after assignment")
	d.water_color = Color(0.1, 0.3, 0.5)
	d.ice_amount = 0.7
	d.sea_level = 0.33
	var json := d.to_json()
	var restored := PlanetData.from_json(json)
	_check(restored != null, "from_json returned null")
	_check(restored.planet_type == d.planet_type, "type did not round-trip")
	_check(is_equal_approx(restored.planet_radius, d.planet_radius), "radius did not round-trip")
	_check_color(restored.water_color, d.water_color, "water_color")
	_check_color(restored.primary_color, d.primary_color, "primary_color")
	_check_color(restored.secondary_color, d.secondary_color, "secondary_color")
	_check(is_equal_approx(restored.ice_amount, d.ice_amount), "ice_amount did not round-trip")
	_check(is_equal_approx(restored.sea_level, d.sea_level), "sea_level did not round-trip")
	# Format 2 files have no sea colour; they must load as a shade of the lowland
	# rather than as a default blue on a desert world.
	var legacy := PlanetData.from_dict({"format": 2, "secondary": "884422"})
	_check(legacy != null, "format-2 dict failed to load")
	_check(
		legacy != null and not legacy.water_color.is_equal_approx(PlanetData.DEFAULT_WATER),
		"format-2 planet did not derive its sea colour from secondary_color"
	)
	_done("PlanetData round-trip")


func _check_planet_mesh() -> void:
	var planet := Planet.new()
	root.add_child(planet)
	await process_frame
	var d := PlanetData.new()
	d.planet_radius = 3.0
	d.sphere_resolution = 16
	d.ring_enabled = true
	d.ring_inner_radius = 0.4
	d.ring_outer_radius = 1.2
	d.atmosphere_density = 0.5
	planet.configure(d)
	await planet.wait_for_build()
	_check(planet.body() != null, "planet body is null after configure")
	_check(planet.body().mesh != null, "planet body mesh is null")
	_check(planet.body().mesh.get_surface_count() > 0, "planet body mesh has no surfaces")
	_check(planet.ring() != null, "planet ring is null after configure with rings enabled")
	_check(planet.atmosphere() != null, "planet atmosphere is null after configure with atmo > 0")
	# Reconfigure — should tear down and rebuild.
	d.planet_radius = 6.0
	d.ring_enabled = false
	d.atmosphere_density = 0.0
	planet.configure(d)
	await planet.wait_for_build()
	_check(planet.body() != null, "planet body null after reconfigure")
	_check(planet.ring() == null, "planet ring not torn down on reconfigure")
	_check(planet.atmosphere() == null, "planet atmo not torn down on reconfigure")
	_done("Planet mesh builds and reconfigures")

	# The waterline clamp is what makes an ocean round: the generator leaves
	# everything below sea_level sitting on the sphere and lifts only what is
	# above it. Measured on the vertices rather than the AABB, because the bug
	# this replaced pushed the sea floor *inward* — a bounding box never sees
	# that, which is how a crumpled potato passed for a planet.
	var terrain := PlanetData.new()
	terrain.planet_radius = 4.0
	terrain.sphere_resolution = 24
	terrain.terrain_height = 0.0
	terrain.sea_level = 0.5
	planet.configure(terrain)
	await planet.wait_for_build()
	var flat := _radius_range(planet)
	_check(flat.y > 0.0, "the generated body mesh has no vertices")
	_check(
		flat.y - flat.x < 0.02,
		"terrain_height 0 still displaced the sphere (r %.3f..%.3f)" % [flat.x, flat.y]
	)

	terrain.terrain_height = 0.2
	_check(planet.refresh_geometry(), "refresh_geometry refused a pure terrain change")
	await planet.wait_for_build()
	var raised := _radius_range(planet)
	_check(
		raised.y > flat.y + 0.05,
		"peak height raised no land (max r %.3f -> %.3f)" % [flat.y, raised.y]
	)
	_check(
		raised.x > terrain.planet_radius - 0.02,
		"terrain dug below the waterline: min r %.3f under a sea at %.1f" % [
			raised.x, terrain.planet_radius,
		]
	)

	# With no sea there is no waterline to clamp against, so the whole surface
	# should move — that is what makes the airless moon lumpy all over.
	terrain.sea_level = 0.0
	_check(planet.refresh_geometry(), "refresh_geometry refused a sea level change")
	await planet.wait_for_build()
	var drained := _radius_range(planet)
	_check(
		drained.x < terrain.planet_radius - 0.05,
		"sea_level 0 should displace the whole surface, but nothing sank (min r %.3f)" % drained.x
	)
	_done("Terrain rises, sea level holds the waterline")

	planet.queue_free()
	await process_frame


## Smallest and largest distance from the centre to a surface vertex, as
## (min, max). Reads the vertices instead of the AABB because half the point is
## how deep the terrain went, and a bounding box only reports the peaks.
func _radius_range(planet: Planet) -> Vector2:
	var body := planet.body()
	if body == null or body.mesh == null:
		return Vector2.ZERO
	var low := INF
	var high := 0.0
	for surface in body.mesh.get_surface_count():
		var arrays := body.mesh.surface_get_arrays(surface)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for v in verts:
			var r := v.length()
			low = minf(low, r)
			high = maxf(high, r)
	return Vector2(0.0 if is_inf(low) else low, high)


func _check_editor_ui() -> void:
	var editor := await _open_editor()
	if editor == null:
		return

	var planet := editor.get_node_or_null("%PreviewPlanet") as Planet
	_check(planet != null, "PreviewPlanet not found in editor scene")
	_check(planet != null and planet.body() != null, "PreviewPlanet has no body after scene load")

	# The camera the input code drives. This was a Camera3D looked up under the
	# wrong name for the whole life of the old editor, so every drag went nowhere.
	var camera := editor.get_node_or_null("%Camera")
	_check(camera != null, "%Camera not found in editor scene")
	_check(camera is OrbitCamera, "%Camera is not an OrbitCamera — orbit, zoom and framing are dead")

	var stage := editor.get_node_or_null("%Stage") as Control
	_check(stage != null, "%Stage not found in editor scene")
	if stage != null:
		_check(stage.size.x > 400.0, "stage is only %.0fpx wide at 1280x720" % stage.size.x)
		var blockers := _opaque_blockers(editor, stage)
		_check(
			blockers.is_empty(),
			"opaque control(s) cover the 3D stage: %s" % ", ".join(blockers)
		)

	# Every property the panel claims to edit must actually reach a widget.
	for prop: String in [
		"planet_name", "seed_value", "planet_type", "planet_radius", "sphere_resolution",
		"terrain_height", "continent_scale", "mountain_scale", "ridge_strength", "sea_level",
		"primary_color", "secondary_color", "water_color", "ice_amount", "detail_strength",
		"rotation_speed", "band_count", "swirl_speed", "swirl_scale",
		"ring_enabled", "ring_inner_radius", "ring_outer_radius", "ring_dust_density",
		"ring_opacity", "ring_color_a", "ring_color_b",
		"atmosphere_density", "atmosphere_color",
	]:
		_check(editor.widget_for(prop) != null, "no control for PlanetData.%s" % prop)

	_done("Editor drives its scene, stage unobstructed")
	editor.queue_free()
	await process_frame


## The editor in the tree at desktop size, laid out and with its first planet
## built — or null, with the reason recorded, if it could not be opened.
##
## The size matters: the panel is a drawer below [constant PlanetEditor.NARROW_WIDTH]
## and a column above it, so at a phone width the overlay check below would be
## asserting nothing.
func _open_editor() -> PlanetEditor:
	var packed := load(EDITOR_SCENE) as PackedScene
	_check(packed != null, "could not load planet_editor.tscn")
	if packed == null:
		return null
	var editor := packed.instantiate() as PlanetEditor
	_check(editor != null, "planet_editor.tscn root is not a PlanetEditor")
	if editor == null:
		return null
	root.size = Vector2i(1280, 720)
	root.add_child(editor)
	await process_frame
	await process_frame
	_check(
		editor.size.x >= PlanetEditor.NARROW_WIDTH,
		"editor laid out at %.0fpx — too narrow to judge the desktop layout" % editor.size.x
	)
	return editor


## Visible controls that paint an opaque background over the whole stage rectangle.
##
## Ancestors are skipped — the stage sits inside containers by design — as are the
## stage's own children, which are the viewport it is there to show.
func _opaque_blockers(editor: PlanetEditor, stage: Control) -> Array[String]:
	var stage_rect := stage.get_global_rect()
	var found: Array[String] = []
	for node in _all_nodes(editor):
		var control := node as Control
		if control == null or control == stage:
			continue
		if control.is_ancestor_of(stage) or stage.is_ancestor_of(control):
			continue
		if not control.is_visible_in_tree():
			continue
		if not control.get_global_rect().encloses(stage_rect):
			continue
		if _paints_opaque(control):
			found.append(control.name)
	return found


func _paints_opaque(control: Control) -> bool:
	if control.modulate.a < 0.5 or control.self_modulate.a < 0.5:
		return false
	if control is ColorRect:
		return (control as ColorRect).color.a > 0.5
	if control is TextureRect:
		return (control as TextureRect).texture != null
	if control is Panel or control is PanelContainer:
		var style := control.get_theme_stylebox("panel") as StyleBoxFlat
		return style != null and style.bg_color.a > 0.5
	return false


func _all_nodes(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_all_nodes(child))
	return out


## Moving a terrain slider has to move the mesh. The old editor had no terrain
## controls at all, so nothing in the panel could reach the generator's noise.
func _check_editor_terrain_slider() -> void:
	var editor := await _open_editor()
	if editor == null:
		return

	var planet := editor.get_node_or_null("%PreviewPlanet") as Planet
	var slider := editor.widget_for("terrain_height") as HSlider
	_check(slider != null, "terrain_height control is not a slider")
	if planet == null or slider == null:
		editor.queue_free()
		return

	await planet.wait_for_build()
	var before := _radius_range(planet).y
	slider.value = slider.max_value
	_check(
		is_equal_approx(editor.data.terrain_height, slider.max_value),
		"the terrain slider did not write PlanetData.terrain_height"
	)
	editor.flush_pending()
	await planet.wait_for_build()
	var after := _radius_range(planet).y
	_check(
		after > before + 0.05,
		"dragging the terrain slider did not change the mesh (%.3f -> %.3f)" % [before, after]
	)
	_done("Terrain slider reaches the generator")
	editor.queue_free()
	await process_frame


## Planets are content, so they save into the project folder and load back by id.
## The old test wrote into user://, which the game can never read from.
func _check_library_round_trip() -> void:
	_check(PlanetLibrary.can_write(), "PlanetLibrary.can_write() is false in a tool run")

	var d := PlanetData.new()
	d.planet_name = "Smoke Test World"
	d.seed_value = 42
	d.planet_type = PlanetData.PlanetType.GAS_GIANT
	d.ice_amount = 0.61
	d.water_color = Color(0.2, 0.4, 0.6)

	var library := PlanetLibrary.instance()
	var result := library.save(d)
	_check(bool(result["ok"]), "PlanetLibrary.save failed: %s" % String(result["error"]))
	var id := String(result["id"])
	_check(id == "smoke_test_world", "slug is %s, expected smoke_test_world" % id)
	if not bool(result["ok"]):
		return

	# save() drops the cache, so this is a genuine read back off disk.
	var reloaded := PlanetLibrary.instance()
	_check(reloaded.has_id(id), "saved planet is not in the library")
	_check(reloaded.name_of(id) == d.planet_name, "display name did not survive the save")
	var loaded := reloaded.get_data(id)
	_check(loaded != null, "get_data returned null for a planet just saved")
	if loaded != null:
		_check(loaded.seed_value == 42, "seed did not round-trip through the library")
		_check(loaded.is_gas_giant(), "type did not round-trip through the library")
		_check(is_equal_approx(loaded.ice_amount, 0.61), "ice_amount did not round-trip")
		# Copies, not the cached resource: the editor's sliders must not be able to
		# rewrite the library's idea of what is on disk.
		loaded.planet_radius = 99.0
		var second := reloaded.get_data(id)
		_check(
			second != null and not is_equal_approx(second.planet_radius, 99.0),
			"get_data handed out the cached resource instead of a copy"
		)

	# The starter planets the flight scene needs must be there too.
	for bundled: String in ["tarn_iv", "tarn_iv_moon"]:
		_check(
			reloaded.has_id(bundled),
			"%s is missing — run tools/make_default_planets.gd" % bundled
		)
	_check(reloaded.load_errors.is_empty(), "library load errors: %s" % ", ".join(reloaded.load_errors))

	# Leave the folder as the repo ships it.
	DirAccess.remove_absolute("%s/%s.tres" % [PlanetLibrary.PLANETS_DIR, id])
	PlanetLibrary.reset()
	_done("Saves and loads from " + PlanetLibrary.PLANETS_DIR)


## The flight scene must show planets built by this renderer, at exactly the radius
## the collision in [FlightModel] is written against.
func _check_flight_scene_planet() -> void:
	var scene := SpaceScene.new()
	root.add_child(scene)
	await process_frame
	await process_frame

	var pivot := scene.get_node_or_null("Planet")
	_check(pivot != null, "SpaceScene has no Planet node")
	if pivot == null:
		return
	var body := pivot.get_node_or_null("Body") as Planet
	var moon := pivot.get_node_or_null("Moon") as Planet
	_check(body != null, "the flight scene's planet is not a Planet node")
	_check(moon != null, "the flight scene's moon is not a Planet node")
	if body == null or moon == null:
		return

	_check(
		is_equal_approx(body.data.planet_radius, SpaceScene.PLANET_RADIUS),
		"planet radius is %.1f, but FlightModel bounces the ship at %.1f" % [
			body.data.planet_radius, SpaceScene.PLANET_RADIUS,
		]
	)
	_check(
		is_equal_approx(moon.data.planet_radius, SpaceScene.MOON_RADIUS),
		"moon radius is %.1f, expected %.1f" % [moon.data.planet_radius, SpaceScene.MOON_RADIUS]
	)
	_check(
		body.sun_direction.normalized().is_equal_approx(SpaceScene.SUN_DIR.normalized()),
		"the planet is lit from a different direction than the visible star"
	)
	await body.wait_for_build()
	_check(body.body() != null and body.body().mesh != null, "flight scene planet has no mesh")
	_check(
		body.body() != null and body.body().mesh.get_surface_count() > 0,
		"flight scene planet mesh has no surfaces"
	)
	_check(body.atmosphere() != null, "flight scene planet has no atmosphere glow")
	# The whole point of the change: the flight scene reads the saved content.
	_check(body.data.planet_name == "Tarn IV", "flight scene planet is not Tarn IV")
	_done("Flight scene renders saved planets")
	scene.queue_free()
	await process_frame


## A palette switch has to reach the worlds, not just the hulls. A planet keeps a
## snapshot of its authored colours, so this also checks that pushing a palette
## twice restates the blend rather than compounding it.
func _check_planet_palette_recolour() -> void:
	var mgr := StyleManager.instance()
	var saved := mgr.current_palette
	var toon := Palette.find_by_id("toon")
	if toon == null:
		_check(false, "no palette with id 'toon' to recolour a planet against")
		_done("Palette reaches planets")
		return

	var planet := Planet.new()
	root.add_child(planet)
	await process_frame
	var d := PlanetData.new()
	d.planet_radius = 3.0
	d.sphere_resolution = 16
	d.primary_color = Color(0.9, 0.1, 0.1)
	d.secondary_color = Color(0.8, 0.2, 0.2)
	d.water_color = Color(0.1, 0.1, 0.9)
	var authored := d.primary_color

	# No palette active: the authored colours must survive untouched, including
	# through configure. This is what keeps an unconfigured game looking exactly
	# as it did before palettes.
	mgr.current_palette = null
	planet.configure(d)
	await planet.wait_for_build()
	_check(
		d.primary_color.is_equal_approx(authored),
		"a planet was recoloured while no palette was active"
	)

	mgr.current_palette = toon
	planet.apply_palette()
	var once := d.primary_color
	_check(not once.is_equal_approx(authored), "a palette switch did not recolour the planet")
	_check(
		Color(authored).lerp(Palette.color("planet_primary"), Planet.PALETTE_MIX).is_equal_approx(once),
		"planet ground is not the documented authored-to-palette blend"
	)
	# Applying twice must land on the same colour, not blend from the last result.
	planet.apply_palette()
	_check(
		d.primary_color.is_equal_approx(once),
		"a second palette push compounded instead of restating the blend"
	)
	_done("Palette reaches planets")

	mgr.current_palette = saved
	planet.queue_free()
	await process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ " + f)
		quit(1)
