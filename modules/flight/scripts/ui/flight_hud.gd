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
var _hit_words: HitWords
## Persona-style shouts from the player's ship ([PlayerCallouts]).
var _callouts: PlayerCallouts
var _menu: FlightMenu
var _fire_button: Button
var _boost_button: Button
var _weapon_button: Button
## A timed level's clock, under the weapon button.
var _timer_label: Label
var _assist_chip: Button
var _view_chip: Button
var _speed_label: Label
var _target_label: Label
var _hint_label: Label
var _hint_tween: Tween = null
## Seconds a hint stays up before it fades.
const HINT_HOLD := 6.0
var _damage_label: Label
var _ground_speed_label: Label

var _energy := 1.0
var _heat := 0.0

## Debug toggles — small checkboxes on the right edge to isolate rendering issues.
var _debug_panel: VBoxContainer = null
## Scrolls [member _debug_panel]; this is what shows and hides.
var _debug_scroll: ScrollContainer = null
## Top-bar chips that fold into [member _tools_chip] on a narrow screen.
var _debug_chips: Array[Control] = []
var _tools_chip: Button = null
## Tap-outside-to-close, one-at-a-time and fit-to-screen for every panel.
var _modals: FlightModalHost = null
var _debug_toggles: Dictionary = {}
var _event_container: CenterContainer = null

## Floating arcade damage numbers & health ghost bars
var _damage_numbers: Array[Dictionary] = []
var _hp_ghost := 1.0
var _shield_ghost := 1.0
var _game_over_modal: Control = null

## Modular HUD components
var _radar_display: RadarDisplay = null
var _combat_modal: CombatSettingsModal = null
var _juice_panel: JuiceSettingsPanel = null
var _perf_panel: PerformancePanel = null
var _stats_panel: CombatStatsPanel = null
var _controls_panel: ControlsPanel = null
var _fonts_panel: MobileHudFontsPanel = null
var _scenario_panel: ScenarioPanel = null
var _bug_hunt_panel: BugHuntPanel = null
var _fly_as_panel: FlyAsPanel = null
var _log_census_panel: LogCensusPanel = null
var _difficulty_panel: DifficultyPanel = null
## The real phone layout (see [method set_mobile_layout]) and whether it is up.
var _mobile_hud: MobileHud = null
var _mobile_layout := false
## Which desktop widgets were visible when the mobile layout took over, so
## leaving it puts back exactly what was there.
var _desktop_visible := {}
var _weapon_selector: WeaponSelector = null

## Visual & Palette controls

var _palette_chip: Button = null
var _palette_preview_dots: HBoxContainer = null
var _style_chip: Button = null
var _mobile_chip: Button = null
var _palette_drawer: PanelContainer = null
var _swatches_grid: HFlowContainer = null
var _palette_tabs_container: HBoxContainer = null
var _swatch_section_label: Label = null


func _ready() -> void:
	_root = owner as FlightRoot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = FlightTheme.create_theme(size, Session.mobile_view_fit)
	_load_spawn_prefs()
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
	# Comic shouts pinned to the world, over the instruments, in both layouts.
	_hit_words = HitWords.new()
	_hit_words.setup(func() -> Camera3D: return _root.camera_node() if _root != null else null)
	add_child(_hit_words)
	_callouts = PlayerCallouts.new()
	_callouts.setup(
		func() -> Camera3D: return _root.camera_node() if _root != null else null,
		func() -> Vector3: return _root.active_ship_node().global_position 			if _root != null and _root.active_ship_node() != null else Vector3.INF
	)
	add_child(_callouts)

	_build_top_bar()
	_build_palette_drawer()
	_build_readouts()
	_build_controls()
	_build_event_container()
	_build_debug_panel()
	_build_rear_view_display()
	_build_game_over_modal()
	_build_radar()
	_build_combat_modal()
	_build_juice_panel()
	_modals = FlightModalHost.new(self)
	for panel: Control in [_debug_scroll, _combat_modal, _juice_panel, _palette_drawer]:
		if panel != null:
			_modals.manage(panel)
	# Come back in the layout the player left in.
	if bool(Session.pref("mobile_layout", OS.has_feature("mobile"))):
		set_mobile_layout.call_deferred(true)


func _build_event_container() -> void:
	_event_container = CenterContainer.new()
	_event_container.name = "EventBubbleContainer"
	_event_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Under the top band and the health panel, not across them.
	_event_container.offset_top = 200.0
	_event_container.custom_minimum_size = Vector2(0.0, 60.0)
	add_child(_event_container)


func get_event_container() -> Control:
	return _event_container


func _build_debug_panel() -> void:
	# Debug panel: toggles on the right edge to isolate rendering issues.
	# A scrolling column down the right edge, so it fits a short phone screen.
	_debug_scroll = ScrollContainer.new()
	_debug_scroll.name = "DebugScroll"
	_debug_scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_debug_scroll.offset_right = -BuilderTheme.PAD
	_debug_scroll.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_debug_scroll.offset_bottom = -BuilderTheme.PAD
	_debug_scroll.offset_left = -180.0
	_debug_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_debug_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_scroll.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.panel_bg(), BuilderTheme.border(), 6)
	)
	_debug_scroll.visible = false
	add_child(_debug_scroll)
	_debug_panel = VBoxContainer.new()
	_debug_panel.name = "DebugToggles"
	_debug_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_debug_scroll.add_child(_debug_panel)

	var lbl := Label.new()
	lbl.text = "DEBUG"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", BuilderTheme.warn())
	_debug_panel.add_child(lbl)

	_add_debug_button("🏠 Hangar", func() -> void: _root.return_to_hangar())
	_add_debug_button("🎮 Controls", func() -> void: toggle_controls_panel())
	_add_debug_button("🕹 Next movement profile (U)", func() -> void: _root.cycle_move_profile())
	_add_debug_button("📱 Mobile HUD (F1 back)", func() -> void: set_mobile_layout(true))
	_add_debug_button("⚡ Performance", func() -> void: toggle_perf_panel())
	_add_setting_check("🎯 Auto-shoot the whole launch (off = once per launch)", JuiceSettings.sling_auto_shoot >= 1.5,
		func(on: bool) -> void: JuiceSettings.set_float("sling_auto_shoot", 2.0 if on else 1.0))
	_add_setting_check("🎯 Tap auto-aims (slingshot)", JuiceSettings.sling_tap_auto_aim,
		func(on: bool) -> void: JuiceSettings.set_effect("sling_tap_auto_aim", on))
	_add_setting_check("🔮 Power-ups from kills", JuiceSettings.power_ups,
		func(on: bool) -> void: JuiceSettings.set_effect("power_ups", on))
	if GameDefaults.can_bake():
		_add_setting_check("💾 Settings save into the game's defaults", GameDefaults.auto_bake, _set_auto_bake)
	_add_debug_button("🎓 Tutorial", func() -> void: _root.start_tutorial())
	_add_debug_button("🎨 Palette", func() -> void: toggle_palette_menu())
	if GameDefaults.can_bake():
		_add_debug_button("💾 Save as game defaults", _bake_game_defaults)
	_add_debug_button("↺ Reset to game defaults", _reset_to_game_defaults)
	_add_debug_button("🔤 HUD fonts", func() -> void: toggle_fonts_panel())
	_add_debug_button("⚔ Scenarios", func() -> void: toggle_scenario_panel())
	_add_debug_button("🧪 Stats", func() -> void: toggle_stats_panel())
	_add_debug_button("🎬 Juice", func() -> void: toggle_juice_panel())
	_add_debug_button("🛩 Fly as…", func() -> void: toggle_fly_as_panel())
	_add_debug_button("🐞 Bug hunt", func() -> void: toggle_bug_hunt_panel())
	_add_debug_button("Log census", func() -> void: toggle_log_census_panel())
	_add_debug_button("🎚 Difficulty", func() -> void: toggle_difficulty_panel())

	_add_debug_toggle("Plumes", true)
	_add_debug_toggle("Halos", true)
	_add_debug_toggle("Tracers", true)
	_add_debug_toggle("Stars", true)
	_add_debug_toggle("Nebula", true)
	_add_debug_toggle("Planet", true)
	_add_debug_toggle("Atmo", true)
	_add_debug_toggle("SafeAtmo", true)
	_add_debug_toggle("AltSurface", Session.planet_surface_alt)
	_add_debug_toggle("Station", true)
	_add_debug_toggle("SkyDome", true)
	_add_debug_toggle("Sun", true)
	_add_debug_toggle("Asteroids", true)
	_add_debug_toggle("Drift", true)
	_add_debug_toggle("Reticle", Session.hud_reticle)
	_add_debug_toggle("Markers", Session.hud_markers)
	_add_debug_toggle("ShipGeo", true)
	_add_debug_toggle("!!! ALL !!!", true)
	# Effect layers, each independently switchable so the new audio/VFX/toon
	# work can be compared against the original look without a code change.
	_add_debug_toggle("SciFiSfx", FxSettings.library_sounds)
	_add_debug_toggle("AddonVFX", FxSettings.addon_vfx)
	_add_debug_toggle("Toon", ToonOverride.enabled())

	# D key toggles the panel.


## Toggles whose state already lives in its own saved setting, so the debug
## strip doesn't keep a second copy that could disagree with it.
const DEBUG_TOGGLES_SAVED_ELSEWHERE := ["AltSurface", "Reticle", "Markers", "SciFiSfx", "AddonVFX", "Toon"]


func _add_debug_button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(action)
	_debug_panel.add_child(b)


## [member GameDefaults.auto_bake], remembered in the session prefs.
func _set_auto_bake(on: bool) -> void:
	GameDefaults.auto_bake = on
	Session.prefs["auto_bake"] = on
	Session.save_to_disk()


## A checkbox in the debug column bound straight to a saved setting: it
## shows [param value] and calls [param on_toggle] with each change. Unlike
## [method _add_debug_toggle] the setting's own class persists it.
func _add_setting_check(label: String, value: bool, on_toggle: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = value
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", 10)
	cb.toggled.connect(on_toggle)
	_debug_panel.add_child(cb)


func _add_debug_toggle(label: String, default: bool) -> void:
	var cb := CheckBox.new()
	cb.text = label
	var value := default
	if not label in DEBUG_TOGGLES_SAVED_ELSEWHERE:
		value = bool(Session.pref("debug_" + label, default))
		if value != default:
			# Put a saved non-default back once the scene it drives exists.
			_on_debug_toggle.call_deferred(label, value)
	cb.button_pressed = value
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
	if not label in DEBUG_TOGGLES_SAVED_ELSEWHERE:
		Session.prefs["debug_" + label] = on
	match label:
		"Plumes": _root.set_debug_visible("plumes", on)
		"Halos": _root.set_debug_visible("halos", on)
		"Tracers": _root.set_debug_visible("tracers", on)
		"Stars": _root.set_debug_visible("stars", on)
		"Nebula": _root.set_debug_visible("nebula", on)
		"Planet": _root.set_debug_visible("planet", on)
		"Atmo": _root.set_debug_visible("atmo", on)
		"SafeAtmo": Planet.swap_all_atmosphere_shaders(on)
		"AltSurface":
			Planet.swap_all_surface_shaders(on)
			Session.planet_surface_alt = on
			Session.planet_surface_style = 1 if on else 0
			Session.save_to_disk()
		"Station": _root.set_debug_visible("station", on)
		"SkyDome": _root.set_debug_visible("skydome", on)
		"Sun": _root.set_debug_visible("sun", on)
		"ShipGeo": _root.set_debug_visible("shipgeo", on)
		"!!! ALL !!!": _root.set_debug_visible("everything", on)
		"Asteroids": _root.set_debug_visible("asteroids", on)
		"Drift": _root.set_debug_visible("drift", on)
		"Reticle": Session.hud_reticle = on
		"Markers": Session.hud_markers = on
		"SciFiSfx":
			FxSettings.set_library_sounds(on)
			if _root.audio != null:
				_root.audio.refresh_bank()
		"AddonVFX": FxSettings.set_addon_vfx(on)
		"Toon":
			# set_toon_shading re-applies the style, which FlightRoot listens for
			# and restyles the hull from — no manual push needed here.
			ToonOverride.set_enabled(on)


func toggle_debug_panel() -> void:
	if _debug_scroll != null:
		_debug_scroll.visible = not _debug_scroll.visible


## Close whatever panel or toolbar popup is open. Returns true if something
## was closed. Back (phone) and Escape call this first.
func close_top_panel() -> bool:
	if _menu != null and _menu.close_open():
		return true
	return _modals != null and _modals.close_top()


## Write the current tuning into the files that ship with the game.
func _bake_game_defaults() -> void:
	var n := GameDefaults.bake()
	if n < 0:
		show_hint("Only a desktop run from the project can save game defaults")
	else:
		show_hint("Saved %d settings files as the game's defaults" % n)


## Drop the player's own settings: everything goes back to what ships.
func _reset_to_game_defaults() -> void:
	Session.reset_to_defaults()
	show_hint("Settings reset to the game defaults — restarting")
	if _root != null:
		_root.get_tree().reload_current_scene.call_deferred()


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
		func(v: float) -> void:
			Session.ship_scale = v
			Session.save_to_disk(),
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

	# Planetary destruction fineness dial
	popup.add_separator()
	popup.add_section("Planetary destruction")
	popup.add_slider_row(
		"Break fineness", 0.5, 3.0, 0.25, Session.planet_break_fineness,
		func(v: float) -> void:
			Session.planet_break_fineness = v
			Session.save_to_disk()
			show_hint("Planet break fineness: ×%.2f" % v),
		"×%.2f"
	)
	popup.add_check_row(
		"Radiant mantle glow", Session.planet_debris_glow,
		func(on: bool) -> void:
			Session.planet_debris_glow = on
			Session.save_to_disk()
			PlanetDebrisBuilder.set_debris_glow_enabled(on, _root)
			show_hint("Planet debris glow: %s" % ("ON" if on else "OFF (Max FPS)"))
	)
	popup.add_help_row(
		"Controls piece count and radiant emission when a planet breaks. "
		+ "Disable glow if experiencing frame drops near shattered debris."
	)
	popup.add_action_row("💥 Shatter nearest planet (Shift+P)", func() -> void:
		_root.shatter_nearest_planet()
	)

	# World-build quality dials: read while the scene builds, so changing them
	# needs a restart (the scale presets above set the precedent).
	popup.add_section("Quality (restart to apply)")
	popup.add_slider_row(
		"Star density", 0.25, 2.0, 0.25, Session.star_density,
		func(v: float) -> void:
			Session.star_density = v
			Session.save_to_disk(),
		"×%.2f"
	)
	popup.add_slider_row(
		"Star size", 0.5, 3.0, 0.25, Session.star_size_mult,
		func(v: float) -> void:
			Session.star_size_mult = v
			Session.save_to_disk(),
		"×%.2f"
	)
	popup.add_slider_row(
		"Distant rocks", 0.0, 2.0, 0.25, Session.asteroid_density,
		func(v: float) -> void:
			Session.asteroid_density = v
			Session.save_to_disk(),
		"×%.2f"
	)
	popup.add_check_row("Backdrop (corona, galaxy, dust)", Session.render_backdrop,
		func(on: bool) -> void:
			Session.render_backdrop = on
			Session.save_to_disk())
	popup.add_check_row("Enhanced lighting (shadows, rim)", Session.enhanced_lighting,
		func(on: bool) -> void:
			Session.enhanced_lighting = on
			Session.save_to_disk())
	popup.add_check_row("Cinematic sun lighting (Galaxy on Fire)", Session.cinematic_lighting,
		func(_on: bool) -> void: _root.toggle_cinematic_lighting())
	popup.add_separator()
	popup.add_section("Star Style (live)")
	var current_style = StyleManager.instance().current_profile
	if current_style != null:
		popup.add_slider_row(
			"Star Size", 0.5, 10.0, 0.5, current_style.star_size,
			func(v: float) -> void:
				current_style.star_size = v
				StyleManager.instance().style_changed.emit(current_style)
		)
		popup.add_slider_row(
			"Star Cartooniness", 0.0, 1.0, 0.1, current_style.star_five_point,
			func(v: float) -> void:
				current_style.star_five_point = v
				StyleManager.instance().style_changed.emit(current_style)
		)
	popup.add_separator()
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

## The spawn panel's remembered choices, kept between popup opens and saved
## across launches (see [method _set_spawn_pref]).
var _spawn_behavior := 0
var _spawn_formation := 0
var _spawn_count := 3
## The team the spawn popup assigns spawned ships to (1 = Red).
var _spawn_team := 1


## Record one spawn-panel choice in [member Session.prefs] and keep the live
## value in step.
func _set_spawn_pref(key: String, value: int) -> void:
	Session.prefs["spawn_" + key] = value
	match key:
		"behavior": _spawn_behavior = value
		"formation": _spawn_formation = value
		"count": _spawn_count = value
		"team": _spawn_team = value


func _load_spawn_prefs() -> void:
	_spawn_behavior = int(Session.pref("spawn_behavior", _spawn_behavior))
	_spawn_formation = int(Session.pref("spawn_formation", _spawn_formation))
	_spawn_count = int(Session.pref("spawn_count", _spawn_count))
	_spawn_team = int(Session.pref("spawn_team", _spawn_team))


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
	Session.save_to_disk()
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
	Session.save_to_disk()
	if _root.model == null:
		return
	_root.model.set_control_mode(_root.model.control_mode)
	show_hint("Arcade pivot ×%.2f — %.0f°/s" % [mult, rad_to_deg(_root.model.turn_rate)])


## Toggle the fast-orbit dial. Read live by the flight model, so ships already
## orbiting change speed the moment it flips.
func _set_fast_orbits(on: bool) -> void:
	Session.fast_orbits = on
	Session.save_to_disk()
	show_hint("Fast orbits: %s" % ("ON" if on else "OFF"))


## How much faster than a real circular orbit the fast-orbit dial flies a held
## ship. The flight model pairs it with the matching k² of pull, so the orbit
## stays the same circle — just taken sooner.
func _set_orbit_speed(scale: float) -> void:
	Session.orbit_speed_scale = maxf(scale, 1.0)
	Session.save_to_disk()
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


func _build_game_over_modal() -> void:
	_game_over_modal = Control.new()
	_game_over_modal.name = "GameOverModal"
	_game_over_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_modal.visible = false

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_modal.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_modal.add_child(center)

	# A sprayed sticker in the mobile HUD's look (see [PopupSkin]), rimmed in
	# its hull colour, instead of the old generic rounded box and emoji.
	var hull_col := MobileHudProfiles.color("hull")
	var panel := PanelContainer.new()
	panel.name = "WreckedPanel"
	panel.custom_minimum_size = Vector2(440, 230)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "WRECKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", hull_col)
	# A slight tilt, like a tag sprayed in a hurry.
	title.pivot_offset = Vector2(200, 26)
	title.rotation_degrees = -3.0
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Your hull gave out. The ship is scrap."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	vbox.add_child(sub)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 18)
	vbox.add_child(btn_box)

	var b_respawn := Button.new()
	b_respawn.name = "Respawn"
	b_respawn.text = "RESPAWN  [R]"
	b_respawn.custom_minimum_size = Vector2(176, 52)
	b_respawn.focus_mode = Control.FOCUS_NONE
	b_respawn.add_theme_font_size_override("font_size", 17)
	b_respawn.pressed.connect(_on_respawn_pressed)
	btn_box.add_child(b_respawn)

	var b_hangar := Button.new()
	b_hangar.name = "Builder"
	b_hangar.text = "BUILDER  [B]"
	b_hangar.custom_minimum_size = Vector2(160, 52)
	b_hangar.focus_mode = Control.FOCUS_NONE
	b_hangar.add_theme_font_size_override("font_size", 15)
	b_hangar.pressed.connect(func() -> void:
		if _root != null:
			_root.return_to_hangar()
	)
	btn_box.add_child(b_hangar)

	add_child(_game_over_modal)
	PopupSkin.skin(panel, hull_col)
	# The respawn button is the one to press: filled in, not just rimmed.
	var go := PopupSkin._button_box(MobileHudProfiles.color("shield"), Color.WHITE, 2, 6)
	b_respawn.add_theme_stylebox_override("normal", go)
	b_respawn.add_theme_stylebox_override("hover", PopupSkin._button_box(MobileHudProfiles.color("shield").lightened(0.2), Color.WHITE, 2, 6))
	b_respawn.add_theme_color_override("font_color", Color.WHITE)


## The popup's respawn button: the same full respawn as the R key (the button
## used to rebuild the ship but leave the popup up and the pilot "dead").
func _on_respawn_pressed() -> void:
	if _root != null:
		_root.respawn_player_ship()


func _build_radar() -> void:
	_radar_display = RadarDisplay.new()
	_radar_display.name = "RadarDisplay"
	_radar_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_display.target_selected.connect(func(target: Node3D) -> void:
		if _root != null and target != null and is_instance_valid(target):
			_root.locked_target = target
			_root.facing_target = true
			var t_name: String = target.preset_name if target is AiShip else target.name
			show_hint("Target Locked: %s" % t_name)
	)
	add_child(_radar_display)


func _build_combat_modal() -> void:
	_combat_modal = CombatSettingsModal.new()
	_combat_modal.name = "CombatSettingsModal"
	_combat_modal.set_anchors_preset(Control.PRESET_CENTER)
	_combat_modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_combat_modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_combat_modal.visible = false
	_combat_modal.setting_changed.connect(_on_combat_setting_changed)
	_combat_modal.action_triggered.connect(_on_combat_action_triggered)
	add_child(_combat_modal)
	PopupSkin.skin(_combat_modal)


func _build_juice_panel() -> void:
	_juice_panel = JuiceSettingsPanel.new()
	_juice_panel.name = "JuiceSettingsPanel"
	_juice_panel.set_anchors_preset(Control.PRESET_CENTER)
	_juice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_juice_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_juice_panel.visible = false
	add_child(_juice_panel)
	PopupSkin.skin(_juice_panel)


func toggle_juice_panel() -> void:
	if _juice_panel != null:
		_juice_panel.visible = not _juice_panel.visible


func toggle_stats_panel() -> void:
	if _stats_panel == null:
		_stats_panel = CombatStatsPanel.new()
		_stats_panel.name = "CombatStatsPanel"
		_stats_panel.setup(_root)
		_center_panel(_stats_panel)
	_stats_panel.visible = not _stats_panel.visible


## Movement profile, camera gestures and every control dial ([ControlsPanel]).
func toggle_controls_panel() -> void:
	if _controls_panel == null:
		_controls_panel = ControlsPanel.new()
		_controls_panel.name = "ControlsPanel"
		_controls_panel.setup(_root)
		_center_panel(_controls_panel)
	_controls_panel.visible = not _controls_panel.visible


func toggle_fonts_panel() -> void:
	if _fonts_panel == null:
		_fonts_panel = MobileHudFontsPanel.new()
		_fonts_panel.name = "MobileHudFontsPanel"
		_center_panel(_fonts_panel)
	_fonts_panel.visible = not _fonts_panel.visible


func toggle_scenario_panel() -> void:
	if _root == null or _root.scenarios == null:
		return
	if _scenario_panel == null:
		_scenario_panel = ScenarioPanel.new()
		_scenario_panel.name = "ScenarioPanel"
		_scenario_panel.setup(_root.scenarios, _root)
		_center_panel(_scenario_panel)
	_scenario_panel.visible = not _scenario_panel.visible


## The 🐞 Bug hunt panel over the flight root's [BugHunt].
func toggle_bug_hunt_panel() -> void:
	if _root == null or _root.bug_hunt == null:
		return
	if _bug_hunt_panel == null:
		_bug_hunt_panel = BugHuntPanel.new()
		_bug_hunt_panel.name = "BugHuntPanel"
		_bug_hunt_panel.setup(_root.bug_hunt)
		_center_panel(_bug_hunt_panel)
	_bug_hunt_panel.visible = not _bug_hunt_panel.visible


## The 🛩 Fly as panel: fly a ship of another size and weapon.
## The Log census panel: what writes to the log the most (see [LogCensus]).
func toggle_log_census_panel() -> void:
	if _log_census_panel == null:
		_log_census_panel = LogCensusPanel.new()
		_log_census_panel.name = "LogCensusPanel"
		_center_panel(_log_census_panel)
	_log_census_panel.visible = not _log_census_panel.visible


## The 🎚 Difficulty panel: the shipped difficulty table, editable while flying.
func toggle_difficulty_panel() -> void:
	if _difficulty_panel == null:
		_difficulty_panel = DifficultyPanel.new()
		_difficulty_panel.name = "DifficultyPanel"
		_center_panel(_difficulty_panel)
	_difficulty_panel.visible = not _difficulty_panel.visible


func toggle_fly_as_panel() -> void:
	if _root == null:
		return
	if _fly_as_panel == null:
		_fly_as_panel = FlyAsPanel.new()
		_fly_as_panel.name = "FlyAsPanel"
		_fly_as_panel.setup(_root)
		_center_panel(_fly_as_panel)
	_fly_as_panel.visible = not _fly_as_panel.visible


func _center_panel(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	panel.z_index = 20
	add_child(panel)
	PopupSkin.skin(panel)
	if _modals != null:
		_modals.manage(panel)


func mobile_layout_active() -> bool:
	return _mobile_layout


## Show the mobile HUD's speed as a meter up to [param max_mps] (0 = back to
## the big number). Kept for a mobile HUD made later.
var _speed_meter_max := 0.0


func set_speed_meter(max_mps: float) -> void:
	_speed_meter_max = maxf(max_mps, 0.0)
	if _mobile_hud != null:
		_mobile_hud.speed_meter_max = _speed_meter_max


## Pop a comic shout at [param world_pos] (see [HitWords]).
func hit_word(word: String, world_pos: Vector3, col: Color, scale := 1.0) -> void:
	if _hit_words != null:
		_hit_words.pop(word, world_pos, col, scale)


## Add a banner (the tutorial's) under the world shouts and callouts, so
## those still read over it.
func add_banner(c: Control) -> void:
	add_child(c)
	if _hit_words != null:
		move_child(c, _hit_words.get_index())


## A comic "!"/"?" over [param ship] (see [method HitWords.mark]).
func mark_word(glyph: String, ship: Node3D, height: float, col: Color) -> void:
	if _hit_words != null:
		_hit_words.mark(glyph, ship, height, col)


## A Persona-style callout from the player's ship (see [PlayerCallouts]).
func callout(text: String, col := Color("ff2a4a")) -> void:
	if _callouts != null:
		_callouts.say(text, col)


## The movement profile ([enum FlightRoot.MoveProfile]) the HUD is laid out for.
var _move_profile := 0


## Show only the controls the movement profile uses: swipe and slingshot fly
## off the bare screen, so the stick, throttle, fire/boost/weapon buttons and
## the speed/target read-outs go. Bars, markers, the menu and every debug
## panel stay.
func set_move_profile(p: int) -> void:
	_move_profile = p
	_apply_move_profile()
	if _mobile_hud != null:
		_mobile_hud.set_move_profile(p)


func _apply_move_profile() -> void:
	if _mobile_layout:
		return
	var shown := not FlightRoot.profile_is_one_thumb(_move_profile)
	for c: Control in [_stick, _throttle, _fire_button, _boost_button, _weapon_button, _speed_label, _ground_speed_label, _target_label]:
		if c != null:
			c.visible = shown
	# FPS: the stick's push is the speed, so no throttle lever.
	if _throttle != null and _move_profile == FlightRoot.MoveProfile.FPS:
		_throttle.visible = false


## Swap the desktop chrome for the real phone layout ([MobileHud]) or back.
## The drawn instruments (reticle, markers, lock brackets, damage numbers),
## the hint line, event bubbles and the game-over card stay up in both; every
## other desktop widget is hidden and restored as it was. F1 leaves, and so
## does the HUD's own small menu button, for a phone with no keyboard.
func set_mobile_layout(on: bool) -> void:
	if on == _mobile_layout:
		return
	_mobile_layout = on
	Session.prefs["mobile_layout"] = on
	if on:
		if _mobile_hud == null:
			_mobile_hud = MobileHud.new()
			_mobile_hud.setup(_root)
			_mobile_hud.set_move_profile(_move_profile)
			_mobile_hud.speed_meter_max = _speed_meter_max
			# In a level or sandbox flight from the game's menu, the menu
			# button pauses (like the MAP button); in the workbench it
			# goes back to the desktop HUD.
			_mobile_hud.exit_requested.connect(func() -> void:
				if _root.campaign_overlay != null:
					_root.campaign_overlay.toggle_pause()
				else:
					set_mobile_layout(false))
			_mobile_hud.scenario_requested.connect(toggle_scenario_panel)
			add_child(_mobile_hud)
			# Under the hint and pop-ups, over the drawn instruments.
			move_child(_mobile_hud, _overlay.get_index() + 1)
		_desktop_visible.clear()
		var keep := [_overlay, _hit_words, _callouts, _hint_label, _event_container, _game_over_modal, _mobile_hud]
		for c in get_children():
			# The graffiti targets are drawn instruments too (added by the root),
			# and the tutorial banner belongs to both layouts.
			if c is CanvasItem and not c in keep and not c is InteractionMarkers and not c is FlightTutorial:
				_desktop_visible[c] = (c as CanvasItem).visible
				(c as CanvasItem).visible = false
		_mobile_hud.visible = true
		# Let go of anything a desktop button was holding.
		if _root != null:
			_root.set_firing(false)
			_root.set_boosting(false)
		show_hint("Mobile HUD — F1 (or ☰) to go back")
	else:
		if _mobile_hud != null:
			_mobile_hud.visible = false
		for c in _desktop_visible:
			if is_instance_valid(c):
				(c as CanvasItem).visible = _desktop_visible[c]
		_desktop_visible.clear()
		_apply_move_profile()
		show_hint("Desktop HUD")


func toggle_perf_panel() -> void:
	if _perf_panel == null:
		_perf_panel = PerformancePanel.new()
		_perf_panel.name = "PerformancePanel"
		_perf_panel.setup(_root)
		_perf_panel.set_anchors_preset(Control.PRESET_CENTER)
		_perf_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_perf_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_perf_panel.visible = false
		add_child(_perf_panel)
		_modals.manage(_perf_panel)
	_perf_panel.visible = not _perf_panel.visible


func toggle_combat_modal() -> void:
	if _combat_modal == null:
		return
	_combat_modal.visible = not _combat_modal.visible
	if _combat_modal.visible and _root != null:
		_combat_modal.update_state(_root.locked_target != null, _root.facing_target, Session.ship_headlights)


func _on_combat_setting_changed(setting_name: String, value: Variant) -> void:
	if _root == null:
		return
	match setting_name:
		"facing_target":
			_root.facing_target = bool(value)
			show_hint("Auto-Face Target: %s" % ("ON" if value else "OFF"))
		"lead_reticle":
			Session.hud_reticle = bool(value)
			Session.save_to_disk()
			show_hint("Predictive Lead Reticle: %s" % ("ON" if value else "OFF"))
		"ship_headlights":
			if Session.ship_headlights != bool(value):
				_root.toggle_headlights()
		"debris_glow":
			Session.planet_debris_glow = bool(value)
			Session.save_to_disk()
			PlanetDebrisBuilder.set_debris_glow_enabled(bool(value), _root)
			show_hint("Planet debris glow: %s" % ("ON" if value else "OFF (Max FPS)"))


func _on_combat_action_triggered(action_name: String, params: Dictionary) -> void:
	if _root == null:
		return
	match action_name:
		"toggle_lock":
			_root.toggle_lock()
		"spawn_ai":
			_spawn_quick(int(params.get("count", 1)))
		"spawn_mother":
			var ok := _root.spawn_mother_ship()
			show_hint("Mother ship launched" if ok else "No room for a mother ship")
		"clear_ai":
			_kill_all_ai()
		"shatter_planet":
			_root.shatter_nearest_planet()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _radar_display != null and _radar_display.handle_click(mb.position):
				get_viewport().set_input_as_handled()


func show_game_over() -> void:
	if _game_over_modal == null:
		return
	# Above everything built after it (the phone controls, popups): under them,
	# a tap on its buttons could land on a control and never reach it.
	_game_over_modal.move_to_front()
	_game_over_modal.z_index = 50
	_game_over_modal.visible = true
	_game_over_modal.modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_game_over_modal, "modulate:a", 1.0, 0.35)


func hide_game_over() -> void:
	if _game_over_modal != null:
		_game_over_modal.visible = false


## Spawn a bouncy floating damage number or status pop (e.g. "-45", "-120 CRIT!", "DETACHED!")
func spawn_damage_number(amount: int, is_hull: bool, is_crit: bool, world_pos := Vector3.ZERO, custom_text := "") -> void:
	var text := ""
	if custom_text != "":
		text = custom_text
	elif is_hull:
		text = ("💥 -" if is_crit else "-") + str(amount)
	else:
		text = "-" + str(amount) + " SHIELD"

	var screen_pos := size * 0.5 + Vector2(randf_range(-30, 30), randf_range(-20, 20))
	if world_pos != Vector3.ZERO and _root != null:
		var cam := _root.camera_node()
		if cam != null and not cam.is_position_behind(world_pos):
			screen_pos = cam.unproject_position(world_pos)
			screen_pos += Vector2(randf_range(-25, 25), randf_range(-15, 15))

	var col := Color("ffcc33")
	if custom_text != "":
		col = Color("ffb000")
	elif not is_hull:
		col = Color("00e5ff")
	elif is_crit:
		col = Color("ff4433")
	else:
		col = Color("ff8844")

	_damage_numbers.append({
		"text": text,
		"pos": screen_pos,
		"vel": Vector2(randf_range(-25, 25), randf_range(-65, -95)),
		"color": col,
		"life": 0.85,
		"max_life": 0.85,
		"is_crit": is_crit or custom_text != "",
	})


func _build_top_bar() -> void:
	# A flow, so the chips wrap onto a second line instead of running off a
	# narrow screen.
	var bar := HFlowContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("h_separation", BuilderTheme.GAP)
	bar.add_theme_constant_override("v_separation", BuilderTheme.GAP)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = BuilderTheme.PAD
	bar.offset_right = -BuilderTheme.PAD
	bar.offset_top = BuilderTheme.PAD
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 10
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
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.add_child(_menu)

	# On a narrow screen the debug chips below fold into this one, which opens
	# the debug column (where every one of them also lives).
	_tools_chip = _chip("🛠", "Debug & tuning panels (D, or Back on a phone)", func() -> void: toggle_debug_panel())
	_tools_chip.visible = false
	bar.add_child(_tools_chip)

	# Palette toggle & preview chip
	_palette_chip = _chip("🎨 " + _get_active_palette_name(), "Color Palette (F10) — switch color palette & view swatches", func() -> void: toggle_palette_menu())
	bar.add_child(_palette_chip)

	# Mini-swatch strip showing key colors
	_palette_preview_dots = HBoxContainer.new()
	_palette_preview_dots.name = "PaletteDots"
	_palette_preview_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette_preview_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_palette_preview_dots.add_theme_constant_override("separation", 3)
	bar.add_child(_palette_preview_dots)
	_update_palette_dots()

	# Art style toggle chip
	_style_chip = _chip(_get_style_chip_label(), "Art Style (F9) — toggle cartoony/rounded vs grounded look", func() -> void: toggle_art_style())
	bar.add_child(_style_chip)

	# Every game-feel dial — camera zoom, hit effects, sound pacing, AI pacing,
	# balance — in its own panel, next to the look settings.
	bar.add_child(_chip("🎮 Controls", "Controls — movement profile (classic, swipe, slingshot, FPS), camera gestures, aim assist", func() -> void: toggle_controls_panel()))
	bar.add_child(_chip("🎬 Juice", "Juice & feel — camera zoom, hit effects, shot sounds, enemy pacing, balance", func() -> void: toggle_juice_panel()))
	bar.add_child(_chip("🧪 Stats", "Stats debugger — player & enemy health, damage, god mode, regen, spawn/kill", func() -> void: toggle_stats_panel()))
	bar.add_child(_chip("⚡ Perf", "Performance — smooth motion, frame cap, resolution, shadows, AI/effects/debris budgets", func() -> void: toggle_perf_panel()))
	bar.add_child(_chip("🛩 Fly as", "Fly another ship — tiny to titan, any weapon, any enemy firing style", func() -> void: toggle_fly_as_panel()))
	bar.add_child(_chip("🐞 Bug hunt", "Flip suspect settings, record the shots, compare runs to find what bends them", func() -> void: toggle_bug_hunt_panel()))

	# Mobile view fit chip
	_mobile_chip = _chip("📱 Mobile" if Session.mobile_view_fit else "🖥 Desktop", "Mobile View (F8) — fit view & UI for mobile screen", func() -> void: toggle_mobile_view())
	bar.add_child(_mobile_chip)
	var first_debug := _palette_chip.get_index()
	for i in range(first_debug, _mobile_chip.get_index() + 1):
		_debug_chips.append(bar.get_child(i) as Control)

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
	# In a flow, a child stretches to its line's height; the chips stay chips.
	for c in bar.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_target_label.clip_text = true


func _get_active_palette_name() -> String:
	var pal := StyleManager.instance().current_palette
	if pal != null:
		return pal.display_name
	return "Default"


func _get_style_chip_label() -> String:
	var prof := StyleManager.instance().current_profile
	if prof != null and prof.id == "cartoony":
		return "✨ Cartoony"
	return "✨ Grounded"


func _update_palette_dots() -> void:
	if _palette_preview_dots == null:
		return
	for c in _palette_preview_dots.get_children():
		c.queue_free()
	var roles := ["background", "star", "hull_primary", "hull_accent", "ui_accent"]
	for role in roles:
		var col := Palette.color(role)
		var rect := ColorRect.new()
		rect.color = col
		rect.custom_minimum_size = Vector2(8, 14)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_palette_preview_dots.add_child(rect)


func toggle_palette_menu() -> void:
	if _palette_drawer == null:
		return
	_palette_drawer.visible = not _palette_drawer.visible
	if _palette_drawer.visible:
		_rebuild_palette_tabs()
		_rebuild_swatches()


func toggle_art_style() -> void:
	var prof := StyleManager.instance().toggle_art_style()
	PartMeshFactory.clear_cache()
	if _style_chip != null:
		_style_chip.text = _get_style_chip_label()
	show_hint("Art Style: %s (%s) — rebuilding geometry & restarting…" % [
		prof.display_name,
		"cartoony & rounded" if prof.id == "cartoony" else "grounded & sharp"
	])
	if _root != null:
		_root.restart_scene()


func toggle_mobile_view() -> void:
	var new_val := not Session.mobile_view_fit
	if _root != null:
		_root.set_mobile_view(new_val)
	else:
		Session.mobile_view_fit = new_val
	update_mobile_view(Session.mobile_view_fit)
	show_hint("Mobile View Fit: %s" % ("ENABLED (closer framing & responsive UI)" if Session.mobile_view_fit else "DESKTOP"))


func toggle_mesh_baking() -> void:
	Session.mesh_baking_enabled = not Session.mesh_baking_enabled
	Session.save_to_disk()
	if _root != null and _root.view != null:
		_root.view.enable_baked_mesh(Session.mesh_baking_enabled)
	show_hint("Mesh Baking: %s" % ("ENABLED (consolidated draw calls)" if Session.mesh_baking_enabled else "OFF (individual parts)"))


func toggle_wireframe_mode() -> void:
	var on: bool = StyleManager.instance().toggle_wireframe()
	show_hint("⚡ Vector Arcade (Wireframe): %s" % ("ON (Geometry Wars neon vector style)" if on else "OFF"))


func update_mobile_view(enabled: bool) -> void:
	if _mobile_chip != null:
		_mobile_chip.text = "📱 Mobile" if enabled else "🖥 Desktop"
	theme = FlightTheme.create_theme(size, enabled)
	_layout_controls()


func refresh_palette() -> void:
	if _palette_chip != null:
		_palette_chip.text = "🎨 " + _get_active_palette_name()
	_update_palette_dots()
	if _palette_drawer != null and _palette_drawer.visible:
		_rebuild_palette_tabs()
		_rebuild_swatches()


func _build_palette_drawer() -> void:
	_palette_drawer = PanelContainer.new()
	_palette_drawer.name = "PaletteDrawer"
	_palette_drawer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_palette_drawer.offset_left = BuilderTheme.PAD
	_palette_drawer.offset_right = -BuilderTheme.PAD
	_palette_drawer.offset_top = BuilderTheme.TOUCH_MIN + BuilderTheme.PAD * 2
	_palette_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette_drawer.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.color("ui_bg_panel")
	sb.border_color = Palette.color("ui_border_strong")
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_palette_drawer.add_theme_stylebox_override("panel", sb)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_palette_drawer.add_child(main_vbox)

	# Header bar
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "🎨 COLOR PALETTE & VISUAL STYLE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Palette.color("ui_accent"))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: _palette_drawer.visible = false)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	# Palette tabs row
	var pal_label := Label.new()
	pal_label.text = "Choose Palette (applies to world void, stars, nebula, rocks, celestial bodies, ships & UI):"
	pal_label.add_theme_font_size_override("font_size", 11)
	pal_label.add_theme_color_override("font_color", Palette.color("ui_text_dim"))
	main_vbox.add_child(pal_label)

	_palette_tabs_container = HBoxContainer.new()
	_palette_tabs_container.add_theme_constant_override("separation", 6)
	main_vbox.add_child(_palette_tabs_container)
	_rebuild_palette_tabs()

	# Swatches section
	_swatch_section_label = Label.new()
	_swatch_section_label.text = "All Colors in Active Palette (%s):" % _get_active_palette_name()
	_swatch_section_label.add_theme_font_size_override("font_size", 11)
	_swatch_section_label.add_theme_color_override("font_color", Palette.color("ui_text_dim"))
	main_vbox.add_child(_swatch_section_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_swatches_grid = HFlowContainer.new()
	_swatches_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swatches_grid.add_theme_constant_override("h_separation", 6)
	_swatches_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_swatches_grid)
	_rebuild_swatches()

	# Quick toggles row
	var toggles_box := HBoxContainer.new()
	toggles_box.add_theme_constant_override("separation", 10)

	var style_toggle_btn := Button.new()
	style_toggle_btn.text = "✨ Toggle Cartoony & Rounded"
	style_toggle_btn.pressed.connect(toggle_art_style)
	toggles_box.add_child(style_toggle_btn)

	var mobile_toggle_btn := Button.new()
	mobile_toggle_btn.text = "📱 Fit View for Mobile Screen"
	mobile_toggle_btn.pressed.connect(toggle_mobile_view)
	toggles_box.add_child(mobile_toggle_btn)

	var bake_toggle_btn := Button.new()
	bake_toggle_btn.text = "⚡ Bake Meshes & Collisions"
	bake_toggle_btn.pressed.connect(toggle_mesh_baking)
	toggles_box.add_child(bake_toggle_btn)

	var wire_toggle_btn := Button.new()
	wire_toggle_btn.text = "🌐 Vector Arcade (Wireframe) (F6)"
	wire_toggle_btn.pressed.connect(toggle_wireframe_mode)
	toggles_box.add_child(wire_toggle_btn)

	main_vbox.add_child(toggles_box)
	add_child(_palette_drawer)


func _rebuild_palette_tabs() -> void:
	if _palette_tabs_container == null:
		return
	for c in _palette_tabs_container.get_children():
		c.queue_free()

	var all_palettes := Palette.all()
	var current_p := StyleManager.instance().current_palette
	var current_id := current_p.id if current_p != null else ""

	for pal in all_palettes:
		var btn := Button.new()
		btn.text = ("● " if pal.id == current_id else "") + pal.display_name
		btn.custom_minimum_size = Vector2(100, 32)
		btn.focus_mode = Control.FOCUS_NONE
		if pal.id == current_id:
			btn.add_theme_color_override("font_color", Palette.color("ui_select"))
		var target_pal := pal
		btn.pressed.connect(func() -> void:
			StyleManager.instance().set_palette(target_pal)
			refresh_palette()
			_rebuild_palette_tabs()
			_rebuild_swatches()
			show_hint("Color Palette: %s applied to world, ships & UI" % target_pal.display_name)
		)
		_palette_tabs_container.add_child(btn)


func _rebuild_swatches() -> void:
	if _swatches_grid == null:
		return
	for c in _swatches_grid.get_children():
		c.queue_free()

	if _swatch_section_label != null:
		_swatch_section_label.text = "All Colors in Active Palette (%s):" % _get_active_palette_name()

	var current_p := StyleManager.instance().current_palette
	if current_p == null:
		var all_p := Palette.all()
		if not all_p.is_empty():
			current_p = all_p[0]

	if current_p == null:
		return

	for row in current_p.swatches():
		var col: Color = row["color"]
		var label_str: String = row["label"]
		var key_str: String = row["key"]
		var group_str: String = row.get("group", "")

		var card := HBoxContainer.new()
		card.custom_minimum_size = Vector2(155, 26)
		card.tooltip_text = "%s (%s)\nRole: %s\nRGB: #%s" % [label_str, group_str, key_str, col.to_html(false)]

		var color_rect := ColorRect.new()
		color_rect.color = col
		color_rect.custom_minimum_size = Vector2(22, 22)
		color_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.add_child(color_rect)

		var info_box := VBoxContainer.new()
		info_box.add_theme_constant_override("separation", 0)

		var name_lbl := Label.new()
		name_lbl.text = label_str
		name_lbl.add_theme_font_size_override("font_size", 10)
		info_box.add_child(name_lbl)

		var hex_lbl := Label.new()
		hex_lbl.text = "#" + col.to_html(false)
		hex_lbl.add_theme_font_size_override("font_size", 9)
		hex_lbl.add_theme_color_override("font_color", Palette.color("ui_text_dim"))
		info_box.add_child(hex_lbl)

		card.add_child(info_box)
		_swatches_grid.add_child(card)


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
	# Tips are sprayed, not typed: the arcade ka1 face with a fat ink outline.
	_hint_label.add_theme_font_override("font", GraffitiStyle.tip_font())
	_hint_label.add_theme_color_override("font_color", GraffitiStyle.SUN)
	_hint_label.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	_hint_label.add_theme_constant_override("outline_size", 8)
	_hint_label.add_theme_color_override("font_shadow_color", GraffitiStyle.SHADOW)
	_hint_label.add_theme_constant_override("shadow_offset_x", 2)
	_hint_label.add_theme_constant_override("shadow_offset_y", 3)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

	_weapon_button = Button.new()
	_weapon_button.name = "WeaponButton"
	_weapon_button.text = "[F] WEP"
	_weapon_button.tooltip_text = "Switch Weapon (F)"
	_weapon_button.focus_mode = Control.FOCUS_NONE
	_weapon_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_weapon_button.add_theme_font_size_override("font_size", 11)
	_weapon_button.add_theme_color_override("font_color", BuilderTheme.accent())
	_weapon_button.pressed.connect(func() -> void:
		# Players have no weapon swapping: the bar is a pause button for them.
		if not Session.debug_mode and _root != null and _root.campaign_overlay != null:
			_root.campaign_overlay.toggle_pause()
			return
		if _root != null and _root.has_method("cycle_weapon"):
			_root.cycle_weapon()
	)
	add_child(_weapon_button)
	_timer_label = Label.new()
	_timer_label.name = "LevelTimer"
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label.add_theme_font_override("font", GraffitiStyle.head_font())
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_outline_color", GraffitiStyle.INK)
	_timer_label.add_theme_constant_override("outline_size", 7)
	_timer_label.visible = false
	add_child(_timer_label)

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


## Positions the thumb controls. Everything is anchored to a corner and
## sized from the shorter screen edge, so the layout is identical in portrait,
## landscape and on a desktop window — only the gaps grow.
## Below this width (or in portrait) the debug chips fold into the 🛠 chip.
const NARROW_WIDTH := 900.0


func _fold_top_bar() -> void:
	if _tools_chip == null:
		return
	var narrow := size.x < NARROW_WIDTH or size.y > size.x
	_tools_chip.visible = narrow
	for chip in _debug_chips:
		chip.visible = not narrow
	# Narrow: the icon toolbar takes a whole line of its own (wrapping inside
	# it) and the chips flow onto the next, instead of every icon stacking in a
	# column at its minimum width. Wide: one row of every icon — a flow's own
	# minimum is its widest child, which stacked the toolbar into a column down
	# the left edge, under the throttle and off the bottom of short screens.
	var avail := maxf(size.x - BuilderTheme.PAD * 2.0, 0.0)
	var n := _menu.get_child_count()
	var row := n * (BuilderTheme.TOUCH_MIN + BuilderTheme.GAP) - BuilderTheme.GAP
	_menu.custom_minimum_size.x = avail if narrow else minf(float(row), avail)


func _layout_controls() -> void:
	_fold_top_bar()
	if _stick == null:
		return
	var is_mob := Session.mobile_view_fit
	theme = FlightTheme.create_theme(size, is_mob)
	var pad := float(BuilderTheme.PAD)
	var short_edge := minf(size.x, size.y)
	var stick_size := clampf(short_edge * 0.30, 110.0, 190.0) * (1.15 if is_mob else 1.0)
	var button_w := clampf(short_edge * 0.17, 76.0, 132.0) * (1.2 if is_mob else 1.0)
	var button_h := float(BuilderTheme.TOUCH_MIN + (16 if is_mob else 8))

	_stick.size = Vector2(stick_size, stick_size)
	_stick.position = size - _stick.size - Vector2(pad, pad)

	_throttle.size = Vector2(clampf(short_edge * 0.10, 54.0, 78.0) * (1.15 if is_mob else 1.0), stick_size)
	_throttle.position = Vector2(pad, size.y - _throttle.size.y - pad)

	# The action buttons sit inboard of the stick, above the throttle: reachable
	# with the left thumb while the right thumb is still flying.
	var stack_x := _throttle.position.x + _throttle.size.x + pad
	_boost_button.size = Vector2(button_w, button_h)
	_boost_button.position = Vector2(stack_x, size.y - button_h - pad)
	_fire_button.size = Vector2(button_w, button_h)
	_fire_button.position = Vector2(stack_x, size.y - button_h * 2.0 - pad * 2.0)
	if _weapon_button != null:
		var wep_w := maxf(button_w, 120.0 if is_mob else 105.0)
		_weapon_button.size = Vector2(wep_w, button_h)
		_weapon_button.position = Vector2(stack_x, size.y - button_h * 3.0 - pad * 3.0)

	var spd_w := 200.0 if is_mob else 160.0
	_speed_label.size = Vector2(spd_w, 48 if is_mob else 40)
	_speed_label.position = Vector2(size.x - spd_w - pad, size.y * 0.5 - 60)
	_speed_label.add_theme_font_size_override("font_size", 34 if is_mob else 26)

	_ground_speed_label.size = Vector2(spd_w, 24 if is_mob else 20)
	_ground_speed_label.position = Vector2(size.x - spd_w - pad, size.y * 0.5 - 18)
	_ground_speed_label.add_theme_font_size_override("font_size", 16 if is_mob else 14)

	var hint_fs := GraffitiStyle.fit(24, size)
	_hint_label.add_theme_font_size_override("font_size", hint_fs)
	_hint_label.size = Vector2(size.x * 0.8, hint_fs * 2.6)
	_hint_label.position = Vector2(size.x * 0.1, size.y * 0.5 + RETICLE_RADIUS * 3.0)

	_damage_label.size = Vector2(260, 20)
	_damage_label.position = Vector2(pad, size.y * 0.5 + 30)


## Update active weapon badge on HUD with name and color indicator.
func _update_timer_label() -> void:
	if _timer_label == null:
		return
	var left := _root.scenarios.time_left() if _root.scenarios != null else -1.0
	_timer_label.visible = left >= 0.0 and _weapon_button != null and _weapon_button.is_visible_in_tree()
	if not _timer_label.visible:
		return
	_timer_label.text = FlightScenarios.clock_text(left)
	var col := GraffitiStyle.SUN
	if left <= 10.0:
		col = col.lerp(GraffitiStyle.HOT, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	_timer_label.add_theme_color_override("font_color", col)
	_timer_label.position = _weapon_button.position + Vector2(0, _weapon_button.size.y + 4)


func update_weapon_badge(weapon: Dictionary) -> void:
	if _weapon_button == null:
		return
	var wname: String = weapon.get("name", "Pulse Laser")
	var color: Color = weapon.get("color", BuilderTheme.text())
	_weapon_button.text = "[F] " + wname
	_weapon_button.tooltip_text = "Switch Weapon (F)\n%s" % weapon.get("desc", "")
	_weapon_button.add_theme_color_override("font_color", color)



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
		["Action (tight chase)", FlightCamera.Mode.ACTION],
		["Cinematic", FlightCamera.Mode.CINEMATIC],
		["Side", FlightCamera.Mode.SIDE],
		["Top-down", FlightCamera.Mode.TOP_DOWN],
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
	popup.add_check_row(
		"Hold camera on spin-out",
		_root.ooc_camera_hold_on(),
		func(_on: bool) -> void: _root.toggle_ooc_camera_hold()
	)

	# Render toggles.
	popup.add_section("Render")
	popup.add_check_row("Drift field", _root.drift_field_on(), func(_on: bool) -> void: _root.toggle_drift_field())
	popup.add_check_row("Rear view (B)", _root._rear_view_on, func(_on: bool) -> void: _root.toggle_rear_view())
	popup.add_check_row("High res (restart)", _root.high_res_on(), func(_on: bool) -> void: _root.toggle_high_res())
	popup.add_option_row(
		"Planet quality (restart)", ["Low", "Medium", "High"], _root.planet_quality(),
		func(index: int) -> void: _root.set_planet_quality(index)
	)
	# Which surface technique planets use — applied live and remembered, so
	# the next flight starts with it for a side-by-side comparison.
	var looks: Array[String] = []
	for look: Dictionary in Planet.SURFACE_STYLES:
		looks.append(String(look["name"]))
	popup.add_option_row(
		"Planet look (starts with this)", looks, Session.planet_surface_style,
		func(index: int) -> void:
			Planet.set_surface_style(index)
			Session.planet_surface_style = index
			Session.planet_surface_alt = index == 1
			Session.save_to_disk()
	)
	popup.add_check_row("High contrast", BuilderTheme.high_contrast, func(_on: bool) -> void: _root.toggle_high_contrast())
	popup.add_check_row("Test volume (restart)", not _root.location_is_space(), func(_on: bool) -> void: _root.toggle_location())
	popup.add_check_row("Planet pointer (J)", _root.planet_pointer_on(), func(_on: bool) -> void: _root.toggle_planet_pointer())
	popup.add_check_row("Cinematic sun lighting (Galaxy on Fire)", _root.cinematic_lighting_on(), func(_on: bool) -> void: _root.toggle_cinematic_lighting())
	if _root.space != null:
		popup.add_check_row("Nebula sky (painted galaxy backdrop)", Session.nebula_sky, func(on: bool) -> void: _root.space.set_nebula_sky(on))


	# Visual & Palette Style
	popup.add_section("Visual & Palette Style")
	popup.add_action_row("Open Palette Menu & Swatches (F10)", func() -> void: toggle_palette_menu())
	popup.add_check_row("Mobile View Fit (closer framing, responsive)", Session.mobile_view_fit, func(on: bool) -> void: toggle_mobile_view())
	popup.add_action_row("📱 Real mobile HUD (F1 to go back)", func() -> void: set_mobile_layout(true))
	popup.add_action_row("🔤 Mobile HUD look & fonts", func() -> void: toggle_fonts_panel())
	popup.add_check_row("Cartoony & Rounded Style", StyleManager.instance().current_profile != null and StyleManager.instance().current_profile.id == "cartoony", func(_on: bool) -> void: toggle_art_style())
	popup.add_check_row("Vector Arcade (Wireframe Neon) (F6)", StyleManager.instance().is_wireframe(), func(_on: bool) -> void: toggle_wireframe_mode())
	popup.add_check_row("Bake Meshes (Draw call optimization)", Session.mesh_baking_enabled, func(_on: bool) -> void: toggle_mesh_baking())

	# HUD clutter (persisted).
	popup.add_section("HUD overlay")
	popup.add_check_row("Reticle", Session.hud_reticle, func(on: bool) -> void:
		Session.hud_reticle = on
		Session.save_to_disk())
	popup.add_check_row("Markers & brackets", Session.hud_markers, func(on: bool) -> void:
		Session.hud_markers = on
		Session.save_to_disk())
	popup.add_check_row("Player indicator", Session.hud_indicators, func(on: bool) -> void:
		Session.hud_indicators = on
		Session.save_to_disk())


func _fill_controls_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Flight"
	popup.add_section("Movement profile (U)")
	for i in FlightRoot.MOVE_PROFILE_NAMES.size():
		popup.add_radio_row(
			String(FlightRoot.MOVE_PROFILE_NAMES[i]), _root.move_profile == i, i,
			func(v: int) -> void: _root.set_move_profile(v)
		)
	popup.add_help_row(
		"Classic: stick, throttle and buttons. Swipe: swipe to fly that way, tap to shoot, "
		+ "hold to boost (keep holding to warp) — ramming hits hard. Slingshot: drag back from "
		+ "your ship and let go; it bounces off everything it hits. Tap to shoot, touch it to catch it. "
		+ "FPS: the stick moves you (push further = faster), drag the screen to look. All their dials: 🎮 Controls."
	)
	popup.add_separator()
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
		"Arcade pivot / tilt", 1.0, 6.0, 0.25, Session.arcade_pivot,
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
	popup.add_check_row("Warp (Z)", _root.model != null and _root.model.warp_active, func(on: bool) -> void:
		if _root.model != null:
			_root.model.warp_active = on
			show_hint("Warp %s — 8× speed" % ("ON" if on else "OFF")))
	popup.add_separator()
	popup.add_check_row("Solar Glare (F7)", Session.glare_enabled, func(on: bool) -> void:
		Session.glare_enabled = on
		Session.save_to_disk()
		if _root.space != null and _root.space.has_method("set_glare_enabled"):
			_root.space.set_glare_enabled(on)
			show_hint("Solar Glare: %s" % ("ON" if on else "OFF"))
	)
	popup.add_action_row("Rebuild ship in orbit (F4)", func() -> void: _root.respawn_player_ship())
	popup.add_action_row("Return to start point (R)", func() -> void: _root.respawn())
	popup.add_action_row("Restart scene (F5)", func() -> void: _root.restart_scene())


func _fill_combat_popup(popup: FlightMenu.DraggablePopup) -> void:
	popup.title = "Combat"
	var sys := _root.active_systems()
	if sys != null:
		var wep_names: Array[String] = []
		for w in SystemsSim.WEAPONS:
			wep_names.append(w.name)
		popup.add_option_row(
			"Active weapon (F)", wep_names, sys.active_weapon_index,
			func(idx: int) -> void:
				_root.set_weapon_index(idx)
		)
		popup.add_separator()
	popup.add_value_row("AI ships alive", str(_root.ai_live_count()))
	popup.add_action_row("⚔ Scenarios — duel, skirmish, waves…", func() -> void: toggle_scenario_panel())
	popup.add_action_row("🛩 Fly as another ship…", func() -> void: toggle_fly_as_panel())
	popup.add_action_row(
		"Lock nearest ship (T)" if _root.locked_target == null else "Release lock (T)",
		func() -> void: _root.toggle_lock()
	)
	popup.add_check_row("Face locked target", _root.facing_target, func(on: bool) -> void: _root.facing_target = on)
	popup.add_action_row("Tactical Headlights (L)", func() -> void: _root.toggle_headlights())
	popup.add_action_row("Open Tactical Combat Panel", func() -> void: toggle_combat_modal())
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
		func(idx: int) -> void: _set_spawn_pref("behavior", idx)
	)
	var forms: Array[String] = ["Scatter", "V-formation", "Line", "Sphere", "Trail"]
	popup.add_option_row(
		"Formation", forms, _spawn_formation,
		func(idx: int) -> void: _set_spawn_pref("formation", idx)
	)
	var teams: Array[String] = ["None", "Red", "Blue", "Green", "Gold"]
	popup.add_option_row(
		"Team", teams, _spawn_team,
		func(idx: int) -> void: _set_spawn_pref("team", idx)
	)
	popup.add_slider_row(
		"Group size", 1.0, 8.0, 1.0, float(_spawn_count),
		func(v: float) -> void: _set_spawn_pref("count", int(v)), "%.0f"
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
	popup.add_action_row("Trigger Faction Skirmish", func() -> void:
		_trigger_incident("faction_skirmish"))
	popup.add_action_row("Trigger Rare Drift (◆)", func() -> void:
		_trigger_incident("rare_drift"))
	popup.add_action_row("Clear active incidents", func() -> void:
		if _root.incident_director != null:
			_root.incident_director.clear_all()
			show_hint("All active incidents cleared"))

	# Planetary destruction suite
	popup.add_separator()
	popup.add_section("Planetary destruction")
	popup.add_slider_row(
		"Break fineness", 0.5, 3.0, 0.25, Session.planet_break_fineness,
		func(v: float) -> void:
			Session.planet_break_fineness = v
			show_hint("Planet break fineness: ×%.2f" % v),
		"×%.2f"
	)
	popup.add_check_row(
		"Radiant mantle glow", Session.planet_debris_glow,
		func(on: bool) -> void:
			PlanetDebrisBuilder.set_debris_glow_enabled(on, _root)
			show_hint("Planet debris glow: %s" % ("ON" if on else "OFF (Max FPS)"))
	)
	popup.add_action_row("Fire heavy weapon (X)", func() -> void: _root._fire_heavy_weapon())
	popup.add_action_row("💥 Shatter nearest planet (Shift+P)", func() -> void: _root.shatter_nearest_planet())


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
		func(v: float) -> void:
			Session.trail_length = v
			Session.save_to_disk(),
		"×%.1f"
	)
	# Trails read the length when built, so re-create the enabled ones on release.
	len_slider.drag_ended.connect(func(_changed: bool) -> void: _root.refresh_trails())


# --- Per-frame sync ---------------------------------------------------------

func _process(delta: float) -> void:
	if _root == null or _root.model == null:
		return
	_update_timer_label()

	# Update floating damage numbers
	var live_numbers: Array[Dictionary] = []
	for dn in _damage_numbers:
		dn["pos"] += dn["vel"] * delta
		dn["vel"] *= (1.0 - 1.2 * delta)
		dn["life"] -= delta
		if dn["life"] > 0.0:
			live_numbers.append(dn)
	_damage_numbers = live_numbers

	# Smooth ghost trails for health & shield bars
	if _root != null:
		var target_hp := clampf(_root.player_hp / maxf(_root.player_max_hp, 1.0), 0.0, 1.0)
		if target_hp < _hp_ghost:
			_hp_ghost = maxf(_hp_ghost - 0.45 * delta, target_hp)
		else:
			_hp_ghost = target_hp

		var target_shield := clampf(_root.player_shield / maxf(_root.player_max_shield, 1.0), 0.0, 1.0)
		if target_shield < _shield_ghost:
			_shield_ghost = maxf(_shield_ghost - 0.65 * delta, target_shield)
		else:
			_shield_ghost = target_shield

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
	# Show out of control warning or damage status if parts lost.
	var dmg := _root.damage
	if model.out_of_control:
		_damage_label.text = "⚠️ TUMBLING OUT OF CONTROL!"
		_damage_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15))
		_damage_label.visible = true
	elif dmg != null and dmg.broken_count() > 0:
		_damage_label.text = "⚠ %d part(s) lost" % dmg.broken_count()
		_damage_label.add_theme_color_override("font_color", BuilderTheme.warn())
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


## The hint line under the reticle. Most hints are developer read-outs
## ("Gravity: HIGH", "ORBIT: stable..."), shown only in debug mode
## (Settings > DEBUG); [param player] hints (what to do now) always show. A
## hint holds for [constant HINT_HOLD] seconds, then fades.
func show_hint(text: String, player := false) -> void:
	if _hint_label == null or (not player and not Session.debug_mode):
		return
	# No dashes in what the player reads: a comma reads faster.
	_hint_label.text = text.replace(" — ", ", ").replace("—", ", ").to_upper() if player else text
	_hint_label.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_HOLD)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.8)


# --- Instruments ------------------------------------------------------------

func _draw_instruments() -> void:
	var camera := _root.camera_node()
	if camera == null or _root.model == null:
		return
	if _root.pilot() != null:
		_root.pilot().draw(_overlay)
	var centre := size * 0.5
	if Session.hud_reticle:
		# The gunsight sits where the guns converge (down the nose), not at
		# the screen centre: the chase camera leads into turns, so the centre
		# is often a little off where the shots go.
		var sight := centre
		var sys_now := _root.active_systems()
		if sys_now != null:
			var bp := sys_now.boresight_point()
			if not camera.is_position_behind(bp):
				sight = camera.unproject_position(bp)
		_reticle_pos = centre if _reticle_pos == Vector2.INF else _reticle_pos.lerp(sight, 0.5)
		_draw_reticle(_reticle_pos)
		if sys_now != null:
			_draw_reload_ring(_reticle_pos, sys_now)
		if _root.locked_target != null and is_instance_valid(_root.locked_target):
			var p_pos := camera.global_position
			var p_vel := _root.model.velocity if _root.model != null else Vector3.ZERO
			var t_node := _root.locked_target
			var t_pos := t_node.global_position
			var t_vel := Vector3.ZERO
			if t_node is CharacterBody3D:
				t_vel = (t_node as CharacterBody3D).velocity
			elif t_node is RigidBody3D:
				t_vel = (t_node as RigidBody3D).linear_velocity
			elif t_node.get("velocity") != null:
				t_vel = t_node.get("velocity")
			var p_speed := 1100.0
			var sys := _root.active_systems()
			if sys != null and sys.has_method("get_active_weapon"):
				var cur_wep: Dictionary = sys.get_active_weapon()
				p_speed = float(cur_wep.get("speed", 1100.0))
			TargetLeadReticle.draw_lead_reticle(_overlay, camera, p_pos, p_vel, t_pos, t_vel, p_speed, centre)
	_draw_drift(camera, centre)
	if Session.hud_markers:
		_draw_markers(camera)
		_draw_lock_bracket(camera)
		_draw_ai_lock_brackets(camera)
	# The mobile layout draws its own health; the minimap would sit under its
	# stick, so both give way to it.
	if not _mobile_layout:
		_draw_power_bars()
	if Session.hud_indicators:
		_draw_player_indicator(camera)
		_draw_edge_indicators(camera, centre)
		if not _mobile_layout:
			_draw_minimap(camera)
	_draw_damage_numbers()


## The gunsight. An open cross rather than a dot: a dot vanishes against a bright
## planet, and the gap in the middle keeps the target visible while you aim.
## The gunsight's drawn position, eased a touch so a physics-tick step never
## shows as a twitch. INF until the first frame.
var _reticle_pos := Vector2.INF


func _draw_reticle(centre: Vector2) -> void:
	var col := BuilderTheme.accent()
	var r := RETICLE_RADIUS
	for i in 4:
		var dir := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][i] as Vector2
		_overlay.draw_line(centre + dir * (r * 0.45), centre + dir * r, col, 1.5, true)
	_overlay.draw_arc(centre, r * 1.5, 0.0, TAU, 32, Color(col, 0.35), 1.0, true)


## The weapon cooldown round the gunsight: an arc that fills as the guns
## reload and closes into a full ring when they are ready, in the weapon's
## colour — red when the capacitor cannot pay for the next shot.
func _draw_reload_ring(centre: Vector2, sys: SystemsSim) -> void:
	var r := RETICLE_RADIUS * 1.5
	var t := sys.reload_progress()
	var col: Color = sys.get_active_weapon().get("color", BuilderTheme.accent())
	if not sys.has_energy_for_shot():
		col = BuilderTheme.bad()
		t = 1.0
	var ready := t >= 0.999
	_overlay.draw_arc(centre, r, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.35), 4.5, true)
	if ready:
		_overlay.draw_arc(centre, r, 0.0, TAU, 40, Color(col, 0.9), 2.5, true)
	else:
		_overlay.draw_arc(centre, r, -PI * 0.5, -PI * 0.5 + TAU * t, 40, Color(col, 0.95), 3.0, true)


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
## Health, shield, capacitor and heat bars beneath the speed readout.
func _draw_power_bars() -> void:
	var w := 120.0
	var h := 7.0
	var gap := 11.0
	var x := size.x - w - float(BuilderTheme.PAD)
	var y := size.y * 0.5 - 54.0

	var hp_frac := 1.0
	var shield_frac := 1.0
	if _root != null:
		hp_frac = clampf(_root.player_hp / maxf(_root.player_max_hp, 1.0), 0.0, 1.0)
		shield_frac = clampf(_root.player_shield / maxf(_root.player_max_shield, 1.0), 0.0, 1.0)

	# HULL with ghost lag
	_draw_ghost_bar(Rect2(x, y, w, h), hp_frac, _hp_ghost, BuilderTheme.gauge_color(hp_frac), "HULL")
	if hp_frac < 0.25 and hp_frac > 0.0:
		# A colour shift alone is easy to miss mid-dogfight — how close to
		# death the player actually is was hard to read at a glance, so a
		# critical hull gets a pulsing outline on top of the colour cue.
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_overlay.draw_rect(
			Rect2(x - 2.0, y - 2.0, w + 4.0, h + 4.0), Color(1.0, 0.15, 0.15, pulse * 0.8), false, 2.0
		)
	# SHIELD with ghost lag — only while there is one (see the power-up bubble).
	if _root != null and _root.player_max_shield > 0.0:
		_draw_ghost_bar(Rect2(x, y + gap + h, w, h), shield_frac, _shield_ghost, Color("00d4ff"), "SHIELD")
	# CAP
	_draw_bar(Rect2(x, y + (gap + h) * 2.0, w, h), _energy, BuilderTheme.accent(), "CAP")
	# HEAT
	_draw_bar(Rect2(x, y + (gap + h) * 3.0, w, h), _heat, BuilderTheme.gauge_color(1.0 - _heat), "HEAT")


func _draw_ghost_bar(rect: Rect2, fraction: float, ghost: float, color: Color, label: String) -> void:
	_overlay.draw_rect(rect, Color(BuilderTheme.bg_deep(), 0.65), true)
	if ghost > fraction:
		_overlay.draw_rect(
			Rect2(rect.position, Vector2(rect.size.x * clampf(ghost, 0.0, 1.0), rect.size.y)),
			Color(1.0, 0.8, 0.4, 0.55), true
		)
	_overlay.draw_rect(
		Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)),
		color, true
	)
	_overlay.draw_rect(rect, BuilderTheme.border(), false, 1.0)
	var label_col := BuilderTheme.text_dim()
	# The hull label pulses white and red while the low-health alarm sounds.
	if label == "HULL" and fraction > 0.0 and fraction < FlightRoot.LOW_HEALTH_FRACTION:
		label_col = Color.WHITE.lerp(Color("ff2a2a"), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	_overlay.draw_string(
		get_theme_default_font(), rect.position + Vector2(0.0, -3.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col
	)


func _draw_damage_numbers() -> void:
	if _damage_numbers.is_empty():
		return
	var font := get_theme_default_font()
	for dn in _damage_numbers:
		var pos: Vector2 = dn["pos"]
		var text: String = dn["text"]
		var color: Color = dn["color"]
		var life: float = dn["life"]
		var max_life: float = dn["max_life"]
		var is_crit: bool = dn["is_crit"]
		var alpha := clampf(life / 0.35, 0.0, 1.0)
		var pop := 1.0 + 0.3 * clampf(life / max_life, 0.0, 1.0)
		var font_size := roundi((17 if is_crit else 13) * pop)

		var draw_col := Color(color, alpha)
		# Shadow for contrast against bright stars and planets
		_overlay.draw_string(
			font, pos + Vector2(1.5, 1.5), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, alpha * 0.9)
		)
		_overlay.draw_string(
			font, pos, text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, draw_col
		)


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
	if not player_indicator_active() or _root.is_player_dead():
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
## views that always keep the player's ship in frame.
func player_indicator_active() -> bool:
	if _root == null or _root.camera_rig == null:
		return false
	return not _root.camera_rig.is_follow_mode()
func _draw_edge_indicators(camera: Camera3D, centre: Vector2) -> void:
	if _root._ai_spawner == null:
		return
	var player_ship = _root.active_ship_node()
	if player_ship == null:
		return
		
	var max_range := 3000.0
	var player_pos: Vector3 = player_ship.global_position
	
	for ship in _root._ai_spawner._ships:
		if not is_instance_valid(ship) or not ship._alive or ship == player_ship:
			continue
			
		var dist: float = player_pos.distance_to(ship.global_position)
		if dist > max_range:
			continue
			
		var point := camera.unproject_position(ship.global_position)
		var is_behind := camera.is_position_behind(ship.global_position)
		var screen_rect := Rect2(Vector2.ZERO, size)
		
		if is_behind or not screen_rect.grow(-10.0).has_point(point):
			var dir_to_ship = (ship.global_position - camera.global_position).normalized()
			var local_dir = camera.global_transform.basis.inverse() * dir_to_ship
			
			var angle = atan2(local_dir.y, local_dir.x)
			var arrow_dir = Vector2(cos(angle), -sin(angle))
			
			# Edge clamp
			var edge_margin := 30.0
			var half_size = size * 0.5 - Vector2(edge_margin, edge_margin)
			var scale_x = half_size.x / abs(arrow_dir.x) if arrow_dir.x != 0 else 9999.0
			var scale_y = half_size.y / abs(arrow_dir.y) if arrow_dir.y != 0 else 9999.0
			var clamp_scale = minf(scale_x, scale_y)
			
			var edge_pos = centre + arrow_dir * clamp_scale
			
			var col = BuilderTheme.warn()
			if ship.team_id == 1:
				col = BuilderTheme.good()
			
			col.a = clampf(1.0 - (dist / max_range), 0.2, 0.8)
			_draw_indicator_arrow(edge_pos, arrow_dir.angle(), 8.0, col, Color.BLACK)

func _draw_minimap(_camera: Camera3D) -> void:
	if _radar_display == null:
		return
	var player_ship: Node3D = _root.active_ship_node()
	if player_ship == null:
		return

	var r := _radar_display.radar_radius
	var centre := Vector2(size.x - r - 20.0, r + 70.0)
	var ai_list: Array = []
	if _root._ai_spawner != null:
		ai_list = _root._ai_spawner._ships
	_radar_display.offline = _root.sensors_lost()
	_radar_display.draw_radar(_overlay, player_ship, ai_list, _root.landmarks(), centre, _root.locked_target)
