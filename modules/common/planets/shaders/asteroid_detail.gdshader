// Triplanar procedural normal-mapped crater and rock shader for broken planet chunks and asteroids.
// Provides realistic micro-craters, faceted ridges, and basalt fractures up close without requiring texture assets.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 rock_color : source_color = vec4(0.24, 0.22, 0.20, 1.0);
uniform vec4 crater_color : source_color = vec4(0.12, 0.11, 0.10, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.88;
uniform float micro_scale : hint_range(0.05, 5.0) = 0.45;
uniform float crater_scale : hint_range(0.01, 1.0) = 0.08;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.75;

// Radiant mantle emission toggle
uniform bool emission_enabled = false;
uniform vec4 emission_color : source_color = vec4(1.0, 0.38, 0.06, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 2.5;

varying vec3 v_world_pos;
varying vec3 v_world_norm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 3D procedural Voronoi / cellular noise for crater ring extraction
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

vec2 voronoi(vec3 p) {
	vec3 n = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = vec3(float(i), float(j), float(k));
				vec3 o = hash33(n + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void fragment() {
	// Multi-frequency craggy rock texture
	vec2 v_crater = voronoi(v_world_pos * crater_scale);
	float crater_rim = smoothstep(0.35, 0.52, v_crater.x) * (1.0 - smoothstep(0.52, 0.80, v_crater.x));
	float crater_depth = smoothstep(0.6, 0.1, v_crater.x);

	// Micro-faceting high-frequency noise
	vec2 v_micro = voronoi(v_world_pos * micro_scale);
	float facet = v_micro.y - v_micro.x;

	// Perturb normals using triplanar-style 3D derivatives
	vec3 n_mod = vec3(
		(sin(v_world_pos.y * micro_scale * 3.5) + facet * 0.8) * 0.4,
		(cos(v_world_pos.z * micro_scale * 3.5) + crater_rim * 1.4) * 0.4,
		(sin(v_world_pos.x * micro_scale * 3.5) + facet * 0.8) * 0.4
	);
	NORMAL = normalize(NORMAL + n_mod * normal_strength);

	// Albedo blending with crater depressions and rims
	vec3 col = mix(rock_color.rgb, crater_color.rgb, crater_depth * 0.65);
	col = mix(col, col * 1.35, crater_rim * 0.55);
	col = mix(col, col * 0.82, facet * 0.3);

	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;

	if (emission_enabled) {
		float fissures = smoothstep(0.18, 0.04, facet);
		EMISSION = emission_color.rgb * (emission_energy * fissures);
	}
}
