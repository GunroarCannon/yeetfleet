## SolarSystemGenLabRoot: a standalone dev scene for watching [SolarSystemGenerator]
## systems actually orbit, and for poking at the knobs that matter — distance
## scale, time scale, reseeding, debug orbit-path overlays, and dropping
## asteroid belts in either of the two places the generator can target (a
## planet, or the system itself).
##
## Not in [ModuleRegistry] and never will be: like `physics_lab`, this is opened
## directly in the editor (F6) for tuning, not reached through the launcher.
##
## Two camera modes, switched from the panel:
## [br]• Orbit — drag to orbit, wheel to zoom, around whichever body is focused
##   (the star by default; click a row in the body list to focus it instead).
## [br]• Free fly — WASD + hold right-mouse to look, unconstrained. Clicking a
##   body list row snaps the camera to a framing shot of it.
##
## "Enter flight test" does not simulate flight in this lab scene at all — it
## hands the current system off to the real [code]flight_test.tscn[/code]
## scene (see [method _on_enter_flight_test_pressed], [constant
## FlightRoot.Location] value GENERATED_SYSTEM) so what you fly is exactly
## what the real game builds, HUD and all, not a stand-in.
class_name SolarSystemGenLabRoot
extends Node3D

enum CamMode { ORBIT, FREE_FLY }

const LOOK_SENSITIVITY := 0.25
const ZOOM_STEP := 0.88
const DIST_MIN := 150.0
const DIST_MAX := 400000.0
const FREE_SPEED_DEFAULT := 800.0
const FREE_SPEED_MIN := 20.0
const FREE_SPEED_MAX := 60000.0

## Backdrop sky dome radius floor — the smallest the dome ever gets, so a tiny
## default system still reads as "space" rather than a cramped bubble. [method
## _build_backdrop] grows [member _sky_radius] past this from the *actual*
## generated system's outer reach (see [method SolarSystemGenerator.outer_extent])
## so a big star, Vast/Realistic distance presets, or a wide belt never leave
## the dome dwarfed by the system it's supposed to surround — nor keep it
## needlessly huge (and its nebula/starfield needlessly sparse-looking) for a
## small, compact one.
const MIN_SKY_RADIUS := 60000.0
const STAR_COUNT := 700
## How much clearance [member _sky_radius] keeps past the system's actual
## outer extent — big enough that the dome never reads as a wall the ship
## could fly into.
const SKY_RADIUS_MARGIN := 1.6

## How often the hierarchy readout re-stringifies the live system, in seconds.
## Every frame would be wasted work — nothing about "what orbits what" changes
## fast enough for a human to read faster than this.
const READOUT_INTERVAL := 0.5

## Rocks per press of a belt-spawn button.
const NEAR_BELT_COUNT := 24
const WIDE_BELT_COUNT := 70

## Quick time-scale jumps, well past the slider's own top end — see the class
## doc on [constant SolarSystemGenerator.MAX_SUBSTEPS] for why arbitrarily
## large multipliers stay responsive instead of stalling.
const TIME_SCALE_PRESETS := [1.0, 20.0, 100.0, 500.0, 2000.0]

var generator: SolarSystemGenerator

## Live backdrop radius — see [constant MIN_SKY_RADIUS]. Recomputed by
## [method _build_backdrop] every regenerate/reseed/preset change.
var _sky_radius := MIN_SKY_RADIUS

var _cam: Camera3D
var _cam_mode := CamMode.ORBIT

# Orbit mode.
var _orbit_yaw := 35.0
var _orbit_pitch := 22.0
var _orbit_dist := 4000.0

# Free-fly mode.
var _free_pos := Vector3.ZERO
var _free_yaw := 35.0
var _free_pitch := 22.0
var _free_speed := FREE_SPEED_DEFAULT

## Body last clicked in the list — the orbit/free-fly focus target, and the
## spawn point the next flight test uses. "" means the star.
var _selected_body_name := ""

var _mode_option: OptionButton
var _time_slider: HSlider
var _time_value_label: Label
var _focus_label: Label
var _body_list_box: VBoxContainer
var _camera_mode_button: Button
var _flight_test_button: Button
var _readout: Label
var _readout_timer := 0.0
var _event_log_status: Label

# Generation-options rows (SolarSystemGenerator.RANDOMIZABLE), key -> control.
var _param_sliders: Dictionary = {}
var _param_value_labels: Dictionary = {}

## On by default: previously required an easy-to-miss opt-in checkbox, which is
## what actually read as "clicking does nothing" — a first-time visitor had no
## reason to find the toggle before trying to click.
var _shooting_stars_enabled := true
const SHOOTING_STAR_LEN := 900.0
const SHOOTING_STAR_DURATION := 0.6

var _save_name_edit: LineEdit
var _load_option: OptionButton
var _save_status: Label


func _ready() -> void:
	get_window().theme = BuilderTheme.build()
	_build_generator()
	_build_environment()
	_build_backdrop()
	_build_camera()
	_frame_camera_to_system()
	_build_ui()
	_refresh_readout()


# --- Generator ---------------------------------------------------------------

func _build_generator() -> void:
	generator = SolarSystemGenerator.new()
	generator.name = "Generator"
	generator.system_seed = Session.seed if Session.seed != 0 else randi()
	generator.time_scale = Session.solar_time_scale
	generator.high_res_geometry = Session.high_res
	Planet.high_detail = Session.high_res
	# generator's own _ready() calls generate_system() once it enters the tree,
	# so bodies exist as soon as add_child returns.
	add_child(generator)


func _star_position() -> Vector3:
	if generator == null or generator.bodies.is_empty():
		return Vector3.ZERO
	return (generator.bodies[0]["node"] as Node3D).global_position


## Whatever body is currently focused (the body list selection), or the star
## if nothing is picked. Used by both camera modes that have a notion of
## "looking at something" — orbit's centre and free-fly's click-to-frame.
func _focus_position() -> Vector3:
	if _selected_body_name != "" and generator != null:
		var entry := generator.find_body(_selected_body_name)
		if not entry.is_empty():
			return (entry["node"] as Node3D).global_position
	return _star_position()


func _focus_radius() -> float:
	if _selected_body_name != "" and generator != null:
		var entry := generator.find_body(_selected_body_name)
		if not entry.is_empty():
			return float(entry.get("radius", SolarSystemGenerator.STAR_RADIUS))
	return SolarSystemGenerator.STAR_RADIUS


## The system's own outer edge, in current-distance-scale units — the same
## quantity the generator uses to place its outermost planet. Used both to frame
## the camera and to place the wide belt just past every planet's orbit.
## Delegates to [method SolarSystemGenerator.outer_extent], which measures the
## real generated bodies/belts rather than re-deriving a guess from the dials
## — the old formula here (`planet_count * PLANET_GAP * distance_mult`) went
## stale the moment [member SolarSystemGenerator.star_radius_mult] started
## widening the actual planet gap (see [method SolarSystemGenerator._planet_gap]),
## and never accounted for belts or moons reaching past the outermost planet
## anyway. Falls back to that old estimate only if nothing has generated yet.
func _outer_extent() -> float:
	var measured := generator.outer_extent()
	if measured > 0.0:
		return measured
	return float(generator.planet_count) * SolarSystemGenerator.PLANET_GAP * generator._distance_mult()


# --- Environment ---------------------------------------------------------------

## A plain overview rig, not [SpaceScene]'s full backdrop: this lab is about
## orbits, not atmosphere, and a starfield/nebula pass would only compete for
## attention with the thing being tuned. It gets a light one anyway (see
## [method _build_backdrop]) — an empty black void reads as "broken", not
## "focused".
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("03050a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2a3448")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	add_child(holder)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.4
	key.light_color = Color("fff2dd")
	key.shadow_enabled = false
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -0.6, -0.4), Vector3.UP)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.4
	fill.light_color = Color("5f7fbf")
	fill.shadow_enabled = false
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.5, 0.4, 0.5), Vector3.UP)
	add_child(fill)


## A small, self-contained starfield + nebula backdrop so the void around a
## generated system isn't just flat black. Rebuildable (see [method
## _on_high_res_toggled]) — a stale "Sky" child, if any, is torn down first.
## The nebula itself is [NebulaGas] (modules/style): blobby puffs for depth
## plus [method NebulaGas.build_streaks] for the crossed colour-wash streaks
## [SpaceScene]'s sky uses — puffs alone read as flat, uniform patches.
func _build_backdrop() -> void:
	_sky_radius = maxf(MIN_SKY_RADIUS, _outer_extent() * SKY_RADIUS_MARGIN)
	var old := get_node_or_null("Sky")
	if old != null:
		remove_child(old)
		old.queue_free()
	var sky := Node3D.new()
	sky.name = "Sky"
	add_child(sky)
	sky.add_child(_make_starfield())
	var cluster_count := 4 if Session.high_res else 3
	var puffs_per_cluster := 6 if Session.high_res else 4
	sky.add_child(NebulaGas.build_streaks(generator.system_seed, _sky_radius * 0.85, 2 if Session.high_res else 1))
	sky.add_child(NebulaGas.build(generator.system_seed, _sky_radius * 0.85, cluster_count, puffs_per_cluster))


func _make_starfield() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91827
	var seg := 6
	var star_count := int(STAR_COUNT * (1.6 if Session.high_res else 1.0))
	for i in star_count:
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
		)
		if dir.length_squared() < 0.0001:
			dir = Vector3.UP
		dir = dir.normalized()
		var bright: float = pow(rng.randf(), 2.6)
		var size: float = _sky_radius * (0.0007 + bright * 0.0018)
		var centre := dir * _sky_radius
		var right := dir.cross(Vector3.UP)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized() * size
		var up := dir.cross(right).normalized() * size
		for s in seg:
			var a0 := TAU * float(s) / float(seg)
			var a1 := TAU * float(s + 1) / float(seg)
			st.add_vertex(centre)
			st.add_vertex(centre + right * cos(a0) + up * sin(a0))
			st.add_vertex(centre + right * cos(a1) + up * sin(a1))
	var inst := MeshInstance3D.new()
	inst.name = "Stars"
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.86, 0.90, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = -10
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = _sky_radius
	return inst


# --- Camera ---------------------------------------------------------------------

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "OverviewCamera"
	_cam.current = true
	_cam.near = 1.0
	_cam.far = 500000.0
	_cam.fov = 55.0
	add_child(_cam)


## Pull the orbit distance out to frame the whole system at its current
## distance-scale. Not called on a plain reseed — the layout scale hasn't
## changed, so the user's own zoom should hold.
func _frame_camera_to_system() -> void:
	_orbit_dist = clampf(_outer_extent() * 1.6, DIST_MIN, DIST_MAX)


func _update_camera_transform() -> void:
	if _cam == null:
		return
	var centre := _focus_position()
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)
	) * _orbit_dist
	_cam.global_position = centre + offset
	_cam.look_at(centre, Vector3.UP)


func _process_free_fly(delta: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(_free_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(_free_pitch))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= basis.z
	if Input.is_key_pressed(KEY_S):
		move += basis.z
	if Input.is_key_pressed(KEY_A):
		move -= basis.x
	if Input.is_key_pressed(KEY_D):
		move += basis.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed := _free_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if move.length_squared() > 0.0:
		_free_pos += move.normalized() * speed * delta
	_cam.global_position = _free_pos
	_cam.global_transform.basis = basis


func _aim_free_camera_at(target: Vector3, distance: float) -> void:
	var dir := Vector3(0.4, 0.28, 1.0).normalized()
	_free_pos = target + dir * distance
	var look_dir := (target - _free_pos).normalized()
	_free_yaw = rad_to_deg(atan2(-look_dir.x, -look_dir.z))
	_free_pitch = rad_to_deg(asin(clampf(look_dir.y, -1.0, 1.0)))


func _unhandled_input(event: InputEvent) -> void:
	if _shooting_stars_enabled:
		var is_click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		var is_touch := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
		if is_click or is_touch:
			_spawn_shooting_star()
	match _cam_mode:
		CamMode.ORBIT:
			_unhandled_input_orbit(event)
		CamMode.FREE_FLY:
			_unhandled_input_free_fly(event)


func _unhandled_input_orbit(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var rel := (event as InputEventMouseMotion).relative
		_orbit_yaw = wrapf(_orbit_yaw - rel.x * LOOK_SENSITIVITY, 0.0, 360.0)
		_orbit_pitch = clampf(_orbit_pitch - rel.y * LOOK_SENSITIVITY, -85.0, 85.0)
	elif event is InputEventScreenDrag:
		var rel := (event as InputEventScreenDrag).relative
		_orbit_yaw = wrapf(_orbit_yaw - rel.x * LOOK_SENSITIVITY, 0.0, 360.0)
		_orbit_pitch = clampf(_orbit_pitch - rel.y * LOOK_SENSITIVITY, -85.0, 85.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_dist = clampf(_orbit_dist * ZOOM_STEP, DIST_MIN, DIST_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_dist = clampf(_orbit_dist / ZOOM_STEP, DIST_MIN, DIST_MAX)


func _unhandled_input_free_fly(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var rel := (event as InputEventMouseMotion).relative
		_free_yaw = wrapf(_free_yaw - rel.x * LOOK_SENSITIVITY, 0.0, 360.0)
		_free_pitch = clampf(_free_pitch - rel.y * LOOK_SENSITIVITY, -85.0, 85.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_free_speed = clampf(_free_speed * 1.2, FREE_SPEED_MIN, FREE_SPEED_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_free_speed = clampf(_free_speed / 1.2, FREE_SPEED_MIN, FREE_SPEED_MAX)


func _process(delta: float) -> void:
	# This lab scene never has a player ship of its own any more — "Enter
	# flight test" hands off to the real flight scene instead of simulating
	# one here (see [method _on_enter_flight_test_pressed]) — so belt LOD (see
	# SolarSystemGenerator.BeltState) has no focus and every belt stays
	# LUMPED while poking at generation from this lab.
	if generator != null:
		generator.set_lod_focus(Vector3.ZERO, false)
	match _cam_mode:
		CamMode.ORBIT:
			_update_camera_transform()
		CamMode.FREE_FLY:
			_process_free_fly(delta)
	_readout_timer += delta
	if _readout_timer >= READOUT_INTERVAL:
		_readout_timer = 0.0
		_refresh_readout()


## Save/load [SolarSystemData] recipes to/from res://data/systems — same
## save-a-name/pick-from-a-list shape as the ship builder's own save flow, at
## a fraction of the size since [SolarSystemData] does its own tiny library
## bookkeeping (see that class's doc).
func _build_save_load_section(vbox: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Save / load system"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(header)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "system name (blank = seed number)"
	_save_name_edit.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN * 0.7)
	vbox.add_child(_save_name_edit)
	_add_button(vbox, "Save system", _on_save_system_pressed)

	_load_option = OptionButton.new()
	_load_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_load_option)
	_refresh_load_options()
	_add_button(vbox, "Load selected system", _on_load_system_pressed)

	_save_status = Label.new()
	_save_status.add_theme_font_size_override("font_size", 9)
	_save_status.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_save_status)


func _refresh_load_options() -> void:
	if _load_option == null:
		return
	_load_option.clear()
	for id in SolarSystemData.list_ids():
		_load_option.add_item(id)


func _on_save_system_pressed() -> void:
	var data := SolarSystemData.from_generator(generator, _save_name_edit.text.strip_edges())
	var result := data.save_to_disk()
	if _save_status != null:
		_save_status.text = "Saved %s" % String(result["path"]) if bool(result["ok"]) \
			else "Save failed: %s" % String(result["error"])
	_refresh_load_options()


func _on_load_system_pressed() -> void:
	if _load_option == null or _load_option.item_count == 0:
		if _save_status != null:
			_save_status.text = "No saved systems to load"
		return
	var id := _load_option.get_item_text(_load_option.selected)
	var data := SolarSystemData.load_from_disk(id)
	if data == null:
		if _save_status != null:
			_save_status.text = "Could not load %s" % id
		return
	data.apply_to(generator)
	_refresh_param_rows()
	_frame_camera_to_system()
	_build_backdrop()
	_selected_body_name = ""
	_update_focus_label()
	_refresh_readout()
	_refresh_body_list()
	if _save_status != null:
		_save_status.text = "Loaded %s" % id


# --- Flight test ---------------------------------------------------------------

## Hands the current system off to the real [code]flight_test.tscn[/code]
## scene rather than simulating flight in this lab: stashes a
## [SolarSystemData] recipe (see [method SolarSystemData.from_generator]) and
## the selected spawn body on [Session], sets [member Session.flight_location]
## to [constant FlightRoot.Location] value GENERATED_SYSTEM, then changes
## scene. [method FlightRoot._build_generated_system] rebuilds the exact same
## system from that recipe once the new scene reads it.
func _on_enter_flight_test_pressed() -> void:
	Session.pending_solar_system = SolarSystemData.from_generator(generator)
	Session.pending_spawn_body_name = _selected_body_name
	Session.flight_location = FlightRoot.Location.GENERATED_SYSTEM
	get_tree().change_scene_to_file(ModuleRegistry.scene_path("flight"))


# --- UI ---------------------------------------------------------------------

## Built in code, the same way [FlightHud] builds its instruments — a Control
## laid out in the .tscn fights the editor for a scene this simple, and every
## widget here is a plain vertical list that code lays out in a few lines.
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Ui"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = BuilderTheme.PAD
	panel.offset_top = BuilderTheme.PAD
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.border(), 6)
	)
	canvas.add_child(panel)

	var outer_scroll := ScrollContainer.new()
	outer_scroll.custom_minimum_size = Vector2(0, 700)
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(outer_scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", BuilderTheme.GAP)
	outer_scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Solar System Gen Lab"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(title)

	_camera_mode_button = _add_button(vbox, "Camera: Orbit (drag / wheel)", _on_toggle_camera_mode_pressed)
	_focus_label = Label.new()
	_focus_label.add_theme_font_size_override("font_size", 10)
	_focus_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_update_focus_label()
	vbox.add_child(_focus_label)
	# Near the top, not after the ~20-row generation-options list: the panel's
	# ScrollContainer clips anything scrolled past its visible height, and a
	# control down there is unreachable by click until the user scrolls all
	# the way down to it — which is what made this read as "click not working".
	_add_check_row(vbox, "Shooting stars on click", _shooting_stars_enabled, _on_shooting_stars_toggled)

	_mode_option = _add_option_row(
		vbox, "Distance", _distance_labels(), _distance_index_for(generator.distance_scale),
		_on_distance_preset_selected
	)

	_build_time_scale_row(vbox)

	_add_separator(vbox)
	_build_generation_options_section(vbox)

	_add_separator(vbox)
	_add_button(vbox, "Regenerate / reseed", _on_regenerate_pressed)
	_add_button(vbox, "Spawn belt near a planet", _on_spawn_near_belt_pressed)
	_add_button(vbox, "Spawn wide system belt", _on_spawn_wide_belt_pressed)

	_add_separator(vbox)
	_add_check_row(
		vbox, "Lock orbits (break on hard hit)", generator.orbit_lock_enabled, _on_orbit_lock_toggled
	)
	_add_check_row(vbox, "Show predicted orbit paths", generator.show_predicted_orbits, _on_predicted_orbits_toggled)
	_add_check_row(vbox, "Show actual travelled trails", generator.show_actual_trails, _on_actual_trails_toggled)
	_add_check_row(vbox, "Log orbit events", generator.log_events, _on_log_events_toggled)
	_add_button(vbox, "Dump event log", _on_dump_event_log_pressed)
	_event_log_status = Label.new()
	_event_log_status.add_theme_font_size_override("font_size", 9)
	_event_log_status.add_theme_color_override("font_color", BuilderTheme.text_dim())
	_event_log_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_event_log_status)

	_add_separator(vbox)
	_add_check_row(vbox, "HD render (denser geometry, more nebula)", Session.high_res, _on_high_res_toggled)

	_add_separator(vbox)
	var test_label := Label.new()
	test_label.text = "Flight test"
	test_label.add_theme_font_size_override("font_size", 11)
	test_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(test_label)
	_flight_test_button = _add_button(vbox, "Enter flight test at selected body", _on_enter_flight_test_pressed)
	var flight_help := Label.new()
	flight_help.text = "Pick a body below first. Loads this system into the real flight scene and flies you there."
	flight_help.add_theme_font_size_override("font_size", 9)
	flight_help.add_theme_color_override("font_color", BuilderTheme.text_dim())
	flight_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(flight_help)

	_add_separator(vbox)
	_build_save_load_section(vbox)

	_add_separator(vbox)
	var body_label := Label.new()
	body_label.text = "Bodies (click: focus camera / pick flight-test spawn)"
	body_label.add_theme_font_size_override("font_size", 11)
	body_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body_label)
	var body_scroll := ScrollContainer.new()
	body_scroll.custom_minimum_size = Vector2(0, 140)
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(body_scroll)
	_body_list_box = VBoxContainer.new()
	_body_list_box.add_theme_constant_override("separation", 2)
	body_scroll.add_child(_body_list_box)

	_add_separator(vbox)
	var readout_label := Label.new()
	readout_label.text = "What orbits what"
	readout_label.add_theme_font_size_override("font_size", 11)
	readout_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	vbox.add_child(readout_label)

	var hierarchy_scroll := ScrollContainer.new()
	hierarchy_scroll.custom_minimum_size = Vector2(0, 180)
	hierarchy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(hierarchy_scroll)

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 11)
	_readout.add_theme_color_override("font_color", BuilderTheme.text())
	_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	hierarchy_scroll.add_child(_readout)

	_refresh_body_list()


func _build_time_scale_row(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BuilderTheme.GAP)
	var name_lbl := Label.new()
	name_lbl.text = "Time scale"
	name_lbl.custom_minimum_size = Vector2(90, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(name_lbl)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 60.0
	_time_slider.step = 1.0
	_time_slider.value = clampf(generator.time_scale, 0.0, 60.0)
	_time_slider.custom_minimum_size = Vector2(90, 24)
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.value_changed.connect(_on_time_scale_changed)
	row.add_child(_time_slider)
	vbox.add_child(row)

	_time_value_label = Label.new()
	_time_value_label.add_theme_font_size_override("font_size", 11)
	_time_value_label.add_theme_color_override("font_color", BuilderTheme.accent())
	vbox.add_child(_time_value_label)
	_update_time_value_label()

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 4)
	for mult in TIME_SCALE_PRESETS:
		var b := Button.new()
		b.text = "%dx" % int(mult)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN * 0.7)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_time_scale_preset_pressed.bind(float(mult)))
		preset_row.add_child(b)
	vbox.add_child(preset_row)


## One slider + lock-checkbox row per [constant SolarSystemGenerator.RANDOMIZABLE]
## entry, built generically from the schema instead of one hand-written row per
## dial — see that constant's doc for why adding a new dial only costs one
## exported var + one schema entry. The lock checkbox controls
## [member SolarSystemGenerator.locked]; "Regenerate / reseed" rerolls every
## unlocked one (see [method SolarSystemGenerator.randomize_unlocked_params]).
func _build_generation_options_section(vbox: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Generation options — lock (☑) to hold a value across reseed"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(header)
	for schema_entry in SolarSystemGenerator.RANDOMIZABLE:
		_add_param_row(vbox, schema_entry)


func _add_param_row(parent: VBoxContainer, schema_entry: Dictionary) -> void:
	var key: String = schema_entry["key"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lock_cb := CheckButton.new()
	lock_cb.button_pressed = bool(generator.locked.get(key, false))
	lock_cb.focus_mode = Control.FOCUS_NONE
	lock_cb.tooltip_text = "Lock: hold this value across Regenerate / reseed"
	lock_cb.toggled.connect(_on_param_lock_toggled.bind(key))
	row.add_child(lock_cb)

	var name_lbl := Label.new()
	name_lbl.text = String(schema_entry["label"])
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(name_lbl)

	var slider := HSlider.new()
	slider.min_value = float(schema_entry["min"])
	slider.max_value = float(schema_entry["max"])
	slider.step = float(schema_entry["step"])
	slider.value = float(generator.get(key))
	slider.custom_minimum_size = Vector2(64, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(34, 0)
	value_lbl.add_theme_font_size_override("font_size", 10)
	value_lbl.add_theme_color_override("font_color", BuilderTheme.accent())
	value_lbl.text = _format_param_value(schema_entry, slider.value)
	row.add_child(value_lbl)

	slider.value_changed.connect(_on_param_slider_changed.bind(schema_entry, value_lbl))
	parent.add_child(row)
	_param_sliders[key] = slider
	_param_value_labels[key] = value_lbl


func _format_param_value(schema_entry: Dictionary, value: float) -> String:
	return "%d" % int(value) if schema_entry.get("is_int", false) else "%.2f" % value


func _on_param_slider_changed(value: float, schema_entry: Dictionary, value_lbl: Label) -> void:
	var key: String = schema_entry["key"]
	generator.set(key, int(value) if schema_entry.get("is_int", false) else value)
	value_lbl.text = _format_param_value(schema_entry, value)


func _on_param_lock_toggled(enabled: bool, key: String) -> void:
	generator.locked[key] = enabled


## Syncs every generation-option slider/label to the generator's current
## values — needed after [method SolarSystemGenerator.randomize_unlocked_params]
## rerolls whichever dials aren't locked, so the panel shows what actually
## generated rather than going stale.
func _refresh_param_rows() -> void:
	for schema_entry in SolarSystemGenerator.RANDOMIZABLE:
		var key: String = schema_entry["key"]
		var slider: HSlider = _param_sliders.get(key)
		if slider == null:
			continue
		var v: float = float(generator.get(key))
		slider.set_value_no_signal(v)
		var lbl: Label = _param_value_labels.get(key)
		if lbl != null:
			lbl.text = _format_param_value(schema_entry, v)


func _update_time_value_label() -> void:
	if _time_value_label != null:
		_time_value_label.text = "%.0fx" % generator.time_scale


func _add_button(parent: VBoxContainer, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _add_check_row(parent: VBoxContainer, label: String, checked: bool, on_toggle: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = label
	cb.button_pressed = checked
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(on_toggle)
	parent.add_child(cb)
	return cb


func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.modulate.a = 0.4
	parent.add_child(sep)


func _add_option_row(
	parent: VBoxContainer, label: String, choices: Array, initial: int, on_selected: Callable
) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BuilderTheme.GAP)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.custom_minimum_size = Vector2(90, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", BuilderTheme.text_dim())
	row.add_child(name_lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in choices:
		opt.add_item(String(c))
	opt.select(initial)
	opt.item_selected.connect(on_selected)
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _refresh_readout() -> void:
	if _readout == null or generator == null:
		return
	_readout.text = generator.describe_hierarchy()


func _update_focus_label() -> void:
	if _focus_label == null:
		return
	_focus_label.text = "Focus: %s" % (_selected_body_name if _selected_body_name != "" else "the star")


func _kind_label(kind: int) -> String:
	match kind:
		SolarSystemGenerator.BodyKind.STAR:
			return "star"
		SolarSystemGenerator.BodyKind.PLANET:
			return "planet"
		SolarSystemGenerator.BodyKind.MOON:
			return "moon"
		_:
			return "body"


func _refresh_body_list() -> void:
	if _body_list_box == null or generator == null:
		return
	for child in _body_list_box.get_children():
		child.queue_free()
	for entry in generator.pickable_bodies():
		var body_name: String = entry["name"]
		var b := Button.new()
		b.text = "%s (%s)" % [body_name, _kind_label(int(entry["kind"]))]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_body_selected.bind(body_name))
		_body_list_box.add_child(b)


# --- UI actions ---------------------------------------------------------------

func _distance_labels() -> Array:
	var labels: Array = []
	for preset in SolarSystemGenerator.DISTANCE_PRESETS:
		labels.append(String(preset["label"]))
	return labels


func _distance_index_for(scale: float) -> int:
	var best := 0
	var best_diff := INF
	for i in SolarSystemGenerator.DISTANCE_PRESETS.size():
		var diff := absf(float(SolarSystemGenerator.DISTANCE_PRESETS[i]["scale"]) - scale)
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


func _on_distance_preset_selected(idx: int) -> void:
	var preset: Dictionary = SolarSystemGenerator.DISTANCE_PRESETS[idx]
	generator.distance_scale = float(preset["scale"])
	generator.generate_system()
	_build_backdrop()
	_frame_camera_to_system()
	_refresh_readout()
	_refresh_body_list()


func _on_time_scale_changed(v: float) -> void:
	generator.time_scale = v
	Session.solar_time_scale = v
	_update_time_value_label()


func _on_time_scale_preset_pressed(mult: float) -> void:
	generator.time_scale = mult
	Session.solar_time_scale = mult
	if _time_slider != null:
		# set_value_no_signal, not .value: a preset above the slider's own
		# range (see TIME_SCALE_PRESETS) would otherwise fire value_changed
		# with the slider's clamped number and silently overwrite the real
		# multiplier we just set.
		_time_slider.set_value_no_signal(clampf(mult, _time_slider.min_value, _time_slider.max_value))
	_update_time_value_label()


func _on_orbit_lock_toggled(enabled: bool) -> void:
	generator.set_orbit_lock_enabled(enabled)


func _on_predicted_orbits_toggled(enabled: bool) -> void:
	generator.set_show_predicted_orbits(enabled)


func _on_actual_trails_toggled(enabled: bool) -> void:
	generator.set_show_actual_trails(enabled)


func _on_log_events_toggled(enabled: bool) -> void:
	generator.log_events = enabled


## Restart-free: rebuilds the backdrop and regenerates the system in place at
## denser geometry (same seed + same params — only [member
## SolarSystemGenerator.high_res_geometry] and [member Planet.high_detail]
## changed), instead of this lab's own flight-scene-side "restart to apply".
func _on_high_res_toggled(enabled: bool) -> void:
	Session.high_res = enabled
	Planet.high_detail = enabled
	generator.high_res_geometry = enabled
	generator.generate_system()
	_build_backdrop()
	_refresh_param_rows()
	_refresh_readout()
	_refresh_body_list()


func _on_shooting_stars_toggled(enabled: bool) -> void:
	_shooting_stars_enabled = enabled


## A bright, fading comet-tail streak spawned out past the camera — cosmetic
## only, self-freeing. No image asset: an unshaded, per-vertex-alpha line
## (the same technique [method SolarSystemGenerator._make_line_mesh] uses for
## orbit-path overlays) faded out with a [Tween] on its own material.
func _spawn_shooting_star() -> void:
	if _cam == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dir := Vector3(
		rng.randf_range(-1.0, 1.0), rng.randf_range(-0.25, 0.25), rng.randf_range(-1.0, 1.0)
	)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var centre := _cam.global_position + dir * (_sky_radius * 0.55)
	var start := centre - side * SHOOTING_STAR_LEN * 0.5
	var end := centre + side * SHOOTING_STAR_LEN * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	st.set_color(Color(1.0, 0.95, 0.85, 0.0))
	st.add_vertex(start)
	st.set_color(Color(1.0, 0.95, 0.85, 1.0))
	st.add_vertex(end)

	var inst := MeshInstance3D.new()
	inst.name = "ShootingStar"
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = -5
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = SHOOTING_STAR_LEN
	add_child(inst)

	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, SHOOTING_STAR_DURATION).from(1.0)
	tween.tween_callback(inst.queue_free)


func _on_dump_event_log_pressed() -> void:
	var path := generator.dump_event_log()
	if _event_log_status != null:
		_event_log_status.text = "Wrote %d lines to %s" % [generator.get_event_log().size(), path] \
			if path != "" else "Could not write event log"


func _on_regenerate_pressed() -> void:
	generator.system_seed = randi()
	generator.randomize_unlocked_params()
	generator.generate_system()
	_build_backdrop()
	_refresh_param_rows()
	_frame_camera_to_system()
	_selected_body_name = ""
	_update_focus_label()
	_refresh_readout()
	_refresh_body_list()


func _on_toggle_camera_mode_pressed() -> void:
	if _cam_mode == CamMode.ORBIT:
		_cam_mode = CamMode.FREE_FLY
		_free_pos = _cam.global_position
		var look_dir := (_focus_position() - _free_pos).normalized()
		if look_dir.length_squared() > 0.0001:
			_free_yaw = rad_to_deg(atan2(-look_dir.x, -look_dir.z))
			_free_pitch = rad_to_deg(asin(clampf(look_dir.y, -1.0, 1.0)))
		_camera_mode_button.text = "Camera: Free fly (WASD, hold RMB to look)"
	else:
		_cam_mode = CamMode.ORBIT
		_camera_mode_button.text = "Camera: Orbit (drag / wheel)"


func _on_body_selected(body_name: String) -> void:
	_selected_body_name = body_name
	_update_focus_label()
	match _cam_mode:
		CamMode.ORBIT:
			_orbit_dist = clampf(_focus_radius() * 10.0, DIST_MIN, DIST_MAX)
		CamMode.FREE_FLY:
			_aim_free_camera_at(_focus_position(), clampf(_focus_radius() * 6.0, DIST_MIN, DIST_MAX))


## Rings a random live planet at half its Hill radius — the same clamp
## [method SolarSystemGenerator._spawn_moons] uses — so the ring reads as that
## planet's belt rather than sliding into the star's own pull.
func _on_spawn_near_belt_pressed() -> void:
	var planets := generator.bodies.filter(
		func(e: Dictionary) -> bool: return e["kind"] == SolarSystemGenerator.BodyKind.PLANET
	)
	if planets.is_empty():
		return
	var entry: Dictionary = planets[randi() % planets.size()]
	var node := entry["node"] as Node3D
	var gbody := entry["gbody"] as GravitySystem.GravityBody
	var near_radius := minf(
		gbody.radius * 2.2 + 60.0, generator._hill_radius(gbody, node.position) * 0.5
	)
	# manual=true: a button the user just pressed to inspect a belt should show
	# real, bounceable rocks immediately, not a lumped ring waiting on a ship.
	generator.spawn_asteroid_belt(node.position, near_radius, NEAR_BELT_COUNT, 15.0, entry["name"], true)
	_refresh_readout()


## Rings the star itself, just past every planet's orbit — the generic
## [method SolarSystemGenerator.spawn_asteroid_belt] call with the star as
## centre, which is what makes the same function read as "the system's belt".
func _on_spawn_wide_belt_pressed() -> void:
	var far_radius := _outer_extent() * 1.2
	var star_name: String = generator.bodies[0]["name"] if not generator.bodies.is_empty() else ""
	generator.spawn_asteroid_belt(_star_position(), far_radius, WIDE_BELT_COUNT, far_radius * 0.05, star_name, true)
	# The belt just spawned past the previous outer extent — grow the dome to
	# match, same as every other regenerate/reseed path (see _build_backdrop).
	_build_backdrop()
	_refresh_readout()
