## Boots [code]runner.tscn[/code] straight into an endless run: waits for the
## flight scene under it to finish building, then starts [EndlessRunner].
extends Node


func _ready() -> void:
	var root := get_parent() as FlightRoot
	if root == null:
		return
	# The flight scene builds its ship and HUD in its own _ready, which runs
	# after this child's; two frames and everything is in place.
	await get_tree().process_frame
	await get_tree().process_frame
	EndlessRunner.attach(root).start()
