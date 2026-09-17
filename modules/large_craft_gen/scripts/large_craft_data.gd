## A complete, saveable large-craft generation recipe: seed + every
## [constant LargeCraftGenerator.RANDOMIZABLE] dial's value and lock state.
## Same "saveable as a .tres resource" shape as [SolarSystemData] — this is
## the bridge a future spawn-menu consumer reads to hand a recipe to a fresh
## [LargeCraftGenerator] without the lab scene in the loop, exactly how
## [SolarSystemData] hands systems to [FlightRoot]'s GENERATED_SYSTEM path.
class_name LargeCraftData
extends Resource

const FORMAT_VERSION := 1
const CRAFT_DIR := "res://data/large_craft"
const INDEX_PATH := "res://data/large_craft/index.json"

@export var craft_seed: int = 0
## Not part of [constant LargeCraftGenerator.RANDOMIZABLE] (it's a shape
## selector, not a dial) so it needs its own field — without it, loading a
## saved ring-station recipe would silently apply its dials to whatever
## archetype the generator currently happens to be set to.
@export var archetype: int = LargeCraftGenerator.Archetype.MOTHERSHIP
## Snapshot of every [constant LargeCraftGenerator.RANDOMIZABLE] key's value.
@export var params: Dictionary = {}
@export var locked: Dictionary = {}
@export var display_name: String = ""


static func from_generator(gen: LargeCraftGenerator, craft_name: String = "") -> LargeCraftData:
	var data := LargeCraftData.new()
	data.craft_seed = gen.craft_seed
	data.archetype = gen.archetype
	data.locked = gen.locked.duplicate()
	data.display_name = craft_name if craft_name != "" else "craft_%d" % gen.craft_seed
	for schema_entry in LargeCraftGenerator.RANDOMIZABLE:
		var key: String = schema_entry["key"]
		data.params[key] = gen.get(key)
	return data


## Copies every recorded field onto [param gen] without generating — for a
## generator that has not entered the tree yet (its own [method Node._ready]
## generates once it does).
func apply_params(gen: LargeCraftGenerator) -> void:
	gen.craft_seed = craft_seed
	gen.archetype = archetype
	gen.locked = locked.duplicate()
	for key: String in params.keys():
		gen.set(key, params[key])


## For a generator already live and in the tree: apply params, then regenerate.
func apply_to(gen: LargeCraftGenerator) -> void:
	apply_params(gen)
	gen.generate()


# --- Disk -----------------------------------------------------------------

static func can_write() -> bool:
	return OS.has_feature("editor")


## Writes this recipe to res://data/large_craft/<slug>.tres. Returns
## {"ok": bool, "path": String, "error": String}, same contract as
## [method SolarSystemData.save_to_disk].
func save_to_disk() -> Dictionary:
	if not LargeCraftData.can_write():
		return {
			"ok": false, "path": "",
			"error": "large craft can only be saved from a dev run — res:// is read-only in an exported build",
		}
	var id := _slug(display_name if display_name != "" else "craft_%d" % craft_seed)
	var path := CRAFT_DIR + "/" + id + ".tres"
	var err := DirAccess.make_dir_recursive_absolute(CRAFT_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": path, "error": "could not create %s (%d)" % [CRAFT_DIR, err]}
	err = ResourceSaver.save(self, path)
	if err != OK:
		return {"ok": false, "path": path, "error": "could not write %s (%d)" % [path, err]}
	_write_index()
	return {"ok": true, "path": path, "error": ""}


static func load_from_disk(id: String) -> LargeCraftData:
	var path := CRAFT_DIR + "/" + id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as LargeCraftData


static func list_ids() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(CRAFT_DIR)
	if dir != null:
		for file_name in dir.get_files():
			var clean := file_name.trim_suffix(".remap")
			if clean.get_extension() == "tres":
				found.append(clean.get_basename())
	if found.is_empty() and FileAccess.file_exists(INDEX_PATH):
		var text := FileAccess.get_file_as_string(INDEX_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var listed: Variant = (parsed as Dictionary).get("craft", [])
			if listed is Array:
				for item: Variant in listed:
					found.append(String(item).get_basename())
	found.sort()
	return found


static func _write_index() -> void:
	var dir := DirAccess.open(CRAFT_DIR)
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
	file.store_string(JSON.stringify({"format": FORMAT_VERSION, "craft": files}, "  ") + "\n")
	file.close()


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
	return out if out != "" else "craft"
