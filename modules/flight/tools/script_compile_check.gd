## Loads a list of scripts so their bodies actually compile — the class-cache
## rescan does not, so a parse error otherwise only shows when a scene loads.
## Headless: `"$GD" --path . --headless --audio-driver Dummy --script
## modules/flight/tools/script_compile_check.gd`. Exit code 1 on any failure.
extends SceneTree

const SCRIPTS := [
	"res://modules/common/juice/juice_settings.gd",
	"res://modules/common/juice/juice_runtime.gd",
	"res://modules/common/juice/juice.gd",
	"res://modules/common/ai/ai_ship.gd",
	"res://modules/common/ai/ai_spawner.gd",
	"res://modules/flight/scripts/flight_model.gd",
	"res://modules/flight/scripts/flight_camera.gd",
	"res://modules/flight/scripts/flight_root.gd",
	"res://modules/ship_builder/scripts/editor/systems_sim.gd",
	"res://modules/flight/scripts/ui/flight_hud.gd",
	"res://modules/flight/scripts/ui/juice_settings_panel.gd",
	"res://modules/flight/scripts/ui/combat_stats_panel.gd",
	"res://modules/flight/scripts/ui/mobile_hud_profiles.gd",
	"res://modules/flight/scripts/ui/mobile_hud.gd",
	"res://modules/flight/scripts/ui/mobile_hud_fonts_panel.gd",
	"res://modules/flight/scripts/ui/virtual_stick.gd",
	"res://modules/flight/scripts/flight_scenarios.gd",
	"res://modules/flight/scripts/ui/scenario_panel.gd",
	"res://modules/common/ai/ai_fire_patterns.gd",
	"res://modules/flight/scripts/audio/space_audio.gd",
	"res://modules/flight/scripts/ui/interaction_markers.gd",
	"res://modules/flight/scripts/debug/bug_hunt.gd",
	"res://modules/flight/scripts/ui/bug_hunt_panel.gd",
	"res://modules/flight/scripts/ui/fly_as_panel.gd",
	"res://modules/common/planets/planet.gd",
	"res://modules/flight/scripts/space_scene.gd",
	"res://modules/core/scripts/session.gd",
]


func _initialize() -> void:
	var failed := 0
	for path: String in SCRIPTS:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			push_error("FAIL: %s did not compile" % path)
			failed += 1
		else:
			print("ok   ", path)
	print("script_compile_check: %d failed" % failed)
	quit(1 if failed > 0 else 0)
