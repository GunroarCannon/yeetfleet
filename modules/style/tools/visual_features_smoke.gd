## visual_features_smoke.gd — headless test for visual toggles, palettes, mobile fit, and mesh/collision baking.
##
## Run:
##   "$GD" --path . --headless --script modules/style/tools/visual_features_smoke.gd
extends SceneTree

const PASS := "  [PASS] "
const FAIL := "  [FAIL] "
var _errors := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print(PASS + msg)
	else:
		printerr(FAIL + msg)
		_errors += 1

func _assert_near(a: float, b: float, msg: String, tol: float = 0.01) -> void:
	_assert(absf(a - b) < tol, msg + " (got %.4f, want %.4f)" % [a, b])


func _init() -> void:
	print("\n=== visual_features smoke ===\n")

	_test_palette_system()
	_test_art_style_toggle()
	_test_mesh_baker_and_colliders()
	_test_mobile_view_fit()

	print("\n--- %d assertion(s) failed ---\n" % _errors)
	quit(1 if _errors > 0 else 0)


# ---------------------------------------------------------------------------
# 1. Palette System
# ---------------------------------------------------------------------------

func _test_palette_system() -> void:
	print("-- Palette System & Swatches --")
	var palettes := Palette.all()
	_assert(palettes.size() >= 5, "at least 5 palettes available (found %d)" % palettes.size())

	var ids := []
	for p in palettes:
		ids.append(p.id)
	_assert("toon" in ids, "toon palette exists")
	_assert("nebula" in ids, "nebula palette exists")
	_assert("ice" in ids, "ice palette exists")

	# Test toon palette swatches
	var toon := Palette.find_by_id("toon")
	_assert(toon != null, "find_by_id('toon') succeeded")
	var swatches := toon.swatches()
	_assert(swatches.size() == Palette.ROLES.size(), "swatches() matches ROLES size (%d)" % swatches.size())

	# Verify no magenta or zero colors in swatches
	var magenta_count := 0
	for s in swatches:
		var c: Color = s["color"]
		if c == Color.MAGENTA:
			magenta_count += 1
	_assert(magenta_count == 0, "no unassigned (magenta) color swatches in toon palette")

	# Test active palette switching
	var mgr := StyleManager.instance()
	var emitted := {"palette": false}
	var conn = mgr.palette_changed.connect(func(_p: Palette) -> void: emitted["palette"] = true)

	mgr.set_palette(toon)
	_assert(mgr.current_palette.id == "toon", "current_palette is now toon")
	_assert(emitted["palette"], "palette_changed signal emitted")
	_assert(Palette.color("hull_primary") == toon.hull_primary, "Palette.color() returns active toon color")


# ---------------------------------------------------------------------------
# 2. Art Style System (Cartoony & Rounded vs Grounded)
# ---------------------------------------------------------------------------

func _test_art_style_toggle() -> void:
	print("-- Art Style Toggle (Cartoony & Rounded vs Grounded) --")
	var mgr := StyleManager.instance()

	# Switch to grounded
	mgr.set_profile_by_id("grounded")
	_assert(mgr.current_profile != null and mgr.current_profile.id == "grounded", "set_profile_by_id('grounded') works")
	_assert_near(mgr.current_profile.roundness, 0.0, "grounded has 0.0 roundness")
	_assert_near(mgr.current_profile.chunkiness, 0.0, "grounded has 0.0 chunkiness")

	# Toggle to cartoony
	var cartoony_prof := mgr.toggle_art_style()
	_assert(cartoony_prof.id == "cartoony", "toggle_art_style switched to cartoony")
	_assert(cartoony_prof.roundness > 0.5, "cartoony has roundness > 0.5 (got %.2f)" % cartoony_prof.roundness)
	_assert(cartoony_prof.chunkiness > 0.2, "cartoony has chunkiness > 0.2 (got %.2f)" % cartoony_prof.chunkiness)
	_assert(cartoony_prof.star_five_point > 0.5, "cartoony has 5-point cartoon stars")
	_assert(cartoony_prof.outline_width > 0.01, "cartoony has outline width > 0.01")

	# Toggle back to grounded
	var grounded_prof := mgr.toggle_art_style()
	_assert(grounded_prof.id == "grounded", "toggle_art_style switched back to grounded")


# ---------------------------------------------------------------------------
# 3. MeshBaker & Part Colliders
# ---------------------------------------------------------------------------

func _test_mesh_baker_and_colliders() -> void:
	print("-- MeshBaker & Ship Part Colliders --")
	var library := PartLibrary.instance()
	library.load_all()
	if library.presets.is_empty():
		_assert(false, "preset library has ships")
		return

	var preset_id := String(library.presets[0].get("id", ""))
	var design := library.build_preset_design(preset_id)
	_assert(design != null, "built preset design")

	var view := ShipAssembler.assemble(design, library, 0.0, false, false)
	_assert(view != null, "assembled ShipView")
	_assert(view.resolution.placements.size() > 0, "view has placements")

	# Part colliders creation
	var test_body := StaticBody3D.new()
	var colliders := view.create_part_colliders(test_body)
	_assert(colliders.size() == view.resolution.placements.size(),
		"created part colliders for each part (%d == %d)" % [colliders.size(), view.resolution.placements.size()])
	_assert(colliders[0].shape is BoxShape3D, "collider shape is BoxShape3D")
	_assert(colliders[0].has_meta("part_path"), "collider carries part_path metadata")

	# Baked mesh generation
	var baked_inst := MeshBaker.bake_ship_mesh(view)
	_assert(baked_inst != null, "bake_ship_mesh produced MeshInstance3D")
	_assert(baked_inst.mesh != null, "baked instance has ArrayMesh")
	_assert(baked_inst.mesh.get_surface_count() > 0, "baked mesh has surfaces")

	# Enable baked mesh mode on view
	view.enable_baked_mesh(true)
	_assert(view.baked_mesh_instance != null and view.baked_mesh_instance.visible, "baked mesh enabled and visible")
	view.enable_baked_mesh(false)
	_assert(not view.baked_mesh_instance.visible, "baked mesh disabled and invisible")

	# Baked compound spheres
	var baked_spheres := MeshBaker.bake_compound_spheres(view.part_boxes)
	_assert(baked_spheres.size() > 0, "baked compound spheres generated (%d spheres)" % baked_spheres.size())
	_assert(baked_spheres[0].has("offset") and baked_spheres[0].has("radius"), "sphere has offset & radius")

	if baked_inst != null:
		baked_inst.free()
	view.root.free()
	test_body.free()


# ---------------------------------------------------------------------------
# 4. Mobile Screen View Fit
# ---------------------------------------------------------------------------

func _test_mobile_view_fit() -> void:
	print("-- Mobile Screen View Fit --")
	var cam_rig := FlightCamera.new()

	_assert(not Session.mobile_view_fit, "default mobile_view_fit is false")

	cam_rig.set_mobile_view(true)
	_assert_near(cam_rig.chase_scale, 0.72, "mobile view tightens chase distance to 0.72")
	_assert_near(cam_rig.base_fov, 62.0, "mobile view tightens FOV to 62.0°")

	cam_rig.set_mobile_view(false)
	_assert_near(cam_rig.chase_scale, 1.0, "desktop view restores chase distance to 1.0")
	_assert_near(cam_rig.base_fov, 72.0, "desktop view restores FOV to 72.0°")

	cam_rig.free()
