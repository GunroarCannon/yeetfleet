## ModuleRegistry: the single answer to "which scene does module X boot into?"
##
## Before this existed, every scene root carried its own hardcoded scene path —
## [ArenaRoot] had two consts, [BuilderRoot] one, [FlightRoot] a raw string in
## two places — so adding a module meant editing every neighbour that wanted to
## reach it. This is the one place that knowledge lives. A module that wants to
## leave for another looks the id up here; nothing else in the codebase names a
## `res://modules/...` scene except the launcher and this file.
##
## The entries are also the data the launcher's picker renders, so the registry
## is read in two very different places — a picker needs a display name and a
## one-line description; a [FlightRoot] "go to arena" button needs only the path.
class_name ModuleRegistry
extends RefCounted

## One entry per bootable module, in picker order. Add a module here and both
## the launcher and every nav button learn about it; forget to and it is simply
## unreachable, which is a feature.
const MODULES: Array[Dictionary] = [
	{
		"id": "menu",
		"name": "Yeetfleet",
		"scene": "res://modules/menu/menu.tscn",
		"tagline": "The game: home screen, campaign map, garage and shop.",
	},
	{
		"id": "ship_builder",
		"name": "Ship Builder",
		"scene": "res://modules/ship_builder/ship_builder.tscn",
		"tagline": "Design ships part by part — sockets, mirroring, stats, paint.",
	},
	{
		"id": "flight",
		"name": "Test Flight",
		"scene": "res://modules/flight/flight_test.tscn",
		"tagline": "Fly your build — 6DOF flight, gravity, AI traffic, combat.",
	},
	{
		"id": "runner",
		"name": "Endless Run",
		"scene": "res://modules/runner/runner.tscn",
		"tagline": "The flight test as an endless runner — dodge, thread rings, ram, go faster.",
	},
	{
		"id": "arena",
		"name": "AI Arena",
		"scene": "res://modules/arena/arena.tscn",
		"tagline": "Watch factions fight, or take a ship over and fly it yourself.",
	},
	{
		"id": "physics_lab",
		"name": "Physics Lab",
		"scene": "res://modules/physics_lab/physics_lab.tscn",
		"tagline": "A/B collision tuning bench: impulse, restitution, spin, hitstop.",
	},
	{
		"id": "style_lab",
		"name": "Style Lab",
		"scene": "res://modules/style_lab/style_lab.tscn",
		"tagline": "Global look toggle & dials: grounded vs friendly, rounding, palettes.",
	},
	{
		"id": "solar_system_gen",
		"name": "Solar System Lab",
		"scene": "res://modules/solar_system_gen/solar_system_gen_lab.tscn",
		"tagline": "Procedural stellar systems: stars, planets, moons, asteroid belts.",
	},
	{
		"id": "large_craft_gen",
		"name": "Large Craft Lab",
		"scene": "res://modules/large_craft_gen/large_craft_gen_lab.tscn",
		"tagline": "Modular capital ships, carriers, stations, and docking pads.",
	},
	{
		"id": "destruction_lab",
		"name": "Destruction & Effects Lab",
		"scene": "res://modules/destruction_lab/destruction_lab.tscn",
		"tagline": "Explosion & destruction testbed — spawn targets, click & trigger blast waves, impacts, shatter.",
	},
]


## Every module id in picker order. The launcher and the smoke test both iterate
## this rather than [member MODULES] directly, so order stays a single fact.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for m in MODULES:
		out.append(String(m.get("id", "")))
	return out


## The scene path for a module id, or "" when the id is unknown. Callers that
## hand ids from code (a nav button) can rely on a non-empty result; callers
## that hand user input (the launcher) must treat "" as "no such module".
static func scene_path(id: String) -> String:
	for m in MODULES:
		if String(m.get("id", "")) == id:
			return String(m.get("scene", ""))
	return ""


## Display name for a module id, or the id itself when unknown, so a picker can
## degrade to something readable instead of a blank row.
static func display_name(id: String) -> String:
	for m in MODULES:
		if String(m.get("id", "")) == id:
			return String(m.get("name", id))
	return id


## One-line description for the picker, or "" when unknown.
static func tagline(id: String) -> String:
	for m in MODULES:
		if String(m.get("id", "")) == id:
			return String(m.get("tagline", ""))
	return ""


## Whether an id names a real, bootable module.
static func has(id: String) -> bool:
	return scene_path(id) != ""
