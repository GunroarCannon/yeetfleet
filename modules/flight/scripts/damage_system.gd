## Modular ship damage and breakdown system.
##
## When the ship hits something fast enough, parts physically break off and the
## ship's stats change to reflect what was lost. Each part category has a set of
## [DamageEffect] entries that describe what happens when that kind of part is
## removed — thrust cut, control authority lost, speed reduced, etc. The effects
## stack additively, so losing both engines halves thrust while losing a wing
## AND a cockpit gives you speed loss AND total control loss.
##
## To add a new effect: add an entry to [enum EffectType], add a handler in
## [method _apply_effect], and register it in [method _effects_for_category].
## To make a new part category cause damage: add a branch in
## [method _effects_for_category] and give it a list of effects.
class_name DamageSystem
extends RefCounted


## The slowest a [constant EffectType.SPEED_PENALTY] may leave a ship, so a
## wrecked engine cripples it without stopping it dead. Scaled by the ship's own
## speed — see [member FlightModel.speed_scale] at the one place this is read: a
## floor fixed at 60 m/s would sit *above* the top speed of a ship the player had
## already slowed, and the penalty would silently stop doing anything at all.
const SPEED_PENALTY_FLOOR := 60.0


## Available effect types. Each one is a named modifier to the flight model.
## Adding a new effect here is the first step; the handler in [method
## _apply_effect] does the rest.
enum EffectType {
	## Halves main-engine thrust (cumulative — lose both and thrust is ~25%).
	THRUST_CUT,
	## Reduces top speed by a fraction.
	SPEED_PENALTY,
	## Reduces turn rate (control authority).
	CONTROL_LOSS,
	## Halves turn rate — severe control damage.
	CONTROL_HALF_LOST,
	## Total loss of steering — the ship can only fly straight or drift.
	CONTROL_TOTAL_LOST,
	## Boost becomes unavailable.
	BOOST_LOST,
	## Energy generation halved (lost a radiator or reactor part).
	POWER_CUT,
	## Weapon hardpoint or turret broken off.
	WEAPON_LOST,
	## The ship's mass drops slightly (lost a heavy piece), making it more
	## manoeuvrable but also more fragile-looking.
	MASS_REDUCTION,
	## A sensor, dish, antenna or nav part broken off: the radar goes dark.
	SENSORS_LOST,
}

## Words in a part's name that make it a sensor (see [enum EffectType] SENSORS_LOST).
const SENSOR_WORDS: Array[String] = ["NAV", "SENSOR", "DISH", "ANTENNA", "RADAR", "COMMS", "ARRAY", "MAST"]


## A single effect applied to the flight model.
class DamageEffect:
	## What kind of effect this is.
	var effect_type: EffectType = EffectType.THRUST_CUT
	## Strength: 0..1 fraction of the effect (0 = nothing, 1 = full penalty).
	## THRUST_CUT ignores this (always halves); SPEED_PENALTY uses it as a
	## multiplier on speed loss, etc.
	var strength: float = 0.5
	## Human-readable label for the HUD toast, e.g. "Thrust halved".
	var label: String = ""


## A part that was physically broken off, for visual and tracking purposes.
class BrokenPart:
	## The placement path of the original part (e.g. "wing_l").
	var path: String
	## The name of the part for the toast.
	var part_name: String
	## The world-space position where it broke off, for a debris node.
	var world_pos: Vector3
	## The direction the debris drifts away, normalised.
	var drift_dir: Vector3
	## Velocity the debris inherits from the ship.
	var drift_speed: float = 0.0
	## The actual part node, already moved to world space by _break_off.
	## FlightRoot uses this as the debris instead of creating a new box.
	var debris_node: Node3D = null


## Signal emitted when a part is broken off, so the HUD can show a toast and the
## flight root can spawn a debris node.
signal part_broken(broken: BrokenPart, effects: Array[DamageEffect])
## Signal emitted when cumulative effects change the model's effective stats,
## so the HUD can show a damage indicator.
signal damage_changed(total_effects: Array[DamageEffect])


## Accumulated effects, keyed by EffectType so only the worst case per type
## is kept (they do not stack for the same type).
var _active_effects: Dictionary = {}
## All effects applied in order, for display in the damage readout.
var _effect_list: Array[DamageEffect] = []
## The ship view, needed to find which node to remove visually.
var _view: ShipView = null
## Reference to the FlightModel, for reading stats.
var _model: FlightModel = null
## The hull holder node inside FlightModel, so broken nodes can be removed.
var _hull_holder: Node3D = null


func bind(view: ShipView, model: FlightModel, hull_holder: Node3D) -> void:
	_view = view
	_model = model
	_hull_holder = hull_holder
	_active_effects.clear()
	_effect_list.clear()


## Where broken-off debris is parented. Null means the model's own parent (the
## player's scene root). An AI ship sets its world host here: its model's
## parent is the AiShip node itself, and debris parented there would vanish
## the moment the dead ship is freed.
var debris_parent: Node = null


## Break off one random part that is still attached, weighted like [method
## handle_impact] (engines and cockpits likelier than greebles). Returns false
## when nothing breakable is left. [param severity] 0..1 goes to the effects.
func break_random_part(severity := 0.5) -> bool:
	if _view == null or _model == null:
		return false
	var candidates: Array = []
	for placement in _view.resolution.placements:
		# Only parts still on the hull. Placements are the design and never
		# shrink, so an already-lost part would otherwise be "lost" again.
		if placement.is_chassis() or not _view.part_nodes.has(placement.path):
			continue
		var weight := 1
		match placement.part.category:
			"engine": weight = 3
			"cockpit": weight = 3
			"weapon": weight = 2
			"wing": weight = 2
		for _w in weight:
			candidates.append(placement)
	if candidates.is_empty():
		return false
	_break_off(candidates.pick_random() as Placement, severity)
	return true


## Called by [method FlightModel._check_collision] when the ship hits something
## fast enough. Picks one or more random parts from the ship and breaks them off.
func handle_impact(impact_speed: float) -> void:
	if _view == null or _model == null:
		return
	var placements := _view.resolution.placements
	if placements.is_empty():
		return

	# Probability of losing a part scales with impact speed. At 30 m/s there is
	# a modest chance; at 80+ m/s it is nearly certain.
	var loss_chance := clampf((impact_speed - 30.0) / 60.0, 0.15, 0.95)
	# Number of parts at risk per impact scales too — a 100 m/s hit can rip
	# off more than one piece.
	var parts_at_risk := clampi(roundi(loss_chance * 2.5), 1, 4)

	var candidates: Array = []
	for placement in placements:
		# Never break the chassis — it is the ship.
		if placement.is_chassis():
			continue
		# Weight cosmetic parts less, critical parts more.
		var weight := 1.0
		if placement.part.category == "engine":
			weight = 2.5
		elif placement.part.category == "cockpit":
			weight = 3.0
		elif placement.part.category == "weapon":
			weight = 1.8
		elif placement.part.category == "greeble":
			weight = 0.4
		for _w in weight:
			candidates.append(placement)

	if candidates.is_empty():
		return

	candidates.shuffle()

	for i in mini(parts_at_risk, candidates.size()):
		var placement := candidates[i] as Placement
		_break_off(placement, loss_chance)


## Remove a single part and apply its effects.
func _break_off(placement: Placement, speed_fraction: float) -> void:
	var path := placement.path
	var part := placement.part
	var category := part.category

	# Record what was lost.
	var broken := BrokenPart.new()
	broken.path = path
	broken.part_name = part.display_name
	broken.world_pos = _model.global_position + _model.global_transform.basis * placement.xform.origin
	broken.drift_dir = -_model.global_transform.basis.z
	broken.drift_speed = _model.velocity.length() * 0.3 + randf_range(5.0, 20.0)

	# Remove the node visually by finding it in _view.part_nodes or _hull_holder.
	var node: Node3D = null
	if _view != null and _view.part_nodes.has(path):
		node = _view.part_nodes[path] as Node3D
	elif _hull_holder != null:
		var safe_name := "chassis" if path == "" else path.replace("/", "__")
		node = _hull_holder.get_node_or_null(safe_name) as Node3D

	if node != null and is_instance_valid(node):
		var orig_xform := node.global_transform
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		
		# Disable any pick Area3D inside the detached part so it doesn't intercept clicks
		for child in node.get_children():
			if child is Area3D:
				child.collision_layer = 0
				child.collision_mask = 0

		# Physical impulse away from the ship centre plus slight lateral tumble
		var out_dir := (orig_xform.origin - _model.global_position).normalized()
		if out_dir.length_squared() < 0.01:
			out_dir = -_model.global_transform.basis.z
		broken.drift_dir = (out_dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.4).normalized()
		broken.drift_speed = randf_range(14.0, 32.0)
		broken.world_pos = orig_xform.origin

		# Wrap into a collidable RigidBody3D so detached pieces become physical, collidable debris
		var base_vel: Vector3 = _model.velocity if _model != null else Vector3.ZERO
		var host: Node = debris_parent if debris_parent != null else _model.get_parent()
		var rb := DebrisRegistry.wrap_rigidbody(
			node, orig_xform, host,
			base_vel + broken.drift_dir * broken.drift_speed,
			Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
		)
		broken.debris_node = rb

	# Remove from the view registry, including pruning muzzles and exhausts
	if _view != null:
		_view.part_nodes.erase(path)
		_view.part_meshes.erase(path)
		_view.part_materials.erase(path)
		# A baked hull hides every part's own mesh and still carries this
		# part in its one combined mesh: show the flying piece, rebake without it.
		if _view.baked_mesh_instance != null and is_instance_valid(_view.baked_mesh_instance):
			_show_meshes(node)
			_view.baked_mesh_instance.queue_free()
			_view.baked_mesh_instance = null
			_view.enable_baked_mesh(true)

		# Prune muzzles belonging to this detached part so broken guns cannot fire:
		var filtered_muzzles: Array[Dictionary] = []
		for m in _view.muzzles:
			if m.get("path", "") != path:
				filtered_muzzles.append(m)
		_view.muzzles = filtered_muzzles

		# Prune exhausts belonging to this detached engine:
		var filtered_exhausts: Array[Dictionary] = []
		for e in _view.exhausts:
			if e.get("path", "") != path:
				filtered_exhausts.append(e)
		_view.exhausts = filtered_exhausts

	# Wing detachment causes asymmetric drag imbalance (pulls yaw and roll)
	if category == "wing" and _model != null:
		var is_left := placement.xform.origin.x < -0.15 or path.contains("_l") or path.contains("left")
		if is_left:
			_model.asymmetric_drag.z += 0.85
			_model.asymmetric_drag.y += 0.40
		else:
			_model.asymmetric_drag.z -= 0.85
			_model.asymmetric_drag.y -= 0.40

	# Compute effects.
	var effects := _effects_for_category(category, part)
	for eff in effects:
		_apply_effect(eff)

	part_broken.emit(broken, effects)
	damage_changed.emit(_effect_list)


## Return the damage effects for a given part category. This is the single
## place to add new part-to-damage mappings.
func _effects_for_category(category: String, part: ShipPart) -> Array[DamageEffect]:
	var out: Array[DamageEffect] = []
	if is_sensor(part):
		out.append(_make_effect(EffectType.SENSORS_LOST, 1.0, "Radar down — lost a sensor"))
	match category:
		"engine":
			out.append(_make_effect(EffectType.THRUST_CUT, 0.5, "Thrust halved — lost an engine"))
			out.append(_make_effect(EffectType.POWER_CUT, 0.3, "Power reduced — lost engine power"))
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.15, "Top speed reduced"))
		"cockpit":
			out.append(_make_effect(EffectType.CONTROL_HALF_LOST, 0.0, "Control severely degraded — lost cockpit systems"))
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.1, "Speed reduced — navigation systems damaged"))
		"weapon":
			out.append(_make_effect(EffectType.WEAPON_LOST, 1.0, "Weapon destroyed — gun mount lost"))
			out.append(_make_effect(EffectType.POWER_CUT, 0.15, "Power systems strained — lost weapon mount"))
		"wing":
			out.append(_make_effect(EffectType.CONTROL_LOSS, 0.4, "Turn rate reduced — lost a wing"))
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.08, "Top speed reduced — drag imbalance"))
		"armor":
			out.append(_make_effect(EffectType.MASS_REDUCTION, 0.2, "Mass reduced — lost armour plating"))
			out.append(_make_effect(EffectType.CONTROL_LOSS, 0.1, "Slight handling change — mass distribution shifted"))
		"cargo":
			out.append(_make_effect(EffectType.MASS_REDUCTION, 0.15, "Mass reduced — lost cargo pod"))
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.05, "Top speed slightly reduced"))
		"greeble":
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.03, "Minor damage — lost a sensor array"))
		_:
			out.append(_make_effect(EffectType.SPEED_PENALTY, 0.05, "Minor structural damage"))
	return out


func _make_effect(type: EffectType, strength: float, label: String) -> DamageEffect:
	var eff := DamageEffect.new()
	eff.effect_type = type
	eff.strength = strength
	eff.label = label
	return eff


## Apply one effect to the active effects dictionary and the flight model.
func _apply_effect(effect: DamageEffect) -> void:
	var key: int = effect.effect_type
	# Keep the worst effect of each type (strongest penalty wins).
	if _active_effects.has(key):
		var existing: DamageEffect = _active_effects[key]
		if effect.strength <= existing.strength:
			return  # existing is worse or equal
	_active_effects[key] = effect
	_effect_list.append(effect)

	# Directly modify the model's live values so the change is felt immediately.
	match effect.effect_type:
		EffectType.THRUST_CUT:
			_model.accel *= effect.strength
			if _model.accel < _model.top_speed * 0.05:
				_model.accel = _model.top_speed * 0.05
		EffectType.SPEED_PENALTY:
			_model.top_speed *= (1.0 - effect.strength)
			_model.top_speed = maxf(
				_model.top_speed, SPEED_PENALTY_FLOOR * _model.speed_scale
			)
		EffectType.CONTROL_LOSS:
			_model.turn_rate *= (1.0 - effect.strength)
			_model.turn_rate = maxf(_model.turn_rate, 0.1)
		EffectType.CONTROL_HALF_LOST:
			_model.turn_rate *= 0.5
			_model.turn_rate = maxf(_model.turn_rate, 0.05)
		EffectType.CONTROL_TOTAL_LOST:
			_model.turn_rate = 0.0
			_model.command.pitch = 0.0
			_model.command.yaw = 0.0
			_model.command.roll = 0.0
		EffectType.BOOST_LOST:
			_model.command.boost = false
		EffectType.POWER_CUT:
			pass  # SystemsSim handles energy; the model just feels it.
		EffectType.MASS_REDUCTION:
			# Lighter ship is faster per unit thrust but more fragile.
			_model.accel *= (1.0 + effect.strength * 0.5)
			_model.turn_rate *= (1.0 + effect.strength * 0.3)


## True when [param part] is a sensor by its name (a radiator array is not).
static func is_sensor(part: ShipPart) -> bool:
	var n := part.display_name.to_upper()
	if n.contains("RADIATOR"):
		return false
	for w in SENSOR_WORDS:
		if n.contains(w):
			return true
	return false


## True while an effect of [param type] is active.
func has_effect(type: EffectType) -> bool:
	return _active_effects.has(type)


## The full list of active damage effects, for the HUD damage readout.
func get_effects() -> Array[DamageEffect]:
	return _effect_list


## How many parts have been broken off.
func broken_count() -> int:
	return _effect_list.size()


## Reset all damage. Called by [method FlightRoot.respawn] or scene restart.
func reset() -> void:
	_active_effects.clear()
	_effect_list.clear()
	if _model != null:
		_model.asymmetric_drag = Vector3.ZERO
		_model.out_of_control = false
		_model._out_of_control_timer = 0.0


static func _show_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = true
		_show_meshes(child)


## Break off ALL remaining parts (used on total destruction / game over).
## Returns the list of all BrokenPart objects created.
func break_all_parts() -> Array[BrokenPart]:
	var out: Array[BrokenPart] = []
	if _view == null or _model == null:
		return out
	# Back from a baked hull to the parts, so the parts are what flies apart
	# (the baked mesh would otherwise hang on, whole, over invisible debris).
	if _view.baked_mesh_instance != null and is_instance_valid(_view.baked_mesh_instance):
		_view.enable_baked_mesh(false)
		_view.baked_mesh_instance.queue_free()
		_view.baked_mesh_instance = null
	var placements := _view.resolution.placements
	for placement in placements:
		var path := placement.path
		var node: Node3D = null
		if _view.part_nodes.has(path):
			node = _view.part_nodes[path] as Node3D
		elif _hull_holder != null:
			var safe_name := "chassis" if path == "" else path.replace("/", "__")
			node = _hull_holder.get_node_or_null(safe_name) as Node3D

		if node != null and is_instance_valid(node):
			var orig_xform := node.global_transform if node.is_inside_tree() else Transform3D()
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)

			for child in node.get_children():
				if child is Area3D:
					child.collision_layer = 0
					child.collision_mask = 0

			var broken := BrokenPart.new()
			broken.path = path
			broken.part_name = placement.part.display_name
			broken.world_pos = orig_xform.origin
			var out_dir := (orig_xform.origin - _model.global_position).normalized()
			if out_dir.length_squared() < 0.01:
				out_dir = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
			broken.drift_dir = (out_dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.5).normalized()
			broken.drift_speed = randf_range(18.0, 48.0)
			# Full-destruction wreckage gets the same real, collidable
			# RigidBody3D treatment as a mid-flight part loss (above) — this
			# used to be a bare decorative Node3D with no collision shape at
			# all, so a dead ship's pieces passed through everything.
			broken.debris_node = DebrisRegistry.wrap_rigidbody(
				node, orig_xform, _model.get_parent(),
				_model.velocity + broken.drift_dir * broken.drift_speed,
				Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)),
			)
			out.append(broken)

	_view.part_nodes.clear()
	_view.part_meshes.clear()
	_view.part_materials.clear()
	_view.muzzles.clear()
	_view.exhausts.clear()
	return out
