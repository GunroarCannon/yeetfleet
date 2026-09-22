## DestructionLabRoot: dedicated testbed for explosions, shockwaves, impacts,
## physical shattering, and planetary destruction.
##
## Allows free camera flythrough, spawning mega ships, fighters, planets, asteroid
## clusters and fuel tanks, clicking on any object in 3D to inspect and trigger
## a variety of destructive physical and visual effects.
class_name DestructionLabRoot
extends Node3D

enum CamMode { FREE_FLY, ORBIT }

const LOOK_SENSITIVITY := 0.22
const FREE_SPEED_DEFAULT := 75.0
const FREE_SPEED_MIN := 5.0
const FREE_SPEED_MAX := 2500.0
const ORBIT_DIST_DEFAULT := 90.0

const PhysicalShockwave = preload("res://modules/physics/scripts/physical_shockwave.gd")
const PlanetDebrisBuilder = preload("res://modules/common/planets/planet_debris_builder.gd")

# --- Camera State ---
var _cam: Camera3D
var _cam_mode: int = CamMode.FREE_FLY
var _free_pos := Vector3(0.0, 30.0, 75.0)
var _free_yaw := 0.0
var _free_pitch := -15.0
var _free_speed := FREE_SPEED_DEFAULT

var _orbit_target := Vector3.ZERO
var _orbit_yaw := 30.0
var _orbit_pitch := 20.0
var _orbit_dist := ORBIT_DIST_DEFAULT
var _is_mouse_looking := false

# --- 3D Scene Nodes ---
var _objects_root: Node3D
var _effects_root: Node3D
var _debris_root: Node3D
var _reticle_node: MeshInstance3D

# --- Selection State ---
var _selected_node: Node = null
var _selected_pos := Vector3.ZERO
var _selected_normal := Vector3.UP

# --- Dials / Tuning ---
var blast_scale := 1.0
var blast_impulse := 80.0
var blast_radius := 25.0
var time_scale := 1.0

# --- Effect Catalog & Comparison ---
## Every effect the lab can trigger, as `{name, call, centered, sound}`:
## [code]call[/code] runs it, [code]centered[/code] says whether it happens at the
## action point (so it can go in a comparison row — a railgun strike originates
## at the camera and cannot), and [code]sound[/code] is the Sci-Fi Sound Library
## id to play with it. Built once in [method _build_effect_catalog].
var _effects: Array[Dictionary] = []
var _effect_picker: OptionButton
var _spacing := 45.0
## When set, [method get_action_pos] returns this instead of the reticle or the
## point ahead of the camera. It is how one trigger function can be aimed at an
## arbitrary spot for a side-by-side comparison without any of them needing a
## position argument.
var _action_override := Vector3.ZERO
var _has_action_override := false

# --- UI Controls ---
var _ui_root: Control
var _target_name_label: Label
var _target_detail_label: Label
var _stats_label: Label
var _cam_mode_btn: Button
var _time_btn_1: Button
var _time_btn_half: Button
var _time_btn_slow: Button
var _time_btn_pause: Button
var _studio_modal: PanelContainer = null
var _studio_slot_picker: OptionButton = null
var _studio_effect_picker: OptionButton = null
var _studio_scale_slider: HSlider = null
var _studio_scale_lbl: Label = null
var _studio_sound_picker: OptionButton = null
var _studio_shockwave_check: CheckBox = null
var _studio_debris_check: CheckBox = null
var _studio_shake_slider: HSlider = null
var _studio_shake_lbl: Label = null
var _studio_origin_label: Label = null
var _studio_desc_label: Label = null
var _studio_status_label: Label = null
var _studio_color_rect: ColorRect = null


func _ready() -> void:
	get_window().theme = BuilderTheme.build()
	# The layer checkboxes below reflect the saved toggles, so make sure the
	# settings have been read before the UI is built from them.
	FxSettings.ensure_loaded()
	_setup_environment()
	_setup_scene_trees()
	_setup_camera()
	_setup_selection_reticle()
	# The catalog has to exist before the picker is built from it.
	_build_effect_catalog()
	_build_ui()
	
	# Spawn default demo arrangement
	_spawn_mega_ship(LargeCraftGenerator.Archetype.DREADNOUGHT, Vector3(0.0, 0.0, 0.0))
	_spawn_asteroid_cluster(Vector3(-45.0, 10.0, -20.0), 8)
	_spawn_fuel_tanks(Vector3(35.0, -5.0, 10.0))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("03060d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("1e2638")
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0
	
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	add_child(holder)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_energy = 1.5
	sun.light_color = Color("fff6ea")
	sun.shadow_enabled = false
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -0.6, -0.4), Vector3.UP)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.5
	fill.light_color = Color("6888c0")
	fill.shadow_enabled = false
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.5, 0.4, 0.5), Vector3.UP)
	add_child(fill)


func _setup_scene_trees() -> void:
	_objects_root = Node3D.new()
	_objects_root.name = "SpawnedObjects"
	add_child(_objects_root)

	_effects_root = Node3D.new()
	_effects_root.name = "ActiveEffects"
	add_child(_effects_root)

	_debris_root = Node3D.new()
	_debris_root.name = "DebrisPieces"
	add_child(_debris_root)


func _setup_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.current = true
	_cam.near = 0.2
	_cam.far = 150000.0
	add_child(_cam)
	_update_camera_transform()


func _setup_selection_reticle() -> void:
	_reticle_node = MeshInstance3D.new()
	_reticle_node.name = "SelectionReticle"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.8
	ring.outer_radius = 2.1
	_reticle_node.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.9, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.9, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reticle_node.material_override = mat
	_reticle_node.visible = false
	add_child(_reticle_node)


# --- Camera Updates & Input ---------------------------------------------------

func _process(delta: float) -> void:
	if _selected_node != null and not is_instance_valid(_selected_node):
		_selected_node = null
		_reticle_node.visible = false
		_target_name_label.text = "Target: None"
		_target_detail_label.text = "Click any object in 3D scene"

	if _cam_mode == CamMode.FREE_FLY:
		_process_free_fly_movement(delta)
	elif _cam_mode == CamMode.ORBIT:
		_process_orbit_movement(delta)
	
	_update_camera_transform()
	_update_stats_label()
	
	if _reticle_node.visible:
		_reticle_node.rotate_y(delta * 1.5)


func _process_free_fly_movement(delta: float) -> void:
	var move_vec := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_vec.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move_vec.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move_vec.x += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		move_vec.y += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_C):
		move_vec.y -= 1.0
	
	if move_vec.length_squared() > 0.001:
		move_vec = move_vec.normalized()
		var speed := _free_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 3.0
		var basis := _cam.global_transform.basis
		var world_move := basis.x * move_vec.x + Vector3.UP * move_vec.y + basis.z * move_vec.z
		_free_pos += world_move * (speed * delta)


func _process_orbit_movement(_delta: float) -> void:
	# Orbit focus target updates dynamically
	if _selected_node != null and is_instance_valid(_selected_node):
		var target_pos := _selected_pos
		if _selected_node is Node3D:
			target_pos = (_selected_node as Node3D).global_position
		_orbit_target = _orbit_target.lerp(target_pos, 0.1)


func _update_camera_transform() -> void:
	if _cam_mode == CamMode.FREE_FLY:
		_cam.global_position = _free_pos
		var yaw_rad := deg_to_rad(_free_yaw)
		var pitch_rad := deg_to_rad(_free_pitch)
		var b := Basis(Vector3.UP, yaw_rad) * Basis(Vector3.RIGHT, pitch_rad)
		_cam.global_transform.basis = b
	else:
		var yaw_rad := deg_to_rad(_orbit_yaw)
		var pitch_rad := deg_to_rad(_orbit_pitch)
		var rot := Basis(Vector3.UP, yaw_rad) * Basis(Vector3.RIGHT, pitch_rad)
		var offset := rot * Vector3(0.0, 0.0, _orbit_dist)
		_cam.global_position = _orbit_target + offset
		_cam.look_at(_orbit_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_mouse_looking = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if _cam_mode == CamMode.FREE_FLY:
				_free_speed = clampf(_free_speed * 1.25, FREE_SPEED_MIN, FREE_SPEED_MAX)
			else:
				_orbit_dist = clampf(_orbit_dist * 0.88, 5.0, 30000.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if _cam_mode == CamMode.FREE_FLY:
				_free_speed = clampf(_free_speed * 0.8, FREE_SPEED_MIN, FREE_SPEED_MAX)
			else:
				_orbit_dist = clampf(_orbit_dist * 1.14, 5.0, 30000.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_raycast_click_selection(mb.position)
	elif event is InputEventMouseMotion and _is_mouse_looking:
		var mm := event as InputEventMouseMotion
		if _cam_mode == CamMode.FREE_FLY:
			_free_yaw -= mm.relative.x * LOOK_SENSITIVITY
			_free_pitch = clampf(_free_pitch - mm.relative.y * LOOK_SENSITIVITY, -89.0, 89.0)
		else:
			_orbit_yaw -= mm.relative.x * LOOK_SENSITIVITY
			_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * LOOK_SENSITIVITY, -89.0, 89.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_1: trigger_heavy_explosion()
			KEY_2: trigger_shockwave_ring()
			KEY_3: trigger_railgun_strike()
			KEY_4: trigger_shatter_radius()
			KEY_5: trigger_antimatter_core()
			KEY_6: trigger_total_breakup()
			KEY_TAB: toggle_camera_mode()
			KEY_F: frame_selected_target()
			KEY_DELETE: delete_selected_target()
			KEY_R: reset_scene()
			KEY_C: spawn_selected_effect()
			KEY_V: compare_effects_row()


func _raycast_click_selection(mouse_screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(mouse_screen_pos)
	var dir := _cam.project_ray_normal(mouse_screen_pos)
	var ray_len := 50000.0
	var to := from + dir * ray_len

	var w3d := get_world_3d()
	if w3d == null:
		return
	var space_state := w3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)

	if not result.is_empty():
		var collider: Object = result["collider"]
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result.get("normal", Vector3.UP)
		select_object(collider, hit_pos, hit_normal)
	else:
		# Check distance to planets or visual models in _objects_root
		var hit_obj: Node = null
		var hit_pt := Vector3.ZERO
		var best_dist := ray_len

		for child in _objects_root.get_children():
			var p_node: Planet = null
			if child is Planet:
				p_node = child as Planet
			else:
				var sub := child.find_children("", "Planet", true, false)
				if not sub.is_empty():
					p_node = sub[0] as Planet

			var c_pos := (child as Node3D).global_position if child is Node3D else Vector3.ZERO
			var check_rad := 20.0
			if p_node != null and p_node.data != null:
				check_rad = p_node.data.planet_radius
				c_pos = p_node.global_position

			var L := c_pos - from
			var tca := L.dot(dir)
			var d2 := L.length_squared() - tca * tca
			if d2 <= check_rad * check_rad:
				var thc := sqrt(maxf(0.0, check_rad * check_rad - d2))
				var t0 := tca - thc
				var t1 := tca + thc
				var t_hit := t0 if t0 > 0.0 else t1
				if t_hit > 0.0 and t_hit < best_dist:
					best_dist = t_hit
					hit_obj = p_node if p_node != null else child
					hit_pt = from + dir * t_hit

		if hit_obj != null:
			select_object(hit_obj, hit_pt, -dir)
		else:
			# Clicked empty space: set focus point at default forward distance
			var free_point := from + dir * 60.0
			select_object(null, free_point, -dir)


func select_object(node: Node, pos: Vector3, normal: Vector3) -> void:
	_selected_node = node
	_selected_pos = pos
	_selected_normal = normal

	_reticle_node.visible = true
	_reticle_node.global_position = pos
	if normal.length_squared() > 0.001:
		_reticle_node.look_at(pos + normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT)

	# Update details in UI
	if node != null:
		var root_target := _find_representative_node(node)
		_target_name_label.text = "Target: %s" % root_target.name
		var details := "Class: %s\nPosition: (%.1f, %.1f, %.1f)\nDistance: %.1f m" % [
			root_target.get_class(), pos.x, pos.y, pos.z, _cam.global_position.distance_to(pos)
		]
		if root_target is LargeCraftGenerator:
			var lcg := root_target as LargeCraftGenerator
			var arch_name: String = LargeCraftGenerator.ARCHETYPE_NAMES.get(lcg.archetype, "Custom")
			details += "\nParts: %d · Archetype: %s" % [
				lcg.part_count(),
				arch_name
			]
		_target_detail_label.text = details
	else:
		_target_name_label.text = "Target: Space Coordinates"
		_target_detail_label.text = "Position: (%.1f, %.1f, %.1f)\nDistance: %.1f m\n(Click on any object to inspect)" % [
			pos.x, pos.y, pos.z, _cam.global_position.distance_to(pos)
		]


func _find_representative_node(node: Node) -> Node:
	var cur := node
	while cur != null and cur != _objects_root and cur != get_tree().root:
		if cur.get_parent() == _objects_root:
			return cur
		cur = cur.get_parent()
	return node


func frame_selected_target() -> void:
	if _selected_pos != Vector3.ZERO:
		_orbit_target = _selected_pos
		_orbit_dist = 60.0
		_free_pos = _selected_pos + Vector3(0.0, 20.0, 50.0)
		_free_yaw = 0.0
		_free_pitch = -18.0
		_update_camera_transform()


func toggle_camera_mode() -> void:
	if _cam_mode == CamMode.FREE_FLY:
		_cam_mode = CamMode.ORBIT
		_orbit_target = _selected_pos if _selected_pos != Vector3.ZERO else Vector3.ZERO
		_orbit_dist = maxf(_cam.global_position.distance_to(_orbit_target), 20.0)
		_cam_mode_btn.text = "Mode: Orbit (Target Focus)"
	else:
		_cam_mode = CamMode.FREE_FLY
		_free_pos = _cam.global_position
		_cam_mode_btn.text = "Mode: Free Fly (WASD+RMB)"


func delete_selected_target() -> void:
	if _selected_node != null and is_instance_valid(_selected_node):
		var rep := _find_representative_node(_selected_node)
		Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), _selected_pos), 2.0, Color.CYAN)
		Juice.light_pop(_selected_pos, Color.CYAN, 20.0, 0.3)
		rep.queue_free()
		_selected_node = null
		_reticle_node.visible = false
		_target_name_label.text = "Target: None"
		_target_detail_label.text = "Click any object in 3D scene"


# --- Effect Triggers (Explosions, Waves, Impacts, Destruction) ---------------

func get_action_pos() -> Vector3:
	if _has_action_override:
		return _action_override
	return _selected_pos if _reticle_node.visible else (_cam.global_position - _cam.global_transform.basis.z * 50.0)


# --- Effect Catalog & Comparison ---------------------------------------------

## Fill [member _effects] with every trigger the lab offers. One list drives the
## picker, the single-spawn button and the comparison row, so a new effect is
## added in exactly one place.
func _build_effect_catalog() -> void:
	_effects = [
		{"name": "Heavy Blast", "call": trigger_heavy_explosion, "centered": true, "sound": &"hit"},
		{"name": "Antimatter Core", "call": trigger_antimatter_core, "centered": true, "sound": &"warp"},
		{"name": "Plasma Fireball", "call": trigger_plasma_bomb, "centered": true, "sound": &"plasma"},
		{"name": "Cascade Detonation", "call": trigger_cascade_detonation, "centered": true, "sound": &"laser"},
		{"name": "Supernova Blast", "call": trigger_supernova, "centered": true, "sound": &"warp"},
		{"name": "Shockwave Ring", "call": trigger_shockwave_ring, "centered": true, "sound": &"alarm"},
		{"name": "Spherical Blast Wave", "call": trigger_spherical_blast_wave, "centered": true, "sound": &"hit"},
		{"name": "Gravity Implosion", "call": trigger_gravitational_implosion, "centered": true, "sound": &"ambience_blackhole"},
		{"name": "EMP Wave", "call": trigger_emp_wave, "centered": true, "sound": &"alarm"},
		{"name": "Shatter Radius", "call": trigger_shatter_radius, "centered": true, "sound": &"hit"},
		{"name": "Addon · Hit", "call": func(): _spawn_addon(AddonVfx.Kind.HIT), "centered": true, "sound": &"hit"},
		{"name": "Addon · Impact", "call": func(): _spawn_addon(AddonVfx.Kind.IMPACT), "centered": true, "sound": &"hit"},
		{"name": "Addon · Big Impact", "call": func(): _spawn_addon(AddonVfx.Kind.BIG_IMPACT), "centered": true, "sound": &"railgun"},
		{"name": "Addon · Explosion (air)", "call": func(): _spawn_addon(AddonVfx.Kind.EXPLOSION_AIR), "centered": true, "sound": &"railgun"},
		{"name": "Addon · Explosion (ground)", "call": func(): _spawn_addon(AddonVfx.Kind.EXPLOSION_GROUND), "centered": true, "sound": &"railgun"},
		{"name": "Addon · Nuke", "call": func(): _spawn_addon(AddonVfx.Kind.NUKE), "centered": true, "sound": &"jingle_lose"},
		{"name": "Addon · Electric Zap", "call": func(): _spawn_addon(AddonVfx.Kind.ZAP), "centered": true, "sound": &"hit"},
		{"name": "Addon · Ball Lightning", "call": func(): _spawn_addon(AddonVfx.Kind.BALL), "centered": true, "sound": &"hit"},
		{"name": "Hit Sprite Flash", "call": func(): AddonVfx.spawn_sprite_hit(_effects_root, get_action_pos(), Vector3.UP, maxf(1.0, blast_scale)), "centered": true, "sound": &""},
		{"name": "Spinal Railgun", "call": trigger_railgun_strike, "centered": false, "sound": &"railgun"},
		{"name": "Tachyon Lance", "call": trigger_thermal_lance, "centered": false, "sound": &"plasma"},
		{"name": "Meteor Slam", "call": trigger_meteor_strike, "centered": false, "sound": &"railgun"},
		{"name": "Missile Salvo", "call": trigger_missile_salvo, "centered": false, "sound": &"missile"},
		{"name": "Total Breakup", "call": trigger_total_breakup, "centered": true, "sound": &"railgun"},
		{"name": "Planet Annihilation", "call": trigger_planetary_annihilation, "centered": true, "sound": &"jingle_lose"},
	]


## Spawn the addon's [param kind] at the action point, sized by the blast scale.
func _spawn_addon(kind: int) -> void:
	AddonVfx.spawn(_effects_root, kind, get_action_pos(), Vector3.UP, maxf(0.6, blast_scale), Color("ffb347"))


## Run effect [param index] centred on [param pos] and play its sound. Everything
## the comparison machinery needs, in one place.
func spawn_effect_at(index: int, pos: Vector3) -> void:
	if index < 0 or index >= _effects.size():
		return
	var entry: Dictionary = _effects[index]
	_action_override = pos
	_has_action_override = true
	(entry["call"] as Callable).call()
	_has_action_override = false
	var sound: StringName = entry.get("sound", &"")
	if sound != &"":
		AddonVfx.play(sound, pos)


## Spawn the picker's current effect at the cursor / selected target.
func spawn_selected_effect() -> void:
	spawn_effect_at(_effect_picker.selected if _effect_picker != null else 0, get_action_pos())


## Lay every position-centred effect out in a row, evenly spaced, so they can be
## watched side by side from one camera position. Strikes that originate at the
## camera are skipped: they have no "there" to compare.
func compare_effects_row() -> void:
	var row: Array[Dictionary] = []
	for entry: Dictionary in _effects:
		if bool(entry.get("centered", false)):
			row.append(entry)
	if row.is_empty():
		return
	var origin := get_action_pos()
	# Lay the row across the camera's right vector so it reads as a line from
	# wherever the player is standing, not along a world axis they may be
	# looking down.
	var right := _cam.global_transform.basis.x.normalized() if _cam != null else Vector3.RIGHT
	var start := origin - right * (_spacing * float(row.size() - 1) * 0.5)
	for i in row.size():
		var p := start + right * (_spacing * float(i))
		# A small vertical jog so a tall fireball does not hide its neighbour.
		p.y += 6.0 if i % 2 == 1 else 0.0
		_action_override = p
		_has_action_override = true
		(row[i]["call"] as Callable).call()
		_has_action_override = false
		var sound: StringName = row[i].get("sound", &"")
		if sound != &"":
			AddonVfx.play(sound, p)
	# Point the reticle at the middle of the row so "Frame Selected" lands on it.
	select_object(null, origin, Vector3.UP)


## Re-skin every live object for the current look. Used by the toon toggle, which
## changes shading without rebuilding geometry.
func _restyle_all() -> void:
	LargeCraftGenerator.refresh_materials()
	for child in _objects_root.get_children():
		if child.has_method("restyle"):
			child.restyle()
		for sub in child.find_children("", "ShipView", true, false):
			if sub.has_method("restyle"):
				sub.restyle()


func trigger_heavy_explosion() -> void:
	var pos := get_action_pos()
	var col := Color(1.0, 0.6, 0.18)
	Juice.flash(col, 0.35, 0.9)
	Juice.shake(clampf(0.4 * blast_scale, 0.1, 1.0))
	Juice.light_pop(pos, col, 45.0 * blast_scale, 0.6)
	Juice.burst(BurstPresets.Preset.EMBERS, Transform3D(Basis(), pos), 2.0 * blast_scale, col)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), pos), 2.5 * blast_scale, Color.WHITE)

	_spawn_fireball_sphere(pos, 18.0 * blast_scale, col, 0.7)
	_apply_radial_physics_blast(pos, blast_radius * 1.5, blast_impulse * 1.5)
	_shatter_target_under_blast(pos, blast_radius)


func trigger_antimatter_core() -> void:
	var pos := get_action_pos()
	var col := Color(0.2, 0.9, 1.0)
	Juice.flash(Color.WHITE, 0.8, 1.4)
	Juice.shake(1.0)
	Juice.light_pop(pos, col, 120.0 * blast_scale, 1.2)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), pos), 4.0 * blast_scale, col)
	
	_spawn_quantum_bubble(pos, 35.0 * blast_scale, col, 1.4)
	_apply_radial_physics_blast(pos, blast_radius * 3.0, blast_impulse * 3.5)
	_shatter_target_under_blast(pos, blast_radius * 2.5)


func trigger_plasma_bomb() -> void:
	var pos := get_action_pos()
	var col := Color(0.9, 0.2, 1.0)
	Juice.flash(col, 0.45, 0.8)
	Juice.shake(0.6 * blast_scale)
	Juice.light_pop(pos, col, 60.0 * blast_scale, 0.8)
	Juice.burst(BurstPresets.Preset.EMBERS, Transform3D(Basis(), pos), 3.0 * blast_scale, col)
	
	_spawn_fireball_sphere(pos, 24.0 * blast_scale, col, 0.9)
	_apply_radial_physics_blast(pos, blast_radius * 2.0, blast_impulse * 2.0)
	_shatter_target_under_blast(pos, blast_radius * 1.6)


func trigger_cascade_detonation() -> void:
	var pos := get_action_pos()
	var count := 7
	for i in count:
		var delay := float(i) * 0.12
		var t := create_tween()
		t.tween_interval(delay)
		var offset := Vector3(randf_range(-12.0, 12.0), randf_range(-8.0, 8.0), randf_range(-12.0, 12.0)) * blast_scale
		t.tween_callback(func():
			var p := pos + offset
			var c := Color(1.0, randf_range(0.3, 0.8), 0.1)
			Juice.light_pop(p, c, 30.0 * blast_scale, 0.4)
			Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), p), 1.5 * blast_scale, c)
			Juice.shake(0.3)
			_spawn_fireball_sphere(p, 10.0 * blast_scale, c, 0.5)
			_apply_radial_physics_blast(p, blast_radius, blast_impulse * 0.8)
			_shatter_target_under_blast(p, blast_radius * 0.8)
		)


func trigger_supernova() -> void:
	var pos := get_action_pos()
	Juice.flash(Color.WHITE, 1.0, 2.5)
	Juice.shake(1.0)
	Juice.light_pop(pos, Color(1.0, 0.9, 0.6), 250.0, 2.2)
	_spawn_quantum_bubble(pos, 120.0 * blast_scale, Color(1.0, 0.8, 0.3), 2.2)
	_apply_radial_physics_blast(pos, blast_radius * 6.0, blast_impulse * 6.0)
	_shatter_target_under_blast(pos, blast_radius * 5.0)


func trigger_shockwave_ring() -> void:
	var pos := get_action_pos()
	var col := Color(0.3, 0.9, 1.0)
	Juice.ring(Transform3D(Basis(), pos), 40.0 * blast_scale, col, 0.8)
	Juice.light_pop(pos, col, 30.0, 0.4)
	Juice.shake(0.4)
	
	# Expanding 3D planar razor-thin wavefront ring mesh
	var ring_mesh := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 36
	tm.ring_segments = 16
	ring_mesh.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mesh.material_override = mat
	_effects_root.add_child(ring_mesh)
	ring_mesh.global_position = pos
	ring_mesh.scale = Vector3(0.01, 0.05, 0.01)
	
	var max_r := 80.0 * blast_scale
	var tw := ring_mesh.create_tween()
	tw.tween_property(ring_mesh, "scale", Vector3(max_r, clampf(max_r * 0.008, 0.05, 0.35), max_r), 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.tween_callback(ring_mesh.queue_free)
	
	_apply_radial_physics_blast(pos, max_r, blast_impulse * 1.8)


func trigger_spherical_blast_wave() -> void:
	var pos := get_action_pos()
	var col := Color(1.0, 0.45, 0.1)
	Juice.shake(0.5)
	Juice.light_pop(pos, col, 35.0, 0.5)
	_spawn_fireball_sphere(pos, 60.0 * blast_scale, col, 1.1)
	_apply_radial_physics_blast(pos, 70.0 * blast_scale, blast_impulse * 2.2)


func trigger_gravitational_implosion() -> void:
	var pos := get_action_pos()
	var col := Color(0.6, 0.1, 0.9)
	Juice.shake(0.4)
	Juice.flash(col, 0.2, 0.5)
	
	# Implosion sphere shrinking inward
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 40.0 * blast_scale
	sm.height = 80.0 * blast_scale
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.1, 0.8, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = mat
	_effects_root.add_child(sphere)
	sphere.global_position = pos
	
	# Sucks nearby bodies inward
	_pull_physics_inward(pos, 90.0 * blast_scale, blast_impulse * 2.0)
	
	var tw := sphere.create_tween()
	tw.tween_property(sphere, "scale", Vector3(0.05, 0.05, 0.05), 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		sphere.queue_free()
		# Rebound explosion
		trigger_antimatter_core()
	)


func trigger_emp_wave() -> void:
	var pos := get_action_pos()
	var col := Color(0.1, 0.95, 1.0)
	Juice.flash(col, 0.6, 0.8)
	Juice.shake(0.35)
	Juice.light_pop(pos, col, 50.0, 0.6)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), pos), 3.5, col)
	_spawn_quantum_bubble(pos, 45.0 * blast_scale, col, 0.7)


func trigger_railgun_strike() -> void:
	var from := _cam.global_position
	var target_pt := get_action_pos()
	var dir := (target_pt - from).normalized()
	
	# Tracer slug
	_spawn_tracer_line(from, target_pt + dir * 40.0, Color(0.85, 0.95, 1.0), 0.45)
	Juice.shake(0.65)
	Juice.flash(Color(0.8, 0.9, 1.0), 0.2, 0.4)
	Juice.light_pop(target_pt, Color(0.8, 0.9, 1.0), 40.0, 0.3)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), target_pt), 2.5, Color.WHITE)
	
	_apply_directional_impulse(target_pt, dir, blast_impulse * 3.0, blast_radius)
	_shatter_target_under_blast(target_pt, blast_radius * 1.4, dir * 60.0)


func trigger_thermal_lance() -> void:
	var from := _cam.global_position
	var target_pt := get_action_pos()
	var col := Color(1.0, 0.25, 0.35)
	
	# Continuous death ray lasting 1.8s
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	var dist := from.distance_to(target_pt)
	cyl.height = dist
	beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = mat
	_effects_root.add_child(beam)
	
	beam.global_position = from.lerp(target_pt, 0.5)
	if (target_pt - from).length_squared() > 0.001:
		beam.look_at(target_pt, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.5).set_delay(0.3)
	tw.tween_callback(beam.queue_free)
	
	Juice.shake(0.45)
	Juice.light_pop(target_pt, col, 35.0, 1.2)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), target_pt), 2.5, col)
	
	_shatter_target_under_blast(target_pt, blast_radius * 1.5, (target_pt - from).normalized() * 40.0)


func trigger_meteor_strike() -> void:
	var target_pt := get_action_pos()
	var spawn_pos := target_pt + Vector3(randf_range(-30.0, 30.0), 90.0, randf_range(-30.0, 30.0))
	var meteor := RigidBody3D.new()
	meteor.name = "IncomingMeteor"
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.5 * blast_scale
	sm.height = 9.0 * blast_scale
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.16, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 3.5
	mi.material_override = mat
	meteor.add_child(mi)
	
	var col_shape := CollisionShape3D.new()
	var sp_shape := SphereShape3D.new()
	sp_shape.radius = 4.5 * blast_scale
	col_shape.shape = sp_shape
	meteor.add_child(col_shape)
	
	_debris_root.add_child(meteor)
	meteor.global_position = spawn_pos
	var vel_dir := (target_pt - spawn_pos).normalized()
	meteor.linear_velocity = vel_dir * 320.0
	meteor.angular_velocity = Vector3(2.0, 3.0, 1.0)
	
	# Schedule detonation when near target
	var tw := create_tween()
	var travel_time := spawn_pos.distance_to(target_pt) / 320.0
	tw.tween_interval(travel_time)
	tw.tween_callback(func():
		if is_instance_valid(meteor):
			var imp_pos := meteor.global_position
			meteor.queue_free()
			trigger_heavy_explosion()
			_apply_directional_impulse(imp_pos, vel_dir, blast_impulse * 3.0, blast_radius * 2.0)
	)


func trigger_missile_salvo() -> void:
	var from := _cam.global_position
	var target_pt := get_action_pos()
	for i in 4:
		var delay := float(i) * 0.14
		var side := Vector3(-4.0 if i % 2 == 0 else 4.0, -2.0, 0.0)
		var m_spawn := from + _cam.global_transform.basis * side
		var t := create_tween()
		t.tween_interval(delay)
		t.tween_callback(func():
			_spawn_guided_missile(m_spawn, target_pt)
		)


func _spawn_guided_missile(from: Vector3, to: Vector3) -> void:
	var m := Node3D.new()
	var body_len := 2.2
	var nose_len := 0.8
	var r := 0.26

	# Fuselage
	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.9
	cyl.bottom_radius = r
	cyl.height = body_len
	cyl.radial_segments = 14
	body_mesh.mesh = cyl
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.25, 0.28, 0.3)
	body_mat.metallic = 0.8
	body_mat.roughness = 0.35
	body_mesh.material_override = body_mat
	body_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	body_mesh.position = Vector3(0.0, 0.0, nose_len * 0.4)
	m.add_child(body_mesh)

	# Pointed nose cone
	var nose_mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = r * 0.9
	cone.height = nose_len
	cone.radial_segments = 14
	nose_mesh.mesh = cone
	var nose_mat := StandardMaterial3D.new()
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nose_mat.albedo_color = Color(1.0, 0.6, 0.1)
	nose_mat.emission_enabled = true
	nose_mat.emission = Color(1.0, 0.5, 0.0)
	nose_mat.emission_energy_multiplier = 3.5
	nose_mesh.material_override = nose_mat
	nose_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	nose_mesh.position = Vector3(0.0, 0.0, -body_len * 0.5)
	m.add_child(nose_mesh)

	# 4 Delta fins
	for fin_idx in 4:
		var fin := MeshInstance3D.new()
		var fm := PrismMesh.new()
		fm.size = Vector3(r * 2.2, r * 0.15, 0.8)
		fin.mesh = fm
		fin.material_override = body_mat
		fin.rotation = Vector3(PI * 0.5, 0.0, float(fin_idx) * PI * 0.5)
		fin.position = Vector3(0.0, 0.0, 0.8)
		m.add_child(fin)

	# Glowing rocket engine exhaust
	var thruster := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = r * 0.6
	tm.bottom_radius = 0.0
	tm.height = 1.0
	thruster.mesh = tm
	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.albedo_color = Color(1.0, 0.65, 0.1)
	t_mat.emission_enabled = true
	t_mat.emission = Color(1.0, 0.5, 0.0)
	t_mat.emission_energy_multiplier = 5.0
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	thruster.material_override = t_mat
	thruster.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	thruster.position = Vector3(0.0, 0.0, body_len * 0.5 + 0.5)
	m.add_child(thruster)

	_effects_root.add_child(m)
	m.global_position = from
	
	var dur := 0.65
	var tw := m.create_tween()
	var mid := from.lerp(to, 0.5) + Vector3(randf_range(-10.0, 10.0), randf_range(5.0, 15.0), 0.0)
	tw.tween_method(func(pct: float):
		var p := from.bezier_interpolate(mid, mid, to, pct)
		m.global_position = p
		m.look_at(to, Vector3.UP)
		if randf() < 0.4:
			Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), p), 0.3, Color(1.0, 0.55, 0.1))
	, 0.0, 1.0, dur)
	tw.tween_callback(func():
		m.queue_free()
		Juice.light_pop(to, Color(1.0, 0.5, 0.1), 25.0, 0.3)
		Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), to), 1.8, Color(1.0, 0.6, 0.1))
		Juice.shake(0.25)
		_apply_radial_physics_blast(to, 15.0, blast_impulse * 0.8)
		_shatter_target_under_blast(to, 12.0)
	)


func trigger_shatter_radius() -> void:
	var pos := get_action_pos()
	Juice.shake(0.5)
	Juice.light_pop(pos, Color(1.0, 0.7, 0.2), 35.0, 0.4)
	Juice.burst(BurstPresets.Preset.SPARKS, Transform3D(Basis(), pos), 2.0, Color.WHITE)
	_apply_radial_physics_blast(pos, blast_radius * 1.5, blast_impulse * 1.8)
	_shatter_target_under_blast(pos, blast_radius * 1.5)


func trigger_total_breakup() -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		trigger_heavy_explosion()
		return
	
	var rep := _find_representative_node(_selected_node)
	var pos := (rep as Node3D).global_position if rep is Node3D else _selected_pos
	
	if rep is LargeCraftGenerator:
		var gen := rep as LargeCraftGenerator
		gen.shatter_at(pos, 250.0, Vector3.UP * 30.0)
		Juice.flash(Color(1.0, 0.7, 0.3), 0.5, 1.2)
		Juice.shake(0.8)
	elif rep is Planet:
		trigger_planetary_annihilation()
	else:
		# Generic destruction: burst into debris boxes
		for i in 14:
			_spawn_tumbling_debris_piece(pos, randf_range(2.0, 6.0))
		Juice.flash(Color.WHITE, 0.4, 0.8)
		Juice.shake(0.7)
		rep.queue_free()
		_selected_node = null
		_reticle_node.visible = false


func trigger_planetary_annihilation() -> void:
	var pos := get_action_pos()
	var planet: Planet = null
	if is_instance_valid(_selected_node) and _selected_node is Planet:
		planet = _selected_node as Planet
	elif is_instance_valid(_selected_node):
		var sub := _selected_node.find_children("", "Planet", true, false)
		if not sub.is_empty() and is_instance_valid(sub[0]):
			planet = sub[0] as Planet
	if planet == null:
		for child in _objects_root.get_children():
			if not is_instance_valid(child):
				continue
			if child is Planet:
				planet = child as Planet
				pos = planet.global_position
				break
			var sub2 := child.find_children("", "Planet", true, false)
			if not sub2.is_empty() and is_instance_valid(sub2[0]):
				planet = sub2[0] as Planet
				pos = planet.global_position
				break

	if planet != null:
		pos = planet.global_position

	Juice.flash(Color(1.0, 0.95, 0.85), 1.0, 3.5)
	Juice.shake(1.0)
	Juice.light_pop(pos, Color(1.0, 0.55, 0.15), 350.0, 3.5)

	# Multilayer expanding physical shockwave pushing all objects, ships and debris
	PhysicalShockwave.create(_effects_root, pos, 600.0, 750.0, 18.0, 350.0, Color(1.0, 0.65, 0.25), 3.0)

	_spawn_fireball_sphere(pos, 80.0, Color(1.0, 0.5, 0.1), 1.6)

	# Spawn curved irregular crust plates textured with the planet's surface shader + large asteroids + core remnant
	if planet != null and is_instance_valid(planet):
		PlanetDebrisBuilder.shatter_planet(planet, pos, _debris_root, 280.0)
		planet.visible = false
		for child in planet.get_children():
			if child is Node3D:
				child.visible = false
		planet.queue_free()


	if not is_instance_valid(_selected_node) or _selected_node == planet:
		_selected_node = null
		_reticle_node.visible = false
		_target_name_label.text = "Target: Obliterated"
		_target_detail_label.text = "Planet was annihilated into planetary debris"


# --- Physics Interaction Helpers ----------------------------------------------

func _apply_radial_physics_blast(epicentre: Vector3, radius: float, max_impulse: float) -> void:
	for child in _debris_root.get_children():
		if child is RigidBody3D:
			var rb := child as RigidBody3D
			var diff := rb.global_position - epicentre
			var dist := diff.length()
			if dist <= radius and dist > 0.01:
				var dir := diff / dist
				var falloff := 1.0 - (dist / radius)
				rb.apply_central_impulse(dir * (max_impulse * falloff))
				rb.apply_torque_impulse(Vector3(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)) * falloff)


func _pull_physics_inward(epicentre: Vector3, radius: float, max_impulse: float) -> void:
	for child in _debris_root.get_children():
		if child is RigidBody3D:
			var rb := child as RigidBody3D
			var diff := epicentre - rb.global_position
			var dist := diff.length()
			if dist <= radius and dist > 0.01:
				var dir := diff / dist
				var falloff := 1.0 - (dist / radius)
				rb.apply_central_impulse(dir * (max_impulse * falloff))


func _apply_directional_impulse(epicentre: Vector3, dir: Vector3, impulse_mag: float, radius: float) -> void:
	for child in _debris_root.get_children():
		if child is RigidBody3D:
			var rb := child as RigidBody3D
			var dist := rb.global_position.distance_to(epicentre)
			if dist <= radius:
				var falloff := 1.0 - (dist / radius)
				rb.apply_central_impulse(dir * (impulse_mag * falloff))


func _shatter_target_under_blast(epicentre: Vector3, radius: float, impulse := Vector3.ZERO) -> void:
	for child in _objects_root.get_children():
		if child is LargeCraftGenerator:
			var gen := child as LargeCraftGenerator
			var detached := gen.shatter_at(epicentre, radius, impulse)
			for rb in detached:
				if rb.get_parent() != null:
					rb.get_parent().remove_child(rb)
				_debris_root.add_child(rb)
		elif child is Planet:
			var pl := child as Planet
			var p_rad: float = pl.data.planet_radius if pl.data != null else 45.0
			if pl.global_position.distance_to(epicentre) <= p_rad + radius:
				var cur_hp: float = pl.get_meta("hp", 800.0) - radius * 15.0
				pl.set_meta("hp", cur_hp)
				if cur_hp <= 0.0:
					trigger_planetary_annihilation()


func _spawn_fireball_sphere(pos: Vector3, target_radius: float, color: Color, life: float) -> void:
	# Planar luminous shockwave ring
	Juice.ring(Transform3D(Basis(), pos), target_radius * 1.6, color, life * 0.75)

	# Superheated inner core
	var mesh_inst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 10
	mesh_inst.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_inst.material_override = mat
	_effects_root.add_child(mesh_inst)
	mesh_inst.global_position = pos

	# Outer corona shell
	var corona := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 1.35
	cs.height = 2.7
	cs.radial_segments = 14
	cs.rings = 8
	corona.mesh = cs
	var c_mat := StandardMaterial3D.new()
	c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	c_mat.emission_enabled = true
	c_mat.emission = color
	c_mat.emission_energy_multiplier = 3.5
	c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	corona.material_override = c_mat
	mesh_inst.add_child(corona)

	var tw := mesh_inst.create_tween()
	tw.tween_property(mesh_inst, "scale", Vector3.ONE * target_radius, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(c_mat, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(mesh_inst.queue_free)


func _spawn_quantum_bubble(pos: Vector3, target_radius: float, color: Color, life: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mesh_inst.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_inst.material_override = mat
	_effects_root.add_child(mesh_inst)
	mesh_inst.global_position = pos

	var tw := mesh_inst.create_tween()
	tw.tween_property(mesh_inst, "scale", Vector3.ONE * target_radius, life * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(mesh_inst.queue_free)


func _spawn_tracer_line(from: Vector3, to: Vector3, color: Color, thickness: float) -> void:
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = thickness
	cm.bottom_radius = thickness
	var dist := from.distance_to(to)
	cm.height = dist
	cyl.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material_override = mat
	_effects_root.add_child(cyl)
	cyl.global_position = from.lerp(to, 0.5)
	if (to - from).length_squared() > 0.001:
		cyl.look_at(to, Vector3.UP)
		cyl.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tw := cyl.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(cyl.queue_free)


func _spawn_tumbling_debris_piece(pos: Vector3, sz: float) -> void:
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sz, sz * randf_range(0.5, 1.5), sz * randf_range(0.5, 1.5))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(randf_range(0.2, 0.4), randf_range(0.2, 0.4), randf_range(0.2, 0.4))
	mi.material_override = mat
	rb.add_child(mi)
	
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	rb.add_child(cs)
	
	_debris_root.add_child(rb)
	rb.global_position = pos + Vector3(randf_range(-sz, sz), randf_range(-sz, sz), randf_range(-sz, sz))
	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	rb.linear_velocity = dir * randf_range(20.0, 120.0)
	rb.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))


# --- Spawner Functions --------------------------------------------------------

func _spawn_mega_ship(archetype: int, pos: Vector3) -> LargeCraftGenerator:
	var gen := LargeCraftGenerator.new()
	gen.name = "MegaShip_%d" % _objects_root.get_child_count()
	gen.archetype = archetype
	_objects_root.add_child(gen)
	gen.global_position = pos
	gen.generate()
	select_object(gen, pos, Vector3.UP)
	return gen


func _spawn_fighter_ship(pos: Vector3) -> Node3D:
	var lib := PartLibrary.instance()
	lib.load_all()
	var design: ShipDesign
	if not lib.presets.is_empty():
		var pick: Dictionary = lib.presets[randi() % lib.presets.size()]
		design = lib.build_preset_design(String(pick.get("id", "")))
	if design == null:
		design = lib.default_design()
		lib.autofill_required(design)
	var view := ShipAssembler.assemble(design, lib, 0.0, false, false)
	view.root.name = "FighterShip_%d" % _objects_root.get_child_count()
	
	var rb := RigidBody3D.new()
	rb.name = "FighterRigidBody_%d" % _objects_root.get_child_count()
	rb.add_child(view.root)
	
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(8.0, 4.0, 12.0)
	cs.shape = bs
	rb.add_child(cs)
	
	_objects_root.add_child(rb)
	rb.global_position = pos
	select_object(rb, pos, Vector3.UP)
	return rb


func _spawn_planet_target(pos: Vector3) -> Planet:
	var p := Planet.new()
	p.name = "Planet_%d" % _objects_root.get_child_count()
	p.sun_direction = Vector3(0.5, 0.3, 0.8).normalized()
	var pdata := PlanetData.new()
	pdata.planet_name = "Tartarus V"
	pdata.planet_radius = 45.0
	pdata.atmosphere_density = 0.5
	pdata.atmosphere_color = Color(0.2, 0.6, 1.0)
	pdata.ring_enabled = true
	pdata.ring_inner_radius = 60.0
	pdata.ring_outer_radius = 110.0
	p.configure(pdata)
	_objects_root.add_child(p)
	p.global_position = pos
	select_object(p, pos, Vector3.UP)
	return p


func _spawn_asteroid_cluster(pos: Vector3, count := 10) -> void:
	for i in count:
		var rock := RigidBody3D.new()
		rock.name = "Asteroid_%d" % _debris_root.get_child_count()
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(2.0, 7.5)
		sm.radius = r
		sm.height = r * 2.0
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.25, 0.45), randf_range(0.22, 0.4), randf_range(0.2, 0.35))
		mat.roughness = 0.95
		mi.material_override = mat
		rock.add_child(mi)

		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = r
		cs.shape = ss
		rock.add_child(cs)

		_debris_root.add_child(rock)
		var offset := Vector3(randf_range(-15.0, 15.0), randf_range(-10.0, 10.0), randf_range(-15.0, 15.0))
		rock.global_position = pos + offset
		rock.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))


func _spawn_fuel_tanks(pos: Vector3) -> void:
	for x in 3:
		for y in 2:
			for z in 2:
				var tank := RigidBody3D.new()
				tank.name = "FuelTank_%d_%d_%d" % [x, y, z]
				var mi := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 1.6
				cyl.bottom_radius = 1.6
				cyl.height = 4.2
				mi.mesh = cyl
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color("d93b2b")
				mat.metallic = 0.7
				mat.roughness = 0.3
				mi.material_override = mat
				tank.add_child(mi)

				var cs := CollisionShape3D.new()
				var cys := CylinderShape3D.new()
				cys.radius = 1.6
				cys.height = 4.2
				cs.shape = cys
				tank.add_child(cs)

				_debris_root.add_child(tank)
				tank.global_position = pos + Vector3(float(x) * 4.0, float(y) * 4.6, float(z) * 4.0)


func clear_all_debris() -> void:
	for child in _debris_root.get_children():
		_debris_root.remove_child(child)
		child.queue_free()
	for child in _effects_root.get_children():
		_effects_root.remove_child(child)
		child.queue_free()


func reset_scene() -> void:
	clear_all_debris()
	for child in _objects_root.get_children():
		_objects_root.remove_child(child)
		child.queue_free()
	_selected_node = null
	_reticle_node.visible = false
	_spawn_mega_ship(LargeCraftGenerator.Archetype.DREADNOUGHT, Vector3.ZERO)


# --- User Interface Construction ---------------------------------------------

func _build_ui() -> void:
	_ui_root = Control.new()
	_ui_root.name = "UI"
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	_build_top_bar()
	_build_left_sidebar()
	_build_right_sidebar()
	_build_bottom_bar()
	_build_explosion_studio()


func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.name = "TopBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ui_root.add_child(top)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	top.add_child(hbox)

	var back_btn := Button.new()
	back_btn.text = "⮜ Launcher"
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://modules/core/core.tscn"))
	hbox.add_child(back_btn)

	var title := Label.new()
	title.text = "💥 DESTRUCTION & EFFECTS LAB"
	title.add_theme_color_override("font_color", BuilderTheme.accent())
	title.add_theme_font_size_override("font_size", 16)
	hbox.add_child(title)

	hbox.add_child(_make_vseparator())

	_cam_mode_btn = Button.new()
	_cam_mode_btn.text = "Mode: Free Fly (WASD+RMB)"
	_cam_mode_btn.pressed.connect(toggle_camera_mode)
	hbox.add_child(_cam_mode_btn)

	var frame_btn := Button.new()
	frame_btn.text = "Frame Selected (F)"
	frame_btn.pressed.connect(frame_selected_target)
	hbox.add_child(frame_btn)

	hbox.add_child(_make_vseparator())

	var time_lbl := Label.new()
	time_lbl.text = "Time:"
	hbox.add_child(time_lbl)

	_time_btn_1 = Button.new()
	_time_btn_1.text = "1.0×"
	_time_btn_1.pressed.connect(func(): _set_time_scale(1.0))
	hbox.add_child(_time_btn_1)

	_time_btn_half = Button.new()
	_time_btn_half.text = "0.5×"
	_time_btn_half.pressed.connect(func(): _set_time_scale(0.5))
	hbox.add_child(_time_btn_half)

	_time_btn_slow = Button.new()
	_time_btn_slow.text = "0.1× Matrix"
	_time_btn_slow.pressed.connect(func(): _set_time_scale(0.1))
	hbox.add_child(_time_btn_slow)

	_time_btn_pause = Button.new()
	_time_btn_pause.text = "Pause"
	_time_btn_pause.pressed.connect(func(): _set_time_scale(0.0001 if time_scale > 0.001 else 1.0))
	hbox.add_child(_time_btn_pause)

	hbox.add_child(_make_vseparator())

	var clear_btn := Button.new()
	clear_btn.text = "Clear Debris"
	clear_btn.pressed.connect(clear_all_debris)
	hbox.add_child(clear_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Scene (R)"
	reset_btn.pressed.connect(reset_scene)
	hbox.add_child(reset_btn)

	hbox.add_child(_make_vseparator())

	var studio_btn := Button.new()
	studio_btn.text = "🎨 EXPLOSION STUDIO"
	studio_btn.tooltip_text = "Open explosion recipe editor to assign effects to slots and save configuration"
	studio_btn.add_theme_color_override("font_color", Color("ffd044"))
	studio_btn.pressed.connect(toggle_explosion_studio)
	hbox.add_child(studio_btn)


func _build_left_sidebar() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_top = 46.0
	scroll.offset_bottom = -34.0
	scroll.offset_right = 210.0
	_ui_root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var sp_lbl := Label.new()
	sp_lbl.text = "SPAWN TARGETS"
	sp_lbl.add_theme_color_override("font_color", BuilderTheme.good())
	vbox.add_child(sp_lbl)

	vbox.add_child(_make_spawn_btn("🚀 Dreadnought", func():
		_spawn_mega_ship(LargeCraftGenerator.Archetype.DREADNOUGHT, _get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("🛸 Mothership", func():
		_spawn_mega_ship(LargeCraftGenerator.Archetype.MOTHERSHIP, _get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("🛰 Ring Station", func():
		_spawn_mega_ship(LargeCraftGenerator.Archetype.RING_STATION, _get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("⛩ Gate Frame", func():
		_spawn_mega_ship(LargeCraftGenerator.Archetype.GATE_FRAME, _get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("🏢 Tower Cluster", func():
		_spawn_mega_ship(LargeCraftGenerator.Archetype.TOWER_CLUSTER, _get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("⚔ Fighter Ship", func():
		_spawn_fighter_ship(_get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("🪐 Celestial Planet", func():
		_spawn_planet_target(_get_spawn_pos())
	))
	vbox.add_child(_make_spawn_btn("☄ Asteroid Field", func():
		_spawn_asteroid_cluster(_get_spawn_pos(), 14)
	))
	vbox.add_child(_make_spawn_btn("🛢 Fuel Tank Stack", func():
		_spawn_fuel_tanks(_get_spawn_pos())
	))

	vbox.add_child(_make_hseparator())

	var fx_lbl := Label.new()
	fx_lbl.text = "FX TUNING"
	fx_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(fx_lbl)

	vbox.add_child(_make_slider_row(vbox, "Scale", 0.4, 3.0, blast_scale, func(v): blast_scale = v))
	vbox.add_child(_make_slider_row(vbox, "Impulse", 10.0, 300.0, blast_impulse, func(v): blast_impulse = v))
	vbox.add_child(_make_slider_row(vbox, "Radius", 10.0, 100.0, blast_radius, func(v): blast_radius = v))

	vbox.add_child(_make_hseparator())

	# Compare: pick one effect and drop it on the target, or lay every
	# position-centred effect out in a row and watch them side by side.
	var cmp_lbl := Label.new()
	cmp_lbl.text = "🧪 COMPARE EFFECTS"
	cmp_lbl.add_theme_color_override("font_color", Color("b58cff"))
	vbox.add_child(cmp_lbl)

	_effect_picker = OptionButton.new()
	_effect_picker.tooltip_text = "Pick an effect, then spawn it at the selected target"
	for entry: Dictionary in _effects:
		_effect_picker.add_item(String(entry["name"]))
	vbox.add_child(_effect_picker)

	var spawn_sel := Button.new()
	spawn_sel.text = "Spawn Selected at Target (C)"
	spawn_sel.pressed.connect(spawn_selected_effect)
	vbox.add_child(spawn_sel)

	var row_btn := Button.new()
	row_btn.text = "Compare Row — all at once (V)"
	row_btn.tooltip_text = "Spawn every centred effect in a line, spaced by the slider"
	row_btn.pressed.connect(compare_effects_row)
	vbox.add_child(row_btn)

	vbox.add_child(_make_slider_row(vbox, "Row spacing", 10.0, 160.0, _spacing, func(v): _spacing = v))

	vbox.add_child(_make_hseparator())

	# Layer switches: the whole point is to flip each on and off while watching
	# the same effect, so every one of these is a single checkbox with no
	# restart required.
	var lay_lbl := Label.new()
	lay_lbl.text = "🎚 LAYERS (A/B)"
	lay_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(lay_lbl)

	vbox.add_child(_make_toggle_row("Sci-Fi library sounds", FxSettings.library_sounds, func(on: bool):
		FxSettings.set_library_sounds(on)
	))
	vbox.add_child(_make_toggle_row("BinbunVFX addon effects", FxSettings.addon_vfx, func(on: bool):
		FxSettings.set_addon_vfx(on)
	))
	vbox.add_child(_make_toggle_row("Sprite hit flash", FxSettings.sprite_hits, func(on: bool):
		FxSettings.set_sprite_hits(on)
	))
	vbox.add_child(_make_toggle_row("Toon shading (all elements)", ToonOverride.enabled(), func(on: bool):
		ToonOverride.set_enabled(on)
		_restyle_all()
	))


func _build_right_sidebar() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_top = 46.0
	scroll.offset_bottom = -34.0
	scroll.offset_left = -230.0
	_ui_root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_target_name_label = Label.new()
	_target_name_label.text = "Target: MegaShip_0"
	_target_name_label.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(_target_name_label)

	_target_detail_label = Label.new()
	_target_detail_label.text = "Click any object in 3D scene"
	_target_detail_label.add_theme_font_size_override("font_size", 11)
	_target_detail_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(_target_detail_label)

	var del_btn := Button.new()
	del_btn.text = "Delete Target (Del)"
	del_btn.pressed.connect(delete_selected_target)
	vbox.add_child(del_btn)

	vbox.add_child(_make_hseparator())

	# Explosions Section
	var exp_lbl := Label.new()
	exp_lbl.text = "💥 EXPLOSIONS"
	exp_lbl.add_theme_color_override("font_color", Color("ff9944"))
	vbox.add_child(exp_lbl)

	vbox.add_child(_make_fx_btn("Heavy Blast (1)", trigger_heavy_explosion))
	vbox.add_child(_make_fx_btn("Antimatter Core (5)", trigger_antimatter_core))
	vbox.add_child(_make_fx_btn("Plasma Fireball", trigger_plasma_bomb))
	vbox.add_child(_make_fx_btn("Cascade Detonation", trigger_cascade_detonation))
	vbox.add_child(_make_fx_btn("Supernova Blast", trigger_supernova))

	vbox.add_child(_make_hseparator())

	# Waves Section
	var wave_lbl := Label.new()
	wave_lbl.text = "🌊 WAVES & PULSES"
	wave_lbl.add_theme_color_override("font_color", Color("44ddff"))
	vbox.add_child(wave_lbl)

	vbox.add_child(_make_fx_btn("Shockwave Ring (2)", trigger_shockwave_ring))
	vbox.add_child(_make_fx_btn("Spherical Blast Wave", trigger_spherical_blast_wave))
	vbox.add_child(_make_fx_btn("Gravity Implosion", trigger_gravitational_implosion))
	vbox.add_child(_make_fx_btn("EMP Distortion Wave", trigger_emp_wave))

	vbox.add_child(_make_hseparator())

	# Impacts Section
	var imp_lbl := Label.new()
	imp_lbl.text = "🎯 IMPACTS & STRIKES"
	imp_lbl.add_theme_color_override("font_color", Color("ffdd44"))
	vbox.add_child(imp_lbl)

	vbox.add_child(_make_fx_btn("Spinal Railgun (3)", trigger_railgun_strike))
	vbox.add_child(_make_fx_btn("Tachyon Lance Beam", trigger_thermal_lance))
	vbox.add_child(_make_fx_btn("Meteor Slam Strike", trigger_meteor_strike))
	vbox.add_child(_make_fx_btn("Missile Salvo", trigger_missile_salvo))

	vbox.add_child(_make_hseparator())

	# Destruction Section
	var des_lbl := Label.new()
	des_lbl.text = "🔨 DESTRUCTION"
	des_lbl.add_theme_color_override("font_color", Color("ff4455"))
	vbox.add_child(des_lbl)

	vbox.add_child(_make_fx_btn("Shatter Radius (4)", trigger_shatter_radius))
	vbox.add_child(_make_fx_btn("Total Breakup (6)", trigger_total_breakup))
	vbox.add_child(_make_fx_btn("Planet Annihilation", trigger_planetary_annihilation))


func _build_bottom_bar() -> void:
	var bottom := PanelContainer.new()
	bottom.name = "BottomBar"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ui_root.add_child(bottom)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	bottom.add_child(hbox)

	var hint := Label.new()
	hint.text = "Left Click: Select & Target • Right Drag: Look • WASD/QE: Fly • Shift: Sprint • Wheel: Speed/Zoom"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", BuilderTheme.text_dim())
	hbox.add_child(hint)

	_stats_label = Label.new()
	_stats_label.text = "FPS: 60 · Objects: 1 · Debris: 0"
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", BuilderTheme.good())
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_stats_label)


func _update_stats_label() -> void:
	if _stats_label != null:
		var fps := Engine.get_frames_per_second()
		var obj_count := _objects_root.get_child_count()
		var deb_count := _debris_root.get_child_count()
		_stats_label.text = "FPS: %d · Targets: %d · Physics Debris: %d · Fly Speed: %.0f m/s" % [
			fps, obj_count, deb_count, _free_speed
		]


func _set_time_scale(scale: float) -> void:
	time_scale = scale
	Engine.time_scale = scale


func _get_spawn_pos() -> Vector3:
	return _cam.global_position - _cam.global_transform.basis.z * 55.0


func _make_spawn_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _make_fx_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _make_toggle_row(text: String, initial: bool, cb: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = initial
	box.add_theme_font_size_override("font_size", 11)
	box.toggled.connect(cb)
	return box


func _make_slider_row(parent: Control, title: String, min_v: float, max_v: float, initial: float, cb: Callable) -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s: %.1f" % [title, initial]
	lbl.add_theme_font_size_override("font_size", 11)
	box.add_child(lbl)
	
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = (max_v - min_v) / 40.0
	sl.value = initial
	sl.value_changed.connect(func(v: float):
		lbl.text = "%s: %.1f" % [title, v]
		cb.call(v)
	)
	box.add_child(sl)
	return box


func _make_vseparator() -> VSeparator:
	return VSeparator.new()


func _make_hseparator() -> HSeparator:
	return HSeparator.new()


# --- Explosion Studio Modal & Assignment System ------------------------------

func toggle_explosion_studio() -> void:
	if _studio_modal == null:
		return
	_studio_modal.visible = not _studio_modal.visible
	if _studio_modal.visible:
		_studio_modal.move_to_front()
		_refresh_studio_fields()


func _build_explosion_studio() -> void:
	ExplosionRegistry.ensure_initialized()
	
	_studio_modal = PanelContainer.new()
	_studio_modal.name = "ExplosionStudioModal"
	_studio_modal.set_anchors_preset(Control.PRESET_CENTER)
	_studio_modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_studio_modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_studio_modal.custom_minimum_size = Vector2(620, 520)
	_studio_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_studio_modal.visible = false
	_ui_root.add_child(_studio_modal)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0d111aee")
	sb.border_color = Color("ffd044")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0.9, 0.6, 0.1, 0.3)
	sb.shadow_size = 18
	_studio_modal.add_theme_stylebox_override("panel", sb)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_studio_modal.add_child(main_vbox)

	# Header bar
	var header := HBoxContainer.new()
	var h_title := Label.new()
	h_title.text = "🎨 EXPLOSION STUDIO · EFFECT ASSIGNMENT & TUNING"
	h_title.add_theme_font_size_override("font_size", 14)
	h_title.add_theme_color_override("font_color", Color("ffd044"))
	header.add_child(h_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.pressed.connect(func(): _studio_modal.visible = false)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	var desc := Label.new()
	desc.text = "Configure which visual explosion asset or procedural recipe maps to each game destruction event."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", BuilderTheme.text_dim())
	main_vbox.add_child(desc)

	main_vbox.add_child(_make_hseparator())

	# Form grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	main_vbox.add_child(grid)

	# 1. Event Slot Picker
	var slot_lbl := Label.new()
	slot_lbl.text = "Game Event Slot:"
	grid.add_child(slot_lbl)

	_studio_slot_picker = OptionButton.new()
	for slot in ExplosionRegistry.ALL_SLOTS:
		var meta: Dictionary = ExplosionRegistry.SLOT_META.get(slot, {})
		_studio_slot_picker.add_item("%s (%s)" % [meta.get("name", slot), slot])
	_studio_slot_picker.item_selected.connect(func(_idx): _on_studio_slot_selected())
	grid.add_child(_studio_slot_picker)

	# 2. Assigned Effect Picker
	var fx_lbl := Label.new()
	fx_lbl.text = "Assigned Effect / Asset:"
	grid.add_child(fx_lbl)

	_studio_effect_picker = OptionButton.new()
	for eff_id in ExplosionRegistry.get_effect_ids():
		var eff_def: Dictionary = ExplosionRegistry.get_effect(eff_id)
		_studio_effect_picker.add_item("%s [%s]" % [eff_def.get("name", eff_id), eff_def.get("pack", "Juice")])
	_studio_effect_picker.item_selected.connect(func(_idx): _on_studio_effect_changed())
	grid.add_child(_studio_effect_picker)

	# 3. Origin Pack & Description
	var orig_lbl := Label.new()
	orig_lbl.text = "Origin Asset Pack:"
	grid.add_child(orig_lbl)

	_studio_origin_label = Label.new()
	_studio_origin_label.text = "BinbunVFX Vol 2"
	_studio_origin_label.add_theme_font_size_override("font_size", 11)
	_studio_origin_label.add_theme_color_override("font_color", BuilderTheme.accent())
	grid.add_child(_studio_origin_label)

	var d_lbl := Label.new()
	d_lbl.text = "Effect Details:"
	grid.add_child(d_lbl)

	_studio_desc_label = Label.new()
	_studio_desc_label.text = "Volumetric expanding fireball"
	_studio_desc_label.add_theme_font_size_override("font_size", 11)
	_studio_desc_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_studio_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_studio_desc_label.custom_minimum_size = Vector2(360, 0)
	grid.add_child(_studio_desc_label)

	# 4. Scale Slider
	var scale_title := Label.new()
	scale_title.text = "Scale Multiplier:"
	grid.add_child(scale_title)

	var scale_box := HBoxContainer.new()
	_studio_scale_slider = HSlider.new()
	_studio_scale_slider.min_value = 0.4
	_studio_scale_slider.max_value = 6.0
	_studio_scale_slider.step = 0.1
	_studio_scale_slider.value = 1.0
	_studio_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_studio_scale_slider.value_changed.connect(_on_studio_scale_changed)
	scale_box.add_child(_studio_scale_slider)

	_studio_scale_lbl = Label.new()
	_studio_scale_lbl.text = "1.0×"
	_studio_scale_lbl.custom_minimum_size = Vector2(40, 0)
	scale_box.add_child(_studio_scale_lbl)
	grid.add_child(scale_box)

	# 5. Sound Picker
	var sound_title := Label.new()
	sound_title.text = "Impact SFX Sound:"
	grid.add_child(sound_title)

	_studio_sound_picker = OptionButton.new()
	var sound_list := ["hit", "railgun", "missile", "plasma", "jingle_lose", "warp", "alarm", "ambience_blackhole", "laser", "shield_recharge"]
	for s in sound_list:
		_studio_sound_picker.add_item(s)
	_studio_sound_picker.item_selected.connect(_on_studio_sound_changed)
	grid.add_child(_studio_sound_picker)

	# 6. Options: Shockwave & Debris
	var opts_title := Label.new()
	opts_title.text = "Secondary Layers:"
	grid.add_child(opts_title)

	var opts_box := HBoxContainer.new()
	opts_box.add_theme_constant_override("separation", 16)
	_studio_shockwave_check = CheckBox.new()
	_studio_shockwave_check.text = "Shockwave Ring"
	_studio_shockwave_check.button_pressed = true
	_studio_shockwave_check.toggled.connect(func(on: bool):
		_save_current_field("shockwave", on)
	)
	opts_box.add_child(_studio_shockwave_check)

	_studio_debris_check = CheckBox.new()
	_studio_debris_check.text = "Flying Debris Shards"
	_studio_debris_check.button_pressed = true
	_studio_debris_check.toggled.connect(func(on: bool):
		_save_current_field("debris", on)
	)
	opts_box.add_child(_studio_debris_check)
	grid.add_child(opts_box)

	# 7. Screen Shake Slider
	var shake_title := Label.new()
	shake_title.text = "Camera Shake:"
	grid.add_child(shake_title)

	var shake_box := HBoxContainer.new()
	_studio_shake_slider = HSlider.new()
	_studio_shake_slider.min_value = 0.0
	_studio_shake_slider.max_value = 1.5
	_studio_shake_slider.step = 0.05
	_studio_shake_slider.value = 0.4
	_studio_shake_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_studio_shake_slider.value_changed.connect(_on_studio_shake_changed)
	shake_box.add_child(_studio_shake_slider)

	_studio_shake_lbl = Label.new()
	_studio_shake_lbl.text = "0.4"
	_studio_shake_lbl.custom_minimum_size = Vector2(40, 0)
	shake_box.add_child(_studio_shake_lbl)
	grid.add_child(shake_box)

	main_vbox.add_child(_make_hseparator())

	# Action and Preset Buttons
	var action_box := HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 10)
	main_vbox.add_child(action_box)

	var test_btn := Button.new()
	test_btn.text = "💥 Test Detonate at Target"
	test_btn.add_theme_color_override("font_color", Color("ffd044"))
	test_btn.pressed.connect(_test_detonate_current_slot)
	action_box.add_child(test_btn)

	var save_btn := Button.new()
	save_btn.text = "💾 Save Assignments (Disk)"
	save_btn.add_theme_color_override("font_color", BuilderTheme.good())
	save_btn.pressed.connect(_save_assignments_to_disk)
	action_box.add_child(save_btn)

	action_box.add_child(_make_vseparator())

	var preset_picker := OptionButton.new()
	preset_picker.add_item("Load Template Preset...")
	preset_picker.add_item("Default Mixed")
	preset_picker.add_item("Retro Vector Neon")
	preset_picker.add_item("Anime Stylized Hits")
	preset_picker.add_item("Heavy Cinematic Nukes")
	preset_picker.item_selected.connect(func(idx: int):
		if idx == 1:
			ExplosionRegistry.apply_preset_template("default")
		elif idx == 2:
			ExplosionRegistry.apply_preset_template("retro_vector")
		elif idx == 3:
			ExplosionRegistry.apply_preset_template("anime_stylized")
		elif idx == 4:
			ExplosionRegistry.apply_preset_template("heavy_cinema")
		_refresh_studio_fields()
		_studio_status_label.text = "Loaded preset template: " + preset_picker.get_item_text(idx)
	)
	action_box.add_child(preset_picker)

	# Status indicator line
	_studio_status_label = Label.new()
	_studio_status_label.text = "Ready. Changes apply live to all destruction events."
	_studio_status_label.add_theme_font_size_override("font_size", 11)
	_studio_status_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	main_vbox.add_child(_studio_status_label)

	_refresh_studio_fields()


func _get_current_selected_slot() -> String:
	if _studio_slot_picker == null or _studio_slot_picker.selected < 0:
		return ExplosionRegistry.SLOT_SHIP_DEATH
	var idx := _studio_slot_picker.selected
	if idx >= 0 and idx < ExplosionRegistry.ALL_SLOTS.size():
		return ExplosionRegistry.ALL_SLOTS[idx]
	return ExplosionRegistry.SLOT_SHIP_DEATH


func _refresh_studio_fields() -> void:
	if _studio_slot_picker == null:
		return
	var slot := _get_current_selected_slot()
	var assign: Dictionary = ExplosionRegistry.get_slot_assignment(slot)
	var eff_id: String = String(assign.get("effect_id", "binbun_air_explosion"))
	var eff_def: Dictionary = ExplosionRegistry.get_effect(eff_id)

	# Select corresponding effect in picker
	var eff_ids := ExplosionRegistry.get_effect_ids()
	var f_idx := eff_ids.find(eff_id)
	if f_idx >= 0 and _studio_effect_picker != null:
		_studio_effect_picker.selected = f_idx

	if _studio_origin_label != null:
		_studio_origin_label.text = String(eff_def.get("pack", "Unknown"))
	if _studio_desc_label != null:
		_studio_desc_label.text = String(eff_def.get("desc", ""))

	var sc: float = float(assign.get("scale", 1.0))
	if _studio_scale_slider != null:
		_studio_scale_slider.value = sc
	if _studio_scale_lbl != null:
		_studio_scale_lbl.text = "%.1f×" % sc

	var s_name: String = String(assign.get("sound", "hit"))
	if _studio_sound_picker != null:
		for i in range(_studio_sound_picker.item_count):
			if _studio_sound_picker.get_item_text(i) == s_name:
				_studio_sound_picker.selected = i
				break

	if _studio_shockwave_check != null:
		_studio_shockwave_check.button_pressed = bool(assign.get("shockwave", true))
	if _studio_debris_check != null:
		_studio_debris_check.button_pressed = bool(assign.get("debris", true))

	var sh: float = float(assign.get("shake", 0.4))
	if _studio_shake_slider != null:
		_studio_shake_slider.value = sh
	if _studio_shake_lbl != null:
		_studio_shake_lbl.text = "%.2f" % sh


func _on_studio_slot_selected() -> void:
	_refresh_studio_fields()


func _on_studio_effect_changed() -> void:
	if _studio_effect_picker == null:
		return
	var eff_ids := ExplosionRegistry.get_effect_ids()
	var idx := _studio_effect_picker.selected
	if idx >= 0 and idx < eff_ids.size():
		var eff_id: String = eff_ids[idx]
		_save_current_field("effect_id", eff_id)
		var eff_def: Dictionary = ExplosionRegistry.get_effect(eff_id)
		if _studio_origin_label != null:
			_studio_origin_label.text = String(eff_def.get("pack", ""))
		if _studio_desc_label != null:
			_studio_desc_label.text = String(eff_def.get("desc", ""))


func _on_studio_scale_changed(v: float) -> void:
	if _studio_scale_lbl != null:
		_studio_scale_lbl.text = "%.1f×" % v
	_save_current_field("scale", v)


func _on_studio_shake_changed(v: float) -> void:
	if _studio_shake_lbl != null:
		_studio_shake_lbl.text = "%.2f" % v
	_save_current_field("shake", v)


func _on_studio_sound_changed(idx: int) -> void:
	if _studio_sound_picker != null:
		var s_name := _studio_sound_picker.get_item_text(idx)
		_save_current_field("sound", s_name)


func _save_current_field(field: String, value: Variant) -> void:
	var slot := _get_current_selected_slot()
	var a: Dictionary = ExplosionRegistry.get_slot_assignment(slot).duplicate()
	a[field] = value
	ExplosionRegistry.set_slot_assignment(slot, a)


func _test_detonate_current_slot() -> void:
	var slot := _get_current_selected_slot()
	var pos := get_action_pos()
	var reg := ExplosionRegistry.new()
	reg.spawn_event(_effects_root, slot, pos, Vector3.UP, blast_scale)
	if _studio_status_label != null:
		_studio_status_label.text = "Detonated slot: %s at %s" % [slot, str(pos)]


func _save_assignments_to_disk() -> void:
	var ok := ExplosionRegistry.save_assignments()
	if _studio_status_label != null:
		if ok:
			_studio_status_label.text = "Successfully saved assignments to res://data/effects/explosion_assignments.json!"
		else:
			_studio_status_label.text = "Error saving assignments to disk."
