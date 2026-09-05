## Headless correctness check for the juice layer itself — not visual, just the
## numbers: does trauma decay to exactly zero, does reduce_motion zero every
## output, do settings round-trip, do pools recycle instead of growing.
##
##     godot --headless --path . --script modules/common/juice/tools/juice_smoke.gd
##
## Exit code is 1 if any check fails. Godot prints its own errors to stderr, so
## CI should also fail the run if the output contains "SCRIPT ERROR" or "ERROR:".
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	print("── Juice smoke test ──────────────────────────────────────────")
	_check_shake_model()
	await _check_reduce_motion()
	await _check_settings_roundtrip()
	await _check_tween_helpers()
	await _check_particle_pool()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- Shake ------------------------------------------------------------------

func _check_shake_model() -> void:
	var shake := JuiceShake.new()
	shake.add_trauma(2.0)
	_check(is_equal_approx(shake.trauma, 1.0), "trauma did not clamp at 1")

	var guard := 0
	while shake.trauma > 0.0 and guard < 5000:
		shake.update(1.0 / 60.0)
		guard += 1
	_check(shake.trauma == 0.0, "trauma did not decay to exactly 0 (left at %f)" % shake.trauma)
	_check(shake.offset_3d() == Vector3.ZERO, "offset_3d was not exactly zero once decayed")
	_check(shake.rotation_3d() == Vector3.ZERO, "rotation_3d was not exactly zero once decayed")
	_check(shake.offset_2d() == Vector2.ZERO, "offset_2d was not exactly zero once decayed")
	print("  shake decays to exactly zero                  ok")

	shake.add_trauma(1.0)
	shake.update(1.0 / 60.0)
	var off := shake.offset_3d()
	var rot := shake.rotation_3d()
	_check(absf(off.x) <= JuiceShake.MAX_TRANSLATE.x + 0.01, "offset_3d.x exceeded its amplitude")
	_check(absf(rot.y) <= JuiceShake.MAX_ROTATE.y + 0.01, "rotation_3d.y exceeded its amplitude")
	print("  shake stays inside its declared amplitude      ok")

	var kicked := JuiceShake.new()
	kicked.add_kick(Vector3.FORWARD, 1.0)
	_check(kicked.offset_3d() != Vector3.ZERO, "a kick produced no offset at all")
	kicked.update(2.0)
	_check(kicked.offset_3d() == Vector3.ZERO, "a kick did not decay to exactly zero")
	print("  a directional kick offsets, then decays to zero ok")


# --- reduce_motion ------------------------------------------------------------

func _check_reduce_motion() -> void:
	var was_reduce := JuiceSettings.reduce_motion
	JuiceSettings.reduce_motion = true

	Juice.shake(1.0)
	Juice.kick(Vector3.FORWARD, 1.0)
	_check(Juice.shake_offset_3d() == Vector3.ZERO, "shake_offset_3d was not zeroed by reduce_motion")
	_check(Juice.shake_rotation_3d() == Vector3.ZERO, "shake_rotation_3d was not zeroed by reduce_motion")
	_check(Juice.shake_offset_2d() == Vector2.ZERO, "shake_offset_2d was not zeroed by reduce_motion")
	Juice.speed_lines(1.0)
	Juice.hitstop(0.05, 0.15)
	_check(is_equal_approx(Engine.time_scale, 1.0), "hitstop ran even though reduce_motion was on")
	await process_frame
	print("  reduce_motion zeroes every output              ok")

	JuiceSettings.reduce_motion = was_reduce


# --- Settings persistence ------------------------------------------------------

func _check_settings_roundtrip() -> void:
	var was_intensity := JuiceSettings.intensity
	var was_reduce := JuiceSettings.reduce_motion

	JuiceSettings.set_intensity(0.42)
	JuiceSettings.set_reduce_motion(true)
	JuiceSettings.intensity = 0.0
	JuiceSettings.reduce_motion = false
	JuiceSettings.load_from_disk()
	_check(is_equal_approx(JuiceSettings.intensity, 0.42), "intensity did not round-trip through disk")
	_check(JuiceSettings.reduce_motion == true, "reduce_motion did not round-trip through disk")
	print("  settings round-trip through user://juice.cfg   ok")

	JuiceSettings.set_intensity(was_intensity)
	JuiceSettings.set_reduce_motion(was_reduce)
	await process_frame


# --- Tween helpers ---------------------------------------------------------

func _check_tween_helpers() -> void:
	var host := Control.new()
	root.add_child(host)
	var label := Label.new()
	root.add_child(label)

	JuiceTween.pop(host)
	JuiceTween.nudge(host, Vector2(6, 0))
	JuiceTween.pulse(host, Color.RED)
	JuiceTween.roll_number(label, 0.0, 10.0, "%.0f")

	for _i in 90:
		await process_frame
	_check(label.text == "10", "roll_number did not land on its target value (got %s)" % label.text)
	print("  tween helpers complete                          ok")

	host.queue_free()
	label.queue_free()
	await process_frame


# --- Particle pool ----------------------------------------------------------

func _check_particle_pool() -> void:
	var burst := ParticleBurst.new()
	burst.preset = BurstPresets.Preset.SPARKS
	root.add_child(burst)
	await process_frame

	var capacity := burst.capacity()
	var children_before := burst.get_child_count()
	for _i in 500:
		burst.emit(Transform3D(Basis(), Vector3.ZERO))
	_check(
		burst.live_count() <= capacity,
		"pool exceeded its declared capacity (%d > %d)" % [burst.live_count(), capacity]
	)
	_check(
		burst.get_child_count() == children_before,
		"the pool grew child nodes instead of recycling (%d -> %d)" % [
			children_before, burst.get_child_count()
		]
	)
	print("  particle pool recycles and stays bounded        ok")

	for _i in 5:
		await process_frame
	burst.queue_free()
	await process_frame


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
