// Procedural cloud layer for planets: a translucent shell just above the
// terrain that carries animated, sun-lit noise.
//
// Why it looks like weather rather than a painted band:
//  - Coordinates come from the model-space position (lat/lon), the same
//    seam-free frame the surface shader uses — a cube-sphere's UVs restart at
//    every face and would draw six clouds' worth of seams.
//  - Coverage is fractal noise run through a soft threshold, so there is real
//    structure: broken cumulus puffs, not a uniform wash.
//  - Clouds are lit by the same sun as the terrain, so the day side is bright
//    and the terminator dims them — which is what makes them read as sitting
//    above the surface instead of being part of it.
//  - The shell rotates with the planet, and TIME adds a slow independent drift.
//
// Still unshaded and texture-free, for GL Compatibility.
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque, shadows_disabled;

uniform vec4 cloud_color : source_color = vec4(0.95, 0.96, 1.0, 1.0);
// Coverage: 0 = clear, 1 = overcast. Multiplied into the noise threshold.
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 sun_direction = vec3(0.42, 0.28, 0.86);
// Spatial frequency of the cloud noise — lower is bigger, rounder puffs.
uniform float cloud_scale : hint_range(1.0, 20.0) = 6.0;
// How fast the clouds drift on their own, independent of the planet's spin.
uniform float drift_speed : hint_range(0.0, 0.5) = 0.04;
// Edge softness of a cloud: low is crisp cumulus, high is a hazy overcast.
uniform float softness : hint_range(0.05, 0.6) = 0.25;

varying vec3 v_local;
varying vec3 v_world_normal;

// --- Hash / noise (mirrors the surface shader, mobile-safe) ---

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Two octaves: enough structure for puff boundaries without GPU cost.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.6;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 2; i++) {
		v += a * value_noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Seam-free lat/lon, like the surface shader.
	vec3 dir = normalize(v_local);
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	float lon = atan(dir.z, dir.x) / TAU + 0.5;
	float from_pole = min(lat, 1.0 - lat);

	// Slow independent drift on top of the planet's own spin.
	lon = fract(lon + TIME * drift_speed);

	// Coverage from noise through a soft threshold — puffs, not a wash.
	float n = fbm(vec2(lon, lat) * cloud_scale);
	float cover = smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, n);
	cover *= cloud_density;
	// Less cloud right at the poles, so the shell is not a solid cap.
	cover *= smoothstep(0.0, 0.12, from_pole);

	// Sun lighting: bright day side, dim night, so clouds catch the light the
	// way the terrain below does.
	vec3 n_world = normalize(v_world_normal);
	float ndotl = max(dot(n_world, normalize(sun_direction)), 0.0);
	float light = mix(0.25, 1.0, ndotl);

	float alpha = clamp(cover * light, 0.0, 1.0);
	ALBEDO = cloud_color.rgb * (0.6 + 0.4 * light);
	ALPHA = alpha;
}
