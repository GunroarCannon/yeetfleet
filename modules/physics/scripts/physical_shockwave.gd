class_name PhysicalShockwave
extends Node3D

## An expanding physical and visual shockwave that exerts radial impulse,
## angular spin, and distance falloff damage to all entities in its path over time.

signal wave_finished()

@export var max_radius := 1200.0
@export var duration := 2.5
@export var peak_force := 450.0
@export var peak_torque := 14.0
@export var peak_damage := 180.0
@export var wave_color := Color(1.0, 0.65, 0.25)
@export var shell_thickness := 50.0

var _elapsed := 0.0
var _current_radius := 0.0
var _hit_objects: Dictionary = {}

var _ring1: MeshInstance3D
var _ring2: MeshInstance3D
var _sphere: MeshInstance3D
var _ring1_mat: StandardMaterial3D
var _ring2_mat: StandardMaterial3D
var _sphere_mat: StandardMaterial3D


static func create(
	parent: Node,
	origin: Vector3,
	radius: float,
	force: float = 400.0,
	torque: float = 12.0,
	damage: float = 150.0,
	color: Color = Color(1.0, 0.65, 0.25),
	wave_duration: float = 2.4
) -> PhysicalShockwave:
	var sw := PhysicalShockwave.new()
	sw.max_radius = radius
	sw.peak_force = force
	sw.peak_torque = torque
	sw.peak_damage = damage
	sw.wave_color = color
	sw.duration = wave_duration
	sw.top_level = true
	sw.position = origin
	parent.add_child(sw)
	return sw


func _ready() -> void:
	_setup_visuals()


func _setup_visuals() -> void:
	# Equatorial razor-thin torus ring
	_ring1 = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 16
	_ring1.mesh = tm
	
	_ring1_mat = StandardMaterial3D.new()
	_ring1_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring1_mat.albedo_color = wave_color
	_ring1_mat.emission_enabled = true
	_ring1_mat.emission = wave_color
	_ring1_mat.emission_energy_multiplier = 6.0
	_ring1_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring1_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring1.material_override = _ring1_mat
	_ring1.scale = Vector3(0.01, 0.1, 0.01)
	add_child(_ring1)

	# 45-degree oblique secondary ring
	_ring2 = MeshInstance3D.new()
	_ring2.mesh = tm
	_ring2_mat = _ring1_mat.duplicate() as StandardMaterial3D
	_ring2.material_override = _ring2_mat
	_ring2.rotation = Vector3(PI * 0.25, PI * 0.25, 0.0)
	_ring2.scale = Vector3(0.01, 0.1, 0.01)
	add_child(_ring2)

	# Translucent 3D spherical wavefront
	_sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_sphere.mesh = sm
	
	_sphere_mat = StandardMaterial3D.new()
	_sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sphere_mat.albedo_color = Color(wave_color.r, wave_color.g, wave_color.b, 0.25)
	_sphere_mat.emission_enabled = true
	_sphere_mat.emission = wave_color
	_sphere_mat.emission_energy_multiplier = 2.0
	_sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sphere_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sphere.material_override = _sphere_mat
	_sphere.scale = Vector3(0.01, 0.01, 0.01)
	add_child(_sphere)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	var ease_t := 1.0 - pow(1.0 - t, 2.5)
	_current_radius = max_radius * ease_t

	var alpha := (1.0 - t) * (1.0 - t)
	if _ring1 != null:
		_ring1.scale = Vector3(_current_radius, maxf(1.0, _current_radius * 0.01), _current_radius)
		_ring1_mat.albedo_color.a = alpha * 0.95
	if _ring2 != null:
		_ring2.scale = Vector3(_current_radius * 0.92, maxf(1.0, _current_radius * 0.01), _current_radius * 0.92)
		_ring2_mat.albedo_color.a = alpha * 0.85
	if _sphere != null:
		_sphere.scale = Vector3(_current_radius, _current_radius, _current_radius)
		_sphere_mat.albedo_color.a = alpha * 0.18

	_propagate_physical_wave()

	if t >= 1.0:
		wave_finished.emit()
		queue_free()


func _propagate_physical_wave() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return

	var epicentre := global_position
	var nodes_to_check: Array[Node] = []
	
	for n in tree.get_nodes_in_group("flight_models"):
		nodes_to_check.append(n)
	for n in tree.get_nodes_in_group("ai_ships"):
		nodes_to_check.append(n)
	for n in tree.get_nodes_in_group("rigid_bodies"):
		nodes_to_check.append(n)

	# Direct 3D physics broadphase query for nearby colliders (much faster than recursive tree walks)
	var w3d := get_world_3d()
	if w3d != null:
		var space_state := w3d.direct_space_state
		if space_state != null:
			var query := PhysicsShapeQueryParameters3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = minf(_current_radius + shell_thickness, max_radius)
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, epicentre)
			query.collide_with_bodies = true
			query.collide_with_areas = false
			var hits := space_state.intersect_shape(query, 32)
			for hit in hits:
				var collider = hit.get("collider")
				if collider is Node and not nodes_to_check.has(collider):
					nodes_to_check.append(collider)

	for obj in nodes_to_check:
		if not is_instance_valid(obj):
			continue
		var id := obj.get_instance_id()
		if _hit_objects.has(id):
			continue

		var node3d := obj as Node3D
		if node3d == null or not node3d.is_inside_tree():
			continue

		var target_pos := node3d.global_position
		var diff := target_pos - epicentre
		var dist := diff.length()

		# Hit when the expanding wavefront reaches the target
		if dist <= _current_radius + shell_thickness:
			_hit_objects[id] = true
			var falloff := 1.0 - clampf(dist / max_radius, 0.0, 1.0)
			var intensity := falloff * falloff
			var push_dir := diff.normalized() if dist > 0.01 else Vector3.UP

			# 1. FlightModel / Player Ship:
			if obj is FlightModel:
				var fm := obj as FlightModel
				fm.apply_radial_blast(epicentre, max_radius, peak_force, peak_torque)
			elif obj.has_method("apply_radial_blast"):
				obj.call("apply_radial_blast", epicentre, max_radius, peak_force, peak_torque)
			
			# 2. AiShip:
			if obj is AiShip:
				var ai := obj as AiShip
				ai.take_damage(peak_damage * intensity)
				if ai.get("model") != null and ai.model != null:
					ai.model.apply_radial_blast(epicentre, max_radius, peak_force, peak_torque)

			# 3. RigidBody3D (debris, asteroids, craft pieces):
			if obj is RigidBody3D:
				var rb := obj as RigidBody3D
				rb.apply_central_impulse(push_dir * (peak_force * intensity * 15.0))
				var r_axis := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
				rb.apply_torque_impulse(r_axis * (peak_torque * intensity * 25.0))

			# 4. Large craft generator:
			if obj is LargeCraftGenerator:
				(obj as LargeCraftGenerator).shatter_at(target_pos, 45.0 * intensity, push_dir * (peak_force * intensity))
