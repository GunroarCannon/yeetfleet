## Regenerates the built-in [Palette] resources under [constant Palette.DIR].
##
## Palette values are data, but they are *derived* data: several palettes share a
## structure — the default one reproduces the literals this system replaced, and
## the themed ones are hue-rotations of the same roles. Writing those by hand as
## `.tres` means hand-converting every `Color("39c0ff")` into float components and
## keeping thirty-odd roles in step across five files. This tool builds them in
## code from the same literals the game used, so a palette is a readable list of
## hex strings and the resource files are output.
##
## Run:  "$GD" --path . --headless --script modules/style/tools/make_palettes.gd
##
## Overwrites the existing files. Each palette's [member Palette.id] is its file
## name, which is what [method StyleSettings.set_palette_id] saves.
extends SceneTree


func _init() -> void:
	_write("nebula", "Nebula", _nebula())
	_write("toon", "Toon", _toon())
	_write("rust", "Rust Belt", _rust())
	_write("ice", "Ice Field", _ice())
	_write("mono", "Mono", _mono())
	print("wrote %d palettes to %s" % [5, Palette.DIR])
	quit()


## The look the game shipped with: every value here is the literal it replaced.
##
## This is the one palette whose job is to be invisible — with it selected, the
## game is pixel-identical to the pre-palette build, which is what makes the
## palette rollout safe to land before any of the themed ones are tuned.
func _nebula() -> Palette:
	var p := Palette.new()
	p.background = Color("03050a")
	p.ambient = Color("2a3448")
	p.star = Color(1.0, 0.85, 0.55)
	p.nebula_core = Color(1.0, 0.55, 0.28)
	p.nebula_edge = Color(0.35, 0.15, 0.55)
	p.hull_primary = Color(0.29, 0.33, 0.40)
	p.hull_accent = Color(0.87, 0.55, 0.16)
	p.hull_trim = Color(0.09, 0.10, 0.13)
	p.rock_light = Color("8d97a6")
	p.rock_mid = Color("6a6257")
	p.rock_dark = Color("3d3831")
	p.rock_accent = Color("d0a24a")
	p.metal_light = Color(0.86, 0.90, 1.0)
	p.metal_mid = Color(0.45, 0.42, 0.40)
	p.metal_dark = Color(0.09, 0.10, 0.13)
	p.planet_primary = Color(0.45, 0.32, 0.22)
	p.planet_secondary = Color(0.68, 0.55, 0.38)
	p.planet_water = Color(0.09, 0.22, 0.38)
	p.planet_ring = Color(0.75, 0.70, 0.62)
	p.planet_cloud = Color(0.95, 0.96, 1.0)
	p.planet_atmosphere = Color(0.45, 0.72, 1.0)
	p.ui_bg_deep = Color("0b0e13")
	p.ui_bg_panel = Color("141922")
	p.ui_bg_panel_alt = Color("1b2230")
	p.ui_bg_field = Color("0e131b")
	p.ui_bg_hover = Color("232c3d")
	p.ui_border = Color("2b3546")
	p.ui_border_strong = Color("3f4c63")
	p.ui_text = Color("d7dee8")
	p.ui_text_dim = Color("8b97a8")
	p.ui_text_strong = Color("f2f6fb")
	p.ui_accent = Color("39c0ff")
	p.ui_accent_dim = Color("1d6f96")
	p.ui_good = Color("5ddba0")
	p.ui_warn = Color("ffc65c")
	p.ui_bad = Color("ff7a6b")
	p.ui_select = Color("ffd84d")
	p.valid = Color("39c0ff")
	p.invalid = Color("ff8a3d")
	p.socket = Color("7d8b9c")
	p.grid = Color(0.30, 0.36, 0.44, 0.35)
	p.beam = Color("6ff0d0")
	return p


## Saturated primaries on a light, warm ground — the palette the cartoony look
## wants. High value, high saturation, and the hull trim is lifted well off black
## because a toon outline reads as a drawn line and a near-black trim fights it.
func _toon() -> Palette:
	var p := _nebula()
	p.background = Color("1b2a4a")
	p.ambient = Color("6b7fa8")
	p.star = Color("ffe066")
	p.nebula_core = Color("ff9f68")
	p.nebula_edge = Color("8a6ad6")
	p.hull_primary = Color("5aa9e6")
	p.hull_accent = Color("ffb703")
	p.hull_trim = Color("35435c")
	p.rock_light = Color("b9c4d4")
	p.rock_mid = Color("8d97a6")
	p.rock_dark = Color("5f6b7d")
	p.rock_accent = Color("ffd166")
	p.metal_light = Color("eef3fb")
	p.metal_mid = Color("a9b6c9")
	p.metal_dark = Color("5a6478")
	p.planet_primary = Color("7bc86c")
	p.planet_secondary = Color("c7e88f")
	p.planet_water = Color("4aa3d8")
	p.planet_ring = Color("f2d7a0")
	p.planet_cloud = Color("ffffff")
	p.planet_atmosphere = Color("9fd8ff")
	p.ui_accent = Color("5aa9e6")
	p.ui_accent_dim = Color("2f6f9e")
	p.ui_good = Color("7bd88f")
	p.ui_bad = Color("ff7b6b")
	p.ui_select = Color("ffb703")
	p.valid = Color("5aa9e6")
	p.invalid = Color("ff9f1c")
	p.socket = Color("94a3b8")
	p.beam = Color("8ff0d0")
	return p


## Soft-lit vinyl toys on a deep indigo night: the look of the art-direction
## references (indigo hulls with orange and lime accents, a pink nebula, warm
## mauve rocks). Written by hand to toybox.tres first; kept here so the values
## live next to the other palettes'.
func _toybox() -> Palette:
	var p := _nebula()
	# The void is scaled up hard on its way to the sky gradient: a navy of
	# (0.03, 0.02, 0.10) rendered as electric blue. Keep it near black.
	p.background = Color(0.022, 0.016, 0.045)
	p.ambient = Color("221c48")
	p.star = Color("ffd98a")
	p.nebula_core = Color("8a3c6e")
	p.nebula_edge = Color("1e1650")
	p.hull_primary = Color("4b4fc4")
	p.hull_accent = Color("ff9a3c")
	p.hull_trim = Color("2c2a5a")
	p.rock_light = Color("c4a8b4")
	p.rock_mid = Color("9a7f90")
	p.rock_dark = Color("6a5572")
	p.rock_accent = Color("ffcf6b")
	p.metal_light = Color("eeeaff")
	p.metal_mid = Color("a9a3cf")
	p.metal_dark = Color("4a4470")
	p.planet_primary = Color("7fcf8a")
	p.planet_secondary = Color("f3d98b")
	p.planet_water = Color("5fb6f0")
	p.planet_ring = Color("f5cfa0")
	p.planet_cloud = Color("ffffff")
	p.planet_atmosphere = Color("b8a6ff")
	p.ui_bg_deep = Color("110f24")
	p.ui_bg_panel = Color("1b1838")
	p.ui_bg_panel_alt = Color("24204a")
	p.ui_bg_field = Color("15122c")
	p.ui_bg_hover = Color("2e2a5c")
	p.ui_border = Color("3a3570")
	p.ui_border_strong = Color("57509a")
	p.ui_text = Color("e8e6ff")
	p.ui_text_dim = Color("9d97c9")
	p.ui_text_strong = Color("ffffff")
	p.ui_accent = Color("7ea8ff")
	p.ui_accent_dim = Color("4a5fb0")
	p.ui_good = Color("7ee06a")
	p.ui_warn = Color("ffd166")
	p.ui_bad = Color("ff6b8b")
	p.ui_select = Color("ffb347")
	p.valid = Color("7ea8ff")
	p.invalid = Color("ff9a3c")
	p.hover = Color("ffe28a")
	p.socket = Color("a9a3cf")
	p.beam = Color("8ff0d0")
	p.grid = Color(0.5, 0.46, 0.8, 0.35)
	return p


## Warm oxide and burnt steel. The hull is the same family as the rock, so a ship
## parked on an asteroid reads as belonging to the same place.
func _rust() -> Palette:
	var p := _nebula()
	p.background = Color("120c08")
	p.ambient = Color("4a3527")
	p.star = Color("ffcf8a")
	p.nebula_core = Color("ff7a3d")
	p.nebula_edge = Color("5c2b1a")
	p.hull_primary = Color("8a6a52")
	p.hull_accent = Color("e0683a")
	p.hull_trim = Color("2b1e16")
	p.rock_light = Color("a38d75")
	p.rock_mid = Color("7a6450")
	p.rock_dark = Color("463527")
	p.rock_accent = Color("e0a24a")
	p.metal_light = Color("d8c3a8")
	p.metal_mid = Color("8a7561")
	p.metal_dark = Color("33251b")
	p.planet_primary = Color("8a5a3a")
	p.planet_secondary = Color("c08d5c")
	p.planet_water = Color("3a2a35")
	p.planet_ring = Color("b08a6a")
	p.planet_cloud = Color("f0e2d0")
	p.planet_atmosphere = Color("d89a6a")
	p.ui_accent = Color("e0883a")
	p.ui_accent_dim = Color("8a4a1c")
	p.ui_good = Color("a8c07a")
	p.ui_warn = Color("ffb03d")
	p.ui_bad = Color("ff5f45")
	p.ui_select = Color("ffc857")
	p.valid = Color("e0883a")
	p.invalid = Color("ff6b35")
	p.socket = Color("9a8672")
	p.beam = Color("7fd8c0")
	return p


## Cold blues on a near-black ground, with a white sun. Desaturated on purpose:
## this is the palette for reading silhouette rather than surface.
func _ice() -> Palette:
	var p := _nebula()
	p.background = Color("04070f")
	p.ambient = Color("25384f")
	p.star = Color("eaf4ff")
	p.nebula_core = Color("8fd4ff")
	p.nebula_edge = Color("243a6b")
	p.hull_primary = Color("9fb4cc")
	p.hull_accent = Color("4fc3f7")
	p.hull_trim = Color("12202e")
	p.rock_light = Color("c3d3e0")
	p.rock_mid = Color("8fa4b8")
	p.rock_dark = Color("4a5c6e")
	p.rock_accent = Color("7fb8d8")
	p.metal_light = Color("f0f7ff")
	p.metal_mid = Color("9db0c4")
	p.metal_dark = Color("1b2836")
	p.planet_primary = Color("8fa8c0")
	p.planet_secondary = Color("c8d8e8")
	p.planet_water = Color("1e3a5c")
	p.planet_ring = Color("d0e0f0")
	p.planet_cloud = Color("ffffff")
	p.planet_atmosphere = Color("7fc4ff")
	p.ui_accent = Color("4fc3f7")
	p.ui_accent_dim = Color("1e6a92")
	p.ui_good = Color("6fe0c0")
	p.ui_warn = Color("ffd07a")
	p.ui_bad = Color("ff7a8a")
	p.ui_select = Color("a8dcff")
	p.valid = Color("4fc3f7")
	p.invalid = Color("ff9a5c")
	p.socket = Color("7d93a8")
	p.beam = Color("a8f0ff")
	return p


## Greys only, keyed off the interface's grey ramp. The palette to check a hull
## reads without colour carrying any of it — a silhouette and lighting test.
func _mono() -> Palette:
	var p := _nebula()
	p.background = Color("0a0a0a")
	p.ambient = Color("333333")
	p.star = Color("f2f2f2")
	p.nebula_core = Color("8c8c8c")
	p.nebula_edge = Color("2e2e2e")
	p.hull_primary = Color("737373")
	p.hull_accent = Color("b8b8b8")
	p.hull_trim = Color("1f1f1f")
	p.rock_light = Color("a6a6a6")
	p.rock_mid = Color("7a7a7a")
	p.rock_dark = Color("454545")
	p.rock_accent = Color("c9c9c9")
	p.metal_light = Color("d9d9d9")
	p.metal_mid = Color("8c8c8c")
	p.metal_dark = Color("262626")
	p.planet_primary = Color("7a7a7a")
	p.planet_secondary = Color("adadad")
	p.planet_water = Color("3d3d3d")
	p.planet_ring = Color("bfbfbf")
	p.planet_cloud = Color("ededed")
	p.planet_atmosphere = Color("9e9e9e")
	p.ui_accent = Color("d0d0d0")
	p.ui_accent_dim = Color("6e6e6e")
	p.ui_good = Color("c4c4c4")
	p.ui_warn = Color("e8e8e8")
	p.ui_bad = Color("9a9a9a")
	p.ui_select = Color("f2f2f2")
	p.valid = Color("d0d0d0")
	p.invalid = Color("8f8f8f")
	p.socket = Color("8a8a8a")
	p.grid = Color(0.55, 0.55, 0.55, 0.35)
	p.beam = Color("e0e0e0")
	return p


## Save one palette as `<DIR>/<id>.tres`, stamping its id and display name.
func _write(id: String, display_name: String, palette: Palette) -> void:
	palette.id = id
	palette.display_name = display_name
	DirAccess.make_dir_recursive_absolute(Palette.DIR)
	var path := Palette.DIR.path_join(id + ".tres")
	var err := ResourceSaver.save(palette, path)
	if err != OK:
		printerr("failed to save %s: %d" % [path, err])
	else:
		print("  ", path)
