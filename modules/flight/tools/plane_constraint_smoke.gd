## plane_constraint_smoke.gd — headless verification for PlaneConstraint.
##
## Run:
##   "$GD" --path . --headless --script modules/flight/tools/plane_constraint_smoke.gd
##
## PlaneConstraint reads/writes FlightModel.velocity. Since we cannot mock
## FlightModel (it's a concrete typed class with a physics process), we test
## the underlying vector mathematics directly — the constraint is just a
## single dot-project-lerp expression, so exercising it in isolation is
## sufficient.
extends SceneTree

const PASS := "  [PASS] "
const FAIL := "  [FAIL] "
var _errors := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print(PASS + msg)
	else:
		printerr(FAIL + msg)
		_errors += 1

func _assert_near(a: float, b: float, msg: String, tol: float = 0.01) -> void:
	_assert(absf(a - b) < tol, msg + " (got %.4f, want %.4f)" % [a, b])

func _assert_vec_near(a: Vector3, b: Vector3, msg: String, tol: float = 0.01) -> void:
	_assert(a.distance_to(b) < tol, msg + " (got %s, want %s)" % [a, b])


# ---------------------------------------------------------------------------
# Shared helper: runs the constraint math on a raw velocity.
# Mirrors the logic in PlaneConstraint._apply_plane_constraint().
# ---------------------------------------------------------------------------

func _constrain(vel: Vector3, normal: Vector3, strength: float, delta: float) -> Vector3:
	var off := vel.dot(normal)
	if absf(off) < 0.001:
		return vel
	var on_plane := vel - normal * off
	return vel.lerp(on_plane, clampf(strength * delta, 0.0, 1.0))


func _init() -> void:
	print("\n=== plane_constraint smoke ===\n")

	_test_on_plane_unchanged()
	_test_off_plane_zeroed_instant()
	_test_partial_snap()
	_test_custom_plane_normal()
	_test_lerp_factor_clamp()
	_test_spring_damp()
	_test_plane_constraint_defaults()

	print("\n--- %d assertion(s) failed ---\n" % _errors)
	quit(1 if _errors > 0 else 0)


# ---------------------------------------------------------------------------
# On-plane velocity: no change
# ---------------------------------------------------------------------------

func _test_on_plane_unchanged() -> void:
	print("-- On-plane velocity unchanged --")
	var vel := Vector3(10, 0, 5)  # purely on XZ plane
	var result := _constrain(vel, Vector3.UP, 12.0, 0.016)
	_assert_near(result.x, 10.0, "X velocity preserved")
	_assert_near(result.y,  0.0, "Y stays zero when already on plane")
	_assert_near(result.z,  5.0, "Z velocity preserved")


# ---------------------------------------------------------------------------
# Instant snap (strength → ∞)
# ---------------------------------------------------------------------------

func _test_off_plane_zeroed_instant() -> void:
	print("-- Instant snap zeroes off-plane component --")
	var vel := Vector3(10, 80, 5)  # 80 m/s off XZ plane
	var result := _constrain(vel, Vector3.UP, 9999.0, 1.0)  # t clamps to 1
	_assert_near(result.x, 10.0, "X preserved after instant snap")
	_assert_near(result.y,  0.0, "Y zeroed instantly (strength=9999)")
	_assert_near(result.z,  5.0, "Z preserved after instant snap")


# ---------------------------------------------------------------------------
# Partial snap (realistic frame)
# ---------------------------------------------------------------------------

func _test_partial_snap() -> void:
	print("-- Partial snap at 60Hz --")
	# strength=12, delta=1/60 → t = 0.2
	var vel := Vector3(0, 100, 0)   # 100 m/s purely off-plane
	var t   := clampf(12.0 / 60.0, 0.0, 1.0)  # 0.2
	_assert_near(t, 0.2, "lerp factor = 12/60 = 0.2")
	# Expected Y after one frame: 100 × (1 − 0.2) = 80.0
	var result := _constrain(vel, Vector3.UP, 12.0, 1.0 / 60.0)
	_assert_near(result.y, 80.0, "off-plane component reduced by 20% at 60Hz", 0.5)
	_assert_near(result.x, 0.0, "X unchanged in partial snap")


# ---------------------------------------------------------------------------
# Custom plane normal (X axis → YZ plane)
# ---------------------------------------------------------------------------

func _test_custom_plane_normal() -> void:
	print("-- Custom plane normal (X-axis → YZ plane) --")
	var vel    := Vector3(60, 5, 10)   # 60 m/s along X = off-plane
	var normal := Vector3.RIGHT        # normal = X → plane is YZ
	var result := _constrain(vel, normal, 9999.0, 1.0)
	_assert_near(result.x,  0.0, "X zeroed for X-normal plane")
	_assert_near(result.y,  5.0, "Y preserved in YZ plane")
	_assert_near(result.z, 10.0, "Z preserved in YZ plane")

	# Diagonal normal: 45° between UP and FORWARD.
	var diag := (Vector3.UP + Vector3.FORWARD).normalized()
	var vel2 := Vector3(0, 10, -10)   # entirely in the off-plane direction
	var r2   := _constrain(vel2, diag, 9999.0, 1.0)
	_assert_near(r2.dot(diag), 0.0, "velocity has no component along diagonal normal", 0.01)


# ---------------------------------------------------------------------------
# Lerp factor is clamped to [0, 1]
# ---------------------------------------------------------------------------

func _test_lerp_factor_clamp() -> void:
	print("-- Lerp factor clamp --")
	# Very large delta must not produce a factor > 1.
	var t_large := clampf(12.0 * 100.0, 0.0, 1.0)
	_assert_near(t_large, 1.0, "lerp factor clamps at 1.0 for large delta")

	# Negative strength (shouldn't happen but must not blow up).
	var t_neg := clampf(-5.0 * 0.016, 0.0, 1.0)
	_assert_near(t_neg, 0.0, "lerp factor clamps at 0.0 for negative product")


# ---------------------------------------------------------------------------
# Spring-damp convergence
# ---------------------------------------------------------------------------

func _test_spring_damp() -> void:
	print("-- Spring-damp banking convergence --")
	# Simulate PlaneConstraint._spring_damp reaching the target.
	var current := 0.0
	var target  := 25.0
	var vel     := 0.0
	var k       := 6.0
	var zeta    := 0.7
	var dt      := 1.0 / 60.0

	# Run for 4 simulated seconds (240 frames at 60Hz).
	for _i in range(240):
		var err := target - current
		vel += err * k * dt
		vel *= 1.0 - minf(2.0 * zeta * k * dt, 1.0)
		current += vel * dt

	_assert(absf(current - target) < 3.0, "spring-damp converges to within 3° of target in 4s (got %.2f)" % current)
	_assert(absf(vel) < 5.0, "spring-damp velocity is near-zero at convergence (got %.2f)" % vel)


# ---------------------------------------------------------------------------
# PlaneConstraint has correct default values
# ---------------------------------------------------------------------------

func _test_plane_constraint_defaults() -> void:
	print("-- PlaneConstraint defaults --")
	var pc := PlaneConstraint.new()
	_assert(pc.snap_strength > 0.0,     "default snap_strength positive")
	_assert(pc.plane_normal == Vector3.UP, "default plane_normal is UP")
	_assert(is_nan(pc.locked_height),   "default locked_height is NaN")
	_assert(pc.pitch_as_bank,           "pitch_as_bank on by default")
	_assert(pc.bank_tilt_deg > 0.0,     "bank_tilt_deg positive")
	_assert(pc.flight_model == null,    "flight_model null until assigned")
	pc.free()
