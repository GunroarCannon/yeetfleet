extends SceneTree
func _init():
    var s = load('res://modules/flight/scripts/space_scene.gd')
    print('space_scene.gd loaded: ', s != null)
    quit()
