extends SceneTree
func _init():
    var s = load('res://modules/common/ai/ai_ship.gd')
    print('ai_ship.gd loaded: ', s != null)
    quit()
