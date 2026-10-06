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

enum Objective { FREE, DESTROY, SURVIVE, DELIVER, GATES, SALVAGE, ESCORT, ASSAULT, DOCK, VOYAGE }

## The objectives [ScenarioObjectives] runs, → its [enum ScenarioObjectives.Kind].
const OBJECTIVE_KINDS := {
	Objective.DELIVER: ScenarioObjectives.Kind.DELIVER,
	Objective.GATES: ScenarioObjectives.Kind.GATES,
	Objective.SALVAGE: ScenarioObjectives.Kind.SALVAGE,
	Objective.ESCORT: ScenarioObjectives.Kind.ESCORT,
	Objective.ASSAULT: ScenarioObjectives.Kind.ASSAULT,
	Objective.DOCK: ScenarioObjectives.Kind.DOCK,
	Objective.VOYAGE: ScenarioObjectives.Kind.VOYAGE,
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
	# What stands at an escort's yellow marker: "station", "gate" or "beacon"
	# ("" = the beacon alone).
	"dest": "",
	# A colour in the level's name: which ships wear it ("foes" / "friend";
	# "planet" is the main world, handled with the system) and the faction paint.
	"tint_for": "",
	"tint_faction": "",
	# Seconds between enemy waves on an escort (0 = none).
	"wave_every": 0.0,
	# A boss: one huge enemy warship in the first wave, [code]boss_size[/code]
	# times a fighter's size, [code]boss_hp[/code] times [constant BOSS_HP]
	# (and the level's enemy_hp), calling [code]boss_guards[/code] fresh guards
	# every [code]boss_reinforce[/code] seconds while it lives (0 = never).
	"boss": false,
	"boss_size": 6.5,
	"boss_hp": 1.0,
	"boss_reinforce": 0.0,
	"boss_guards": 2,
	# Other fighter archetypes (FIGHTER_ARCHETYPES keys) mixed in with
	# enemy_arch, one ship in [code]enemy_mix_every[/code] each.
	"enemy_mix": [],
	"enemy_mix_every": 3,
	# Scenery: this many neutral giants (big freighters, team 0) drifting
	# through, and backdrop megastructures ([LargeCraftGenerator]) in the
	# distance. Neither fights anyone.
	"bystanders": 0,
	"backdrop": 0,
	# The level climb ([Difficulty.for_level]): enemy size ×, aggression
	# ([method AiShip.set_threat]), the heaviest gun class they may carry
	# (0 fighter … 3 capital) and the share that carry it, attack slots on the
	# player (-1 = the Juice dial), the boss's own gun class and hull preset.
	"enemy_size": 1.0,
	"threat": 1.0,
	"gun_class": -1,
	"heavy_share": 0.3,
	"max_attackers": -1,
	"boss_gun_class": -1,
	"boss_preset": "",
	# Backdrop megastructures' size ([enum FlightRoot.CraftSize]; -1 = the
	# debug menu's pick).
	"backdrop_size": -1,
	# A megastructure boss ([LargeCraftGenerator] + [MegaCraft]) instead of a
	# big ship: its kind (0 dreadnought, 1 mothership) and size (CraftSize).
	"mega_boss": false,
	"mega_kind": 0,
	"mega_size": 1,
	# ASSAULT: the carrier is a megastructure of mega_size.
	"mega": false,
	# Heavy dreadnoughts (the keel_dreadnought hull) in the first wave.
	"dreadnoughts": 0,
	"dreadnought_size": 3.0,
	"dreadnought_hp": 5.0,
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
	"boss": {
		"name": "Boss fight", "desc": "A huge warship and its guards block the road. Wreck the boss.",
		"enemies": 3, "enemy_arch": "Military squad", "enemy_distance": 900.0, "allies": 2,
		"boss": true, "boss_reinforce": 26.0, "enemy_mix": ["Strike team"], "backdrop": 0,
	},
}
const OBJECTIVE_PRESETS := {
	"courier": {
		"name": "Courier run", "desc": "Grab the three cargo packages, any order. Follow the gold arrow. No shooting needed.",
		"objective": Objective.DELIVER, "enemies": 0, "points": 3, "spacing": 1000.0,
	},
	"race": {
		"name": "Ring race", "desc": "Fly through all eight rings, any order, before the clock runs out.",
		"objective": Objective.GATES, "enemies": 0, "gates": 8, "time_limit": 90.0,
	},
	"salvage": {
		"name": "Salvage sweep", "desc": "Six cargo pods are drifting nearby. Touch them all to collect them.",
		"objective": Objective.SALVAGE, "enemies": 0, "pods": 6, "spacing": 800.0,
	},
	"dock": {
		"name": "Dock with the carrier", "desc": "A giant friendly carrier waits ahead. Fly into its glowing bay and slow right down.",
		"objective": Objective.DOCK, "enemies": 0, "escort_size": 10.0, "route": 2500.0,
	},
	"escort": {
		"name": "Escort the hauler", "desc": "Guard a big freighter to its destination. Pirates will go for it, not you.",
		"objective": Objective.ESCORT, "enemies": 3, "enemy_arch": "Pirates", "wave_every": 22.0,
		"escort_size": 4.0, "escort_speed": 60.0, "route": 2100.0, "enemy_distance": 700.0,
	},
	"capital": {
		"name": "Escort the capital ship", "desc": "A huge capital ship crawls to the jump point under heavy attack. Keep it alive.",
		"objective": Objective.ESCORT, "enemies": 4, "enemy_arch": "Military squad", "wave_every": 26.0, "allies": 2,
		"escort_size": 9.0, "escort_speed": 42.0, "escort_hp": 2.5, "route": 2500.0, "enemy_distance": 900.0,
	},
	"protect": {
		"name": "Guard the hauler", "desc": "A hauler is stranded while its drive cools. Keep it safe until the clock runs out.",
		"objective": Objective.ESCORT, "enemies": 3, "enemy_arch": "Pirates", "wave_every": 18.0,
		"escort_size": 4.0, "hold_time": 75.0, "enemy_distance": 700.0,
	},
	"voyage": {
		"name": "Voyage", "desc": "Fly out to a far planet of this system. Pirates may be waiting on the way.",
		"objective": Objective.VOYAGE, "enemies": 0,
	},
	"assault": {
		"name": "Carrier assault", "desc": "Bring down an enemy mothership. It keeps launching fighters while it lives.",
		"objective": Objective.ASSAULT, "enemies": 2, "enemy_arch": "Pirates", "enemy_distance": 1400.0, "allies": 2,
	},
}
const PRESET_ORDER := ["duel", "skirmish", "waves", "battle", "survive", "practice", "ambush", "boss"]
## The boss's hull before the dials: many fighters' worth.
const BOSS_HP := 2600.0
## A neutral giant's size, in fighter sizes.
const BYSTANDER_SIZE := Vector2(5.0, 8.0)
## The objective scenarios, in picker order (after the fights).
const OBJECTIVE_ORDER := ["courier", "race", "salvage", "dock", "escort", "capital", "protect", "voyage", "assault"]

var state: int = State.IDLE
## The running scenario's full settings ([constant DEFAULTS] + overrides).
var config: Dictionary = {}
var wave := 0
var kills := 0
## Kills the player made themselves (not the wingmen): the fight star.
var player_kills := 0
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
## The running boss fight's boss, or null.
var boss: AiShip = null
## A megastructure boss ([code]mega_boss[/code]), or null.
var mega_boss: MegaCraft = null
var _boss_clock := 0.0
var _mega_nag := 6.0
## Scenery this scenario put in (see [code]bystanders[/code] / [code]backdrop[/code]).
var _bystanders: Array[AiShip] = []
var _backdrop := false
## Why the last run was lost, in a word or three for the end card
## ("WRECKED", "ESCORT DESTROYED", "OUT OF TIME"), or "".
var lose_reason := ""

## What to do, in a few words, per preset: the tip line when one starts.
const TIPS := {
	"duel": "BEAT THE ACE", "skirmish": "WRECK THEM ALL", "waves": "CLEAR EVERY WAVE",
	"battle": "WIN THE BATTLE", "survive": "STAY ALIVE", "practice": "WRECK THE DRONES",
	"ambush": "BREAK THE AMBUSH", "courier": "GRAB THE CARGO", "race": "FLY THROUGH THE RINGS",
	"salvage": "GRAB THE PODS", "dock": "FLY INTO THE BAY", "escort": "ESCORT THE HAULER",
	"capital": "ESCORT THE BIG SHIP", "assault": "WRECK THE MOTHERSHIP", "boss": "WRECK THE BOSS",
	"protect": "GUARD THE HAULER", "voyage": "FLY TO THE FAR PLANET",
}


func setup(root: FlightRoot) -> void:
	_root = root


## A preset's full settings, ready to hand to [method start] (or to edit).
static func preset(id: String) -> Dictionary:
	var c := DEFAULTS.duplicate()
	c.merge(PRESETS.get(id, OBJECTIVE_PRESETS.get(id, {})), true)
	if TIPS.has(id):
		c["tip"] = TIPS[id]
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


## The objective's goals that pull the player and snap a slingshot aim
## (empty when none).
func objective_points() -> Array[Vector3]:
	if _objectives != null and is_instance_valid(_objectives):
		return _objectives.magnet_points()
	return []


## The first enemy still flying (the lone ace of a duel), or null.
func first_enemy() -> AiShip:
	for s: AiShip in _enemies:
		if s != null and is_instance_valid(s) and s._alive:
			return s
	return null


## The friendly ship an escort mission guards, while it lives; else null.
func guarded_ship() -> AiShip:
	if _objectives == null or not is_instance_valid(_objectives):
		return null
	if _objectives.kind != ScenarioObjectives.Kind.ESCORT:
		return null
	var s := _objectives.ship
	return s if s != null and is_instance_valid(s) and s._alive else null


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
	player_kills = 0
	elapsed = 0.0
	state = State.RUNNING
	_apply_rules()
	var objective := int(config["objective"])
	if OBJECTIVE_KINDS.has(objective):
		_objectives = ScenarioObjectives.new()
		_objectives.name = "Objectives"
		add_child(_objectives)
		_objectives.begin(OBJECTIVE_KINDS[objective], config, _root, _spawner)
		_wave_clock = 0.0
		# Guard missions: a couple of attackers on the guarded ship at a
		# time, the rest (and anyone near the player) on the player.
		AiShip.guard_ship = guarded_ship()
		AiShip.guard_share = Difficulty.v("protect_escort_share") if float(config.get("hold_time", 0.0)) > 0.0 else 1.0
		if int(config["enemies"]) > 0:
			_next_wave()
	else:
		_next_wave()
	# Wingmen after the enemy: under the ship cap the enemy must get its
	# slots first, or a fight could start with nobody to fight.
	_spawn_allies()
	if bool(config["boss"]):
		_spawn_boss()
	for i in int(config.get("dreadnoughts", 0)):
		_spawn_dreadnought(i)
	_spawn_scenery()
	# A guard job says how long: "GUARD IT FOR 1 MINUTE".
	var hold := roundi(float(config.get("hold_time", 0.0)))
	if hold > 0:
		config["tip"] = "GUARD IT FOR %s" % hold_words(hold)
	# A short tip in the sprayed hint line; the long desc stays in the picker.
	_root.announce(String(config.get("tip", String(config["name"]))))
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
	boss = null
	mega_boss = null
	_boss_clock = 0.0
	for b in _bystanders:
		if is_instance_valid(b) and b._alive:
			b.teardown()
	_bystanders.clear()
	if _backdrop and _root != null:
		_root.clear_large_craft(true)
	_backdrop = false
	_wave_delay = -1.0
	AiSpawner.scenario_cap = -1
	AiShip.clear_scenario_rules()
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
## The guarded ship's hull left (0–1) on an escort or protect mission (0 once
## it is gone), or -1 when nothing is guarded — for the star rating.
func guard_hull() -> float:
	if _objectives == null or not is_instance_valid(_objectives) or _objectives.kind != ScenarioObjectives.Kind.ESCORT:
		return -1.0
	var s := _objectives.ship
	if s == null or not is_instance_valid(s) or not s._alive:
		return 0.0
	return clampf(s.hp / maxf(s.max_hp, 1.0), 0.0, 1.0)


## For the HUD: how many enemies a fight still has ("3 LEFT", "WAVE 2/4 · 3
## LEFT"), or "" when the count means nothing — no scenario, a hold-out that
## keeps topping its attackers up, or an objective level (waves there are
## endless pressure, not a count to clear).
func count_line() -> String:
	if state != State.RUNNING or _objectives != null:
		return ""
	if int(config.get("objective", Objective.DESTROY)) != Objective.DESTROY:
		return ""
	var foes := _alive(_enemies).size()
	var line := "%d LEFT" % foes
	if int(config["waves"]) > 1:
		line = "WAVE %d/%d  ·  %s" % [wave, int(config["waves"]), line]
	return line


func status_line() -> String:
	match state:
		State.IDLE:
			return ""
		State.WON:
			return "%s: VICTORY! %d kills" % [config.get("name", ""), kills]
		State.LOST:
			return "%s: %s" % [config.get("name", ""), lose_reason]
	if _objectives != null:
		return _objectives.status()
	# A megastructure boss is an enemy too, and the last one standing.
	var foes := _alive(_enemies).size() + (1 if mega_alive() else 0)
	var friends := _alive(_allies).size()
	var line := String(config["name"]).to_upper()
	match int(config["objective"]):
		Objective.SURVIVE:
			line += "  ·  SURVIVE %ds" % ceili(maxf(float(config["survive_time"]) - elapsed, 0.0))
		_:
			if int(config["waves"]) > 1:
				line += "  ·  WAVE %d/%d" % [wave, int(config["waves"])]
			if is_instance_valid(boss) and boss._alive:
				line += "  ·  BOSS %d%%" % ceili(boss.hp / maxf(boss.max_hp, 1.0) * 100.0)
			elif mega_alive():
				line += "  ·  BOSS %d%%" % ceili(mega_boss.health() * 100.0)
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
	_tick_boss(delta)
	if objective == Objective.SURVIVE:
		if elapsed >= float(config["survive_time"]):
			_finish(true)
			return
		# Keep the pressure on: top the attackers back up as they fall.
		if foes.size() < int(config["enemies"]) and _wave_delay < 0.0:
			_wave_delay = 3.0
	elif foes.is_empty() and _wave_delay < 0.0 and not mega_alive():
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
		_root.announce("WAVE CLEAR!")
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
		_root.announce("WAVE %d!" % wave)


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
	# Enemies can come as a mix of kinds: every [code]enemy_mix_every[/code]th
	# ship is one of the enemy_mix archetypes, in their own group.
	var mix: Array = config.get("enemy_mix", []) if team == ENEMY_TEAM else []
	var every := maxi(int(config.get("enemy_mix_every", 3)), 2)
	var mixed := 0 if mix.is_empty() or count < 2 else maxi(count / every, 1)
	var arch := AiFactions.create(int(FIGHTER_ARCHETYPES.get(arch_name, AiFactions.Archetype.WOLF_PIRATE)))
	# The climb makes enemies bigger; wingmen stay as they are.
	AiShip.spawn_scale = float(config.get("enemy_size", 1.0)) if team == ENEMY_TEAM else 1.0
	_spawner.spawn_group_with(arch, count - mixed, team)
	if mixed > 0:
		var other := String(mix[randi() % mix.size()])
		_spawner.spawn_group_with(
			AiFactions.create(int(FIGHTER_ARCHETYPES.get(other, AiFactions.Archetype.STRIKE_TEAM))), mixed, team)
	AiShip.spawn_scale = 1.0
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
			_toughen(s)
			if bool(config["frozen_enemies"]):
				s._ai_paused = true
				s.systems.set_firing(false)
			_enemies.append(s)
			if String(config.get("tint_for", "")) == "foes":
				s.paint_as(String(config.get("tint_faction", "")))
			# The ones coming for the convoy wear a red target from the start.
			if int(config.get("objective", -1)) == Objective.ESCORT:
				_root.pin_marker(s, InteractionMarkers.COLORS[AiShip.Attitude.HOSTILE])
		else:
			var side := -1.0 if i % 2 == 0 else 1.0
			pos = ship_x.origin + right * side * (50.0 + 35.0 * float(i / 2)) - fwd * (25.0 + 15.0 * float(i / 2))
			_place(s, Transform3D(Basis.looking_at(fwd, up), pos))
			_allies.append(s)
			# Wingmen wear a green target, like the red ones on the foe.
			_root.pin_marker(s, InteractionMarkers.COLORS[AiShip.Attitude.FRIENDLY])
		i += 1


## The boss: one huge warship at the head of the enemy line, marked for the
## player, with a hull of [constant BOSS_HP] under the level's dials.
func _spawn_boss() -> void:
	if bool(config.get("mega_boss", false)) and _spawn_mega_boss():
		return
	var ship_x := _root.model.global_transform
	var fwd := -ship_x.basis.z
	var up := ship_x.basis.y
	var pos := ship_x.origin + fwd * (float(config["enemy_distance"]) + 250.0 + maxf(float(config["boss_size"]) - 3.5, 0.0) * 40.0)
	var arch := AiFactions.create(int(FIGHTER_ARCHETYPES.get(String(config["enemy_arch"]), AiFactions.Archetype.MILITARY_SQUAD)))
	var xf := Transform3D(Basis.looking_at(-fwd, up), pos)
	boss = _spawner.spawn_big(xf, float(config["boss_size"]), ENEMY_TEAM, arch, String(config.get("boss_preset", "")))
	if boss == null:
		return
	_place(boss, xf)
	# Marked so a swarm archetype's "popcorn" rules (a hard ram pops it) skip it.
	boss.set_meta("boss", true)
	boss.max_hp = BOSS_HP * float(config["boss_hp"]) * float(config["enemy_hp"])
	boss.hp = boss.max_hp
	boss._weapon_mult *= float(config["enemy_damage"])
	boss.set_threat(float(config.get("threat", 1.0)))
	if String(config.get("tint_for", "")) == "foes":
		boss.paint_as(String(config.get("tint_faction", "")))
	if int(config.get("boss_gun_class", -1)) >= 0:
		boss.arm(int(config["boss_gun_class"]))
	_enemies.append(boss)
	_boss_clock = 0.0
	_root.pin_marker(boss, Color("ff2a4a"))
	_root.big_notice("BOSS!", String(config.get("name", "")).to_upper(), Color("ff2a4a"), 1.6)


## While the boss lives it calls in fresh guards now and then.
func _tick_boss(delta: float) -> void:
	# Only the big ship left: say so now and then, or the level looks stuck.
	if mega_alive() and _alive(_enemies).is_empty():
		_mega_nag -= delta
		if _mega_nag <= 0.0:
			_mega_nag = 20.0
			_root.announce("WRECK THE BOSS SHIP TO WIN!")
	var every := float(config.get("boss_reinforce", 0.0))
	if boss == null or every <= 0.0:
		return
	if not is_instance_valid(boss) or not boss._alive:
		boss = null
		return
	_boss_clock += delta
	if _boss_clock < every:
		return
	_boss_clock = 0.0
	var before := _spawner.ships().duplicate()
	var arch := AiFactions.create(int(FIGHTER_ARCHETYPES.get(String(config["enemy_arch"]), AiFactions.Archetype.MILITARY_SQUAD)))
	_spawner.spawn_group_with(arch, int(config["boss_guards"]), ENEMY_TEAM)
	var at := boss.global_transform
	var side_dir := at.basis.x.normalized()
	var i := 0
	for s: AiShip in _spawner.ships():
		if s in before:
			continue
		var side := -1.0 if i % 2 == 0 else 1.0
		_place(s, Transform3D(at.basis.orthonormalized(), at.origin + side_dir * side * (80.0 + 30.0 * i)))
		_toughen(s)
		_enemies.append(s)
		i += 1
	if i > 0:
		_root.announce("THE BOSS CALLS FOR HELP!")


## A megastructure boss: a dreadnought or a mothership ([code]mega_kind[/code])
## of [code]mega_size[/code], straight ahead, armed — turrets, launch bays, a
## hull shot off piece by piece. False if it could not be built (the level
## then gets its ordinary big-ship boss).
func _spawn_mega_boss() -> bool:
	var kind := LargeCraftGenerator.Archetype.MOTHERSHIP if int(config.get("mega_kind", 0)) == 1 \
		else LargeCraftGenerator.Archetype.DREADNOUGHT
	var gen := _root.spawn_large_craft(kind, Vector3.ZERO, int(config.get("mega_size", 1)))
	if gen == null:
		return false
	mega_boss = _root.arm_large_craft(gen, true)
	if mega_boss == null:
		return false
	mega_boss.damage_mult = float(config.get("enemy_damage", 1.0))
	mega_boss.always_active = true
	_backdrop = true
	_root.big_notice("BOSS!", String(config.get("name", "")).to_upper(), Color("ff2a4a"), 1.6)
	return true


## Whether the megastructure boss is still in one piece.
func mega_alive() -> bool:
	return mega_boss != null and is_instance_valid(mega_boss) and not mega_boss.is_dead()


## A ship that joined the enemy mid-fight (a megastructure's launched
## fighter): counted, marked and toughened like the rest.
func add_enemy(s: AiShip) -> void:
	if state != State.RUNNING or s == null or s in _enemies:
		return
	_toughen(s)
	_enemies.append(s)
	_root.pin_marker(s, InteractionMarkers.COLORS[AiShip.Attitude.HOSTILE])


## [param s] seconds as words: "30 SECONDS", "1 MINUTE", "1 MINUTE 30".
static func hold_words(s: int) -> String:
	if s < 60:
		return "%d SECONDS" % s
	var m := s / 60
	var rest := s % 60
	var out := "%d MINUTE%s" % [m, "" if m == 1 else "S"]
	return out + (" %d" % rest if rest > 0 else "")


## The level's scenery: neutral giants drifting across the field and
## megastructures out in the distance. They fight no one; they are there to
## make the place feel lived in (and to be flown past).
func _spawn_scenery() -> void:
	# Nothing on screen may out-size a boss, cosmetic or not.
	if bool(config.get("boss", false)):
		return
	var ship_x := _root.model.global_transform
	var fwd := -ship_x.basis.z
	var right := ship_x.basis.x
	var up := ship_x.basis.y
	for i in int(config.get("bystanders", 0)):
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := ship_x.origin + right * side * randf_range(500.0, 800.0) + fwd * randf_range(200.0, 900.0)
		pos += up * randf_range(-80.0, 120.0)
		# Crossing the field, not coming at the player.
		var heading := (-right * side + fwd * randf_range(-0.3, 0.3)).normalized()
		var xf := Transform3D(Basis.looking_at(heading, up), pos)
		var b := _spawner.spawn_big(xf, randf_range(BYSTANDER_SIZE.x, BYSTANDER_SIZE.y), 0,
			AiFactions.create(AiFactions.Archetype.CONVOY_TRADER))
		if b != null:
			_place(b, xf)
			_bystanders.append(b)
	var kinds := [LargeCraftGenerator.Archetype.MOTHERSHIP, LargeCraftGenerator.Archetype.RING_STATION,
		LargeCraftGenerator.Archetype.TOWER_CLUSTER, LargeCraftGenerator.Archetype.GATE_FRAME]
	for i in int(config.get("backdrop", 0)):
		var bearing := (fwd + right * randf_range(-1.2, 1.2) + up * randf_range(-0.2, 0.4)).normalized()
		if _root.spawn_large_craft(kinds[randi() % kinds.size()], bearing, int(config.get("backdrop_size", -1))) != null:
			_backdrop = true


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
		if ship.killed_by_player:
			player_kills += 1


## The player's own share of the kills so far (0..1), or -1 before any.
func kill_share() -> float:
	return float(player_kills) / float(kills) if kills > 0 else -1.0


## The scenario-wide rules from [Difficulty]: who enemies go for, how hard
## the wingmen hit, how many may shoot at the player at once.
func _apply_rules() -> void:
	AiShip.clear_scenario_rules()
	AiShip.player_focus = Difficulty.v("player_focus")
	AiShip.ally_damage_mult = Difficulty.v("ally_damage")
	AiShip.guard_max_attackers = int(Difficulty.v("escort_max_attackers"))
	AiShip.guard_player_range = Difficulty.v("escort_player_range")
	AiShip.max_attackers_override = int(config.get("max_attackers", -1))


## A fresh enemy brought up to the level: hull and damage dials, its
## aggression, and its guns — the heaviest class allowed for a share of
## them (a lone ace always), one class lower for the rest.
func _toughen(s: AiShip) -> void:
	s.max_hp = clampf(s.max_hp, ENEMY_HP_MIN, ENEMY_HP_MAX) * float(config["enemy_hp"])
	s.hp = s.max_hp
	s._weapon_mult *= float(config["enemy_damage"])
	s.set_threat(float(config.get("threat", 1.0)))
	var top := int(config.get("gun_class", -1))
	if top >= 0:
		s.arm(top if randf() < float(config.get("heavy_share", 0.3)) else maxi(top - 1, 0))


## A heavy dreadnought (the keel_dreadnought hull) out on the enemy's flank:
## a big, slow gun platform with capital guns and many fighters' hull.
func _spawn_dreadnought(i: int) -> void:
	var ship_x := _root.model.global_transform
	var fwd := -ship_x.basis.z
	var side := -1.0 if i % 2 == 0 else 1.0
	var pos := ship_x.origin + fwd * (float(config["enemy_distance"]) + 350.0) + ship_x.basis.x * side * 320.0
	var xf := Transform3D(Basis.looking_at(-fwd, ship_x.basis.y), pos)
	var arch := AiFactions.create(AiFactions.Archetype.MILITARY_SQUAD)
	var d_size := float(config.get("dreadnought_size", 3.0))
	if bool(config.get("boss", false)):
		d_size = minf(d_size, float(config["boss_size"]) * 0.6)
	var d := _spawner.spawn_big(xf, d_size, ENEMY_TEAM, arch, Difficulty.DREADNOUGHT_PRESET)
	if d == null:
		return
	_place(d, xf)
	d.max_hp = ENEMY_HP_MAX * float(config["enemy_hp"]) * float(config.get("dreadnought_hp", 5.0))
	d.hp = d.max_hp
	d._weapon_mult *= float(config["enemy_damage"])
	d.set_threat(float(config.get("threat", 1.0)))
	d.arm(3)
	_enemies.append(d)
	_root.pin_marker(d, Color("ff8a2a"))
	_root.announce("DREADNOUGHT!")


func _finish(won: bool) -> void:
	state = State.WON if won else State.LOST
	lose_reason = ""
	if not won:
		if _root._player_dead:
			lose_reason = "WRECKED"
		elif _objectives != null and _objectives.lose_reason != "":
			lose_reason = _objectives.lose_reason
		else:
			lose_reason = "MISSION FAILED"
	_root.announce("VICTORY!" if won else lose_reason)
	changed.emit()


static func _alive(list: Array[AiShip]) -> Array[AiShip]:
	var out: Array[AiShip] = []
	for s in list:
		if is_instance_valid(s) and s._alive:
			out.append(s)
	return out
