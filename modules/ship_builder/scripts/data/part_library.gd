## Loads and indexes all ship content from JSON on disk.
##
## Content lives as plain JSON rather than .tres so that it is hand-editable,
## diffable, and addable without touching code — the data-driven requirement from
## the design doc. Files are validated on load and problems are collected in
## [member load_errors] instead of crashing, so a typo in one part does not take
## the whole builder down.
class_name PartLibrary
extends RefCounted

const PARTS_DIR := "res://data/parts"
const PRESETS_DIR := "res://data/presets"
const FACTIONS_PATH := "res://data/factions.json"

## Exported builds cannot always enumerate directories, so directory scanning
## falls back to this manifest. Keep it in step when adding a parts file.
const PARTS_MANIFEST: Array[String] = [
	"chassis.json",
	"cockpits.json",
	"engines.json",
	"weapons.json",
	"cargo.json",
	"wings.json",
	"armor.json",
	"greebles.json",
]

const PRESETS_MANIFEST: Array[String] = ["ship_families.json"]

static var _instance: PartLibrary = null

## id -> ShipPart
var parts: Dictionary = {}
## category -> Array[ShipPart], in file order
var by_category: Dictionary = {}
## Faction colour/decal presets, as loaded.
var factions: Array[Dictionary] = []
## Preset ships (chassis + default loadout), as loaded.
var presets: Array[Dictionary] = []
## Human-readable content problems found while loading.
var load_errors: Array[String] = []


static func instance() -> PartLibrary:
	if _instance == null:
		_instance = PartLibrary.new()
		_instance.load_all()
	return _instance


## Drop the cached library. Used by the test harness reload button so content can
## be edited and re-read without restarting.
static func reset() -> void:
	_instance = null


func load_all() -> void:
	parts.clear()
	by_category.clear()
	factions.clear()
	presets.clear()
	load_errors.clear()
	for category in ShipPart.CATEGORIES:
		by_category[category] = [] as Array[ShipPart]

	for file_name in _list_json(PARTS_DIR, PARTS_MANIFEST):
		_load_parts_file(PARTS_DIR + "/" + file_name)
	for file_name in _list_json(PRESETS_DIR, PRESETS_MANIFEST):
		_load_presets_file(PRESETS_DIR + "/" + file_name)
	_load_factions()


## Directory listing with a manifest fallback, tolerant of the ".remap" suffix
## Godot adds to exported resources.
func _list_json(dir_path: String, manifest: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for file_name in dir.get_files():
			var clean := file_name.trim_suffix(".remap")
			if clean.get_extension().to_lower() == "json" and not found.has(clean):
				found.append(clean)
	if found.is_empty():
		for file_name in manifest:
			if FileAccess.file_exists(dir_path + "/" + file_name):
				found.append(file_name)
	found.sort()
	return found


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("Missing file: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		load_errors.append("Empty file: " + path)
		return null
	var parser := JSON.new()
	if parser.parse(text) != OK:
		load_errors.append("%s line %d: %s" % [path.get_file(), parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


func _load_parts_file(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	if not data is Dictionary or not (data as Dictionary).has("parts"):
		load_errors.append(path.get_file() + ": expected an object with a 'parts' array.")
		return
	for entry: Variant in (data as Dictionary)["parts"]:
		if not entry is Dictionary:
			continue
		var part := ShipPart.from_dict(entry)
		_validate_part(part, path.get_file())
		if part.id.is_empty():
			load_errors.append(path.get_file() + ": a part is missing its id.")
			continue
		if parts.has(part.id):
			load_errors.append("Duplicate part id: " + part.id)
			continue
		parts[part.id] = part
		if not by_category.has(part.category):
			by_category[part.category] = [] as Array[ShipPart]
		(by_category[part.category] as Array[ShipPart]).append(part)


func _validate_part(part: ShipPart, file_name: String) -> void:
	if not ShipPart.CATEGORIES.has(part.category):
		load_errors.append("%s: part %s has unknown category %s" % [file_name, part.id, part.category])
	if not ShipPart.SIZE_CLASSES.has(part.size_class):
		load_errors.append("%s: part %s has unknown size class %s" % [file_name, part.id, part.size_class])
	for key: Variant in part.stats:
		if not ShipStats.STAT_KEYS.has(String(key)):
			load_errors.append("%s: part %s has unknown stat key %s" % [file_name, part.id, key])
	if part.mesh_spec.is_empty():
		load_errors.append("%s: part %s has no mesh spec" % [file_name, part.id])
	var seen: Array[String] = []
	for socket in part.sockets:
		if socket.id.is_empty():
			load_errors.append("%s: part %s has a socket with no id" % [file_name, part.id])
		elif seen.has(socket.id):
			load_errors.append("%s: part %s has duplicate socket %s" % [file_name, part.id, socket.id])
		else:
			seen.append(socket.id)
	# Mirror targets must exist, or a wing pair silently becomes a single wing.
	for socket in part.sockets:
		if socket.is_mirror() and part.get_socket(socket.mirror_of) == null:
			load_errors.append("%s: part %s socket %s mirrors missing socket %s" % [
				file_name, part.id, socket.id, socket.mirror_of
			])


func _load_presets_file(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	if not data is Dictionary:
		return
	for entry: Variant in (data as Dictionary).get("ships", []):
		if entry is Dictionary:
			presets.append(entry)


func _load_factions() -> void:
	var data: Variant = _read_json(FACTIONS_PATH)
	if data == null:
		return
	if not data is Dictionary:
		return
	for entry: Variant in (data as Dictionary).get("factions", []):
		if entry is Dictionary:
			factions.append(entry)


# --- Queries ---------------------------------------------------------------

func get_part(part_id: String) -> ShipPart:
	return parts.get(part_id, null) as ShipPart


func has_part(part_id: String) -> bool:
	return parts.has(part_id)


func parts_in_category(category: String) -> Array[ShipPart]:
	return by_category.get(category, [] as Array[ShipPart])


func chassis_list() -> Array[ShipPart]:
	return parts_in_category("chassis")


func count() -> int:
	return parts.size()


## Palette query: filter by category, size class and a free-text term matched
## against name, id, description and tags.
func filter_parts(category := "", size_class := "", search := "") -> Array[ShipPart]:
	var term := search.strip_edges().to_lower()
	var out: Array[ShipPart] = []
	var pool: Array[ShipPart] = []
	if category == "":
		for c in ShipPart.CATEGORIES:
			pool.append_array(parts_in_category(c))
	else:
		pool = parts_in_category(category)
	for part in pool:
		if size_class != "" and part.size_class != size_class:
			continue
		if term != "" and not _matches(part, term):
			continue
		out.append(part)
	return out


func _matches(part: ShipPart, term: String) -> bool:
	if part.display_name.to_lower().contains(term):
		return true
	if part.id.to_lower().contains(term):
		return true
	if part.description.to_lower().contains(term):
		return true
	for tag in part.tags:
		if tag.to_lower().contains(term):
			return true
	return false


## Parts that would fit a given socket, for the "fill this socket" flow where the
## player picks the socket first and is offered only valid parts.
func parts_for_socket(socket: PartSocket) -> Array[ShipPart]:
	var out: Array[ShipPart] = []
	for part_id: Variant in parts:
		var part := parts[part_id] as ShipPart
		if socket.accepts_part(part):
			out.append(part)
	out.sort_custom(func(a: ShipPart, b: ShipPart) -> bool: return a.display_name < b.display_name)
	return out


func get_faction(faction_id: String) -> Dictionary:
	for f in factions:
		if String(f.get("id", "")) == faction_id:
			return f
	return {}


func get_preset(preset_id: String) -> Dictionary:
	for p in presets:
		if String(p.get("id", "")) == preset_id:
			return p
	return {}


## Turn a preset entry into a live design. Presets are stored in the same shape
## as a saved design, so a ship family is just a shipped save file.
func build_preset_design(preset_id: String) -> ShipDesign:
	var preset := get_preset(preset_id)
	if preset.is_empty():
		return null
	var design := ShipDesign.from_dict(preset)
	if design == null or design.root == null:
		return null
	if design.faction_id != "":
		apply_faction(design, design.faction_id)
	return design


## Apply a faction colour set to a design, leaving per-part overrides intact.
func apply_faction(design: ShipDesign, faction_id: String) -> bool:
	var faction := get_faction(faction_id)
	if faction.is_empty():
		return false
	var cols: Dictionary = faction.get("palette", {})
	for channel: Variant in cols:
		design.set_color(String(channel), Color.from_string(String(cols[channel]), Color.MAGENTA))
	if faction.has("material"):
		design.material_preset = String(faction["material"])
	design.faction_id = faction_id
	return true


## A sensible starter ship: the first preset, or failing that the lightest
## chassis with its required sockets filled by the cheapest valid part. Keeps the
## harness usable even with an incomplete content set.
func default_design() -> ShipDesign:
	if not presets.is_empty():
		var d := build_preset_design(String(presets[0].get("id", "")))
		if d != null:
			return d
	var chassis := chassis_list()
	if chassis.is_empty():
		return null
	var design := ShipDesign.create(chassis[0].id)
	autofill_required(design)
	return design


## Fill every empty required socket with the cheapest part that fits. Used by the
## starter ship and by the "Autofill" button, so a player can never be stuck with
## an unflyable frame and no idea which socket is the problem.
func autofill_required(design: ShipDesign, max_passes := 6) -> int:
	var placed := 0
	for _pass in max_passes:
		var res := design.resolve(self)
		var filled_any := false
		for entry in res.open_sockets:
			var socket := entry["socket"] as PartSocket
			if not socket.required:
				continue
			var candidates := parts_for_socket(socket)
			if candidates.is_empty():
				continue
			var best: ShipPart = candidates[0]
			for c in candidates:
				if c.cost < best.cost:
					best = c
			if design.place_part(String(entry["path"]), best.id, self):
				placed += 1
				filled_any = true
		if not filled_any:
			break
	return placed
