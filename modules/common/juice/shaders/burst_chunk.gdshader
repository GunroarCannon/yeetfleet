// Solid burst particles (debris, vapour): alpha-blended. Debris is a jagged
// shard — a triangle squashed and turned per particle — with a lit edge; a
// puff (softness 1) is a soft round cloud.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://modules/common/juice/shaders/burst_particle.gdshaderinc"

uniform float softness : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// Signed distance to an equilateral triangle of circumradius ~1 (iq).
float tri(vec2 p) {
	const float k = 1.7320508;
	p.x = abs(p.x) - 1.0;
	p.y = p.y + 1.0 / k;
	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}
	p.x -= clamp(p.x, -2.0, 0.0);
	return -length(p) * sign(p.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	if (softness > 0.5) {
		float a = 1.0 - smoothstep(0.1, 1.0, length(uv));
		ALBEDO = COLOR.rgb;
		ALPHA = COLOR.a * a * a;
	} else {
		// Per particle: its own turn and squash, so no two shards match.
		float ang = hash(particle_seed + 1.3) * 6.2831;
		mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
		vec2 p = rot * uv * vec2(1.0, 1.0 + hash(particle_seed + 7.1) * 0.8) * 1.15;
		float d = tri(p);
		float a = 1.0 - smoothstep(-0.04, 0.02, d);
		// Lit rim along the shard's edge.
		float rim = smoothstep(-0.25, -0.05, d);
		ALBEDO = COLOR.rgb + vec3(0.3) * rim;
		ALPHA = COLOR.a * a;
	}
}
