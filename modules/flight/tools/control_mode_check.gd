## Headless check that the control-mode presets actually differ in feel now:
## Arcade must turn noticeably faster and have higher assist authority than
## Realistic, and the preset's authority/spool must reach the model.
##
##     godot --path . --headless --script modules/flight/tools/control_mode_check.gd
extends SceneTree

const DT := 0.016


func _initialize() -> void:
	print("── control-mode difference check ──────────────────────")
	var rig := Node3D.new()
	root.add_child(rig)
	var model := FlightModel.new()
	rig.add_child(model)
	# A plain design for the preset multipliers to act on.
	var stats := ShipStats.new()
	stats.top_speed = 300.0
	stats.accel = 30.0
	stats.agility = 90.0
	model.configure(stats, null, null)
	await process_frame
	await process_frame

	var failures := 0
	var arcade_turn := _turn_over(model, FlightModel.ControlMode.ARCADE, 36)
	var realistic_turn := _turn_over(model, FlightModel.ControlMode.REALISTIC, 36)
	print("  turn over 0.6s: arcade %.1f°  realistic %.1f°" % [
		rad_to_deg(arcade_turn), rad_to_deg(realistic_turn),
	])
	if arcade_turn <= realistic_turn * 1.4:
		push_error("control check: Arcade did not turn clearly faster than Realistic (%.1f vs %.1f°)" % [
			rad_to_deg(arcade_turn), rad_to_deg(realistic_turn),
		])
		failures += 1

	# Authority and spool are wired from the presets, and each must make its mode
	# feel different: arcade snappy/high-authority, realistic heavy/low-authority.
	model.set_control_mode(FlightModel.ControlMode.ARCADE)
	var arcade_authority := model.assist_authority
	var arcade_spool := model.turn_spool
	model.set_control_mode(FlightModel.ControlMode.REALISTIC)
	var realistic_authority := model.assist_authority
	if realistic_authority >= arcade_authority:
		push_error("control check: assist authority not wired from preset (arcade %.1f, realistic %.1f)" % [
			arcade_authority, realistic_authority,
		])
		failures += 1
	if model.turn_spool < arcade_spool * 1.5:
		push_error("control check: Realistic spool (%.2f s) is not heavier than Arcade (%.2f s)" % [
			model.turn_spool, arcade_spool,
		])
		failures += 1
	print("  authority: arcade %.1f/s  realistic %.1f/s  spool %.2f/%.2f s (wired)" % [
		arcade_authority, realistic_authority, arcade_spool, model.turn_spool,
	])

	print("")
	if failures == 0:
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)


## Hold full yaw for [param frames] physics steps in a control mode and return
## how many radians the nose turned (reset between runs).
func _turn_over(model: FlightModel, mode: int, frames: int) -> float:
	model.set_control_mode(mode)
	model.set_assist_mode(0)  # manual: pure rotation from the stick, no fly-by-wire
	model.command.yaw = 1.0
	model.angular = Vector3.ZERO
	model.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var start := -model.global_transform.basis.z
	for i in frames:
		model._physics_process(DT)
	var end := -model.global_transform.basis.z
	model.command.yaw = 0.0
	return start.angle_to(end)
