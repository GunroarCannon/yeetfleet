class_name StyleToon extends StyleBase3D


func style_id() -> StringName:
	return &"toon"


func material_for(hint: StringName, p: FacePalette, g: FaceGenome) -> Material:
	var mat := ShaderMaterial.new()
	var shader := load("res://modules/alien_face_gen/render3d/shaders/toon_ramp.gdshader")
	mat.shader = shader
	
	# Set shader parameters based on palette
	match hint:
		&"shell":
			mat.set_shader_parameter("color_deep", p.skin_deep)
			mat.set_shader_parameter("color_base", p.skin_base)
			mat.set_shader_parameter("color_light", p.skin_light)
		&"eyes":
			mat.set_shader_parameter("color_deep", p.eye_pupil)
			mat.set_shader_parameter("color_base", p.eye_iris)
			mat.set_shader_parameter("color_light", p.eye_sclera)
			if g.eye_glow > 0.3:
				mat.set_shader_parameter("emission_color", p.eye_glow)
				mat.set_shader_parameter("emission_strength", g.eye_glow)
		&"crest":
			mat.set_shader_parameter("color_deep", p.skin_deep)
			mat.set_shader_parameter("color_base", p.crest)
			mat.set_shader_parameter("color_light", p.skin_light)
		_:
			mat.set_shader_parameter("color_deep", p.skin_deep)
			mat.set_shader_parameter("color_base", p.skin_base)
			mat.set_shader_parameter("color_light", p.skin_light)
	
	return mat
