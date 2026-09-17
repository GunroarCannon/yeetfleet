## reputation_smoke.gd — headless verification for modules/reputation/
##
## Run:
##   "$GD" --path . --headless --script modules/reputation/tools/reputation_smoke.gd
##
## All assertions must pass (exit code 0). No Godot scene required.
extends SceneTree

# ---------------------------------------------------------------------------
const PASS := "  [PASS] "
const FAIL := "  [FAIL] "
var _errors := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print(PASS + msg)
	else:
		printerr(FAIL + msg)
		_errors += 1

# ---------------------------------------------------------------------------
func _init() -> void:
	print("\n=== reputation smoke ===\n")

	_test_grudge()
	_test_session_rep_store_hostile()
	_test_session_rep_store_friendly_reduces_heat()
	_test_session_rep_store_decay()
	_test_session_rep_store_serialise()
	_test_witness_range()
	_test_witness_out_of_range()
	_test_recognition_thresholds()
	_test_recognition_label()
	_test_recognition_out_of_range()
	_test_saved_rep_store_delegates()
	_test_multiple_factions_isolated()
	_test_grudge_from_dict_roundtrip()

	print("\n--- %d assertion(s) failed ---\n" % _errors)
	quit(1 if _errors > 0 else 0)

# ---------------------------------------------------------------------------
# Grudge
# ---------------------------------------------------------------------------

func _test_grudge() -> void:
	print("-- Grudge --")
	var g := Grudge.new("player", "pirates", RepStore.ACTS.ATTACK, 5, 0.0)

	_assert(g.actor_id == "player",  "actor_id set")
	_assert(g.faction_id == "pirates", "faction_id set")
	_assert(g.act == RepStore.ACTS.ATTACK, "act set")
	_assert(g.severity == 5, "severity set")
	_assert(g.heat == float(5 * RepStore.HEAT_PER_SEVERITY), "heat initialised to severity × HEAT_PER_SEVERITY")

	# Tick advances decay.
	var alive := g.tick(1.0)
	_assert(alive, "grudge still alive after 1 second")
	_assert(g.heat < float(5 * RepStore.HEAT_PER_SEVERITY), "heat decreased after tick")

	# Tick until dead (max 500 iterations safety).
	var iters := 0
	while g.tick(10.0) and iters < 500:
		iters += 1
	_assert(not g.tick(10.0), "grudge dies when heat reaches zero")

# ---------------------------------------------------------------------------
# SessionRepStore — hostile path
# ---------------------------------------------------------------------------

func _test_session_rep_store_hostile() -> void:
	print("-- SessionRepStore hostile path --")
	var store := SessionRepStore.new()

	_assert(store.get_heat("player", "empire") == 0, "initial heat is 0")

	store.record_act("player", "empire", RepStore.ACTS.ATTACK, 3)
	var heat_after := store.get_heat("player", "empire")
	_assert(heat_after == 3 * RepStore.HEAT_PER_SEVERITY,
		"heat = severity × HEAT_PER_SEVERITY after attack")
	_assert(store.grudge_count() == 1, "one grudge recorded")

	# Second act on same faction accumulates.
	store.record_act("player", "empire", RepStore.ACTS.RAM, 2)
	var heat2 := store.get_heat("player", "empire")
	_assert(heat2 == (3 + 2) * RepStore.HEAT_PER_SEVERITY,
		"heat accumulates across multiple acts on same faction")
	_assert(store.grudge_count() == 2, "two grudges recorded")

	# Different faction is isolated.
	store.record_act("player", "traders", RepStore.ACTS.STEAL, 5)
	_assert(store.get_heat("player", "traders") == 5 * RepStore.HEAT_PER_SEVERITY,
		"traders heat is independent")
	_assert(store.get_heat("player", "empire") == heat2,
		"empire heat unchanged by traders act")

# ---------------------------------------------------------------------------
# SessionRepStore — friendly reduces heat
# ---------------------------------------------------------------------------

func _test_session_rep_store_friendly_reduces_heat() -> void:
	print("-- SessionRepStore friendly reduces heat --")
	var store := SessionRepStore.new()
	store.record_act("player", "empire", RepStore.ACTS.ATTACK, 5)
	var base_heat := store.get_heat("player", "empire")

	store.record_act("player", "empire", RepStore.ACTS.RESCUE, 3)
	var after_rescue := store.get_heat("player", "empire")
	_assert(after_rescue < base_heat,
		"heat decreases after friendly rescue act")
	_assert(after_rescue == max(0, base_heat - 3 * RepStore.COOL_PER_SEVERITY),
		"heat = base − cool_per_severity × severity")

	# Friendly acts alone leave heat at 0 (cannot go negative).
	var store2 := SessionRepStore.new()
	store2.record_act("player", "traders", RepStore.ACTS.PAYMENT, 10)
	_assert(store2.get_heat("player", "traders") == 0,
		"friendly act alone does not produce negative heat")

# ---------------------------------------------------------------------------
# SessionRepStore — decay over time
# ---------------------------------------------------------------------------

func _test_session_rep_store_decay() -> void:
	print("-- SessionRepStore decay --")
	var store := SessionRepStore.new()
	store.record_act("player", "pirates", RepStore.ACTS.ATTACK, 1)
	var initial := store.get_heat("player", "pirates")
	_assert(initial > 0, "heat > 0 after attack")

	# Tick a large amount to force full decay.
	store.tick(9999.0)
	_assert(store.get_heat("player", "pirates") == 0, "heat decays to 0 over time")
	_assert(store.grudge_count() == 0, "dead grudges are removed")

# ---------------------------------------------------------------------------
# SessionRepStore — serialise / deserialise round-trip
# ---------------------------------------------------------------------------

func _test_session_rep_store_serialise() -> void:
	print("-- SessionRepStore serialise round-trip --")
	var store := SessionRepStore.new()
	store.record_act("player", "empire", RepStore.ACTS.ATTACK, 4)
	store.record_act("player", "traders", RepStore.ACTS.RESCUE, 2)
	store.tick(5.0)  # Advance time so session_time is non-zero.

	var d := store.to_dict()
	_assert(d.has("grudges"), "to_dict has grudges key")
	_assert(d.has("friendly"), "to_dict has friendly key")
	_assert(d.has("session_time"), "to_dict has session_time key")

	var store2 := SessionRepStore.new()
	store2.from_dict(d)
	_assert(store2.get_heat("player", "empire") == store.get_heat("player", "empire"),
		"empire heat survives round-trip")
	_assert(store2.get_heat("player", "traders") == store.get_heat("player", "traders"),
		"traders heat survives round-trip")
	_assert(store2.grudge_count() == store.grudge_count(),
		"grudge count survives round-trip")

# ---------------------------------------------------------------------------
# Witness — in range
# ---------------------------------------------------------------------------

func _test_witness_range() -> void:
	print("-- Witness range --")
	var w := Witness.new()  # space_state = null → LOS always clear

	var act_pos := Vector3.ZERO
	var candidates := [
		{"position": Vector3(100, 0, 0), "faction_id": "empire", "id": "patrol_1"},
		{"position": Vector3(200, 0, 0), "faction_id": "traders", "id": "hauler_1"},
	]
	var observers := w.get_observers_positional(act_pos, candidates)
	_assert(observers.size() == 2, "both nearby ships witness the act")

# ---------------------------------------------------------------------------
# Witness — out of range
# ---------------------------------------------------------------------------

func _test_witness_out_of_range() -> void:
	print("-- Witness out of range --")
	var w := Witness.new()

	var act_pos := Vector3.ZERO
	var candidates := [
		{"position": Vector3(900, 0, 0), "faction_id": "empire", "id": "far_patrol"},
	]
	var observers := w.get_observers_positional(act_pos, candidates)
	_assert(observers.is_empty(), "ship beyond WITNESS_RANGE_M does not witness")

	# One in-range, one out.
	var mixed := [
		{"position": Vector3(100, 0, 0), "faction_id": "traders", "id": "near"},
		{"position": Vector3(1200, 0, 0), "faction_id": "pirates", "id": "far"},
	]
	var obs2 := w.get_observers_positional(act_pos, mixed)
	_assert(obs2.size() == 1, "only in-range ship witnesses in mixed set")
	_assert(obs2[0].get("id", "") == "near", "correct witness selected")

# ---------------------------------------------------------------------------
# Recognition — thresholds
# ---------------------------------------------------------------------------

func _test_recognition_thresholds() -> void:
	print("-- Recognition thresholds --")
	var store := SessionRepStore.new()

	# Unknown — no history.
	var r0 := Recognition.evaluate("player", "empire", store, 100.0)
	_assert(r0 == Recognition.RecognitionResult.UNKNOWN, "no history → UNKNOWN")

	# IDENTIFIED — heat between 1 and HOSTILE_THRESHOLD.
	store.record_act("player", "empire", RepStore.ACTS.STEAL, 1)
	var heat_identified := store.get_heat("player", "empire")
	if heat_identified < RepStore.HOSTILE_THRESHOLD:
		var r1 := Recognition.evaluate("player", "empire", store, 100.0)
		_assert(r1 == Recognition.RecognitionResult.IDENTIFIED,
			"small heat → IDENTIFIED")

	# HOSTILE — push past HOSTILE_THRESHOLD.
	# Calculate how much more we need.
	var need := RepStore.HOSTILE_THRESHOLD - store.get_heat("player", "empire") + 1
	var sev := ceili(float(need) / float(RepStore.HEAT_PER_SEVERITY))
	store.record_act("player", "empire", RepStore.ACTS.ATTACK, sev)
	var r2 := Recognition.evaluate("player", "empire", store, 100.0)
	_assert(r2 == Recognition.RecognitionResult.HOSTILE,
		"heat >= HOSTILE_THRESHOLD → HOSTILE")

	# KOS — push past KOS_THRESHOLD.
	var need_kos := RepStore.KOS_THRESHOLD - store.get_heat("player", "empire") + 1
	var sev_kos := ceili(float(need_kos) / float(RepStore.HEAT_PER_SEVERITY))
	store.record_act("player", "empire", RepStore.ACTS.ATTACK, sev_kos)
	var r3 := Recognition.evaluate("player", "empire", store, 100.0)
	_assert(r3 == Recognition.RecognitionResult.KOS,
		"heat >= KOS_THRESHOLD → KOS")

# ---------------------------------------------------------------------------
# Recognition — label strings
# ---------------------------------------------------------------------------

func _test_recognition_label() -> void:
	print("-- Recognition labels --")
	_assert(Recognition.label_for(Recognition.RecognitionResult.UNKNOWN)    == "",
		"UNKNOWN label is empty string")
	_assert(Recognition.label_for(Recognition.RecognitionResult.IDENTIFIED) == "IDENTIFIED",
		"IDENTIFIED label correct")
	_assert(Recognition.label_for(Recognition.RecognitionResult.HOSTILE)    == "IDENTIFIED: HOSTILE",
		"HOSTILE label correct")
	_assert(Recognition.label_for(Recognition.RecognitionResult.KOS)        == "KILL ORDER ACTIVE",
		"KOS label correct")

# ---------------------------------------------------------------------------
# Recognition — out of transponder range → UNKNOWN regardless of heat
# ---------------------------------------------------------------------------

func _test_recognition_out_of_range() -> void:
	print("-- Recognition out of transponder range --")
	var store := SessionRepStore.new()
	# Max heat.
	store.record_act("player", "empire", RepStore.ACTS.ATTACK, 10)
	var r := Recognition.evaluate("player", "empire", store,
		Recognition.TRANSPONDER_RANGE_M + 1.0)
	_assert(r == Recognition.RecognitionResult.UNKNOWN,
		"beyond transponder range → UNKNOWN even at max heat")

# ---------------------------------------------------------------------------
# SavedRepStore — delegates to SessionRepStore correctly
# ---------------------------------------------------------------------------

func _test_saved_rep_store_delegates() -> void:
	print("-- SavedRepStore delegates --")
	var store := SavedRepStore.new()
	store.record_act("player", "traders", RepStore.ACTS.ATTACK, 3)
	var h := store.get_heat("player", "traders")
	_assert(h == 3 * RepStore.HEAT_PER_SEVERITY,
		"SavedRepStore.get_heat delegates to SessionRepStore")

	var d := store.to_dict()
	_assert(d.has("grudges"), "SavedRepStore.to_dict delegates to SessionRepStore")

	var store2 := SavedRepStore.new()
	store2.from_dict(d)
	_assert(store2.get_heat("player", "traders") == h,
		"SavedRepStore.from_dict round-trip preserves heat")

# ---------------------------------------------------------------------------
# Multiple factions are isolated from each other
# ---------------------------------------------------------------------------

func _test_multiple_factions_isolated() -> void:
	print("-- Multiple faction isolation --")
	var store := SessionRepStore.new()
	store.record_act("player", "empire",  RepStore.ACTS.ATTACK, 5)
	store.record_act("player", "pirates", RepStore.ACTS.RESCUE, 4)
	store.record_act("player", "traders", RepStore.ACTS.STEAL,  2)

	var he := store.get_heat("player", "empire")
	var hp := store.get_heat("player", "pirates")
	var ht := store.get_heat("player", "traders")

	_assert(he > 0, "empire has heat")
	_assert(hp == 0, "pirates: only friendly act → heat = 0")
	_assert(ht > 0, "traders has heat")

	# Factions list.
	var factions := store.get_factions_for("player")
	_assert("empire" in factions,  "empire in factions list")
	_assert("traders" in factions, "traders in factions list")

# ---------------------------------------------------------------------------
# Grudge.from_dict round-trip
# ---------------------------------------------------------------------------

func _test_grudge_from_dict_roundtrip() -> void:
	print("-- Grudge from_dict round-trip --")
	var g := Grudge.new("npc_456", "empire", RepStore.ACTS.RAM, 7, 12.5)
	g.heat = 38.5  # Simulate partial decay.

	var d := g.to_dict()
	var g2 := Grudge.from_dict(d)

	_assert(g2.actor_id == g.actor_id,    "actor_id round-trip")
	_assert(g2.faction_id == g.faction_id, "faction_id round-trip")
	_assert(g2.act == g.act,              "act round-trip")
	_assert(g2.severity == g.severity,    "severity round-trip")
	_assert(absf(g2.heat - g.heat) < 0.001, "heat round-trip within tolerance")
	_assert(absf(g2.timestamp - g.timestamp) < 0.001, "timestamp round-trip")
