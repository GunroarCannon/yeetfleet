## Everything the pilot reads and everything the pilot touches.
##
## One layout serves a phone and a desktop. That is a constraint, not a
## compromise: the controls live in the four corners where thumbs already are,
## the middle of the screen stays clear for the thing you are flying at, and the
## only chrome that is ever more than one tap deep is behind the menu button.
## Nothing here is keyboard-only and nothing here is touch-only.
##
## The instruments are drawn rather than assembled from Controls, because most of
## them — the reticle, the drift marker, the landmark pips — are positions
## projected out of the 3D view every frame, and a Control per pip would be a
## node churn for no gain.
class_name FlightHud
extends Control

## Toolbar category ids — one icon button per category, each opening a draggable
## popup panel (see [FlightMenu]). The HUD fills each popup's content when its
## category button is pressed.
const CAT_VIEW := 1
const CAT_CONTROLS := 2
const CAT_COMBAT := 3
const CAT_GRAVITY := 4
const CAT_ORBIT := 5
const CAT_SETTINGS := 6
const CAT_HELP := 7
const CAT_TRAILS := 8
const CAT_CRAFT := 9
## Direct-action toolbar buttons (no popup).
const ACTION_HANGAR := 90

## Reticle size in pixels, and the radius the drift marker is clamped to when the
## direction of travel leaves the screen. An off-screen marker is useless; a
## marker pinned to the edge of a ring still says "your momentum is that way".
const RETICLE_RADIUS := 16.0
const DRIFT_CLAMP := 0.34

## Landmarks stop being drawn beyond this range, in metres.
const MARKER_RANGE := 9000.0

var _root: FlightRoot

var _stick: VirtualStick
var _throttle: ThrottleLever
var _overlay: Control
var _menu: FlightMenu
var _fire_button: Button
var _boost_button: Button
var _assist_chip: Button
var _view_chip: Button
var _speed_label: Label
var _target_label: Label
var _hint_label: Label
var _damage_label: Label
var _ground_speed_label: Label

var _energy := 1.0
var _heat := 0.0

## Debug toggles — small checkboxes on the right edge to isolate rendering issues.
var _debug_panel: VBoxContainer = null
var _debug_toggles: Dictionary = {}
var _event_container: CenterContainer = null


func _ready() -> void:
	_root = owner as FlightRoot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	# The instrument overlay sits under every widget and ignores input entirely,
	# so a pip drawn over the fire button never eats the tap.
	_overlay = Control.new()
	_overlay.name = "Instruments"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_instruments)
	add_child(_overlay)

	_build_top_bar()
	_build_readouts()
	_build_controls()
	_build_event_container()
	_build_debug_panel()
	_build_rear_view_display()


func _build_event_container() -> void:
	_event_container = CenterContainer.new()
	_event_container.name = "EventBubbleContainer"
	_event_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_event_container.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_event_container.custom_minimum_size = Vector2(0.0, 60.0)
	add_child(_event_container)


func get_event_container() -> Control:
	return _event_container


func _build_debug_panel() -> void:
	# Debug panel: toggles on the right edge to isolate rendering issues.
	_debug_panel = VBoxContainer.new()
	_debug_panel.name = "DebugToggles"
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.offset_right = -BuilderTheme.PAD
	_debug_panel.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_debug_panel.offset_left = -160.0
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_panel.visible = false
	add_child(_debug_panel)

	var lbl := Label.new()
	lbl.text = "DEBUG"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", BuilderTheme.warn())
	_debug_panel.add_child(lbl)

	_add_debug_toggle("Plumes", true)
	_add_debug_toggle("Halos", true)
	_add_debug_toggle("Tracers", true)
	_add_debug_toggle("Stars", true)
	_add_debug_toggle("Nebula", true)
	_add_debug_toggle("Planet", true)
	_add_debug_toggle("Atmo", true)
	_add_debug_toggle("SafeAtmo", true)
	_add_debug_toggle("Station", true)
	_add_debug_toggle("SkyDome", true)
	_add_debug_toggle("Sun", true)
	_add_debug_toggle("Asteroids", true)
	_add_debug_toggle("Drift", true)
	_add_debug_toggle("Reticle", Session.hud_reticle)
	_add_debug_toggle("Markers", Session.hud_markers)
	_add_debug_toggle("ShipGeo", true)
	_add_debug_toggle("!!! ALL !!!", true)

	# D key toggles the panel.


func _add_debug_toggle(label: String, default: bool) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = default
	cb.add_theme_font_size_override("font_size", 10)
	cb.add_theme_color_override("font_color", BuilderTheme.text_dim())
	cb.mouse_filter = Control.MOUSE_FILTER_STOP
	cb.toggled.connect(func(on: bool) -> void: _on_debug_toggle(label, on))
	_debug_panel.add_child(cb)
	_debug_toggles[label] = cb


func _on_debug_toggle(label: String, on: bool) -> void:
	# Forward to FlightRoot which owns the actual nodes.
	if _root == null:
		return
	match label:
		"Plumes": _root.set_debug_visible("plumes", on)
		"Halos": _root.set_debug_visible("halos", on)
		"Tracers": _root.set_debug_visible("tracers", on)
		"Stars": _root.set_debug_visible("stars", on)
		"Nebula": _root.set_debug_visible("nebula", on)
		"Planet": _root.set_debug_visible("planet", on)
		"Atmo": _root.set_debug_visible("atmo", on)
		"SafeAtmo": Planet.swap_all_atmosphere_shaders(on)
		"Station": _root.set_debug_visible("station", on)
		"SkyDome": _root.set_debug_visible("skydome", on)
		"Sun": _root.set_debug_visible("sun", on)
		"ShipGeo": _root.set_debug_visible("shipgeo", on)
		"!!! ALL !!!": _root.set_debug_visible("everything", on)
		"Asteroids": _root.set_debug_visible("asteroids", on)
		"Drift": _root.set_debug_visible("drift", on)
		"Reticle": Session.hud_reticle = on
		"Markers": Session.hud_markers = on


func toggle_debug_panel() -> void:
	if _debug_panel != null:
		_debug_panel.visible = not _debug_panel.visible


# --- Settings popup -----------------------------------------------------------

## Fill the Settings popup: render distance and world-scale sliders. Continuous
## values live directly in the popup (unlike the old PopupMenu, a draggable panel
## can host HSliders).
func _fill_settings_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Settings"
	popup.add_slider_row(
		"Far clip", 10000.0, 80000.0, 1000.0, _root.far_clip(),
		func(v: float) -> void: _root.set_far_clip(v)
	)
	popup.add_slider_row(
		"Far view dist", 100.0, 2000.0, 50.0, _root.far_view_max(),
		func(v: float) -> void: _root.set_far_view_max(v)
	)
	popup.add_separator()
	popup.add_slider_row(
		"Planet size", 0.5, 10.0, 0.5, _root.planet_scale(),
		func(v: float) -> void: _root.set_planet_scale(v)
	)
	popup.add_slider_row(
		"Planet spacing", 0.5, 5.0, 0.25, _root.planet_spacing(),
		func(v: float) -> void: _root.set_planet_spacing(v)
	)

	# Ship size: scales every spawned hull (player + AI) and its collision radius.
	# Live value is stored as the slider drags; releasing reloads the flight scene
	# so all ships rebuild at the new scale (assemble applies Session.ship_scale).
	# Goes to 10x deliberately — "how big can a ship get" is a test question.
	popup.add_separator()
	var ship_slider := popup.add_slider_row(
		"Ship size", 0.5, 10.0, 0.5, Session.ship_scale,
		func(v: float) -> void: Session.ship_scale = v,
		"×%.1f"
	)
	ship_slider.drag_ended.connect(func(_changed: bool) -> void: _apply_ship_size())

	# Presets — jump the planet sliders to a pair and restart.
	popup.add_separator()
	for p: Array in [["Default", 1.0, 1.0], ["Big world", 3.0, 1.5], ["Realistic", 6.0, 3.0], ["Huge", 10.0, 5.0]]:
		popup.add_action_row(
			"Preset: %s (restart)" % String(p[0]),
			func() -> void: _apply_planet_preset(p)
		)
	popup.add_action_row("Restart with this scale", func() -> void: _root.restart_scene())

	# World-build quality dials: read while the scene builds, so changing them
	# needs a restart (the scale presets above set the precedent).
	popup.add_section("Quality (restart to apply)")
	popup.add_slider_row(
		"Star density", 0.25, 2.0, 0.25, Session.star_density,
		func(v: float) -> void: Session.star_density = v, "×%.2f"
	)
	popup.add_slider_row(
		"Distant rocks", 0.0, 2.0, 0.25, Session.asteroid_density,
		func(v: float) -> void: Session.asteroid_density = v, "×%.2f"
	)
	popup.add_check_row("Backdrop (corona, galaxy, dust)", Session.render_backdrop,
		func(on: bool) -> void: Session.render_backdrop = on)
	popup.add_action_row("Apply quality & restart", func() -> void:
		show_hint("Applying quality…")
		_root.restart_scene())
	popup.add_separator()
	popup.add_action_row("Reset all settings", func() -> void: _reset_all_settings())


func _apply_planet_preset(preset: Array) -> void:
	_root.set_planet_scale(float(preset[1]))
	_root.set_planet_spacing(float(preset[2]))
	show_hint("Planet scale preset: %s — restarting…" % String(preset[0]))
	_root.restart_scene()


## Fired once when the Ship-size slider is released: reload the flight scene so
## every ship rebuilds at the new scale.
func _apply_ship_size() -> void:
	show_hint("Ship size ×%.1f — restarting…" % Session.ship_scale)
	_root.restart_scene()


# --- Spawn state --------------------------------------------------------------

## The spawn panel's remembered choices, kept between popup opens.
var _spawn_behavior := 0
var _spawn_formation := 0
var _spawn_count := 3
## The team the spawn popup assigns spawned ships to (1 = Red).
var _spawn_team := 1


func _on_spawn_pressed() -> void:
	if _root._ai_spawner == null:
		return
	var forms := [
		AiGroupBehaviour.FormationShape.SCATTER,
		AiGroupBehaviour.FormationShape.V_FORM,
		AiGroupBehaviour.FormationShape.LINE,
		AiGroupBehaviour.FormationShape.SPHERE,
		AiGroupBehaviour.FormationShape.TRAIL,
	]
	var arch := AiFactions.custom(_spawn_behavior, forms[_spawn_formation], _spawn_count)
	_root._ai_spawner.spawn_group_with(arch, _spawn_count, _spawn_team)
	var names: Array[String] = ["Hunt", "Patrol", "Swarm", "Flee", "Guard", "Sniper"]
	var form_names: Array[String] = ["scatter", "V", "line", "sphere", "trail"]
	show_hint("Spawned %d %s (%s formation, team %s)" % [
		_spawn_count, names[_spawn_behavior], form_names[_spawn_formation], _team_short(_spawn_team)
	])


func _team_short(team: int) -> String:
	match team:
		1: return "Red"
		2: return "Blue"
		3: return "Green"
		4: return "Gold"
		_: return "None"


## Set a feel multiplier and re-apply it to the ship. configure() recomputes the
## control mode's preset numbers and multiplies by the Session dials, so forcing
## a re-configure with the current mode picks the new multiplier up live.
func _apply_feel_mult(damping: bool, mult: float) -> void:
	if damping:
		Session.damping_mult = mult
	else:
		Session.assist_mult = mult
	if _root.model != null:
		_root.model.set_control_mode(_root.model.control_mode)
	show_hint("%s ×%.2f" % ["Damping" if damping else "Assist authority", mult])


## Set the player's speed dial — see [method FlightRoot.set_player_speed_scale].
## The hint reads back the ceiling the ship actually ends up with, because
## "×0.25" on its own says nothing about whether the ship in front of you is now
## a 60 m/s hauler or a 300 m/s interceptor.
func _apply_player_speed(scale: float) -> void:
	_root.set_player_speed_scale(scale)
	var tops := _root.model.top_speed if _root.model != null else 0.0
	show_hint("Your ship ×%.2f — tops out at %.0f m/s" % [scale, tops])


## Set the AI population's speed dial — see [method
## FlightRoot.set_npc_speed_scale]. Named for what the row is called: the point
## of this dial is that it does not move *your* ship, so the hint says whose
## speed just changed rather than just reporting a number.
func _apply_npc_speed(scale: float) -> void:
	_root.set_npc_speed_scale(scale)
	show_hint("Other ships ×%.2f — yours unchanged" % scale)


## One short line for the Flight menu: which assist mode the Z key has landed on.
## The full explanation sits under it in a help row.
func _assist_short() -> String:
	var m := _root.model
	if m == null:
		return "—"
	match m.assist_mode:
		0: return "Off — thrust lever, nothing slows you"
		1: return "Damping — thrust, and drift bleeds off"
		_: return "Full — motion follows the nose"


## The active feel profile for the Flight menu's readout.
func _profile_display() -> String:
	var id := _root.phys_profile_id()
	return id if id != "" else "—"

## Set the arcade pivot multiplier and re-apply it. Same trick as the feel dials:
## [method FlightModel.configure] recomputes the mode's preset, so re-selecting
## the current mode picks the new multiplier up live instead of at the next
## respawn. The hint reads the turn rate back in degrees per second, because
## "×3" means nothing without knowing what it is three times.
func _apply_arcade_pivot(mult: float) -> void:
	Session.arcade_pivot = mult
	if _root.model == null:
		return
	_root.model.set_control_mode(_root.model.control_mode)
	show_hint("Arcade pivot ×%.2f — %.0f°/s" % [mult, rad_to_deg(_root.model.turn_rate)])


## Toggle the fast-orbit dial. Read live by the flight model, so ships already
## orbiting change speed the moment it flips.
func _set_fast_orbits(on: bool) -> void:
	Session.fast_orbits = on
	show_hint("Fast orbits: %s" % ("ON" if on else "OFF"))


## How much faster than a real circular orbit the fast-orbit dial flies a held
## ship. The flight model pairs it with the matching k² of pull, so the orbit
## stays the same circle — just taken sooner.
func _set_orbit_speed(scale: float) -> void:
	Session.orbit_speed_scale = maxf(scale, 1.0)
	show_hint("Orbit speed ×%.0f" % Session.orbit_speed_scale)


## One-line orbit state for the Orbit & time menu, from the model's tracking.
func _orbit_readout() -> String:
	var m := _root.model
	if m == null:
		return "no ship"
	var body := String(m._orbit_body_name)
	if m._in_orbit:
		return "stable around %s" % body if body != "" else "stable"
	return ("approaching %s" % body) if body != "" else "no dominant body"


## Reset every persisted setting, then restart so the world, ships and HUD all
## rebuild at the shipped defaults.
func _reset_all_settings() -> void:
	Session.reset_to_defaults()
	show_hint("All settings reset to defaults — restarting…")
	_root.restart_scene()


func _build_rear_view_display() -> void:
	# The rear view TextureRect is created by FlightRoot._build_rear_view()
	# and added to the HUD. We just need to add it as a child here.
	# It will be added when toggle_rear_view() is first called.
	pass


func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = BuilderTheme.PAD
	bar.offset_right = -BuilderTheme.PAD
	bar.offset_top = BuilderTheme.PAD
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	# The icon toolbar, top-left: one button per menu category, each opening a
	# draggable popup. Replaces the old single ☰ menu.
	_menu = FlightMenu.new()
	_menu.name = "Toolbar"
	_menu.attach(self)
	_menu.category_pressed.connect(_on_category)
	_menu.add_category(CAT_VIEW, "guns/delapouite/crosshair.png", "View — camera modes, drift field, render toggles")
	_menu.add_category(CAT_CONTROLS, "hands/delapouite/hand-grip.png", "Flight — assist, control modes, respawn")
	_menu.add_category(CAT_COMBAT, "guns/lorc/sentry-gun.png", "Combat — lock-on, spawn ships, arena")
	_menu.add_category(CAT_GRAVITY, "fire/lorc/burning-meteor.png", "Gravity — mode, strength, range, visualizers")
	_menu.add_category(CAT_ORBIT, "fire/lorc/firework-rocket.png", "Orbit & time — orbit test, satellites, speed of time")
	_menu.add_category(CAT_SETTINGS, "batteries.png", "Settings — render distance, world scale")
	_menu.add_category(CAT_HELP, "hands/john-redman/paper.png", "Help — controls card")
	_menu.add_category(CAT_TRAILS, "shoes/lorc/footprint.png", "Trails — see which way things are moving")
	_menu.add_category(CAT_CRAFT, "guns/lorc/cannon.png", "Large craft — spawn motherships, stations, gates to fly around")
	_menu.add_action_icon(ACTION_HANGAR, "flashlight.png", "Back to the hangar (Esc)", func() -> void: _root.return_to_hangar())
	bar.add_child(_menu)

	_target_label = Label.new()
	_target_label.name = "Target"
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	bar.add_child(_target_label)

	# Two chips rather than menu items: view and assist are the settings a pilot
	# changes mid-fight, and mid-fight is exactly when a menu is unusable.
	_view_chip = _chip("Chase", "Change view (V)", func() -> void: _root.cycle_view())
	bar.add_child(_view_chip)
	_assist_chip = _chip("ASSIST", "Flight assist (Z)", func() -> void: _root.toggle_assist())
	bar.add_child(_assist_chip)


func _chip(text: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, BuilderTheme.TOUCH_MIN)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _build_readouts() -> void:
	_speed_label = Label.new()
	_speed_label.name = "Speed"
	_speed_label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label.add_theme_font_size_override("font_size", 26)
	_speed_label.add_theme_color_override("font_color", BuilderTheme.text_strong_color())
	add_child(_speed_label)

	# Ground speed: total velocity magnitude with sign (negative = moving backward).
	_ground_speed_label = Label.new()
	_ground_speed_label.name = "GroundSpeed"
	_ground_speed_label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_ground_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ground_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_speed_label.add_theme_font_size_override("font_size", 14)
	_ground_speed_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(_ground_speed_label)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_color_override("font_color", BuilderTheme.warn())
	add_child(_hint_label)

	_damage_label = Label.new()
	_damage_label.name = "Damage"
	_damage_label.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_label.add_theme_font_size_override("font_size", 12)
	_damage_label.add_theme_color_override("font_color", BuilderTheme.bad())
	add_child(_damage_label)


func _build_controls() -> void:
	_throttle = ThrottleLever.new()
	_throttle.name = "Throttle"
	_throttle.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_throttle.changed.connect(func(v: float) -> void: _root.set_throttle(v))
	add_child(_throttle)

	_stick = VirtualStick.new()
	_stick.name = "Stick"
	_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stick.moved.connect(func(v: Vector2) -> void: _root.set_stick(v))
	add_child(_stick)

	_fire_button = _hold_button("FIRE", "Fire (Space)", BuilderTheme.bad())
	_fire_button.button_down.connect(func() -> void: _root.set_firing(true))
	_fire_button.button_up.connect(func() -> void: _root.set_firing(false))
	add_child(_fire_button)

	_boost_button = _hold_button("BOOST", "Boost (Shift)", BuilderTheme.accent())
	_boost_button.button_down.connect(func() -> void: _root.set_boosting(true))
	_boost_button.button_up.connect(func() -> void: _root.set_boosting(false))
	add_child(_boost_button)

	_layout_controls()
	resized.connect(_layout_controls)


func _hold_button(text: String, tooltip: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", tint)
	# Action on press, not on release: a weapon that waits for you to lift your
	# thumb is a weapon that fires after the shot was needed.
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	return b


## Positions the four thumb controls. Everything is anchored to a corner and
## sized from the shorter screen edge, so the layout is identical in portrait,
## landscape and on a desktop window — only the gaps grow.
func _layout_controls() -> void:
	if _stick == null:
		return
	var pad := float(BuilderTheme.PAD)
	var short_edge := minf(size.x, size.y)
	var stick_size := clampf(short_edge * 0.30, 110.0, 190.0)
	var button_w := clampf(short_edge * 0.17, 76.0, 132.0)
	var button_h := float(BuilderTheme.TOUCH_MIN + 8)

	_stick.size = Vector2(stick_size, stick_size)
	_stick.position = size - _stick.size - Vector2(pad, pad)

	_throttle.size = Vector2(clampf(short_edge * 0.10, 54.0, 78.0), stick_size)
	_throttle.position = Vector2(pad, size.y - _throttle.size.y - pad)

	# The action buttons sit inboard of the stick, above the throttle: reachable
	# with the left thumb while the right thumb is still flying.
	var stack_x := _throttle.position.x + _throttle.size.x + pad
	_boost_button.size = Vector2(button_w, button_h)
	_boost_button.position = Vector2(stack_x, size.y - button_h - pad)
	_fire_button.size = Vector2(button_w, button_h)
	_fire_button.position = Vector2(stack_x, size.y - button_h * 2.0 - pad * 2.0)

	_speed_label.size = Vector2(160, 40)
	_speed_label.position = Vector2(size.x - 160 - pad, size.y * 0.5 - 60)
	_ground_speed_label.size = Vector2(160, 20)
	_ground_speed_label.position = Vector2(size.x - 160 - pad, size.y * 0.5 - 22)
	_hint_label.size = Vector2(size.x * 0.6, 24)
	_hint_label.position = Vector2(size.x * 0.2, size.y * 0.5 + RETICLE_RADIUS * 3.0)

	_damage_label.size = Vector2(260, 20)
	_damage_label.position = Vector2(pad, size.y * 0.5 + 30)


# --- Menu popups --------------------------------------------------------------

## A toolbar category button was pressed: clear the popup, fill it with that
## category's controls, then let the toolbar re-clamp it on screen.
func _on_category(id: int) -> void:
	var popup := _menu.popup_for(id)
	if popup == null:
		return
	popup.clear()
	match id:
		CAT_VIEW: _fill_view_popup(popup)
		CAT_CONTROLS: _fill_controls_popup(popup)
		CAT_COMBAT: _fill_combat_popup(popup)
		CAT_GRAVITY: _fill_gravity_popup(popup)
		CAT_ORBIT: _fill_orbit_popup(popup)
		CAT_SETTINGS: _fill_settings_popup(popup)
		CAT_HELP: _fill_help_popup(popup)
		CAT_TRAILS: _fill_trails_popup(popup)
		CAT_CRAFT: _fill_craft_popup(popup)
	_menu.recentre_open()


func _fill_view_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "View"
	var mode := _root.camera_mode()
	for entry: Array in [
		["Cockpit", FlightCamera.Mode.COCKPIT],
		["Chase", FlightCamera.Mode.CHASE],
		["External", FlightCamera.Mode.ORBIT],
		["Rear", FlightCamera.Mode.REAR],
		["Far", FlightCamera.Mode.FAR],
		["Planet (P)", FlightCamera.Mode.PLANET],
		["Free", FlightCamera.Mode.FREE],
	]:
		popup.add_radio_row(
			String(entry[0]), mode == int(entry[1]), int(entry[1]),
			func(v: int) -> void: _root.set_view(v)
		)
	# Camera dials (live, persisted).
	popup.add_section("Camera")
	popup.add_slider_row(
		"Field of view", 50.0, 120.0, 1.0, Session.camera_fov,
		func(v: float) -> void: _root.set_camera_fov(v), "%.0f°"
	)
	popup.add_slider_row(
		"Chase distance", 0.5, 2.0, 0.05, Session.camera_chase,
		func(v: float) -> void: _root.set_camera_chase(v), "×%.2f"
	)

	# Render toggles.
	popup.add_section("Render")
	popup.add_check_row("Drift field", _root.drift_field_on(), func(_on: bool) -> void: _root.toggle_drift_field())
	popup.add_check_row("Rear view (B)", _root._rear_view_on, func(_on: bool) -> void: _root.toggle_rear_view())
	popup.add_check_row("High res (restart)", _root.high_res_on(), func(_on: bool) -> void: _root.toggle_high_res())
	popup.add_check_row("High contrast", BuilderTheme.high_contrast, func(_on: bool) -> void: _root.toggle_high_contrast())
	popup.add_check_row("Test volume (restart)", not _root.location_is_space(), func(_on: bool) -> void: _root.toggle_location())
	popup.add_check_row("Planet pointer (J)", _root.planet_pointer_on(), func(_on: bool) -> void: _root.toggle_planet_pointer())

	# HUD clutter (persisted).
	popup.add_section("HUD overlay")
	popup.add_check_row("Reticle", Session.hud_reticle, func(on: bool) -> void: Session.hud_reticle = on)
	popup.add_check_row("Markers & brackets", Session.hud_markers, func(on: bool) -> void: Session.hud_markers = on)
	popup.add_check_row("Player indicator", Session.hud_indicators, func(on: bool) -> void: Session.hud_indicators = on)


func _fill_controls_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Flight"
	popup.add_action_row("Cycle assist (Z)", func() -> void: _root.toggle_assist())
	popup.add_value_row("Assist now", _assist_short())
	popup.add_help_row(
		"How your motion follows your nose. Off: the throttle is a thrust lever and nothing ever slows you down. "
		+ "Damping: thrust as usual, but sideways drift bleeds away. "
		+ "Full: the computer flies your velocity onto wherever you point."
	)

	# Handling master, then the two dials that tune it. The presets were a bare
	# list of four words before; nothing on screen said what any of them bundled.
	popup.add_separator()
	popup.add_section("Handling preset")
	var ctrl := _root.model.control_mode if _root.model != null else FlightModel.ControlMode.SIM
	for entry: Array in [
		["Arcade", FlightModel.ControlMode.ARCADE],
		["Sim", FlightModel.ControlMode.SIM],
		["Realistic", FlightModel.ControlMode.REALISTIC],
		["Dogfight (F11)", FlightModel.ControlMode.DOGFIGHT],
	]:
		popup.add_radio_row(
			String(entry[0]), ctrl == int(entry[1]), int(entry[1]),
			func(v: int) -> void: _root.model.set_control_mode(v)
		)
	popup.add_help_row(
		"One preset bundles turn rate, top speed, and how snappy the assist is. "
		+ "The dials below multiply it, so you tune a preset rather than replace it."
	)
	# Arcade pivot sits directly under the modes it applies to, because it is a
	# property of arcade rather than a global dial: crank it and arcade stops
	# being "responsive" and starts being an FPS — point the nose and be pointing
	# there. Nothing happens on the other three modes, which is the point.
	popup.add_slider_row(
		"Arcade pivot", 1.0, 6.0, 0.25, Session.arcade_pivot,
		func(v: float) -> void: _apply_arcade_pivot(v), "×%.2f"
	)
	popup.add_help_row(
		"Arcade preset only. How much faster than its own tuning the nose swings "
		+ "round — at the top the ship points where you flick it, like an FPS."
	)

	# The two assist dials, named for what they do to the ship rather than for
	# the variable they happen to scale.
	popup.add_separator()
	popup.add_section("Assist tuning (× the preset)")
	popup.add_slider_row(
		"Nose grip", 0.5, 5.0, 0.05, Session.assist_mult,
		func(v: float) -> void: _apply_feel_mult(false, v), "×%.2f"
	)
	popup.add_help_row(
		"Full assist only. How hard the ship drags its motion around onto the "
		+ "nose. Low and it slides on like ice; high and it goes where you point."
	)
	popup.add_slider_row(
		"Drift bleed-off", 0.25, 2.0, 0.05, Session.damping_mult,
		func(v: float) -> void: _apply_feel_mult(true, v), "×%.2f"
	)
	popup.add_help_row(
		"Damping mode only. How quickly leftover sideways drift dies away once "
		+ "you stop turning."
	)

	# Two speed dials rather than one: slowing a fight down so it is readable and
	# slowing the enemy down so it is winnable are different requests.
	popup.add_separator()
	popup.add_section("Speed (ships only)")
	popup.add_slider_row(
		"Your ship", 0.1, 2.0, 0.05, Session.player_speed_scale,
		func(v: float) -> void: _apply_player_speed(v), "×%.2f"
	)
	popup.add_help_row("Your top speed and acceleration. Nothing else is affected.")
	popup.add_slider_row(
		"Other ships", 0.1, 2.0, 0.05, Session.npc_speed_scale,
		func(v: float) -> void: _apply_npc_speed(v), "×%.2f"
	)
	popup.add_help_row(
		"Every AI ship's top speed and acceleration. Your ship is unaffected. "
		+ "Rocks, debris and planet orbits are never affected by either dial."
	)

	# Collision feel: what the old "feel profile" row actually is.
	popup.add_separator()
	popup.add_section("Collision feel")
	popup.add_value_row("Profile", _profile_display())
	popup.add_action_row("Cycle collision profile (K)", func() -> void:
		var id := _root.cycle_phys_profile()
		if id != "":
			show_hint("Collision profile: %s" % id))
	popup.add_help_row(
		"How the world's impacts feel — bounciness, friction, and how much a hit "
		+ "spins you. 'cartoony' and 'grounded' are the two shipped profiles."
	)

	# Ship & scene actions.
	popup.add_separator()
	popup.add_check_row("Warp (X)", _root.model != null and _root.model.warp_active, func(on: bool) -> void:
		if _root.model != null:
			_root.model.warp_active = on
			show_hint("Warp %s — 8× speed" % ("ON" if on else "OFF")))
	popup.add_separator()
	popup.add_action_row("Rebuild ship in orbit (F4)", func() -> void: _root.respawn_player_ship())
	popup.add_action_row("Return to start point (R)", func() -> void: _root.respawn())
	popup.add_action_row("Restart scene (F5)", func() -> void: _root.restart_scene())


func _fill_combat_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Combat"
	popup.add_value_row("AI ships alive", str(_root.ai_live_count()))
	popup.add_action_row(
		"Lock nearest ship (T)" if _root.locked_target == null else "Release lock (T)",
		func() -> void: _root.toggle_lock()
	)
	popup.add_check_row("Face locked target", _root.facing_target, func(on: bool) -> void: _root.facing_target = on)
	popup.add_separator()
	popup.add_action_row("Spawn 1 AI ship", func() -> void: _spawn_quick(1))
	popup.add_action_row("Spawn 3 AI ships", func() -> void: _spawn_quick(3))
	popup.add_action_row("Spawn 6 AI ships", func() -> void: _spawn_quick(6))
	popup.add_action_row("Spawn random wave", func() -> void: _spawn_quick(3 + randi() % 6))
	popup.add_action_row("Spawn mother ship (6)", func() -> void:
		var ok := _root.spawn_mother_ship()
		show_hint("Mother ship launched" if ok else "No room for a mother ship"))
	popup.add_action_row("Kill all AI ships", func() -> void: _kill_all_ai())
	popup.add_action_row("AI test arena", func() -> void: _root.go_arena())
	popup.add_separator()
	# Custom spawn group: behaviour, formation, team, size.
	var behaviors: Array[String] = ["Hunt player", "Patrol", "Boid swarm", "Flee", "Guard", "Sniper"]
	popup.add_option_row(
		"Behaviour", behaviors, _spawn_behavior,
		func(idx: int) -> void: _spawn_behavior = idx
	)
	var forms: Array[String] = ["Scatter", "V-formation", "Line", "Sphere", "Trail"]
	popup.add_option_row(
		"Formation", forms, _spawn_formation,
		func(idx: int) -> void: _spawn_formation = idx
	)
	var teams: Array[String] = ["None", "Red", "Blue", "Green", "Gold"]
	popup.add_option_row(
		"Team", teams, _spawn_team,
		func(idx: int) -> void: _spawn_team = idx
	)
	popup.add_slider_row(
		"Group size", 1.0, 8.0, 1.0, float(_spawn_count),
		func(v: float) -> void: _spawn_count = int(v), "%.0f"
	)
	popup.add_action_row("Spawn group", func() -> void: _on_spawn_pressed())

	# Dynamic In-World Incidents (M4)
	popup.add_separator()
	popup.add_section("Dynamic incidents (M4)")
	popup.add_action_row("Trigger Distress Call (🚨)", func() -> void:
		_trigger_incident("distress_call"))
	popup.add_action_row("Trigger Pirate Raid (🎯)", func() -> void:
		_trigger_incident("pirate_raid"))
	popup.add_action_row("Trigger Cargo Request (📦)", func() -> void:
		_trigger_incident("cargo_request"))
	popup.add_action_row("Trigger Derelict Tumble (!)", func() -> void:
		_trigger_incident("derelict_tumble"))
	popup.add_action_row("Trigger Meteor Strike (🚨)", func() -> void:
		_trigger_incident("meteor_strike"))
	popup.add_action_row("Trigger Faction Skirmish (🎯)", func() -> void:
		_trigger_incident("faction_skirmish"))
	popup.add_action_row("Trigger Rare Drift (◆)", func() -> void:
		_trigger_incident("rare_drift"))
	popup.add_action_row("Clear active incidents", func() -> void:
		if _root.incident_director != null:
			_root.incident_director.clear_all()
			show_hint("All active incidents cleared"))


func _trigger_incident(type_name: String) -> void:
	if _root.incident_director != null:
		var inc := _root.incident_director.trigger_incident(type_name)
		if inc != null:
			show_hint("Triggered: %s" % inc.title)


func _spawn_quick(count: int) -> void:
	if _root._ai_spawner != null:
		_root._ai_spawner.spawn_near_player(count)
		show_hint("Spawned %d AI ship(s)" % count)


func _kill_all_ai() -> void:
	if _root._ai_spawner != null:
		_root._ai_spawner.kill_all()
		show_hint("All AI ships destroyed")


func _fill_gravity_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Gravity"
	var grav := _root.gravity
	if grav == null:
		popup.add_label_row("No gravity bodies here")
		return
	var mode := grav.mode
	for entry: Array in [
		["OFF", GravitySystem.GravityMode.OFF],
		["Normal", GravitySystem.GravityMode.NORMAL],
		["High", GravitySystem.GravityMode.HIGH],
	]:
		popup.add_radio_row(
			"Mode: " + String(entry[0]), mode == int(entry[1]), int(entry[1]),
			func(v: int) -> void: grav.mode = v
		)
	# No-pull ("orbit only"): bodies keep their orbits and nothing falls in.
	popup.add_check_row("Pull (things fall in)", grav.pull_enabled, func(_on: bool) -> void: _root.toggle_gravity_pull())
	popup.add_separator()
	var grav_str := 1.0
	if _root.model != null:
		grav_str = _root.model.gravity_strength
	for step: float in [0.5, 1.0, 2.0, 5.0, 10.0]:
		popup.add_radio_row(
			"Strength ×%.1f" % step, is_equal_approx(grav_str, step), int(step * 10),
			func(v: int) -> void: _root.model.gravity_strength = float(v) / 10.0
		)
	popup.add_separator()
	var grav_range := grav.range_multiplier
	for step: float in [0.5, 1.0, 2.0, 4.0, 8.0]:
		popup.add_radio_row(
			"Range ×%.1f" % step, is_equal_approx(grav_range, step), int(step * 10),
			func(v: int) -> void: grav.range_multiplier = float(v) / 10.0
		)
	popup.add_separator()
	var viz_on := _root._gravity_viz != null and _root._gravity_viz.is_showing()
	popup.add_check_row("Gravity visualizer (H)", viz_on, func(_on: bool) -> void: _root.toggle_gravity_viz())
	popup.add_check_row("Chaos (Y)", _root.gravity_chaos_on(), func(_on: bool) -> void: _root.toggle_gravity_chaos())


func _fill_orbit_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Orbit & time"
	popup.add_value_row("Orbit status", _orbit_readout())
	popup.add_action_row("Enter orbit (debug)", func() -> void: _root.enter_orbit())
	popup.add_action_row("Match circular speed", func() -> void: _root.match_circular_speed())
	popup.add_action_row("Spawn satellite (N)", func() -> void: _root.spawn_satellite())
	popup.add_action_row("Clear satellites (M)", func() -> void: _root.delete_satellites())
	popup.add_separator()
	if _root.model != null:
		var assist_rate := _root.model.orbital_assist_rate
		for step: float in FlightModel.ORBITAL_ASSIST_RATE_STEPS:
			popup.add_radio_row(
				"Assist strength ×%.1f" % step, is_equal_approx(assist_rate, step), int(step * 10),
				func(v: int) -> void: _root.model.orbital_assist_rate = float(v) / 10.0
			)
		popup.add_separator()
	# Fast orbits: a ship the assist is holding whips around its body far faster
	# than its own gravity would ever carry it. Ships only — nothing but a
	# [FlightModel] under orbital assist is affected, so rocks, debris and the
	# planets themselves keep their real motion.
	popup.add_check_row("Fast orbits", Session.fast_orbits,
		func(on: bool) -> void: _set_fast_orbits(on))
	popup.add_slider_row(
		"Orbit speed", 2.0, 20.0, 1.0, Session.orbit_speed_scale,
		func(v: float) -> void: _set_orbit_speed(v), "×%.0f"
	)
	var ts: int = int(_root.time_scale())
	for step: int in [1, 2, 4, 8, 10]:
		popup.add_radio_row(
			"Time ×%d" % step, ts == step, step,
			func(v: int) -> void: _root.set_time_scale(float(v))
		)


## One "Spawn: <archetype>" row per [enum LargeCraftGenerator.Archetype],
## built from [constant LargeCraftGenerator.ARCHETYPE_NAMES] so a new
## archetype added there shows up here for free.
func _fill_craft_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Large craft"
	popup.add_label_row("Debug spawner, ahead of the ship — full dial control is the large_craft_gen lab's job")
	popup.add_label_row("Size")
	for preset: int in FlightRoot.CRAFT_SIZE_LABELS.keys():
		popup.add_radio_row(
			FlightRoot.CRAFT_SIZE_LABELS[preset], _root.craft_size_preset == preset, preset,
			func(v: int) -> void: _root.craft_size_preset = v
		)
	popup.add_separator()
	for archetype: int in LargeCraftGenerator.ARCHETYPE_NAMES.keys():
		var label: String = LargeCraftGenerator.ARCHETYPE_NAMES[archetype]
		popup.add_action_row("Spawn: %s" % label, func() -> void: _root.spawn_large_craft(archetype))
	popup.add_separator()
	popup.add_action_row("Spawn 3 (mixed archetypes)", func() -> void: _root.spawn_large_craft_mix(3))
	popup.add_action_row("Clear large craft", func() -> void: _root.clear_large_craft())


func _fill_help_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Help"
	var ver := String(Engine.get_version_info()["string"])
	popup.add_value_row("Run", "Godot %s · seed %d" % [ver, Session.seed])
	popup.add_action_row("Controls card (? / F1)", func() -> void: _root.toggle_help())
	popup.add_action_row("Back to the hangar (Esc)", func() -> void: _root.return_to_hangar())


func _fill_trails_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Trails"
	popup.add_check_row("Player ship trail", _root.trail_player_on(), func(on: bool) -> void: _root.set_trail_player(on))
	popup.add_check_row("All ships trail", _root.trail_ships_on(), func(on: bool) -> void: _root.set_trail_ships(on))
	popup.add_section("Appearance")
	var len_slider := popup.add_slider_row(
		"Trail length", 0.5, 2.0, 0.1, Session.trail_length,
		func(v: float) -> void: Session.trail_length = v, "×%.1f"
	)
	# Trails read the length when built, so re-create the enabled ones on release.
	len_slider.drag_ended.connect(func(_changed: bool) -> void: _root.refresh_trails())


# --- Per-frame sync ---------------------------------------------------------

func _process(_delta: float) -> void:
	if _root == null or _root.model == null:
		return
	# active_model() is the controlled AI ship when the player is piloting one.
	var model := _root.active_model()
	var speed := model.forward_speed()
	_speed_label.text = "%d m/s" % roundi(speed)
	_speed_label.add_theme_color_override(
		"font_color",
		BuilderTheme.accent() if model.boost_level > 0.05 else BuilderTheme.text_strong_color()
	)
	# Ground speed: total velocity with sign based on forward direction.
	var ground_vel := model.velocity
	var forward := -model.global_transform.basis.z
	var ground_speed_signed = ground_vel.length() * sign(ground_vel.dot(forward))
	_ground_speed_label.text = "ground %+.0f m/s" % ground_speed_signed
	var gs_color := BuilderTheme.good() if ground_speed_signed >= 0.0 else BuilderTheme.warn()
	gs_color.a = 0.7
	_ground_speed_label.add_theme_color_override("font_color", gs_color)
	_throttle.set_actual(speed / maxf(model.top_speed, 1.0))
	# Only echo the stick when the player is not holding it: writing into a
	# widget the finger is on makes it stutter.
	_stick.set_external(Vector2(model.command.yaw * -1.0, model.command.pitch * -1.0))
	_view_chip.text = _root.camera_mode_label()
	match model.assist_mode:
		2:
			_assist_chip.text = "ASSIST"
			_assist_chip.add_theme_color_override("font_color", BuilderTheme.good())
		1:
			_assist_chip.text = "DAMPING"
			_assist_chip.add_theme_color_override("font_color", BuilderTheme.accent())
		_:
			_assist_chip.text = "MANUAL"
			_assist_chip.add_theme_color_override("font_color", BuilderTheme.warn())
	_target_label.text = _root.target_line()
	# Show damage status if any parts have been broken off.
	var dmg := _root.damage
	if dmg != null and dmg.broken_count() > 0:
		_damage_label.text = "⚠ %d part(s) lost" % dmg.broken_count()
		_damage_label.visible = true
	else:
		_damage_label.visible = false
	_overlay.queue_redraw()


## Mirror the throttle lever without emitting, for keyboard-driven changes.
func sync_throttle(value: float) -> void:
	if _throttle != null:
		_throttle.set_value_from(value, false)


func set_power(energy: float, heat: float) -> void:
	_energy = energy
	_heat = heat


func show_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


# --- Instruments ------------------------------------------------------------

func _draw_instruments() -> void:
	var camera := _root.camera_node()
	if camera == null or _root.model == null:
		return
	var centre := size * 0.5
	if Session.hud_reticle:
		_draw_reticle(centre)
	_draw_drift(camera, centre)
	if Session.hud_markers:
		_draw_markers(camera)
		_draw_lock_bracket(camera)
		_draw_ai_lock_brackets(camera)
	_draw_power_bars()
	if Session.hud_indicators:
		_draw_player_indicator(camera)


## The gunsight. An open cross rather than a dot: a dot vanishes against a bright
## planet, and the gap in the middle keeps the target visible while you aim.
func _draw_reticle(centre: Vector2) -> void:
	var col := BuilderTheme.accent()
	var r := RETICLE_RADIUS
	for i in 4:
		var dir := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][i] as Vector2
		_overlay.draw_line(centre + dir * (r * 0.45), centre + dir * r, col, 1.5, true)
	_overlay.draw_arc(centre, r * 1.5, 0.0, TAU, 32, Color(col, 0.35), 1.0, true)


## Where the ship is actually going, which with assist off is rarely where it is
## pointing. Drawn as a ring for prograde and a crossed ring for retrograde, so
## the two are distinguishable at a glance without colour.
func _draw_drift(camera: Camera3D, centre: Vector2) -> void:
	var model := _root.model
	var speed := model.velocity.length()
	if speed < 1.0:
		return
	var prograde := model.velocity / speed
	var forward := -camera.global_transform.basis.z
	var behind := prograde.dot(forward) < 0.0
	var world := camera.global_position + (prograde if not behind else -prograde) * 400.0
	var point := camera.unproject_position(world)

	# Clamp to a ring around the reticle so the marker never leaves the screen.
	var limit := minf(size.x, size.y) * DRIFT_CLAMP
	var offset := point - centre
	if offset.length() > limit:
		offset = offset.normalized() * limit
	point = centre + offset

	var col := BuilderTheme.good() if not behind else BuilderTheme.warn()
	# Fade the marker out as the ship stops drifting off its nose, so a
	# fly-by-wire pilot is not stared at by an instrument that never moves.
	var divergence := clampf(1.0 - prograde.dot(-model.global_transform.basis.z), 0.0, 1.0)
	col.a = clampf(0.25 + divergence * 6.0, 0.25, 1.0)
	_overlay.draw_arc(point, 7.0, 0.0, TAU, 20, col, 1.5, true)
	if behind:
		var d := Vector2(5.0, 5.0)
		_overlay.draw_line(point - d, point + d, col, 1.5, true)
		_overlay.draw_line(point - Vector2(d.x, -d.y), point + Vector2(d.x, -d.y), col, 1.5, true)


## Nav pips for the station and the planet: a bracket, a name and a range. The
## range figure is the whole point — apparent size tells you nothing about
## distance when the objects vary from 120 m to 1.4 km across.
func _draw_markers(camera: Camera3D) -> void:
	var font := get_theme_default_font()
	var font_size := 11
	for landmark in _root.landmarks():
		var world: Vector3 = landmark["position"]
		var distance := camera.global_position.distance_to(world)
		if distance > MARKER_RANGE or camera.is_position_behind(world):
			continue
		var point := camera.unproject_position(world)
		if not Rect2(Vector2.ZERO, size).grow(-4.0).has_point(point):
			continue
		var col: Color = landmark["color"]
		var r := 9.0
		# Four corner ticks: reads as a target bracket at any size and never
		# hides the thing it is bracketing.
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := point + Vector2(sx, sy) * r
				_overlay.draw_line(corner, corner - Vector2(sx * 4.0, 0.0), col, 1.5, true)
				_overlay.draw_line(corner, corner - Vector2(0.0, sy * 4.0), col, 1.5, true)
		var label := "%s  %s" % [landmark["name"], _range_text(distance)]
		_overlay.draw_string(
			font, point + Vector2(r + 4.0, 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col
		)


static func _range_text(metres: float) -> String:
	return "%.1f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)


## A weapons-lock bracket on the locked target: four corner ticks, a name, a
## range and the target's HP. Drawn whenever T has locked a ship.
func _draw_lock_bracket(camera: Camera3D) -> void:
	var target := _root.locked_target
	if target == null or not is_instance_valid(target):
		return
	var world: Vector3 = target.global_position
	if camera.is_position_behind(world):
		return
	var point := camera.unproject_position(world)
	var font := get_theme_default_font()
	var col := BuilderTheme.warn()
	var r := 11.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := point + Vector2(sx, sy) * r
			_overlay.draw_line(corner, corner - Vector2(sx * 5.0, 0.0), col, 2.0, true)
			_overlay.draw_line(corner, corner - Vector2(0.0, sy * 5.0), col, 2.0, true)
	var dist := camera.global_position.distance_to(world)
	var label := "LOCK  %s" % _range_text(dist)
	if target is AiShip:
		var ai := target as AiShip
		label = "LOCK  %s  %s" % [ai.preset_name, _range_text(dist)]
		var hp_frac := ai.hp / maxf(ai.max_hp, 1.0)
		label += "  %d%%" % roundi(hp_frac * 100.0)
	else:
		label = "LOCK  %s" % _range_text(dist)
	_overlay.draw_string(
		font, point + Vector2(r + 5.0, 5.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col
	)


## Small brackets on every AI ship that has locked a target of its own, so the
## fight reads the way the player's own lock does: you can see who has a bead on
## whom. Lighter than the player's lock so the two never compete for attention.
func _draw_ai_lock_brackets(camera: Camera3D) -> void:
	if _root._ai_spawner == null:
		return
	var font := get_theme_default_font()
	var col := BuilderTheme.text_dim()
	col.a = 0.6
	var r := 6.0
	for ship in _root._ai_spawner._ships:
		if not is_instance_valid(ship) or not ship._alive or ship.locked_enemy == null:
			continue
		var world: Vector3 = ship.global_position
		if camera.is_position_behind(world):
			continue
		var point := camera.unproject_position(world)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := point + Vector2(sx, sy) * r
				_overlay.draw_line(corner, corner - Vector2(sx * 3.0, 0.0), col, 1.0, true)
				_overlay.draw_line(corner, corner - Vector2(0.0, sy * 3.0), col, 1.0, true)
		var dist := camera.global_position.distance_to(world)
		_overlay.draw_string(
			font, point + Vector2(r + 4.0, 4.0), "LOCKED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col
		)


## Capacitor and heat, as two short bars beneath the speed readout. They share the
## corner with the speed because they answer the same question — can I do the
## thing I am about to do.
func _draw_power_bars() -> void:
	var w := 118.0
	var h := 7.0
	var x := size.x - w - float(BuilderTheme.PAD)
	var y := size.y * 0.5 - 16.0
	_draw_bar(Rect2(x, y, w, h), _energy, BuilderTheme.accent(), "CAP")
	_draw_bar(Rect2(x, y + h + 12.0, w, h), _heat, BuilderTheme.gauge_color(1.0 - _heat), "HEAT")


func _draw_bar(rect: Rect2, fraction: float, color: Color, label: String) -> void:
	_overlay.draw_rect(rect, Color(BuilderTheme.bg_deep(), 0.55), true)
	_overlay.draw_rect(
		Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)),
		color, true
	)
	_overlay.draw_rect(rect, BuilderTheme.border(), false, 1.0)
	_overlay.draw_string(
		get_theme_default_font(), rect.position + Vector2(0.0, -3.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BuilderTheme.text_dim()
	)


## The external views (far, planet, free, external, target) can put the player's
## ship entirely off frame. A constant-pixel-size locator pins to the screen edge
## with an arrow back toward the ship — it never grows or shrinks with the camera
## and never leaves the viewport. Hidden in cockpit, chase and rear, where the
## ship is always in frame.
const PLAYER_INDICATOR_SIZE := 26.0

func _draw_player_indicator(camera: Camera3D) -> void:
	if not player_indicator_active():
		return
	var ship := _root.active_ship_node()
	if ship == null or not is_instance_valid(ship):
		return
	var to_ship := ship.global_position - camera.global_position
	if to_ship.length_squared() < 1.0:
		return
	# Project a far point on the camera→ship ray rather than the ship itself:
	# unproject of a point behind the camera mirrors into the wrong screen
	# quadrant, while a point in front of it always lands on the right side.
	var far_point := camera.global_position + to_ship.normalized() * 400.0
	var raw := camera.unproject_position(far_point)
	var margin := PLAYER_INDICATOR_SIZE + 10.0
	var clamped := Vector2(
		clampf(raw.x, margin, size.x - margin),
		clampf(raw.y, margin, size.y - margin)
	)
	var dir := raw - clamped
	var col := BuilderTheme.accent()
	var outline := Color(0.03, 0.05, 0.1, 0.85)
	var r := PLAYER_INDICATOR_SIZE
	if dir.length() < 2.0:
		# The ship is on screen: a big diamond with a dark outline and a thin
		# ring, so it reads as "you are here" without hiding the hull.
		var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008)
		_overlay.draw_arc(clamped, r * 1.35 * pulse, 0.0, TAU, 40, Color(col, 0.4), 1.5, true)
		_draw_indicator_diamond(clamped, r, col, outline)
	else:
		# Off screen: clamp to the edge and draw a large chevron pointing back at
		# the ship's true screen direction.
		_draw_indicator_arrow(clamped, dir.angle(), r, col, outline)
	_overlay.draw_string(
		get_theme_default_font(), clamped + Vector2(-12.0, r + 16.0), "YOU",
		HORIZONTAL_ALIGNMENT_CENTER, 24, 11, col
	)


func _draw_indicator_diamond(at: Vector2, r: float, col: Color, outline: Color) -> void:
	var big := PackedVector2Array([
		at + Vector2(0.0, -r), at + Vector2(r, 0.0), at + Vector2(0.0, r), at + Vector2(-r, 0.0),
	])
	var small := PackedVector2Array([
		at + Vector2(0.0, -r * 0.66), at + Vector2(r * 0.66, 0.0),
		at + Vector2(0.0, r * 0.66), at + Vector2(-r * 0.66, 0.0),
	])
	_overlay.draw_colored_polygon(big, outline)
	_overlay.draw_colored_polygon(small, col)


func _draw_indicator_arrow(at: Vector2, angle: float, r: float, col: Color, outline: Color) -> void:
	var dirv := Vector2.from_angle(angle)
	var tip := at + dirv * r
	var lo := at + dirv.rotated(2.4) * r
	var hi := at + dirv.rotated(-2.4) * r
	var chevron := PackedVector2Array([tip, lo, hi])
	_overlay.draw_colored_polygon(chevron, outline)
	# A bright inner chevron, inset, so the arrow reads over bright scenery too.
	var inner_tip := at + dirv * r * 0.6
	var inner_lo := at + dirv.rotated(2.6) * r * 0.6
	var inner_hi := at + dirv.rotated(-2.6) * r * 0.6
	_overlay.draw_colored_polygon(PackedVector2Array([inner_tip, inner_lo, inner_hi]), col)


## True when the external-view player indicator is armed: every mode except the
## three that always keep the player's ship in frame.
func player_indicator_active() -> bool:
	var mode := _root.camera_mode() if _root != null else FlightCamera.Mode.CHASE
	return mode != FlightCamera.Mode.COCKPIT \
		and mode != FlightCamera.Mode.REAR \
		and mode != FlightCamera.Mode.CHASE
