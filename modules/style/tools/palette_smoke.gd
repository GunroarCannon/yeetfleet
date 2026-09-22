## Headless smoke test for the palette half of modules/style.
##
##     godot --headless --path . --script modules/style/tools/palette_smoke.gd
##
## What this locks down:
##   - every built-in palette loads, and every one defines every role in
##     [constant Palette.ROLES] (the key/property drift check — the table and the
##     exports are two lists that have to agree)
##   - the default palette reproduces [constant Palette.DEFAULTS] exactly, so the
##     palette rollout stays invisible until somebody picks a different one
##   - switching palettes actually changes the colours, emits palette_changed, and
##     persists an id
##   - the derived helpers return what their callers assume: four distinct rock
##     families, four nebula washes, and planet colours that stay near their anchor
##
## See TECHNICAL_PLAN.md §M3 for the style module description.

extends SceneTree

var _failures: Array[String] = []
var _reported := 0


func _initialize() -> void:
	print("── palette smoke test ────────────────────────────────")
	await _test_palettes_load()
	await _test_every_role_resolves()
	await _test_default_palette_matches_defaults()
	await _test_switching_changes_colour()
	await _test_swatches_cover_roles()
	await _test_derived_helpers()
	_finish()


func _test_palettes_load() -> void:
	var all := Palette.all()
	if all.size() < 5:
		_failures.append("expected at least 5 built-in palettes, found %d" % all.size())
	for p in all:
		if p.id == "":
			_failures.append("a palette loaded with no id (%s)" % p.resource_path)
		if p.display_name == "":
			_failures.append("palette '%s' has no display name" % p.id)
	_done("Built-in palettes load")


## The whole system turns on [constant Palette.ROLES] naming things that are
## actually exported properties. A typo there is silent at runtime — [method
## Palette.get_role] would just fall back — so it is caught here instead.
func _test_every_role_resolves() -> void:
	for p in Palette.all():
		for row: Dictionary in Palette.ROLES:
			var key := String(row["key"])
			if not p.get(key) is Color:
				_failures.append("palette '%s' has no Color property '%s'" % [p.id, key])
			if String(row["label"]) == "" or String(row["group"]) == "":
				_failures.append("role '%s' is missing a label or group" % key)
	# And the defaults every role falls back to have to cover the same table.
	for row: Dictionary in Palette.ROLES:
		var key := String(row["key"])
		if not Palette.DEFAULTS.has(key):
			_failures.append("role '%s' has no entry in Palette.DEFAULTS" % key)
	_done("Every role resolves")


## The palette rollout is meant to be invisible: with the default palette selected
## the game should look exactly as it did before palettes existed. That only holds
## while this stays true.
func _test_default_palette_matches_defaults() -> void:
	var mgr := StyleManager.instance()
	var saved := mgr.current_palette
	var nebula := Palette.find_by_id("nebula")
	if nebula == null:
		_failures.append("no palette with id 'nebula'")
		mgr.current_palette = saved
		_done("Default palette is a no-op")
		return
	mgr.current_palette = nebula
	for row: Dictionary in Palette.ROLES:
		var key := String(row["key"])
		var want: Color = Palette.DEFAULTS[key]
		var got := Palette.color(key)
		if not got.is_equal_approx(want):
			_failures.append("default palette changed '%s': %s != %s" % [key, got, want])
	mgr.current_palette = saved
	_done("Default palette is a no-op")


func _test_switching_changes_colour() -> void:
	var mgr := StyleManager.instance()
	var saved := mgr.current_palette
	var saved_id := StyleSettings.palette_id
	var fired := {"count": 0}
	mgr.palette_changed.connect(func(_p: Palette) -> void: fired["count"] += 1)

	var before := Palette.color("hull_primary")
	# Reach for a palette that is genuinely different from the active one. The
	# player may already have any palette selected, including this test's first
	# choice — and switching to the palette you are already on changes nothing,
	# which would read as a failure of the code rather than of the fixture.
	var target := Palette.find_by_id("toon")
	if target == null or target == mgr.current_palette:
		target = Palette.find_by_id("mono")
	if target == null:
		_failures.append("no palette to switch to")
	else:
		# persist = false: this test must not overwrite the player's real setting.
		mgr.set_palette(target, false)
		if fired["count"] == 0:
			_failures.append("set_palette did not emit palette_changed")
		if Palette.color("hull_primary").is_equal_approx(before):
			_failures.append("switching to '%s' did not change hull_primary" % target.id)
		# persist=false must leave the saved id exactly as it was.
		if StyleSettings.palette_id != saved_id:
			_failures.append("set_palette(persist=false) wrote the saved id")
		# A role the target palette inherits from nothing must still resolve.
		if Palette.color("ui_text").a <= 0.0:
			_failures.append("an inherited UI role came back fully transparent")

	mgr.current_palette = saved
	_done("Switching recolours")


func _test_swatches_cover_roles() -> void:
	var toon := Palette.find_by_id("toon")
	if toon == null:
		_done("Swatches cover every role")
		return
	var rows := toon.swatches()
	if rows.size() != Palette.ROLES.size():
		_failures.append(
			"swatches() returned %d rows for %d roles" % [rows.size(), Palette.ROLES.size()]
		)
	for i in rows.size():
		var want := String((Palette.ROLES[i] as Dictionary)["key"])
		if String(rows[i]["key"]) != want:
			_failures.append("swatches() reordered at %d: %s != %s" % [i, rows[i]["key"], want])
		if not rows[i]["color"] is Color:
			_failures.append("swatch '%s' has no colour" % rows[i]["key"])
	_done("Swatches cover every role")


func _test_derived_helpers() -> void:
	# Four rock families, and they have to be genuinely different or a belt reads
	# as one asset repeated.
	var seen := {}
	for i in Palette.ROCK_FAMILIES:
		var family := Palette.rock_family(i)
		for key in ["primary", "accent", "trim"]:
			if not family.has(key):
				_failures.append("rock_family(%d) has no '%s'" % [i, key])
		seen[family["primary"]] = true
	if seen.size() < Palette.ROCK_FAMILIES:
		_failures.append("rock families are not distinct (%d unique)" % seen.size())
	# Out-of-range indices must wrap rather than error.
	if Palette.rock_family(Palette.ROCK_FAMILIES + 1)["primary"] != Palette.rock_family(1)["primary"]:
		_failures.append("rock_family did not wrap its index")

	var washes := {}
	for i in Palette.NEBULA_WASHES:
		var wash := Palette.nebula_wash(i)
		if not (wash.has("core") and wash.has("edge")):
			_failures.append("nebula_wash(%d) is missing core or edge" % i)
		if (wash["core"] as Color).a < 0.99:
			_failures.append("nebula_wash(%d) baked an alpha in; callers set their own" % i)
		washes[wash["core"]] = true
	if washes.size() < Palette.NEBULA_WASHES:
		_failures.append("nebula washes are not distinct (%d unique)" % washes.size())

	# A planet colour must stay in its anchor's neighbourhood, or "anchored to the
	# palette" is a claim the code does not keep.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var anchor := Palette.color("planet_primary")
	for i in 40:
		var c := Palette.planet_color(0, 0.07, rng)
		var turns := absf(c.h - anchor.h)
		turns = minf(turns, 1.0 - turns)
		if turns > 0.08:
			_failures.append("planet colour strayed %.3f turns from its anchor" % turns)
			break
	_done("Derived helpers")


func _done(label: String) -> void:
	var mark := "ok" if _failures.size() == _reported else "FAILED"
	_reported = _failures.size()
	print("  %-35s %s" % [label, mark])

func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("── PASS ──────────────────────────────────────────────────")
		quit(0)
	else:
		print("── FAIL (%d) ─────────────────────────────────────────────" % _failures.size())
		for f in _failures:
			print("  ✗ " + f)
		quit(1)
