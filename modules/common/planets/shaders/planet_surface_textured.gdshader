// Alternative planet surface shader — same [PlanetData] palette contract as
// planet_surface.gdshader (primary/secondary/water color, sea_level,
// ice_amount) so the two are directly comparable on the same planet, but a
// different technique: standard lit rendering (diffuse_lambert +
// specular_schlick_ggx, like asteroid_detail.gdshader's triplanar rock
// technique) with real per-pixel normal perturbation instead of one manual
// unshaded sun term. The bump gives the surface actual depth under Godot's
// own lighting, rather than reading as a flat painted sphere — see
// Planet.swap_all_surface_shaders, which is what the "AltSurface" debug
// toggle and the flight-test planet-look picker flip between this and the
// original. A pure add-alongside: removing this file and the toggle removes
// the option cleanly, since nothing else depends on it.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 primary_color : source_color = vec4(0.3, 0.5, 0.8, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.7, 0.4, 0.2, 1.0);
uniform vec4 water_color : source_color = vec4(0.09, 0.22, 0.38, 1.0);
uniform float planet_type : hint_range(0.0, 1.0) = 0.0; // 0 = gas giant, 1 = rocky
uniform float sea_level : hint_range(0.0, 1.0) = 0.48;
uniform float ice_amount : hint_range(0.0, 1.0) = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.12;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.8;
uniform float bump_scale : hint_range(0.05, 5.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
// Kept for API parity with planet_surface.gdshader's uniform set — Planet's
// _write_surface_params sets these on whichever surface shader is active,
// so swapping shaders never needs a special case there. Unused here: this
// shader's "band"/"swirl" look comes from bump detail, not banding, and it
// lights through Godot's own pipeline rather than a manual sun uniform.
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.15;
uniform float swirl_scale : hint_range(0.0, 10.0) = 3.0;
uniform float band_count : hint_range(2.0, 20.0) = 8.0;
uniform float rotation_speed : hint_range(0.0, 1.0) = 0.02;
uniform float relief : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_direction = vec3(0.42, 0.28, 0.86);
uniform vec3 sphere_center_offset = vec3(0.0);
uniform float wireframe_mode : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_world_pos;

const vec3 ICE = vec3(0.90, 0.94, 0.98);

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
				if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void vertex() {
	v_local = VERTEX + sphere_center_offset;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(v_local);
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	float lon = atan(dir.z, dir.x) / TAU + 0.5;
	float elevation = COLOR.r;

	vec3 albedo;
	float rough = roughness;

	if (planet_type < 0.5) {
		// Gas giant: coarse voronoi cells standing in for turbulent bands —
		// a different texture family from the sine bands in
		// planet_surface.gdshader, still animated and still two-tone.
		vec2 cell = voronoi(vec3(lon * band_count, lat * band_count * 0.6, TIME * swirl_speed * 0.05) * swirl_scale * 0.5);
		float band = smoothstep(0.0, 0.9, cell.y - cell.x);
		albedo = mix(secondary_color.rgb, primary_color.rgb, band);
		rough = 0.35;
	} else {
		float land = smoothstep(sea_level - 0.005, sea_level + 0.012, elevation);
		float land_t = clamp((elevation - sea_level) / max(1.0 - sea_level, 0.001), 0.0, 1.0);
		float depth_t = clamp((sea_level - elevation) / max(sea_level, 0.001), 0.0, 1.0);

		vec3 sea = water_color.rgb * mix(1.3, 0.4, sqrt(depth_t));
		vec3 ground = mix(secondary_color.rgb, primary_color.rgb, smoothstep(0.0, 0.55, land_t));
		albedo = mix(sea, ground, land);

		float from_pole = min(lat, 1.0 - lat);
		float cap_edge = mix(0.03, 0.15, ice_amount);
		float polar = smoothstep(cap_edge, cap_edge * 0.25, from_pole);
		float latitude_cold = smoothstep(0.45, 0.08, from_pole);
		float snow_line = mix(mix(0.95, 0.62, ice_amount), mix(0.55, 0.20, ice_amount), latitude_cold);
		float snow = smoothstep(snow_line, snow_line + 0.12, land_t) * land;
		albedo = mix(albedo, ICE, max(polar, snow) * 0.92);

		rough = mix(0.9, 0.2, land * (1.0 - max(polar, snow)));

		// Real per-pixel bump via triplanar-style voronoi, gated to land —
		// water stays a smooth sphere by construction (see
		// planet_surface.gdshader's own note on this).
		vec2 v = voronoi(v_world_pos * bump_scale);
		float facet = (v.y - v.x) - 0.5;
		vec3 n_mod = vec3(
			sin(v_world_pos.y * bump_scale * 4.0) * 0.5,
			cos(v_world_pos.z * bump_scale * 4.0) * 0.5,
			sin(v_world_pos.x * bump_scale * 4.0) * 0.5
		) * facet;
		NORMAL = normalize(NORMAL + n_mod * bump_strength * relief * land * detail_strength * 3.0);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.2;

	if (wireframe_mode > 0.5) {
		float lat_dist = abs(fract(lat * 18.0) - 0.5);
		float lat_ring = 1.0 - smoothstep(0.0, fwidth(lat * 18.0) * 1.8 + 0.035, lat_dist);
		float lon_dist = abs(fract(lon * 24.0) - 0.5);
		float lon_ring = 1.0 - smoothstep(0.0, fwidth(lon * 24.0) * 1.8 + 0.035, lon_dist);
		float rings = max(lat_ring, lon_ring);
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float limb = pow(1.0 - facing, 2.5);
		float edge = max(rings * 1.4, limb * 1.1);
		if (edge < 0.18) {
			discard;
		}
		vec3 neon_planet = mix(primary_color.rgb, secondary_color.rgb, lat);
		float max_c = max(neon_planet.r, max(neon_planet.g, neon_planet.b));
		if (max_c > 0.01) {
			neon_planet = neon_planet / max_c;
		}
		ALBEDO = neon_planet * (edge * 1.6);
		EMISSION = neon_planet * (edge * 1.6);
	}
}
