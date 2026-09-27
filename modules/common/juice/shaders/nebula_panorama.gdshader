// The flight sky's backdrop, drawn once into an equirectangular panorama by
// NebulaSky and then used as the environment's sky — so all of this noise is
// paid for a single time at load, not every frame.
//
// Each pixel of the panorama is a direction on the sky. Three layers:
//   * gas — domain-warped fractal noise (noise fed through noise, so the
//     clouds curl and filament instead of blobbing), coloured from the
//     palette's nebula pair with a third accent for glowing knots;
//   * a galactic band — a soft ribbon of light across the sky, broken up by
//     dark dust lanes, with a brighter core toward the galaxy;
//   * stars — thousands of pin-points from a 3D cell hash, denser in the band,
//     a few bright ones with a small halo.
// 3D noise on the direction, never on the UV, so there is no seam at the
// wrap-around and no pinching at the poles.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform vec3 bg_color : source_color = vec3(0.03, 0.02, 0.07);
uniform vec3 neb_a : source_color = vec3(0.45, 0.18, 0.62);
uniform vec3 neb_b : source_color = vec3(0.12, 0.35, 0.70);
uniform vec3 neb_c : source_color = vec3(1.00, 0.36, 0.62);
uniform vec3 star_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float seed = 0.0;
// Overall strength of the gas (0 = stars and band only).
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0;
uniform float band_amount : hint_range(0.0, 2.0) = 1.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
// The galactic plane's normal, and the direction of the galaxy's bright core.
uniform vec3 band_normal = vec3(0.28, 0.92, 0.27);
uniform vec3 core_dir = vec3(-0.72, 0.45, -0.52);
// Panorama width / 4096, set by NebulaSky.
uniform float res_scale = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// One layer of stars: a star in some of the cells of a grid laid over the
// sky at [scale], jittered inside its cell, with [chance] of a cell holding one.
vec3 star_layer(vec3 d, float scale, float chance, float size, float glow) {
	vec3 c = d * scale;
	vec3 id = floor(c);
	vec3 f = fract(c) - 0.5;
	float h = hash13(id + seed);
	if (h > chance) {
		return vec3(0.0);
	}
	vec3 off = (vec3(hash13(id + 1.7), hash13(id + 4.1), hash13(id + 7.3)) - 0.5) * 0.5;
	float r = length(f - off);
	float b = hash13(id + 9.9);
	float core_px = smoothstep(size, 0.0, r);
	float halo = glow * exp(-r * r * 40.0) * b;
	// A touch of colour: most stars white, some warm, some cold.
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), hash13(id + 3.3));
	return tint * star_color * (core_px * (0.35 + b * 1.1) + halo);
}

void fragment() {
	float lon = (UV.x - 0.5) * TAU;
	float lat = (0.5 - UV.y) * PI;
	vec3 d = vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));

	vec3 p = d * 2.1 + vec3(seed * 0.37, seed * 0.11, -seed * 0.23);
	// Domain warp: the clouds' own noise bends where they are sampled.
	vec3 q = vec3(fbm(p), fbm(p + vec3(5.2, 1.3, 2.8)), fbm(p + vec3(1.7, 9.2, 4.1)));
	float n = fbm(p + 2.6 * q);
	float n2 = fbm(p * 2.2 + 4.0 * q + 3.3);

	vec3 col = bg_color;

	// Gas.
	float dens = smoothstep(0.38, 0.92, n);
	vec3 gas = mix(neb_a, neb_b, smoothstep(0.35, 0.75, n2));
	gas = mix(gas, neb_c, smoothstep(0.58, 0.88, q.x) * 0.6);
	col += gas * pow(dens, 1.7) * 0.85 * cloud_amount;
	// Glowing knots where the gas is thickest.
	float knots = pow(smoothstep(0.55, 0.85, n2 * (0.4 + dens)), 3.0);
	col += neb_c * knots * 0.9 * cloud_amount;

	// Galactic band, brighter toward the core, cut by dust lanes.
	float bd = dot(d, normalize(band_normal));
	float band = exp(-bd * bd / 0.03);
	float toward_core = pow(max(dot(d, normalize(core_dir)), 0.0), 3.0);
	float mw = band * (0.3 + 0.7 * fbm(p * 3.1 + q * 2.0)) * (0.55 + toward_core * 1.3);
	float dust = smoothstep(0.42, 0.72, fbm(p * 4.3 + vec3(7.0))) * band;
	vec3 band_col = mix(mix(neb_b, star_color, 0.55), vec3(1.0, 0.85, 0.65), toward_core);
	col += band_col * mw * 0.5 * band_amount * (1.0 - dust * 0.9);
	col *= 1.0 - dust * 0.35;

	// Stars: a dense faint layer, a sparser mid layer, a few bright ones.
	float in_band = 0.35 + band * 0.9;
	// Cell sizes follow the panorama's resolution so a star covers a pixel or
	// two of it instead of aliasing into grain.
	vec3 stars = star_layer(d, 240.0 * res_scale, 0.16 * in_band, 0.34, 0.0) * 0.5;
	stars += star_layer(d, 130.0 * res_scale, 0.09 * in_band, 0.28, 0.0);
	stars += star_layer(d, 48.0 * res_scale, 0.06, 0.14, 0.4) * 1.4;
	col += stars * star_amount * (1.0 - dust * 0.7);

	COLOR = vec4(col, 1.0);
}
