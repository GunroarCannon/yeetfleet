## The real phone layout: a clean, comic-panel HUD that replaces the desktop
## chrome while it is up (see [method FlightHud.set_mobile_layout]; F1 goes
## back).
##
## Health panel top-left, a big speed readout top-right, a throttle dial with
## up/down chevrons on the right edge, a stick bottom-left and a fire / boost /
## weapon cluster bottom-right. The look — palette, comic bands, halftone,
## fonts per text role — comes from the active [MobileHudProfiles] profile, and
## so does the touch scheme (Simple / Standard / Pro) and whether the whole
## layout is mirrored for a left-handed grip.
##
## Drawn rather than assembled from themed Controls, like the rest of the
## flight HUD: the static art sits on its own layer ([member _decor]) that
## only redraws on resize or a profile change; the bars, speed and dial layer
## ([member _live]) redraws every frame. State is read from [FlightRoot] each
## frame — the player's hull is a plain field with many writers, not a signal.
##
## The juice (comic profiles lean on it hardest): inked, leaning bars with a
## drop shadow, moving hatch and a glint; a white flash, a shake and a
## "POW!" burst when the hull takes a chunk; the speed number punching on
## every hundred and radiating rays under boost; buttons that squash and
## ripple when pressed.
class_name MobileHud
extends Control

## Tapped the small menu button: the owner switches back to the desktop HUD.
signal exit_requested
## Tapped the top status band: the owner opens the scenario picker.
signal scenario_requested

## Throttle change per second while a chevron is held.
const THROTTLE_RATE := 0.9
## Simple scheme: throttle change per second toward cruise (thumb down) and
## back to a stop (thumb up).
const SIMPLE_SPOOL_UP := 1.4
const SIMPLE_SPOOL_DOWN := 0.8
## Metres per second to the kilometres per hour the readout shows.
const KMH := 3.6
## Comic shouts for a hull hit / a shield hit.
const HIT_WORDS := ["POW!", "BAM!", "WHAM!", "KRAK!", "OOF!", "BLAM!"]
const SHIELD_WORDS := ["ZZT!", "FZZT!", "BZZ!"]
## A hull hit bigger than this fraction of max hull pops a burst.
const BURST_MIN_HIT := 0.025

var _root: FlightRoot = null
var _decor: Control
var _live: Control
var _stick: Stick
var _fire: RoundButton
var _boost: RoundButton
var _cycle: RoundButton
var _up: RoundButton
var _down: RoundButton
var _menu: RoundButton
## The top comic band doubles as a button (see [signal scenario_requested]).
var _band_btn: Control
## The band's shape, mirrored and ready to draw into (set in [method _layout]).
var _band_quad := PackedVector2Array()
var _band_text_prev := ""
var _band_flash := 0.0
## The charge bar's eased fill (-1 = not drawn yet) and the last frame's real
## delta it eases on.
var _charge_shown := -1.0
var _dt_last := 0.016
var _view: RoundButton
var _roll_l: RoundButton
var _roll_r: RoundButton
var _lock: RoundButton
var _throttle_dir := 0.0
## Simple scheme: the throttle being ramped to, or -1 when not ramping.
var _simple_goal := -1.0
var _rev := -1

# Layout, recomputed in [method _layout].
var _u := 360.0
var _pad := 12.0
var _panel := Rect2()
var _dial_c := Vector2.ZERO
var _dial_r := 30.0
var _speed_right := 0.0
## Top of the speed readout: the screen's top edge in landscape, under the
## health panel in portrait (where the panel takes the top-left).
var _speed_top := 0.0
## Mirrored layout ([member MobileHudProfiles.swap_sides]): every x goes
## through [method _mx].
var _flip := false
var _scheme := "standard"

# Juice state, all advanced on real time in [method _process].
var _t := 0.0
var _hp_prev := -1.0
var _sh_prev := -1.0
var _hp_ghost := 1.0
var _sh_ghost := 1.0
var _hp_flash := 0.0
var _sh_flash := 0.0
var _heal_glow := 0.0
var _shake := 0.0
var _shake_off := Vector2.ZERO
## The offset the live layer is drawing under right now (the shake inside the
## health group, zero elsewhere); [method _text] draws on top of it.
var _draw_off := Vector2.ZERO
var _title_pop := 0.0
var _speed_shown := 0.0
var _speed_pop := 0.0
var _last_hundred := 0
## Live comic bursts: {pos, t, life, word, rot, size, col, seed}.
var _bursts: Array[Dictionary] = []
var _combo_prev := 0
var _combo_pop := 0.0
## Top of the speed meter, m/s; above 0 the speed shows as a meter instead of
## the big number (the endless runner turns it on).
var speed_meter_max := 0.0
## The radar (swipe and slingshot: their bottom-left corner is free of the
## stick), drawn into the live layer, and where it sits.
var _radar: RadarDisplay
var _radar_c := Vector2.ZERO


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	name = "MobileHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor = _layer("Decor", _draw_decor)
	_live = _layer("Live", _draw_live)

	_stick = Stick.new()
	_stick.name = "Stick"
	_stick.moved.connect(func(v: Vector2) -> void:
		if _root != null:
			_root.set_stick(v)
	)
	_stick.held.connect(func(on: bool) -> void:
		if _scheme == "simple":
			_simple_goal = MobileHudProfiles.simple_speed if on else 0.0
	)
	add_child(_stick)

	_fire = _button("fire", true)
	_fire.down.connect(func() -> void: _root.set_firing(true))
	_fire.up.connect(func() -> void: _root.set_firing(false))
	_boost = _button("boost")
	_boost.down.connect(func() -> void: _root.set_boosting(true))
	_boost.up.connect(func() -> void: _root.set_boosting(false))
	_cycle = _button("cycle")
	_cycle.down.connect(func() -> void: _root.cycle_weapon())
	_up = _button("up")
	_up.flat = true
	_up.down.connect(func() -> void: _throttle_dir = 1.0)
	_up.up.connect(func() -> void: _throttle_dir = 0.0)
	_down = _button("down")
	_down.flat = true
	_down.down.connect(func() -> void: _throttle_dir = -1.0)
	_down.up.connect(func() -> void: _throttle_dir = 0.0)
	_menu = _button("menu")
	_menu.up.connect(func() -> void: exit_requested.emit())
	_view = _button("view")
	_view.down.connect(func() -> void: _root.cycle_view())
	_roll_l = _button("roll_l")
	_roll_l.down.connect(func() -> void: _root.set_roll(-1.0))
	_roll_l.up.connect(func() -> void: _root.set_roll(0.0))
	_roll_r = _button("roll_r")
	_roll_r.down.connect(func() -> void: _root.set_roll(1.0))
	_roll_r.up.connect(func() -> void: _root.set_roll(0.0))
	_lock = _button("lock")
	_lock.down.connect(func() -> void: _root.toggle_lock())

	_radar = RadarDisplay.new()
	_radar.name = "Radar"
	_radar.visible = false
	add_child(_radar)

	_band_btn = Control.new()
	_band_btn.name = "Band"
	_band_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_band_btn.gui_input.connect(func(e: InputEvent) -> void:
		var tapped := (e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed)
		if tapped:
			_band_flash = 1.0
			scenario_requested.emit()
			_band_btn.accept_event()
	)
	add_child(_band_btn)
	move_child(_band_btn, 2)

	resized.connect(_layout)
	_layout()


func _layer(layer_name: String, painter: Callable) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(painter)
	add_child(c)
	return c


func _button(kind: String, big := false) -> RoundButton:
	var b := RoundButton.new()
	b.name = kind.capitalize()
	b.kind = kind
	b.big = big
	add_child(b)
	return b


# --- Layout -------------------------------------------------------------------

## Everything is anchored to its corner and sized from the short screen edge,
## so the same layout holds on a 16:9 phone, a 20:9 phone and a desktop window.
## Positions are worked out for the right-handed layout, then mirrored through
## [method _mx] when the sides are swapped.
func _layout() -> void:
	var w := size.x
	var h := size.y
	_flip = MobileHudProfiles.swap_sides
	_scheme = MobileHudProfiles.scheme
	_u = maxf(minf(w, h), 200.0)
	_pad = _u * 0.04
	_panel = Rect2(0.0, 0.0, maxf(_u * 0.66, w * 0.27), _u * 0.3)
	var simple := _scheme == "simple"
	var pro := _scheme == "pro"

	var sr := _u * 0.2
	var stick_c := Vector2(_pad + sr * 1.1, h - _pad - sr * 1.05)
	if simple:
		# A floating stick over the whole lower-left: the thumb lands anywhere
		# and the ring appears under it.
		var zone := Rect2(0.0, _panel.end.y + _pad, w * 0.46, h - _panel.end.y - _pad)
		_stick.ring_radius = sr
		_stick.size = zone.size
		_stick.position = Vector2(w - zone.end.x if _flip else zone.position.x, zone.position.y)
		var rest := stick_c - zone.position
		_stick.rest_point = Vector2(zone.size.x - rest.x if _flip else rest.x, rest.y)
	else:
		_stick.ring_radius = 0.0
		_stick.rest_point = Vector2(-1.0, -1.0)
		_place(_stick, stick_c, sr)

	var fr := _u * (0.15 if simple else 0.125)
	var fire_c := Vector2(w - _pad - fr * 1.05, h - _pad - fr * 1.05)
	_place(_fire, fire_c, fr)
	_place(_boost, fire_c + Vector2(-fr - _u * 0.135, fr * 0.2), _u * 0.08)
	_place(_cycle, fire_c + Vector2(-fr * 1.45, -fr * 1.75), _u * 0.075)
	_place(_lock, fire_c + Vector2(-fr * 2.75, -fr * 1.2), _u * 0.06)
	_place(_roll_l, stick_c + Vector2(-sr * 0.55, -sr * 1.5), _u * 0.055)
	_place(_roll_r, stick_c + Vector2(sr * 0.55, -sr * 1.5), _u * 0.055)

	_dial_r = _u * 0.085
	_dial_c = Vector2(w - _pad - _dial_r * 1.2, fire_c.y - fr * 3.3)
	var cr := _u * 0.05
	_place(_up, _dial_c - Vector2(0.0, _dial_r + cr * 1.2), cr)
	_place(_down, _dial_c + Vector2(0.0, _dial_r + cr * 1.2), cr)
	var one_thumb := FlightRoot.profile_is_one_thumb(_move_profile)
	_speed_right = _dial_c.x - _dial_r * 1.1
	_speed_top = _pad
	if one_thumb or simple:
		# No throttle dial to sit beside: the speed takes the corner.
		_speed_right = w - _pad * 0.6
	if h > w:
		# Portrait: the health panel and band fill the top; the speed goes
		# under the band, against the right edge.
		_speed_right = w - _pad * 0.6
		_speed_top = _panel.end.y + _pad * 0.5
	# Portrait: the health panel already takes most of the width, so the band
	# runs to the far edge and the menu/view buttons drop under the speed.
	# The menu (pause) is always the outer one.
	var portrait := h > w
	var bh := _u * 0.078
	var top := _pad * 0.6 + _u * 0.04
	if portrait:
		var my := _speed_top + _u * 0.33
		_place(_menu, Vector2(w - _pad - _u * 0.06, my), _u * 0.06)
		_place(_view, Vector2(w - _pad - _u * 0.2, my), _u * 0.06)
	elif one_thumb or simple:
		_place(_menu, Vector2(w * 0.72 + _u * 0.1, top), _u * 0.04)
		_place(_view, Vector2(w * 0.72, top), _u * 0.04)
	else:
		_place(_menu, Vector2(w * 0.66 + _u * 0.1, top), _u * 0.04)
		_place(_view, Vector2(w * 0.66, top), _u * 0.04)

	# The status band across the top: a slab from the health panel's corner.
	var bx0 := _panel.end.x - _panel.size.y * float(MobileHudProfiles.profile()["skew"]) * 0.2
	var bx1 := w - _pad if portrait else w * 0.62
	_band_quad = _mpoly(_skew_quad(Rect2(bx0, 0.0, bx1 - bx0, bh), -1.2))
	_band_btn.size = Vector2(bx1 - bx0, bh)
	_band_btn.position = Vector2(_mx(bx1) if _flip else bx0, 0.0)
	_band_btn.visible = bool(MobileHudProfiles.profile()["bands"])

	_stick.visible = true
	_fire.visible = true
	for b: RoundButton in [_boost, _cycle, _up, _down]:
		b.visible = not simple
	for b: RoundButton in [_roll_l, _roll_r, _lock]:
		b.visible = pro
	# The radar takes the free bottom-left corner of the one-thumb profiles,
	# sized off the short edge so a portrait phone gets the same proportion.
	var rr := _u * 0.15
	_radar.radar_radius = rr
	_radar_c = Vector2(_pad + rr * 1.05, h - _pad - rr * 1.05)
	# Swipe and slingshot fly off the bare screen: no stick, no flight buttons.
	if FlightRoot.profile_is_one_thumb(_move_profile):
		for c: Control in [_stick, _fire, _boost, _cycle, _up, _down, _roll_l, _roll_r, _lock]:
			c.visible = false
	elif _move_profile == FlightRoot.MoveProfile.FPS:
		# FPS: the stick's push is the speed, so no throttle buttons.
		for c: Control in [_up, _down]:
			c.visible = false
	_decor.queue_redraw()


## The movement profile ([enum FlightRoot.MoveProfile]); see [method
## FlightHud.set_move_profile].
var _move_profile := 0


func set_move_profile(p: int) -> void:
	_move_profile = p
	if is_inside_tree():
		_layout()


## Place [param c] centred on [param centre] (right-handed coordinates).
func _place(c: Control, centre: Vector2, radius: float) -> void:
	c.size = Vector2(radius, radius) * 2.0
	c.position = Vector2(_mx(centre.x), centre.y) - Vector2(radius, radius)


## An x in the right-handed layout, mirrored when the sides are swapped.
func _mx(x: float) -> float:
	return size.x - x if _flip else x


func _mpoly(poly: PackedVector2Array) -> PackedVector2Array:
	if not _flip:
		return poly
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(size.x - p.x, p.y))
	return out


# --- Per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or _root == null or _root.model == null:
		return
	if MobileHudProfiles.revision != _rev:
		_rev = MobileHudProfiles.revision
		_layout()
		for c in get_children():
			(c as CanvasItem).queue_redraw()
	# Real time, so the HUD still answers (and animates) under a freeze or
	# the kill cam.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	_t += dt
	_dt_last = dt
	var m := _root.active_model()
	if _scheme == "simple" and _simple_goal >= 0.0:
		# Hold to fly: a thumb going down ramps to the chosen cruise, lifting
		# it ramps to a stop. Only while ramping — once there the throttle is
		# left alone, so the keyboard (or anything else) can still drive it.
		var rate := SIMPLE_SPOOL_UP if _simple_goal > m.command.throttle else SIMPLE_SPOOL_DOWN
		var next := move_toward(m.command.throttle, _simple_goal, rate * dt)
		_root.set_throttle(next)
		if is_equal_approx(next, _simple_goal):
			_simple_goal = -1.0
	elif _throttle_dir != 0.0:
		_root.set_throttle(m.command.throttle + _throttle_dir * THROTTLE_RATE * dt)
	# Keyboard steering shows on the stick, the same as the desktop one.
	_stick.set_external(Vector2(-m.command.yaw, -m.command.pitch))
	_fire.active = _root._button_firing
	_boost.active = m.command.boost
	_lock.active = _root.locked_target != null and is_instance_valid(_root.locked_target)
	_update_juice(m, dt)
	_live.queue_redraw()
	_stick.queue_redraw()


## Watch the hull, shield and speed for changes worth a reaction.
func _update_juice(m: FlightModel, dt: float) -> void:
	var P := MobileHudProfiles.profile()
	var hp := clampf(_root.player_hp / maxf(_root.player_max_hp, 1.0), 0.0, 1.0)
	var sh := 0.0
	if _root.player_max_shield > 0.0:
		sh = clampf(_root.player_shield / _root.player_max_shield, 0.0, 1.0)
	if _hp_prev < 0.0:
		_hp_prev = hp
		_sh_prev = sh
	var hp_drop := _hp_prev - hp
	if hp_drop > 0.002:
		_hp_flash = 1.0
		_title_pop = 1.0
		_shake = minf(_shake + 0.3 + hp_drop * 8.0, 1.0)
		if hp_drop >= BURST_MIN_HIT and bool(P.get("comic_fx", false)):
			_burst(HIT_WORDS[randi() % HIT_WORDS.size()], P["hull"], 1.0 + minf(hp_drop * 4.0, 0.6), hp)
	elif hp - _hp_prev > 0.01:
		_heal_glow = 1.0
	var sh_drop := _sh_prev - sh
	if sh_drop > 0.002:
		_sh_flash = 1.0
		_shake = minf(_shake + 0.12 + sh_drop * 3.0, 1.0)
		if sh_drop >= BURST_MIN_HIT * 2.0 and bool(P.get("comic_fx", false)) and _bursts.size() < 3:
			_burst(SHIELD_WORDS[randi() % SHIELD_WORDS.size()], P["shield"], 0.8, sh)
	_hp_prev = hp
	_sh_prev = sh
	# The ghost of lost health hangs a beat, then drains after the bar.
	_hp_ghost = hp if hp >= _hp_ghost else maxf(_hp_ghost - (0.45 if _hp_flash < 0.5 else 0.0) * dt, hp)
	_sh_ghost = sh if sh >= _sh_ghost else maxf(_sh_ghost - (0.6 if _sh_flash < 0.5 else 0.0) * dt, sh)
	_hp_flash = move_toward(_hp_flash, 0.0, dt * 2.2)
	_sh_flash = move_toward(_sh_flash, 0.0, dt * 2.5)
	_heal_glow = move_toward(_heal_glow, 0.0, dt * 1.5)
	_band_flash = move_toward(_band_flash, 0.0, dt * 2.5)
	_title_pop = move_toward(_title_pop, 0.0, dt * 2.8)
	_shake = move_toward(_shake, 0.0, dt * 3.0)
	var amp := _shake * _shake * _u * 0.018
	_shake_off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp
	_decor.position = _shake_off * 0.6

	# The speed number rolls toward the real speed and punches on each hundred.
	var kmh := absf(m.forward_speed()) * KMH
	if speed_meter_max > 0.0:
		# The meter shows the ship's whole speed, carry included (the runner
		# pulls the ship along its track on [member FlightModel.frame_velocity]).
		kmh = (m.velocity + m.frame_velocity).length() * KMH
	_speed_shown = lerpf(_speed_shown, kmh, 1.0 - exp(-14.0 * dt))
	var hundred := int(kmh / 100.0)
	if hundred > _last_hundred:
		_speed_pop = 1.0
	_last_hundred = hundred
	_speed_pop = move_toward(_speed_pop, 0.0, dt * 3.0)
	_combo_pop = move_toward(_combo_pop, 0.0, dt * 3.5)

	for b in _bursts:
		b["t"] = float(b["t"]) + dt
	_bursts = _bursts.filter(func(b: Dictionary) -> bool: return float(b["t"]) < float(b["life"]))


## Pop a comic shout where the hit landed on the hull ([member
## JuiceSettings.world_hit_words]), or over the bar that just lost a chunk,
## near where the fill now ends.
func _burst(word: String, col: Color, scale: float, frac_now: float) -> void:
	if JuiceSettings.world_hit_words:
		var at := _root.last_hit_point
		if at == Vector3.ZERO and _root.model != null:
			at = _root.model.global_position
		_root.hit_word(word, at, col, scale)
		return
	var at := Vector2(
		_panel.size.x * clampf(0.3 + frac_now * 0.5, 0.35, 0.8) + randf_range(-1.0, 1.0) * _u * 0.03,
		_panel.end.y + _u * randf_range(0.02, 0.07)
	)
	_bursts.append({
		"pos": at, "t": 0.0, "life": 0.9, "word": word, "rot": randf_range(-0.35, 0.35),
		"size": scale, "col": col, "seed": randi(),
	})
	if _bursts.size() > 4:
		_bursts.pop_front()


# --- Static art ---------------------------------------------------------------

func _draw_decor() -> void:
	var P := MobileHudProfiles.profile()
	var w := size.x
	var h := size.y
	var c := _decor
	var comic := bool(P.get("comic_fx", false))
	if bool(P["bands"]):
		# Comic-page framing: the top band is a slab cut on the diagonal, with
		# a white gutter and an ink line round it, like a panel on a printed
		# page. (The two slabs along the bottom edge went: they did nothing.)
		_comic_slab(c, _band_quad, P["band"], P, Color(0, 0, 0, 0), false, false)
	var quad := _skew_quad(_panel, float(P["skew"]) * -1.0)
	var edge: Color = P["panel_edge"]
	if comic and edge.a > 0.0:
		# Printed drop shadow: the panel's ink, knocked down and right.
		var shadow := quad.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(_u * 0.014, _u * 0.014)
		c.draw_colored_polygon(_mpoly(shadow), Color(edge, 0.85))
	quad = _mpoly(quad)
	if comic:
		_comic_slab(c, quad, P["panel"], P, P["panel_dots"] if bool(P["halftone"]) else Color(0, 0, 0, 0), false, not _flip)
		return
	c.draw_colored_polygon(quad, P["panel"])
	if bool(P["halftone"]):
		_halftone(c, quad, P["panel_dots"], not _flip)
	if edge.a > 0.0:
		var closed := quad.duplicate()
		closed.append(quad[0])
		c.draw_polyline(closed, edge, maxf(2.0, _u * 0.008), true)


## One comic panel: ink outline, white gutter, the fill, then halftone dots
## (if [param dots] is visible) and diagonal speed-line hatching ([param lines]).
## Borders are grown from the shape itself (mitred), so corners stay sharp.
func _comic_slab(
	c: Control, poly: PackedVector2Array, fill: Color, P: Dictionary, dots: Color,
	lines: bool, grow_right: bool
) -> void:
	if poly.size() < 3:
		return
	var ink: Color = P["panel_edge"]
	var gutter: Color = P.get("gutter", Color.WHITE)
	var outer := Geometry2D.offset_polygon(poly, _u * 0.016, Geometry2D.JOIN_MITER)
	var mid := Geometry2D.offset_polygon(poly, _u * 0.009, Geometry2D.JOIN_MITER)
	if not outer.is_empty() and ink.a > 0.0:
		c.draw_colored_polygon(outer[0], ink)
	if not mid.is_empty():
		c.draw_colored_polygon(mid[0], gutter)
	var inner := Geometry2D.offset_polygon(poly, _u * 0.003, Geometry2D.JOIN_MITER)
	if not inner.is_empty() and ink.a > 0.0:
		c.draw_colored_polygon(inner[0], ink)
	c.draw_colored_polygon(poly, fill)
	if dots.a > 0.0:
		_halftone(c, poly, dots, grow_right)
	if lines:
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var step := _u * 0.028
		var x := box.position.x - box.size.y
		var line_col := Color(fill.lightened(0.5), 0.55)
		while x < box.end.x:
			var seg := PackedVector2Array([Vector2(x, box.end.y), Vector2(x + box.size.y * 1.3, box.position.y)])
			for piece in Geometry2D.intersect_polyline_with_polygon(seg, poly):
				c.draw_polyline(piece, line_col, maxf(1.0, _u * 0.004), true)
			x += step


## A parallelogram in [param r], its bottom edge slid by [param skew] × height
## (negative: the right side leans in, like the health panel's cut corner).
func _skew_quad(r: Rect2, skew: float) -> PackedVector2Array:
	var off := r.size.y * skew
	if skew < 0.0:
		return PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x + off, r.end.y), Vector2(r.position.x, r.end.y),
		])
	return PackedVector2Array([
		r.position + Vector2(off, 0.0), Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
	])


## Comic halftone: a dot grid clipped to [param poly], the dots growing toward
## one end so the fill reads as shaded print.
func _halftone(c: Control, poly: PackedVector2Array, col: Color, grow_right: bool) -> void:
	if col.a <= 0.0:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var step := maxf(_u * 0.022, 4.0)
	# Dots are placed by their centre: test against the shape pulled in by a
	# dot's radius, or the edge dots poke out past the ink line.
	var inner := Geometry2D.offset_polygon(poly, -step * 0.45, Geometry2D.JOIN_MITER)
	var test := inner[0] if not inner.is_empty() else poly
	var y := box.position.y + step * 0.5
	var row := 0
	while y < box.end.y:
		var x := box.position.x + step * (0.5 + 0.5 * float(row % 2))
		while x < box.end.x:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, test):
				var t := (x - box.position.x) / maxf(box.size.x, 1.0)
				if not grow_right:
					t = 1.0 - t
				c.draw_circle(p, step * 0.42 * lerpf(0.15, 1.0, t), col)
			x += step
		y += step * 0.87
		row += 1


# --- Live readouts --------------------------------------------------------------

func _draw_live() -> void:
	if _root == null or _root.model == null:
		return
	var P := MobileHudProfiles.profile()
	var c := _live
	var m := _root.active_model()
	var comic := bool(P.get("comic_fx", false))

	# Health panel: hull and shield bars with icon tabs, then the title. The
	# whole group jolts with the hit shake.
	var hp := clampf(_root.player_hp / maxf(_root.player_max_hp, 1.0), 0.0, 1.0)
	var sh := clampf(_root.player_shield / maxf(_root.player_max_shield, 1.0), 0.0, 1.0)
	if _root.player_max_shield <= 0.0:
		sh = 0.0
	_draw_off = _shake_off
	c.draw_set_transform(_draw_off)
	var ib := _u * 0.055
	var gap := _u * 0.012
	var x := _u * 0.03
	var bar_w := _panel.size.x - x * 2.0 - ib - gap - _panel.size.y * float(P["skew"]) * 0.45
	var y1 := _u * 0.028
	var y2 := y1 + ib + gap
	_icon_tab(c, Rect2(x, y1, ib, ib), "hull", P, _hp_flash)
	_bar(c, Rect2(x + ib + gap, y1 + ib * 0.14, bar_w, ib * 0.72), hp, _hp_ghost, P["hull"], P, _hp_flash, comic)
	# The shield bar only while there is a shield (the power-up's bubble, or
	# the design's own with [member JuiceSettings.design_shields]).
	if _root.player_max_shield > 0.0:
		_icon_tab(c, Rect2(x, y2, ib, ib), "shield", P, _sh_flash)
		_bar(c, Rect2(x + ib + gap, y2 + ib * 0.14, bar_w, ib * 0.72), sh, _sh_ghost, P["shield"], P, _sh_flash, comic)
	var low := hp < 0.25 and hp > 0.0
	if low:
		var pulse := 0.5 + 0.5 * sin(_t * 12.0)
		var quad := _mpoly(_skew_quad(_panel, float(P["skew"]) * -1.0))
		quad.append(quad[0])
		c.draw_polyline(quad, Color(1.0, 0.15, 0.15, pulse), maxf(3.0, _u * 0.012), true)
	if _heal_glow > 0.0:
		var quad2 := _mpoly(_skew_quad(_panel, float(P["skew"]) * -1.0))
		quad2.append(quad2[0])
		c.draw_polyline(quad2, Color(0.4, 1.0, 0.55, _heal_glow), maxf(3.0, _u * 0.01), true)
	# HEALTH: pops on a hit, goes red and wobbles when low.
	var pop := _ease_back(1.0 - _title_pop) if _title_pop > 0.0 else 1.0
	var title_scale := 1.0 + 0.22 * _title_pop * (1.0 - pop * 0.5)
	var title_col: Color = P["title"]
	var wobble := 0.0
	if low:
		title_col = title_col.lerp(Color("ff3b3b"), 0.5 + 0.5 * sin(_t * 12.0))
		wobble = sin(_t * 9.0) * 0.06
	# Centred under the bars rather than hard against the panel's edge.
	var title_x := x + (ib + gap + bar_w) * 0.5
	_text(c, "HEALTH", "title", Vector2(title_x, y2 + ib + _u * 0.078), _u * 0.08 * title_scale, title_col,
		P["title_outline"], P, false, -0.25, true, wobble)
	_draw_off = Vector2.ZERO
	c.draw_set_transform(_draw_off)

	if bool(P["bands"]):
		_draw_band(c, P)

	# Comic bursts ride over the panel's lower edge.
	for b in _bursts:
		_draw_burst(c, b, P)

	if JuiceSettings.combo_counter:
		_draw_combo(c, P)

	if FlightRoot.profile_is_one_thumb(_move_profile):
		var ship := _root.active_ship_node()
		if ship != null:
			_radar.draw_radar(c, ship, _root.live_enemies(), _root.landmarks(),
				Vector2(_mx(_radar_c.x), _radar_c.y), _root.locked_target)

	var kmh := roundi(_speed_shown)
	_draw_speed_meter(c, P, m, kmh)
	# The throttle dial means nothing where swipe or slingshot fly the ship.
	if _scheme != "simple" and not FlightRoot.profile_is_one_thumb(_move_profile):
		_draw_dial(c, m, P, kmh)


## The top band is the guns' charge bar: it fills with the capacitor in the
## active weapon's colour, from the health panel's side, and carries the
## weapon's name. Too little charge for a shot and the fill pulses red. It
## flashes when the weapon changes or it is tapped (a tap still opens the
## scenario picker — no text says so; it's a test-bench shortcut).
func _draw_band(c: Control, P: Dictionary) -> void:
	if _band_quad.size() < 4:
		return
	var sys := _root.active_systems()
	var line := ""
	var frac := 0.0
	var wcol := Color(P["shield"])
	var starved := false
	if sys != null:
		var w := sys.get_active_weapon()
		line = String(w.get("short", w.get("name", ""))).to_upper()
		frac = sys.charge_fraction()
		wcol = w.get("color", wcol)
		starved = not sys.has_energy_for_shot()
	_charge_shown = frac if _charge_shown < 0.0 else lerpf(_charge_shown, frac, 1.0 - exp(-12.0 * _dt_last))
	if line != _band_text_prev:
		if _band_text_prev != "":
			_band_flash = 1.0
		_band_text_prev = line
	# The empty trough, then the charge. The band quad runs [start, end, end
	# bottom, start bottom] from the health panel's side, so lerping along its
	# top and bottom edges fills sideways, keeping the slab's slant, and drains
	# back toward the panel. Everything is clipped against the panel (and its
	# ink), which overlaps the band's start: the fill used to paint over it.
	var q := _band_quad
	var panel := _mpoly(_skew_quad(_panel, float(P["skew"]) * -1.0))
	var inked := Geometry2D.offset_polygon(panel, _u * 0.016, Geometry2D.JOIN_MITER)
	if not inked.is_empty():
		panel = inked[0]
	_fill_clipped(c, q, panel, Color(P["bar_bg"], 0.85))
	if _charge_shown > 0.002:
		var f := clampf(_charge_shown, 0.0, 1.0)
		var a := q[0].lerp(q[1], f)
		var b := q[3].lerp(q[2], f)
		var col := wcol
		if starved:
			col = col.lerp(Color("ff3b3b"), 0.5 + 0.5 * sin(_t * 14.0))
		_fill_clipped(c, PackedVector2Array([q[0], a, b, q[3]]), panel, col)
		# A lighter top edge, like the health bars.
		_fill_clipped(c, PackedVector2Array([q[0], a, a.lerp(b, 0.28), q[0].lerp(q[3], 0.28)]), panel, Color(1, 1, 1, 0.25))
		# The hot leading edge where the charge ends.
		c.draw_line(a, b, Color(1, 1, 1, 0.7), maxf(2.0, _u * 0.006), true)
	if _band_flash > 0.0:
		_fill_clipped(c, _band_quad, panel, Color(1, 1, 1, _band_flash * 0.6))
	var bh := _band_quad[3].y - _band_quad[0].y
	var left := minf(_band_quad[0].x, _band_quad[3].x)
	var right := maxf(_band_quad[1].x, _band_quad[2].x)
	var avail := right - left - bh * 1.6
	var font := MobileHudProfiles.font("label")
	if font == null:
		font = get_theme_default_font()
	var px := bh * 0.46
	var fs := maxi(roundi(px * MobileHudProfiles.style("size_label")), 6)
	var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > avail and tw > 0.0:
		px *= avail / tw
	var cx := (left + right) * 0.5 - bh * 0.3 * (-1.0 if _flip else 1.0)
	_text(c, line, "label", Vector2(cx, bh * 0.66), px, Color.WHITE, P["panel_edge"], P,
		false, -0.15, true, 0.0, false, 3)
	# A timed level's clock hangs right under the band, big; the last ten
	# seconds pulse red.
	var left_s := _root.scenarios.time_left() if _root.scenarios != null else -1.0
	if left_s >= 0.0:
		var urgent := left_s <= 10.0
		var tcol := Color("ffc61a")
		if urgent:
			tcol = tcol.lerp(Color("ff3b3b"), 0.5 + 0.5 * sin(_t * 12.0))
		_text(c, FlightScenarios.clock_text(left_s), "title", Vector2(cx, bh * 1.75), bh * (0.95 if urgent else 0.8),
			tcol, P["panel_edge"], P, false, -0.08, true, 0.0, false, 4)


## Draw [param poly] minus [param cut] (the health panel over the band's start).
func _fill_clipped(c: Control, poly: PackedVector2Array, cut: PackedVector2Array, col: Color) -> void:
	# Both shapes are convex, so the difference never has holes.
	for piece in Geometry2D.clip_polygons(poly, cut):
		if piece.size() >= 3:
			c.draw_colored_polygon(piece, col)


## The speed, top right: a round gauge in the throttle dial's style — its ring
## fills (green through yellow to red) toward [member speed_meter_max] (the
## runner's top) or boost speed, ticked every tenth, with the number in the
## profile's number font inside and KMH under it. Punches on each hundred;
## boost jiggles it and radiates rays behind it.
func _draw_speed_meter(c: Control, P: Dictionary, m: FlightModel, kmh: int) -> void:
	var top := speed_meter_max if speed_meter_max > 0.0 else maxf(m.top_speed, 1.0) * FlightModel.BOOST_SPEED
	var frac := clampf(_speed_shown / KMH / top, 0.0, 1.0)
	var col := Color("46ff9b").lerp(Color("ffe23d"), clampf(frac * 2.0, 0.0, 1.0)).lerp(
		Color("ff3b3b"), clampf(frac * 2.0 - 1.0, 0.0, 1.0))
	var boosting := m.command.boost
	var comic := bool(P.get("comic_fx", false))
	var sp := 1.0 + 0.12 * _speed_pop * _speed_pop
	var r := _u * 0.12 * sp
	# Right-handed centre (mirrored below for a swapped layout).
	var ctr := Vector2(_speed_right - _u * 0.12, _speed_top + _u * 0.13)
	if boosting:
		ctr += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _u * 0.004
	if boosting and comic:
		_speed_rays(c, ctr, P)
	var dc := Vector2(_mx(ctr.x), ctr.y)
	var rim: Color = P["dial_ring"]
	c.draw_circle(dc, r, P["button"])
	c.draw_arc(dc, r, 0.0, TAU, 56, Color(rim, 0.35), maxf(2.0, _u * 0.006), true)
	var start := PI * 0.75
	for i in 11:
		var a := start + PI * 1.5 * float(i) / 10.0
		var d := Vector2.from_angle(a)
		c.draw_line(dc + d * r * 0.72, dc + d * r * (0.8 if i % 5 else 0.66), Color(rim, 0.5), maxf(1.0, _u * 0.004), true)
	if frac > 0.005:
		var sweep := PI * 1.5 * frac
		c.draw_arc(dc, r * 0.9, start, start + sweep, 48, col, maxf(3.0, _u * 0.016), true)
		c.draw_circle(dc + Vector2.from_angle(start + sweep) * r * 0.9, _u * 0.012, col.lightened(0.4))
	var num_col: Color = P["speed"]
	if boosting:
		num_col = num_col.lerp(P["speed_unit"], 0.35 + 0.25 * sin(_t * 20.0))
	_text(c, str(kmh), "number", Vector2(ctr.x, ctr.y + r * 0.14), r * 0.5, num_col, P["speed_outline"], P, false, 0.0, true)
	_text(c, "KMH", "label", Vector2(ctr.x, ctr.y + r * 0.46), r * 0.26, Color(P["speed"], 0.8), Color(0, 0, 0, 0), P, false, 0.0, true)


## The combo counter: "x3" and COMBO under the top band while a chain of
## kills is live ([ComboChain]), popping on each new kill, with a bar under it
## draining as the chain window runs out.
func _draw_combo(c: Control, P: Dictionary) -> void:
	var chain := _root.combo
	var n := chain.count if chain.is_live() else 0
	if n != _combo_prev:
		if n > _combo_prev and n >= 2:
			_combo_pop = 1.0
		_combo_prev = n
	if n < 2:
		return
	var portrait := size.y > size.x
	var y := (_panel.end.y + _u * 0.2) if portrait else _u * 0.2
	var at := Vector2(size.x * 0.5, y)
	var pop := 1.0 + 0.45 * _combo_pop * _combo_pop
	var hue := Color("ffe23d").lerp(Color("ff3fa4"), clampf(float(n - 2) / 6.0, 0.0, 1.0))
	var wob := sin(_t * 10.0) * 0.05 * _combo_pop
	_text(c, "x%d" % n, "number", at, _u * 0.11 * pop, hue, P["speed_outline"], P, false, -0.2, true, wob, false, 3)
	_text(c, "COMBO!", "title", at + Vector2(0.0, _u * 0.06), _u * 0.05, Color.WHITE, P["speed_outline"], P,
		false, -0.2, true, 0.0, false, 2)
	var left := chain.fraction_left()
	var bw := _u * 0.22
	var r := Rect2(at.x - bw * 0.5, at.y + _u * 0.085, bw * left, _u * 0.012)
	c.draw_rect(Rect2(at.x - bw * 0.5, r.position.y, bw, r.size.y), Color(0, 0, 0, 0.45), true)
	c.draw_rect(r, hue, true)


## Throttle dial: the ring fills with the throttle (reverse runs the other
## way in the unit colour), with ticks, a needle knob and the throttle % inside.
func _draw_dial(c: Control, m: FlightModel, P: Dictionary, _kmh: int) -> void:
	var rim: Color = P["dial_ring"]
	var dc := Vector2(_mx(_dial_c.x), _dial_c.y)
	c.draw_circle(dc, _dial_r, P["button"])
	c.draw_arc(dc, _dial_r, 0.0, TAU, 56, Color(rim, 0.35), maxf(2.0, _u * 0.006), true)
	var start := PI * 0.75
	for i in 11:
		var a := start + PI * 1.5 * float(i) / 10.0
		var d := Vector2.from_angle(a)
		c.draw_line(dc + d * _dial_r * 0.72, dc + d * _dial_r * (0.8 if i % 5 else 0.66), Color(rim, 0.5), maxf(1.0, _u * 0.004), true)
	var thr := clampf(m.command.throttle, -1.0, 1.0)
	if absf(thr) > 0.005:
		var sweep := PI * 1.5 * thr
		var col: Color = rim if thr > 0.0 else P["speed_unit"]
		c.draw_arc(dc, _dial_r * 0.9, start, start + sweep, 48, col, maxf(3.0, _u * 0.014), true)
		var tip := dc + Vector2.from_angle(start + sweep) * _dial_r * 0.9
		c.draw_circle(tip, _u * 0.011, col.lightened(0.4))
	# The throttle it sets (the speed has its own gauge up top).
	_text(c, "%d%%" % roundi(thr * 100.0), "number", Vector2(_dial_c.x, _dial_c.y + _u * 0.012), _u * 0.04, P["speed"], Color(0, 0, 0, 0), P, false, 0.0, true)
	_text(c, "THR", "label", Vector2(_dial_c.x, _dial_c.y + _u * 0.045), _u * 0.024, Color(P["speed"], 0.75), Color(0, 0, 0, 0), P, false, 0.0, true)


func _icon_tab(c: Control, r: Rect2, kind: String, P: Dictionary, flash: float) -> void:
	# A hit makes the tab jump: grow, then settle.
	var s := 1.0 + 0.25 * flash * flash
	var rr := Rect2(r.get_center() - r.size * s * 0.5, r.size * s)
	rr.position.x = _mx(rr.end.x) if _flip else rr.position.x
	c.draw_rect(rr, Color(P["icon_bg"]).lerp(Color.WHITE, flash * 0.6), true)
	var edge: Color = P["panel_edge"]
	if edge.a > 0.0:
		c.draw_rect(rr, edge, false, maxf(1.5, _u * 0.005))
	var ctr := rr.get_center()
	var sz := rr.size.x * 0.3
	var col: Color = Color(P["icon"]).lerp(P["hull"] if kind == "hull" else P["shield"], flash)
	if kind == "hull":
		var t := sz * 0.35
		c.draw_rect(Rect2(ctr - Vector2(sz, t), Vector2(sz * 2.0, t * 2.0)), col, true)
		c.draw_rect(Rect2(ctr - Vector2(t, sz), Vector2(t * 2.0, sz * 2.0)), col, true)
	else:
		var bolt := PackedVector2Array([
			Vector2(0.25, -1.0), Vector2(-0.55, 0.15), Vector2(-0.05, 0.15),
			Vector2(-0.25, 1.0), Vector2(0.55, -0.15), Vector2(0.05, -0.15),
		])
		for i in bolt.size():
			bolt[i] = ctr + bolt[i] * sz * 1.1
		c.draw_colored_polygon(bolt, col)


## A leaning parallelogram bar, x0..x0+w along the bottom edge, its top edge
## slid right by [param lean] × height (italic, like the comic lettering).
func _para(x0: float, y: float, w: float, h: float, lean: float) -> PackedVector2Array:
	return _mpoly(PackedVector2Array([
		Vector2(x0 + lean * h, y), Vector2(x0 + w + lean * h, y), Vector2(x0 + w, y + h), Vector2(x0, y + h),
	]))


func _bar(
	c: Control, r: Rect2, frac: float, ghost: float, col: Color, P: Dictionary,
	flash: float, comic: bool, label := ""
) -> void:
	var lean := 0.45 if comic else 0.0
	var x0 := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var edge: Color = P["panel_edge"]
	var ink := maxf(1.5, _u * 0.006)
	if comic and edge.a > 0.0:
		c.draw_colored_polygon(_para(x0 + _u * 0.007, y + _u * 0.007, w, h, lean), Color(edge, 0.9))
	c.draw_colored_polygon(_para(x0, y, w, h, lean), P["bar_bg"])
	# Segment ticks every 10%, under the fill so the empty part still reads
	# as a gauge.
	for i in range(1, 10):
		var xi := x0 + w * float(i) / 10.0
		c.draw_line(Vector2(_mx(xi), y + h), Vector2(_mx(xi + lean * h), y), Color(1, 1, 1, 0.08), maxf(1.0, _u * 0.003), true)
	# The lost chunk: white on impact, fading to a warm ghost as it drains.
	if ghost > frac + 0.001:
		var gcol := Color(1.0, 0.85, 0.5, 0.6).lerp(Color.WHITE, flash)
		c.draw_colored_polygon(_para(x0 + w * frac, y, w * (ghost - frac), h, lean), gcol)
	if frac > 0.001:
		var fw := w * frac
		c.draw_colored_polygon(_para(x0, y, fw, h, lean), col)
		# Body: a darker lower band and a light top edge.
		c.draw_colored_polygon(_para(x0, y + h * 0.62, fw, h * 0.38, lean), col.darkened(0.22))
		c.draw_colored_polygon(_para(x0 + lean * h * 0.72, y, fw, h * 0.26, lean), Color(1, 1, 1, 0.3))
		if comic:
			# Moving diagonal hatch, clipped to the fill by construction.
			var slope := lean + 0.9
			var spacing := h * 0.95
			var s0 := x0 - spacing + fmod(_t * _u * 0.04, spacing)
			var hatch := Color(col.lightened(0.45), 0.35)
			while s0 < x0 + fw:
				var a := Vector2(s0, y + h)
				var b := Vector2(s0 + slope * h, y)
				if s0 >= x0 and b.x <= x0 + fw + lean * h:
					c.draw_line(Vector2(_mx(a.x), a.y), Vector2(_mx(b.x), b.y), hatch, maxf(1.5, h * 0.18), true)
				s0 += spacing
		# A glint sweeps along the fill every couple of seconds.
		var g := fmod(_t * 0.5 + (0.0 if col == Color(P["hull"]) else 0.4), 1.8) - 0.2
		var gx := x0 + fw * g
		var gw := h * 0.55
		if g > 0.0 and gx + gw < x0 + fw:
			c.draw_colored_polygon(_para(gx, y, gw, h, lean + 0.7), Color(1, 1, 1, 0.28))
		# Hot leading edge.
		var ex := x0 + fw
		c.draw_line(Vector2(_mx(ex), y + h), Vector2(_mx(ex + lean * h), y), Color(1, 1, 1, 0.55 + 0.45 * flash), maxf(2.0, _u * 0.006), true)
	if flash > 0.0:
		c.draw_colored_polygon(_para(x0, y, w, h, lean), Color(1, 1, 1, flash * 0.35))
	if edge.a > 0.0:
		var outline := _para(x0, y, w, h, lean)
		outline.append(outline[0])
		c.draw_polyline(outline, edge, ink, true)
	# The number, tucked inside the bar's far end.
	var pct := label if label != "" else "%d%%" % roundi(frac * 100.0)
	_text(c, pct, "label", Vector2(x0 + w - h * 0.3, y + h * 0.78), h * 0.8, Color.WHITE,
		Color(edge, 0.9) if edge.a > 0.0 else Color(0, 0, 0, 0.6), P, true, 0.0, false, 0.0, true, 3)


## A comic starburst with its shout: pops in with an overshoot, holds, fades.
func _draw_burst(c: Control, b: Dictionary, P: Dictionary) -> void:
	var t := float(b["t"]) / float(b["life"])
	var grow := _ease_back(clampf(t * 5.0, 0.0, 1.0))
	var alpha := 1.0 - smoothstep(0.65, 1.0, t)
	var r := _u * 0.065 * float(b["size"]) * grow
	if r <= 0.5:
		return
	var pos: Vector2 = b["pos"]
	pos = Vector2(_mx(pos.x), pos.y - t * _u * 0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b["seed"])
	var pts := PackedVector2Array()
	var spikes := 14
	var rot := float(b["rot"])
	for i in spikes * 2:
		var a := rot + TAU * float(i) / float(spikes * 2)
		var k := 1.0 if i % 2 == 0 else 0.6
		pts.append(pos + Vector2.from_angle(a) * r * k * rng.randf_range(0.85, 1.15) * Vector2(1.35, 1.0))
	var edge: Color = P["panel_edge"]
	var shadow := pts.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(_u * 0.006, _u * 0.006)
	c.draw_colored_polygon(shadow, Color(edge, 0.9 * alpha))
	c.draw_colored_polygon(pts, Color(Color("ffe23d"), alpha))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(pos + (p - pos) * 0.72)
	c.draw_colored_polygon(inner, Color(Color.WHITE, alpha * 0.9))
	var closed := pts.duplicate()
	closed.append(pts[0])
	c.draw_polyline(closed, Color(edge, alpha), maxf(1.5, _u * 0.005), true)
	var word_col: Color = b["col"]
	_text(c, String(b["word"]), "title", pos + Vector2(0.0, r * 0.28), r * 0.72, Color(word_col, alpha),
		Color(edge, alpha), P, false, 0.0, true, rot * 0.5, false)


## Boost rays: a slow-turning fan of wedges behind the speed number.
func _speed_rays(c: Control, at: Vector2, P: Dictionary) -> void:
	var centre := Vector2(_mx(at.x), at.y)
	var col := Color(P["speed_unit"], 0.35)
	var n := 12
	for i in n:
		var a := _t * 0.8 + TAU * float(i) / float(n)
		var d := Vector2.from_angle(a)
		var side := d.orthogonal() * _u * 0.012
		var inner := centre + d * _u * 0.05
		var outer := centre + d * _u * (0.17 + 0.02 * sin(_t * 9.0 + float(i)))
		c.draw_colored_polygon(PackedVector2Array([inner + side * 0.3, outer + side, outer - side, inner - side * 0.3]), col)


## easeOutBack: overshoots a little past 1 and settles — the "pop".
static func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


## One line of HUD text in a role's font. [param right] aligns its right edge
## to [param pos].x, [param centre] its middle; [param skew] leans it (comic
## italics, only when the profile has an outline — the clean looks stay upright),
## scaled by the profile's lean style; [param rot] turns it. [param pos] is in
## the right-handed layout and mirrored here (a right-aligned readout becomes
## left-aligned on the mirrored side) unless [param mirror] is false.
## [param min_outline] floors the outline so small labels keep their ink.
func _text(
	c: Control, text: String, role: String, pos: Vector2, px: float, col: Color,
	outline: Color, P: Dictionary, right: bool, skew: float, centre := false,
	rot := 0.0, mirror := true, min_outline := 0
) -> void:
	var font := MobileHudProfiles.font(role)
	if font == null:
		font = get_theme_default_font()
	var fs := maxi(roundi(px * MobileHudProfiles.style("size_" + role)), 6)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := pos
	if mirror and _flip:
		at.x = size.x - at.x
		if not centre:
			right = not right
	if right:
		at.x -= width
	elif centre:
		at.x -= width * 0.5
	var ol := int(P["outline"])
	var ol_px := roundi(float(ol) * _u / 360.0 * MobileHudProfiles.style("outline"))
	if ol > 0:
		ol_px = maxi(ol_px, 2)
	ol_px = maxi(ol_px, min_outline if outline.a > 0.0 else 0)
	if ol <= 0:
		skew = 0.0
	skew *= MobileHudProfiles.style("lean")
	var xf := Transform2D(0.0, Vector2.ONE, skew, at)
	if not is_zero_approx(rot):
		# Turn about the text's own middle.
		var mid := Vector2(width * 0.5, -fs * 0.35)
		xf = Transform2D(rot, at + mid) * Transform2D(0.0, Vector2.ONE, skew, -mid)
	c.draw_set_transform_matrix(Transform2D(0.0, _draw_off) * xf)
	if ol_px > 0 and outline.a > 0.0:
		c.draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol_px, outline)
	c.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	c.draw_set_transform(_draw_off)


## Vector icons for the round buttons, drawn centred on [param at] at scale
## [param s] (about half the button's radius).
static func draw_icon(c: CanvasItem, kind: String, at: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.22)
	match kind:
		"fire":
			# A rocket heading up-right, with its flame.
			var body := PackedVector2Array([
				Vector2(0.0, -1.0), Vector2(0.3, -0.55), Vector2(0.3, 0.45), Vector2(-0.3, 0.45), Vector2(-0.3, -0.55),
			])
			var fin_r := PackedVector2Array([Vector2(0.3, 0.05), Vector2(0.62, 0.62), Vector2(0.3, 0.45)])
			var fin_l := PackedVector2Array([Vector2(-0.3, 0.05), Vector2(-0.3, 0.45), Vector2(-0.62, 0.62)])
			var flame := PackedVector2Array([Vector2(0.2, 0.52), Vector2(0.0, 1.05), Vector2(-0.2, 0.52)])
			for poly in [body, fin_r, fin_l, flame]:
				var pts := PackedVector2Array()
				for p: Vector2 in poly:
					pts.append(at + p.rotated(PI * 0.25) * s * 1.15)
				c.draw_colored_polygon(pts, col if poly != flame else Color("ffb21e"))
		"boost":
			var dart := PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.75, 0.85), Vector2(0.0, 0.4), Vector2(-0.75, 0.85)])
			for i in dart.size():
				dart[i] = at + dart[i] * s
			c.draw_colored_polygon(dart, col)
		"cycle":
			var r := s * 0.85
			c.draw_arc(at, r, deg_to_rad(200.0), deg_to_rad(340.0), 20, col, w, true)
			c.draw_arc(at, r, deg_to_rad(20.0), deg_to_rad(160.0), 20, col, w, true)
			for a: float in [deg_to_rad(340.0), deg_to_rad(160.0)]:
				var tip := at + Vector2.from_angle(a) * r
				var tangent := Vector2.from_angle(a + PI * 0.5)
				var radial := Vector2.from_angle(a)
				c.draw_colored_polygon(PackedVector2Array([
					tip + tangent * s * 0.45, tip + radial * s * 0.32, tip - radial * s * 0.32,
				]), col)
		"up", "down":
			var d := -1.0 if kind == "up" else 1.0
			c.draw_polyline(PackedVector2Array([
				at + Vector2(-s, -d * s * 0.3), at + Vector2(0.0, d * s * 0.45), at + Vector2(s, -d * s * 0.3),
			]), col, w * 1.3, true)
		"menu":
			for i in 3:
				var yy := (float(i) - 1.0) * s * 0.55
				c.draw_line(at + Vector2(-s * 0.7, yy), at + Vector2(s * 0.7, yy), col, w, true)
		"view":
			# An eye: two arcs and a pupil.
			c.draw_arc(at + Vector2(0.0, s * 0.55), s * 0.95, deg_to_rad(215.0), deg_to_rad(325.0), 16, col, w, true)
			c.draw_arc(at - Vector2(0.0, s * 0.55), s * 0.95, deg_to_rad(35.0), deg_to_rad(145.0), 16, col, w, true)
			c.draw_circle(at, s * 0.28, col)
		"roll_l", "roll_r":
			# A curling arrow round the nose.
			var dir := -1.0 if kind == "roll_l" else 1.0
			var r := s * 0.8
			c.draw_arc(at, r, deg_to_rad(200.0), deg_to_rad(340.0), 20, col, w, true)
			var end_a := deg_to_rad(340.0) if dir > 0.0 else deg_to_rad(200.0)
			var tip := at + Vector2.from_angle(end_a) * r
			var tangent := Vector2.from_angle(end_a + PI * 0.5) * dir
			var radial := Vector2.from_angle(end_a)
			c.draw_colored_polygon(PackedVector2Array([
				tip + tangent * s * 0.5, tip + radial * s * 0.35, tip - radial * s * 0.35,
			]), col)
			c.draw_circle(at, s * 0.18, col)
		"lock":
			# Crosshair brackets.
			var k := s * 0.85
			var l := s * 0.4
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					var corner := at + Vector2(sx * k, sy * k)
					c.draw_line(corner, corner - Vector2(sx * l, 0.0), col, w, true)
					c.draw_line(corner, corner - Vector2(0.0, sy * l), col, w, true)
			c.draw_circle(at, s * 0.16, col)


## Spray-paint neon per button, for the profiles with [code]graffiti[/code] on:
## a glowing, gapped ring with scope ticks and paint drips over a dark core.
const NEON := {
	"fire": Color("8cff3a"), "boost": Color("ff3fa4"), "cycle": Color("33d6ff"),
	"lock": Color("ff4fd8"), "view": Color("33d6ff"), "menu": Color("33d6ff"),
	"roll_l": Color("ffe23d"), "roll_r": Color("ffe23d"), "up": Color("ff3f8e"), "down": Color("ff3f8e"),
}
## Icon colour when it differs from the ring (the big fire button's pink
## rocket in a green ring, like a sticker).
const NEON_ICON := {"fire": Color("ff3fd0")}


static func graffiti_on() -> bool:
	return bool(MobileHudProfiles.profile().get("graffiti", false))


## A neon ring: soft halo, dark core, the ring cut into [param segments] arcs
## (turned by [param rot]), scope ticks in the gaps and drips hanging under it.
## Shared by the round buttons and the stick.
static func draw_neon_ring(
	c: CanvasItem, at: Vector2, r: float, col: Color, segments: int, rot: float,
	ticks: bool, drips: bool, lit: bool
) -> void:
	for k in 4:
		c.draw_arc(at, r * (1.02 + 0.07 * float(k)), 0.0, TAU, 48, Color(col, (0.16 if lit else 0.1) - 0.025 * float(k)), r * 0.12, true)
	c.draw_circle(at, r * 0.9, Color(0.05, 0.03, 0.09, 0.8))
	if lit:
		c.draw_circle(at, r * 0.9, Color(col, 0.16))
	var ring := col.lightened(0.25) if lit else col
	var gap := 0.28 if segments > 1 else 0.0
	for i in segments:
		var a0 := rot + TAU * float(i) / float(segments) + gap * 0.5
		c.draw_arc(at, r * 0.84, a0, a0 + TAU / float(segments) - gap, 24, ring, r * 0.13, true)
		if ticks:
			var mid := rot + TAU * float(i) / float(segments)
			var d := Vector2.from_angle(mid)
			c.draw_line(at + d * r * 0.72, at + d * r * 1.08, ring, r * 0.07, true)
	c.draw_arc(at, r * 0.6, 0.0, TAU, 40, Color(col, 0.35), maxf(1.0, r * 0.03), true)
	if drips:
		# Fixed per ring size so they don't crawl: three runs under the ring.
		for dd: Vector3 in [Vector3(98.0, 0.28, 0.07), Vector3(76.0, 0.16, 0.055), Vector3(118.0, 0.12, 0.05)]:
			var p0 := at + Vector2.from_angle(deg_to_rad(dd.x)) * r * 0.9
			var p1 := p0 + Vector2(0.0, r * dd.y)
			c.draw_line(p0, p1, col, r * dd.z * 1.4, true)
			c.draw_circle(p1, r * dd.z, col)
	# Overspray: a few fixed flecks just outside the ring.
	for k in 7:
		var a := float(k) * 2.39996 + 0.7
		var rr := r * (1.1 + 0.12 * float(k % 3))
		c.draw_circle(at + Vector2.from_angle(a) * rr, r * (0.02 + 0.012 * float(k % 2)), Color(col, 0.55))


## A round, hold-able HUD button: [signal down] on press, [signal up] on
## release. Touch and mouse both; each finger is tracked by index so the
## stick thumb and a button thumb never steal each other's release.
## Squashes while held, pops back and throws a ripple ring on press.
class RoundButton extends Control:
	signal down
	signal up

	var kind := "fire"
	var big := false
	## Icon only, no disc — the throttle chevrons.
	var flat := false
	## Lit: the thing it controls is on (firing, boosting, a lock held).
	var active := false
	var _held := false
	var _pointer := -1
	var _ripple := 0.0
	var _pop := 0.0
	var _spin := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_set_held(mb.pressed)
				accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pointer = st.index
				_set_held(true)
			elif st.index == _pointer:
				_pointer = -1
				_set_held(false)
			accept_event()

	func _set_held(on: bool) -> void:
		if on == _held:
			return
		_held = on
		queue_redraw()
		if on:
			_ripple = 1.0
			down.emit()
		else:
			_pop = 1.0
			up.emit()

	func _notification(what: int) -> void:
		# Hidden mid-press (the layout switched away): let go cleanly.
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
			_set_held(false)

	func _process(delta: float) -> void:
		var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
		if _ripple > 0.0 or _pop > 0.0 or active or _held:
			_ripple = move_toward(_ripple, 0.0, dt * 3.0)
			_pop = move_toward(_pop, 0.0, dt * 5.0)
			_spin += dt * (3.0 if active else 1.0)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var base_r := r
		if MobileHud.graffiti_on():
			# Leave room for the halo and drips inside the control's rect.
			r *= 0.8
			base_r = r
		if _held:
			r *= 0.86
		r *= 1.0 + 0.1 * sin(_pop * PI)
		if MobileHud.graffiti_on():
			_draw_graffiti(c, r, base_r)
			return
		var rim := MobileHudProfiles.color("fire_rim" if big else "button_rim")
		var icon := MobileHudProfiles.color("button_icon")
		if flat:
			MobileHud.draw_icon(self, kind, c, r * 0.7, rim if not _held else icon)
			return
		if _ripple > 0.0:
			var t := 1.0 - _ripple
			draw_arc(c, base_r * (0.9 + t * 0.55), 0.0, TAU, 48, Color(rim, _ripple * 0.8), maxf(2.0, base_r * 0.08 * _ripple), true)
		draw_circle(c, r, MobileHudProfiles.color("button"))
		if active:
			draw_circle(c, r, Color(rim, 0.22))
			# A turning dashed ring: "this is running".
			var dashes := 10
			for i in dashes:
				var a := _spin + TAU * float(i) / float(dashes)
				draw_arc(c, r * 1.1, a, a + TAU / float(dashes) * 0.5, 6, Color(rim, 0.85), maxf(2.0, r * 0.06), true)
		draw_arc(c, r, 0.0, TAU, 56, rim, maxf(2.0, r * (0.09 if big else 0.07)), true)
		if big:
			draw_arc(c, r * 0.8, 0.0, TAU, 56, Color(rim, 0.3), maxf(1.5, r * 0.03), true)
		if _held:
			draw_circle(c, r, Color(1, 1, 1, 0.14))
		MobileHud.draw_icon(self, kind, c, r * (0.42 if big else 0.5), icon)

	func _draw_graffiti(c: Vector2, r: float, base_r: float) -> void:
		var col: Color = MobileHud.NEON.get(kind, Color("33d6ff"))
		var icon_col: Color = MobileHud.NEON_ICON.get(kind, col)
		if flat:
			# Double chevrons, sprayed: a glow pass under the stroke.
			for k in 2:
				var off := Vector2(0.0, (float(k) - 0.5) * r * 0.55 * (-1.0 if kind == "up" else 1.0))
				MobileHud.draw_icon(self, kind, c + off, r * 0.78, Color(col, 0.25))
				MobileHud.draw_icon(self, kind, c + off, r * 0.62, col if not _held else col.lightened(0.4))
			return
		if _ripple > 0.0:
			var t := 1.0 - _ripple
			draw_arc(c, base_r * (0.95 + t * 0.5), 0.0, TAU, 48, Color(col, _ripple * 0.8), maxf(2.0, base_r * 0.1 * _ripple), true)
		var segments := 4 if big else 3
		var rot := (_spin if active else 0.0) + (PI * 0.25 if big else -PI * 0.5)
		MobileHud.draw_neon_ring(self, c, r, col, segments, rot, big, big or kind == "boost", active or _held)
		var s := r * (0.44 if big else 0.5)
		MobileHud.draw_icon(self, kind, c, s * 1.15, Color(icon_col, 0.3))
		MobileHud.draw_icon(self, kind, c, s, icon_col)


## The flight stick in the profile's look: a dark disc, a rim, four arrow
## ticks and a raised knob, plus a lit wedge on the rim in the direction it
## is pushed. In the graffiti look it is a sprayed neon scope with chevrons.
## All input handling is [VirtualStick]'s.
class Stick extends VirtualStick:
	func _draw() -> void:
		var r := radius()
		var centre := _origin if _dragging else rest_centre()
		if MobileHud.graffiti_on():
			_draw_graffiti(centre, r * 0.86)
			return
		var rim := MobileHudProfiles.color("button_rim")
		draw_circle(centre, r, MobileHudProfiles.color("stick"))
		draw_arc(centre, r, 0.0, TAU, 64, rim, maxf(2.0, r * 0.035), true)
		draw_arc(centre, r * 0.84, 0.0, TAU, 64, Color(rim, 0.22), maxf(1.0, r * 0.015), true)
		var push := value.length()
		if push > 0.05:
			var a := value.angle()
			draw_arc(centre, r * 0.93, a - 0.55, a + 0.55, 20, Color(MobileHudProfiles.color("dial_ring"), 0.4 + 0.5 * push), maxf(3.0, r * 0.1), true)
		for i in 4:
			var d := Vector2.from_angle(float(i) * PI * 0.5)
			var tip := centre + d * r * 0.78
			var base := centre + d * r * 0.64
			var side := d.orthogonal() * r * 0.09
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(rim, 0.8))
		var knob := centre + value * r * 0.6
		var kr := r * (0.36 if not _dragging else 0.4)
		draw_circle(knob + Vector2(r * 0.03, r * 0.04), kr, Color(0, 0, 0, 0.35))
		draw_circle(knob, kr, MobileHudProfiles.color("button"))
		draw_arc(knob, kr, 0.0, TAU, 40, rim, maxf(2.0, kr * 0.08), true)
		draw_circle(knob, kr * 0.55, Color(rim, 0.14 if not _dragging else 0.3))

	func _draw_graffiti(centre: Vector2, r: float) -> void:
		var col := Color("ff3f8e")
		var lit := _dragging
		MobileHud.draw_neon_ring(self, centre, r, col, 4, PI * 0.25, false, true, lit)
		# Double chevrons at the four points, brightest the way it is pushed.
		for i in 4:
			var d := Vector2.from_angle(float(i) * PI * 0.5)
			var push := maxf(value.dot(d), 0.0)
			var cc := Color(col.lightened(push * 0.5), 0.55 + 0.45 * push)
			for k in 2:
				var tip := centre + d * r * (0.74 + 0.1 * float(k))
				var side := d.orthogonal() * r * 0.1
				var back := tip - d * r * 0.08
				draw_polyline(PackedVector2Array([back + side, tip, back - side]), cc, maxf(2.0, r * 0.045), true)
		var knob := centre + value * r * 0.55
		var kr := r * (0.3 if not lit else 0.34)
		var kcol := Color("33d6ff")
		for k in 3:
			draw_arc(knob, kr * (1.05 + 0.1 * float(k)), 0.0, TAU, 32, Color(kcol, 0.12 - 0.03 * float(k)), kr * 0.18, true)
		draw_circle(knob, kr, Color(0.05, 0.03, 0.09, 0.9))
		draw_arc(knob, kr, 0.0, TAU, 32, kcol, maxf(2.0, kr * 0.16), true)
		draw_circle(knob, kr * 0.35, Color(kcol, 0.6 if lit else 0.35))
