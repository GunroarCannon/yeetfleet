## Loads and saves planets as reusable game content in [constant PLANETS_DIR].
##
## Planets made in the editor are content, not scratch: the flight scene has to be
## able to fly past one, and a second planet should be a file somebody adds rather
## than code somebody writes. So they live in the project folder as [PlanetData]
## .tres resources, next to the ship parts in res://data, and both the editor and
## [SpaceScene] read them through here.
##
## Same shape as [PartLibrary] deliberately — a cached singleton, a directory scan
## with a manifest fallback for exported builds, and problems collected in
## [member load_errors] rather than thrown, so one bad file does not take the
## flight scene down with it.
##
## [b]Writing[/b] only works while res:// is a real directory, which means the
## editor and tool runs. An exported build cannot write into its own .pck, so
## [method save] reports that plainly instead of failing silently — see
## [method can_write]. Reading works everywhere, which is the direction that
## matters at runtime.
class_name PlanetLibrary
extends RefCounted

const PLANETS_DIR := "res://data/planets"
## Enumeration fallback: exported builds cannot always list a directory, so every
## save also rewrites this index of the files that exist.
const INDEX_PATH := "res://data/planets/index.json"
const INDEX_FORMAT := 1

## Planets shipped with the project. The index file is authoritative once it
## exists; this covers a fresh checkout where it does not.
const BUNDLED: Array[String] = [
	"tarn_iv.tres",
	"tarn_iv_moon.tres",
]

static var _instance: PlanetLibrary = null

## id -> {"id": String, "name": String, "path": String, "data": PlanetData}
var entries: Dictionary = {}
## Human-readable content problems found while loading.
var load_errors: Array[String] = []


static func instance() -> PlanetLibrary:
	if _instance == null:
		_instance = PlanetLibrary.new()
		_instance.load_all()
	return _instance


## Drop the cached library, so a planet saved this session is picked up by the
## next read. Called by the editor after every save.
static func reset() -> void:
	_instance = null


func load_all() -> void:
	entries.clear()
	load_errors.clear()
	for file_name in _list_files():
		var path := PLANETS_DIR + "/" + file_name
		var res: Resource = load(path) if ResourceLoader.exists(path) else null
		var data := res as PlanetData
		if data == null:
			load_errors.append("%s is not a PlanetData resource" % path)
			continue
		var id := file_name.get_basename()
		entries[id] = {
			"id": id,
			"name": data.planet_name if data.planet_name.strip_edges() != "" else id,
			"path": path,
			"data": data,
		}


## Ids of every planet on disk, in display-name order — what a load list shows.
func ids() -> Array[String]:
	var sorted: Array[String] = []
	for id: String in entries.keys():
		sorted.append(id)
	sorted.sort_custom(func(a: String, b: String) -> bool:
		return String(entries[a]["name"]).naturalnocasecmp_to(String(entries[b]["name"])) < 0
	)
	return sorted


func has_id(id: String) -> bool:
	return entries.has(id)


## Display name for a planet, or the id if it has none.
func name_of(id: String) -> String:
	if not entries.has(id):
		return id
	return String(entries[id]["name"])


## A planet ready to be edited or configured into a [Planet].
##
## Always a copy. [method load] caches resources engine-wide, so handing out the
## cached instance would let the editor's sliders quietly rewrite the library's
## idea of what is on disk — and let two planets in the flight scene share one
## radius.
func get_data(id: String) -> PlanetData:
	if not entries.has(id):
		return null
	var data := entries[id]["data"] as PlanetData
	if data == null:
		return null
	return data.duplicate(true) as PlanetData


## True while planets can be written, i.e. while res:// is a real directory. An
## exported build's res:// lives inside the .pck and is read-only.
static func can_write() -> bool:
	return OS.has_feature("editor")


## Write a planet into the project folder. Returns
## [code]{"ok": bool, "id": String, "path": String, "error": String}[/code] —
## a dictionary rather than an error code because every caller wants to put the
## reason in front of the person who pressed Save.
func save(data: PlanetData) -> Dictionary:
	if data == null:
		return {"ok": false, "id": "", "path": "", "error": "nothing to save"}
	if not can_write():
		return {
			"ok": false, "id": "", "path": "",
			"error": "planets can only be saved from a dev run — res:// is read-only in an exported build",
		}
	var id := slug(data.planet_name)
	var path := PLANETS_DIR + "/" + id + ".tres"
	var err := DirAccess.make_dir_recursive_absolute(PLANETS_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "id": id, "path": path, "error": "could not create %s (%d)" % [PLANETS_DIR, err]}
	# Saved as a copy: the editor keeps editing its own resource after this, and a
	# saved file that keeps changing under the library is not a saved file.
	err = ResourceSaver.save(data.duplicate(true), path)
	if err != OK:
		return {"ok": false, "id": id, "path": path, "error": "could not write %s (%d)" % [path, err]}
	# The cache is stale the moment a file appears, and the index has to grow with
	# it or an exported build will not see the new planet.
	reset()
	_write_index()
	return {"ok": true, "id": id, "path": path, "error": ""}


## Filename-safe id from a display name. Lowercase, words joined by underscores,
## so "Tarn IV" and "tarn iv" are the same planet and saving twice overwrites
## rather than littering.
static func slug(display_name: String) -> String:
	var out := ""
	var last_was_sep := true
	for i in display_name.length():
		var c := display_name[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			last_was_sep = false
		elif not last_was_sep:
			out += "_"
			last_was_sep = true
	out = out.trim_suffix("_")
	return out if out != "" else "planet"


# --- Disk -----------------------------------------------------------------

## Directory listing, falling back to the index and then to the bundled list.
## Tolerant of the ".remap" suffix Godot adds to exported resources.
func _list_files() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(PLANETS_DIR)
	if dir != null:
		for file_name in dir.get_files():
			var clean := file_name.trim_suffix(".remap")
			if clean.get_extension() == "tres" or clean.get_extension() == "res":
				found.append(clean)
	if not found.is_empty():
		return found
	for file_name in _index_files():
		found.append(file_name)
	if not found.is_empty():
		return found
	for file_name in BUNDLED:
		if ResourceLoader.exists(PLANETS_DIR + "/" + file_name):
			found.append(file_name)
	return found


func _index_files() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(INDEX_PATH):
		return out
	var text := FileAccess.get_file_as_string(INDEX_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		load_errors.append("%s is not valid JSON" % INDEX_PATH)
		return out
	var listed: Variant = (parsed as Dictionary).get("planets", [])
	if listed is Array:
		for item: Variant in listed:
			var file_name := String(item)
			if ResourceLoader.exists(PLANETS_DIR + "/" + file_name):
				out.append(file_name)
	return out


func _write_index() -> void:
	var dir := DirAccess.open(PLANETS_DIR)
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
	file.store_string(JSON.stringify({"format": INDEX_FORMAT, "planets": files}, "  ") + "\n")
	file.close()
