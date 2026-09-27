class_name ExplosionRegistry
extends RefCounted

## ExplosionRegistry: Central manager and repository for explosion visual effects.
## Maps in-game destruction events to specific visual assets or procedural recipes,
## and saves/loads assignments to/from disk.

const ASSIGNMENTS_PATH := "res://data/effects/explosion_assignments.json"
const USER_ASSIGNMENTS_PATH := "user://explosion_assignments.json"

## Standard Game Event Slots that trigger explosions
const SLOT_SHIP_DEATH := "ship_death"
const SLOT_CAPITAL_DEATH := "capital_ship_death"
const SLOT_PLANET_IMPACT := "planet_impact"
const SLOT_MISSILE_BLAST := "missile_blast"
const SLOT_NOVA_NUKE := "nova_nuke"
const SLOT_PLASMA_BURST := "plasma_burst"
const SLOT_SINGULARITY := "singularity_collapse"
const SLOT_SHIELD_OVERLOAD := "shield_overload"
const SLOT_PART_BREAKOFF := "part_breakoff"

const ALL_SLOTS := [
	SLOT_SHIP_DEATH,
	SLOT_CAPITAL_DEATH,
	SLOT_PLANET_IMPACT,
	SLOT_MISSILE_BLAST,
	SLOT_NOVA_NUKE,
	SLOT_PLASMA_BURST,
	SLOT_SINGULARITY,
	SLOT_SHIELD_OVERLOAD,
	SLOT_PART_BREAKOFF,
]

## Information about each slot for UI presentation
const SLOT_META := {
	SLOT_SHIP_DEATH: {
		"name": "Ship Hull Destruction",
		"desc": "Standard fighter or civilian craft destruction explosion",
		"default_effect": "binbun_air_explosion",
		"default_scale": 1.4,
		"default_sound": "hit",
	},
	SLOT_CAPITAL_DEATH: {
		"name": "Capital Ship Cataclysm",
		"desc": "Massive multi-stage breakup for dreadnoughts and stations",
		"default_effect": "binbun_nuke",
		"default_scale": 4.5,
		"default_sound": "warp",
	},
	SLOT_PLANET_IMPACT: {
		"name": "Planet & Asteroid Impact",
		"desc": "Detonation when heavy munitions or ships collide with celestial bodies",
		"default_effect": "binbun_ground_explosion",
		"default_scale": 2.2,
		"default_sound": "railgun",
	},
	SLOT_MISSILE_BLAST: {
		"name": "Missile Warhead Blast",
		"desc": "Standard kinetic and explosive missile warhead detonation",
		"default_effect": "binbun_impact_01",
		"default_scale": 1.2,
		"default_sound": "missile",
	},
	SLOT_NOVA_NUKE: {
		"name": "Nova Torpedo / Thermonuclear",
		"desc": "Heavy capital-grade thermonuclear torpedo detonation",
		"default_effect": "binbun_nuke",
		"default_scale": 3.0,
		"default_sound": "jingle_lose",
	},
	SLOT_PLASMA_BURST: {
		"name": "Plasma Cannon Detonation",
		"desc": "Superheated plasma bolt impact and splash explosion",
		"default_effect": "procedural_plasma_bomb",
		"default_scale": 1.6,
		"default_sound": "plasma",
	},
	SLOT_SINGULARITY: {
		"name": "Singularity Collapse",
		"desc": "Micro-black hole implosion followed by violent spacetime burst",
		"default_effect": "procedural_singularity",
		"default_scale": 2.5,
		"default_sound": "ambience_blackhole",
	},
	SLOT_SHIELD_OVERLOAD: {
		"name": "Shield Overload / EMP",
		"desc": "High-voltage electrical discharge when deflector shields collapse",
		"default_effect": "binbun_ball_lightning",
		"default_scale": 1.8,
		"default_sound": "alarm",
	},
	SLOT_PART_BREAKOFF: {
		"name": "Part Breakoff Flash",
		"desc": "Small localized blast when an individual wing or engine is sheared off",
		"default_effect": "binbun_hit_01",
		"default_scale": 0.8,
		"default_sound": "hit",
	},
}

## Catalog of all known explosion effects (authored addon assets + procedural recipes)
static var _catalog: Dictionary = {}
static var _assignments: Dictionary = {}
static var _initialized: bool = false
static var _scene_cache: Dictionary = {}

static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_build_catalog()
	load_assignments()

static func _build_catalog() -> void:
	_catalog.clear()
	
	# --- BinbunVFX Vol 2 Addon Assets ---
	_register_effect({
		"id": "binbun_air_explosion",
		"name": "Binbun · Air Explosion 01",
		"pack": "BinbunVFX Vol 2 (ExplosionFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/ExplosionFX/effects/air/vfx_air_explosion_01.tscn",
		"desc": "Volumetric expanding fireball with smoke plumes, shockwave disc, and sparks",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.55, 0.15),
		"default_sound": "hit",
	})
	_register_effect({
		"id": "binbun_ground_explosion",
		"name": "Binbun · Ground Explosion 01",
		"pack": "BinbunVFX Vol 2 (ExplosionFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn",
		"desc": "Directional cratering explosion blast with upward debris and hemispherical shock",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.60, 0.20),
		"default_sound": "railgun",
	})
	_register_effect({
		"id": "binbun_nuke",
		"name": "Binbun · Nuke Explosion 01",
		"pack": "BinbunVFX Vol 2 (ExplosionFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn",
		"desc": "Huge tactical thermonuclear mushroom cloud with double shockwave rings and blinding flash",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.70, 0.30),
		"default_sound": "jingle_lose",
	})
	_register_effect({
		"id": "binbun_big_impact_01",
		"name": "Binbun · Big Impact 01",
		"pack": "BinbunVFX Vol 2 (StylizedHitFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
		"desc": "Heavy stylized impact blast with radial energy spokes and corona flare",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.85, 0.25),
		"default_sound": "railgun",
	})
	_register_effect({
		"id": "binbun_big_impact_02",
		"name": "Binbun · Big Impact 02",
		"pack": "BinbunVFX Vol 2 (StylizedHitFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
		"desc": "High-energy concussive blast with spinning diamond sparks and particle burst",
		"default_scale": 1.0,
		"default_color": Color(0.9, 0.4, 1.0),
		"default_sound": "railgun",
	})
	_register_effect({
		"id": "binbun_impact_01",
		"name": "Binbun · Impact 01",
		"pack": "BinbunVFX Vol 2 (StylizedHitFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
		"desc": "Medium-caliber ordnance impact with bright cross flare and flying sparks",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.8, 0.3),
		"default_sound": "hit",
	})
	_register_effect({
		"id": "binbun_hit_01",
		"name": "Binbun · Light Hit 01",
		"pack": "BinbunVFX Vol 2 (StylizedHitFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
		"desc": "Compact point impact burst for localized component strikes",
		"default_scale": 1.0,
		"default_color": Color(1.0, 0.9, 0.4),
		"default_sound": "hit",
	})
	_register_effect({
		"id": "binbun_ball_lightning",
		"name": "Binbun · Ball Lightning 01",
		"pack": "BinbunVFX Vol 2 (ElectricFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/ElectricFX/effects/ball/vfx_ball_lightning_01.tscn",
		"desc": "High-voltage spherical plasma orb with arcing electric tendrils",
		"default_scale": 1.0,
		"default_color": Color(0.2, 0.85, 1.0),
		"default_sound": "alarm",
	})
	_register_effect({
		"id": "binbun_zap",
		"name": "Binbun · Electric Zap 01",
		"pack": "BinbunVFX Vol 2 (ElectricFX)",
		"type": "addon_scene",
		"path": "res://addons/BinbunVFX_Vol2/ElectricFX/effects/zap/vfx_zap_lightning_01.tscn",
		"desc": "Sudden jagged electric discharge arc with energetic sparks",
		"default_scale": 1.0,
		"default_color": Color(0.3, 0.9, 1.0),
		"default_sound": "hit",
	})

	# --- Procedural Juice Recipes ---
	_register_effect({
		"id": "procedural_fireball",
		"name": "Juice · Multi-Sphere Fireball",
		"pack": "Procedural Juice System",
		"type": "procedural",
		"path": "",
		"desc": "Multi-sphere expanding fireball cluster with glowing incandescent core, smoke, and light pop",
		"default_scale": 1.5,
		"default_color": Color(1.0, 0.45, 0.10),
		"default_sound": "hit",
	})
	_register_effect({
		"id": "procedural_plasma_bomb",
		"name": "Juice · Plasma Nova Burst",
		"pack": "Procedural Juice System",
		"type": "procedural",
		"path": "",
		"desc": "Expanding electric cyan/green plasma shell with high-energy ring sparks and intense light pop",
		"default_scale": 1.6,
		"default_color": Color(0.1, 0.95, 0.85),
		"default_sound": "plasma",
	})
	_register_effect({
		"id": "procedural_singularity",
		"name": "Juice · Gravitational Implosion",
		"pack": "Procedural Juice System",
		"type": "procedural",
		"path": "",
		"desc": "Spacetime collapse drawing matter inward followed by an explosive antimatter rebound",
		"default_scale": 2.2,
		"default_color": Color(0.65, 0.1, 0.95),
		"default_sound": "ambience_blackhole",
	})
	_register_effect({
		"id": "procedural_supernova",
		"name": "Juice · Supernova Starburst",
		"pack": "Procedural Juice System",
		"type": "procedural",
		"path": "",
		"desc": "Colossal stellar blast wave with multi-ring shockwaves, white core pop, and flying debris",
		"default_scale": 3.5,
		"default_color": Color(1.0, 0.85, 0.3),
		"default_sound": "warp",
	})
	_register_effect({
		"id": "vector_shatter",
		"name": "Vector · Neon Wireframe Burst",
		"pack": "Style Module (Vector Arcade)",
		"type": "procedural",
		"path": "",
		"desc": "Retro arcade wireframe polyhedral explosion with exploding glowing line shards, diamonds, and crosses",
		"default_scale": 1.8,
		"default_color": Color(0.0, 0.95, 1.0),
		"default_sound": "laser",
	})

static func _register_effect(data: Dictionary) -> void:
	_catalog[data["id"]] = data

static func get_catalog() -> Dictionary:
	ensure_initialized()
	return _catalog

static func get_effect(id: String) -> Dictionary:
	ensure_initialized()
	return _catalog.get(id, {})

static func get_effect_ids() -> Array:
	ensure_initialized()
	return _catalog.keys()

static func get_slot_assignment(slot: String) -> Dictionary:
	ensure_initialized()
	if _assignments.has(slot):
		return _assignments[slot]
	return _get_default_slot_assignment(slot)

static func set_slot_assignment(slot: String, data: Dictionary) -> void:
	ensure_initialized()
	_assignments[slot] = data

static func _get_default_slot_assignment(slot: String) -> Dictionary:
	var meta: Dictionary = SLOT_META.get(slot, {})
	var eff_id: String = String(meta.get("default_effect", "binbun_air_explosion"))
	var eff_def := get_effect(eff_id)
	return {
		"effect_id": eff_id,
		"scale": float(meta.get("default_scale", 1.0)),
		"color": eff_def.get("default_color", Color(1.0, 0.6, 0.2)),
		"sound": String(meta.get("default_sound", "hit")),
		"shockwave": true,
		"debris": true,
		"shake": 0.4,
	}

## Loads assignments from disk (JSON), falling back to defaults if not present
static func load_assignments() -> void:
	_assignments.clear()
	var path_to_load := ""
	if FileAccess.file_exists(USER_ASSIGNMENTS_PATH):
		path_to_load = USER_ASSIGNMENTS_PATH
	elif FileAccess.file_exists(ASSIGNMENTS_PATH):
		path_to_load = ASSIGNMENTS_PATH
	
	if path_to_load != "":
		var file := FileAccess.open(path_to_load, FileAccess.READ)
		if file != null:
			var json_text := file.get_as_text()
			var parsed: Variant = JSON.parse_string(json_text)
			if parsed is Dictionary:
				for slot in ALL_SLOTS:
					if parsed.has(slot) and parsed[slot] is Dictionary:
						var entry: Dictionary = parsed[slot]
						var c_raw: Variant = entry.get("color", null)
						var col: Color = Color(1.0, 0.6, 0.2)
						if c_raw is Array and c_raw.size() >= 3:
							col = Color(float(c_raw[0]), float(c_raw[1]), float(c_raw[2]), float(c_raw[3]) if c_raw.size() > 3 else 1.0)
						elif c_raw is String:
							col = Color.from_string(c_raw, Color.WHITE)
						_assignments[slot] = {
							"effect_id": String(entry.get("effect_id", "binbun_air_explosion")),
							"scale": float(entry.get("scale", 1.0)),
							"color": col,
							"sound": String(entry.get("sound", "hit")),
							"shockwave": bool(entry.get("shockwave", true)),
							"debris": bool(entry.get("debris", true)),
							"shake": float(entry.get("shake", 0.4)),
						}
	
	# Fill in any missing slots with defaults
	for slot in ALL_SLOTS:
		if not _assignments.has(slot):
			_assignments[slot] = _get_default_slot_assignment(slot)

## Saves current assignments to JSON file
static func save_assignments() -> bool:
	ensure_initialized()
	var out_dict := {}
	for slot in ALL_SLOTS:
		var a: Dictionary = _assignments.get(slot, _get_default_slot_assignment(slot))
		var col: Color = a.get("color", Color.WHITE)
		out_dict[slot] = {
			"effect_id": String(a.get("effect_id", "binbun_air_explosion")),
			"scale": float(a.get("scale", 1.0)),
			"color": [col.r, col.g, col.b, col.a],
			"sound": String(a.get("sound", "hit")),
			"shockwave": bool(a.get("shockwave", true)),
			"debris": bool(a.get("debris", true)),
			"shake": float(a.get("shake", 0.4)),
		}
	
	var json_str := JSON.stringify(out_dict, "  ")
	
	# Ensure directory exists
	var dir := "res://data/effects"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	
	var res_file := FileAccess.open(ASSIGNMENTS_PATH, FileAccess.WRITE)
	var success := false
	if res_file != null:
		res_file.store_string(json_str)
		res_file.close()
		success = true
	
	var user_file := FileAccess.open(USER_ASSIGNMENTS_PATH, FileAccess.WRITE)
	if user_file != null:
		user_file.store_string(json_str)
		user_file.close()
		success = true
	
	return success

## Load a built-in thematic preset template
static func apply_preset_template(preset_name: String) -> void:
	ensure_initialized()
	match preset_name:
		"retro_vector":
			for slot in ALL_SLOTS:
				_assignments[slot] = {
					"effect_id": "vector_shatter",
					"scale": 1.6,
					"color": Color(0.0, 0.95, 1.0) if slot != SLOT_NOVA_NUKE else Color(1.0, 0.15, 0.45),
					"sound": "laser",
					"shockwave": true,
					"debris": true,
					"shake": 0.4,
				}
		"anime_stylized":
			for slot in ALL_SLOTS:
				var eff := "binbun_big_impact_01" if slot == SLOT_PLANET_IMPACT else ("binbun_impact_01" if slot == SLOT_PART_BREAKOFF else "binbun_air_explosion")
				_assignments[slot] = {
					"effect_id": eff,
					"scale": 1.5,
					"color": Color(1.0, 0.85, 0.2),
					"sound": "railgun",
					"shockwave": true,
					"debris": true,
					"shake": 0.5,
				}
		"heavy_cinema":
			for slot in ALL_SLOTS:
				var eff := "binbun_nuke" if (slot == SLOT_CAPITAL_DEATH or slot == SLOT_NOVA_NUKE) else "binbun_ground_explosion"
				_assignments[slot] = {
					"effect_id": eff,
					"scale": 2.2,
					"color": Color(1.0, 0.55, 0.1),
					"sound": "warp",
					"shockwave": true,
					"debris": true,
					"shake": 0.7,
				}
		_: # "default"
			for slot in ALL_SLOTS:
				_assignments[slot] = _get_default_slot_assignment(slot)

## Spawns the assigned explosion for a game event slot
static func spawn_event(parent: Node3D, slot: String, pos: Vector3, normal: Vector3 = Vector3.UP, scale_mult: float = 1.0, color_override: Variant = null) -> Node3D:
	ensure_initialized()
	var a := get_slot_assignment(slot)
	var eff_id: String = String(a.get("effect_id", "binbun_air_explosion"))
	var base_scale: float = float(a.get("scale", 1.0)) * scale_mult
	var col: Color = color_override if (color_override is Color) else a.get("color", Color(1.0, 0.6, 0.2))
	var sound_id: String = String(a.get("sound", "hit"))
	var shockwave: bool = bool(a.get("shockwave", true))
	var debris: bool = bool(a.get("debris", true))
	var shake: float = float(a.get("shake", 0.4))
	
	# Scaled by how close it is: a blast out in the world used to rattle the
	# player's camera wherever it went off.
	shake *= AddonVfx.camera_falloff(pos, 600.0)
	if shake > 0.01:
		Juice.shake(shake)
	
	return spawn_effect(parent, eff_id, pos, normal, base_scale, col, sound_id, shockwave, debris)

## Spawns an explosion effect by its unique effect ID
static func spawn_effect(
	parent: Node3D,
	effect_id: String,
	pos: Vector3,
	normal: Vector3 = Vector3.UP,
	scale: float = 1.0,
	color: Color = Color.WHITE,
	sound_id: String = "",
	with_shockwave: bool = false,
	with_debris: bool = false
) -> Node3D:
	ensure_initialized()
	if parent == null or not is_instance_valid(parent):
		return null
	if not AddonVfx.worth_spawning(pos):
		return null
	
	var def := get_effect(effect_id)
	var effect_type: String = String(def.get("type", "procedural"))
	var root_inst: Node3D = null
	
	if effect_type == "addon_scene":
		var scene_path: String = String(def.get("path", ""))
		root_inst = _instantiate_addon_scene(scene_path, color, scale)
	elif effect_type == "procedural":
		root_inst = _create_procedural_effect(effect_id, color, scale)
	
	if root_inst == null:
		# Fallback to basic fireball
		root_inst = _create_procedural_fireball(color, scale)
	
	parent.add_child(root_inst)
	root_inst.global_position = pos
	if normal.length_squared() > 0.01 and absf(normal.dot(Vector3.UP)) < 0.99:
		root_inst.look_at_from_position(pos, pos + normal, Vector3.UP)
	
	# Light flash pop
	Juice.light_pop(pos, color, maxf(12.0, scale * 18.0), 0.4)
	
	# Optional shockwave ring
	if with_shockwave:
		var xform := Transform3D(Basis(), pos)
		Juice.ring(xform, scale * 3.5, color, 0.45)
	
	# Optional embers / sparks debris
	if with_debris:
		var xf := Transform3D(Basis(), pos)
		Juice.burst(BurstPresets.Preset.SPARKS, xf, scale * 1.5, Color.WHITE)
		Juice.burst(BurstPresets.Preset.EMBERS, xf, scale * 1.8, color)
		Juice.burst(BurstPresets.Preset.DEBRIS, xf, scale * 1.2)
	
	# Optional sound
	var sid := sound_id if sound_id != "" else String(def.get("default_sound", ""))
	if sid != "":
		_play_spatial_sound(parent, pos, sid)
	
	return root_inst

static func _instantiate_addon_scene(path: String, color: Color, scale: float) -> Node3D:
	if path == "":
		return null
	var packed: PackedScene = _scene_cache.get(path, null)
	if packed == null:
		if ResourceLoader.exists(path):
			packed = load(path) as PackedScene
			if packed != null:
				_scene_cache[path] = packed
	if packed == null:
		return null
	
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		return null
	
	var node := inst as Node3D
	node.scale = Vector3.ONE * maxf(0.01, scale)
	
	# Look for AnimationPlayer to play the explosion one-shot
	var anim_player: AnimationPlayer = null
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is AnimationPlayer and anim_player == null:
			anim_player = cur
		# Apply particle tint color to materials
		if cur is GPUParticles3D or cur is CPUParticles3D:
			cur.emitting = true
		for child in cur.get_children():
			stack.append(child)
	
	if anim_player != null and anim_player.has_animation("play"):
		anim_player.play("play")
	elif anim_player != null and anim_player.get_animation_list().size() > 0:
		anim_player.play(anim_player.get_animation_list()[0])
	
	# Auto free after animation or backstop timeout
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var max_life := 3.5
		if anim_player != null and anim_player.current_animation != "":
			var a := anim_player.get_animation(anim_player.current_animation)
			if a != null:
				max_life = maxf(1.0, a.length + 0.3)
		# A bound method, not a lambda holding [code]node[/code]: the effect is
		# often freed first (with the ship it hung off), and a lambda's freed
		# capture errored when the timer fired. A bound call just disconnects.
		var timer := tree.create_timer(max_life)
		timer.timeout.connect(node.queue_free)
	return node

static func _create_procedural_effect(recipe_id: String, color: Color, scale: float) -> Node3D:
	match recipe_id:
		"procedural_fireball":
			return _create_procedural_fireball(color, scale)
		"procedural_plasma_bomb":
			return _create_procedural_plasma(color, scale)
		"procedural_singularity":
			return _create_procedural_singularity(color, scale)
		"procedural_supernova":
			return _create_procedural_supernova(color, scale)
		"vector_shatter":
			return _create_vector_shatter(color, scale)
		_:
			return _create_procedural_fireball(color, scale)

static func _create_procedural_fireball(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralFireball"
	
	# Expanding fireball cluster
	for i in 4:
		var sphere := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r_base := (3.0 + float(i) * 1.2) * scale
		sm.radius = r_base
		sm.height = r_base * 2.0
		sphere.mesh = sm
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var c_tint := color if i == 0 else Color(color.r * 1.1, color.g * 0.6, color.b * 0.2, 0.8)
		mat.albedo_color = c_tint
		sphere.material_override = mat
		
		var offset := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * (scale * 1.5)
		sphere.position = offset
		sphere.scale = Vector3.ONE * 0.2
		root.add_child(sphere)
		
		var tw := sphere.create_tween().set_parallel(true)
		tw.tween_property(sphere, "scale", Vector3.ONE * 1.2, 0.45 + float(i) * 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.65 + float(i) * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t := tree.create_timer(1.2)
		t.timeout.connect(root.queue_free)
	return root

static func _create_procedural_plasma(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralPlasma"
	
	# Electric core sphere
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.0 * scale
	sm.height = 8.0 * scale
	core.mesh = sm
	var c_mat := StandardMaterial3D.new()
	c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	c_mat.albedo_color = Color.WHITE * 2.5
	core.material_override = c_mat
	core.scale = Vector3.ONE * 0.1
	root.add_child(core)
	
	# Outer expanding plasma shell
	var shell := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 6.0 * scale
	s_mesh.height = 12.0 * scale
	shell.mesh = s_mesh
	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s_mat.albedo_color = color * 1.8
	shell.material_override = s_mat
	shell.scale = Vector3.ONE * 0.1
	root.add_child(shell)
	
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE * 1.4, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c_mat, "albedo_color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(shell, "scale", Vector3.ONE * 2.2, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s_mat, "albedo_color:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t := tree.create_timer(1.0)
		t.timeout.connect(root.queue_free)
	return root

static func _create_procedural_singularity(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralSingularity"
	
	# Inward collapsing sphere
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 8.0 * scale
	sm.height = 16.0 * scale
	s.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color * 1.5
	s.material_override = mat
	root.add_child(s)
	
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 0.05, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(s):
			mat.albedo_color = Color.WHITE * 3.0
			var tw2 := s.create_tween().set_parallel(true)
			tw2.tween_property(s, "scale", Vector3.ONE * 2.8, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw2.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	)
	
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t := tree.create_timer(1.2)
		t.timeout.connect(root.queue_free)
	return root

static func _create_procedural_supernova(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralSupernova"
	
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 12.0 * scale
	sm.height = 24.0 * scale
	core.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color.WHITE * 3.5
	core.material_override = mat
	core.scale = Vector3.ONE * 0.05
	root.add_child(core)
	
	var tw := core.create_tween().set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE * 2.5, 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t := tree.create_timer(1.4)
		t.timeout.connect(root.queue_free)
	return root

static func _create_vector_shatter(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "VectorShatter"
	
	var util := load("res://modules/style/scripts/wireframe_util.gd")
	var v_mat: Material = null
	if util != null:
		v_mat = util.create_vector_material(color, 2.2)
	else:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = color * 2.0
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		v_mat = sm
	
	# Shards flying outward
	for i in 12:
		var shard := MeshInstance3D.new()
		if util != null:
			shard.mesh = util.create_vector_diamond(0.4 * scale)
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * (0.3 * scale)
			shard.mesh = box
		shard.material_override = v_mat
		root.add_child(shard)
		
		var dir := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		var dist := randf_range(8.0, 24.0) * scale
		var target_pos := dir * dist
		var rot_axis := Vector3(randf(), randf(), randf()).normalized()
		
		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "position", target_pos, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", rot_axis * TAU * 2.0, 0.85)
		tw.tween_property(shard, "scale", Vector3.ZERO, 0.85).set_ease(Tween.EASE_IN)
	
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t := tree.create_timer(1.1)
		t.timeout.connect(root.queue_free)
	return root

## Explosion voices playing right now. Each is a player made for the one
## sound; a chain of deaths and hit blasts used to stack them without limit,
## and every live voice is mixed on the audio thread.
static var _live_sounds := 0
const MAX_LIVE_SOUNDS := 6


static func _play_spatial_sound(parent: Node3D, pos: Vector3, sound_id: String) -> void:
	if _live_sounds >= MAX_LIVE_SOUNDS or not AddonVfx.worth_spawning(pos, 3200.0):
		return
	var stream: AudioStream = Sfx.stream(StringName(sound_id))
	if stream == null:
		return
	_live_sounds += 1
	var asp := AudioStreamPlayer3D.new()
	asp.tree_exiting.connect(func() -> void: _live_sounds = maxi(_live_sounds - 1, 0))
	asp.stream = stream
	asp.unit_size = 28.0
	asp.max_distance = 3200.0
	asp.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	asp.position = pos
	parent.add_child(asp)
	asp.play()
	asp.finished.connect(asp.queue_free)
