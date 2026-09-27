## Bug hunt: flip suspect variables, record what the game does under a fixed,
## repeatable stimulus, and compare the runs to find which variable a bug hangs
## off — the debugging rule for "the shots aren't straight sometimes".
##
## A *suspect* is any variable that might be to blame: a toggle, a dial, an
## engine setting. Each has a getter, a setter and an alternative value to try.
## A *run* sets some suspects, drives the ship through the same stimulus
## (auto-fire, a stick weave, simulated hits landing on the hull), records the
## metrics, restores everything and files the result. A *hunt* is a baseline
## run followed by one run per suspect, each with only that suspect flipped,
## ranked by how far flipping it moved the metric — the biggest mover is the
## likely source.
##
## Built-in metrics come from [member SystemsSim.shot_probe]: for every shot
## (and every frame of a held beam) the player's guns fire, how many degrees it
## left off the line a perfect gun would take — from its barrel in the ship's
## steady frame to the gunsight or the locked target's lead point. Anything
## else can feed its own channel through [method record]. Suspects are open
## too: [method register_suspect].
##
## Lives under [FlightRoot]; the 🐞 Bug hunt panel ([BugHuntPanel]) is its UI,
## and modules/flight/tools/bug_hunt_check.gd runs a hunt headless.
class_name BugHunt
extends Node

## A run finished; [param run] is its entry in [member runs].
signal run_finished(run: Dictionary)
## A hunt finished; [param verdict] is the ranked summary.
signal hunt_finished(verdict: Dictionary)
signal status_changed(text: String)

## The metric a hunt ranks suspects by.
const RANK_METRIC := "shot_dev_mean"
## Seconds of stimulus before recording starts, so a flipped setting's
## transient (a beam re-spawning, a spring settling) is not measured.
const WARMUP := 0.5
const CSV_PATH := "user://bug_hunt_runs.csv"

var root: FlightRoot = null
## Seconds each run records for.
var run_time := 4.0
## Stimulus switches, all on by default: they are what makes the bug show.
var stim_fire := true
var stim_weave := true
var stim_hits := true

## id -> {label, get: Callable, set: Callable, alt: Variant}
var suspects: Dictionary = {}
## Suspect ids a hunt flips, in order. Defaults to every registered suspect.
var hunt_ids: Array[String] = []
## Every finished run: {label, flips: {id: value}, metrics: {name: value}, time}.
var runs: Array[Dictionary] = []

var _samples: Dictionary = {}
var _recording := false
var _t := 0.0
var _phase_warm := false
var _current: Dictionary = {}
var _restore: Dictionary = {}
var _queue: Array[Dictionary] = []
var _hunting := false
var _hit_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_register_builtin_suspects()
	set_process(false)


func _exit_tree() -> void:
	_stop_probe()
	if _recording:
		_apply(_restore)


# --- Suspects -------------------------------------------------------------------

## Add a variable to suspect. [param alt] is the value a hunt flips it to
## (for a bool, pass [code]null[/code] to mean "the opposite of now").
func register_suspect(id: String, label: String, getter: Callable, setter: Callable, alt: Variant = null) -> void:
	suspects[id] = {"label": label, "get": getter, "set": setter, "alt": alt}
	if not hunt_ids.has(id):
		hunt_ids.append(id)


func _register_builtin_suspects() -> void:
	for pair: Array in [
		["shot_stable_frame", "Guns read off the steady frame"],
		["beam_camera_aim", "Held beam aims along the camera (old bug)"],
		["hit_squash_stretch", "Squash & stretch on hit"],
		["hit_knockback", "Knockback on hit"],
		["knockback_visual", "Knockback moves the hull only"],
		["aim_assist_enabled", "Aim assist"],
		["offaxis_guns_hold", "Side/rear guns hold fire"],
	]:
		var field: String = pair[0]
		register_suspect(field, pair[1],
			func() -> Variant: return JuiceSettings.get_effect(field),
			func(v: Variant) -> void: JuiceSettings._set_bool(field, bool(v)))
	for trio: Array in [
		["muzzle_convergence_deg", "Gun convergence cone", 180.0, 12.0],
		["player_spread_mult", "Your spread", 0.0, 0.3],
		["player_recoil", "Recoil on your ship", 0.0, 0.1],
	]:
		var field: String = trio[0]
		var a: float = trio[2]
		var b: float = trio[3]
		register_suspect(field, trio[1],
			func() -> Variant: return JuiceSettings.get_float(field),
			func(v: Variant) -> void: JuiceSettings._load_float(field, float(v)),
			# Flip to whichever end is further from where the dial sits.
			func(now: float) -> float: return a if absf(now - a) > absf(now - b) else b)
	register_suspect("physics_interpolation", "Physics interpolation",
		func() -> Variant: return get_tree().physics_interpolation,
		func(v: Variant) -> void: get_tree().physics_interpolation = bool(v))
	register_suspect("facing_target", "Face locked target",
		func() -> Variant: return root.facing_target if root != null else false,
		func(v: Variant) -> void:
			if root != null:
				root.facing_target = bool(v))


## The value a hunt tries for [param id]: its registered alternative, the
## opposite for a bool, or whatever a callable alternative picks from now.
func alt_value(id: String) -> Variant:
	var s: Dictionary = suspects[id]
	var now: Variant = (s["get"] as Callable).call()
	var alt: Variant = s["alt"]
	if alt is Callable:
		return (alt as Callable).call(now)
	if alt == null:
		return not bool(now)
	return alt


# --- Runs -------------------------------------------------------------------------

## Record one run with [param flips] ({suspect id: value}) applied for its
## duration, labelled [param label]. Everything flipped is put back after.
func start_run(label: String, flips: Dictionary = {}) -> void:
	if _recording:
		return
	_current = {"label": label, "flips": flips.duplicate()}
	_restore = {}
	for id: String in flips.keys():
		if suspects.has(id):
			_restore[id] = (suspects[id]["get"] as Callable).call()
	_apply(flips)
	_samples = {}
	_recording = true
	_phase_warm = true
	_t = WARMUP
	_hit_timer = 0.0
	# The same stimulus every run, so runs differ only by what was flipped.
	_rng.seed = 1234
	SystemsSim.shot_probe = _on_shot
	set_process(true)
	status_changed.emit("Recording: %s" % label)


## Baseline, then each of [member hunt_ids] flipped on its own, then a second
## baseline (so drift between the first and last run is visible).
func start_hunt() -> void:
	if _recording:
		return
	_queue.clear()
	_queue.append({"label": "baseline", "flips": {}})
	for id: String in hunt_ids:
		if suspects.has(id):
			_queue.append({"label": String(suspects[id]["label"]), "flips": {id: alt_value(id)}, "suspect": id})
	_queue.append({"label": "baseline (again)", "flips": {}})
	_hunting = true
	runs.clear()
	_next_in_queue()


func is_busy() -> bool:
	return _recording or _hunting


func cancel() -> void:
	_queue.clear()
	_hunting = false
	if _recording:
		_finish_run()


func clear_runs() -> void:
	runs.clear()


## Feed a custom metric channel while recording (ignored otherwise). Each
## channel reports mean, 95th percentile and max.
func record(channel: String, value: float) -> void:
	if not _recording or _phase_warm:
		return
	# A plain Array, not a packed one: packed arrays are values, so appending
	# to the one read out of the dictionary would append to a copy.
	if not _samples.has(channel):
		_samples[channel] = []
	(_samples[channel] as Array).append(value)


func _process(delta: float) -> void:
	if not _recording:
		return
	_drive_stimulus(delta)
	_t -= delta
	if _t > 0.0:
		return
	if _phase_warm:
		_phase_warm = false
		_t = run_time
		return
	_finish_run()


func _drive_stimulus(delta: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	if stim_fire:
		root.set_firing(true)
	if stim_weave:
		var time := Time.get_ticks_msec() / 1000.0
		root.set_stick(Vector2(sin(time * 2.3) * 0.7, sin(time * 1.7 + 1.0) * 0.4))
	if stim_hits:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			_hit_timer = 0.35
			var m := root.active_model()
			if m != null:
				var dir := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized()
				if JuiceSettings.hit_squash_stretch:
					m.squash_from_weapon_hit(dir, 0.6)
				if JuiceSettings.hit_knockback:
					m.apply_knockback(-dir, 8.0)


func _finish_run() -> void:
	_recording = false
	set_process(false)
	_stop_probe()
	if root != null and is_instance_valid(root):
		if stim_fire:
			root.set_firing(false)
		if stim_weave:
			root.set_stick(Vector2.ZERO)
	_apply(_restore)
	var run := _current.duplicate()
	run["metrics"] = _summarise()
	run["time"] = Time.get_datetime_string_from_system()
	runs.append(run)
	_append_csv(run)
	run_finished.emit(run)
	if _hunting:
		_next_in_queue()
	else:
		status_changed.emit("Done: %s" % String(run["label"]))


func _next_in_queue() -> void:
	if _queue.is_empty():
		_hunting = false
		var verdict := verdict()
		status_changed.emit(String(verdict.get("text", "")))
		hunt_finished.emit(verdict)
		return
	var next: Dictionary = _queue.pop_front()
	start_run(String(next["label"]), next["flips"])
	_current["suspect"] = next.get("suspect", "")


func _apply(values: Dictionary) -> void:
	for id: String in values.keys():
		if suspects.has(id):
			(suspects[id]["set"] as Callable).call(values[id])


func _stop_probe() -> void:
	if SystemsSim.shot_probe.is_valid() and SystemsSim.shot_probe.get_object() == self:
		SystemsSim.shot_probe = Callable()


## The shot probe: only the guns the player is firing count.
func _on_shot(rig: SystemsSim, _origin: Vector3, dir: Vector3, ideal: Vector3, _weapon_id: String, is_beam: bool) -> void:
	if root == null or rig != root.active_systems():
		return
	var dev := rad_to_deg(dir.angle_to(ideal))
	record("shot_dev", dev)
	if is_beam:
		record("beam_dev", dev)
	else:
		record("bolt_dev", dev)


func _summarise() -> Dictionary:
	var out := {}
	for channel: String in _samples.keys():
		var arr := PackedFloat32Array(_samples[channel] as Array)
		if arr.is_empty():
			continue
		var sorted := arr.duplicate()
		sorted.sort()
		var total := 0.0
		for v in arr:
			total += v
		out[channel + "_n"] = arr.size()
		out[channel + "_mean"] = total / float(arr.size())
		out[channel + "_p95"] = sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)]
		out[channel + "_max"] = sorted[sorted.size() - 1]
	return out


## The hunt's ranking: every single-suspect run against the baseline, by how
## much flipping that suspect moved [constant RANK_METRIC]. The top mover that
## *reduced* it is named as the likely source.
## {text, baseline, ranked: [{id, label, value, delta}]}
func verdict() -> Dictionary:
	var base := -1.0
	for run in runs:
		if String(run.get("label", "")) == "baseline":
			base = float(run["metrics"].get(RANK_METRIC, -1.0))
	var ranked: Array[Dictionary] = []
	for run in runs:
		var sid := String(run.get("suspect", ""))
		if sid == "":
			continue
		var v := float(run["metrics"].get(RANK_METRIC, -1.0))
		ranked.append({"id": sid, "label": run["label"], "value": v, "delta": v - base,
			"flipped_to": run["flips"].get(sid)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["delta"]) < float(b["delta"]))
	var text := "No shots recorded — is a weapon equipped and firing?"
	if base >= 0.0 and not ranked.is_empty():
		var top: Dictionary = ranked[0]
		if float(top["delta"]) < -maxf(base * 0.2, 0.05):
			text = "Likely source: \"%s\" (set to %s) cut the average miss %.2f° → %.2f°." % [
				top["label"], str(top["flipped_to"]), base, float(top["value"])]
		else:
			var worst: Dictionary = ranked[ranked.size() - 1]
			text = "Nothing flipped made the shots straighter (baseline %.2f°)." % base
			if float(worst["delta"]) > maxf(base * 0.2, 0.05):
				text += " Flipping \"%s\" made them worse (%.2f°) — it is what keeps them straight now." % [
					worst["label"], float(worst["value"])]
	return {"text": text, "baseline": base, "ranked": ranked}


func _append_csv(run: Dictionary) -> void:
	var exists := FileAccess.file_exists(CSV_PATH)
	var f := FileAccess.open(CSV_PATH, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if not exists:
		f.store_line("time,label,flips,shots,mean_deg,p95_deg,max_deg,beam_mean_deg")
	var m: Dictionary = run["metrics"]
	f.store_line("%s,\"%s\",\"%s\",%d,%.3f,%.3f,%.3f,%.3f" % [
		run["time"], run["label"], JSON.stringify(run["flips"]).replace("\"", "'"),
		int(m.get("shot_dev_n", 0)), float(m.get("shot_dev_mean", -1.0)),
		float(m.get("shot_dev_p95", -1.0)), float(m.get("shot_dev_max", -1.0)),
		float(m.get("beam_dev_mean", -1.0))])
