class_name StylePaintedDecal extends StyleBase3D


func style_id() -> StringName:
	return &"painted_decal"


func material_for(hint: StringName, p: FacePalette, g: FaceGenome) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	match hint:
		&"eyes":
			if g.eye_glow > 0.3:
				mat.emission_enabled = true
				mat.emission = p.eye_glow
				mat.emission_energy_multiplier = g.eye_glow
		_:
			pass

	if p.is_emissive_palette and g.emissive_amount > 0.3:
		mat.emission_enabled = true
		mat.emission = p.eye_glow
		mat.emission_energy_multiplier = g.emissive_amount

	return mat
