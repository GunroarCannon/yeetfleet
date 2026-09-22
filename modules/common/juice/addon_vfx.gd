## One-shots from the BinbunVFX addon, plus the animated sprite hit flash in
## [code]assets/hit-effects[/code], behind a single [member enabled] switch.
##
## This is the layering point the comparison lab exists for: with [method enabled]
## true an impact gets the addon's particles, its own light pop and a matching
## sound on top of whatever [Juice] already did; with it false the project falls
## back to the pure-Juice look it had before, so the two can be flipped against
## each other without a code change.
##
## The addon's effects are scene-per-effect [Node3D]s driven by their own
## [AnimationPlayer] (see [VFXControllerBB]). We instantiate one, force it to
## one-shot + autoplay, then free it on [code]finished[/code] with a lifetime
## backstop so a scene whose animation never reports finishing cannot leak.
##
## Sound lives here rather than in [SpaceAudio] so the destruction lab — which
## has no flight module — still gets a hit that reads as a hit. The pool is
## small and round-robins, exactly like [SpaceAudio]'s own spatial pool.
##
## Every path is optional: a scene that failed to import simply produces no
## effect instead of an error, and [method available] reports the truth.
class_name AddonVfx
extends RefCounted

enum Kind {
	HIT,            ## a glancing weapon hit
	IMPACT,         ## a heavier weapon impact
	BIG_IMPACT,     ## capital-grade impact
	EXPLOSION_AIR,  ## detonation in open space
	EXPLOSION_GROUND, ## detonation against a surface
	NUKE,           ## the largest available blast
	ZAP,            ## electric zap
	BALL,           ## ball lightning
	PROJECTILE_BOLT,    ## basic energy bolt/projectile
	PROJECTILE_JAVELIN,  ## heavy/piercing javelin projectile
	PROJECTILE_WAVE,    ## energy wave / crescent projectile
}

const ROOT := "res://addons/BinbunVFX_Vol2"
const HIT_SPRITE_DIR := "res://assets/hit-effects"

## One or more scenes per kind; a variant is picked at random so repeated hits do
## not read as a stutter.
const SCENES := {
	Kind.HIT: [
		ROOT + "/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
		ROOT + "/StylizedHitFX/effects/hit/vfx_hit_02.tscn",
	],
	Kind.IMPACT: [
		ROOT + "/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
		ROOT + "/StylizedHitFX/effects/impact/vfx_impact_02.tscn",
	],
	Kind.BIG_IMPACT: [
		ROOT + "/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
		ROOT + "/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
	],
	Kind.EXPLOSION_AIR: [ROOT + "/ExplosionFX/effects/air/vfx_air_explosion_01.tscn"],
	Kind.EXPLOSION_GROUND: [ROOT + "/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"],
	Kind.NUKE: [ROOT + "/ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn"],
	Kind.ZAP: [ROOT + "/ElectricFX/effects/zap/vfx_zap_lightning_01.tscn"],
	Kind.BALL: [ROOT + "/ElectricFX/effects/ball/vfx_ball_lightning_01.tscn"],
	Kind.PROJECTILE_BOLT: [
		ROOT + "/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_01.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_02.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_03.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_04.tscn",
	],
	Kind.PROJECTILE_JAVELIN: [
		ROOT + "/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_01.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_02.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_03.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_04.tscn",
	],
	Kind.PROJECTILE_WAVE: [
		ROOT + "/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_01.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_02.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_03.tscn",
		ROOT + "/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_04.tscn",
	],
}

## The three frames of the sprite hit flash, played in order. Named rather than
## globbed so a re-export of the art cannot silently change the running order.
const HIT_SPRITE_FRAMES := [
	HIT_SPRITE_DIR + "/Hit Effect 01 1.png",
	HIT_SPRITE_DIR + "/Hit Effect 01 2.png",
	HIT_SPRITE_DIR + "/Hit Effect 01 3.png",
]

## How long a spawned effect may live before it is force-freed even if its
## animation never reports finishing. Longer than any authored effect.
const MAX_LIFETIME := 8.0

## Spatial audio pool. Four is the whole budget: a broadside resolves to a few
## simultaneous impacts at most.
const AUDIO_POOL_SIZE := 4
const AUDIO_UNIT_SIZE := 24.0
const AUDIO_MAX_DISTANCE := 2600.0

static var _scene_cache: Dictionary = {}
static var _audio_host: Node3D = null
static var _audio_pool: Array[AudioStreamPlayer3D] = []
static var _audio_idx := 0


# --- Toggle ----------------------------------------------------------------

## Whether the addon layer is on, read from the persisted [FxSettings].
static func enabled() -> bool:
	FxSettings.ensure_loaded()
	return FxSettings.addon_vfx


static func set_enabled(value: bool) -> void:
	FxSettings.set_addon_vfx(value)


## True when at least one addon scene actually loaded, so a caller can decide to
## skip the spawn entirely instead of instantiating into nothing.
static func available() -> bool:
	return scene_for(Kind.HIT) != null or scene_for(Kind.EXPLOSION_AIR) != null


# --- Spawning --------------------------------------------------------------

## The [PackedScene] for [param kind], cached, or null when the file is missing.
static func scene_for(kind: Kind) -> PackedScene:
	if _scene_cache.has(kind):
		return _scene_cache[kind]
	var paths: Array = SCENES.get(kind, [])
	if paths.is_empty():
		_scene_cache[kind] = null
		return null
	var path := String(paths[randi() % paths.size()])
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	_scene_cache[kind] = scene
	return scene


## Instantiate [param kind] at [param pos], oriented so its forward axis looks
## along [param normal]. Returns the effect node, or null when the addon is off,
## the scene is missing, or [param parent] is not in the tree.
static func spawn(
	parent: Node,
	kind: Kind,
	pos: Vector3,
	normal := Vector3.UP,
	scale := 1.0,
	color := Color.TRANSPARENT
) -> Node3D:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return null
	var scene := scene_for(kind)
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	# Force a single pass and let it start itself; both must be set before the
	# node enters the tree, because VFXControllerBB plays from _enter_tree.
	node.set("one_shot", true)
	node.set("autoplay", true)
	if color.a > 0.0:
		node.set("primary_color", color)
		node.set("secondary_color", color.darkened(0.35))
		node.set("tertiary_color", color.darkened(0.6))
	parent.add_child(node)
	node.global_position = pos
	if normal.length_squared() > 0.001:
		node.look_at(pos + normal.normalized(), Vector3.UP if absf(normal.normalized().y) < 0.95 else Vector3.RIGHT)
	node.scale = Vector3.ONE * maxf(scale, 0.01)
	# Free on completion, with a hard backstop so a looping or broken animation
	# cannot leave the effect in the tree forever.
	if node.has_signal("finished"):
		node.connect("finished", node.queue_free)
	var anim := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_signal("animation_finished"):
		anim.animation_finished.connect(func(_anim_name: StringName) -> void:
			if is_instance_valid(node):
				node.queue_free()
		)
	var backstop := Timer.new()
	backstop.wait_time = MAX_LIFETIME
	backstop.one_shot = true
	backstop.autostart = true
	backstop.timeout.connect(node.queue_free)
	node.add_child(backstop)
	return node


## A weapon hit: the addon hit effect plus the sprite flash, in [param parent].
## [param normal] is the surface normal, so the flash faces out of the hull.
static func hit(
	parent: Node,
	pos: Vector3,
	normal := Vector3.UP,
	scale := 1.0,
	color := Color.TRANSPARENT,
	sound := &"hit"
) -> void:
	if not enabled():
		return
	if color.a <= 0.0:
		color = Color("8ef0ff")
	spawn(parent, Kind.HIT, pos, normal, scale, color)
	# The sprite flash is its own toggle: it is a 2D read on a 3D impact, and
	# some looks want it and some want the purely volumetric hit.
	FxSettings.ensure_loaded()
	if FxSettings.sprite_hits:
		spawn_sprite_hit(parent, pos, normal, scale)
	# An empty id is how a caller says "I already have this sound" — the flight
	# weapon path plays its own explosion, and a second copy would just be loud.
	if sound != &"":
		play(sound, pos)


## A detonation. [param scale] multiplies the effect size and [param heavy]
## picks the bigger scene. An empty [param sound] means the caller owns the
## mix — the flight module plays its own explosion through [SpaceAudio], and a
## second copy here would only be louder.
static func explosion(
	parent: Node,
	pos: Vector3,
	scale := 1.0,
	heavy := false,
	color := Color.TRANSPARENT,
	sound := &""
) -> void:
	if not enabled():
		return
	spawn(parent, Kind.BIG_IMPACT if heavy else Kind.EXPLOSION_AIR, pos, Vector3.UP, scale, color)
	if sound != &"":
		play(sound, pos)


## A catastrophic planetary or capital-grade nuke detonation.
static func nuke(
	parent: Node,
	pos: Vector3,
	scale := 2.5,
	color := Color.TRANSPARENT,
	sound := &""
) -> void:
	if not enabled():
		return
	spawn(parent, Kind.NUKE, pos, Vector3.UP, scale, color)
	if sound != &"":
		play(sound, pos)


## A detonation against a surface (planetary crust, asteroid, or large craft structure).
static func ground_explosion(
	parent: Node,
	pos: Vector3,
	normal := Vector3.UP,
	scale := 1.5,
	color := Color.TRANSPARENT,
	sound := &""
) -> void:
	if not enabled():
		return
	spawn(parent, Kind.EXPLOSION_GROUND, pos, normal, scale, color)
	if sound != &"":
		play(sound, pos)


## An electric effect at [param pos]: zap by default, ball when [param ball] is
## true.
static func electric(parent: Node, pos: Vector3, scale := 1.0, ball := false) -> void:
	if not enabled():
		return
	spawn(parent, Kind.BALL if ball else Kind.ZAP, pos, Vector3.UP, scale, Color("8fd8ff"))
	play(&"hit", pos)


## Spawn a magic projectile visual at [param pos] looking along [param dir].
static func projectile_fx(
	parent: Node,
	pos: Vector3,
	dir := Vector3.FORWARD,
	kind := Kind.PROJECTILE_BOLT,
	scale := 1.0,
	color := Color.TRANSPARENT
) -> Node3D:
	if not enabled():
		return null
	return spawn(parent, kind, pos, dir, scale, color)


## The animated sprite flash on its own — a billboarded three-frame hit that
## reads even when the addon's 3D particles are switched off.
static func spawn_sprite_hit(
	parent: Node,
	pos: Vector3,
	normal := Vector3.UP,
	scale := 1.0
) -> AnimatedSprite3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var frames := _hit_sprite_frames()
	if frames == null:
		return null
	var sprite := AnimatedSprite3D.new()
	sprite.name = "HitFlash"
	sprite.sprite_frames = frames
	sprite.animation = "default"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Size the billboard by world height so [param scale] means the same thing
	# whatever the source art resolution is.
	var tex := frames.get_frame_texture("default", 0) as Texture2D
	var tex_size := float(maxi(tex.get_width() if tex != null else 64, 1))
	sprite.pixel_size = (0.06 * scale) / tex_size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	sprite.material_override = mat
	sprite.speed_scale = 18.0
	# AnimatedSprite3D.autoplay is the animation *name* to start on, not a bool.
	sprite.autoplay = &"default"
	parent.add_child(sprite)
	sprite.global_position = pos
	sprite.global_rotation = Vector3.ZERO
	sprite.connect("animation_finished", sprite.queue_free)
	return sprite


static func _hit_sprite_frames() -> SpriteFrames:
	FxSettings.ensure_loaded()
	if not FxSettings.sprite_hits:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("default")
	frames.set_animation_speed("default", 18.0)
	frames.set_animation_loop("default", false)
	var added := 0
	for path: String in HIT_SPRITE_FRAMES:
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			frames.add_frame("default", tex)
			added += 1
	return frames if added > 0 else null


# --- Audio -----------------------------------------------------------------

## Play a Sci-Fi Sound Library one-shot at [param pos] through the local pool.
## Silent when the library is off or has no stream for [param id].
static func play(id: StringName, pos: Vector3, pitch_variance := 0.08) -> AudioStreamPlayer3D:
	FxSettings.ensure_loaded()
	if not FxSettings.library_sounds:
		return null
	var stream := Sfx.random_stream(id)
	if stream == null:
		return null
	var pool := _ensure_audio_pool()
	if pool.is_empty():
		return null
	var player := pool[_audio_idx]
	_audio_idx = (_audio_idx + 1) % pool.size()
	player.stop()
	player.global_position = pos
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.stream = stream
	player.play()
	return player


static func _ensure_audio_pool() -> Array[AudioStreamPlayer3D]:
	if not _audio_pool.is_empty() and is_instance_valid(_audio_host) and _audio_host.is_inside_tree():
		return _audio_pool
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return _audio_pool
	_audio_host = Node3D.new()
	_audio_host.name = "AddonVfxAudio"
	(loop as SceneTree).root.add_child(_audio_host)
	_audio_pool.clear()
	for i in AUDIO_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "AddonSfx_%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.unit_size = AUDIO_UNIT_SIZE
		p.max_distance = AUDIO_MAX_DISTANCE
		p.max_db = 6.0
		_audio_host.add_child(p)
		_audio_pool.append(p)
	return _audio_pool
