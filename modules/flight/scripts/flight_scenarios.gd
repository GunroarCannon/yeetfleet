## FlightScenarios: set-piece fights on top of the space flight scene — a duel,
## a squad skirmish, wave survival, target practice, a full team battle — or
## a custom mix built from the same dials.
##
## A scenario clears the ambient traffic, turns the spawner's auto fleet off,
## puts the player on team 1 and spawns enemy (team 2) and ally (team 1)
## groups at set distances, so ships actually fight each other rather than
## all diving at the player. It then tracks kills, waves and the clock, and
## reports a one-line status ([method status_line]) the HUDs show, plus a
## result when the objective is met or the player dies. [method stop] hands
## the scene back to free roam: teams cleared, auto fleet restored.
##
## A child of [FlightRoot]; talks to the fleet only through [AiSpawner]'s
## public spawn calls and its [signal AiSpawner.ship_destroyed].
class_name FlightScenarios
extends Node

## Emitted when a scenario starts, ends, or its status line changes.
signal changed

enum Objective { FREE, DESTROY, SURVIVE, DELIVER, GATES, SALVAGE, ESCORT, ASSAULT, DOCK }

## The objectives [ScenarioObjectives] runs, → its [enum ScenarioObjectives.Kind].
const OBJECTIVE_KINDS := {
	Objective.DELIVER: ScenarioObjectives.Kind.DELIVER,
	Objective.GATES: ScenarioObjectives.Kind.GATES,
	Objective.SALVAGE: ScenarioObjectives.Kind.SALVAGE,
	Objective.ESCORT: ScenarioObjectives.Kind.ESCORT,
	Objective.ASSAULT: ScenarioObjectives.Kind.ASSAULT,
	Objective.DOCK: ScenarioObjectives.Kind.DOCK,
}
enum State { IDLE, RUNNING, WON, LOST }

const PLAYER_TEAM := 1
## Hull range every scenario enemy is clamped into (before the toughness dial).
const ENEMY_HP_MIN := 150.0
const ENEMY_HP_MAX := 700.0
const ENEMY_TEAM := 2

## Combat archetypes offered in the pickers ([enum AiFactions.Archetype]);
## traders and scouts flee rather than fight, so they are left out.
const FIGHTER_ARCHETYPES := {
	"Pirates": AiFactions.Archetype.WOLF_PIRATE,
	"Military squad": AiFactions.Archetype.MILITARY_SQUAD,
	"Strike team": AiFactions.Archetype.STRIKE_TEAM,
	"Swarm": AiFactions.Archetype.BASIC_SWARM,
	"Police patrol": AiFactions.Archetype.POLICE_PATROL,
	"Lone wolves": AiFactions.Archetype.LONE_WOLF,
}

## The defaults every scenario starts from; a preset overrides some of them.
const DEFAULTS := {
	"name": "Custom",
	"desc": "",
	"objective": Objective.DESTROY,
	"enemies": 3,
	"allies": 0,
	"enemy_arch": "Pirates",
	"ally_arch": "Military squad",
	"waves": 1,
	"wave_growth": 1,
	"survive_time": 90.0,
	"enemy_distance": 650.0,
	"enemy_hp": 1.0,
	"enemy_damage": 1.0,
	"frozen_enemies": false,
	"player_full_heal": true,
	# The objective scenarios (see [ScenarioObjectives]).
	"points": 3,
	"gates": 8,
	"pods": 6,
	"spacing": 1600.0,
	"time_limit": 0.0,
	"route": 3500.0,
	"escort_size": 4.0,
	"escort_speed": 50.0,
	"escort_hp": 1.0,
	# Seconds between enemy waves on an escort (0 = none).
	"wave_every": 0.0,
}

const PRESETS := {
	"duel": {
		"name": "Duel", "desc": "One ace, head to head. Lock on (T) and take them down.",
		"enemies": 1, "enemy_arch": "Lone wolves", "enemy_distance": 500.0, "enemy_hp": 1.5,
	},
	"skirmish": {
		"name": "Skirmish 3 v 3", "desc": "You and two wingmen against a pirate trio.",
		"enemies": 3, "allies": 2, "enemy_arch": "Pirates",
	},
	"waves": {
		"name": "Wave survival", "desc": "Five waves, each one bigger. Clear a wave to call the next.",
		"enemies": 2, "waves": 5, "wave_growth": 1, "enemy_arch": "Swarm", "enemy_hp": 0.6,
	},
	"battle": {
		"name": "Team battle", "desc": "Two fleets collide. Your side is blue on the radar.",
		"enemies": 6, "allies": 5, "enemy_arch": "Military squad", "ally_arch": "Strike team",
		"enemy_distance": 900.0,
	},
	"survive": {
		"name": "Hold out", "desc": "Stay alive for 90 seconds against a strike team.",
		"objective": Objective.SURVIVE, "enemies": 4, "enemy_arch": "Strike team", "survive_time": 90.0,
	},
	"practice": {
		"name": "Target practice", "desc": "Five sitting ducks that never fire back. Test your guns.",
		"enemies": 5, "enemy_arch": "Swarm", "frozen_enemies": true, "enemy_distance": 400.0,
		"enemy_damage": 0.0,
	},
	"ambush": {
		"name": "Ambush", "desc": "A big pirate pack drops in close. Tough odds.",
		"enemies": 7, "enemy_arch": "Pirates", "enemy_distance": 350.0, "enemy_damage": 1.2,
	},
}
const OBJECTIVE_PRESETS := {
	"courier": {
		"name": "Courier run", "desc": "Deliver the cargo to three drop points in order — follow the blue arrow. No shooting needed.",
		"objective": Objective.DELIVER, "enemies": 0, "points": 3, "spacing": 1600.0, "time_limit": 180.0,
	},
	"race": {
		"name": "Ring race", "desc": "Thread eight rings in order before the clock runs out.",
		"objective": Objective.GATES, "enemies": 0, "gates": 8, "time_limit": 90.0,
	},
	"salvage": {
		"name": "Salvage sweep", "desc": "Six cargo pods are drifting nearby. Touch them all to collect them.",
		"objective": Objective.SALVAGE, "enemies": 0, "pods": 6, "spacing": 1100.0, "time_limit": 150.0,
	},
	"dock": {
		"name": "Dock with the carrier", "desc": "A giant friendly carrier waits ahead. Fly into its glowing bay and slow right down.",
		"objective": Objective.DOCK, "enemies": 0, "escort_size": 10.0, "route": 2500.0,
	},
	"escort": {
		"name": "Escort the hauler", "desc": "Guard a big freighter to its destination. Pirates will go for it, not you.",
		"objective": Objective.ESCORT, "enemies": 3, "enemy_arch": "Pirates", "wave_every": 22.0,
		"escort_size": 4.0, "escort_speed": 55.0, "route": 3500.0, "enemy_distance": 700.0,
	},
	"capital": {
		"name": "Escort the capital ship", "desc": "A huge capital ship crawls to the jump point under heavy attack. Keep it alive.",
		"objective": Objective.ESCORT, "enemies": 4, "enemy_arch": "Military squad", "wave_every": 26.0, "allies": 2,
		"escort_size": 9.0, "escort_speed": 32.0, "escort_hp": 2.5, "route": 4000.0, "enemy_distance": 900.0,
	},
	"assault": {
		"name": "Carrier assault", "desc": "Bring down an enemy mothership. It keeps launching fighters while it lives.",
		"objective": Objective.ASSAULT, "enemies": 2, "enemy_arch": "Pirates", "enemy_distance": 1400.0, "allies": 2,
	},
}
const PRESET_ORDER := ["duel", "skirmish", "waves", "battle", "survive", "practice", "ambush"]
## The objective scenarios, in picker order (after the fights).
const OBJECTIVE_ORDER := ["courier", "race", "salvage", "dock", "escort", "capital", "assault"]

var state: int = State.IDLE
## The running scenario's full settings ([constant DEFAULTS] + overrides).
var config: Dictionary = {}
var wave := 0
var kills := 0
var elapsed := 0.0

var _root: FlightRoot
var _spawner: AiSpawner
var _enemies: Array[AiShip] = []
var _allies: Array[AiShip] = []
var _last_status := ""
## Seconds before the next wave drops in (the pause between waves).
var _wave_delay := -1.0
## The objective scenarios' goals and markers, or null.
var _objectives: ScenarioObjectives = null
var _wave_clock := 0.0


func setup(root: FlightRoot) -> void:
	_root = root


## A preset's full settings, ready to hand to [method start] (or to edit).
static func preset(id: String) -> Dictionary:
	var c := DEFAULTS.duplicate()
	c.merge(PRESETS.get(id, OBJECTIVE_PRESETS.get(id, {})), true)
	return c


func is_running() -> bool:
	return state == State.RUNNING


## Seconds left on a running scenario's clock — an objective's time limit or
## a hold-out's countdown — or -1 when nothing is timed.
func time_left() -> float:
	if state != State.RUNNING:
		return -1.0
	if _objectives != null:
		return _objectives.time_left()
	if int(config.get("objective", Objective.DESTROY)) == Objective.SURVIVE:
		return maxf(float(config["survive_time"]) - elapsed, 0.0)
	return -1.0


## [param sec] as "1:05", for the HUD timers.
static func clock_text(sec: float) -> String:
	var s := ceili(sec)
	return "%d:%02d" % [int(s / 60.0), s % 60]


func start(settings: Dictionary) -> void:
	_spawner = _root.ensure_ai_spawner()
	if _spawner == null:
		return
	stop(false)
	config = DEFAULTS.duplicate()
	config.merge(settings, true)
	if not _spawner.ship_destroyed.is_connected(_on_ship_destroyed):
		_spawner.ship_destroyed.connect(_on_ship_destroyed)
	_spawner.auto_fleet = false
	_spawner.teardown()
	# Room for both sides, within what a phone can hold.
	AiSpawner.scenario_cap = 8 if OS.has_feature("mobile") else 24
	_root.set_player_team(PLAYER_TEAM)
	if bool(config["player_full_heal"]):
		_root.revive_player()
	wave = 0
	kills = 0
	elapsed = 0.0
	state = State.RUNNING
	var objective := int(config["objective"])
	if OBJECTIVE_KINDS.has(objective):
		_objectives = ScenarioObjectives.new()
		_objectives.name = "Objectives"
		add_child(_objectives)
		_objectives.begin(OBJECTIVE_KINDS[objective], config, _root, _spawner)
		_wave_clock = 0.0
		if int(config["enemies"]) > 0:
			_next_wave()
	else:
		_next_wave()
	# Wingmen after the enemy: under the ship cap the enemy must get its
	# slots first, or a fight could start with nobody to fight.
	_spawn_allies()
	_root.announce("%s — %s" % [config["name"], config["desc"]])
	changed.emit()


## Back to free roam. [param restore_fleet]: bring the ambient traffic back.
func stop(restore_fleet := true) -> void:
	if state == State.IDLE and config.is_empty():
		return
	state = State.IDLE
	config = {}
	if _objectives != null and is_instance_valid(_objectives):
		_objectives.clear()
	_objectives = null
	_enemies.clear()
	_allies.clear()
	_wave_delay = -1.0
	AiSpawner.scenario_cap = -1
	if _root != null:
		_root.set_player_team(0)
	if restore_fleet and _spawner != null and is_instance_valid(_spawner):
		_spawner.teardown()
		_spawner.auto_fleet = true
		_spawner.spawn_initial_fleet()
	changed.emit()


func restart() -> void:
	if config.is_empty():
		return
	start(config.duplicate())


## One line for the HUD band: objective progress, or "" in free roam.
func status_line() -> String:
	match state:
		State.IDLE:
			return ""
		State.WON:
			return "%s — VICTORY! %d kills" % [config.get("name", ""), kills]
		State.LOST:
			return "%s — SHOT DOWN. Tap to retry" % config.get("name", "")
	if _objectives != null:
		return _objectives.status()
	var foes := _alive(_enemies).size()
	var friends := _alive(_allies).size()
	var line := String(config["name"]).to_upper()
	match int(config["objective"]):
		Objective.SURVIVE:
			line += "  ·  SURVIVE %ds" % ceili(maxf(float(config["survive_time"]) - elapsed, 0.0))
		_:
			if int(config["waves"]) > 1:
				line += "  ·  WAVE %d/%d" % [wave, int(config["waves"])]
			line += "  ·  %d LEFT" % foes
	if not _allies.is_empty():
		line += "  ·  %d WINGMEN" % friends
	return line


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed += delta
	if _root._player_dead:
		_finish(false)
		return
	var foes := _alive(_enemies)
	var objective := int(config["objective"])
	if _objectives != null:
		var result := _objectives.tick(delta)
		if result != 0:
			_finish(result > 0)
			return
		# Escorts: fresh attackers every so often, dropping in near the convoy.
		var every := float(config["wave_every"])
		if every > 0.0:
			_wave_clock += delta
			if _wave_clock >= every:
				_wave_clock = 0.0
				_next_wave()
		var line0 := status_line()
		if line0 != _last_status:
			_last_status = line0
			changed.emit()
		return
	if objective == Objective.SURVIVE:
		if elapsed >= float(config["survive_time"]):
			_finish(true)
			return
		# Keep the pressure on: top the attackers back up as they fall.
		if foes.size() < int(config["enemies"]) and _wave_delay < 0.0:
			_wave_delay = 3.0
	elif foes.is_empty() and _wave_delay < 0.0:
		# Nobody has gone down yet, so this wave never arrived (the spawner was
		# full): call it again. Finishing here handed out a free win — three
		# stars and the pay — the moment a level started.
		if kills == 0 and int(config["enemies"]) > 0:
			wave = maxi(wave - 1, 0)
			_wave_delay = 1.0
			return
		if wave >= int(config["waves"]):
			_finish(true)
			return
		_wave_delay = 2.5
		_root.announce("Wave %d cleared!" % wave)
	if _wave_delay >= 0.0:
		_wave_delay -= delta
		if _wave_delay < 0.0:
			if objective == Objective.SURVIVE:
				_spawn_side(int(config["enemies"]) - foes.size(), ENEMY_TEAM, String(config["enemy_arch"]))
			else:
				_next_wave()
	var line := status_line()
	if line != _last_status:
		_last_status = line
		changed.emit()


func _next_wave() -> void:
	wave += 1
	var count := int(config["enemies"]) + (wave - 1) * int(config["wave_growth"])
	_spawn_side(count, ENEMY_TEAM, String(config["enemy_arch"]))
	if int(config["waves"]) > 1:
		_root.announce("WAVE %d — %d incoming!" % [wave, count])


func _spawn_allies() -> void:
	_spawn_side(int(config["allies"]), PLAYER_TEAM, String(config["ally_arch"]))


## Spawn [param count] ships of an archetype on a side and place them: the
## enemy ahead of the player at [code]enemy_distance[/code], wingmen off
## either wing. The spawner scatters ships around the player, so the new ones
## are picked out by diffing its roster and moved into formation.
func _spawn_side(count: int, team: int, arch_name: String) -> void:
	if count <= 0:
		return
	var before := _spawner.ships().duplicate()
	var arch := AiFactions.create(int(FIGHTER_ARCHETYPES.get(arch_name, AiFactions.Archetype.WOLF_PIRATE)))
	_spawner.spawn_group_with(arch, count, team)
	var ship_x := _root.model.global_transform
	var fwd := -ship_x.basis.z
	var right := ship_x.basis.x
	var up := ship_x.basis.y
	var i := 0
	for s: AiShip in _spawner.ships():
		if s in before:
			continue
		var pos: Vector3
		if team == ENEMY_TEAM:
			var d := float(config["enemy_distance"])
			pos = ship_x.origin + fwd * d + right * (float(i) - float(count - 1) * 0.5) * 70.0 \
				+ up * randf_range(-40.0, 40.0)
			_place(s, Transform3D(Basis.looking_at(-fwd, up), pos))
			# A random preset can be a capital hull with tens of thousands of
			# hull points; a set-piece needs fights that end, so every enemy
			# is brought into a fighter's range before the toughness dial.
			s.max_hp = clampf(s.max_hp, ENEMY_HP_MIN, ENEMY_HP_MAX) * float(config["enemy_hp"])
			s.hp = s.max_hp
			s._weapon_mult *= float(config["enemy_damage"])
			if bool(config["frozen_enemies"]):
				s._ai_paused = true
				s.systems.set_firing(false)
			_enemies.append(s)
		else:
			var side := -1.0 if i % 2 == 0 else 1.0
			pos = ship_x.origin + right * side * (50.0 + 35.0 * float(i / 2)) - fwd * (25.0 + 15.0 * float(i / 2))
			_place(s, Transform3D(Basis.looking_at(fwd, up), pos))
			_allies.append(s)
		i += 1


## Move a freshly spawned ship. Its [FlightModel] is top_level and owns the
## real transform, so the model is what has to move (the AiShip node follows
## for anything reading it before the next tick).
func _place(s: AiShip, xf: Transform3D) -> void:
	s.global_transform = xf
	if s.model != null:
		s.model.global_transform = xf
		s.model.halt()
		s.model.reset_physics_interpolation()


func _on_ship_destroyed(ship: AiShip) -> void:
	if state == State.RUNNING and ship in _enemies:
		kills += 1


func _finish(won: bool) -> void:
	state = State.WON if won else State.LOST
	_root.announce("VICTORY! %d kills in %ds" % [kills, roundi(elapsed)] if won else "Shot down — tap the band (or Retry) to go again")
	changed.emit()


static func _alive(list: Array[AiShip]) -> Array[AiShip]:
	var out: Array[AiShip] = []
	for s in list:
		if is_instance_valid(s) and s._alive:
			out.append(s)
	return out
