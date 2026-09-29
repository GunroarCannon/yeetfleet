// A floating power-up: a see-through sci-fi orb drawn as glowing latitude
// and longitude lines over a faint fill, the lines slowly scrolling.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform float lines_u = 12.0;
uniform float lines_v = 7.0;
uniform float fade = 1.0;

float grid_line(float x, float width) {
	float f = abs(fract(x) - 0.5);
	return smoothstep(0.5 - width, 0.5, f);
}

void fragment() {
	float lu = grid_line(UV.x * lines_u + TIME * 0.15, 0.06);
	float lv = grid_line(UV.y * lines_v, 0.07);
	float line = max(lu, lv);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), line * 0.5);
	ALPHA = clamp(0.06 + rim * 0.35 + line * 0.85, 0.0, 1.0) * fade;
}
