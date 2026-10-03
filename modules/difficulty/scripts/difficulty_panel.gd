## DifficultyPanel: the editor for [Difficulty] — every dial of the shipped
## table, the Easy / Normal / Hard presets, the per-level curves and the ship
## recommendation wording.
##
## One control, built from [constant Difficulty.SCHEMA] so a new dial shows up
## here by being added there. It is hosted by the workbench's Difficulty Lab and
## by the flight scene's 🎚 Difficulty debug chip. Edits apply at once (the game
## reads [method Difficulty.v] live); Save writes the JSON every build ships.
class_name DifficultyPanel
extends PanelContainer

signal closed

const EDIT_BASE := 0
const READOUT_KINDS: Array[String] = ["skirmish", "ambush", "battle", "waves", "duel", "boss", "assault", "escort", "survive"]

var _edit := EDIT_BASE
var _tabs: TabContainer
var _body: VBoxContainer
var _growth_box: VBoxContainer
var _ships_box: VBoxContainer
var _status: Label
var _folded: Dictionary = {}
# Growth tab state.
var _g_stat := "hp"
var _g_level := 20
var _g_kind := "skirmish"
var _g_graph: GrowthGraph
var _g_readout: GridContainer
# Ships tab state.
var _s_ship := "kestrel"
var _s_pips := 5
var _s_graph: GrowthGraph
var _s_table: GridContainer
var _s_summary: Label


func _ready() -> void:
	custom_minimum_size = Vector2(560.0, 520.0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "🎚 Difficulty"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	header.add_child(close_btn)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	root.add_child(modes)
	modes.add_child(_small("Edit"))
	var edit_pick := OptionButton.new()
	edit_pick.add_item("Base numbers", EDIT_BASE)
	for i in Difficulty.PRESET_NAMES.size():
		edit_pick.add_item("%s tweaks" % Difficulty.PRESET_NAMES[i].capitalize(), i + 1)
	edit_pick.item_selected.connect(func(idx: int) -> void:
		_edit = edit_pick.get_item_id(idx)
		_rebuild())
	modes.add_child(edit_pick)
	modes.add_child(_small("Play as"))
	var play_pick := OptionButton.new()
	for n in Difficulty.PRESET_NAMES:
		play_pick.add_item(n.capitalize())
	play_pick.select(Difficulty.preset)
	play_pick.item_selected.connect(func(idx: int) -> void:
		Difficulty.set_preset(idx)
		_rebuild())
	modes.add_child(play_pick)

	edit_pick.tooltip_text = "Which table you are changing: the base numbers every player gets, or the multipliers one preset puts on top of them."
	play_pick.tooltip_text = "Which preset the game uses right now (the same choice as Settings > Difficulty). Try each one while testing."
	var note := _small("EDIT = which table the sliders change: the base numbers, or one preset's multipliers on top of "
		+ "them (Normal stays x1). PLAY AS = which preset the game runs while you test.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 520.0
	root.add_child(note)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_body = _tab_box("Dials")
	_growth_box = _tab_box("Level growth")
	_ships_box = _tab_box("Your ships")

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	root.add_child(foot)
	var save := Button.new()
	save.text = "💾 Save to game"
	save.focus_mode = Control.FOCUS_NONE
	save.disabled = not Difficulty.can_save()
	save.tooltip_text = "Writes %s — what every build plays. Desktop runs only." % Difficulty.DATA_PATH
	save.pressed.connect(func() -> void:
		_say("Saved to the game file." if Difficulty.save() else "Could not save here."))
	foot.add_child(save)
	var reload := Button.new()
	reload.text = "↺ Reload file"
	reload.focus_mode = Control.FOCUS_NONE
	reload.pressed.connect(func() -> void:
		Difficulty.reload()
		_rebuild()
		_say("Reloaded."))
	foot.add_child(reload)
	var reset := Button.new()
	reset.text = "Defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		Difficulty.reset()
		_rebuild()
		_say("Defaults (not saved yet)."))
	foot.add_child(reset)
	_status = _small("" if Difficulty.can_save() else "Read-only here: edits last this session.")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(_status)
	_rebuild()


func _say(text: String) -> void:
	_status.text = text


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	return l


func _tab_box(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _rebuild() -> void:
	for box in [_body, _growth_box, _ships_box]:
		for c in (box as Node).get_children():
			c.queue_free()
	var groups: Array[String] = []
	for k: String in Difficulty.SCHEMA:
		var g := String((Difficulty.SCHEMA[k] as Array)[3])
		if g not in groups and not g.begins_with("Growth"):
			groups.append(g)
	for g in groups:
		var box := _section(g, _body)
		for k: String in Difficulty.SCHEMA:
			if String((Difficulty.SCHEMA[k] as Array)[3]) == g:
				_dial_row(box, k)
	if _edit == EDIT_BASE:
		_curves_section()
		_text_section()
	_build_growth()
	_build_ships()


## A collapsible section; remembers whether it was folded across rebuilds.
func _section(title: String, parent: VBoxContainer) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = bool(_folded.get(title, title != "Player"))
	fold.folding_changed.connect(func(is_folded: bool) -> void: _folded[title] = is_folded)
	parent.add_child(fold)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	fold.add_child(box)
	return box


func _dial_row(box: VBoxContainer, dial: String) -> void:
	var s: Array = Difficulty.SCHEMA[dial]
	var lo := float(s[1])
	var hi := float(s[2])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = String(s[4])
	box.add_child(row)
	var name_l := Label.new()
	name_l.text = dial.replace("_", " ")
	name_l.custom_minimum_size.x = 170.0
	name_l.add_theme_font_size_override("font_size", 13)
	row.add_child(name_l)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 120.0
	var spin := SpinBox.new()
	spin.custom_minimum_size.x = 96.0
	if _edit == EDIT_BASE:
		var step := 1.0 if hi - lo >= 20.0 else 0.005
		slider.min_value = lo
		slider.max_value = hi
		slider.step = step
		slider.value = Difficulty.base(dial)
		spin.min_value = lo
		spin.max_value = hi
		spin.step = step
		spin.value = Difficulty.base(dial)
		slider.value_changed.connect(func(x: float) -> void:
			Difficulty.set_dial(dial, x)
			spin.set_value_no_signal(x))
		spin.value_changed.connect(func(x: float) -> void:
			Difficulty.set_dial(dial, x)
			slider.set_value_no_signal(x))
	else:
		var pname: String = Difficulty.PRESET_NAMES[_edit - 1]
		slider.min_value = 0.05
		slider.max_value = 3.0
		slider.step = 0.01
		slider.value = Difficulty.preset_mult(pname, dial)
		spin.min_value = 0.05
		spin.max_value = 20.0
		spin.step = 0.01
		spin.prefix = "×"
		spin.value = Difficulty.preset_mult(pname, dial)
		var result := _small("")
		result.custom_minimum_size.x = 70.0
		result.text = "= %s" % _fmt(Difficulty.base(dial) * Difficulty.preset_mult(pname, dial))
		slider.value_changed.connect(func(x: float) -> void:
			Difficulty.set_preset_mult(pname, dial, x)
			spin.set_value_no_signal(x)
			result.text = "= %s" % _fmt(Difficulty.base(dial) * x))
		spin.value_changed.connect(func(x: float) -> void:
			Difficulty.set_preset_mult(pname, dial, x)
			slider.set_value_no_signal(minf(x, 3.0))
			result.text = "= %s" % _fmt(Difficulty.base(dial) * x))
		row.add_child(slider)
		row.add_child(spin)
		row.add_child(result)
		return
	row.add_child(slider)
	row.add_child(spin)


func _fmt(x: float) -> String:
	return str(snappedf(x, 0.01 if absf(x) < 100.0 else 1.0))


# --- Curves ---------------------------------------------------------------------

func _curves_section() -> void:
	var box := _section("Level curves", _body)
	var note := _small("A ×multiplier by level number, on top of the growth formula (Level growth tab). Points are joined by "
		+ "straight lines and flat past the ends — e.g. a plateau at 30, or a spike at boss levels.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 500.0
	box.add_child(note)
	for id: String in Difficulty.CURVES:
		var title := Label.new()
		title.text = String((Difficulty.CURVES[id] as Array)[0])
		title.add_theme_font_size_override("font_size", 13)
		box.add_child(title)
		var pts := Difficulty.curve_points(id)
		for i in pts.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			box.add_child(row)
			row.add_child(_small("level"))
			var lv := SpinBox.new()
			lv.min_value = 1
			lv.max_value = 200
			lv.step = 1
			lv.value = int(pts[i][0])
			row.add_child(lv)
			row.add_child(_small("×"))
			var mult := SpinBox.new()
			mult.min_value = 0.05
			mult.max_value = 20.0
			mult.step = 0.05
			mult.value = float(pts[i][1])
			row.add_child(mult)
			var apply := func(_x: float) -> void:
				var cur := Difficulty.curve_points(id)
				cur[i] = [int(lv.value), mult.value]
				Difficulty.set_curve_points(id, cur)
			lv.value_changed.connect(apply)
			mult.value_changed.connect(apply)
			var del := Button.new()
			del.text = "✕"
			del.focus_mode = Control.FOCUS_NONE
			del.disabled = pts.size() <= 1
			del.pressed.connect(func() -> void:
				var cur := Difficulty.curve_points(id)
				cur.remove_at(i)
				Difficulty.set_curve_points(id, cur)
				_rebuild())
			row.add_child(del)
		var add := Button.new()
		add.text = "+ point"
		add.focus_mode = Control.FOCUS_NONE
		add.pressed.connect(func() -> void:
			var cur := Difficulty.curve_points(id)
			var last: Array = cur[cur.size() - 1]
			cur.append([int(last[0]) + 10, float(last[1])])
			Difficulty.set_curve_points(id, cur)
			_rebuild())
		box.add_child(add)


# --- Words ----------------------------------------------------------------------

func _text_section() -> void:
	var box := _section("Ship recommendation words", _body)
	var note := _small("Shown on a level when it only recommends a ship (Ship choice > force ship = 0). "
		+ "Reads as: <lead-in> <words for the ship type>.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 500.0
	box.add_child(note)
	_text_row(box, "lead-in", "")
	for t in Difficulty.HINT_TYPES:
		_text_row(box, t.to_lower(), t)
	var preview := _small("")
	box.add_child(preview)
	preview.text = "e.g.  " + Difficulty.ship_hint("SCOUT")


func _text_row(box: VBoxContainer, label: String, type_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170.0
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = Difficulty.hint_text(type_name)
	edit.text_changed.connect(func(t: String) -> void: Difficulty.set_hint_text(type_name, t))
	row.add_child(edit)


# --- Level growth ---------------------------------------------------------------

func _build_growth() -> void:
	var box := _growth_box
	var note := _small("Every stat that climbs follows one formula:  (start + (end - start) x t^shape) x era^eras x curve,  "
		+ "with t = (level-1) / (span-1). START is level 1, END is the value at the span level, SHAPE bends the line "
		+ "(1 straight, above 1 slow then steep), ERA multiplies the stat again for every era (dashed lines). "
		+ "Click the graph to pick a level.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 500.0
	box.add_child(note)

	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 8)
	box.add_child(pick)
	pick.add_child(_small("Stat"))
	var stat_pick := OptionButton.new()
	var ids := Difficulty.GROWTH.keys()
	for i in ids.size():
		stat_pick.add_item(String(Difficulty.GROWTH[ids[i]]), i)
	stat_pick.select(maxi(ids.find(_g_stat), 0))
	stat_pick.item_selected.connect(func(idx: int) -> void:
		_g_stat = String(ids[idx])
		_rebuild())
	pick.add_child(stat_pick)

	var formula := _small(Difficulty.formula_text(_g_stat))
	formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	formula.custom_minimum_size.x = 500.0
	box.add_child(formula)

	_g_graph = GrowthGraph.new()
	_g_graph.max_level = 80
	_g_graph.marker_level = _g_level
	_g_graph.level_picked.connect(func(lv: int) -> void:
		_g_level = lv
		_refresh_growth())
	box.add_child(_g_graph)

	for suffix in ["_start", "_end", "_shape", "_era"]:
		_dial_row(box, _g_stat + suffix)
	for d in ["growth_span", "era_start", "era_levels"]:
		_dial_row(box, d)

	var look := HBoxContainer.new()
	look.add_theme_constant_override("separation", 8)
	box.add_child(look)
	look.add_child(_small("Look at level"))
	var lv_spin := SpinBox.new()
	lv_spin.min_value = 1
	lv_spin.max_value = 200
	lv_spin.value = _g_level
	lv_spin.value_changed.connect(func(x: float) -> void:
		_g_level = int(x)
		_refresh_growth())
	look.add_child(lv_spin)
	look.add_child(_small("kind"))
	var kind_pick := OptionButton.new()
	for k in READOUT_KINDS:
		kind_pick.add_item(k)
	kind_pick.select(maxi(READOUT_KINDS.find(_g_kind), 0))
	kind_pick.item_selected.connect(func(idx: int) -> void:
		_g_kind = READOUT_KINDS[idx]
		_refresh_growth())
	look.add_child(kind_pick)
	_g_readout = GridContainer.new()
	_g_readout.columns = 2
	_g_readout.add_theme_constant_override("h_separation", 16)
	box.add_child(_g_readout)
	_refresh_growth()


func _refresh_growth() -> void:
	if _g_graph == null or not is_instance_valid(_g_graph):
		return
	var id := _g_stat
	_g_graph.series = [{"label": String(Difficulty.GROWTH[id]), "color": Color("ffb347"), "fn": func(n: int) -> float: return Difficulty.stat(id, n)}]
	_g_graph.marker_level = _g_level
	_g_graph.era_marks = _era_marks()
	_g_graph.log_scale = Difficulty.stat(id, 80) > Difficulty.stat(id, 1) * 6.0 and Difficulty.stat(id, 1) > 0.0
	_g_graph.refresh()
	for c in _g_readout.get_children():
		c.queue_free()
	for row: Array in Difficulty.level_stats(_g_level, _g_kind):
		_g_readout.add_child(_small(String(row[0])))
		_g_readout.add_child(_lbl(String(row[1])))


func _era_marks() -> Array[int]:
	var out: Array[int] = []
	var n := int(Difficulty.v("era_start"))
	while n <= 80:
		out.append(n)
		n += maxi(int(Difficulty.v("era_levels")), 1)
	return out


# --- Your ships -----------------------------------------------------------------

func _build_ships() -> void:
	var box := _ships_box
	var note := _small("How a ship's upgrades stack up against the level climb. RATING is the garage bar (cells), "
		+ "x is what the upgrades multiply it by in flight, and EDGE compares hull and guns to what the level "
		+ "brings (1.0 = a stock Kestrel on level 1). Under 1 the ship is outclassed there.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 500.0
	box.add_child(note)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 8)
	box.add_child(pick)
	pick.add_child(_small("Ship"))
	var ship_pick := OptionButton.new()
	var ids := ShipCatalog.ids()
	for i in ids.size():
		ship_pick.add_item(String(ShipCatalog.get_ship(ids[i])["name"]), i)
	ship_pick.select(maxi(ids.find(_s_ship), 0))
	ship_pick.item_selected.connect(func(idx: int) -> void:
		_s_ship = ids[idx]
		_refresh_ships())
	pick.add_child(ship_pick)
	pick.add_child(_small("upgrades on each track"))
	var pips := SpinBox.new()
	pips.min_value = 0
	pips.max_value = ShipCatalog.MAX_PIPS
	pips.value = _s_pips
	pips.value_changed.connect(func(x: float) -> void:
		_s_pips = int(x)
		_refresh_ships())
	pick.add_child(pips)
	_s_table = GridContainer.new()
	_s_table.columns = 5
	_s_table.add_theme_constant_override("h_separation", 18)
	box.add_child(_s_table)
	_s_graph = GrowthGraph.new()
	_s_graph.max_level = 80
	_s_graph.level_picked.connect(func(lv: int) -> void:
		_g_level = lv
		_refresh_ships())
	box.add_child(_s_graph)
	_s_summary = _small("")
	box.add_child(_s_summary)
	_refresh_ships()


## Hull and guns against what level [param n] brings, relative to a stock
## Kestrel on level 1.
func _edge(ship: String, pips: int, n: int) -> float:
	var tough := float(ShipCatalog.rating(ship, "hull")) * ShipCatalog.stat_mult(ship, "hull", pips) \
		/ (Difficulty.stat("damage", n) * Difficulty.v("enemy_bite"))
	var power := float(ShipCatalog.rating(ship, "guns")) * ShipCatalog.stat_mult(ship, "guns", pips) \
		/ (Difficulty.stat("hp", n) * Difficulty.v("enemy_hp"))
	var ref_t := 1.0 / (Difficulty.stat("damage", 1) * Difficulty.v("enemy_bite"))
	var ref_p := 2.0 / (Difficulty.stat("hp", 1) * Difficulty.v("enemy_hp"))
	return sqrt(tough * power) / sqrt(ref_t * ref_p)


func _refresh_ships() -> void:
	if _s_table == null or not is_instance_valid(_s_table):
		return
	for c in _s_table.get_children():
		c.queue_free()
	for h in ["track", "rating", "upgrades x", "in flight", "per upgrade"]:
		_s_table.add_child(_small(h))
	for i in ShipCatalog.STATS.size():
		var st: String = ShipCatalog.STATS[i]
		var rating := ShipCatalog.rating(_s_ship, st)
		var m := ShipCatalog.stat_mult(_s_ship, st, _s_pips)
		_s_table.add_child(_small(ShipCatalog.STAT_NAMES[i]))
		_s_table.add_child(_lbl("%d / %d" % [rating, rating + ShipCatalog.MAX_PIPS]))
		_s_table.add_child(_lbl("x %.2f" % m))
		_s_table.add_child(_lbl("%.2f" % (float(rating) * m)))
		_s_table.add_child(_lbl("+%d%%" % roundi((ShipCatalog.stat_mult(_s_ship, st, 1) - 1.0) * 100.0)))
	var ship := _s_ship
	var pips := _s_pips
	_s_graph.series = [
		{"label": "stock", "color": Color("8f86a8"), "fn": func(n: int) -> float: return _edge(ship, 0, n)},
		{"label": "%d upgrades" % pips, "color": Color("7dff3a"), "fn": func(n: int) -> float: return _edge(ship, pips, n)},
		{"label": "break-even", "color": Color(1, 1, 1, 0.35), "fn": func(_n: int) -> float: return 1.0},
	]
	_s_graph.marker_level = _g_level
	_s_graph.era_marks = _era_marks()
	_s_graph.log_scale = true
	_s_graph.refresh()
	_s_summary.text = "At level %d the edge is %.2f stock, %.2f with %d upgrades." % [
		_g_level, _edge(ship, 0, _g_level), _edge(ship, pips, _g_level), pips]


func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l
