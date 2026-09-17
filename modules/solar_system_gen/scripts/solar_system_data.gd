## A complete, saveable solar-system generation recipe: seed, every
## [constant SolarSystemGenerator.RANDOMIZABLE] dial's value + lock state, and
## the belts manually placed on top of generation. Pure data, no scene
## references — the same "saveable as a .tres resource" pattern as
## [PlanetData]/[ShipDesign].
##
## Auto-spawned belts ([member SolarSystemGenerator.planet_belt_chance] /
## [member SolarSystemGenerator.wide_belt_chance]) already reproduce
## deterministically from [member system_seed] + [member params], so only
## manually placed ones ([SolarSystemGenLabRoot]'s "Spawn belt" buttons) need
## recording — see [member manual_belts].
##
## Deliberately its own tiny library too (see [method save_to_disk] / [method
## load_from_disk] / [method list_ids]) rather than a separate class the way
## [PlanetLibrary] is: the solar_system_gen lab is the only reader/writer, so
## a second class purely for directory bookkeeping isn't worth it here.
##
## [b]Module note:[/b] this class (and [SolarSystemGenerator] itself) is
## deliberately allowed to be referenced from [code]modules/flight[/code]
## (see [constant FlightRoot.Location] value GENERATED_SYSTEM) even though
## solar_system_gen otherwise sits above flight in this project's module
## layering — neither this class nor [SolarSystemGenerator] depends on
## flight (only [SolarSystemGenLabRoot], the lab UI, does), so this stays a
## one-directional dependency, not a cycle.
class_name SolarSystemData
extends Resource

const FORMAT_VERSION := 1
const SYSTEMS_DIR := "res://data/systems"
const INDEX_PATH := "res://data/systems/index.json"

@export var system_seed: int = 0
@export var distance_scale: float = 1.0
@export var time_scale: float = 1.0
## Snapshot of every [constant SolarSystemGenerator.RANDOMIZABLE] key's value
## at save time.
@export var params: Dictionary = {}
## Snapshot of [member SolarSystemGenerator.locked].
@export var locked: Dictionary = {}
## {center_name, ring_radius, count, thickness} per manually-placed belt.
@export var manual_belts: Array[Dictionary] = []
@export var display_name: String = ""


## Captures [param gen]'s full recipe.
static func from_generator(gen: SolarSystemGenerator, name: String = "") -> SolarSystemData:
	var data := SolarSystemData.new()
	data.system_seed = gen.system_seed
	data.distance_scale = gen.distance_scale
	data.time_scale = gen.time_scale
	data.locked = gen.locked.duplicate()
	data.display_name = name if name != "" else "system_%d" % gen.system_seed
	for schema_entry in SolarSystemGenerator.RANDOMIZABLE:
		var key: String = schema_entry["key"]
		data.params[key] = gen.get(key)
	for belt: Dictionary in gen.belts:
		if bool(belt.get("manual", false)):
			data.manual_belts.append({
				"center_name": belt.get("center_name", ""),
				"ring_radius": belt["ring_radius"], "count": belt["count"], "thickness": belt["thickness"],
			})
	return data


## Copies every recorded field onto [param gen] without generating — for a
## generator that has not entered the tree yet (its own [method Node._ready]
## auto-generates once it does; see [FlightRoot._build_generated_system]).
func apply_params(gen: SolarSystemGenerator) -> void:
	gen.system_seed = system_seed
	gen.distance_scale = distance_scale
	gen.time_scale = time_scale
	gen.locked = locked.duplicate()
	for key: String in params.keys():
		gen.set(key, params[key])


## Replays every [member manual_belts] entry onto [param gen] — call once
## [param gen] has already generated once.
func spawn_manual_belts(gen: SolarSystemGenerator) -> void:
	for belt: Dictionary in manual_belts:
		gen.spawn_asteroid_belt(
			Vector3.ZERO, float(belt["ring_radius"]), int(belt["count"]), float(belt["thickness"]),
			String(belt.get("center_name", "")), true
		)


## For a generator that is already live and in the tree (the lab's own "Load
## system" button): apply params, regenerate explicitly, then replay belts.
func apply_to(gen: SolarSystemGenerator) -> void:
	apply_params(gen)
	gen.generate_system()
	spawn_manual_belts(gen)


# --- Disk -----------------------------------------------------------------

## True while systems can be written, i.e. while res:// is a real directory —
## same constraint [PlanetLibrary.can_write] documents.
static func can_write() -> bool:
	return OS.has_feature("editor")


## Writes this recipe to res://data/systems/<slug>.tres. Returns
## {"ok": bool, "path": String, "error": String} — a caller wants the reason
## in front of whoever pressed Save, not just a bool.
func save_to_disk() -> Dictionary:
	if not SolarSystemData.can_write():
		return {
			"ok": false, "path": "",
			"error": "systems can only be saved from a dev run — res:// is read-only in an exported build",
		}
	var id := _slug(display_name if display_name != "" else "system_%d" % system_seed)
	var path := SYSTEMS_DIR + "/" + id + ".tres"
	var err := DirAccess.make_dir_recursive_absolute(SYSTEMS_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": path, "error": "could not create %s (%d)" % [SYSTEMS_DIR, err]}
	err = ResourceSaver.save(self, path)
	if err != OK:
		return {"ok": false, "path": path, "error": "could not write %s (%d)" % [path, err]}
	_write_index()
	return {"ok": true, "path": path, "error": ""}


static func load_from_disk(id: String) -> SolarSystemData:
	var path := SYSTEMS_DIR + "/" + id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SolarSystemData


## Ids of every saved system (filename without extension) — directory
## listing with an index.json fallback for exported builds, same shape as
## [method PlanetLibrary._list_files].
static func list_ids() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(SYSTEMS_DIR)
	if dir != null:
		for file_name in dir.get_files():
			var clean := file_name.trim_suffix(".remap")
			if clean.get_extension() == "tres":
				found.append(clean.get_basename())
	if found.is_empty() and FileAccess.file_exists(INDEX_PATH):
		var text := FileAccess.get_file_as_string(INDEX_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var listed: Variant = (parsed as Dictionary).get("systems", [])
			if listed is Array:
				for item: Variant in listed:
					found.append(String(item).get_basename())
	found.sort()
	return found


static func _write_index() -> void:
	var dir := DirAccess.open(SYSTEMS_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	for file_name in dir.get_files():
		if file_name.get_extension() == "tres":
			files.append(file_name)
	files.sort()
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"format": FORMAT_VERSION, "systems": files}, "  ") + "\n")
	file.close()


## Filename-safe id from a display name — same rule [PlanetLibrary.slug] uses.
static func _slug(display: String) -> String:
	var out := ""
	var last_was_sep := true
	for i in display.length():
		var c := display[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			last_was_sep = false
		elif not last_was_sep:
			out += "_"
			last_was_sep = true
	out = out.trim_suffix("_")
	return out if out != "" else "system"
