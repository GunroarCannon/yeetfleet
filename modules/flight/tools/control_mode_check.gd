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

	failures += _check_speed_scale(model)
	failures += _check_arcade_pivot(model)

	print("")
	if failures == 0:
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % failures)
		quit(1)


## The ship-speed dial: [member FlightModel.speed_scale] scales a ship's top
## speed and acceleration together, and [method FlightModel.rescale_speed] moves a
## ship already in flight to a new scale by the ratio — so the round trip has to
## land back exactly where it started, or every nudge of the slider would ratchet
## the ship's speed up or down.
func _check_speed_scale(model: FlightModel) -> int:
	var failures := 0
	model.speed_scale = 1.0
	model.set_control_mode(FlightModel.ControlMode.SIM)
	var full_speed := model.top_speed
	var full_accel := model.accel

	model.speed_scale = 0.25
	model.rescale_speed(0.25)
	print("  speed scale ×0.25: top %.0f -> %.0f m/s, accel %.1f -> %.1f" % [
		full_speed, model.top_speed, full_accel, model.accel,
	])
	if not is_equal_approx(model.top_speed, full_speed * 0.25):
		push_error("speed scale: top speed %.1f is not a quarter of %.1f" % [model.top_speed, full_speed])
		failures += 1
	if not is_equal_approx(model.accel, full_accel * 0.25):
		push_error("speed scale: accel %.1f did not scale with the ceiling %.1f" % [model.accel, full_accel])
		failures += 1
	# Slower ships must still be flyable: a ceiling under the reverse fraction
	# would make the throttle a dead stick.
	if model.top_speed <= 0.0 or model.accel <= 0.0:
		push_error("speed scale: a slowed ship has no speed or no thrust")
		failures += 1

	model.speed_scale = 1.0
	model.rescale_speed(1.0)
	if not is_equal_approx(model.top_speed, full_speed) or not is_equal_approx(model.accel, full_accel):
		push_error("speed scale: the round trip did not restore %.1f/%.1f (got %.1f/%.1f)" % [
			full_speed, full_accel, model.top_speed, model.accel,
		])
		failures += 1

	# A fresh configure at a scaled setting must land on the same number, or the
	# dial would mean one thing for a ship in flight and another for the next one.
	model.speed_scale = 0.5
	model.configure(model._stats, null, null)
	if not is_equal_approx(model.top_speed, full_speed * 0.5):
		push_error("speed scale: a ship configured at ×0.5 got %.1f, not %.1f" % [
			model.top_speed, full_speed * 0.5,
		])
		failures += 1
	model.speed_scale = 1.0
	model.configure(model._stats, null, null)
	return failures


## The arcade pivot dial. Three things have to hold: arcade's turn rate actually
## scales, the scaled rate reaches the physics, and sim is untouched — the dial
## is scoped to arcade precisely so that turning it up cannot quietly turn the
## modes with weight into the mode without any.
##
## The untouched half is asserted on [member FlightModel.turn_rate] rather than
## on a measured angle: the two sim runs share a model and differ by a few
## arc-seconds of integration noise, which no tolerance worth writing can tell
## apart from "the dial nudged it". The rate is the number the dial moves, so it
## is the honest thing to compare. The measured turn is still checked, on arcade
## only, to prove the rate is not merely set but used.
##
## Measured over a short window on purpose: [method Basis.angle_to] saturates at
## 180°, and a ×4 arcade pivot crosses that inside the 36 frames the other checks
## use, which would read as "no faster" for the silliest possible reason.
func _check_arcade_pivot(model: FlightModel) -> int:
	var failures := 0
	Session.arcade_pivot = 1.0
	model.set_control_mode(FlightModel.ControlMode.ARCADE)
	var arcade_rate := model.turn_rate
	model.set_control_mode(FlightModel.ControlMode.SIM)
	var sim_rate := model.turn_rate

	Session.arcade_pivot = 4.0
	model.set_control_mode(FlightModel.ControlMode.ARCADE)
	var arcade_rate_fast := model.turn_rate
	model.set_control_mode(FlightModel.ControlMode.SIM)
	var sim_rate_after := model.turn_rate

	print("  arcade pivot ×4: arcade turn %.0f → %.0f°/s, sim %.1f → %.1f°/s (unchanged)" % [
		rad_to_deg(arcade_rate), rad_to_deg(arcade_rate_fast),
		rad_to_deg(sim_rate), rad_to_deg(sim_rate_after),
	])
	if not is_equal_approx(arcade_rate_fast, arcade_rate * 4.0):
		push_error("arcade pivot: ×4 gave arcade %.1f°/s, not %.1f°/s" % [
			rad_to_deg(arcade_rate_fast), rad_to_deg(arcade_rate * 4.0),
		])
		failures += 1
	if not is_equal_approx(sim_rate_after, sim_rate):
		push_error("arcade pivot: sim moved too (%.2f°/s → %.2f°/s)" % [
			rad_to_deg(sim_rate), rad_to_deg(sim_rate_after),
		])
		failures += 1

	# And the rate is actually flown, not just stored: same stick, same frames.
	Session.arcade_pivot = 1.0
	var arcade_turn := _turn_over(model, FlightModel.ControlMode.ARCADE, 6)
	Session.arcade_pivot = 4.0
	var arcade_turn_fast := _turn_over(model, FlightModel.ControlMode.ARCADE, 6)
	if arcade_turn_fast < arcade_turn * 2.5:
		push_error("arcade pivot: the nose only went from %.0f° to %.0f° in 6 frames" % [
			rad_to_deg(arcade_turn), rad_to_deg(arcade_turn_fast),
		])
		failures += 1

	Session.arcade_pivot = 1.0
	model.configure(model._stats, null, null)
	return failures


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
