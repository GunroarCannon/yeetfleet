extends SceneTree
func _init():
    var s = load('res://modules/ship_builder/assets/ship_part.gdshader')
    print('ship_part.gdshader loaded: ', s != null)
    quit()
