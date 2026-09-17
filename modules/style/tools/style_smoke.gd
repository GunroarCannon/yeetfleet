## Headless smoke test for modules/style: verifies the style system loads
## and can manipulate profiles without requiring a visible window.
##
##     godot --headless --path . --script modules/style/tools/style_smoke.gd
##
## The plan's M3 contract, verified headlessly:
##   - StyleProfile loads correctly
##   - StyleManager singleton works
##   - Grounded and friendly profiles load and differ
##   - MeshRounding actually reshapes geometry (roundness/chunkiness/rock_potato)
##   - Palette actually recolors (saturation/lift)
##   - ShipMaterials wires the style dials onto a real shader material
##
## See TECHNICAL_PLAN.md §M3 for the style module description.

extends SceneTree

var _failures: Array[String] = []
var _reported := 0

func _initialize() -> void:
	print("── style module smoke test ───────────────────────────")

	# Test 1: StyleProfile loads
	await _test_style_profile_loads()

	# Test 2: StyleManager singleton
	await _test_style_manager_singleton()

	# Test 3: Profile loading and differences
	await _test_profile_loading()

	# Test 4: Supporting classes exist
	await _test_supporting_classes()

	# Test 5: MeshRounding actually reshapes geometry
	await _test_mesh_rounding_geometry()

	# Test 6: Palette actually recolors
	await _test_palette_dials()

	# Test 7: ShipMaterials wires the style dials onto a real material
	await _test_ship_materials_style_wiring()

	# Test 8: The cartoony toggle actually changes a live hull's geometry
	await _test_live_style_switch()

	_finish()

func _test_style_profile_loads() -> void:
	# Try to load the StyleProfile script
	var profile_script = load("res://modules/style/scripts/style_profile.gd")
	if profile_script == null:
		_failures.append("Failed to load style_profile.gd")
		_done("StyleProfile loads")
		return

	# Try to instantiate it
	var profile = profile_script.new()
	if profile == null:
		_failures.append("Failed to instantiate StyleProfile")
		_done("StyleProfile loads")
		return

	_done("StyleProfile loads")

func _test_style_manager_singleton() -> void:
	# Test that StyleManager is a proper singleton
	var manager1 = StyleManager.instance()
	var manager2 = StyleManager.instance()

	if manager1 == null:
		_failures.append("StyleManager.instance() returned null")
	elif manager2 == null:
		_failures.append("Second StyleManager.instance() returned null")
	elif manager1 != manager2:
		_failures.append("StyleManager is not a singleton (two different instances)")

	_done("StyleManager singleton")

func _test_profile_loading() -> void:
	# Test loading the built-in profiles
	var grounded = load("res://modules/style/data/profiles/grounded.tres") as StyleProfile
	var friendly = load("res://modules/style/data/profiles/friendly.tres") as StyleProfile

	if grounded == null:
		_failures.append("Failed to load grounded.tres")
	if friendly == null:
		_failures.append("Failed to load friendly.tres")

	# Verify they have different values (they should be clearly different)
	if grounded != null and friendly != null:
		# Check a few key differences
		if grounded.roundness == friendly.roundness:
			_failures.append("grounded and friendly have identical roundness")
		if grounded.shading_bands == friendly.shading_bands:
			_failures.append("grounded and friendly have identical shading_bands")
		if grounded.spec_amount == friendly.spec_amount:
			_failures.append("grounded and friendly have identical spec_amount")

	_done("Profile loading")

func _test_supporting_classes() -> void:
	# Test that the supporting classes can be loaded
	var mesh_rounding_script = load("res://modules/style/scripts/mesh_rounding.gd")
	var palette_script = load("res://modules/style/scripts/palette.gd")

	if mesh_rounding_script == null:
		_failures.append("Failed to load mesh_rounding.gd")
	if palette_script == null:
		_failures.append("Failed to load palette.gd")

	# Try to instantiate them
	if mesh_rounding_script != null:
		var mesh_rounding = mesh_rounding_script.new()
		if mesh_rounding == null:
			_failures.append("Failed to instantiate MeshRounding")

	if palette_script != null:
		var palette = palette_script.new()
		if palette == null:
			_failures.append("Failed to instantiate Palette")

	_done("Supporting classes")

## Real geometry assertions, not just "the class loads": build a plain box
## (LowPoly, unshared flat-shaded verts, same topology every part/rock uses)
## and check each dial actually moves what it claims to.
func _test_mesh_rounding_geometry() -> void:
	var lp := LowPoly.new()
	lp.begin_shape()
	lp.add_box(Vector3.ZERO, Vector3(4.0, 1.0, 1.0))
	lp.end_shape()
	var base_mesh := lp.commit("test_box")
	var base_arrays: Array = base_mesh.surface_get_arrays(0)
	var base_verts: PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var base_normals: PackedVector3Array = base_arrays[Mesh.ARRAY_NORMAL]

	# roundness: reorients normals toward the smoothed average, leaves verts alone.
	var mr_round := MeshRounding.new()
	mr_round.roundness = 1.0
	var rounded := mr_round.apply(base_mesh)
	var r_arrays: Array = rounded.surface_get_arrays(0)
	var r_verts: PackedVector3Array = r_arrays[Mesh.ARRAY_VERTEX]
	var r_normals: PackedVector3Array = r_arrays[Mesh.ARRAY_NORMAL]
	if r_verts != base_verts:
		_failures.append("roundness moved vertices (should only reorient normals)")
	var normals_changed := false
	for i in r_normals.size():
		if not r_normals[i].is_equal_approx(base_normals[i]):
			normals_changed = true
			break
	if not normals_changed:
		_failures.append("roundness=1.0 did not change any normals")

	# chunkiness: moves vertices and shrinks the longest axis relative to the others.
	var mr_chunk := MeshRounding.new()
	mr_chunk.chunkiness = 1.0
	var chunky := mr_chunk.apply(base_mesh)
	var c_arrays: Array = chunky.surface_get_arrays(0)
	var c_verts: PackedVector3Array = c_arrays[Mesh.ARRAY_VERTEX]
	if c_verts == base_verts:
		_failures.append("chunkiness=1.0 did not move any vertices")
	var chunky_aabb := chunky.get_aabb()
	var orig_aabb := base_mesh.get_aabb()
	if chunky_aabb.size.x >= orig_aabb.size.x:
		_failures.append(
			"chunkiness did not shrink the longest axis (x: %.2f -> %.2f)"
			% [orig_aabb.size.x, chunky_aabb.size.x]
		)

	# rock_potato: only displaces verts when is_asteroid is set.
	var mr_potato := MeshRounding.new()
	mr_potato.rock_potato = 1.0
	mr_potato.is_asteroid = false
	var not_potato := mr_potato.apply(base_mesh)
	var np_arrays: Array = not_potato.surface_get_arrays(0)
	if np_arrays[Mesh.ARRAY_VERTEX] != base_verts:
		_failures.append("rock_potato displaced vertices even with is_asteroid=false")

	mr_potato.is_asteroid = true
	var potato := mr_potato.apply(base_mesh)
	var p_arrays: Array = potato.surface_get_arrays(0)
	if p_arrays[Mesh.ARRAY_VERTEX] == base_verts:
		_failures.append("rock_potato=1.0 with is_asteroid=true did not displace any vertices")

	_done("MeshRounding geometry")


## Real color-math assertions for the palette dials, isolated behind a
## save/restore of the live StyleManager profile so this test cannot leak into
## whatever the rest of the suite (or a real scene) expects.
func _test_palette_dials() -> void:
	var mgr := StyleManager.instance()
	var saved_profile := mgr.current_profile

	var profile := StyleProfile.new()
	profile.palette_saturation = 0.0
	profile.palette_lift = 0.0
	mgr.current_profile = profile
	var gray := Palette.get_sat_lifted_color(Color(1.0, 0.0, 0.0))
	if not is_equal_approx(gray.r, gray.g) or not is_equal_approx(gray.g, gray.b):
		_failures.append("palette_saturation=0.0 did not desaturate red to gray (%s)" % gray)

	profile.palette_saturation = 1.0
	profile.palette_lift = 0.5
	var lifted := Palette.get_sat_lifted_color(Color(0.2, 0.2, 0.2))
	if lifted.v <= 0.2:
		_failures.append("palette_lift=0.5 did not brighten the color (%s)" % lifted)

	mgr.current_profile = saved_profile
	_done("Palette dials")


## Confirms the shading-dial and outline wiring actually lands on a real
## ShaderMaterial, and that dropping outline_width back to 0 removes the
## outline pass rather than leaving a stale one at its last width.
func _test_ship_materials_style_wiring() -> void:
	var mgr := StyleManager.instance()
	var saved_profile := mgr.current_profile

	var profile := StyleProfile.new()
	profile.outline_width = 0.02
	profile.outline_color = Color.BLACK
	profile.shading_bands = 3
	profile.spec_amount = 1.5
	profile.rim_amount = 0.5
	mgr.current_profile = profile

	var mat := ShaderMaterial.new()
	mat.shader = ShipMaterials.part_shader()
	ShipMaterials.apply_style_dials(mat)
	if not is_equal_approx(float(mat.get_shader_parameter("shading_bands")), 3.0):
		_failures.append("apply_style_dials did not set shading_bands")
	if not is_equal_approx(float(mat.get_shader_parameter("spec_mult")), 1.5):
		_failures.append("apply_style_dials did not set spec_mult")

	ShipMaterials.apply_outline(mat)
	if mat.next_pass == null:
		_failures.append("apply_outline did not attach a next_pass with outline_width > 0")

	profile.outline_width = 0.0
	ShipMaterials.apply_outline(mat)
	if mat.next_pass != null:
		_failures.append("apply_outline did not remove next_pass when outline_width == 0")

	mgr.current_profile = saved_profile
	_done("ShipMaterials style wiring")


## The cartoony toggle's whole promise: flipping to a rounder look changes a hull
## that is already built, without a scene reload.
##
## Exercises the real path a consumer takes — [method ShipView.restyle] against the
## real part factory — rather than MeshRounding directly, because the failure this
## guards against is not "roundness works" (test 5) but "a ship already in the
## scene keeps the mesh it was built with".
func _test_live_style_switch() -> void:
	var library := PartLibrary.instance()
	library.load_all()
	if library.presets.is_empty():
		_failures.append("no ship presets to build a hull from")
		_done("Live style switch")
		return
	var preset_id := String(library.presets[0].get("id", ""))
	var design := library.build_preset_design(preset_id)
	if design == null:
		_failures.append("could not build preset design '%s'" % preset_id)
		_done("Live style switch")
		return

	var mgr := StyleManager.instance()
	var saved_profile := mgr.current_profile

	# Grounded: no rounding, so the hull is the raw LowPoly output.
	mgr.current_profile = load("res://modules/style/data/profiles/grounded.tres") as StyleProfile
	var grounded_view := ShipAssembler.assemble(design, library, 0.0, false, false)
	var grounded_size := grounded_view.aabb.size
	var grounded_token := PartMeshFactory.style_token()

	# Cartoony: roundness and chunkiness both move vertices.
	mgr.current_profile = load("res://modules/style/data/profiles/cartoony.tres") as StyleProfile
	var cartoony_token := PartMeshFactory.style_token()
	if cartoony_token == grounded_token:
		_failures.append("cartoony and grounded share a mesh-cache token")
	var cartoony_view := ShipAssembler.assemble(design, library, 0.0, false, false)
	if cartoony_view.aabb.size.is_equal_approx(grounded_size):
		_failures.append("cartoony built the same geometry as grounded")

	# The live half: an already-built hull has to change when asked.
	grounded_view.restyle()
	if grounded_view.aabb.size.is_equal_approx(grounded_size):
		_failures.append("restyle() left the hull's geometry unchanged")
	# And switching back has to land where it started, or the toggle is a one-way
	# ratchet — this is the cache-key-was-right check.
	mgr.current_profile = load("res://modules/style/data/profiles/grounded.tres") as StyleProfile
	grounded_view.restyle()
	if not grounded_view.aabb.size.is_equal_approx(grounded_size):
		_failures.append(
			"switching back to grounded did not restore the original bounds (%s != %s)"
				% [grounded_view.aabb.size, grounded_size]
		)
	# A chunkier hull is a wider hull, so the collision hull must move with it —
	# otherwise the ship collides along a silhouette it no longer has.
	if cartoony_view.collision_hull().is_empty():
		_failures.append("the cartoony hull produced no collision sections")

	mgr.current_profile = saved_profile
	grounded_view.destroy()
	cartoony_view.destroy()
	_done("Live style switch")


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-35s %s" % [label, mark])

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