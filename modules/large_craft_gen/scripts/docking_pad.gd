## A parking spot on a large craft: ships that drift inside [member capture_radius]
## get gently pulled toward the pad's anchor (this node's own origin, +Z is the
## approach direction) and have their velocity damped as they close in, so
## coasting near a ramp reads as "parking", not just floating there — the same
## lerp-toward-target shape [FlightModel._apply_orbital_assist] uses for
## orbital capture, applied here to a landing spot instead of an orbit.
##
## Generic on purpose: it drives any [RigidBody3D] that enters, duck-typed on
## [member RigidBody3D.linear_velocity], so a real ship controller can dock at
## one of these later without this class knowing anything about ships.
class_name DockingPad
extends Area3D

## Bodies inside this radius get pulled toward the anchor.
@export var capture_radius := 8.0
## Once this close, velocity is damped toward zero instead of just redirected
## — "parked" rather than "orbiting the pad".
@export var park_radius := 1.5
## How hard the pull redirects velocity, per second (lerp factor).
@export var pull_rate := 1.5
## How hard velocity is damped toward zero once inside [member park_radius].
@export var park_damping := 2.5
## Metres/second the pad pulls an in-range body toward the anchor at.
@export var approach_speed := 6.0

signal body_docked(body: Node3D)
signal body_departed(body: Node3D)

## Guide chevrons hovering out along the approach axis, flowing toward the
## anchor in a loop — the "arrows pointing at the point that will pull you in
## for landing" cue a real approach needs, since nothing else about an empty
## Area3D reads as "dock here" from a distance.
const GUIDE_COUNT := 4
const GUIDE_SIZE := 0.9
## How fast one arrow completes a far-to-near loop, in seconds.
const GUIDE_LOOP_TIME := 1.6

var _docked: Dictionary = {}  # body/marker key -> true, so body_docked only fires once per visit
var _guides: MultiMeshInstance3D = null
var _guide_time := 0.0


func _ready() -> void:
	monitoring = true
	body_exited.connect(_on_body_exited)
	_build_guides()


func _physics_process(delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is RigidBody3D:
			_magnetize(body as RigidBody3D, delta)


func _process(delta: float) -> void:
	_animate_guides(delta)


func _magnetize(body: RigidBody3D, delta: float) -> void:
	body.linear_velocity = pull_point(body.global_position, body.linear_velocity, delta, body)


## [member capture_radius]/[member park_radius]/[member approach_speed] are
## authored as plain local-unit numbers, same as everything else on this
## pad — but a [LargeCraftGenerator] scaled up via
## [member LargeCraftGenerator.scale_mult] scales this pad's actual physical
## position and collision shape right along with it (ordinary Godot transform
## inheritance), while the exported numbers themselves obviously don't change.
## [method pull_point] compares against real world-space distances, so it has
## to scale those numbers back up first or a docked-to structure bigger than
## 1x silently never captures anything (the physical Area3D trigger zone
## grows with the structure; the math deciding whether to pull didn't, until
## this existed). Assumes uniform scale, which is all [LargeCraftGenerator]
## ever applies.
func _world_scale() -> float:
	return global_transform.basis.get_scale().x


## Pulls any flyer that exposes a position + velocity toward this pad without
## needing it to be a physics [RigidBody3D] Area3D can detect via overlap —
## [FlightModel] has no collider (see its own doc comment) and so never
## appears in [method Area3D.get_overlapping_bodies]. Returns the adjusted
## velocity; the caller writes it back onto whatever it came from. Same pull/
## park math [method _magnetize] already uses, generalised off a raw
## position/velocity pair. [param marker_key] identifies the flyer for the
## docked/departed bookkeeping (an Object works — a body, or the flyer's own
## model); pass null to skip docked-state tracking entirely.
func pull_point(position: Vector3, velocity: Vector3, delta: float, marker_key: Variant = null) -> Vector3:
	var s := _world_scale()
	var to_anchor := global_position - position
	var dist := to_anchor.length()
	if dist > capture_radius * s:
		if marker_key != null and _docked.has(marker_key):
			_docked.erase(marker_key)
			body_departed.emit(marker_key if marker_key is Node3D else null)
		return velocity
	var pulled := velocity
	if dist > park_radius * s:
		var target := to_anchor.normalized() * approach_speed * s
		pulled = pulled.lerp(target, clampf(delta * pull_rate, 0.0, 1.0))
	else:
		pulled = pulled.lerp(Vector3.ZERO, clampf(delta * park_damping, 0.0, 1.0))
		if marker_key != null and not _docked.has(marker_key):
			_docked[marker_key] = true
			body_docked.emit(marker_key if marker_key is Node3D else null)
	return pulled


func _on_body_exited(body: Node3D) -> void:
	if _docked.has(body):
		_docked.erase(body)
		body_departed.emit(body)


func is_docked(body: Node3D) -> bool:
	return _docked.has(body)


# --- Approach guide visuals --------------------------------------------------

## One small flattened-cone "arrow" mesh, instanced [constant GUIDE_COUNT]
## times along local +Z (the approach axis), each rotated to point its tip
## along local -Z — toward the anchor.
func _build_guides() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = GUIDE_SIZE * 0.5
	cone.height = GUIDE_SIZE
	cone.radial_segments = 4  # a stubby 4-sided arrowhead, not a smooth cone

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = GUIDE_COUNT
	for i in GUIDE_COUNT:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, 0, capture_radius)))

	_guides = MultiMeshInstance3D.new()
	_guides.name = "ApproachGuides"
	_guides.multimesh = mm
	_guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guides.material_override = ShipMaterials.glow_material(Color("6ff0d0"))
	add_child(_guides)


## Each arrow slides from [member capture_radius] down to [member park_radius]
## along local +Z and loops back out — a continuous flow toward the landing
## point rather than a static marker. Tip aimed along local -Z the whole time
## ([code]Basis(Vector3.RIGHT, -PI * 0.5)[/code] turns the cone's default +Y
## apex to -Z).
func _animate_guides(delta: float) -> void:
	if _guides == null or _guides.multimesh == null:
		return
	_guide_time += delta
	var mm: MultiMesh = _guides.multimesh
	var span := maxf(capture_radius - park_radius, 0.5)
	var point_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in GUIDE_COUNT:
		var phase := fposmod(_guide_time / GUIDE_LOOP_TIME + float(i) / float(GUIDE_COUNT), 1.0)
		var z := capture_radius - span * phase
		mm.set_instance_transform(i, Transform3D(point_basis, Vector3(0, 0, z)))
