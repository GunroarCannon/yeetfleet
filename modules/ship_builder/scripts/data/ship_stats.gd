## Aggregated ship performance, derived from the parts that make up a design.
##
## Additive stats are summed straight off the parts; a small number are maxima
## (sensor range) rather than sums. Everything a player actually reads —
## top speed, turn rate, jump range — is *derived* from those raws, so swapping a
## cargo pod visibly costs agility without any part having to know about agility.
class_name ShipStats
extends RefCounted

## Raw stat vocabulary. Parts may only contribute to these keys; unknown keys
## are reported as content errors by the library loader.
const STAT_KEYS: Array[String] = [
	"mass",             # tonnes
	"thrust",           # kN
	"agility_pool",     # unitless control authority, converted to deg/s below
	"hull_hp",
	"shield_hp",
	"energy_capacity",  # MJ, the weapon/shield capacitor
	"power_output",     # MW produced
	"power_draw",       # MW consumed at idle
	"cargo_capacity",   # tonnes
	"fuel_capacity",    # tonnes
	"sensor_range",     # km
	"heat",             # heat generated at full burn
	"heat_dissipation", # heat shed per second
]

## Stats where the best part wins instead of parts stacking.
const MAX_STATS: Array[String] = ["sensor_range"]

const LABELS := {
	"mass": "Mass",
	"thrust": "Thrust",
	"agility_pool": "Control authority",
	"hull_hp": "Hull",
	"shield_hp": "Shield",
	"energy_capacity": "Capacitor",
	"power_output": "Power out",
	"power_draw": "Power draw",
	"cargo_capacity": "Cargo",
	"fuel_capacity": "Fuel",
	"sensor_range": "Sensors",
	"heat": "Heat",
	"heat_dissipation": "Cooling",
}

const UNITS := {
	"mass": "t",
	"thrust": "kN",
	"agility_pool": "",
	"hull_hp": "",
	"shield_hp": "",
	"energy_capacity": "MJ",
	"power_output": "MW",
	"power_draw": "MW",
	"cargo_capacity": "t",
	"fuel_capacity": "t",
	"sensor_range": "km",
	"heat": "",
	"heat_dissipation": "/s",
}

## Stats where a bigger number is worse, so the UI can colour deltas correctly.
const LOWER_IS_BETTER: Array[String] = ["mass", "power_draw", "heat", "cost"]

# --- Tuning constants -------------------------------------------------------
# Kept together and named so the flight sim module can reuse the same curves
# rather than inventing its own and drifting apart.
const SPEED_COEFF := 120.0
const SPEED_EXPONENT := 0.6
const ACCEL_COEFF := 8.0
const AGILITY_COEFF := 34.0
const AGILITY_MASS_EXPONENT := 0.62
## Floor on control authority as a fraction of the bare chassis' own, so an
## over-plated hull is a bad ship rather than an impossible one.
const AGILITY_FLOOR_FRACTION := 0.15
const JUMP_COEFF := 7.5

var raw: Dictionary = {}

# Derived, filled by [method finalise].
var thrust_to_mass := 0.0
var accel := 0.0            # m/s^2
var top_speed := 0.0        # m/s
var agility := 0.0          # deg/s
var power_balance := 0.0    # MW spare
var jump_range := 0.0       # ly
var loaded_mass := 0.0      # hull mass + cargo actually aboard

var part_count := 0
var weapon_count := 0
var engine_count := 0
var cockpit_count := 0
var cargo_used := 0.0

var chassis: ShipPart = null
## Blocking problems — the ship will not fly.
var errors: Array[String] = []
## Non-blocking problems — it flies, but badly.
var warnings: Array[String] = []
## Neutral observations worth surfacing.
var notes: Array[String] = []

var cost := 0

## True when the agility floor had to rescue a build whose parts cancelled out all
## of its control authority. Surfaced as a warning rather than hidden.
var _agility_clamped := false


func _init() -> void:
	for key in STAT_KEYS:
		raw[key] = 0.0


func get_stat(key: String) -> float:
	return float(raw.get(key, 0.0))


## Fold one part's contribution in. Cosmetic parts add cost but no performance,
## which is what keeps greebles a free expression layer.
func add_part(part: ShipPart) -> void:
	part_count += 1
	cost += part.cost
	match part.category:
		"weapon": weapon_count += 1
		"engine": engine_count += 1
		"cockpit": cockpit_count += 1
	if part.is_cosmetic():
		return
	for key: Variant in part.stats:
		var k := String(key)
		if not raw.has(k):
			continue
		var v := float(part.stats[key])
		if MAX_STATS.has(k):
			raw[k] = maxf(float(raw[k]), v)
		else:
			raw[k] = float(raw[k]) + v


## Compute the derived figures and run validation. [param cargo_load] is the
## tonnage currently in the hold, so the systems test can show a laden ship
## handling worse than an empty one.
func finalise(cargo_load := 0.0) -> void:
	var hull_mass := maxf(get_stat("mass"), 0.5)
	cargo_used = clampf(cargo_load, 0.0, get_stat("cargo_capacity"))
	loaded_mass = hull_mass + cargo_used

	thrust_to_mass = get_stat("thrust") / loaded_mass
	accel = thrust_to_mass * ACCEL_COEFF
	top_speed = SPEED_COEFF * pow(maxf(thrust_to_mass, 0.0), SPEED_EXPONENT)
	# Control authority never goes negative. Bolting armour and cargo onto a hull
	# makes it sluggish; it does not make it turn backwards. The pool is floored at
	# a fraction of the bare chassis' own authority, because the hull's own
	# manoeuvring thrusters keep working no matter what is bolted to it.
	var pool := get_stat("agility_pool")
	var pool_floor := 0.0
	if chassis != null:
		pool_floor = maxf(chassis.stat("agility_pool"), 0.0) * AGILITY_FLOOR_FRACTION
	_agility_clamped = pool < pool_floor
	agility = AGILITY_COEFF * maxf(pool, pool_floor) / pow(loaded_mass, AGILITY_MASS_EXPONENT)
	power_balance = get_stat("power_output") - get_stat("power_draw")
	jump_range = JUMP_COEFF * get_stat("fuel_capacity") / sqrt(maxf(loaded_mass, 1.0))

	_validate()


func _validate() -> void:
	errors.clear()
	warnings.clear()
	notes.clear()

	if engine_count == 0:
		errors.append("No thruster fitted — the ship cannot move.")
	if cockpit_count == 0:
		errors.append("No cockpit or bridge — the ship cannot be crewed.")
	if get_stat("thrust") <= 0.0:
		errors.append("Zero thrust.")

	if power_balance < 0.0:
		errors.append("Power deficit of %.1f MW — systems will brown out." % -power_balance)
	elif power_balance < 2.0 and get_stat("power_output") > 0.0:
		warnings.append("Only %.1f MW spare; firing everything at once will dip the capacitor." % power_balance)

	if chassis != null and chassis.mass_limit > 0.0 and loaded_mass > chassis.mass_limit:
		warnings.append("Overloaded: %.1f t on a %.0f t frame. Structural strain." % [loaded_mass, chassis.mass_limit])

	if get_stat("heat") > get_stat("heat_dissipation") and get_stat("heat") > 0.0:
		warnings.append("Heat build-up: %.0f generated vs %.0f shed. Sustained burn will cook you." % [
			get_stat("heat"), get_stat("heat_dissipation")
		])

	if get_stat("shield_hp") <= 0.0:
		warnings.append("No shield generator — every hit lands on the hull.")
	if weapon_count == 0:
		notes.append("Unarmed. Fine for a hauler, fatal anywhere else.")
	if get_stat("cargo_capacity") <= 0.0:
		notes.append("No cargo capacity — cannot trade.")
	if _agility_clamped:
		warnings.append(
			"Control authority swamped by mass — turning on hull thrusters alone. "
			+ "Fit wings or drop armour."
		)
	if agility < 8.0 and engine_count > 0:
		notes.append("Very sluggish turn rate (%.1f°/s). Consider wings or less mass." % agility)


func is_flyable() -> bool:
	return errors.is_empty()


# --- Formatting helpers, shared by every UI that shows stats ----------------

static func stat_label(key: String) -> String:
	return LABELS.get(key, key.capitalize())


static func stat_unit(key: String) -> String:
	return UNITS.get(key, "")


static func format_value(key: String, value: float) -> String:
	var unit: String = UNITS.get(key, "")
	var digits := 1 if absf(value) < 100.0 else 0
	return "%.*f%s" % [digits, value, unit]


static func format_delta(key: String, value: float) -> String:
	var sign_str := "+" if value >= 0.0 else ""
	return sign_str + format_value(key, value)


## True when a positive delta on this key is an improvement. Used to pick the
## green/red (or, in high-contrast mode, up/down arrow) affordance.
static func is_improvement(key: String, delta: float) -> bool:
	if LOWER_IS_BETTER.has(key):
		return delta < 0.0
	return delta > 0.0


## Rows for the stat panel. [code]key[/code] names the matching entry in
## [method to_compare_dict] where one exists, so the panel can line a live value up
## with the corresponding preview value and show a delta; rows with no key are
## display-only.
func derived_rows() -> Array[Dictionary]:
	return [
		{"key": "top_speed", "label": "Top speed", "text": "%.0f m/s" % top_speed, "fill": clampf(top_speed / 400.0, 0.0, 1.0)},
		{"key": "accel", "label": "Acceleration", "text": "%.1f m/s²" % accel, "fill": clampf(accel / 40.0, 0.0, 1.0)},
		{"key": "agility", "label": "Turn rate", "text": "%.1f °/s" % agility, "fill": clampf(agility / 90.0, 0.0, 1.0)},
		{"key": "hull_hp", "label": "Hull", "text": "%.0f" % get_stat("hull_hp"), "fill": clampf(get_stat("hull_hp") / 2000.0, 0.0, 1.0)},
		{"key": "shield_hp", "label": "Shield", "text": "%.0f" % get_stat("shield_hp"), "fill": clampf(get_stat("shield_hp") / 1200.0, 0.0, 1.0)},
		{"key": "cargo_capacity", "label": "Cargo", "text": "%.0f t" % get_stat("cargo_capacity"), "fill": clampf(get_stat("cargo_capacity") / 400.0, 0.0, 1.0)},
		{"key": "power_balance", "label": "Power spare", "text": "%.1f MW" % power_balance, "fill": clampf(power_balance / 20.0, 0.0, 1.0)},
		{"key": "energy_capacity", "label": "Capacitor", "text": "%.0f MJ" % get_stat("energy_capacity"), "fill": clampf(get_stat("energy_capacity") / 400.0, 0.0, 1.0)},
		{"key": "jump_range", "label": "Jump range", "text": "%.1f ly" % jump_range, "fill": clampf(jump_range / 30.0, 0.0, 1.0)},
		{"key": "heat_dissipation", "label": "Cooling", "text": "%.0f /s" % get_stat("heat_dissipation"), "fill": clampf(get_stat("heat_dissipation") / 300.0, 0.0, 1.0)},
		{"key": "sensor_range", "label": "Sensors", "text": "%.0f km" % get_stat("sensor_range"), "fill": clampf(get_stat("sensor_range") / 120.0, 0.0, 1.0)},
		{"key": "mass", "label": "Laden mass", "text": "%.1f t" % loaded_mass, "fill": clampf(loaded_mass / 800.0, 0.0, 1.0)},
		{"key": "cost", "label": "Hull cost", "text": "%s cr" % _thousands(cost), "fill": clampf(float(cost) / 2000000.0, 0.0, 1.0)},
	]


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## Snapshot used for before/after comparison when hovering a palette part.
func to_compare_dict() -> Dictionary:
	return {
		"top_speed": top_speed,
		"accel": accel,
		"agility": agility,
		"hull_hp": get_stat("hull_hp"),
		"shield_hp": get_stat("shield_hp"),
		"cargo_capacity": get_stat("cargo_capacity"),
		"power_balance": power_balance,
		"energy_capacity": get_stat("energy_capacity"),
		"jump_range": jump_range,
		"heat_dissipation": get_stat("heat_dissipation"),
		"sensor_range": get_stat("sensor_range"),
		"mass": loaded_mass,
		"cost": float(cost),
	}
