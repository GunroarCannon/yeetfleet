## reputation_shot.gd — visual screenshot for modules/reputation/
##
## Renders a top-down diagram showing:
##   - Player ship (blue cube) at centre
##   - Faction ships at varying distances, labelled with their heat level
##   - Recognition status banners above each faction ship
##   - A Witness range circle (wireframe cylinder)
##
## Run:
##   "$GD" --path . --headless --script modules/reputation/tools/reputation_shot.gd
##
## Output: reputation.png in the project root.
extends SceneTree

const OUT_PATH  := "reputation.png"
const IMG_W     := 1024
const IMG_H     := 768

func _init() -> void:
	var vp := get_root()
	vp.size = Vector2i(IMG_W, IMG_H)

	# --- Camera -------------------------------------------------------
	var cam := Camera3D.new()
	cam.position = Vector3(0, 28, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.fov = 55.0
	vp.add_child(cam)

	# --- Lighting -----------------------------------------------------
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.08)
	e.ambient_light_color = Color(0.4, 0.4, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 45, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)

	# --- Build a SessionRepStore with some history --------------------
	var store := SessionRepStore.new()
	store.record_act("player", "empire",  RepStore.ACTS.ATTACK, 6)
	store.record_act("player", "traders", RepStore.ACTS.STEAL,  2)
	store.record_act("player", "pirates", RepStore.ACTS.RESCUE, 4)

	# --- Scenario ships -----------------------------------------------
	var ships := [
		{
			"label":     "EMPIRE PATROL",
			"faction_id": "empire",
			"pos":       Vector3(-7, 0, -5),
			"color":     Color(0.6, 0.7, 1.0),
		},
		{
			"label":     "TRADERS GUILD",
			"faction_id": "traders",
			"pos":       Vector3(7, 0, -3),
			"color":     Color(0.8, 0.9, 0.5),
		},
		{
			"label":     "PIRATES",
			"faction_id": "pirates",
			"pos":       Vector3(0, 0, 7),
			"color":     Color(1.0, 0.4, 0.3),
		},
		{
			"label":     "FAR PATROL (out of range)",
			"faction_id": "empire",
			"pos":       Vector3(14, 0, 0),
			"color":     Color(0.5, 0.5, 0.5),
		},
	]

	var player_pos := Vector3.ZERO

	# Player ship.
	_add_cube(vp, player_pos, Color(0.3, 0.5, 1.0), 1.0)
	_add_label3d(vp, player_pos + Vector3(0, 1.5, 0), "PLAYER", Color.WHITE, 0.08)

	# Witness range ring (approximate with thin cylinder).
	_add_range_ring(vp, player_pos, 8.0)

	# Faction ships.
	for s in ships:
		var pos: Vector3 = s["pos"]
		var dist := float(pos.length())
		var faction: String = s["faction_id"]
		var heat := store.get_heat("player", faction)
		var result := Recognition.evaluate("player", faction, store, dist * 40.0)
		# 40 units = 1000 m scale for display; transponder range = 500 m = 12.5 units

		# Use actual transponder range mapping (1 unit = ~40m in this scene).
		# TRANSPONDER_RANGE_M = 500 → 12.5 units. Ships at 7–14 units = 280–560m.
		var display_result := Recognition.evaluate("player", faction, store,
			dist * (float(Recognition.TRANSPONDER_RANGE_M) / 12.5))

		_add_cube(vp, pos, s["color"], 0.7)

		# Faction label.
		_add_label3d(vp, pos + Vector3(0, 1.6, 0), s["label"], s["color"], 0.055)

		# Heat bar (text).
		var heat_str := "Heat: %d" % heat
		_add_label3d(vp, pos + Vector3(0, 2.2, 0), heat_str, Color(1.0, 0.7, 0.3), 0.055)

		# Recognition status.
		var rlabel := Recognition.label_for(display_result)
		if rlabel.is_empty():
			rlabel = "—"
		var rcol := Color(0.5, 1.0, 0.5)
		match display_result:
			Recognition.RecognitionResult.KOS:
				rcol = Color(1.0, 0.1, 0.1)
			Recognition.RecognitionResult.HOSTILE:
				rcol = Color(1.0, 0.5, 0.1)
			Recognition.RecognitionResult.IDENTIFIED:
				rcol = Color(0.9, 0.9, 0.3)
		_add_label3d(vp, pos + Vector3(0, 2.8, 0), rlabel, rcol, 0.06)

	await process_frame
	await process_frame

	var img := vp.get_texture().get_image()
	img.save_png(OUT_PATH)
	print("Saved: ", OUT_PATH)
	quit(0)


func _add_cube(parent: Node, pos: Vector3, col: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(size, size * 0.4, size)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.3
	mat.roughness = 0.6
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_label3d(parent: Node, pos: Vector3, text: String, col: Color, px: float) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = px
	lbl.font_size = 28
	lbl.modulate = col
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = pos
	parent.add_child(lbl)


func _add_range_ring(parent: Node, centre: Vector3, radius: float) -> void:
	# Thin cylinder as range indicator.
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.05
	m.rings = 1
	m.radial_segments = 48
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	# Label.
	_add_label3d(parent, centre + Vector3(radius + 0.5, 0, 0),
		"TRANSPONDER\nRANGE", Color(0.4, 0.6, 1.0, 0.8), 0.045)
