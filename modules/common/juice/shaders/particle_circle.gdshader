// Masks a QuadMesh into a soft circle for particle effects.
// Used by ParticleBurst so sparks, embers, vapour and debris are
// round instead of square, without needing a circle mesh.
// Also used by engine halos via beam_color uniform.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float softness : hint_range(0.01, 0.5) = 0.15;
uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Core: bright centre that falls off toward edges.
	float core = 1.0 - smoothstep(0.0, 0.4, dist);
	// Soft edge: gentle falloff to transparent.
	float edge = 1.0 - smoothstep(1.0 - softness, 1.0, dist);
	// Combine: core is bright, edge is soft.
	float alpha = max(core * 0.6, edge);

	// Use beam_color uniform when set (engine halos), fall back to vertex color (particles).
	vec3 col = beam_color.rgb;
	float a = beam_color.a * alpha;
	// If beam_color is near-white and opaque, it was not set — use vertex color.
	if (beam_color.a > 0.99 && beam_color.r > 0.98 && beam_color.g > 0.98 && beam_color.b > 0.98) {
		col = COLOR.rgb;
		a = COLOR.a * alpha;
	}
	ALBEDO = col;
	ALPHA = a;
}
