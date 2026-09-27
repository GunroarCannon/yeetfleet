// Toon planet surface — the third "planet look" (see Planet.SURFACE_STYLES and
// the flight test's Planet look picker). The same PlanetData palette contract
// and the same albedo as planet_surface.gdshader (sea, shore, land, snow; gas
// giant bands), so the three looks compare on one planet, but lit like a cel
// cartoon: the day side stepped into a few soft bands, a tinted shadow side
// rather than black, a bright rim hugging the lit limb, and a halftone dot
// screen printed into the shade.
//
// The lighting is adapted from addons/UltimateToonSource's stylized.gdshader
// (its stepped light, shadow tint, fresnel rim and screen pattern), rewritten
// here to be self-contained: no texture, no dependency on the addon, so the
// addon can be deleted and this still works — and deleting this file and its
// entry in Planet.SURFACE_STYLES removes the look cleanly.
shader_type spatial;
render_mode unshaded, cull_disabled;

// Vector Arcade wireframe mode
uniform float wireframe_mode : hint_range(0.0, 1.0) = 0.0;

uniform vec4 primary_color : source_color = vec4(0.3, 0.5, 0.8, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.7, 0.4, 0.2, 1.0);
// Sea, and only sea. Two colours could not cover water, lowland and peak at
// once: with the ocean tinted from secondary_color like the lowlands, every
// rocky planet came out one flat hue whatever the pickers said.
uniform vec4 water_color : source_color = vec4(0.09, 0.22, 0.38, 1.0);
uniform float planet_type : hint_range(0.0, 1.0) = 0.0; // 0 = gas giant, 1 = rocky
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.15;
uniform float swirl_scale : hint_range(0.0, 10.0) = 3.0;
uniform float band_count : hint_range(2.0, 20.0) = 8.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.12;
uniform float rotation_speed : hint_range(0.0, 1.0) = 0.02;
// Where the waterline sits in the baked 0..1 elevation range.
uniform float sea_level : hint_range(0.0, 1.0) = 0.48;
// How much of the planet is frozen. 0 leaves it ice-free; 1 pushes the caps out
// toward the tropics and the snow line down toward the shoreline.
uniform float ice_amount : hint_range(0.0, 1.0) = 0.5;
// 0 leaves a rocky planet flat-shaded from elevation alone; 1 lets the displaced
// surface normals shade the relief, which is what makes mountains read as raised.
uniform float relief : hint_range(0.0, 1.0) = 1.0;
// World-space direction light arrives from. Set by [Planet] to match the scene.
uniform vec3 sun_direction = vec3(0.42, 0.28, 0.86);
// Optional offset for planetary crust debris fragments, mapping chunk vertices
// back to their exact geographic location on the parent planet.
uniform vec3 sphere_center_offset = vec3(0.0);

// --- Toon lighting ---
// How many lit bands the day side is stepped into, and how soft their edges.
uniform float toon_steps : hint_range(1.0, 6.0) = 3.0;
uniform float toon_step_softness : hint_range(0.0, 0.5) = 0.18;
// The night side's colour: a tint of the albedo, not black.
uniform vec4 toon_shadow_tint : source_color = vec4(0.22, 0.16, 0.42, 1.0);
uniform float toon_shadow_floor : hint_range(0.0, 1.0) = 0.28;
// Rim light round the lit limb (the cartoon "back light").
uniform vec4 toon_rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float toon_rim_amount : hint_range(0.5, 8.0) = 3.0;
uniform float toon_rim_strength : hint_range(0.0, 1.5) = 0.55;
// Halftone dots printed into the shade; 0 turns them off.
uniform float toon_halftone : hint_range(0.0, 1.0) = 0.35;
uniform float toon_halftone_scale : hint_range(40.0, 400.0) = 140.0;


// Model-space position, for latitude and longitude: the built-in VERTEX is in
// view space by the time fragment() runs, which is the wrong frame for it.
varying vec3 v_local;
// World-space normal of the *undisplaced* sphere, so relief can be dialled back
// to plain spherical shading without rebuilding the mesh.
varying vec3 v_world_smooth;

const vec3 ICE = vec3(0.90, 0.94, 0.98);

// --- Hash functions (cheap, mobile-safe, no texture lookups) ---

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

// Fractal noise — three octaves for detail without GPU cost.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX + sphere_center_offset;
	// Displacement runs along the outward direction, so normalising the model-space
	// position recovers the sphere normal whatever the terrain did to it.
	v_world_smooth = normalize((MODEL_MATRIX * vec4(normalize(v_local), 0.0)).xyz);
}

void fragment() {
	// Latitude and longitude from the direction out of the planet's centre.
	// Seam-free on a cube-sphere, and unaffected by how far the vertex was
	// displaced.
	vec3 dir = normalize(v_local);
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / PI;      // 0 = north pole, 1 = south
	float lon = atan(dir.z, dir.x) / TAU + 0.5;          // 0..1 around the equator

	// Rotate the planet around its axis.
	lon = fract(lon + TIME * rotation_speed);

	// Elevation the generator actually displaced this vertex to, 0..1 with 0.5 as
	// the undisplaced radius. Flat 0.5 everywhere on a smooth planet.
	float elevation = COLOR.r;

	vec3 albedo;
	// How much of the displaced normal to shade with, and how glossy the surface
	// is. Both depend on what the fragment turned out to be — rock, water or ice
	// — so the rocky branch sets them and the gas giant leaves them alone.
	float relief_mask = 1.0;
	float gloss = 0.15;

	if (planet_type < 0.5) {
		// --- GAS GIANT: horizontal bands with animated swirl ---
		float band = sin((lat - 0.5) * band_count * PI) * 0.5 + 0.5;

		// Animated swirl distortion sampled from noise.
		float swirl_time = TIME * swirl_speed;
		float n1 = value_noise(vec2(lon * swirl_scale, lat * swirl_scale * 0.7) + swirl_time);

		// Swirl offsets the band position, creating the characteristic
		// turbulent bands of Jupiter/Saturn.
		float swirl_offset = (n1 - 0.5) * detail_strength * 2.0;
		band = clamp(band + swirl_offset, 0.0, 1.0);

		// A second noise layer for smaller storm-like features.
		float storm = fbm(vec2(lon * swirl_scale * 2.5, lat * swirl_scale * 2.0) + swirl_time * 0.3);
		band = mix(band, storm, detail_strength * 0.4);

		albedo = mix(secondary_color.rgb, primary_color.rgb, band);

		// Colour variation within a band: the storm noise shifts the hue between
		// the two pickers, so a gas giant has turbulent regions of different
		// tint rather than one static striped colour.
		float tint = (storm - 0.5) * detail_strength;
		albedo += (primary_color.rgb - secondary_color.rgb) * tint * 0.5;
	} else {
		// --- ROCKY: coloured by the elevation the mesh was built at ---
		// A narrow ramp across the waterline, rather than a step, so a 48-vertex
		// planet does not show a staircase coastline.
		float land = smoothstep(sea_level - 0.005, sea_level + 0.012, elevation);
		// Height within the *land* range: 0 at the waterline, 1 at the highest the
		// noise can reach. Normalised so flooding the planet with sea_level does
		// not drag the snow line and the peak colour along with it.
		float land_t = clamp((elevation - sea_level) / max(1.0 - sea_level, 0.001), 0.0, 1.0);
		// Depth below the waterline, on the same normalised footing.
		float depth_t = clamp((sea_level - elevation) / max(sea_level, 0.001), 0.0, 1.0);

		// Bright shelves and a dark abyss: that gradient is most of what makes an
		// ocean read as an ocean rather than as a blue disc.
		vec3 sea = water_color.rgb * mix(1.3, 0.4, sqrt(depth_t));
		// Secondary is the lowland colour, primary the high one — the same
		// contract the gas giant path uses, so the two pickers mean one thing.
		vec3 ground = mix(secondary_color.rgb, primary_color.rgb, smoothstep(0.0, 0.55, land_t));
		albedo = mix(sea, ground, land);

		// Fine surface break-up, on land only: noise on water reads as dirt.
		float grain = fbm(vec2(lon, lat) * 26.0);
		albedo *= 1.0 + (grain - 0.5) * detail_strength * land;
		// Coloured grain, not just brightness: the noise shifts the hue between
		// the ground colours, so rock reads as stone with variation rather than
		// as one flat shade wearing speckles.
		float tint = (grain - 0.5) * detail_strength;
		albedo = mix(albedo, mix(secondary_color.rgb, primary_color.rgb, 0.5), tint * 0.6 * land);
		// A slow latitude band so a world is not one single hue around its
		// whole waist — the eye needs the horizon to break tone to read round.
		float lat_tint = value_noise(vec2(lat * 4.0, 0.5));
		albedo = mix(albedo, primary_color.rgb, (lat_tint - 0.5) * detail_strength * 0.4 * land);

		// Ice caps. Latitude only, and narrow — this is a cap, not a hemisphere.
		// The old 0.16..0.06 ramp reached 29 degrees from the pole and painted a
		// fifth of the planet white.
		float from_pole = min(lat, 1.0 - lat);
		float cap_edge = mix(0.03, 0.15, ice_amount);
		float polar = smoothstep(cap_edge, cap_edge * 0.25, from_pole);

		// Snow, and only on peaks. The snow line drops toward the poles, so an
		// equatorial mountain has to be far taller to hold snow than one at 60
		// degrees — which is what stops snow reading as a coat of white paint.
		float latitude_cold = smoothstep(0.45, 0.08, from_pole);
		float snow_line = mix(mix(0.95, 0.62, ice_amount), mix(0.55, 0.20, ice_amount), latitude_cold);
		float snow = smoothstep(snow_line, snow_line + 0.12, land_t) * land;

		albedo = mix(albedo, ICE, max(polar, snow) * 0.92);

		// Water is a sphere by construction — the generator clamps displacement at
		// the waterline — so shading it with the shore's displaced normals was pure
		// mud. It is also the only glossy thing on the planet, ice aside.
		relief_mask = land;
		gloss = mix(0.26, 0.06, land);
		gloss = mix(gloss, 0.18, max(polar, snow));
	}

	// --- Toon lighting, in world space ---
	// Same normals as the painted look (see planet_surface.gdshader), then the
	// light is quantised instead of used raw.
	vec3 n_geom = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n = normalize(mix(v_world_smooth, n_geom, relief * relief_mask));
	vec3 l = normalize(sun_direction);
	float ndotl = clamp(dot(n, l), 0.0, 1.0);

	// Stepped bands with soft edges: floor into a step, smooth the fraction.
	float lm = ndotl * toon_steps;
	float base_step = floor(lm);
	float frac_step = smoothstep(0.5 - toon_step_softness, 0.5 + toon_step_softness, lm - base_step);
	float light = clamp((base_step + frac_step) / toon_steps, 0.0, 1.0);

	// Halftone in the shade: a screen-space dot grid whose dots grow as the
	// light falls, like print on a comic page.
	if (toon_halftone > 0.0) {
		vec2 grid = FRAGCOORD.xy / VIEWPORT_SIZE.y * toon_halftone_scale;
		grid = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * grid;
		float d = length(fract(grid) - 0.5);
		float dot_r = (1.0 - light) * 0.6;
		float dots = 1.0 - smoothstep(dot_r - 0.08, dot_r + 0.08, d);
		light = mix(light, light * (1.0 - dots * 0.6), toon_halftone);
	}

	vec3 shade = mix(albedo * toon_shadow_tint.rgb * 1.6, albedo, toon_shadow_floor);
	vec3 lit = mix(shade, albedo * 1.08, light);

	// Rim on the lit limb only, so the night side keeps its silhouette dark.
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(-normalize(VERTEX), 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(v_world_smooth, view_dir), 0.0, 1.0), toon_rim_amount);
	float rim = smoothstep(0.35, 0.6, fres) * smoothstep(-0.1, 0.35, dot(v_world_smooth, l));
	lit += toon_rim_color.rgb * rim * toon_rim_strength;

	// A crisp specular star on water and ice, stepped like the light.
	vec3 h = normalize(l + view_dir);
	float spec = step(0.985, dot(n, h)) * gloss * 3.0 * step(0.001, ndotl);

	ALBEDO = lit + vec3(spec);

	if (wireframe_mode > 0.5) {
		// Neon latitude and longitude vector grid rings for planets (Geometry Wars / Vector Arcade)
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
	}
}
