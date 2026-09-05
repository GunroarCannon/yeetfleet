# AI Use Cases — 30 Group Behaviour Patterns

Each use case documents: what it is, which algorithms it uses, how to tune it, and where it fits in a space game. The system is modular — every use case is a combination of archetype parameters, not new code.

---

## How to Read This Document

Each use case specifies:
- **Archetype**: Which `AiFactions.Archetype` to use (or create)
- **Algorithms**: Which `AiGroupBehaviour` functions are active
- **Parameters**: Key tuning values
- **Game context**: When and why you'd see this in the game

To "activate" a use case, set the archetype's parameters in `ai_factions.gd` `_apply_defaults()`. The behaviour system picks it up automatically.

---

## PIRATES & OUTLAWS

### 1. Wolf Pack Ambush
**Archetype:** `WOLF_PIRATE` | **Algorithms:** Wolfpack pursuit (feint pattern), scatter formation
**Parameters:** group_size 3-5, aggression 0.7, detection 900m, flee 150m, speed 1.15×
**Game context:** 3-5 pirate ships burst from behind an asteroid, some feinting while others flank. The player sees ships splitting into two groups — one attacking head-on, the other circling to cut off escape. Classic Elite dangerous encounter.

### 2. Pirate Fleet Raid
**Archetype:** `PIRATE_FLEET` | **Algorithms:** Wolfpack (encircle), boid loose flocking for approach
**Parameters:** group_size 4-8, aggression 0.85, formation scatter, spacing 150m, encircle pattern
**Game context:** A large pirate fleet descends on a convoy or station. Ships approach in a loose cloud (boids), then split into encirclement positions when they reach engagement range. The sheer number is the threat.

### 3. Smuggler's Run
**Archetype:** `SMUGGLER` | **Algorithms:** Solo or pair, evasive waypoint weaving
**Parameters:** group_size 1-2, aggression 0.15, flee_range 500m, speed 1.2×, no boost
**Game context:** One or two fast ships threading through the asteroid belt, changing direction frequently. If the player gets close, they run. They never fire first. The belt is their cover.

### 4. Ambush Trap
**Archetype:** `AMBUSHER` | **Algorithms:** Threat response (IGNORE until triggered), then wolfpack pincer
**Parameters:** group_size 3-6, aggression 1.0, detection 600m, default_response IGNORE → ATTACK
**Game context:** Ships that appear stationary or on patrol until the player enters a trigger radius. Then they all activate simultaneously and converge from multiple angles. The "bait" ship lures victims in.

---

## LAW ENFORCEMENT

### 5. Police Patrol
**Archetype:** `POLICE_PATROL` | **Algorithms:** V-formation, threat investigate
**Parameters:** group_size 2-4, aggression 0.5, V-form spacing 100m, detection 1200m
**Game context:** Two to four police ships in a clean V-formation, cruising through the belt. If the player fires or goes wanted, they investigate, then pursue. They call for backup (spawn more ships).

### 6. Police Strike Force
**Archetype:** `POLICE_STRIKE` | **Algorithms:** V-formation approach, pincer combat
**Parameters:** group_size 3-5, aggression 0.9, spacing 70m, speed 1.1×, pincer pattern
**Game context:** A tactical police response to a serious threat. Tight formation on approach, then splitting into pincer formation to box in the target. They don't shoot to kill — they shoot to disable.

### 7. Station Security
**Archetype:** `STATION_GUARD` | **Algorithms:** Sphere formation orbit, threat converge
**Parameters:** group_size 3-6, aggression 0.9, orbit spacing 200m, detection 800m, no flee
**Game context:** Ships orbiting the station in a spherical patrol pattern. When a threat appears, they break orbit and converge. They always return to their orbit positions afterward. The station is their home — they never flee.

### 8. Border Checkpoint
**Archetype:** `POLICE_PATROL` (modified) | **Algorithms:** Line formation, hold position
**Parameters:** group_size 2-3, formation LINE, spacing 200m, detection 1500m, aggression 0.3
**Game context:** Two police ships holding a stationary line across a flight corridor. They scan passing ships and hail those without clearance. Low aggression — they investigate, not attack.

---

## SWARMS & ALIENS

### 9. Basic Boid Swarm
**Archetype:** `BASIC_SWARM` | **Algorithms:** Boid flocking (separation + alignment + cohesion)
**Parameters:** group_size 6-15, boids=true, swarm=true, speed 0.8×, flee_range 80m
**Game context:** A cloud of small ships moving as one organism. No individual intelligence — they follow local rules and produce emergent flocking behaviour. Visually hypnotic, dangerous in numbers.

### 10. Eldritch Horror Swarm
**Archetype:** `ELDRITCH_SWARM` | **Algorithms:** Boid flocking + swarm CA + impossible orbit patterns
**Parameters:** group_size 8-25, boids=true, swarm=true, speed 1.2×, no flee, aggression 0.6
**Game context:** Alien ships that move in patterns that feel wrong — they orbit points that don't exist, swarm in shapes that suggest intelligence, and attack with coordinated precision that feels ancient. The "eldritch" tag triggers unique visual effects (pulsing glow, unnatural colours).

### 11. Alien Drone Cloud
**Archetype:** `ALIEN_DRONE` | **Algorithms:** Boid flocking, fast scatter-attack
**Parameters:** group_size 4-12, boids=true, speed 1.4×, detection 400m, aggression 0.5
**Game context:** Tiny, fast alien ships that swarm like insects. They investigate curiously, then attack in a coordinated wave. When they flee, they scatter in all directions like startled birds. Individual drones are weak; the cloud is the threat.

### 12. Swarm Consciousness
**Archetype:** `ELDRITCH_SWARM` (modified) | **Algorithms:** Swarm CA with hierarchical rules
**Parameters:** group_size 15-30, swarm=true, boids=true, formation SPHERE, spacing 30m
**Game context:** A massive swarm that behaves as a single entity. Individual ships are cells in a larger organism. The swarm moves slowly but purposefully. Destroying individual ships doesn't affect the group — new ones fill the gaps. Only destroying the "queen" (a slightly larger ship at the centre) breaks the swarm.

---

## MILITARY & TACTICAL

### 13. Military Patrol
**Archetype:** `MILITARY_SQUAD` | **Algorithms:** V-formation, leapfrog advance
**Parameters:** group_size 3-6, V-form spacing 90m, aggression 0.8, pincer combat, no flee
**Game context:** A disciplined military unit on patrol. Tight V-formation, coordinated turns. When they engage, they use leapfrog tactics — half advance while half provide covering fire. They don't break formation under fire.

### 14. Strike Team Insertion
**Archetype:** `STRIKE_TEAM` | **Algorithms:** Tight V-form approach, pincer attack
**Parameters:** group_size 2-4, spacing 60m, aggression 0.95, speed 1.1×, pincer
**Game context:** A small, elite unit approaching a target with precision. They arrive in tight formation, then split into two groups for a pincer attack. Fast, lethal, coordinated. The most dangerous small-group encounter.

### 15. Honor Guard
**Archetype:** `HONOR_GUARD` | **Algorithms:** Sphere formation around a VIP, suicidal defense
**Parameters:** group_size 4-8, spacing 80m, aggression 1.0, no flee, encircle combat
**Game context:** Ships surrounding a capital ship or VIP. They maintain sphere formation at all times. When attacked, they don't chase — they hold position and fire at anything that comes within range. They fight to the death.

### 16. Defense Grid
**Archetype:** `DEFENSE_GRID` | **Algorithms:** Fixed-position sphere, fire on anything in range
**Parameters:** group_size 4-8, spacing 150m, speed 0 (stationary), aggression 1.0, detection 1000m
**Game context:** Automated defense platforms in fixed positions around a station or planet. They don't move — they just shoot. The player has to navigate between them. Classic "run the gauntlet" encounter.

### 17. Emergency Response
**Archetype:** `EMERGENCY_RESPONSE` | **Algorithms:** V-form fast approach, investigate then defend
**Parameters:** group_size 2-4, speed 1.4×, detection 2000m, aggression 0.6, V-form spacing 80m
**Game context:** Fast response ships that converge on distress signals or combat zones. They arrive quickly in formation, assess the situation, and either help (if friendly) or engage (if hostile). They're the "reinforcements" that arrive mid-fight.

---

## CIVILIANS & TRADERS

### 18. Trade Convoy
**Archetype:** `CONVOY_TRADER` | **Algorithms:** Line formation, follow leader, flee from threats
**Parameters:** group_size 2-4, LINE formation, spacing 150m, aggression 0.1, speed 0.85×, flee_range 400m
**Game context:** Slow cargo ships in a line, following a lead vessel. They're fat, slow, and valuable. Pirates attack them; the player can protect them for reputation. They boost away from danger but can't fight effectively.

### 19. Mining Operation
**Archetype:** `MINING_CREW` | **Algorithms:** Scatter formation around asteroids, orbit mining points
**Parameters:** group_size 2-4, spacing 100m, aggression 0.05, speed 0.7×, no boost, flee 300m
**Game context:** Slow ships clustered around asteroids, methodically mining. They don't fight — they flee. But they're near valuable resources, so the player might protect them or compete for the same rocks.

### 20. Research Expedition
**Archetype:** `RESEARCH_GROUP` | **Algorithms:** Scatter formation, investigate anomalies, flee from combat
**Parameters:** group_size 1-3, spacing 150m, aggression 0.0, speed 0.75×, detection 1200m, flee 400m
**Game context:** Slow, curious ships that investigate anomalies and signals. They scan everything, communicate findings, and flee from any threat. They might discover something valuable — or something dangerous.

### 21. Migration Fleet
**Archetype:** `MIGRATION_FLEET` | **Algorithms:** Trail formation, directional movement, avoid all combat
**Parameters:** group_size 6-15, TRAIL formation, spacing 200m, aggression 0.0, speed 0.6×, flee 600m
**Game context:** A large group of civilian ships moving slowly in one direction. They're going somewhere specific and they don't want trouble. The player can escort them, attack them, or just watch them pass. They're a living part of the world.

### 22. Scavenger Gang
**Archetype:** `SCAVENGERS` | **Algorithms:** Scatter formation, orbit wreckage, flee from living ships
**Parameters:** group_size 2-5, spacing 80m, aggression 0.1, speed 0.8×, no boost, flee 300m
**Game context:** Ships circling wreckage or debris fields, picking through salvage. They flee from anything alive and armed. If the player destroys a ship, the scavengers rush in to collect the pieces. They're opportunistic, not hostile.

---

## SPECIAL ENCOUNTERS

### 23. Bounty Hunter Posse
**Archetype:** `BOUNTY_HUNTER` | **Algorithms:** V-form pursuit, feint combat pattern
**Parameters:** group_size 2-3, spacing 70m, aggression 0.85, detection 1200m, speed 1.1×, feint
**Game context:** A small group of hunters tracking a specific target (could be the player, or an NPC). They coordinate pursuit, with some ships flanking while others drive the target toward an ambush. They're smart, aggressive, and well-equipped.

### 24. Derelict Patrol
**Archetype:** `DERELICT_PATROL` | **Algorithms:** Trail formation, pre-programmed patrol routes
**Parameters:** group_size 1-3, TRAIL formation, spacing 60m, speed 0.5×, no boost, aggression 0.3
**Game context:** Ghost ships moving in slow, predictable patterns. They follow ancient patrol routes, occasionally firing at anything that crosses their path. They're not intelligent — they're running on autopilot. Destroying them is easy; understanding why they're still moving is the mystery.

### 25. Distress Signal Bait
**Archetype:** `AMBUSHER` (modified) | **Algorithms:** Fake distress signal → ambush on approach
**Parameters:** group_size 3-5, detection 600m, aggression 1.0, default_response IGNORE → ATTACK, feint
**Game context:** A ship broadcasting a distress signal. When the player approaches to help, the signal stops and hidden ships emerge from behind asteroids. The "distress" ship joins the attack. A classic trap that rewards caution.

### 26. Cult Orbital Ritual
**Archetype:** `CULT_ORBITAL` | **Algorithms:** Sphere orbit around a sacred point, aggressive when approached
**Parameters:** group_size 3-8, SPHERE formation, spacing 60m, speed 0.85×, aggression 0.7, no flee
**Game context:** Ships orbiting a point in space — maybe an artifact, a beacon, or nothing visible at all. They move in precise, ritualistic patterns. Approach too close and they attack as a group. They're fanatical and won't retreat.

### 27. Patrol Drone Grid
**Archetype:** `PATROL_DRONE` | **Algorithms:** Solo patrol route, investigate but don't pursue
**Parameters:** group_size 1, detection 500m, aggression 0.4, speed 0.9×, no boost
**Game context:** Single autonomous drones following patrol routes through the belt. They investigate anomalies but don't chase. They're the "eyes" of a larger force — destroy one and more might come. They're a reconnaissance network, not a combat force.

### 28. Experiment Drones
**Archetype:** `EXPERIMENT_DRONE` | **Algorithms:** Boid flocking, erratic movement, test attack patterns
**Parameters:** group_size 3-8, boids=true, speed 1.3×, aggression 0.5, detection 500m
**Game context:** Drones that seem to be testing the player's responses. They approach in different formations, attack with varying patterns, and retreat to observe. They're learning. Each encounter is slightly different from the last. They adapt.

### 29. Deep Space Anomaly
**Archetype:** `ANOMALY` | **Algorithms:** Impossible movement patterns, distorts nearby ships
**Parameters:** group_size 1, speed 2.0×, detection 2000m, aggression 0.0, no flee
**Game context:** A single entity that moves in ways that shouldn't be possible — it's in one place, then suddenly somewhere else. It doesn't attack, but its presence distorts nearby ships' controls. The player can't fight it — they can only observe and survive. It's the beginning of a larger mystery.

### 30. Escort Detail
**Archetype:** `ESCORT_GROUP` | **Algorithms:** Sphere formation around VIP, proportional threat response
**Parameters:** group_size 2-4, SPHERE formation, spacing 100m, aggression 0.7, encircle combat
**Game context:** Ships surrounding a VIP (a trader, a diplomat, a prisoner transport). They maintain sphere formation and react proportionally to threats — a single ship gets a warning; an attack gets a coordinated response. They're professional, not fanatical.

---

## Tuning Guide

### How to adjust group behaviour

| Parameter | What it controls | Range |
|-----------|-----------------|-------|
| `group_size_min/max` | How many ships in a group | 1-30 |
| `detection_range` | When the group notices the player | 200-2000m |
| `flee_range` | When the group runs | 0 (never) - 600m |
| `aggression` | How quickly they attack | 0.0 (pacifist) - 1.0 (always) |
| `group_mode` | Formation shape | V_FORM, LINE, SPHERE, SCATTER, TRAIL, ZIPPER |
| `formation_spacing` | Distance between ships | 30-200m |
| `combat_pattern` | How they fight | 0 (encircle), 1 (pincer), 2 (feint) |
| `default_response` | Group reaction to threats | IGNORE, INVESTIGATE, FLEE, ATTACK, DEFEND |
| `use_boids` | Enable flocking | true/false |
| `use_swarm` | Enable swarm CA | true/false |
| `speed_mult` | Speed modifier | 0.5-2.0 |
| `can_boost` | Can use boost | true/false |

### How to add a new use case

1. Pick an existing archetype or create a new one in `ai_factions.gd`
2. Set the parameters in `_apply_defaults()`
3. Add the archetype to `random_archetype()` weighted table (or spawn it programmatically)
4. The behaviour system handles the rest — no new code needed

### How algorithms compose

The behaviour system blends forces in this order:
1. **Individual state machine** (CRUISE, PATROL, etc.) → base steering
2. **Boid flocking** → group cohesion/alignment/separation
3. **Swarm CA** → emergent local patterns
4. **Formation offset** → maintain position relative to group centre
5. **Threat response** → group-level reaction to the player
6. **Wolfpack pursuit** → coordinated attack manoeuvres
7. **Orbit** → circle a point at fixed radius

Each force is weighted by the archetype's parameters. The blend is done in `AiBehaviour._compute_group_force()`. Adding a new algorithm means adding one static func to `AiGroupBehaviour` and one blend call in `_compute_group_force`.
