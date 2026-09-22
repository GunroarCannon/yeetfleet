## visual_showcase_shot.gd — renders and screenshots the visual palette menu,
## swatches grid, cartoony rounded look, and mobile view fit.
##
## Run:
##   "$GD" --path . --rendering-driver opengl3 --script modules/style/tools/visual_showcase_shot.gd -- visual_palette_showcase.png
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "visual_palette_showcase.png" if args.is_empty() else String(args[0])
	var warm := 25 if args.size() < 2 else int(args[1])
	var size := Vector2i(1280, 720)

	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size

	# Configure StyleManager to Toon palette + Cartoony rounded look
	var mgr := StyleManager.instance()
	var toon_pal := Palette.find_by_id("toon")
	if toon_pal != null:
		mgr.set_palette(toon_pal)

	var cartoony_prof := mgr.find_profile("cartoony")
	if cartoony_prof != null:
		mgr.set_profile(cartoony_prof)

	Session.mobile_view_fit = true

	# Build 3D world with ship & scenery
	var world := Node3D.new()
	world.name = "ShowcaseWorld"
	root.add_child(world)

	# Environment
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Palette.color("background")
	e.ambient_light_color = Palette.color("ambient")
	e.ambient_light_energy = 0.95
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_node.environment = e
	world.add_child(env_node)

	# Key light (front-three-quarters illuminating the ship)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.98, 0.92)
	sun.light_energy = 1.8
	world.add_child(sun)

	# Camera fill light
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(10.0, 15.0, 0.0)
	fill.light_color = Palette.color("star").lerp(Color.WHITE, 0.5)
	fill.light_energy = 0.9
	world.add_child(fill)

	# Camera with mobile-fit framing
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, -0.4, 8.2)
	cam.fov = 58.0
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, -1.8, 0.0), Vector3.UP)
	cam.current = true

	# Assemble a player ship with cartoony rounded style
	var lib := PartLibrary.instance()
	lib.load_all()
	var design: ShipDesign = null
	if not lib.presets.is_empty():
		design = lib.build_preset_design(String(lib.presets[0].get("id", "")))
	if design != null:
		design.refresh_palette()
		var ship_view := ShipAssembler.assemble(design, lib, 0.0, false, false)
		ship_view.restyle(true)
		ship_view.root.position = Vector3(0.0, -1.8, 0.0)
		ship_view.root.rotation_degrees = Vector3(12.0, -40.0, 5.0)
		world.add_child(ship_view.root)

	# Add a couple of stylized cartoon rocks
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Palette.color("rock_mid")
	rock_mat.roughness = 0.8
	var rock1 := MeshInstance3D.new()
	var rmesh1 := SphereMesh.new()
	rmesh1.radius = 1.4
	rmesh1.height = 2.8
	rmesh1.radial_segments = 12
	rmesh1.rings = 6
	rock1.mesh = rmesh1
	rock1.material_override = rock_mat
	rock1.position = Vector3(-6.5, -1.0, -3.0)
	world.add_child(rock1)

	var rock2 := MeshInstance3D.new()
	var rmesh2 := SphereMesh.new()
	rmesh2.radius = 0.9
	rmesh2.height = 1.8
	rmesh2.radial_segments = 10
	rmesh2.rings = 5
	rock2.mesh = rmesh2
	rock2.material_override = rock_mat
	rock2.position = Vector3(7.0, 1.5, -5.0)
	world.add_child(rock2)

	# 2D HUD Canvas with TopBar & Open Palette Drawer
	var canvas := CanvasLayer.new()
	root.add_child(canvas)

	# Top Bar
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 12.0
	top_bar.offset_right = -12.0
	top_bar.offset_top = 10.0
	top_bar.custom_minimum_size = Vector2(0.0, 44.0)
	canvas.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text = "PROJECT NEBULA"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Palette.color("ui_text_strong"))
	top_bar.add_child(title_lbl)

	var pal_chip := Button.new()
	pal_chip.text = "🎨 TOON PALETTE"
	pal_chip.custom_minimum_size = Vector2(130, 36)
	top_bar.add_child(pal_chip)

	# Dots
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 4)
	for r in ["background", "star", "hull_primary", "hull_accent", "ui_accent"]:
		var cr := ColorRect.new()
		cr.color = Palette.color(r)
		cr.custom_minimum_size = Vector2(10, 16)
		dots.add_child(cr)
	top_bar.add_child(dots)

	var style_chip := Button.new()
	style_chip.text = "✨ CARTOONY & ROUNDED"
	style_chip.custom_minimum_size = Vector2(170, 36)
	style_chip.add_theme_color_override("font_color", Palette.color("ui_good"))
	top_bar.add_child(style_chip)

	var mob_chip := Button.new()
	mob_chip.text = "📱 MOBILE SCREEN FIT"
	mob_chip.custom_minimum_size = Vector2(160, 36)
	mob_chip.add_theme_color_override("font_color", Palette.color("ui_select"))
	top_bar.add_child(mob_chip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var speed_chip := Button.new()
	speed_chip.text = "180 m/s"
	speed_chip.add_theme_font_size_override("font_size", 18)
	speed_chip.add_theme_color_override("font_color", Palette.color("ui_accent"))
	top_bar.add_child(speed_chip)

	# Open Palette Drawer Panel
	var drawer := PanelContainer.new()
	drawer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drawer.offset_left = 12.0
	drawer.offset_right = -12.0
	drawer.offset_top = 58.0
	drawer.custom_minimum_size = Vector2(0.0, 240.0)

	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Palette.color("ui_bg_panel")
	dsb.border_color = Palette.color("ui_accent")
	dsb.border_width_bottom = 2
	dsb.border_width_left = 2
	dsb.border_width_right = 2
	dsb.border_width_top = 2
	dsb.corner_radius_bottom_left = 8
	dsb.corner_radius_bottom_right = 8
	dsb.content_margin_left = 14
	dsb.content_margin_right = 14
	dsb.content_margin_top = 10
	dsb.content_margin_bottom = 12
	drawer.add_theme_stylebox_override("panel", dsb)
	canvas.add_child(drawer)

	var dvbox := VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 8)
	drawer.add_child(dvbox)

	# Drawer Header
	var dheader := HBoxContainer.new()
	var dtitle := Label.new()
	dtitle.text = "🎨 COLOR PALETTES & ART STYLE CONTROLS"
	dtitle.add_theme_font_size_override("font_size", 14)
	dtitle.add_theme_color_override("font_color", Palette.color("ui_accent"))
	dheader.add_child(dtitle)

	var dspacer := Control.new()
	dspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dheader.add_child(dspacer)

	var badge := Label.new()
	badge.text = "ACTIVE PALETTE: TOON (42 COLOR ROLES)"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Palette.color("ui_good"))
	dheader.add_child(badge)
	dvbox.add_child(dheader)

	# Palette Tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for p in Palette.all():
		var b := Button.new()
		b.text = ("● " if p.id == "toon" else "") + p.display_name
		b.custom_minimum_size = Vector2(100, 30)
		if p.id == "toon":
			b.add_theme_color_override("font_color", Palette.color("ui_select"))
		tabs.add_child(b)
	dvbox.add_child(tabs)

	# Swatches Grid
	var sgrid := HFlowContainer.new()
	sgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sgrid.add_theme_constant_override("h_separation", 6)
	sgrid.add_theme_constant_override("v_separation", 6)
	dvbox.add_child(sgrid)

	for row in toon_pal.swatches():
		var col: Color = row["color"]
		var lbl: String = row["label"]
		var card := HBoxContainer.new()
		card.custom_minimum_size = Vector2(148, 22)

		var crect := ColorRect.new()
		crect.color = col
		crect.custom_minimum_size = Vector2(18, 18)
		card.add_child(crect)

		var cname := Label.new()
		cname.text = lbl
		cname.add_theme_font_size_override("font_size", 10)
		card.add_child(cname)

		var chex := Label.new()
		chex.text = "#" + col.to_html(false).substr(0, 6)
		chex.add_theme_font_size_override("font_size", 9)
		chex.add_theme_color_override("font_color", Palette.color("ui_text_dim"))
		card.add_child(chex)

		sgrid.add_child(card)

	# Quick toggles row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)

	var b_cart := Button.new()
	b_cart.text = "✨ Art Style: CARTOONY & ROUNDED (Active)"
	b_cart.add_theme_color_override("font_color", Palette.color("ui_good"))
	action_row.add_child(b_cart)

	var b_mob := Button.new()
	b_mob.text = "📱 Mobile Screen Fit: ENABLED (Active)"
	b_mob.add_theme_color_override("font_color", Palette.color("ui_select"))
	action_row.add_child(b_mob)

	var b_bake := Button.new()
	b_bake.text = "⚡ Mesh & Collider Baking: OPTIMIZED"
	action_row.add_child(b_bake)

	dvbox.add_child(action_row)

	# Warm up frames
	for _i in warm:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
