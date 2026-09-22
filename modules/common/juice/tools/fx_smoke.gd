## Headless correctness check for the three optional effect layers: the Sci-Fi
## Sound Library bank, the BinbunVFX addon wrapper, and the global toon override.
## Not visual — it asserts that the assets resolve, the toggles really gate the
## work, and the settings round-trip.
##
##     godot --headless --path . --script modules/common/juice/tools/fx_smoke.gd
##
## Exit code is 1 if any check fails. The addon checks matter most: a scene whose
## internal paths point at a folder that does not exist loads as null, and
## without this the only symptom is an effect that silently never appears.
extends SceneTree

const HIT_SPRITE := "res://assets/hit-effects/Hit Effect 01 1.png"

var _failures: Array[String] = []


func _initialize() -> void:
	print("── FX layers smoke test ─────────────────────────────────────")
	await _check_sound_library()
	await _check_fx_settings()
	await _check_addon_vfx()
	await _check_toon_override()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- Sci-Fi Sound Library -----------------------------------------------------

func _check_sound_library() -> void:
	_check(Sfx.available(), "the Sci-Fi Sound Library did not load at all")
	var laser := Sfx.stream(&"laser")
	_check(laser is AudioStream, "Sfx.stream('laser') is not an AudioStream")
	_check(
		Sfx.streams(&"laser").size() == 10,
		"expected 10 laser variants, got %d" % Sfx.streams(&"laser").size()
	)
	_check(Sfx.stream(&"not_an_id") == null, "an unknown id did not come back null")

	# A loop id has to actually loop, or the engine drone stops after one pass.
	var engine := Sfx.stream(&"engine_loop_small")
	_check(engine != null, "no engine loop in the library")
	if engine is AudioStreamMP3:
		_check((engine as AudioStreamMP3).loop, "the engine loop stream is not set to loop")

	var random := Sfx.random_stream(&"laser")
	_check(random != null, "random_stream returned null for a populated id")
	print("  sound library resolves, lasers vary, loops loop ok")


# --- Toggle persistence -------------------------------------------------------

func _check_fx_settings() -> void:
	var was_sounds := FxSettings.library_sounds
	var was_vfx := FxSettings.addon_vfx
	var was_sprites := FxSettings.sprite_hits

	FxSettings.set_library_sounds(false)
	FxSettings.set_addon_vfx(false)
	FxSettings.set_sprite_hits(false)
	FxSettings.library_sounds = true
	FxSettings.addon_vfx = true
	FxSettings.sprite_hits = true
	FxSettings.load_from_disk()
	_check(FxSettings.library_sounds == false, "library_sounds did not round-trip")
	_check(FxSettings.addon_vfx == false, "addon_vfx did not round-trip")
	_check(FxSettings.sprite_hits == false, "sprite_hits did not round-trip")
	print("  fx toggles round-trip through user://fx.cfg    ok")

	FxSettings.set_library_sounds(was_sounds)
	FxSettings.set_addon_vfx(was_vfx)
	FxSettings.set_sprite_hits(was_sprites)
	await process_frame


# --- BinbunVFX addon ----------------------------------------------------------

func _check_addon_vfx() -> void:
	_check(AddonVfx.available(), "no BinbunVFX scene loaded — check the addon's internal paths")

	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	await process_frame

	# The toggle has to actually gate the work, not just hide a result.
	AddonVfx.set_enabled(false)
	_check(
		AddonVfx.spawn(host, AddonVfx.Kind.HIT, Vector3.ZERO) == null,
		"spawn produced a node while the addon layer was switched off"
	)
	AddonVfx.set_enabled(true)

	var hit := AddonVfx.spawn(host, AddonVfx.Kind.HIT, Vector3(0.0, 1.0, 0.0), Vector3.UP, 1.0, Color.CYAN)
	_check(hit != null and is_instance_valid(hit), "the hit effect did not instantiate")
	_check(hit == null or hit.is_inside_tree(), "the hit effect was not added to the tree")
	# The addon ships its AnimationPlayer library in Godot 3's `libraries/ = ...`
	# form, which Godot 4 parses as an empty library — so the scene loads, looks
	# fine, and never plays. Assert the animation is actually reachable.
	if hit != null:
		var anim := hit.get_node_or_null("AnimationPlayer") as AnimationPlayer
		_check(anim != null, "the hit effect has no AnimationPlayer")
		_check(
			anim == null or anim.has_animation("main"),
			"the hit effect's AnimationPlayer has no 'main' animation — the addon scene's library failed to load"
		)

	var blast := AddonVfx.spawn(host, AddonVfx.Kind.EXPLOSION_AIR, Vector3(2.0, 0.0, 0.0))
	_check(blast != null and is_instance_valid(blast), "the explosion effect did not instantiate")

	var nuke_node := AddonVfx.spawn(host, AddonVfx.Kind.NUKE, Vector3(4.0, 0.0, 0.0))
	_check(nuke_node != null and is_instance_valid(nuke_node), "the nuke effect did not instantiate")

	var ground_node := AddonVfx.spawn(host, AddonVfx.Kind.EXPLOSION_GROUND, Vector3(6.0, 0.0, 0.0))
	_check(ground_node != null and is_instance_valid(ground_node), "the ground explosion did not instantiate")

	var zap_node := AddonVfx.spawn(host, AddonVfx.Kind.ZAP, Vector3(8.0, 0.0, 0.0))
	_check(zap_node != null and is_instance_valid(zap_node), "the zap lightning did not instantiate")

	var ball_node := AddonVfx.spawn(host, AddonVfx.Kind.BALL, Vector3(10.0, 0.0, 0.0))
	_check(ball_node != null and is_instance_valid(ball_node), "the ball lightning did not instantiate")

	var proj_bolt := AddonVfx.projectile_fx(host, Vector3(12.0, 0.0, 0.0), Vector3.FORWARD, AddonVfx.Kind.PROJECTILE_BOLT)
	_check(proj_bolt != null and is_instance_valid(proj_bolt), "the projectile bolt did not instantiate")

	var proj_jav := AddonVfx.projectile_fx(host, Vector3(14.0, 0.0, 0.0), Vector3.FORWARD, AddonVfx.Kind.PROJECTILE_JAVELIN)
	_check(proj_jav != null and is_instance_valid(proj_jav), "the projectile javelin did not instantiate")

	var proj_wave := AddonVfx.projectile_fx(host, Vector3(16.0, 0.0, 0.0), Vector3.FORWARD, AddonVfx.Kind.PROJECTILE_WAVE)
	_check(proj_wave != null and is_instance_valid(proj_wave), "the projectile wave did not instantiate")

	print("  addon scenes (hits, explosions, lightning, projectiles) instantiate and honour the toggle ok")

	# The sprite flash is the one piece with an art dependency, so name the file
	# when it is missing rather than failing anonymously.
	_check(ResourceLoader.exists(HIT_SPRITE), "hit sprite art is not imported: %s" % HIT_SPRITE)
	var sprite := AddonVfx.spawn_sprite_hit(host, Vector3(0.0, 3.0, 0.0))
	_check(sprite != null, "the sprite hit flash did not build (are the PNGs imported?)")
	if sprite != null:
		_check(sprite.sprite_frames != null, "the sprite flash has no frames")
		_check(
			sprite.sprite_frames.get_frame_count("default") == 3,
			"expected 3 frames in the sprite flash, got %d" % sprite.sprite_frames.get_frame_count("default")
		)
	print("  sprite hit flash builds three frames         ok")

	host.queue_free()
	await process_frame


# --- Toon override ------------------------------------------------------------

func _check_toon_override() -> void:
	_check(ToonOverride.shader() != null, "the UltimateToonSource shader did not load")
	var mat := ToonOverride.make_material(Color("ff8844"))
	_check(mat != null, "make_material returned null")

	var was := ToonOverride.enabled()
	ToonOverride.set_enabled(true)
	_check(StyleSettings.toon_shading == true, "enabling toon did not persist the setting")

	# The toggle has to actually reach the materials, not just flip a flag: the
	# hull/rock shader reads it as a uniform, and that uniform is what puts the
	# whole game into the stepped shading path.
	var part_mat := ShaderMaterial.new()
	part_mat.shader = ShipMaterials.part_shader()
	ShipMaterials.apply_style_dials(part_mat)
	_check(
		float(part_mat.get_shader_parameter("toon_override")) == 1.0,
		"the toon toggle did not set toon_override on the part material"
	)

	ToonOverride.set_enabled(was)
	_check(ToonOverride.enabled() == was, "the toon toggle did not restore")
	ShipMaterials.apply_style_dials(part_mat)
	_check(
		float(part_mat.get_shader_parameter("toon_override")) <= 0.0,
		"turning toon back off left toon_override set on the material"
	)
	print("  toon override loads the addon shader, reaches materials ok")


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for text in _failures:
			print("  ✗ " + text)
		quit(1)
