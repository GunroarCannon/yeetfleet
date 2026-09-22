extends SceneTree

func _initialize() -> void:
	var lib := PartLibrary.instance()
	lib.load_all()
	var design: ShipDesign = null
	for p in lib.presets:
		var pid := String(p.get("id", ""))
		if pid == "wedge_fighter" or pid == "balanced_fighter":
			design = lib.build_preset_design(pid)
			break
	var ship_view := ShipAssembler.assemble(design, lib, 0.0, false, false)
	print("AABB: ", ship_view.aabb)
	for p in design.placements:
		print("Part: ", p.part_id, " pos: ", p.transform.origin)
	quit()
