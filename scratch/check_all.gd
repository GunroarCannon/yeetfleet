extends SceneTree
func _init():
    load('res://modules/common/juice/explosion_registry.gd')
    load('res://modules/flight/scripts/flight_root.gd')
    load('res://modules/flight/scripts/damage_system.gd')
    load('res://modules/ship_builder/scripts/editor/systems_sim.gd')
    load('res://modules/destruction_lab/scripts/destruction_lab_root.gd')
    print('ALL COMPILED OK')
    quit()
