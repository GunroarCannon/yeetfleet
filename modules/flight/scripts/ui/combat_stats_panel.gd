## CombatStatsPanel: the flight-test debugger's health & stats bench, opened
## from the 🧪 Stats chip on the top bar or the D debug strip.
##
## Player hull/shield size, god mode, damage in and out, regeneration, and the
## enemy side's hull, damage, fire rate, accuracy and speed — plus one-tap
## actions (heal, set hull, kill, spawn). Dials write through to
## [JuiceSettings] like the 🎬 Juice panel it borrows its rows from; actions
## call into [FlightRoot]. A live readout at the top shows what they did.
class_name CombatStatsPanel
extends JuiceSettingsPanel

var _root: FlightRoot = null
var _player_readout: Label = null
var _enemy_readout: Label = null


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	panel_title = "🧪 STATS DEBUGGER"
	accent = Color("ffd23f")
	super._ready()


func _build_rows(vbox: VBoxContainer) -> void:
	_section(vbox, "Player", Color("6ec6ff"))
	_player_readout = _readout(vbox)
	_check(vbox, "Invulnerable (god mode)", "player_invulnerable", JuiceSettings.player_invulnerable)
	_slider_row(
		vbox, "Player hull size", 0.2, 20.0, 0.1, JuiceSettings.player_durability_mult,
		func(v: float) -> void:
			JuiceSettings.set_player_durability_mult(v)
			_refresh_player()
	)
	_slider_row(
		vbox, "Hull HP scale (every ship)", 0.1, 5.0, 0.05, JuiceSettings.hull_hp_mult,
		func(v: float) -> void:
			JuiceSettings.set_hull_hp_mult(v)
			_refresh_player()
	)
	_float_after(vbox, "Shield size", "player_shield_mult", 0.05, "×%.2f", _refresh_player)
	_float_row(vbox, "Damage you take", "player_damage_taken_mult", 0.05, "×%.2f")
	_float_row(vbox, "Damage you deal", "player_damage_dealt_mult", 0.1, "×%.1f")
	_float_row(vbox, "Your toughness (hits ÷)", "player_toughness", 0.05, "÷%.2f")
	_float_row(vbox, "Your firepower (guns & rams)", "player_power", 0.05, "×%.2f")
	_float_row(vbox, "Your gun damage (guns only)", "player_gun_damage", 0.05, "×%.2f")
	_float_row(vbox, "Your ram reach (hits without touching)", "player_ram_reach", 0.1, "×%.1f hull")
	_float_row(vbox, "Your shots hit within", "player_shot_hit_scale", 0.1, "×%.1f ship size")
	_check(vbox, "A lost wing spins you out (like the AI)", "player_wing_spiral", JuiceSettings.player_wing_spiral)
	_slider_row(vbox, "Ram damage", 0.5, 2.0, 0.05, JuiceSettings.ram_damage_mult, JuiceSettings.set_ram_damage_mult)
	_float_row(vbox, "Hull regen", "player_hp_regen", 0.5, "%.1f%%/s")
	_float_row(vbox, "Shield regen", "player_shield_regen", 0.5, "%.1f%%/s")
	_float_row(vbox, "Shield regen delay", "player_shield_regen_delay", 0.1, "%.1f s")
	_buttons(vbox, [
		["❤ Full heal", func() -> void: _act_player(1.0)],
		["🛡 Refill shield", func() -> void: _call_root("refill_player_shield")],
		["Hull 50%", func() -> void: _act_player(0.5)],
		["Hull 10%", func() -> void: _act_player(0.1)],
		["💀 Die", func() -> void: _act_player(0.0)],
		["↺ Respawn", func() -> void: _call_root("respawn_player_ship")],
	])

	_section(vbox, "Enemies", Color("ff6f60"))
	_enemy_readout = _readout(vbox)
	_check(vbox, "Passive (never shoot you)", "enemies_passive", JuiceSettings.enemies_passive)
	_check(vbox, "One-hit kills (your hits)", "one_hit_kills", JuiceSettings.one_hit_kills)
	var r: Vector2 = JuiceSettings.FLOAT_RANGES["enemy_hp_mult"]
	_slider_row(
		vbox, "Enemy hull", r.x, r.y, 0.05, JuiceSettings.enemy_hp_mult,
		func(v: float) -> void:
			var old := JuiceSettings.enemy_hp_mult
			JuiceSettings.set_float("enemy_hp_mult", v)
			if _root != null:
				_root.rescale_enemy_hp(old)
	)
	_float_row(vbox, "Enemy damage", "enemy_damage_mult", 0.05, "×%.2f")
	_float_row(vbox, "Enemy fire rate", "enemy_fire_rate_mult", 0.05, "×%.2f")
	_float_row(vbox, "Enemy accuracy", "enemy_accuracy", 0.05, "%.0f%%", 100.0)
	_float_row(vbox, "Enemy shots hit you within", "enemy_shot_hit_scale", 0.05, "×%.2f your size")
	_float_row(vbox, "Warning before they fire", "enemy_telegraph", 0.05, "%.2f s")
	_float_row(vbox, "Max ships shooting you at once", "ai_max_attackers", 1.0, "%.0f")
	_slider_row(
		vbox, "Enemy speed", 0.25, 3.0, 0.05, Session.npc_speed_scale,
		func(v: float) -> void:
			if _root != null:
				_root.set_npc_speed_scale(v)
	)
	_buttons(vbox, [
		["+1 ship", func() -> void: _spawn(1)],
		["+5 ships", func() -> void: _spawn(5)],
		["Damage all 50%", func() -> void: _call_root("damage_all_enemies", [0.5])],
		["Heal all", func() -> void: _call_root("heal_all_enemies")],
		["Kill all", _kill_all],
	])


func _process(_delta: float) -> void:
	if not visible or _root == null or _player_readout == null:
		return
	_player_readout.text = "Hull %d / %d   ·   Shield %d / %d%s" % [
		roundi(_root.player_hp), roundi(_root.player_max_hp),
		roundi(_root.player_shield), roundi(_root.player_max_shield),
		"   ·   DEAD" if _root._player_dead else "",
	]
	var enemies := _root.live_enemies()
	var avg := ""
	if not enemies.is_empty():
		var frac := 0.0
		for ship in enemies:
			frac += ship.hp / maxf(ship.max_hp, 1.0)
		avg = "   ·   avg hull %d%%" % roundi(frac / enemies.size() * 100.0)
	_enemy_readout.text = "%d live ship(s)%s" % [enemies.size(), avg]


func _readout(vbox: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	vbox.add_child(label)
	return label


## A [method _float_row] that also runs [param after] on every change.
func _float_after(
	vbox: VBoxContainer, text: String, field: String, step: float, fmt: String, after: Callable
) -> void:
	var r: Vector2 = JuiceSettings.FLOAT_RANGES[field]
	_slider_row(
		vbox, text, r.x, r.y, step, JuiceSettings.get_float(field),
		func(v: float) -> void:
			JuiceSettings.set_float(field, v)
			after.call(),
		fmt
	)


## A wrapping row of action buttons: each entry is [label, Callable].
func _buttons(vbox: VBoxContainer, entries: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	vbox.add_child(flow)
	for entry: Array in entries:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(entry[1])
		flow.add_child(b)


func _refresh_player() -> void:
	_call_root("refresh_player_max_stats")


func _act_player(fraction: float) -> void:
	if _root == null:
		return
	if fraction >= 1.0 and _root._player_dead:
		_root.respawn()
		return
	_root.set_player_hp_fraction(fraction)


func _kill_all() -> void:
	if _root != null and _root._ai_spawner != null:
		_root._ai_spawner.kill_all()


func _spawn(count: int) -> void:
	if _root != null and _root._ai_spawner != null:
		_root._ai_spawner.spawn_near_player(count)


func _call_root(method: String, args: Array = []) -> void:
	if _root != null:
		_root.callv(method, args)
