// Procedural planet ring shader.
//
// A flat annulus disc with concentric density bands, a configurable gap,
// and a dust-density falloff. The ring is alpha-masked so thin rings are
// translucent and the gap is fully transparent.
//
// Mesh: a flat ring (inner/outer radius), UV.x = radial position 0..1,
// UV.y = angular position. Animated very subtly via TIME for dust drift.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 ring_color_a : source_color = vec4(0.75, 0.70, 0.62, 1.0);
uniform vec4 ring_color_b : source_color = vec4(0.55, 0.48, 0.38, 1.0);
uniform float dust_density : hint_range(0.0, 2.0) = 1.0;
uniform float ring_opacity : hint_range(0.0, 1.0) = 0.75;
uniform float gap_position : hint_range(0.1, 0.9) = 0.45;
uniform float gap_width : hint_range(0.01, 0.2) = 0.06;
uniform float band_frequency : hint_range(5.0, 40.0) = 18.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float radial = UV.x;
	float angle = UV.y;

	// Concentric density bands — the visible ring structure.
	float bands = sin(radial * band_frequency * TAU) * 0.5 + 0.5;
	// Finer secondary bands for variation.
	float fine = sin(radial * band_frequency * 3.7 * TAU + 1.3) * 0.5 + 0.5;
	float density = mix(bands, fine, 0.3) * dust_density;

	// Cassini-like division: a gap in the ring.
	float gap_dist = abs(radial - gap_position);
	float gap = smoothstep(0.0, gap_width * 0.5, gap_dist);
	density *= gap;

	// Inner and outer edge fade.
	float inner_edge = smoothstep(0.0, 0.04, radial);
	float outer_edge = smoothstep(1.0, 0.94, radial);
	density *= inner_edge * outer_edge;

	// Subtle angular variation — clumps and streaks.
	float clump = hash21(vec2(floor(angle * 60.0), floor(radial * 40.0)));
	density *= 0.7 + clump * 0.3;

	// Very slow radial drift to keep the ring from looking frozen.
	float drift = TIME * 0.005;
	float drift_noise = hash21(vec2(radial * 8.0 + drift, angle * 3.0));
	density *= 0.92 + drift_noise * 0.08;

	// Color varies radially: inner rings tend warmer, outer cooler.
	vec3 color = mix(ring_color_b.rgb, ring_color_a.rgb, radial);

	float alpha = clamp(density * ring_opacity, 0.0, 1.0);

	ALBEDO = color;
	ALPHA = alpha;
}
