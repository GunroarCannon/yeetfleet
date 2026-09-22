extends SceneTree

func _init() -> void:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_disabled;

uniform float shading_bands : hint_range(0.0, 5.0) = 3.0;
uniform float spec_mult : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	ALBEDO = vec3(0.5);
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	if (shading_bands > 0.5) {
		float band = smoothstep(-0.25, -0.15, NdotL) * 0.45 + smoothstep(0.12, 0.22, NdotL) * 0.55;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (band * ATTENUATION);
		vec3 half_vec = normalize(VIEW + LIGHT);
		float NdotH = max(dot(NORMAL, half_vec), 0.0);
		float spec = smoothstep(0.80, 0.88, pow(NdotH, 24.0 * (1.0 - ROUGHNESS)));
		SPECULAR_LIGHT += LIGHT_COLOR * (spec * spec_mult * ATTENUATION * 1.8);
	} else {
		float diff = max(NdotL, 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (diff * ATTENUATION);
		vec3 half_vec = normalize(VIEW + LIGHT);
		float NdotH = max(dot(NORMAL, half_vec), 0.0);
		float spec = pow(NdotH, 16.0 / max(ROUGHNESS * ROUGHNESS, 0.01));
		SPECULAR_LIGHT += LIGHT_COLOR * (spec * ATTENUATION);
	}
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = s
	print("Shader compilation successful!")
	quit()
