// Radial streaks and vignette that ramp in with speed. Canvas layer, additive
// feel achieved with alpha rather than a blend mode so it composites cleanly
// over the flash overlay.
shader_type canvas_item;

uniform float speed_fraction : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);

void fragment() {
	vec2 centered = UV - 0.5;
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	float streak = sin(angle * 40.0) * 0.5 + 0.5;
	streak = smoothstep(0.7, 1.0, streak);

	float radial_mask = smoothstep(0.25, 0.9, dist) * speed_fraction;
	float vignette = smoothstep(0.35, 1.05, dist) * speed_fraction * 0.5;

	float alpha = streak * radial_mask * 0.5 + vignette;
	COLOR = vec4(line_color.rgb, clamp(alpha, 0.0, 1.0));
}
