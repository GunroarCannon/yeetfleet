class_name FaceGenTestHelpers

static func check(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

static func approx(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps

static func print_results(fails: Array, phase: int) -> void:
	if fails.is_empty():
		print("PHASE%d OK" % phase)
	else:
		for f in fails:
			printerr("FAIL: ", f)
		printerr("PHASE%d FAILED (%d)" % [phase, fails.size()])
