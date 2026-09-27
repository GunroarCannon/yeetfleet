// Procedural star surface shader: a turbulent, animated fireball with a
// bright fresnel corona at the limb.
//
// Reuses planet_surface.gdshader's noise toolkit (hash / value-noise / fbm)
// so the two celestial-body shaders read as the same visual language, and
// stays unshaded and texture-free for GL Compatibility the same way that
// shader does.
//
// A star has no lit/unlit side to shade — it IS the light — so unlike the
// planet shader there is no diffuse term: turbulent noise picks a colour
// between a hot core tone and a cooler "sunspot" tone, scrolling across the
// sphere in two overlapping directions so it churns instead of reading as one
// rigid rotating texture, and a fresnel term brightens the limb into a
// corona without a second mesh or a screen-space pass.
//
// Written to ALBEDO, not EMISSION, on purpose: this project's bloom reads
// off the final unshaded colour (see glow_material()'s own albedo_color and
// planet_surface.gdshader's ALBEDO-only output) rather than a separate
// emission buffer, and under the Compatibility renderer a bright EMISSION
// here measurably did not bloom at all where an equally bright ALBEDO does.
shader_type spatial;
render_mode unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.55, 1.0);
uniform vec4 spot_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 corona_color : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float turbulence_scale : hint_range(0.5, 12.0) = 4.0;
uniform float turbulence_speed : hint_range(0.0, 2.0) = 0.12;
// How much of the surface the darker sunspot tone can claim at its boldest —
// 0 leaves a smooth, evenly turbulent fireball with no dark patches at all.
uniform float spot_amount : hint_range(0.0, 1.0) = 0.45;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 4.0) = 2.2;
// Deliberately modest: the scene's bloom pass clips anything much past ~1.3
// to flat white on a screen-space blur wide enough to swallow a disc this
// small entirely, which is what erased the turbulence and the sunspots the
// first time this shipped. Kept low enough that the body of the disc renders
// its real, unclipped colour — texture visible — and only the fresnel-boosted
// rim below climbs into bloom range, which is what turns into the corona.
uniform float brightness : hint_range(0.2, 8.0) = 0.62;
// A slow overall brighten/dim so the star reads as alive rather than a
// static painted ball — small enough that it never looks like flicker.
uniform float pulse_speed : hint_range(0.0, 2.0) = 0.35;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.06;

varying vec3 v_local;

// --- Hash / noise (matches planet_surface.gdshader) -------------------------

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Latitude/longitude from the direction out of the star's centre — the
	// same seam-free trick planet_surface.gdshader uses, and for the same
	// reason: a sphere's own UVs pinch at the poles.
	vec3 dir = normalize(v_local);
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	float lon = atan(dir.z, dir.x) / TAU + 0.5;

	// Two turbulence layers, scrolling at different rates and opposite
	// directions, so the surface boils rather than just spinning as one
	// rigid texture.
	float t = TIME * turbulence_speed;
	vec2 uv = vec2(lon, lat) * turbulence_scale;
	float n1 = fbm(uv + vec2(t, -t * 0.6));
	float n2 = fbm(uv * 1.7 - vec2(-t * 0.5, t * 0.8) + 5.2);
	float turbulence = clamp(n1 * 0.65 + n2 * 0.55, 0.0, 1.0);

	// Sunspots carved from a threshold on the second noise layer rather than
	// an independent sample, so the veins and the spots read as one boiling
	// surface instead of two unrelated layers.
	float spots = smoothstep(0.55, 0.75, n2) * spot_amount;

	vec3 albedo = mix(core_color.rgb, spot_color.rgb, clamp(turbulence + spots, 0.0, 1.0));

	// Fresnel rim: the star's own corona, without a second mesh or a
	// screen-space pass — correct and cheap for a plain sphere seen from
	// outside, which a star always is.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(-normalize(VERTEX), 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), rim_power);
	albedo = mix(albedo, corona_color.rgb, fresnel * 0.85);

	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	ALBEDO = albedo * brightness * pulse * (1.0 + fresnel * rim_strength);
}
