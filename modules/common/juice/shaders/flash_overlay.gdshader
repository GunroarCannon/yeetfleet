// Full-screen colour flash, damage vignette and speed-line ramp, driven by
// ScreenFlash's uniforms. One draw for all three so they never compete for a
// second full-screen pass.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float speed_fraction : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = (UV - 0.5) * 2.0;
	float dist = length(centered);

	float vignette_amount = smoothstep(0.35, 1.0, dist) * vignette_strength;
	float speed_amount = smoothstep(0.4, 1.1, dist) * speed_fraction * 0.6;

	float vignette_alpha = vignette_amount * vignette_color.a;
	float speed_alpha = speed_amount * 0.4;
	float total_alpha = clamp(flash_strength + vignette_alpha + speed_alpha, 0.0, 1.0);

	vec3 mixed = flash_color.rgb * flash_strength
		+ vignette_color.rgb * vignette_alpha
		+ vec3(0.7, 0.85, 1.0) * speed_alpha;
	mixed /= max(flash_strength + vignette_alpha + speed_alpha, 0.0001);

	COLOR = vec4(mixed, total_alpha);
}
