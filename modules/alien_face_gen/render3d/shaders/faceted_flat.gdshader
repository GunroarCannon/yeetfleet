shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform vec3 light_dir : source_range = vec3(0.3, -0.5, 0.8);
uniform float ambient_strength : source_range = 0.2;

void fragment() {
	ALBEDO = albedo_color.rgb * COLOR.rgb;
}
