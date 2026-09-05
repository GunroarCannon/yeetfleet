shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color_deep : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform vec4 color_base : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 color_light : source_color = vec4(0.9, 0.9, 0.9, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float emission_strength : source_range = 0.0;

void fragment() {
	float NdotL = dot(NORMAL, normalize(vec3(0.3, -0.5, 0.8)));
	
	vec3 albedo;
	if (NdotL < -0.1) {
		albedo = color_deep.rgb;
	} else if (NdotL < 0.3) {
		albedo = color_base.rgb;
	} else {
		albedo = color_light.rgb;
	}
	
	ALBEDO = albedo;
	
	if (emission_strength > 0.0) {
		EMISSION = emission_color.rgb * emission_strength;
	}
}
