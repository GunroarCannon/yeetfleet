## PerformanceSettings: the smoothness/cost dials, persisted, applied live.
##
## Edited from the flight HUD's ⚡ Performance panel. Every field is saved to
## `user://performance.cfg` on change and survives restarts. Core, like
## [Session]: engine types only, never another module's. The modules that pay a
## cost (AI spawner, effects, debris) read these fields themselves.
##
## [method apply] pushes the engine-level ones (frame pacing, physics rate and
## interpolation, viewport resolution/AA/LOD) onto a [SceneTree].
## [method apply_to_node] handles the per-node ones (light shadows, world glow)
## and is called for every node as it enters the tree.
class_name PerformanceSettings
extends RefCounted

const SETTINGS_PATH := "user://performance.cfg"
const SECTION := "performance"

## Smooth rendering between 60 Hz physics ticks. Without it, on any display
## faster than 60 Hz every ship (and the camera following it) moves in 60 Hz
## steps: visible judder at 120/144 Hz.
static var physics_interpolation := true
## Frame cap, 0 = uncapped.
static var max_fps := 0
## 0 off, 1 on, 2 adaptive.
static var vsync := 1
## 3D render resolution as a fraction of the window (0.5–1.0). Multiplies with
## the Settings menu's High-res supersampling.
static var render_scale := 1.0
## MSAA level: 0 off, 1 = 2×, 2 = 4×, 3 = 8×.
static var msaa := 0
static var fxaa := false
## 0 no shadows, 1 sun only, 2 every light.
static var shadows := 2
## Bloom/glow on the world environment.
static var glow := true
## Physics simulation rate. Higher is more precise and costs more CPU; with
## [member physics_interpolation] on, 60 already looks smooth.
static var physics_tps := 60
## Live AI ship cap for the spawner.
static var max_ai_ships := 12
## Concurrent addon effects (hit sparks, explosions) before extra ones are
## skipped. Explosions for ship deaths and part loss always spawn.
static var vfx_budget := 32
## Live wreckage/debris cap: past it, the oldest piece is freed.
static var max_debris := 120
## Multiplier on how long debris lives.
static var debris_lifetime := 1.0
## Mesh LOD aggressiveness: pixels of error allowed before a lower LOD is used.
static var mesh_lod := 1.0

static var _loaded := false


## Three reference points. "Smoothest" is what "all set to high performance"
## means: every dial at the setting that costs least per frame.
const PRESETS := {
	"Smoothest": {
		"physics_interpolation": true, "max_fps": 0, "vsync": 1, "render_scale": 0.75,
		"msaa": 0, "fxaa": true, "shadows": 0, "glow": false, "physics_tps": 60,
		"max_ai_ships": 6, "vfx_budget": 12, "max_debris": 40, "debris_lifetime": 0.4,
		"mesh_lod": 4.0,
	},
	"Balanced": {
		"physics_interpolation": true, "max_fps": 0, "vsync": 1, "render_scale": 1.0,
		"msaa": 0, "fxaa": true, "shadows": 1, "glow": true, "physics_tps": 60,
		"max_ai_ships": 12, "vfx_budget": 32, "max_debris": 120, "debris_lifetime": 1.0,
		"mesh_lod": 1.0,
	},
	"Best quality": {
		"physics_interpolation": true, "max_fps": 0, "vsync": 1, "render_scale": 1.0,
		"msaa": 2, "fxaa": false, "shadows": 2, "glow": true, "physics_tps": 120,
		"max_ai_ships": 20, "vfx_budget": 64, "max_debris": 250, "debris_lifetime": 1.5,
		"mesh_lod": 0.5,
	},
}


static func ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()


## Set one field by name and save. Static vars aren't reachable through
## [method Object.set], so this is a dispatch.
static func set_value(field: String, value: Variant) -> void:
	_assign(field, value)
	save_to_disk()


static func get_value(field: String) -> Variant:
	match field:
		"physics_interpolation": return physics_interpolation
		"max_fps": return max_fps
		"vsync": return vsync
		"render_scale": return render_scale
		"msaa": return msaa
		"fxaa": return fxaa
		"shadows": return shadows
		"glow": return glow
		"physics_tps": return physics_tps
		"max_ai_ships": return max_ai_ships
		"vfx_budget": return vfx_budget
		"max_debris": return max_debris
		"debris_lifetime": return debris_lifetime
		"mesh_lod": return mesh_lod
	return null


static func apply_preset(preset_name: String) -> void:
	var p: Dictionary = PRESETS.get(preset_name, {})
	for field: String in p:
		_assign(field, p[field])
	save_to_disk()


static func _assign(field: String, value: Variant) -> void:
	match field:
		"physics_interpolation": physics_interpolation = bool(value)
		"max_fps": max_fps = clampi(int(value), 0, 500)
		"vsync": vsync = clampi(int(value), 0, 2)
		"render_scale": render_scale = clampf(float(value), 0.5, 1.0)
		"msaa": msaa = clampi(int(value), 0, 3)
		"fxaa": fxaa = bool(value)
		"shadows": shadows = clampi(int(value), 0, 2)
		"glow": glow = bool(value)
		"physics_tps": physics_tps = clampi(int(value), 30, 240)
		"max_ai_ships": max_ai_ships = clampi(int(value), 0, 40)
		"vfx_budget": vfx_budget = clampi(int(value), 4, 128)
		"max_debris": max_debris = clampi(int(value), 10, 500)
		"debris_lifetime": debris_lifetime = clampf(float(value), 0.1, 3.0)
		"mesh_lod": mesh_lod = clampf(float(value), 0.25, 8.0)
		_: push_warning("PerformanceSettings: unknown field %s" % field)


const FIELDS := [
	"physics_interpolation", "max_fps", "vsync", "render_scale", "msaa", "fxaa",
	"shadows", "glow", "physics_tps", "max_ai_ships", "vfx_budget", "max_debris",
	"debris_lifetime", "mesh_lod",
]


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for field: String in FIELDS:
		cfg.set_value(SECTION, field, get_value(field))
	cfg.save(SETTINGS_PATH)


static func load_from_disk() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH, PerformanceSettings.load_from_disk) != OK:
		return
	for field: String in FIELDS:
		if cfg.has_section_key(SECTION, field):
			_assign(field, cfg.get_value(SECTION, field))


## Push the engine- and viewport-level settings. [param supersample] is the
## caller's own extra render scale (the Settings menu's High-res), multiplied
## in rather than overwritten.
static func apply(tree: SceneTree, supersample := 1.0) -> void:
	ensure_loaded()
	tree.physics_interpolation = physics_interpolation
	Engine.max_fps = max_fps
	Engine.physics_ticks_per_second = physics_tps
	# Enough catch-up steps that a slow frame at a high tick rate doesn't make
	# the simulation fall behind real time.
	Engine.max_physics_steps_per_frame = maxi(8, physics_tps / 15)
	if DisplayServer.get_name() != "headless":
		var modes := [
			DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE,
		]
		DisplayServer.window_set_vsync_mode(modes[vsync])
	var vp := tree.root
	vp.scaling_3d_scale = render_scale * supersample
	vp.msaa_3d = [
		Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X,
	][msaa]
	# FXAA does not exist on the Compatibility renderer: asking for it only
	# logged an error at every start.
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = mesh_lod
	_apply_recursive(tree.root)


static func _apply_recursive(node: Node) -> void:
	apply_to_node(node)
	for child in node.get_children():
		_apply_recursive(child)


## Per-node settings: light shadows and environment glow. Called on every node
## entering the tree, so lights on ships spawned later obey it too.
static func apply_to_node(node: Node) -> void:
	if node is DirectionalLight3D:
		var sun := node as Light3D
		_remember(sun, "perf_shadow", sun.shadow_enabled)
		sun.shadow_enabled = shadows >= 1 and bool(sun.get_meta("perf_shadow"))
	elif node is OmniLight3D or node is SpotLight3D:
		var light := node as Light3D
		_remember(light, "perf_shadow", light.shadow_enabled)
		light.shadow_enabled = shadows >= 2 and bool(light.get_meta("perf_shadow"))
	elif node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		if env != null:
			_remember(env, "perf_glow", env.glow_enabled)
			env.glow_enabled = glow and bool(env.get_meta("perf_glow"))


## Store the value the scene authored, the first time only, so switching a
## dial back on restores what was there instead of forcing it on.
static func _remember(obj: Object, key: String, value: Variant) -> void:
	if not obj.has_meta(key):
		obj.set_meta(key, value)
