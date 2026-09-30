## RadarDisplay: Modular 3D tactical radar display widget.
##
## Renders a 3D-aware orbital radar with range rings, rotating sweep line,
## contact elevation stems (altitude above/below plane), and faction-colored pips.
## Supports responsive sizing and touch / click target selection.
class_name RadarDisplay
extends Control

signal target_selected(target: Node3D)
signal range_changed(new_range: float)

@export var radar_radius: float = 76.0
@export var max_range: float = 5000.0
@export var show_elevation_stems: bool = true

## The ship's sensors are gone: the radar shows static and no contacts.
var offline := false
var _sweep_angle: float = 0.0
var _contacts: Array[Dictionary] = [] # Cached for click hit-testing


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(radar_radius * 2.0 + 16.0, radar_radius * 2.0 + 16.0)


func _process(delta: float) -> void:
	_sweep_angle = fmod(_sweep_angle + delta * 2.4, TAU)


func set_radar_range(new_range: float) -> void:
	max_range = clampf(new_range, 1000.0, 25000.0)
	range_changed.emit(max_range)


## No sensors: dark glass full of flickering static and a red "NO SIGNAL".
func _draw_offline(overlay: Control, centre: Vector2) -> void:
	overlay.draw_circle(centre, radar_radius, Color(0.03, 0.02, 0.04, 0.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec() / 70
	for i in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radar_radius * 0.95
		var p := centre + Vector2(cos(a), sin(a)) * r
		var g := rng.randf_range(0.25, 0.8)
		overlay.draw_rect(Rect2(p, Vector2(rng.randf_range(2.0, 7.0), 2.0)), Color(g, g, g, 0.6))
	overlay.draw_arc(centre, radar_radius, 0.0, TAU, 48, Color(1.0, 0.3, 0.25, 0.8), 2.0, true)
	# A terminal face: it is the radio's own read-out.
	var font := GraffitiStyle.terminal_font()
	var fs := maxi(int(radar_radius * 0.22), 10)
	var text := "NO SIGNAL"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if int(Time.get_ticks_msec() / 400) % 2 == 0:
		overlay.draw_string_outline(font, centre + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		overlay.draw_string(font, centre + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.35, 0.3))


## Renders the tactical radar onto the HUD drawing overlay.
func draw_radar(
	overlay: Control,
	player_ship: Node3D,
	ai_ships: Array,
	landmarks: Array,
	centre: Vector2,
	locked_target: Node3D = null
) -> void:
	if player_ship == null or not is_instance_valid(player_ship):
		return

	_contacts.clear()
	if offline:
		_draw_offline(overlay, centre)
		return

	# Background dark tactical glass
	overlay.draw_circle(centre, radar_radius, Color(0.02, 0.04, 0.08, 0.65))
	
	# Range rings (outer, mid, inner)
	var border_col: Color = Palette.color("ui_border")
	var dim_col := border_col * Color(1.0, 1.0, 1.0, 0.35)
	overlay.draw_arc(centre, radar_radius, 0.0, TAU, 48, border_col, 1.5, true)
	overlay.draw_arc(centre, radar_radius * 0.66, 0.0, TAU, 36, dim_col, 1.0, true)
	overlay.draw_arc(centre, radar_radius * 0.33, 0.0, TAU, 24, dim_col, 1.0, true)

	# Crosshairs (forward, aft, port, starboard)
	overlay.draw_line(centre - Vector2(radar_radius, 0.0), centre + Vector2(radar_radius, 0.0), dim_col, 1.0)
	overlay.draw_line(centre - Vector2(0.0, radar_radius), centre + Vector2(0.0, radar_radius), dim_col, 1.0)

	# Rotating radar sweep line
	var sweep_vec := Vector2(cos(_sweep_angle), sin(_sweep_angle)) * radar_radius
	overlay.draw_line(centre, centre + sweep_vec, Color(0.2, 0.85, 1.0, 0.25), 1.5, true)

	# Player center pip (bright triangle pointing up)
	var p_fwd := Vector2(0.0, -4.5)
	var p_left := Vector2(-3.5, 3.5)
	var p_right := Vector2(3.5, 3.5)
	overlay.draw_colored_polygon(PackedVector2Array([centre + p_fwd, centre + p_left, centre + p_right]), Color(0.2, 0.9, 1.0))

	var player_pos := player_ship.global_position
	var player_fwd := -player_ship.global_transform.basis.z
	var player_right := player_ship.global_transform.basis.x
	var player_up := player_ship.global_transform.basis.y

	# Draw AI ships
	for ship in ai_ships:
		if not is_instance_valid(ship) or ship == player_ship:
			continue
		var alive: bool = ship.get("_alive") if ship.get("_alive") != null else true
		if not alive:
			continue

		var ship_pos: Vector3 = ship.global_position
		var offset_world := ship_pos - player_pos
		var dist := offset_world.length()
		if dist > max_range:
			continue

		var dot_fwd := offset_world.dot(player_fwd)
		var dot_right := offset_world.dot(player_right)
		var dot_up := offset_world.dot(player_up)

		# Plane projection onto radar disc
		var map_pos := centre + Vector2(dot_right, -dot_fwd) / max_range * radar_radius
		if map_pos.distance_to(centre) > radar_radius:
			continue

		var is_locked: bool = (ship == locked_target)
		var team_id: int = int(ship.get("team_id")) if ship.get("team_id") != null else 0
		var pip_col: Color = Color("46ff9b") if team_id == 1 else (Color("ffd000") if is_locked else Color("ff4a4a"))

		# 3D elevation stem (altitude line above/below player plane)
		if show_elevation_stems and absf(dot_up) > 15.0:
			var stem_h := clampf(-dot_up / max_range * radar_radius * 1.5, -24.0, 24.0)
			var stem_end := map_pos + Vector2(0.0, stem_h)
			overlay.draw_line(map_pos, stem_end, Color(pip_col, 0.4), 1.0)
			overlay.draw_circle(stem_end, 2.5 if is_locked else 2.0, pip_col)
		else:
			overlay.draw_circle(map_pos, 3.2 if is_locked else 2.2, pip_col)

		# Cache contact for input selection
		_contacts.append({
			"target": ship,
			"pos": map_pos,
			"radius": 10.0
		})

	# Draw landmarks / planets
	for lm in landmarks:
		var l_pos: Vector3 = lm["position"]
		var l_offset := l_pos - player_pos
		var l_dist := l_offset.length()
		var l_dot_fwd := l_offset.dot(player_fwd)
		var l_dot_right := l_offset.dot(player_right)
		var l_dir := Vector2(l_dot_right, -l_dot_fwd).normalized()
		var l_col: Color = lm.get("color", Color("a0b4ff"))

		if l_dist <= max_range:
			var lm_pos := centre + Vector2(l_dot_right, -l_dot_fwd) / max_range * radar_radius
			overlay.draw_circle(lm_pos, 3.5, l_col)
		else:
			# Pin to edge of radar disc
			var lm_edge := centre + l_dir * (radar_radius - 2.0)
			overlay.draw_arc(lm_edge, 2.8, 0.0, TAU, 8, l_col, 1.5, true)


## Handles click on radar to select nearest target
func handle_click(click_pos: Vector2) -> bool:
	for c in _contacts:
		var p: Vector2 = c["pos"]
		var r: float = c["radius"]
		if click_pos.distance_to(p) <= r:
			target_selected.emit(c["target"] as Node3D)
			return true
	return false
