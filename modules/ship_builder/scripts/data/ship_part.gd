## A single modular ship part: chassis, cockpit, engine, weapon, cargo, wing,
## armour plate or cosmetic greeble.
##
## Parts are pure data. They carry stat deltas, a procedural mesh recipe, the
## sockets they expose to further parts, and any functional payload the systems
## simulation needs (weapon damage, engine exhaust size, and so on). Nothing here
## knows about scenes, which is what keeps the module independently testable.
class_name ShipPart
extends Resource

const CATEGORIES: Array[String] = [
	"chassis", "cockpit", "engine", "weapon", "cargo", "wing", "armor", "greeble",
]

## Ordered smallest to largest. Socket size gates compare against this list.
const SIZE_CLASSES: Array[String] = ["fighter", "corvette", "hauler", "capital"]

## Human labels for the category tabs in the palette.
const CATEGORY_LABELS := {
	"chassis": "Hull / Chassis",
	"cockpit": "Cockpit / Bridge",
	"engine": "Engine / Thruster",
	"weapon": "Weapon Hardpoint",
	"cargo": "Cargo / Utility",
	"wing": "Wings / Fins",
	"armor": "Armour / Plating",
	"greeble": "Detail (cosmetic)",
}

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_enum("chassis", "cockpit", "engine", "weapon", "cargo", "wing", "armor", "greeble")
var category := "greeble"
@export_enum("fighter", "corvette", "hauler", "capital") var size_class := "fighter"

## Stat key -> delta. See [ShipStats.STAT_KEYS] for the vocabulary.
@export var stats: Dictionary = {}
## Recipe consumed by [PartMeshFactory]. `kind` picks the generator, the rest are
## that generator's parameters.
@export var mesh_spec: Dictionary = {}
## Attachment points this part offers to other parts.
@export var sockets: Array[PartSocket] = []
## Payload for the live systems simulation (damage, fire_rate, exhaust, ...).
@export var func_data: Dictionary = {}
## Free-form tags used by faction presets and future economy hooks.
@export var tags: Array[String] = []
@export var cost := 0

## Chassis-only: structural mass ceiling. Exceeding it is a validation warning
## rather than a hard block, so players can see the cost of overloading.
@export var mass_limit := 0.0


static func from_dict(d: Dictionary) -> ShipPart:
	var p := ShipPart.new()
	p.id = String(d.get("id", ""))
	p.display_name = String(d.get("name", p.id.capitalize()))
	p.description = String(d.get("desc", ""))
	p.category = String(d.get("category", "greeble"))
	p.size_class = String(d.get("size", "fighter"))
	p.cost = int(d.get("cost", 0))
	p.mass_limit = float(d.get("mass_limit", 0.0))
	p.mesh_spec = d.get("mesh", {}).duplicate(true)
	p.func_data = d.get("func", {}).duplicate(true)
	for t: Variant in d.get("tags", []):
		p.tags.append(String(t))
	var raw_stats: Dictionary = d.get("stats", {})
	for k: Variant in raw_stats:
		p.stats[String(k)] = float(raw_stats[k])
	for s: Variant in d.get("sockets", []):
		p.sockets.append(PartSocket.from_dict(s))
	return p


func get_socket(socket_id: String) -> PartSocket:
	for s in sockets:
		if s.id == socket_id:
			return s
	return null


## Sockets that hold their own content (i.e. excluding passive mirrors).
func primary_sockets() -> Array[PartSocket]:
	var out: Array[PartSocket] = []
	for s in sockets:
		if not s.is_mirror():
			out.append(s)
	return out


func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


func category_label() -> String:
	return CATEGORY_LABELS.get(category, category.capitalize())


func size_index() -> int:
	return SIZE_CLASSES.find(size_class)


## Cosmetic parts are exempt from stat budgets, per the design doc's "pure
## expression, no stat cost" rule for greebles.
func is_cosmetic() -> bool:
	return category == "greeble"


## One-line stat summary for palette buttons and tooltips.
func summary() -> String:
	var bits: PackedStringArray = []
	var order := ["mass", "thrust", "hull_hp", "shield_hp", "cargo_capacity", "power_output", "power_draw"]
	for key in order:
		if stats.has(key) and absf(stat(key)) > 0.001:
			bits.append("%s %s" % [ShipStats.stat_label(key), ShipStats.format_delta(key, stat(key))])
	if bits.is_empty():
		return "Cosmetic — no stat effect"
	return "  ".join(bits)
