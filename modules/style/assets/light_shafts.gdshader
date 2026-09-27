// Advanced lighting post pass: screen-space light shafts, colour grade, vignette.
//
// The GL Compatibility renderer has no volumetric fog, so god rays are done the
// classic way: every pixel marches toward the star's screen position through a
// copy of the frame, collecting how much bright sky it passes. A hull or a rock
// between the pixel and the star is dark in that copy, so it cuts a shadow into
// the shafts on its own -- the beams-through-bamboo look, with no geometry.
//
// Only near-star brightness counts (the mask falls off with distance from the
// star), so a pink nebula filling the frame does not throw rays of its own.
//
// Cost is `samples` screen reads per pixel. That is fine on desktop and the
// reason the whole pass is gated behind the advanced-lighting setting.
shader_type canvas_item;

// Plain linear, no mipmaps: the compat renderer does not always build a mip
// chain for the screen copy, and sampling a mip level that is not there reads
// black on some GL drivers -- the whole frame went dark in testing.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Star position in UV space. May sit outside 0..1 when the star is just off
// screen -- the shafts still fan in from that edge.
uniform vec2 sun_uv = vec2(0.5, 0.5);
// 0 when the star is behind the camera or far off screen, 1 when framed.
uniform float sun_visible : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shaft_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float shaft_strength : hint_range(0.0, 3.0) = 1.4;
uniform int samples : hint_range(8, 64) = 32;
// How far each march reaches toward the star, as a fraction of the distance.
uniform float density : hint_range(0.1, 1.0) = 0.85;
uniform float decay : hint_range(0.8, 1.0) = 0.955;
// Luminance a sampled pixel has to beat to count as "sky light".
uniform float threshold : hint_range(0.0, 1.0) = 0.55;
// Radius (in screen heights) around the star that can emit shafts at all.
uniform float source_radius : hint_range(0.05, 2.0) = 0.55;

// --- Grade ---
uniform float saturation : hint_range(0.0, 2.0) = 1.03;
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform vec4 shadow_tint : source_color = vec4(0.30, 0.22, 0.52, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.93, 0.80, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.22;
uniform float vignette : hint_range(0.0, 1.0) = 0.32;
// Soft glow wrapped around the star itself, so it reads as a light source
// rather than a white disc even where bloom is weak.
uniform float halo_strength : hint_range(0.0, 2.0) = 0.35;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Fail safe. On some GL drivers the screen copy this pass reads now and then
	// comes back empty for a frame (seen as a fully black screenshot, about one
	// run in a dozen, never with the pass off). The 3D frame underneath is fine,
	// so when five spread-out taps are all exactly black -- which no palette's
	// void is -- draw nothing and let that frame show ungraded.
	vec3 probe = textureLod(screen_tex, vec2(0.5), 0.0).rgb
		+ textureLod(screen_tex, vec2(0.2, 0.2), 0.0).rgb
		+ textureLod(screen_tex, vec2(0.8, 0.2), 0.0).rgb
		+ textureLod(screen_tex, vec2(0.2, 0.8), 0.0).rgb
		+ textureLod(screen_tex, vec2(0.8, 0.8), 0.0).rgb;
	bool empty_copy = dot(probe, vec3(1.0)) <= 0.0;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	// --- Shafts ---
	vec3 shafts = vec3(0.0);
	if (sun_visible > 0.001 && shaft_strength > 0.001) {
		vec2 to_sun = sun_uv - uv;
		vec2 step_uv = to_sun * density / float(samples);
		vec2 p = uv;
		float weight = 1.0;
		float acc = 0.0;
		for (int i = 0; i < 64; i++) {
			if (i >= samples) {
				break;
			}
			p += step_uv;
			vec3 s = textureLod(screen_tex, clamp(p, vec2(0.001), vec2(0.999)), 0.0).rgb;
			float bright = smoothstep(threshold, 1.0, luma(s));
			vec2 d = (p - sun_uv) * vec2(aspect, 1.0);
			float near_sun = 1.0 - smoothstep(0.0, source_radius, length(d));
			acc += bright * near_sun * weight;
			weight *= decay;
		}
		acc /= float(samples);
		shafts = shaft_color.rgb * acc * shaft_strength * sun_visible * 3.0;

		vec2 hd = (uv - sun_uv) * vec2(aspect, 1.0);
		float halo = exp(-length(hd) * 5.0) * halo_strength * sun_visible;
		shafts += shaft_color.rgb * halo;
	}
	// Belt and braces against a bad uniform: a NaN here would black out every
	// pixel on screen, so drop the shafts rather than the frame.
	if (any(isnan(shafts)) || any(isinf(shafts))) {
		shafts = vec3(0.0);
	}
	// Screen blend, so the beams brighten without clipping what is already lit.
	col = 1.0 - (1.0 - col) * (1.0 - clamp(shafts, 0.0, 1.0));

	// --- Grade ---
	float l = luma(col);
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	vec3 tint = mix(shadow_tint.rgb * 2.0, highlight_tint.rgb, smoothstep(0.0, 0.7, l));
	col = mix(col, col * tint, tint_amount);

	vec2 v = (uv - 0.5) * vec2(aspect, 1.0);
	col *= 1.0 - vignette * smoothstep(0.35, 1.15, length(v));

	// (No early return: Godot rejects `return` in fragment().)
	COLOR = empty_copy ? vec4(0.0) : vec4(clamp(col, 0.0, 1.0), 1.0);
}
