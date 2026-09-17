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
## segment_count = hull segments along the spine. hull_width/hull_height_ratio
## /taper = cross-section and how much it narrows fore/aft. dock_arm_count/
## dock_arm_length = docking arms off the hull. spire_count/greeble_count =
## surface detail.
func _generate_mothership() -> void:
	var spine := _build_spine()
	_mount_dock_arms_on_spine(spine)
	_scatter_on_spine("spire", spire_count, spine, true)
	_scatter_on_spine("greeble_block", greeble_count, spine, false)


## {z: float, radius: float} per segment, hull-surface radius at that point
## along the spine — dock arms, spires and greebles mount off this.
func _build_spine() -> Array[Dictionary]:
	var half := float(segment_count) * SEGMENT_LENGTH * 0.5
	var sections: Array[Dictionary] = []
	# Linear taper (lerp from 1.0 to [member taper] across the run), not a
	# per-segment compounding multiply — at 80 segments even a gentle 0.9
	# per-segment taper compounds to 0.9^80 ≈ 0.0002 and the hull collapses
	# to a needle a few segments in. Linear keeps "last segment is `taper`
	# fraction of the first" true regardless of how many segments there are.
	var last := maxf(float(segment_count - 1), 1.0)
	for i in segment_count:
		var z := half - float(i) * SEGMENT_LENGTH - SEGMENT_LENGTH * 0.5
		var scale := lerpf(1.0, taper, float(i) / last)
		var width := hull_width * scale
		var height := width * hull_height_ratio
		var jitter := 1.0 + _rng.randf_range(-part_scale_jitter, part_scale_jitter)
		_add_part("hull_segment", {
			"length": SEGMENT_LENGTH * 1.02,  # slight overlap so segments don't gap at the seam
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
## Same tapered hull spine as the mothership — the "docking station" and the
## "warship" read as the same basic hull shape in the reference material, the
## difference is what's bolted to it and what it does once spawned (flight-
## side: moves under its own power and fires, see [FlightRoot]). segment_count/
## hull_width/hull_height_ratio/taper = spine, as the mothership. dock_arm_count/
## dock_arm_length = small hangar bays (repurposed from the mothership's own
## docking arms — a warship still launches fighters). spire_count = weapon
## turrets studding the hull (repurposed — bristling with guns reads better
## than antennae on something meant to fight). greeble_count = hull plating,
## as everywhere else.
func _generate_dreadnought() -> void:
	var spine := _build_spine()
	_mount_dock_arms_on_spine(spine)
	_mount_turrets_on_spine(spine)
	_mount_wings_and_tail(spine)
	_scatter_on_spine("greeble_block", greeble_count, spine, false)


## Wings + a tail fin — the actual "reads as a ship, not a tube with guns
## bolted on" silhouette; sized off the same hull_width/segment_count every
## other part on this archetype already reads, rather than adding yet more
## dials just for this. Wings mount a little aft of centre (clear of the
## bow's taper); the fin and a pair of smaller horizontal stabilizers sit at
## the stern.
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

	# A pair of smaller horizontal stabilizers flank the fin's base — the
	# main wings already proved the "wing" kind mirrors cleanly, so this is
	# just a scaled-down reuse rather than a new part kind.
	var stab_span := span * 0.35
	for side: float in [1.0, -1.0]:
		_add_part("wing", {
			"span": stab_span, "root_chord": root_chord * 0.45, "tip_chord": tip_chord * 0.6,
			"sweep": sweep * 0.5, "dihedral": 0.0, "thickness": thickness * 0.8, "side": side,
		}, Transform3D(Basis(), Vector3(side * stern_r * 0.5, stern_r * 0.25, stern_z)))


## Studs the hull with [member spire_count] weapon turrets and records each
## one's muzzle transform in [member _turrets] for [method get_turret_points].
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
## segment_count = ring wedge count (ring smoothness/detail). hull_width =
## hub radius and ring tube thickness. dock_arm_count/dock_arm_length = dock
## pads jutting from the ring's outer rim. spire_count = antennae on the rim.
## greeble_count = surface detail on the hub.
func _generate_ring_station() -> void:
	var hub_radius := hull_width * 0.6
	var ring_radius := maxf(hull_width * 4.0, hub_radius * 2.2)
	var tube_radius := maxf(hull_width * 0.18, 0.5)

	_add_part("dome", {"radius": hub_radius, "sides": 12, "steps": 6, "flip": 0.0}, Transform3D())
	_add_part("dome", {"radius": hub_radius, "sides": 12, "steps": 6, "flip": 1.0}, Transform3D())

	# Ring lies flat (hoop-normal along world Y): rotate the wedge's own
	# XY-plane convention 90° about X.
	var ring_basis := Basis(Vector3(1, 0, 0), PI * 0.5)
	var wedges := maxi(segment_count, 3)
	for i in wedges:
		var center_angle := TAU * float(i) / float(wedges)
		_add_part("ring_segment", {
			"center_angle": center_angle, "angle_span": TAU / float(wedges) * 1.02,
			"radius": ring_radius, "tube_radius": tube_radius, "sides": 8, "steps": 4,
		}, Transform3D(ring_basis, Vector3.ZERO))

	# Spokes: a handful regardless of wedge count, so a coarse ring still
	# reads as "a wheel", not just a hoop floating near a ball.
	var spoke_count := clampi(roundi(float(wedges) / 6.0), 3, 12)
	for i in spoke_count:
		var angle := TAU * float(i) / float(spoke_count)
		var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
		var mount := Vector3(dir_flat.x * hub_radius, 0.0, dir_flat.z * hub_radius)
		var xform := Transform3D(_radial_basis(dir_flat), mount)
		_add_part("strut", {"length": ring_radius - hub_radius, "thickness": tube_radius * 0.8}, xform, true)

	if dock_arm_count > 0:
		for i in dock_arm_count:
			var angle := TAU * float(i) / float(dock_arm_count) + _rng.randf_range(-0.15, 0.15)
			var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
			var mount := dir_flat * (ring_radius + tube_radius)
			_place_dock_arm(mount, dir_flat, _jittered(dock_arm_length))

	for i in spire_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dir_flat := Vector3(cos(angle), 0.0, sin(angle))
		var mount := dir_flat * (ring_radius + tube_radius)
		var height := _rng.randf_range(1.0, 3.0)
		_add_part("spire", {"height": height, "base_radius": 0.5, "sides": 6},
			Transform3D(_radial_up_basis(Vector3.UP), mount), true)

	for i in greeble_count:
		var angle := _rng.randf_range(0.0, TAU)
		var on_ring := _rng.randf() > 0.5
		var radius := (ring_radius if on_ring else hub_radius) + _rng.randf_range(0.2, 1.0)
		var pos := Vector3(cos(angle) * radius, _rng.randf_range(-hub_radius * 0.3, hub_radius * 0.3) if not on_ring else 0.0, sin(angle) * radius)
		var size := _rng.randf_range(0.3, 0.8)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size}, Transform3D(Basis(), pos), true)


# --- Gate frame (Archetype.GATE_FRAME) --------------------------------------
## segment_count = internal rings threaded through the frame. hull_width/
## hull_height_ratio = the opening's width/height. dock_arm_length = frame
## depth (also reused as the spacing that sets total length). dock_arm_count
## = dock pads mounted on the frame's outer beams. spire_count/greeble_count
## = surface detail on the beams.
func _generate_gate_frame() -> void:
	var width := hull_width * 2.0
	var height := hull_width * hull_height_ratio * 2.0
	var depth := maxf(dock_arm_length * float(maxi(segment_count, 1)) * 0.5, dock_arm_length)
	var hx := width * 0.5
	var hy := height * 0.5
	var hz := depth * 0.5
	var thickness := maxf(hull_width * 0.12, 0.4)

	# Four corner beams running the full depth.
	for corner in [Vector3(hx, hy, 0), Vector3(-hx, hy, 0), Vector3(hx, -hy, 0), Vector3(-hx, -hy, 0)]:
		_add_part("strut", {"length": depth, "thickness": thickness},
			Transform3D(Basis(), corner + Vector3(0, 0, hz)))
	# End-cap rectangles at front and back tie the corners together — each
	# beam aimed at its neighbour with [method _radial_basis] (local -Z -> dir)
	# rather than hand-composed rotations, the same trick every other aimed
	# part in this file already uses, so it's proven rather than guessed.
	for z in [hz, -hz]:
		var corners := [Vector3(hx, hy, z), Vector3(-hx, hy, z), Vector3(-hx, -hy, z), Vector3(hx, -hy, z)]
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var seg := b - a
			_add_part("strut", {"length": seg.length(), "thickness": thickness}, Transform3D(_radial_basis(seg.normalized()), a))

	# Internal rings, hoop facing Z (the gate's own fly-through axis) — no
	# extra rotation needed, unlike the ring station's flattened wheel.
	var ring_count := maxi(segment_count, 1)
	var ring_radius := minf(hx, hy) * 0.75
	var tube_radius := maxf(hull_width * 0.08, 0.25)
	for r in ring_count:
		var t := (float(r) + 0.5) / float(ring_count)
		var z := lerpf(hz, -hz, t)
		var wedges := 8
		for i in wedges:
			var center_angle := TAU * float(i) / float(wedges)
			_add_part("ring_segment", {
				"center_angle": center_angle, "angle_span": TAU / float(wedges) * 1.02,
				"radius": ring_radius, "tube_radius": tube_radius, "sides": 6, "steps": 3,
			}, Transform3D(Basis(), Vector3(0, 0, z)))

	if dock_arm_count > 0:
		for i in dock_arm_count:
			var side := 1.0 if i % 2 == 0 else -1.0
			var z := lerpf(hz * 0.6, -hz * 0.6, float(i / 2) / maxf(float(dock_arm_count / 2), 1.0))
			var dir_flat := Vector3(side, 0.0, 0.0)
			_place_dock_arm(Vector3(side * hx, 0.0, z), dir_flat, _jittered(dock_arm_length * 0.4))

	for i in spire_count:
		var corner := Vector3(hx if _rng.randf() > 0.5 else -hx, hy if _rng.randf() > 0.5 else -hy, _rng.randf_range(-hz, hz))
		_add_part("spire", {"height": _rng.randf_range(1.0, 2.5), "base_radius": 0.5, "sides": 5},
			Transform3D(_radial_up_basis((corner - Vector3(0, 0, corner.z)).normalized()), corner), true)

	for i in greeble_count:
		var corner := Vector3(hx if _rng.randf() > 0.5 else -hx, hy if _rng.randf() > 0.5 else -hy, _rng.randf_range(-hz, hz))
		var size := _rng.randf_range(0.3, 0.7)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size}, Transform3D(Basis(), corner), true)


# --- Tower cluster (Archetype.TOWER_CLUSTER) --------------------------------
## dock_arm_count = number of towers in the cluster (repurposed — a cluster
## reads better than one tower). segment_count = segments per tower (height).
## hull_width = tower cross-section. dock_arm_length unused here. spire_count
## /greeble_count = lit-window surface detail, the bulk of the look.
func _generate_tower_cluster() -> void:
	var tower_count := maxi(dock_arm_count, 1)
	var cluster_radius := hull_width * 0.9 * sqrt(float(tower_count))
	var towers: Array[Dictionary] = []  # {base: Vector3, top: Vector3, radius: float}
	for t in tower_count:
		var angle := TAU * float(t) / float(tower_count) + _rng.randf_range(-0.3, 0.3)
		var offset := (Vector3(cos(angle), 0, sin(angle)) * cluster_radius) if tower_count > 1 else Vector3.ZERO
		var tower_height := float(segment_count) * SEGMENT_LENGTH * (0.8 + _rng.randf_range(0.0, 0.6))
		var width := hull_width * (0.6 + _rng.randf_range(0.0, 0.5))
		var floors := maxi(int(tower_height / SEGMENT_LENGTH), 1)
		# Linear taper across the tower's height, same reasoning as
		# [method _build_spine] — a compounding `scale *= taper` per floor
		# pinches a tall tower to a needle well before its top.
		var last_floor := maxf(float(floors - 1), 1.0)
		for f in floors:
			var y := float(f) * SEGMENT_LENGTH + SEGMENT_LENGTH * 0.5
			var w := width * lerpf(1.0, taper, float(f) / last_floor)
			_add_part("hull_segment", {
				"length": SEGMENT_LENGTH * 1.02, "width": w, "height": w * hull_height_ratio,
				"corner": w * 0.15, "taper": 1.0,
			}, Transform3D(_radial_up_basis(Vector3.UP), offset + Vector3(0, y, 0)))
		towers.append({"base": offset, "top": offset + Vector3(0, floors * SEGMENT_LENGTH, 0), "radius": width * 0.5})

	# A thin central spar ties the cluster together visually, same idea as
	# the reference monolith's connecting spine.
	if towers.size() > 1:
		var tallest: Dictionary = towers[0]
		for tw in towers:
			if float(tw["top"].y) > float(tallest["top"].y):
				tallest = tw
		_add_part("strut", {"length": float(tallest["top"].y), "thickness": hull_width * 0.1},
			Transform3D(_radial_up_basis(Vector3.UP), Vector3(0, tallest["top"].y, 0)), true)

	if dock_arm_count > 0 and not towers.is_empty():
		var base_tower: Dictionary = towers[0]
		_place_dock_arm(Vector3(base_tower["base"]) + Vector3(0, SEGMENT_LENGTH, 0), Vector3.FORWARD, _jittered(dock_arm_length))

	for i in spire_count + greeble_count:
		if towers.is_empty():
			break
		var tower: Dictionary = towers[_rng.randi_range(0, towers.size() - 1)]
		var y := _rng.randf_range(0.0, float(tower["top"].y))
		var angle := _rng.randf_range(0.0, TAU)
		var r := float(tower["radius"])
		var pos := Vector3(tower["base"]) + Vector3(cos(angle) * r, y, sin(angle) * r)
		var size := _rng.randf_range(0.25, 0.7)
		_add_part(_random_greeble_kind(), {"sx": size, "sy": size, "sz": size},
			Transform3D(Basis(), pos + Vector3(cos(angle), 0, sin(angle)) * size * 0.4), true)


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
	part.local_xform = local_xform
	_parts[part.id] = part
	_next_id += 1
	return part.id


static var _mat_hull: ShaderMaterial = null
static var _mat_greeble: ShaderMaterial = null

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
		out.append({
			"node": part.node,
			"hull": HullFit.spheres_for_box(part.aabb),
		})
	return out


## True if [param body] is currently parked at any of this craft's dock pads.
func is_body_docked(body: Node3D) -> bool:
	for pad in _dock_pads:
		if is_instance_valid(pad) and pad.is_docked(body):
			return true
	return false
