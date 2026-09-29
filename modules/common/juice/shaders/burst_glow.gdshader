// Glowing burst particles (sparks, embers, ring sparks): additive, a hot
// near-white core fading through the particle's colour to a soft edge.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://modules/common/juice/shaders/burst_particle.gdshaderinc"

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float glow = 1.0 - smoothstep(0.15, 1.0, r);
	glow *= glow;
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	vec3 col = mix(COLOR.rgb, vec3(1.0, 0.97, 0.9), core * 0.8);
	float a = COLOR.a * glow;
	ALBEDO = col * a;
	ALPHA = a;
}
