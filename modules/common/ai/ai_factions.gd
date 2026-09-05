## Faction archetypes: the personality and group behaviour of each faction type.
##
## Each archetype defines HOW a faction's ships move and fight together.
## The archetype is assigned when a ship spawns and never changes.
## Multiple factions can share an archetype (e.g. two pirate groups both use
## the WOLF archetype but with different aggression and detection ranges).
##
## Adding a new faction type:
##   1. Add an enum value to [enum Archetype]
##   2. Add its defaults in [method _defaults_for]
##   3. Optionally add it to [method random_archetype] weighted spawn table
##   4. The behaviour system picks it up automatically — no other code changes.
##
## Adding a new use case (e.g. "escort convoy"):
##   1. Pick an existing archetype or create a new one
##   2. Tune its parameters (detection_range, aggression, formation, etc.)
##   3. The 30 use cases in AI_USE_CASES.md document the parameter combos.
class_name AiFactions
extends RefCounted


enum Archetype {
	## Solo opportunistic fighters. Loose formation, hit-and-run, flee when outnumbered.
	WOLF_PIRATE,
	## Coordinated patrol ships. V-formation, investigate threats, call for backup.
	POLICE_PATROL,
	## Mindless swarm. Boid flocking, no tactics, overwhelm with numbers.
	BASIC_SWARM,
	## Organized military. Tight formations, leapfrog advances, suppressive fire.
	MILITARY_SQUAD,
	## Traders in a convoy. Follow a leader, flee from threats, fight only cornered.
	CONVOY_TRADER,
	## Scouting party. Fast, spread out, investigate and report, flee if engaged.
	SCOUT_GROUP,
	## Station defenders. Orbit the station, converge on threats, high aggression near home.
	STATION_GUARD,
	## Lone wolf. No group behaviour, pure individual state machine.
	LONE_WOLF,
	## Precision strike team. Small squad, pincer manoeuvres, target priority.
	STRIKE_TEAM,
	## Elritch swarm. Alien, eerie movement patterns, impossible geometry.
	ELDRITCH_SWARM,
	## Tiny alien drones. Fast, chaotic, swarm-like but with purpose.
	ALIEN_DRONE,
	## Mining operation. Slow, methodical, orbit asteroids, flee from danger.
	MINING_CREW,
	## Rescue team. Investigate distress signals, converge on the source, defensive.
	RESCUE_TEAM,
	## Smuggler. Solo or pair, evasive, uses asteroid cover, fights only cornered.
	SMUGGLER,
	## Bounty hunters. Small group, coordinated pursuit, high aggression,智能 target selection.
	BOUNTY_HUNTER,
	## Ancient autopilot. Derelict ships that move in pre-programmed patterns.
	DERELICT_PATROL,
	## Escort detail. Surround a VIP, react to threats proportionally.
	ESCORT_GROUP,
	## Pirate fleet. Large group, wolfpack tactics, encircle and overwhelm.
	PIRATE_FLEET,
	## Police strike force. Tactical entry, suppressive fire, arrest-focused.
	POLICE_STRIKE,
	## Research vessel. Slow, cautious, investigate anomalies, flee from combat.
	RESEARCH_GROUP,
	## Patrol drone. Autonomous, repetitive patrol route, ignores most threats.
	PATROL_DRONE,
	## Distress signal bait. Lures ships in, then ambushes.
	AMBUSHER,
	## Honor guard. Tight formation around a capital ship, suicidal defense.
	HONOR_GUARD,
	## Scavengers. Circle wreckage, flee from living ships, opportunistic.
	SCAVENGERS,
	## Religious cult. Orbital patterns around a sacred point, aggressive when approached.
	CULT_ORBITAL,
	## Automated defense grid. Stationary positions, fire on anything in range.
	DEFENSE_GRID,
	## Migration fleet. Large group, slow, directional, avoid combat.
	MIGRATION_FLEET,
	## Experimentation drones. Erratic movement, test attack patterns, adaptive.
	EXPERIMENT_DRONE,
	## Deep space anomaly. Moves in impossible patterns, distorts nearby ships.
	ANOMALY,
	## Emergency response. Fast, converge on the emergency, aggressive toward threats.
	EMERGENCY_RESPONSE,
	## The guaranteed player-hunter squad: always aggressive, tight V formation,
	## pincer attack. Spawned by [AiSpawner.spawn_hunters] so every session meets
	## a pursuer even when the random fleet is all civilians.
	HUNTER_SQUAD,
}


## Behaviour profiles for [method custom] — what the HUD's spawn panel lets the
## player pick for a manually-spawned group.
enum Behavior {
	## Chase and engage the player on sight.
	HUNT,
	## Wander a patrol area, investigate contacts.
	PATROL,
	## Mindless boid swarm that mobs the player.
	SWARM,
	## Run from the player.
	FLEE,
	## Orbit a point, defend if threatened.
	GUARD,
	## Sit still / drift slowly and shoot — aims better by not moving.
	SNIPER,
}


## The data that defines how a faction type behaves.
class ArchetypeData:
	var archetype: int = Archetype.LONE_WOLF
	## Group size range (min, max ships per group).
	var group_size_min := 1
	var group_size_max := 1
	## Detection range in metres.
	var detection_range := 800.0
	## Flee range — when to run.
	var flee_range := 200.0
	## Aggression: 0 = pacifist, 1 = always attacks.
	var aggression := 0.3
	## Preferred group movement mode.
	var group_mode: int = AiGroupBehaviour.FormationShape.SCATTER
	## Preferred formation spacing in metres.
	var formation_spacing := 80.0
	## Combat pattern: 0=encircle, 1=pincer, 2=feint.
	var combat_pattern := 0
	## Threat response: IGNORE, INVESTIGATE, FLEE, ATTACK, DEFEND.
	var default_response: int = AiGroupBehaviour.ThreatResponse.INVESTIGATE
	## Whether this faction uses boid flocking.
	var use_boids := false
	## Whether this faction uses swarm rules.
	var use_swarm := false
	## Boid weights override (if null, uses defaults).
	var boid_weights: Dictionary = {}
	## Speed multiplier relative to base stats.
	var speed_mult := 1.0
	## Whether ships in this faction can boost.
	var can_boost := true
	## Behavioural tags for the per-ship state machine.
	var tags: Array[String] = []
	## Combat style: when a target is inside weapons range, hold nearly still and
	## rotate fully onto it instead of chasing — a turret or sniper reads as
	## deadly because it stops moving and aims.
	var hold_to_aim := false


## Returns a new [ArchetypeData] with defaults for the given archetype.
## Call this once per ship at spawn time.
static func create(archetype: int) -> ArchetypeData:
	var data := ArchetypeData.new()
	data.archetype = archetype
	_apply_defaults(data)
	return data


## Pick a random archetype, weighted toward common types.
static func random_archetype(rng: RandomNumberGenerator) -> int:
	# Weighted table: common types appear more often.
	var table: Array[int] = [
		Archetype.WOLF_PIRATE, Archetype.WOLF_PIRATE, Archetype.WOLF_PIRATE,
		Archetype.POLICE_PATROL, Archetype.POLICE_PATROL,
		Archetype.BASIC_SWARM, Archetype.BASIC_SWARM,
		Archetype.CONVOY_TRADER,
		Archetype.SCOUT_GROUP,
		Archetype.STATION_GUARD,
		Archetype.MILITARY_SQUAD,
		Archetype.LONE_WOLF, Archetype.LONE_WOLF,
		Archetype.SMUGGLER,
		Archetype.ALIEN_DRONE, Archetype.ALIEN_DRONE,
		Archetype.ELDRITCH_SWARM,
		Archetype.MINING_CREW,
		Archetype.SCAVENGERS,
		Archetype.BOUNTY_HUNTER,
		Archetype.PATROL_DRONE,
		Archetype.ESCORT_GROUP,
		Archetype.CULT_ORBITAL,
		Archetype.AMBUSHER,
		Archetype.DERELICT_PATROL,
		Archetype.RESEARCH_GROUP,
		Archetype.EXPERIMENT_DRONE,
		Archetype.ANOMALY,
		Archetype.MIGRATION_FLEET,
		Archetype.EMERGENCY_RESPONSE,
	]
	return table[rng.randi() % table.size()]


## Build an archetype from independent choices (behaviour, formation, group size)
## — what the HUD's spawn panel drives. Behaviour and formation are decoupled, so
## a player can spawn "3 hunters in a line" or "6 boids in a sphere".
static func custom(behavior: int, formation: int, count: int) -> ArchetypeData:
	var d := ArchetypeData.new()
	d.group_size_min = maxi(count, 1)
	d.group_size_max = maxi(count, 1)
	d.group_mode = formation
	d.formation_spacing = 80.0
	match behavior:
		Behavior.HUNT:
			d.aggression = 1.0
			d.detection_range = 1500.0
			d.flee_range = 0.0
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.combat_pattern = 1  # Pincer
			d.speed_mult = 1.1
			d.tags = ["hunter"]
		Behavior.PATROL:
			d.aggression = 0.4
			d.detection_range = 900.0
			d.flee_range = 200.0
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 0.9
			d.tags = ["patrol"]
		Behavior.SWARM:
			d.use_boids = true
			d.use_swarm = true
			d.aggression = 0.5
			d.detection_range = 500.0
			d.flee_range = 100.0
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.2
			d.can_boost = false
			d.tags = ["swarm"]
		Behavior.FLEE:
			d.aggression = 0.05
			d.detection_range = 700.0
			d.flee_range = 400.0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 1.0
			d.can_boost = false
			d.tags = ["civilian"]
		Behavior.GUARD:
			d.aggression = 0.9
			d.detection_range = 800.0
			d.flee_range = 0.0
			d.default_response = AiGroupBehaviour.ThreatResponse.DEFEND
			d.speed_mult = 0.9
			d.tags = ["guard"]
		Behavior.SNIPER:
			d.aggression = 1.0
			d.detection_range = 1500.0
			d.flee_range = 0.0
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 0.6
			d.hold_to_aim = true
			d.tags = ["sniper"]
	return d


# --- Internal defaults -------------------------------------------------------

static func _apply_defaults(d: ArchetypeData) -> void:
	match d.archetype:
		Archetype.WOLF_PIRATE:
			d.group_size_min = 2
			d.group_size_max = 5
			d.detection_range = 900.0
			d.flee_range = 150.0
			d.aggression = 0.7
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 120.0
			d.combat_pattern = 2  # Feint
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.15
			d.tags = ["aggressive", "pack"]

		Archetype.POLICE_PATROL:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 1200.0
			d.flee_range = 0.0  # Police don't flee
			d.aggression = 0.5
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 100.0
			d.combat_pattern = 1  # Pincer
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 1.0
			d.tags = ["lawful", "coordinated"]

		Archetype.BASIC_SWARM:
			d.group_size_min = 6
			d.group_size_max = 15
			d.detection_range = 300.0
			d.flee_range = 80.0
			d.aggression = 0.2
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 40.0
			d.use_boids = true
			d.use_swarm = true
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.8
			d.can_boost = false
			d.tags = ["mindless", "flocking"]

		Archetype.MILITARY_SQUAD:
			d.group_size_min = 3
			d.group_size_max = 6
			d.detection_range = 1000.0
			d.flee_range = 0.0  # Military doesn't flee
			d.aggression = 0.8
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 90.0
			d.combat_pattern = 1  # Pincer
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.0
			d.tags = ["military", "disciplined"]

		Archetype.CONVOY_TRADER:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 600.0
			d.flee_range = 400.0
			d.aggression = 0.1
			d.group_mode = AiGroupBehaviour.FormationShape.LINE
			d.formation_spacing = 150.0
			d.combat_pattern = 0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.85
			d.can_boost = false
			d.tags = ["civilian", "cautious"]

		Archetype.SCOUT_GROUP:
			d.group_size_min = 2
			d.group_size_max = 3
			d.detection_range = 1500.0
			d.flee_range = 300.0
			d.aggression = 0.2
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 200.0
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 1.3
			d.tags = ["recon", "fast"]

		Archetype.STATION_GUARD:
			d.group_size_min = 3
			d.group_size_max = 6
			d.detection_range = 800.0
			d.flee_range = 0.0  # Guards don't flee from their post
			d.aggression = 0.9
			d.group_mode = AiGroupBehaviour.FormationShape.SPHERE
			d.formation_spacing = 200.0
			d.combat_pattern = 0  # Encircle
			d.default_response = AiGroupBehaviour.ThreatResponse.DEFEND
			d.speed_mult = 0.9
			d.hold_to_aim = true  # Turret-style: hold the ring, aim properly
			d.tags = ["guard", "defensive"]

		Archetype.LONE_WOLF:
			d.group_size_min = 1
			d.group_size_max = 1
			d.detection_range = 700.0
			d.flee_range = 200.0
			d.aggression = 0.4
			d.default_response = AiGroupBehaviour.ThreatResponse.IGNORE
			d.speed_mult = 1.0
			d.tags = ["solo"]

		Archetype.STRIKE_TEAM:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 600.0
			d.flee_range = 100.0
			d.aggression = 0.95
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 60.0
			d.combat_pattern = 1  # Pincer
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.1
			d.tags = ["elite", "coordinated"]

		Archetype.ELDRITCH_SWARM:
			d.group_size_min = 8
			d.group_size_max = 25
			d.detection_range = 500.0
			d.flee_range = 0.0  # Eldritch things don't flee
			d.aggression = 0.6
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 50.0
			d.use_boids = true
			d.use_swarm = true
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.2
			d.can_boost = true
			d.tags = ["eldritch", "alien", "swarm"]

		Archetype.ALIEN_DRONE:
			d.group_size_min = 4
			d.group_size_max = 12
			d.detection_range = 400.0
			d.flee_range = 100.0
			d.aggression = 0.5
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 30.0
			d.use_boids = true
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.4
			d.can_boost = true
			d.tags = ["alien", "fast", "chaotic"]

		Archetype.MINING_CREW:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 400.0
			d.flee_range = 300.0
			d.aggression = 0.05
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 100.0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.7
			d.can_boost = false
			d.tags = ["civilian", "mining"]

		Archetype.RESCUE_TEAM:
			d.group_size_min = 2
			d.group_size_max = 3
			d.detection_range = 1500.0
			d.flee_range = 100.0
			d.aggression = 0.3
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 80.0
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 1.2
			d.tags = ["helpful", "fast"]

		Archetype.SMUGGLER:
			d.group_size_min = 1
			d.group_size_max = 2
			d.detection_range = 1000.0
			d.flee_range = 500.0
			d.aggression = 0.15
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 1.2
			d.tags = ["sneaky", "fast"]

		Archetype.BOUNTY_HUNTER:
			d.group_size_min = 2
			d.group_size_max = 3
			d.detection_range = 1200.0
			d.flee_range = 150.0
			d.aggression = 0.85
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 70.0
			d.combat_pattern = 2  # Feint
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.1
			d.tags = ["bounty", "aggressive"]

		Archetype.DERELICT_PATROL:
			d.group_size_min = 1
			d.group_size_max = 3
			d.detection_range = 200.0
			d.flee_range = 0.0
			d.aggression = 0.3
			d.group_mode = AiGroupBehaviour.FormationShape.TRAIL
			d.formation_spacing = 60.0
			d.default_response = AiGroupBehaviour.ThreatResponse.IGNORE
			d.speed_mult = 0.5
			d.can_boost = false
			d.tags = ["derelict", "slow"]

		Archetype.ESCORT_GROUP:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 900.0
			d.flee_range = 0.0  # Escorts don't flee
			d.aggression = 0.7
			d.group_mode = AiGroupBehaviour.FormationShape.SPHERE
			d.formation_spacing = 100.0
			d.combat_pattern = 0  # Encircle
			d.default_response = AiGroupBehaviour.ThreatResponse.DEFEND
			d.speed_mult = 1.0
			d.tags = ["escort", "protective"]

		Archetype.PIRATE_FLEET:
			d.group_size_min = 4
			d.group_size_max = 8
			d.detection_range = 1000.0
			d.flee_range = 100.0
			d.aggression = 0.85
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 150.0
			d.combat_pattern = 0  # Encircle
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.05
			d.tags = ["aggressive", "fleet"]

		Archetype.POLICE_STRIKE:
			d.group_size_min = 3
			d.group_size_max = 5
			d.detection_range = 800.0
			d.flee_range = 0.0
			d.aggression = 0.9
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 70.0
			d.combat_pattern = 1  # Pincer
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.1
			d.tags = ["lawful", "elite"]

		Archetype.RESEARCH_GROUP:
			d.group_size_min = 1
			d.group_size_max = 3
			d.detection_range = 1200.0
			d.flee_range = 400.0
			d.aggression = 0.0
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 150.0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.75
			d.can_boost = false
			d.tags = ["civilian", "curious"]

		Archetype.PATROL_DRONE:
			d.group_size_min = 1
			d.group_size_max = 1
			d.detection_range = 500.0
			d.flee_range = 0.0
			d.aggression = 0.4
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 0.9
			d.can_boost = false
			d.tags = ["drone", "automated"]

		Archetype.AMBUSHER:
			d.group_size_min = 3
			d.group_size_max = 6
			d.detection_range = 600.0
			d.flee_range = 0.0
			d.aggression = 1.0
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 200.0
			d.combat_pattern = 2  # Feint
			d.default_response = AiGroupBehaviour.ThreatResponse.IGNORE  # Wait
			d.speed_mult = 1.1
			d.tags = ["sneaky", "aggressive"]

		Archetype.HONOR_GUARD:
			d.group_size_min = 4
			d.group_size_max = 8
			d.detection_range = 600.0
			d.flee_range = 0.0
			d.aggression = 1.0
			d.group_mode = AiGroupBehaviour.FormationShape.SPHERE
			d.formation_spacing = 80.0
			d.combat_pattern = 0  # Encircle
			d.default_response = AiGroupBehaviour.ThreatResponse.DEFEND
			d.speed_mult = 0.9
			d.hold_to_aim = true  # Screen the VIP by holding and shooting straight.
			d.tags = ["guard", "suicidal"]

		Archetype.SCAVENGERS:
			d.group_size_min = 2
			d.group_size_max = 5
			d.detection_range = 500.0
			d.flee_range = 300.0
			d.aggression = 0.1
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 80.0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.8
			d.can_boost = false
			d.tags = ["civilian", "opportunistic"]

		Archetype.CULT_ORBITAL:
			d.group_size_min = 3
			d.group_size_max = 8
			d.detection_range = 400.0
			d.flee_range = 0.0
			d.aggression = 0.7
			d.group_mode = AiGroupBehaviour.FormationShape.SPHERE
			d.formation_spacing = 60.0
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 0.85
			d.tags = ["cult", "ritualistic"]

		Archetype.DEFENSE_GRID:
			d.group_size_min = 4
			d.group_size_max = 8
			d.detection_range = 1000.0
			d.flee_range = 0.0
			d.aggression = 1.0
			d.group_mode = AiGroupBehaviour.FormationShape.SPHERE
			d.formation_spacing = 150.0
			d.combat_pattern = 0
			d.default_response = AiGroupBehaviour.ThreatResponse.DEFEND
			d.speed_mult = 0.0  # Stationary
			d.hold_to_aim = true  # A defence grid IS a turret: still, and aimed.
			d.can_boost = false
			d.tags = ["automated", "stationary"]

		Archetype.MIGRATION_FLEET:
			d.group_size_min = 6
			d.group_size_max = 15
			d.detection_range = 500.0
			d.flee_range = 600.0
			d.aggression = 0.0
			d.group_mode = AiGroupBehaviour.FormationShape.TRAIL
			d.formation_spacing = 200.0
			d.default_response = AiGroupBehaviour.ThreatResponse.FLEE
			d.speed_mult = 0.6
			d.can_boost = false
			d.tags = ["civilian", "migration"]

		Archetype.EXPERIMENT_DRONE:
			d.group_size_min = 3
			d.group_size_max = 8
			d.detection_range = 500.0
			d.flee_range = 100.0
			d.aggression = 0.5
			d.group_mode = AiGroupBehaviour.FormationShape.SCATTER
			d.formation_spacing = 40.0
			d.use_boids = true
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.3
			d.tags = ["experimental", "adaptive"]

		Archetype.ANOMALY:
			d.group_size_min = 1
			d.group_size_max = 1
			d.detection_range = 2000.0
			d.flee_range = 0.0
			d.aggression = 0.0
			d.default_response = AiGroupBehaviour.ThreatResponse.IGNORE
			d.speed_mult = 2.0
			d.tags = ["anomaly", "unknowable"]

		Archetype.EMERGENCY_RESPONSE:
			d.group_size_min = 2
			d.group_size_max = 4
			d.detection_range = 2000.0
			d.flee_range = 50.0
			d.aggression = 0.6
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 80.0
			d.default_response = AiGroupBehaviour.ThreatResponse.INVESTIGATE
			d.speed_mult = 1.4
			d.tags = ["emergency", "fast"]

		Archetype.HUNTER_SQUAD:
			d.group_size_min = 3
			d.group_size_max = 4
			d.detection_range = 1600.0
			d.flee_range = 0.0  # Hunters don't flee the hunt.
			d.aggression = 1.0
			d.group_mode = AiGroupBehaviour.FormationShape.V_FORM
			d.formation_spacing = 90.0
			d.combat_pattern = 1  # Pincer
			d.default_response = AiGroupBehaviour.ThreatResponse.ATTACK
			d.speed_mult = 1.1
			d.tags = ["hunter", "elite"]
