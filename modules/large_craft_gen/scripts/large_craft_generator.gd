## Procedural large craft: a modular mothership/docking-station hybrid built
## from a chain of hull segments with docking arms and greeble spires studding
## it — the same schema-driven-dials, part-composition idea
## [code]solar_system_gen[/code] and [code]ship_builder[/code] each apply to
## their own domain, aimed here at "one enormous structure" instead of "one
## system" or "one flyable ship".
##
## Every visible part (hull segment, dock arm, spire, greeble) is its own
## [StaticBody3D] with its own collider, tracked in [member _parts] — not one
## fused mesh — so [method shoot_at] can raycast to a single part and detach
## exactly that one, matching a castle's turrets or a station's arms being
## shot off individually rather than the whole structure breaking at once.
## A detached part becomes a free [RigidBody3D] and Godot's own physics
## carries it away; nothing here fades or despawns it.
##
## Deliberately dependency-free of any other module: it reaches into
## [code]ship_builder[/code] only for the generic [LowPoly] mesh toolkit and
## [ShipMaterials] shader helpers (both already reused across module
## boundaries — see [code]space_scene.gd[/code]'s [code]_rock_material[/code])
## and never touches [ShipPart]/[ShipDesign], which are that module's own
## player-facing data types.
class_name LargeCraftGenerator
extends Node3D

signal generated
signal part_detached(kind: String, node: Node3D)

## Which structure shape [method generate] builds. Every archetype shares the
## same dials — see the per-archetype build functions for what each dial
## means there — plus the same shootable-parts/dock-pad machinery, so a new
## archetype is a new build function, not a new subsystem.
enum Archetype { MOTHERSHIP, RING_STATION, GATE_FRAME, TOWER_CLUSTER, DREADNOUGHT }
const ARCHETYPE_NAMES := {
	Archetype.MOTHERSHIP: "Mothership / dock",
	Archetype.RING_STATION: "Ring station",
	Archetype.GATE_FRAME: "Gate frame",
	Archetype.TOWER_CLUSTER: "Tower cluster",
	Archetype.DREADNOUGHT: "Dreadnought (armed, mobile)",
}
@export var archetype: Archetype = Archetype.MOTHERSHIP

## --- Randomizable generation dials -------------------------------------------
## Same contract as [constant SolarSystemGenerator.RANDOMIZABLE]: every var
## here has a matching [constant RANDOMIZABLE] schema row, so the lab UI and
## [LargeCraftData] snapshot/restore both drive off the one array instead of a
## hand-built row per dial.
@export var craft_seed: int = 12345
## Defaults sit well up the [constant RANDOMIZABLE] range on purpose — these
## are meant to read as mega-structures, not modest ships; see
## [code]large-craft-gen-scale[/code] memory. A fresh spawn only needs a seed.
@export var segment_count: int = 24
@export var hull_width: float = 28.0
@export var hull_height_ratio: float = 0.7
@export var taper: float = 0.85
@export var dock_arm_count: int = 4
@export var dock_arm_length: float = 30.0
@export var spire_count: int = 40
@export var greeble_count: int = 120
@export var part_scale_jitter: float = 0.15
## Uniform whole-structure scale, applied as [member Node3D.scale] after
## [method generate] rather than baked into the part dials — a 60x structure
## built directly out of [member segment_count]/[member greeble_count] would
## need tens of thousands of live parts to look filled-in at that size; a
## flat scale multiply gets the same reference-photo "this is planet-sized"
## silhouette for the cost of a single transform, no extra geometry. Default
## of 5.0 puts a default mothership's ~85m unscaled extent at ~425m — at
## least a quarter of [constant SpaceScene.PLANET_RADIUS] (1400m), per the
## user's explicit "these should be planet-sized by default" correction (see
## [code]large-craft-gen-scale[/code] memory). Top of the dial range (60x)
## reaches ~5100m, past this game's own star radius convention
## ([code]SolarSystemGenerator.STAR_RADIUS[/code] × its 10x max mult = 2200m)
## — i.e. genuinely sun-scale, not just planet-scale.
@export var scale_mult: float = 5.0

## Ranges run well past "modest mothership" on purpose — a death-star or
## ship-city scale structure needs hundreds of segments/spires/greebles, not
## a dozen. At the top of these ranges generate() can take a visible moment
## and part_count() climbs into the high hundreds; nothing here streams parts
## in/out by distance the way [SolarSystemGenerator]'s belt LOD does, so a
## live-flight consumer spawning a structure at this scale should budget for
## that the same way belts had to.
##
## Every [constant Archetype] shares this one schema — labels are kept
## archetype-neutral on purpose since what a dial drives differs per
## archetype (see each `_generate_*` function's own doc comment for exactly
## what "segment_count" etc. means there), the same way [code]dock_arm_count[/code]
## and [code]dock_arm_length[/code] always mean "how many dock pads, how far
## they reach" regardless of where on the structure they end up mounted.
const RANDOMIZABLE: Array[Dictionary] = [
	{"key": "segment_count", "label": "Segments", "min": 2.0, "max": 80.0, "step": 1.0, "is_int": true},
	{"key": "hull_width", "label": "Scale", "min": 4.0, "max": 70.0, "step": 0.5},
	{"key": "hull_height_ratio", "label": "Shape ratio", "min": 0.4, "max": 1.2, "step": 0.05},
	{"key": "taper", "label": "Taper", "min": 0.6, "max": 1.0, "step": 0.02},
	{"key": "dock_arm_count", "label": "Dock arms", "min": 0.0, "max": 24.0, "step": 1.0, "is_int": true},
	{"key": "dock_arm_length", "label": "Dock arm length", "min": 4.0, "max": 100.0, "step": 0.5},
	{"key": "spire_count", "label": "Spires", "min": 0.0, "max": 250.0, "step": 1.0, "is_int": true},
	{"key": "greeble_count", "label": "Greebles", "min": 0.0, "max": 600.0, "step": 1.0, "is_int": true},
	{"key": "part_scale_jitter", "label": "Part scale jitter", "min": 0.0, "max": 0.4, "step": 0.02},
	{"key": "scale_mult", "label": "Overall scale", "min": 0.5, "max": 60.0, "step": 0.5},
]
## Per-[constant RANDOMIZABLE] key -> whether a reroll should leave it alone.
## Same shape and same "missing key means unlocked" rule as
## [member SolarSystemGenerator.locked].
var locked: Dictionary = {}

const SEGMENT_LENGTH := 6.0
const DETACH_IMPULSE := 8.0

class Part extends RefCounted:
	var id: int
	var kind: String
	var cosmetic: bool
	var node: StaticBody3D
	var mesh: ArrayMesh
	var aabb: AABB
	var markers: Dictionary
	var spec: Dictionary
	var local_xform: Transform3D

var _parts: Dictionary = {}  ## id (int) -> Part
var _next_id := 0
var _dock_pads: Array[DockingPad] = []
var _pad_for_part: Dictionary = {}  ## part id -> DockingPad
var _debris: Array[Node3D] = []
## [constant Archetype.DREADNOUGHT] turret muzzles, in this node's own local
## (pre-scale) space — see [method get_turret_points]. Not [DockingPad]-style
## live nodes: a turret's barrel doesn't animate, so a stored transform is
## all a firing consumer (flight-side) needs.
var _turrets: Array[Transform3D] = []
var _rng := RandomNumberGenerator.new()

@onready var _parts_root := Node3D.new()
@onready var _pads_root := Node3D.new()
@onready var _debris_root := Node3D.new()


func _ready() -> void:
	_parts_root.name = "Parts"
	_pads_root.name = "DockPads"
	_debris_root.name = "Debris"
	add_child(_parts_root)
	add_child(_pads_root)
	add_child(_debris_root)
	generate()


## Rebuild from scratch. Deterministic from [member craft_seed] + every
## [constant RANDOMIZABLE] value, same as [method SolarSystemGenerator.generate_system].
func generate() -> void:
	for child in _parts_root.get_children():
		child.queue_free()
	for child in _pads_root.get_children():
		child.queue_free()
	for child in _debris_root.get_children():
		child.queue_free()
	_parts.clear()
	_next_id = 0
	_dock_pads.clear()
	_pad_for_part.clear()
	_debris.clear()
	_turrets.clear()
	_rng.seed = craft_seed

	match archetype:
		Archetype.RING_STATION: _generate_ring_station()
		Archetype.GATE_FRAME: _generate_gate_frame()
		Archetype.TOWER_CLUSTER: _generate_tower_cluster()
		Archetype.DREADNOUGHT: _generate_dreadnought()
		_: _generate_mothership()
	# Whole-structure scale (see [member scale_mult]'s doc comment) — applied
	# last so every part-building function above stays written in plain,
	# human-sized local units regardless of how big the final craft ends up.
	scale = Vector3.ONE * scale_mult
	generated.emit()


## Reroll every unlocked [constant RANDOMIZABLE] dial, then regenerate — same
## contract as [method SolarSystemGenerator.randomize_unlocked_params].
func randomize_unlocked_params(new_seed: int) -> void:
	craft_seed = new_seed
	var roll := RandomNumberGenerator.new()
	roll.seed = new_seed
	for entry: Dictionary in RANDOMIZABLE:
		var key: String = entry["key"]
		if bool(locked.get(key, false)):
			continue
		var v := roll.randf_range(float(entry["min"]), float(entry["max"]))
		if bool(entry.get("is_int", false)):
			set(key, roundi(v))
		else:
			set(key, v)
	generate()


# --- Mothership / dock (Archetype.MOTHERSHIP) -----------------------------
## Concentric stepped saucer mothership with ventral plasma super-core,
## radial city trenches, illuminated window bands, and perimeter docking clamp bays (Ref 5 & 6).
func _generate_mothership() -> void:
	var saucer_r := maxf(hull_width * 3.2, 32.0)
	var saucer_h := hull_width * hull_height_ratio * 0.75
	var mid_r := saucer_r * 0.55
	var inner_r := saucer_r * 0.25

	# 1. Forward command prow & central citadel spine running along Z
	# Forward bow prow extends along +Z so shoot_at along the Z axis hits it cleanly.
	var bow_length := saucer_r * 1.15
	var prow_segments := maxi(segment_count / 3, 4)
	for i in prow_segments:
		var t := float(i) / float(prow_segments)
		var z := lerpf(inner_r * 0.4, bow_length, t)
		var scale_t := lerpf(1.0, taper * 0.4, t)
		var w := hull_width * 0.65 * scale_t
		_add_part("hull_segment", {
			"length": (bow_length - inner_r * 0.4) / float(prow_segments) * 1.05,
			"width": w, "height": w * hull_height_ratio,
			"corner": w * 0.15, "taper": 0.88,
		}, Transform3D(Basis(), Vector3(0, 0, z)))

	# Aft stern engineering hull / engine block
	var stern_length := saucer_r * 0.85
	var stern_segments := maxi(segment_count / 4, 3)
	for i in stern_segments:
		var t := float(i) / float(stern_segments)
		var z := lerpf(-inner_r * 0.4, -stern_length, t)
		var w := hull_width * lerpf(0.75, 1.15, t)
		_add_part("hull_segment", {
			"length": stern_length / float(stern_segments) * 1.05,
			"width": w, "height": w * hull_height_ratio * 0.9,
			"corner": w * 0.12, "taper": 1.0,
		}, Transform3D(Basis(), Vector3(0, 0, z)))

	# 2. Colossal concentric tiered saucer / disc (Ref 5)
	var sectors := 8
	var angle_per := TAU / float(sectors)
	for i in sectors:
		var angle := angle_per * float(i)
		_add_part("saucer_sector", {
			"center_angle": angle,
			"angle_span": angle_per * 1.02,
			"inner_r": inner_r,
			"mid_r": mid_r,
			"outer_r": saucer_r,
			"height": saucer_h,
			"steps": 5,
		}, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))

	# 3. Ventral recessed glowing super-core / plasma vent (Ref 5)
	_add_part("plasma_core", {
		"radius": inner_r * 0.95,
		"depth": saucer_h * 0.85,
		"sides": 14,
	}, Transform3D(Basis(), Vector3(0.0, -saucer_h * 0.35, 0.0)))

	# 4. Dorsal central observation biosphere dome / bridge citadel (Ref 5, 6)
	_add_part("biosphere_dome", {
		"radius": inner_r * 0.85,
		"sides": 14,
		"steps": 6,
		"flip": 0.0,
	}, Transform3D(Basis(), Vector3(0.0, saucer_h * 0.45, 0.0)))

	# 5. Cantilevered perimeter docking clamp bays along the saucer rim
	# Exactly dock_arm_count pads, distributed around the perimeter!
	if dock_arm_count > 0:
		for i in dock_arm_count:
			var angle := TAU * float(i) / float(dock_arm_count) + _rng.randf_range(-0.1, 0.1)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			var mount_pos := radial * saucer_r
			_place_dock_arm(mount_pos, radial, _jittered(dock_arm_length))

	# 6. Spires and greebles on the saucer decks and spine
	for i in spire_count:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(inner_r * 1.05, mid_r * 0.98)
		var pos := Vector3(cos(a) * r, saucer_h * 0.36, sin(a) * r)
		var height := _rng.randf_range(1.5, 4.0)
		_add_part("spire", {"height": height, "base_radius": 0.6, "sides": 6},
			Transform3D(_radial_up_basis(Vector3.UP), pos), true)

	for i in greeble_count:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(mid_r * 1.02, saucer_r * 0.98)
		var pos := Vector3(cos(a) * r, saucer_h * 0.13, sin(a) * r)
		var size := _rng.randf_range(0.4, 0.9)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size},
			Transform3D(Basis(), pos), true)


## {z: float, radius: float} per segment, hull-surface radius at that point
## along the spine — dock arms, spires and greebles mount off this.
func _build_spine() -> Array[Dictionary]:
	var half := float(segment_count) * SEGMENT_LENGTH * 0.5
	var sections: Array[Dictionary] = []
	var last := maxf(float(segment_count - 1), 1.0)
	for i in segment_count:
		var z := half - float(i) * SEGMENT_LENGTH - SEGMENT_LENGTH * 0.5
		var scale := lerpf(1.0, taper, float(i) / last)
		var width := hull_width * scale
		var height := width * hull_height_ratio
		var jitter := 1.0 + _rng.randf_range(-part_scale_jitter, part_scale_jitter)
		_add_part("hull_segment", {
			"length": SEGMENT_LENGTH * 1.02,
			"width": width * jitter, "height": height * jitter,
			"corner": width * 0.12, "taper": taper,
		}, Transform3D(Basis(), Vector3(0, 0, z)))
		sections.append({"z": z, "radius": width * 0.5})
	return sections


func _mount_dock_arms_on_spine(spine: Array[Dictionary]) -> void:
	if dock_arm_count <= 0 or spine.is_empty():
		return
	for i in dock_arm_count:
		var angle := TAU * float(i) / float(dock_arm_count) + _rng.randf_range(-0.2, 0.2)
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var section: Dictionary = spine[_rng.randi_range(1, spine.size() - 2)] if spine.size() > 2 else spine[0]
		var mount_z := float(section["z"])
		var mount_r := float(section["radius"])
		_place_dock_arm(radial * mount_r + Vector3(0, 0, mount_z), radial, _jittered(dock_arm_length))


func _scatter_on_spine(kind: String, count: int, spine: Array[Dictionary], upright: bool) -> void:
	for i in count:
		if spine.is_empty():
			break
		var section: Dictionary = spine[_rng.randi_range(0, spine.size() - 1)]
		var angle := _rng.randf_range(0.0, TAU)
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var mount_r := float(section["radius"])
		var mount_z := float(section["z"]) + _rng.randf_range(-SEGMENT_LENGTH * 0.45, SEGMENT_LENGTH * 0.45)
		if upright:
			var height := _rng.randf_range(1.5, 4.0) * (1.0 + _rng.randf_range(-part_scale_jitter, part_scale_jitter))
			var xform := Transform3D(_radial_up_basis(radial), radial * mount_r + Vector3(0, 0, mount_z))
			_add_part("spire", {"height": height, "base_radius": _rng.randf_range(0.5, 1.2), "sides": 6}, xform, true)
		else:
			var size := _rng.randf_range(0.3, 0.9)
			var xform := Transform3D(_radial_basis(radial), radial * (mount_r + size * 0.4) + Vector3(0, 0, mount_z))
			var part_kind := _random_greeble_kind() if kind == "greeble_block" else kind
			_add_part(part_kind, {"sx": size, "sy": size, "sz": size}, xform, true)


# --- Dreadnought (Archetype.DREADNOUGHT) ------------------------------------
## Colossal titan warship with spinal rail cannon trench, asymmetric citadel
## engineering, offset rotating gravity wheel, propellant tank cluster, and gun turrets (Ref 6).
func _generate_dreadnought() -> void:
	var spine := _build_spine()
	_mount_turrets_on_spine(spine)
	_mount_wings_and_tail(spine)

	# Asymmetric Citadel Engineering (Ref 6):
	var mid_i := clampi(int(float(spine.size()) * 0.5), 0, spine.size() - 1)
	var mid: Dictionary = spine[mid_i]
	var mid_r := float(mid["radius"])
	var mid_z := float(mid["z"])

	# Port flank: offset rotating gravity wheel / ring on a structural truss axle!
	var wheel_r := mid_r * 1.6
	var axle_len := mid_r * 2.2
	var port_mount := Vector3(mid_r, 0.0, mid_z)
	_add_part("truss_spine", {
		"length": axle_len, "width": mid_r * 0.25, "height": mid_r * 0.25, "bays": 3,
	}, Transform3D(_radial_basis(Vector3.RIGHT), port_mount))
	_add_part("energy_ring", {
		"radius": wheel_r, "tube_radius": mid_r * 0.18, "sides": 10, "segments": 16,
	}, Transform3D(Basis(), port_mount + Vector3(axle_len, 0.0, 0.0)))

	# Starboard flank: bank of pressurized propellant tanks (fuel_cluster) in cradle!
	_add_part("fuel_cluster", {
		"length": SEGMENT_LENGTH * 3.5, "tank_radius": mid_r * 0.25, "count": 4,
	}, Transform3D(Basis(), Vector3(-mid_r * 1.1, 0.0, mid_z + SEGMENT_LENGTH * 1.5)))

	# Dorsal deck: geodesic biosphere dome / command module
	_add_part("biosphere_dome", {
		"radius": mid_r * 0.55, "sides": 12, "steps": 5, "flip": 0.0,
	}, Transform3D(Basis(), Vector3(0.0, mid_r * hull_height_ratio * 0.95, mid_z - SEGMENT_LENGTH)))

	# Flank heat radiator wings
	for side: float in [1.0, -1.0]:
		_add_part("radiator_wing", {
			"span": mid_r * 1.8, "chord": SEGMENT_LENGTH * 2.5, "thickness": mid_r * 0.08, "side": side,
		}, Transform3D(Basis(), Vector3(side * mid_r * 0.9, mid_r * 0.3, mid_z - SEGMENT_LENGTH * 2.5)))

	# Launch / docking bays
	_mount_dock_arms_on_spine(spine)

	# Greebles
	_scatter_on_spine("greeble_block", greeble_count, spine, false)


func _mount_wings_and_tail(spine: Array[Dictionary]) -> void:
	if spine.is_empty():
		return
	var mid_i := clampi(int(float(spine.size()) * 0.58), 0, spine.size() - 1)
	var mid: Dictionary = spine[mid_i]
	var mount_r := float(mid["radius"])
	var mount_z := float(mid["z"])
	var span := hull_width * _rng.randf_range(2.2, 3.4)
	var root_chord := SEGMENT_LENGTH * _rng.randf_range(3.5, 5.5)
	var tip_chord := root_chord * _rng.randf_range(0.2, 0.4)
	var sweep := root_chord * _rng.randf_range(0.4, 1.0)
	var thickness := hull_width * 0.05
	for side: float in [1.0, -1.0]:
		_add_part("wing", {
			"span": span, "root_chord": root_chord, "tip_chord": tip_chord,
			"sweep": sweep, "dihedral": root_chord * 0.08, "thickness": thickness, "side": side,
		}, Transform3D(Basis(), Vector3(side * mount_r, 0, mount_z)))

	var stern: Dictionary = spine[spine.size() - 1]
	var stern_r := float(stern["radius"])
	var stern_z := float(stern["z"])
	var fin_height := hull_width * _rng.randf_range(1.4, 2.2)
	_add_part("tail_fin", {
		"height": fin_height, "root_chord": SEGMENT_LENGTH * 4.0, "tip_chord": SEGMENT_LENGTH * 1.2,
		"sweep": SEGMENT_LENGTH * 2.0, "thickness": thickness,
	}, Transform3D(Basis(), Vector3(0, stern_r * 0.6, stern_z)))

	var stab_span := span * 0.35
	for side: float in [1.0, -1.0]:
		_add_part("wing", {
			"span": stab_span, "root_chord": root_chord * 0.45, "tip_chord": tip_chord * 0.6,
			"sweep": sweep * 0.5, "dihedral": 0.0, "thickness": thickness * 0.8, "side": side,
		}, Transform3D(Basis(), Vector3(side * stern_r * 0.5, stern_r * 0.25, stern_z)))


func _mount_turrets_on_spine(spine: Array[Dictionary]) -> void:
	for i in spire_count:
		if spine.is_empty():
			break
		var section: Dictionary = spine[_rng.randi_range(0, spine.size() - 1)]
		var angle := _rng.randf_range(0.0, TAU)
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var mount_r := float(section["radius"])
		var mount_z := float(section["z"])
		var xform := Transform3D(_radial_basis(radial), radial * mount_r + Vector3(0, 0, mount_z))
		var j := 1.0 + _rng.randf_range(-part_scale_jitter, part_scale_jitter)
		var part_id := _add_part("turret", {
			"base": 1.2 * j, "barrel": 1.8 * j, "barrel_r": 0.22 * j,
		}, xform, true)
		var part: Part = _parts[part_id]
		var muzzle: Transform3D = part.markers.get("muzzle", [Transform3D()])[0]
		_turrets.append(xform * muzzle)


# --- Ring station (Archetype.RING_STATION) ---------------------------------
## Colossal torus ring citadel with central glowing biosphere dome,
## open structural truss spokes, perimeter radiator fins, and rim docking gantries (Ref 1).
func _generate_ring_station() -> void:
	var hub_radius := hull_width * 0.7
	var ring_radius := maxf(hull_width * 4.2, hub_radius * 2.5)
	var tube_radius := maxf(hull_width * 0.22, 0.8)

	# 1. Central glowing geodesic biosphere dome / core station hub (Ref 1)
	_add_part("biosphere_dome", {"radius": hub_radius, "sides": 14, "steps": 6, "flip": 0.0}, Transform3D())
	_add_part("dome", {"radius": hub_radius * 0.95, "sides": 14, "steps": 5, "flip": 1.0}, Transform3D())

	# 2. Multi-tier outer torus ring with convex hull collision
	var ring_basis := Basis(Vector3(1, 0, 0), PI * 0.5)
	var wedges := maxi(segment_count, 12)
	for i in wedges:
		var center_angle := TAU * float(i) / float(wedges)
		_add_part("ring_segment", {
			"center_angle": center_angle, "angle_span": TAU / float(wedges) * 1.02,
			"radius": ring_radius, "tube_radius": tube_radius, "sides": 8, "steps": 4,
		}, Transform3D(ring_basis, Vector3.ZERO))

	# 3. Open structural truss spokes connecting the central hub to the outer ring (Ref 1)
	var spoke_count := clampi(roundi(float(wedges) / 4.0), 4, 10)
	for i in spoke_count:
		var angle := TAU * float(i) / float(spoke_count)
		var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
		var mount := dir_flat * hub_radius
		var spoke_len := ring_radius - hub_radius
		var xform := Transform3D(_radial_basis(dir_flat), mount)
		_add_part("truss_spine", {
			"length": spoke_len, "width": tube_radius * 1.1, "height": tube_radius * 1.1, "bays": 4,
		}, xform)

	# 4. Outer rim radiator wings (Ref 1)
	var wing_count := 4
	for i in wing_count:
		var angle := TAU * (float(i) + 0.5) / float(wing_count)
		var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
		var mount := dir_flat * (ring_radius + tube_radius)
		var side := 1.0 if i % 2 == 0 else -1.0
		_add_part("radiator_wing", {
			"span": tube_radius * 3.5, "chord": tube_radius * 2.5, "thickness": tube_radius * 0.25, "side": side,
		}, Transform3D(_radial_basis(dir_flat), mount))

	# 5. Outer rim docking arms
	if dock_arm_count > 0:
		for i in dock_arm_count:
			var angle := TAU * float(i) / float(dock_arm_count) + _rng.randf_range(-0.1, 0.1)
			var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
			var mount := dir_flat * (ring_radius + tube_radius)
			_place_dock_arm(mount, dir_flat, _jittered(dock_arm_length))

	# 6. Spire antennae and surface greebles
	for i in spire_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
		var mount := dir_flat * (ring_radius + tube_radius)
		var height := _rng.randf_range(1.5, 4.0)
		_add_part("spire", {"height": height, "base_radius": 0.5, "sides": 6},
			Transform3D(_radial_up_basis(Vector3.UP), mount), true)

	for i in greeble_count:
		var angle := _rng.randf_range(0.0, TAU)
		var on_ring := _rng.randf() > 0.4
		var radius := (ring_radius if on_ring else hub_radius) + _rng.randf_range(0.2, 1.0)
		var pos := Vector3(cos(angle) * radius, _rng.randf_range(-hub_radius * 0.3, hub_radius * 0.3) if not on_ring else 0.0, sin(angle) * radius)
		var size := _rng.randf_range(0.35, 0.85)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size}, Transform3D(Basis(), pos), true)


# --- Gate frame (Archetype.GATE_FRAME) --------------------------------------
## Colossal vertical rectangular open monolith portal frame with stepped side pylons,
## suspended tiered circular energy rings, and central vertical glowing plasma beam (Ref 0).
func _generate_gate_frame() -> void:
	var width := hull_width * 2.8
	var height := hull_width * hull_height_ratio * 3.4
	var depth := maxf(dock_arm_length * 0.8, 20.0)
	var hx := width * 0.5
	var hy := height * 0.5
	var hz := depth * 0.5
	var pylon_w := maxf(hull_width * 0.35, 3.0)
	var pylon_d := maxf(hull_width * 0.4, 4.0)

	# 1. Colossal vertical side pylons (Left and Right - Ref 0)
	for side: float in [1.0, -1.0]:
		var px: float = side * (hx + pylon_w * 0.5)
		_add_part("city_slab", {
			"width": pylon_w * 1.3, "height": height * 1.1, "depth": pylon_d,
			"chamfer": pylon_w * 0.25, "taper": 0.95, "windows": 5,
		}, Transform3D(Basis(), Vector3(px, -hy * 1.05, 0.0)))

		_add_part("truss_spine", {
			"length": height * 1.05, "width": pylon_w * 0.8, "height": pylon_d * 0.8, "bays": 6,
		}, Transform3D(_radial_basis(Vector3.UP), Vector3(px + side * pylon_w * 0.6, -hy * 1.05, 0.0)))

	# 2. Top and bottom arched bridge lintels tying the pylons together
	for y_side: float in [1.0, -1.0]:
		var py: float = y_side * (hy + pylon_w * 0.3)
		_add_part("truss_spine", {
			"length": width + pylon_w * 2.0, "width": pylon_w * 0.8, "height": pylon_d * 0.7, "bays": 6,
		}, Transform3D(_radial_basis(Vector3.RIGHT), Vector3(-(hx + pylon_w), py, 0.0)))

	# 3. Tiered suspended circular energy rings inside the portal opening (Ref 0)
	var ring_tiers := maxi(segment_count / 6, 3)
	var ring_radius := minf(hx, hy) * 0.6
	var tube_radius := maxf(hull_width * 0.09, 0.4)
	for r in ring_tiers:
		var t := (float(r) + 0.5) / float(ring_tiers) - 0.5
		var ring_y := t * hy * 0.85
		var scale_tier := 1.0 - absf(t) * 0.25
		_add_part("energy_ring", {
			"radius": ring_radius * scale_tier,
			"tube_radius": tube_radius,
			"sides": 10,
			"segments": 20,
		}, Transform3D(_radial_up_basis(Vector3.UP), Vector3(0.0, ring_y, 0.0)))

	# 4. Vertical central glowing plasma conduit emitter beam running between rings
	_add_part("plasma_core", {
		"radius": ring_radius * 0.35, "depth": height * 0.9, "tiers": 4,
	}, Transform3D(_radial_up_basis(Vector3.UP), Vector3(0.0, 0.0, 0.0)))

	# 5. Cantilevered docking arms on outer pylon faces
	if dock_arm_count > 0:
		for i in dock_arm_count:
			var side: float = 1.0 if (i % 2 == 0) else -1.0
			var t := float(i) / float(maxi(dock_arm_count - 1, 1)) - 0.5
			var mount := Vector3(side * (hx + pylon_w * 1.1), t * hy * 1.1, 0.0)
			var dir := Vector3(side, 0.0, 0.0)
			_place_dock_arm(mount, dir, _jittered(dock_arm_length * 0.65))

	# 6. Spires and greebles
	for i in spire_count:
		var side := 1.0 if _rng.randf() > 0.5 else -1.0
		var px := side * (hx + pylon_w * 0.5)
		var y := _rng.randf_range(-hy, hy)
		var z := _rng.randf_range(-hz, hz)
		var height_s := _rng.randf_range(1.5, 3.5)
		_add_part("spire", {"height": height_s, "base_radius": 0.5, "sides": 6},
			Transform3D(_radial_up_basis(Vector3(side, 0, 0)), Vector3(px + side * pylon_w * 0.5, y, z)), true)

	for i in greeble_count:
		var side := 1.0 if _rng.randf() > 0.5 else -1.0
		var px := side * (hx + pylon_w * 0.5)
		var y := _rng.randf_range(-hy, hy)
		var z := _rng.randf_range(-hz, hz)
		var size := _rng.randf_range(0.4, 0.8)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size},
			Transform3D(Basis(), Vector3(px, y, z)), true)


# --- Tower cluster (Archetype.TOWER_CLUSTER) --------------------------------
## Colossal vertical orbital city spire with central structural elevator truss spine,
## massive angular cantilevered city slabs with lit window grids, and terraces (Refs 2, 3, 4).
func _generate_tower_cluster() -> void:
	var tower_height := float(segment_count) * SEGMENT_LENGTH * 1.1
	var core_width := hull_width * 0.35
	var floors := maxi(int(tower_height / SEGMENT_LENGTH), 3)

	# 1. Colossal multi-tiered foundation base platform at y=0 (Refs 2, 3, 4)
	var base_w := hull_width * 2.2
	var base_h := SEGMENT_LENGTH * 0.7
	_add_part("city_slab", {
		"width": base_w, "height": base_h, "depth": base_w,
		"chamfer": base_w * 0.2, "taper": 0.92, "windows": 2,
	}, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))
	_add_part("city_slab", {
		"width": base_w * 0.65, "height": base_h * 0.8, "depth": base_w * 0.65,
		"chamfer": base_w * 0.15, "taper": 0.95, "windows": 2,
	}, Transform3D(Basis(), Vector3(0.0, base_h, 0.0)))

	# 2. Central vertical open structural truss elevator spine (Ref 2, 3)
	var truss_bays := clampi(floors, 4, 16)
	_add_part("truss_spine", {
		"length": tower_height,
		"width": core_width,
		"height": core_width,
		"bays": truss_bays,
	}, Transform3D(_radial_basis(Vector3.UP), Vector3(0.0, 0.0, 0.0)))

	# 3. Cantilevered city slabs jutting out at staggered levels (Refs 2, 3, 4)
	var slab_levels := clampi(floors / 2, 3, 12)
	for lvl in slab_levels:
		var t := float(lvl) / float(slab_levels)
		var y := lerpf(base_h * 2.0, tower_height - SEGMENT_LENGTH * 2.0, t)
		var angle := float(lvl) * 2.39996 + _rng.randf_range(-0.15, 0.15)
		var slab_w := hull_width * lerpf(1.3, 0.6, t)
		var slab_d := hull_width * lerpf(1.1, 0.55, t)
		var slab_h := SEGMENT_LENGTH * lerpf(1.4, 0.9, t)
		var reach := core_width * 0.5 + slab_d * 0.45
		var pos := Vector3(sin(angle) * reach, y, cos(angle) * reach)
		var slab_basis := Basis(Vector3.UP, angle)
		_add_part("city_slab", {
			"width": slab_w, "height": slab_h, "depth": slab_d,
			"chamfer": slab_w * 0.18, "taper": 0.88, "windows": 3,
		}, Transform3D(slab_basis, pos))

		# Cantilever structural truss bridge connecting back into the elevator spine
		var bridge_dir := Vector3(sin(angle), 0.0, cos(angle))
		var bridge_mount := Vector3(0.0, y + slab_h * 0.2, 0.0)
		_add_part("truss_spine", {
			"length": reach + slab_d * 0.1,
			"width": core_width * 0.35,
			"height": core_width * 0.35,
			"bays": 2,
		}, Transform3D(_radial_basis(bridge_dir), bridge_mount), true)

	# 4. Spire crown at the apex
	_add_part("spire", {
		"height": hull_width * 1.2, "base_radius": core_width * 0.6, "sides": 8,
	}, Transform3D(_radial_up_basis(Vector3.UP), Vector3(0.0, tower_height, 0.0)))

	# 5. Observation biosphere dome on the lower terrace
	_add_part("biosphere_dome", {
		"radius": core_width * 1.1, "sides": 12, "steps": 5, "flip": 0.0,
	}, Transform3D(Basis(), Vector3(0.0, base_h * 1.8, 0.0)))

	# 6. Cantilevered landing pads
	if dock_arm_count > 0:
		for i in dock_arm_count:
			var t := (float(i) + 0.5) / float(dock_arm_count)
			var y := lerpf(base_h * 2.5, tower_height * 0.7, t)
			var angle := TAU * float(i) / float(dock_arm_count) + 0.5
			var dir := Vector3(sin(angle), 0.0, cos(angle))
			var mount := dir * (core_width * 1.2 + hull_width * 0.4) + Vector3(0, y, 0)
			_place_dock_arm(mount, dir, _jittered(dock_arm_length * 0.6))

	# 7. Spires and greebles
	for i in spire_count:
		var t := _rng.randf()
		var y := lerpf(base_h * 2.0, tower_height * 0.9, t)
		var angle := _rng.randf_range(0.0, TAU)
		var r := core_width * 0.8 + _rng.randf_range(0.5, hull_width * 0.5)
		var pos := Vector3(sin(angle) * r, y, cos(angle) * r)
		_add_part("spire", {"height": _rng.randf_range(1.5, 3.5), "base_radius": 0.5, "sides": 6},
			Transform3D(_radial_up_basis(Vector3.UP), pos), true)

	for i in greeble_count:
		var t := _rng.randf()
		var y := lerpf(base_h * 1.5, tower_height * 0.9, t)
		var angle := _rng.randf_range(0.0, TAU)
		var r := core_width * 0.6 + _rng.randf_range(0.2, hull_width * 0.4)
		var pos := Vector3(sin(angle) * r, y, cos(angle) * r)
		var size := _rng.randf_range(0.3, 0.75)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size},
			Transform3D(Basis(), pos), true)


# --- Shared placement helpers -----------------------------------------------

func _jittered(value: float) -> float:
	return value * (1.0 + _rng.randf_range(-part_scale_jitter, part_scale_jitter))


## Every scattered-greeble call site picks from this instead of hardcoding
## "greeble_block" — a hull studded with only cubes is what read as "just
## cubes"; [code]greeble_block[/code] stays weighted heaviest so the mix still
## reads as plating-with-detail rather than a pile of antennas.
const GREEBLE_KINDS := [
	"greeble_block", "greeble_block", "greeble_panel", "greeble_vent", "greeble_antenna", "greeble_dish",
]

func _random_greeble_kind() -> String:
	return GREEBLE_KINDS[_rng.randi_range(0, GREEBLE_KINDS.size() - 1)]


## Places one dock_ramp + strut + [DockingPad] at [param mount_pos], reaching
## outward along [param dir]. The one dock-pad builder every archetype calls
## — [member dock_arm_count]/[member dock_arm_length] always mean "how many
## of these, how long" regardless of where on the structure they end up.
func _place_dock_arm(mount_pos: Vector3, dir: Vector3, length: float) -> void:
	var basis := _radial_basis(dir)
	var xform := Transform3D(basis, mount_pos)
	var part_id := _add_part("dock_ramp", {
		"length": length, "width": 2.6, "thickness": 0.6, "pad_width": 5.0,
	}, xform)
	_add_part("strut", {"length": length * 0.3, "thickness": 0.6}, xform, true)

	var part: Part = _parts[part_id]
	var dock_marker: Transform3D = part.markers.get("dock", [Transform3D()])[0]
	var pad := DockingPad.new()
	pad.name = "DockPad_%d" % part_id
	var pad_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Must match (or exceed) capture_radius — a body outside this actual
	# physical Area3D shape never appears in get_overlapping_bodies(), no
	# matter what the magnetize math's own capture_radius says.
	sphere.radius = pad.capture_radius
	pad_shape.shape = sphere
	pad.add_child(pad_shape)
	_pads_root.add_child(pad)
	pad.transform = xform * dock_marker
	_dock_pads.append(pad)
	_pad_for_part[part_id] = pad


## Basis whose local -Z points along [param dir] (the outward/approach
## convention every [LargeCraftPartFactory] generator uses) with a sane `up`
## fallback when `dir` is nearly vertical.
func _radial_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(dir, up)


## Spires stand upright off the hull (local +Y is "up the tower") rather than
## outward like a ramp, so they need local Y, not -Z, aimed along [param dir].
## The tower mesh is rotationally symmetric about its own Y axis, so any
## orthonormal basis with that Y column is fine — no need to match a facing.
func _radial_up_basis(dir: Vector3) -> Basis:
	var y_axis := dir.normalized()
	var reference := Vector3.FORWARD if absf(y_axis.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x_axis := reference.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _add_part(kind: String, spec: Dictionary, local_xform: Transform3D, cosmetic := false) -> int:
	var built := LargeCraftPartFactory.build(kind, spec)
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [kind, _next_id]
	body.transform = local_xform

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = built.mesh
	mesh_inst.material_override = _metal_material(cosmetic)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var col_shape: Shape3D = null
	if not cosmetic and built.mesh != null and built.mesh.get_surface_count() > 0:
		col_shape = built.mesh.create_trimesh_shape()
	if col_shape != null:
		shape.shape = col_shape
		shape.position = Vector3.ZERO
	else:
		var box := BoxShape3D.new()
		var size := built.aabb.size
		box.size = Vector3(maxf(size.x, 0.2), maxf(size.y, 0.2), maxf(size.z, 0.2))
		shape.shape = box
		shape.position = built.aabb.get_center()
	body.add_child(shape)

	_parts_root.add_child(body)

	var part := Part.new()
	part.id = _next_id
	part.kind = kind
	part.cosmetic = cosmetic
	part.node = body
	part.mesh = built.mesh
	part.aabb = built.aabb
	part.markers = built.markers
	part.spec = spec
	part.local_xform = local_xform
	_parts[part.id] = part
	_next_id += 1
	return part.id


static var _mat_hull: ShaderMaterial = null
static var _mat_greeble: ShaderMaterial = null

static func refresh_materials() -> void:
	_mat_hull = null
	_mat_greeble = null


func restyle() -> void:
	refresh_materials()
	for part in _parts.values():
		if is_instance_valid(part.node):
			var mesh_inst: MeshInstance3D = part.node.get_node_or_null("Mesh")
			if mesh_inst != null:
				mesh_inst.material_override = _metal_material(part.cosmetic)


## Bakes static structure parts into unified meshes for low draw calls on mobile.
func bake_structure_meshes() -> void:
	var st_hull := SurfaceTool.new()
	st_hull.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_greeble := SurfaceTool.new()
	st_greeble.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_hull := false
	var has_greeble := false

	for part in _parts.values():
		if not is_instance_valid(part.node) or part.mesh == null or part.mesh.get_surface_count() == 0:
			continue
		var st := st_greeble if part.cosmetic else st_hull
		if part.cosmetic:
			has_greeble = true
		else:
			has_hull = true
		var xform: Transform3D = part.node.transform
		var arrays: Array = part.mesh.surface_get_arrays(0)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

		if indices.is_empty():
			for i in verts.size():
				if not normals.is_empty() and i < normals.size():
					st.set_normal((xform.basis * normals[i]).normalized())
				if not colors.is_empty() and i < colors.size():
					st.set_color(colors[i])
				st.add_vertex(xform * verts[i])
		else:
			for idx in indices:
				if not normals.is_empty() and idx < normals.size():
					st.set_normal((xform.basis * normals[idx]).normalized())
				if not colors.is_empty() and idx < colors.size():
					st.set_color(colors[idx])
				st.add_vertex(xform * verts[idx])

		# Hide individual mesh instances but keep the StaticBody3D collision intact
		var mesh_inst: MeshInstance3D = part.node.get_node_or_null("Mesh")
		if mesh_inst != null:
			mesh_inst.visible = false

	if has_hull:
		var mi_hull := MeshInstance3D.new()
		mi_hull.name = "BakedHullStructure"
		mi_hull.mesh = st_hull.commit()
		mi_hull.material_override = _metal_material(false)
		mi_hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts_root.add_child(mi_hull)

	if has_greeble:
		var mi_greeble := MeshInstance3D.new()
		mi_greeble.name = "BakedGreebleStructure"
		mi_greeble.mesh = st_greeble.commit()
		mi_greeble.material_override = _metal_material(true)
		mi_greeble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts_root.add_child(mi_greeble)


func _metal_material(cosmetic: bool) -> ShaderMaterial:
	if cosmetic:
		if _mat_greeble == null:
			_mat_greeble = _build_material(
				Palette.color("metal_mid"), Palette.color("ui_warn"), Palette.color("metal_dark")
			)
		return _mat_greeble
	if _mat_hull == null:
		_mat_hull = _build_material(
			Palette.color("metal_light"), Palette.color("beam"), Palette.color("metal_dark")
		)
	return _mat_hull


static func _build_material(primary: Color, accent: Color, trim: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ShipMaterials.part_shader()
	mat.set_shader_parameter("primary_color", Palette.get_sat_lifted_color(primary))
	mat.set_shader_parameter("accent_color", Palette.get_sat_lifted_color(accent))
	mat.set_shader_parameter("trim_color", Palette.get_sat_lifted_color(trim))
	mat.set_shader_parameter("metallic_amount", 0.3)
	mat.set_shader_parameter("roughness_amount", 0.75)
	mat.set_shader_parameter("specular_amount", 0.25)
	mat.set_shader_parameter("rim_strength", 0.16)
	mat.set_shader_parameter("ao_strength", 0.32)
	mat.set_shader_parameter("solidity", 0.2)
	ShipMaterials.apply_style_dials(mat)
	ShipMaterials.apply_outline(mat)
	return mat


# --- Shooting / detach -----------------------------------------------------

## Raycast from [param from] along [param dir] and detach whichever part is
## hit first. Returns the detached [RigidBody3D], or null if nothing was hit.
func shoot_at(from: Vector3, dir: Vector3, max_dist := 200.0) -> RigidBody3D:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * max_dist)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var body: Object = hit.get("collider")
	for id: int in _parts.keys():
		var part: Part = _parts[id]
		if part.node == body:
			return _detach_part(id, dir.normalized())
	return null


func _detach_part(id: int, hit_dir: Vector3) -> RigidBody3D:
	if not _parts.has(id):
		return null
	var part: Part = _parts[id]
	var world_xform := global_transform * part.local_xform

	var rigid := RigidBody3D.new()
	rigid.name = "Debris_%s_%d" % [part.kind, id]
	rigid.top_level = true
	rigid.transform = world_xform

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = part.mesh
	mesh_inst.material_override = _metal_material(part.cosmetic)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rigid.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var col_shape: Shape3D = null
	if not part.cosmetic and part.mesh != null and part.mesh.get_surface_count() > 0:
		col_shape = part.mesh.create_convex_shape(true, true)
	if col_shape != null:
		shape.shape = col_shape
		shape.position = Vector3.ZERO
	else:
		var box := BoxShape3D.new()
		var size := part.aabb.size
		box.size = Vector3(maxf(size.x, 0.2), maxf(size.y, 0.2), maxf(size.z, 0.2))
		shape.shape = box
		shape.position = part.aabb.get_center()
	rigid.add_child(shape)

	_debris_root.add_child(rigid)
	rigid.linear_velocity = hit_dir * DETACH_IMPULSE
	rigid.angular_velocity = Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)
	) * 1.5
	_debris.append(rigid)

	if _pad_for_part.has(id):
		var pad: DockingPad = _pad_for_part[id]
		_dock_pads.erase(pad)
		pad.queue_free()
		_pad_for_part.erase(id)

	part.node.queue_free()
	_parts.erase(id)
	part_detached.emit(part.kind, rigid)
	return rigid


# --- Queries -----------------------------------------------------------------

func part_count() -> int:
	return _parts.size()


func dock_pad_count() -> int:
	return _dock_pads.size()


func debris_count() -> int:
	return _debris.size()


## Rough "radius" of the whole structure — max distance from the origin to
## any part's mount point plus that part's own extent. Archetype-agnostic
## (unlike a hand-tuned per-archetype size formula), so camera framing or a
## spawn-placement offset can size itself without knowing which archetype
## this is.
func approx_extent() -> float:
	var extent := 1.0
	for id: int in _parts.keys():
		var part: Part = _parts[id]
		var reach := part.local_xform.origin.length() + part.aabb.size.length() * 0.5
		extent = maxf(extent, reach)
	# Parts are measured in this node's own local (pre-[member scale_mult])
	# space; multiply back up to the real world-space size a caller actually
	# needs (spawn placement, camera framing) — [member scale] is applied
	# uniformly, so its x component alone is exact.
	return extent * scale.x


## Geometric bounding-box center of all live parts in global space.
## Centers camera framing accurately on tall vertical spires or offset citadels.
func get_structure_center() -> Vector3:
	if _parts.is_empty():
		return global_position
	var min_pos := Vector3(INF, INF, INF)
	var max_pos := Vector3(-INF, -INF, -INF)
	for id: int in _parts.keys():
		var part: Part = _parts[id]
		var half_size: Vector3 = part.aabb.size * 0.5
		var p: Vector3 = part.local_xform.origin
		min_pos.x = minf(min_pos.x, p.x - half_size.x)
		min_pos.y = minf(min_pos.y, p.y - half_size.y)
		min_pos.z = minf(min_pos.z, p.z - half_size.z)
		max_pos.x = maxf(max_pos.x, p.x + half_size.x)
		max_pos.y = maxf(max_pos.y, p.y + half_size.y)
		max_pos.z = maxf(max_pos.z, p.z + half_size.z)
	var local_center: Vector3 = (min_pos + max_pos) * 0.5
	return to_global(local_center)


## Radius of sphere enclosing all live parts measured from [method get_structure_center].
func get_structure_radius() -> float:
	var center := get_structure_center()
	var max_dist := 1.0
	for id: int in _parts.keys():
		var part: Part = _parts[id]
		var part_world: Vector3 = to_global(part.local_xform.origin)
		var part_radius: float = part.aabb.size.length() * 0.5 * scale.x
		var d: float = center.distance_to(part_world) + part_radius
		max_dist = maxf(max_dist, d)
	return max_dist


## World-space transforms of every live dock pad — for a future ship-docking
## consumer that wants candidate approach points without knowing anything
## about how this generator built them.
func get_dock_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for pad in _dock_pads:
		if is_instance_valid(pad):
			out.append(pad.global_transform)
	return out


## The live dock pads themselves, for a consumer that wants to pull a flyer
## toward one directly (see [method DockingPad.pull_point]) — [FlightModel]
## has no collider (see its own doc comment) so never shows up in
## [method Area3D.get_overlapping_bodies], and needs to be magnetized by an
## explicit call instead of the automatic RigidBody3D path.
func get_dock_pads() -> Array[DockingPad]:
	var out: Array[DockingPad] = []
	for pad in _dock_pads:
		if is_instance_valid(pad):
			out.append(pad)
	return out


## World-space transforms of every [constant Archetype.DREADNOUGHT] turret
## muzzle (forward = local -Z, this factory's aim convention) — empty for
## every other archetype. Purely geometric; this module stays combat-
## agnostic (see the class doc comment), so firing anything from these is
## entirely [FlightRoot]'s call, the same split [method get_dock_points] has
## with actual docking behaviour.
func get_turret_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for t in _turrets:
		out.append(global_transform * t)
	return out


## One entry per *structural* part (everything not marked cosmetic —
## spires/greebles/turrets are deliberately excluded, or a craft's collision would
## mean registering hundreds of tiny rivets instead of the actual hull), as
## `{node, hull}`: the part's own [StaticBody3D] and a compound of spheres fitted
## to its bounds.
##
## The spheres are in [param node]'s own space, which is the space
## [method PhysBody.set_hull] reads offsets in — the solver transforms them by the
## body node's global transform, and the part node carries the part's placement.
##
## This used to be a single sphere per part, sized
## `aabb.get_center().length() + aabb.size.length()*0.5` from the node origin. For a
## hull segment — many times longer than it is wide — that is a ball more than two
## segments across, so a mothership's collision was a row of huge invisible spheres
## reaching well outside its silhouette and the player bounced off empty space
## alongside it. [method HullFit.spheres_for_box] chains spheres down the part's
## longest axis instead, at that part's cross-section, so a big structure is
## collided with where it actually is.
##
## Purely geometric, like [method get_dock_points]/[method get_turret_points]
## — this module stays physics-agnostic (see the class doc comment); actually
## registering these with the flight scene's [PhysWorld] is [FlightRoot]'s
## job.
func get_collision_spheres() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _parts.keys():
		var part: Part = _parts[id]
		if part.cosmetic or not is_instance_valid(part.node):
			continue
		
		var hull: Array[Dictionary] = []
		if part.kind == "energy_ring":
			var r: float = float(part.spec.get("radius", 18.0))
			var tr: float = float(part.spec.get("tube_radius", 1.8))
			var count: int = max(6, int(PI * r / tr))
			for i in count:
				var a := TAU * float(i) / float(count)
				hull.append({
					"center": Vector3(cos(a) * r, sin(a) * r, 0.0),
					"radius": tr * 1.5
				})
		elif part.kind == "ring_segment":
			var r: float = float(part.spec.get("radius", 20.0))
			var tr: float = float(part.spec.get("tube_radius", 2.0))
			var ca: float = float(part.spec.get("center_angle", 0.0))
			var span: float = float(part.spec.get("angle_span", PI * 0.25))
			var arc_len := r * span
			var count: int = max(2, int(arc_len / (tr * 1.5)))
			for i in count + 1:
				var t := float(i) / float(count)
				var a := ca - span * 0.5 + span * t
				hull.append({
					"center": Vector3(cos(a) * r, sin(a) * r, 0.0),
					"radius": tr * 1.2
				})
		else:
			hull = HullFit.spheres_for_box(part.aabb)
			
		out.append({
			"node": part.node,
			"hull": hull,
		})
	return out


## True if [param body] is currently parked at any of this craft's dock pads.
func is_body_docked(body: Node3D) -> bool:
	for pad in _dock_pads:
		if is_instance_valid(pad) and pad.is_docked(body):
			return true
	return false
