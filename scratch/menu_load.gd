extends SceneTree
func _initialize() -> void:
	for p in ["res://modules/menu/scripts/menu_root.gd", "res://modules/menu/scripts/menu_stage.gd", "res://modules/menu/scripts/menu_props.gd", "res://modules/menu/scripts/pic_set.gd", "res://modules/menu/scripts/ui/home_screen.gd", "res://modules/menu/scripts/ui/map_screen.gd", "res://modules/menu/scripts/ui/level_map_view.gd", "res://modules/menu/scripts/ui/report_panel.gd", "res://modules/menu/scripts/ui/garage_screen.gd", "res://modules/menu/scripts/ui/settings_screen.gd", "res://modules/menu/scripts/ui/top_bar.gd", "res://modules/menu/scripts/ui/wallet_chip.gd", "res://modules/menu/scripts/ui/graffiti_title.gd", "res://modules/common/ui/slab_button.gd", "res://modules/common/ui/graffiti_icons.gd", "res://modules/common/ui/graffiti_style.gd", "res://modules/flight/scripts/ui/campaign_level_overlay.gd", "res://modules/flight/scripts/flight_root.gd"]:
		var s := load(p)
		print(p.get_file(), " ", "ok" if s != null and (s as GDScript).can_instantiate() else "FAIL")
	quit()
