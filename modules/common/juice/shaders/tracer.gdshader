// Beam core with soft glow and a travelling bright head. Meant for a quad
// with V running 0 (tail) to 1 (head) along the shot's direction of travel;
// head_position sweeps 0→1 once per shot so the bright point runs the beam's
// length instead of the whole beam popping in at once.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.6, 1.0, 0.9, 1.0);
uniform float head_position : hint_range(0.0, 1.0) = 1.0;
uniform float softness : hint_range(0.01, 1.0) = 0.3;

void fragment() {
	float along = UV.y;
	float radial = abs(UV.x - 0.5) * 2.0;

	// Core: bright centre line that fades toward edges.
	float core = smoothstep(1.0, 0.0, radial) * smoothstep(0.0, 0.1, along);
	// Glow: wider, softer halo around the core.
	float glow = smoothstep(1.0, 0.0, radial * 0.7) * 0.35;

	// Travelling head: bright point that moves along the beam.
	float head_dist = abs(along - head_position);
	float head = smoothstep(softness, 0.0, head_dist) * smoothstep(1.0, 0.0, radial * 0.5);

	// Tail fade: older parts of the beam are dimmer.
	float tail = smoothstep(head_position, 0.0, along) * 0.4;

	// Combine: core is brightest, head adds extra punch, glow fills the width.
	float alpha = clamp(core * 0.6 + head * 1.5 + glow + tail * 0.3, 0.0, 1.0);

	// Slightly overdrive the colour so the core reads as white-hot.
	vec3 col = mix(beam_color.rgb, vec3(1.0), core * 0.4);

	ALBEDO = col;
	ALPHA = alpha;
}
