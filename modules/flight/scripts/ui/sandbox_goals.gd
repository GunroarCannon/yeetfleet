## SandboxGoals: what free flight is for, on screen. A small panel down the
## left of the HUD with the pilot's points and the coin they are heading for
## (a bar), three mini goals at a time each with its own progress bar (wreck
## ships, break up a raid, help a drifter, grab orbs, yeet, chain wrecks,
## survive, fly by a world), and one line on what is happening out there.
##
## A finished goal pays bonus points (they count into the wreck card's coins
## like any other) and a new one takes its place. Dying wipes the progress.
##
## [SandboxLife] owns it and feeds it through [method note]: the events the
## tutorial hears ("kill", "powerup", "launch", "swipe", "chain") plus its own
## "raid" and "rescue". Hidden while the tutorial is up.
class_name SandboxGoals
extends Control

## Goals up at once, and how long a finished one stays up before it is
## replaced (seconds, wall clock).
const SLOTS := 3
const DONE_HOLD := 2.2
## Seconds between the footer's tips when nothing is going on out there.
const TIP_EVERY := 9.0
## The words under the panel when no incident is running.
const TIPS := [
	"QUIET SKIES. A SIGNAL COMES EVERY NOW AND THEN",
	"WRECKS DROP POWER-UP ORBS. FLY INTO THEM!",
	"WRECK SHIPS FAST TO CHAIN THEM FOR MORE POINTS",
	"POINTS TURN INTO COINS WHEN YOU GO DOWN",
]
## The pool. [code]events[/code]: the note names that count. [code]mode[/code]:
## "sum" adds each event up, "max" keeps the biggest (a chain), "time" fills by
## the second alive, "visit" is reaching a world. [code]need[/code] grows by
## [code]step[/code] each time that goal is done. [code]wait[/code]: it needs an
## incident to turn up, so only one such goal is up at a time.
const POOL := {
	"wreck": {"text": "WRECK %d SHIPS", "events": ["kill"], "mode": "sum", "need": 3, "step": 2, "points": 150},
	"orbs": {"text": "GRAB %d POWER-UP ORBS", "events": ["powerup"], "mode": "sum", "need": 2, "step": 1, "points": 150},
	"yeet": {"text": "YEET %d TIMES", "events": ["launch", "swipe"], "mode": "sum", "need": 5, "step": 3, "points": 100},
	"chain": {"text": "CHAIN %d WRECKS", "events": ["chain"], "mode": "max", "need": 2, "step": 1, "points": 250},
	"survive": {"text": "SURVIVE %d SECONDS", "events": [], "mode": "time", "need": 45, "step": 30, "points": 150},
	"visit": {"text": "FLY BY %s", "events": [], "mode": "visit", "need": 1, "step": 0, "points": 200},
	"raid": {"text": "BREAK UP A PIRATE RAID", "events": ["raid"], "mode": "sum", "need": 1, "step": 0, "points": 300, "wait": true},
	"help": {"text": "HELP OR SALVAGE A DRIFTER", "events": ["rescue"], "mode": "sum", "need": 1, "step": 0, "points": 200, "wait": true},
}
## A goal's bar colour, by id.
const BAR := {
	"wreck": Color("ff3a6e"), "orbs": Color("35e0ff"), "yeet": Color("ff8a1f"), "chain": Color("ffc61a"),
	"survive": Color("b6ff3a"), "visit": Color("9d6bff"), "raid": Color("ff3a6e"), "help": Color("35e0ff"),
}

var _root: FlightRoot
var _life: SandboxLife
## Goals up: {id, have, need, points, done_at, name, start, reach, label}.
var _goals: Array[Dictionary] = []
var _done_count := {}
var _recent: Array[String] = []
var _visited: Array[String] = []
var _rng := RandomNumberGenerator.new()
## Seconds alive this life, for the points readout (the end card counts the same way).
var _alive_t := 0.0
var _was_dead := false
var _redraw := 0.0
var _tip_i := 0
var _tip_clock := 0.0


func setup(root: FlightRoot, life: SandboxLife) -> void:
	_root = root
	_life = life


func _ready() -> void:
	name = "SandboxGoals"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_tip_i = _rng.randi_range(0, TIPS.size() - 1)
	for i in SLOTS:
		_add_goal()


## The goals now up, for checks: each [code]{id, have, need, done}[/code].
func state() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Dictionary in _goals:
		out.append({"id": g["id"], "have": g["have"], "need": g["need"], "done": float(g["done_at"]) >= 0.0})
	return out


## The player did [param event] ([param amount] of it).
func note(event: String, amount := 1.0) -> void:
	for g: Dictionary in _goals:
		if float(g["done_at"]) >= 0.0:
			continue
		var def: Dictionary = POOL[g["id"]]
		if not (event in (def["events"] as Array)):
			continue
		if String(def["mode"]) == "max":
			g["have"] = maxf(float(g["have"]), amount)
		else:
			g["have"] = float(g["have"]) + amount
		if float(g["have"]) >= float(g["need"]):
			_complete(g)
	queue_redraw()


# --- Goals --------------------------------------------------------------------

func _add_goal(slot := -1) -> void:
	var id := _pick()
	if id == "":
		return
	var def: Dictionary = POOL[id]
	var g := {"id": id, "have": 0.0, "done_at": -1.0, "points": int(def["points"]),
		"need": float(def["need"]) + float(def["step"]) * float(_done_count.get(id, 0)),
		"name": "", "start": 0.0, "reach": 0.0, "label": ""}
	if id == "visit":
		_aim(g)
	g["label"] = _label(g)
	if slot >= 0 and slot < _goals.size():
		_goals[slot] = g
	else:
		_goals.append(g)


## A goal id not up now and not just done; at most one that waits on an incident.
func _pick() -> String:
	var up: Array[String] = []
	var waiting := false
	for g: Dictionary in _goals:
		up.append(String(g["id"]))
		if bool(POOL[g["id"]].get("wait", false)):
			waiting = true
	var ok: Array[String] = []
	for id: String in POOL:
		if id in up or id in _recent:
			continue
		if waiting and bool(POOL[id].get("wait", false)):
			continue
		if id == "visit" and _world().is_empty():
			continue
		ok.append(id)
	if ok.is_empty():
		for id: String in POOL:
			if not (id in up) and not (waiting and bool(POOL[id].get("wait", false))):
				ok.append(id)
	return ok[_rng.randi_range(0, ok.size() - 1)] if not ok.is_empty() else ""


func _label(g: Dictionary) -> String:
	var text := String(POOL[g["id"]]["text"])
	if String(g["id"]) == "visit":
		return text % String(g["name"]).to_upper()
	if text.contains("%d"):
		return text % int(g["need"])
	return text


## Point a "fly by" goal at a world the ship is not already at, one it has
## not just visited if there is a choice.
func _aim(g: Dictionary) -> void:
	var spots := _world()
	if spots.is_empty():
		return
	var fresh: Array[Dictionary] = []
	for e: Dictionary in spots:
		if not (String(e["name"]) in _visited):
			fresh.append(e)
	var from := fresh if not fresh.is_empty() else spots
	var e: Dictionary = from[_rng.randi_range(0, from.size() - 1)]
	var model := _root.active_model()
	g["name"] = String(e["name"])
	g["reach"] = float(e["radius"]) * 1.6 + 220.0
	g["start"] = model.global_position.distance_to(e["position"]) if model != null else 1000.0


## The named worlds and structures that count, far enough off to be a trip.
func _world() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var model := _root.active_model()
	if model == null:
		return out
	for e: Dictionary in _root.landmarks():
		var nm := String(e.get("name", ""))
		var r := float(e.get("radius", 0.0))
		if nm == "" or r < 150.0:
			continue
		if model.global_position.distance_to(e["position"]) > r * 1.6 + 220.0 + 600.0:
			out.append({"name": nm, "position": e["position"], "radius": r, "ref": e})
	return out


## The live position of a "fly by" goal's world (a structure moves).
func _where(g: Dictionary) -> Variant:
	for e: Dictionary in _root.landmarks():
		if String(e.get("name", "")) == String(g["name"]):
			return e["position"]
	return null


func _complete(g: Dictionary) -> void:
	g["done_at"] = Time.get_ticks_msec() / 1000.0
	var id := String(g["id"])
	_done_count[id] = int(_done_count.get(id, 0)) + 1
	_recent.append(id)
	while _recent.size() > 2:
		_recent.pop_front()
	if id == "visit" and not (String(g["name"]) in _visited):
		_visited.append(String(g["name"]))
		while _visited.size() > 3:
			_visited.pop_front()
	_root.score += int(g["points"])
	var model := _root.active_model()
	if model != null:
		_root.hit_word("GOAL! +%d" % int(g["points"]), model.global_position, Color("b6ff3a"), 1.3)
	GameAudio.ui(&"coin", 0.0)


# --- Tick ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(_root):
		return
	var teaching := _root.tutorial != null and is_instance_valid(_root.tutorial)
	visible = not teaching
	if _root.is_player_dead():
		_was_dead = true
		return
	if _was_dead:
		_was_dead = false
		_reset()
	if get_tree().paused:
		return
	_alive_t += delta
	if teaching:
		return
	_tip_clock += delta
	if _tip_clock >= TIP_EVERY:
		_tip_clock = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
	var now := Time.get_ticks_msec() / 1000.0
	var model := _root.active_model()
	for i in _goals.size():
		var g := _goals[i]
		if float(g["done_at"]) >= 0.0:
			if now - float(g["done_at"]) >= DONE_HOLD:
				_add_goal(i)
			continue
		match String(POOL[g["id"]]["mode"]):
			"time":
				g["have"] = float(g["have"]) + delta
				if float(g["have"]) >= float(g["need"]):
					_complete(g)
			"visit":
				var at: Variant = _where(g)
				if at != null and model != null and model.global_position.distance_to(at) <= float(g["reach"]):
					g["have"] = 1.0
					_complete(g)
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = 0.1
		queue_redraw()


## The ship went down: the goals start over (the points are the card's).
func _reset() -> void:
	_alive_t = 0.0
	for i in _goals.size():
		var g := _goals[i]
		if float(g["done_at"]) >= 0.0:
			_add_goal(i)
		elif String(g["id"]) == "visit":
			g["have"] = 0.0
			_aim(g)
			g["label"] = _label(g)
		else:
			g["have"] = 0.0


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	if _root == null or _goals.is_empty():
		return
	var vp := size
	var u := clampf(minf(vp.x, vp.y) / 720.0, 0.62, 1.25)
	if vp.x < vp.y:
		u = clampf(vp.x / 620.0, 0.6, 1.0)
	var w := 300.0 * u
	if vp.x < vp.y:
		w = minf(w, vp.x * 0.56)
	var x := 12.0 * u
	# Under the health plate, above the radar.
	var y := vp.y * (0.235 if vp.x < vp.y else 0.315)
	var font := GraffitiStyle.tip_font()
	var nums := GraffitiStyle.number_font()
	var inner := w - 28.0 * u

	# The points and the coin they are heading for.
	var points := _root.score + int(_alive_t * CampaignLevelOverlay.POINTS_PER_SEC)
	var per := CampaignLevelOverlay.POINTS_PER_COIN
	var head := Rect2(x, y, w, 38.0 * u)
	GraffitiStyle.draw_slab(self, head, GraffitiStyle.INK, 10.0, 3.0, Vector2(4, 5))
	_left("%d PTS" % points, Vector2(x + 14.0 * u, y + 13.0 * u), int(17.0 * u), GraffitiStyle.SUN, font, inner * 0.55)
	_right("%d COINS" % (points / per), Vector2(x + w - 14.0 * u, y + 13.0 * u), int(14.0 * u), GraffitiStyle.CYAN, font)
	_bar(Rect2(x + 14.0 * u, y + 26.0 * u, inner, 7.0 * u), float(points % per) / float(per), GraffitiStyle.SUN)
	y += head.size.y + 5.0 * u

	# The goals.
	var now := Time.get_ticks_msec() / 1000.0
	for g: Dictionary in _goals:
		var done := float(g["done_at"]) >= 0.0
		var row := Rect2(x, y, w, 42.0 * u)
		var fill := GraffitiStyle.LIME if done else GraffitiStyle.INK
		GraffitiStyle.draw_slab(self, row, fill, 10.0, 3.0, Vector2(4, 5))
		if done:
			var pulse := 0.5 + 0.5 * sin((now - float(g["done_at"])) * 10.0)
			draw_rect(Rect2(row.position, row.size), Color(1, 1, 1, 0.18 * pulse))
			_left("DONE!", Vector2(x + 14.0 * u, y + 21.0 * u), int(20.0 * u), GraffitiStyle.INK, font, inner * 0.6)
			_right("+%d" % int(g["points"]), Vector2(x + w - 14.0 * u, y + 21.0 * u), int(20.0 * u), GraffitiStyle.INK, nums)
		else:
			_left(String(g["label"]), Vector2(x + 14.0 * u, y + 13.0 * u), int(14.0 * u), GraffitiStyle.PAPER, font, inner - 48.0 * u)
			_right("+%d" % int(g["points"]), Vector2(x + w - 14.0 * u, y + 13.0 * u), int(15.0 * u), GraffitiStyle.SUN, nums)
			var frac := 0.0
			var count := ""
			var mode := String(POOL[g["id"]]["mode"])
			if mode == "visit":
				var at: Variant = _where(g)
				var model := _root.active_model()
				if at != null and model != null:
					var d := model.global_position.distance_to(at)
					var span := maxf(float(g["start"]) - float(g["reach"]), 1.0)
					frac = clampf(1.0 - (d - float(g["reach"])) / span, 0.0, 1.0)
					count = _dist(d)
			elif mode == "time":
				frac = float(g["have"]) / float(g["need"])
				count = "%ds" % int(maxf(float(g["need"]) - float(g["have"]), 0.0))
			else:
				frac = float(g["have"]) / float(g["need"])
				count = "%d OF %d" % [int(g["have"]), int(g["need"])]
			var bar_w := inner - 74.0 * u
			_bar(Rect2(x + 14.0 * u, y + 28.0 * u, bar_w, 8.0 * u), frac, BAR[g["id"]])
			_right(count, Vector2(x + w - 14.0 * u, y + 32.0 * u), int(12.0 * u), GraffitiStyle.PAPER, font)
		y += row.size.y + 5.0 * u

	# What is going on out there.
	var line := _life.situation() if _life != null else ""
	if line == "":
		line = TIPS[_tip_i]
	var foot := Rect2(x, y, w, 38.0 * u)
	GraffitiStyle.draw_slab(self, foot, GraffitiStyle.VIOLET, 10.0, 3.0, Vector2(4, 5))
	draw_multiline_string(font, Vector2(x + 14.0 * u, y + 16.0 * u), line, HORIZONTAL_ALIGNMENT_LEFT,
		inner, int(12.0 * u), 2, GraffitiStyle.PAPER)


## Text with its left edge on [param at] (its middle line), shrunk to fit [param max_w].
func _left(text: String, at: Vector2, size_px: int, col: Color, font: Font, max_w := 0.0) -> void:
	var s := size_px
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	while max_w > 0.0 and tw > max_w and s > 9:
		s -= 1
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	GraffitiStyle.draw_text(self, text, at + Vector2(tw * 0.5, 0.0), s, col, 4, font)


## Text with its right edge on [param at].
func _right(text: String, at: Vector2, size_px: int, col: Color, font: Font) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	GraffitiStyle.draw_text(self, text, at - Vector2(tw * 0.5, 0.0), size_px, col, 4, font)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(1, 1, 1, 0.16))
	if frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, GraffitiStyle.PAPER, false, 1.5)


static func _dist(m: float) -> String:
	return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)
