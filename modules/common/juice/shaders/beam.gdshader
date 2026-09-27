// Weapon beam shader: a soft-edged glowing tube with energy flowing along its
// length, instead of a flat-tinted additive quad.
//
// The mesh (SystemsSim._make_beam_mesh) is a crossed pair of quads — two
// planes through the beam's axis, UV.x 0..1 across each plane's width and
// UV.y 0..1 along its length. That crossed-quad trick is what makes a beam
// look round from any angle without real cylinder geometry; this shader adds
// the two things a flat tint cannot: a soft radial falloff so the beam reads
// as a glowing tube rather than a lit card, and a noise pattern scrolling
// along UV.y so energy visibly travels from muzzle to target.
//
// Additive and unshaded like the StandardMaterial3D it replaces (see
// SystemsSim._spawn_shot's is_beam branch) — brightness lives in ALBEDO, not
// EMISSION: this project's bloom reads the unshaded albedo (see
// star_surface.gdshader's header for where that was confirmed the hard way).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flow_speed : hint_range(0.0, 12.0) = 4.0;
uniform float flow_scale : hint_range(0.5, 8.0) = 2.5;
// 0 for an ordinary bolt-sized beam; raised for a weapon's "mega beam" tier
// (hyper_beam, planet_buster_beam) — widens the bright core and adds a second,
// slower counter-scrolling noise layer so a huge beam reads as more than a
// scaled-up small one.
uniform float mega_boost : hint_range(0.0, 1.0) = 0.0;
// Overall opacity, driven every frame from GDScript for the beam's
// life-based fade — see SystemsSim._advance_shots' beam branch.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

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

void fragment() {
	// 0 at the plane's centreline, 1 at its silhouette edge — the crossed-quad
	// equivalent of "distance from the beam's axis" a real cylinder would give
	// for free.
	float radial = abs(UV.x - 0.5) * 2.0;

	// Energy scrolling from muzzle (UV.y 0) to target (UV.y 1). A second,
	// slower, counter-scrolling layer only kicks in for a mega beam, so a
	// huge weapon's surface churns instead of just showing one faster streak.
	float flow = value_noise(vec2(UV.x * flow_scale, UV.y * 5.0 - TIME * flow_speed));
	if (mega_boost > 0.0) {
		float flow2 = value_noise(vec2(UV.x * flow_scale * 1.7 + 3.1, UV.y * 3.0 + TIME * flow_speed * 0.4));
		flow = mix(flow, max(flow, flow2), mega_boost);
	}

	// Soft glowing-tube falloff: bright through the middle, fading toward the
	// silhouette edge, with the energy flow riding on top as brightness
	// variation rather than a separate visible layer.
	float core_width = mix(0.35, 0.6, mega_boost);
	float tube = 1.0 - smoothstep(0.0, 1.0, radial);
	float core = 1.0 - smoothstep(0.0, core_width, radial);
	core = max(core, (flow - 0.5) * 0.4 * tube);

	vec3 albedo = mix(beam_color.rgb, core_color.rgb, clamp(core, 0.0, 1.0));
	float glow = tube * (0.65 + flow * 0.5);

	ALBEDO = albedo * glow * (1.0 + mega_boost * 0.8);
	ALPHA = clamp(glow, 0.0, 1.0) * opacity;
}
