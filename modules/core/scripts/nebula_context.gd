## NebulaContext: the shared state a scene root hands to every module it builds.
##
## This is the module-isolation contract made concrete (TECHNICAL_PLAN §0.1-0.2):
## a module never walks the tree looking for "the" gravity system or "the"
## events director — its constructor receives a context and reads what it needs
## off it. The scene root is the only thing that builds a context, and the only
## file where modules meet (their signals get wired there, never by calling each
## other).
##
## Fields may be null. The physics lab has no events and the style lab has no
## physics, so every module must run against a partially-filled context.
## Null-check, do not assume.
##
## The context is built once per scene reload, and seeds its [member rng] from
## [Session]'s run seed, so an F5 restart replays the same random stream —
## which is the whole basis of the "predictable rules" promise (§0.3).
class_name NebulaContext
extends RefCounted

## The one seeded source of randomness for this scene. Everything that rolls
## dice shares this instance; nobody calls `randomize()` anywhere else.
var rng := RandomNumberGenerator.new()

## The flight + orbit pinball table. The one module that exists today that a
## new module might legitimately want (gravity is off when the scene has no
## bodies, so null here means "no gravity", not "broken").
var gravity: GravitySystem = null

# The rest of the plan's modules attach their façade here as they land (M1/M3/
# M4/M5). Declared as comments until the classes exist, so this file parses on
# the day M0 ships:
#
#   var phys: PhysWorld          # modules/physics        (M1)
#   var style: StyleProfile      # modules/style          (M3)
#   var events: IncidentDirector # modules/events         (M4)
#   var reputation: RepStore     # modules/reputation     (M5)


func _init() -> void:
	# Seeded from the session rather than random: two F5 restarts of the same
	# run must behave identically, and a run started with --seed=<n> must be
	# reproducible from the number printed at boot.
	rng.seed = Session.seed
