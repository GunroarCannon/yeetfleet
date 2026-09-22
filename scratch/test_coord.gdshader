shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform float grid_spacing = 0.038;
uniform float line_thickness = 0.0011;
uniform float time_speed = 0.45;
uniform float brightness = 1.25;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

vec2 warp_spacetime(vec2 p, float t) {
	// 1. Gentle undulating ribbons (horizontal wave displacement across vertical strings)
	float w1 = sin(p.y * 3.4 + t * 1.2) * 0.035;
	float w2 = sin(p.y * 6.8 - t * 0.6) * 0.015;
	float w3 = sin(p.y * 1.8 + p.x * 1.8 + t * 0.8) * 0.022;
	vec2 res = p + vec2(w1 + w2 + w3, cos(p.x * 2.8 + t * 0.7) * 0.012);

	// 2. Large localized vortex (bottom-left, matching Geometry Wars 3 reference)
	vec2 v1 = vec2(-0.55, -0.32);
	vec2 d1 = p - v1;
	float r1 = length(d1);
	float pull1 = smoothstep(0.75, 0.04, r1);
	// Smooth radial pull without singular pinching at center
	res += (d1 * 0.38 / (r1 * 2.5 + 0.18)) * pull1;

	// 3. Secondary subtle vortex (upper-right)
	vec2 v2 = vec2(0.65, 0.28);
	vec2 d2 = p - v2;
	float r2 = length(d2);
	float pull2 = smoothstep(0.60, 0.05, r2);
	res += (d2 * 0.26 / (r2 * 2.8 + 0.22)) * pull2;

	return res;
}

float eval_strings(vec2 wp) {
	// Dominant vertical undulating ribbons
	float g_x = fract(wp.x / grid_spacing);
	float d_x = abs(g_x - 0.5) * grid_spacing;
	float fw_x = fwidth(wp.x);
	float lx = 1.0 - smoothstep(0.0, fw_x * 1.7 + line_thickness, d_x);

	// Subtle horizontal grid lines (showing spacetime curvature)
	float g_y = fract(wp.y / (grid_spacing * 1.5));
	float d_y = abs(g_y - 0.5) * (grid_spacing * 1.5);
	float fw_y = fwidth(wp.y);
	float ly = 1.0 - smoothstep(0.0, fw_y * 1.7 + line_thickness * 0.75, d_y);

	return max(lx, ly * 0.14);
}

void fragment() {
	// Screen coordinate: p.y spans ~[-0.58, 0.58], p.x spans ~[-1.03, 1.03]
	vec2 p = VERTEX.xy / (-VERTEX.z);
	float t = TIME * time_speed;

	// CRT barrel curvature
	float r2 = dot(p, p);
	vec2 crt_p = p * (1.0 + r2 * 0.05);

	vec2 wp = warp_spacetime(crt_p, t);

	// Chromatic aberration RGB split (phosphor edge fringe)
	vec2 ca = vec2(0.0016, 0.0);
	float sr = eval_strings(wp + ca);
	float sg = eval_strings(wp);
	float sb = eval_strings(wp - ca);

	// Deep neon palette for background strings: electric violet, magenta, and cyan
	vec3 col_violet = vec3(0.35, 0.03, 0.82);
	vec3 col_magenta = vec3(0.92, 0.04, 0.65);
	vec3 col_cyan = vec3(0.0, 0.88, 1.0);
	vec3 col_red = vec3(1.0, 0.06, 0.16);
	vec3 col_orange = vec3(1.0, 0.44, 0.03);

	float phase = sin(wp.y * 2.5 + wp.x * 1.2 + t * 0.7) * 0.5 + 0.5;
	vec3 base_color = mix(col_violet, col_magenta, phase);
	float cross_phase = cos(wp.x * 2.2 - wp.y * 1.1 - t * 0.45) * 0.5 + 0.5;
	base_color = mix(base_color, col_cyan, cross_phase * 0.48);

	// Concentric vortex rings (Geometry Wars fiery red/pink loops in bottom-left)
	vec2 v1 = vec2(-0.55, -0.32);
	float dist1 = length(crt_p - v1);
	float ring1 = abs(fract(dist1 * 5.5 - t * 0.55) - 0.5);
	float ring_line1 = (1.0 - smoothstep(0.0, fwidth(dist1 * 5.5) * 1.8 + 0.028, ring1)) * smoothstep(0.80, 0.06, dist1);

	vec2 v2 = vec2(0.65, 0.28);
	float dist2 = length(crt_p - v2);
	float ring2 = abs(fract(dist2 * 5.2 + t * 0.45) - 0.5);
	float ring_line2 = (1.0 - smoothstep(0.0, fwidth(dist2 * 5.2) * 1.8 + 0.028, ring2)) * smoothstep(0.65, 0.06, dist2);

	vec3 ring_col1 = mix(col_red, col_orange, smoothstep(0.06, 0.60, dist1));
	vec3 ring_col2 = mix(col_magenta, col_cyan, smoothstep(0.06, 0.50, dist2));

	vec3 final_color = vec3(
		base_color.r * sr,
		base_color.g * sg,
		base_color.b * sb
	);
	final_color += ring_col1 * ring_line1 * 2.0;
	final_color += ring_col2 * ring_line2 * 1.5;

	// CRT border vignette & scanline
	vec2 edge = abs(p) / vec2(1.05, 0.60);
	float vign = 1.0 - smoothstep(0.85, 1.15, max(edge.x, edge.y));
	float scanline = sin(p.y * 460.0) * 0.035 + 0.965;

	ALBEDO = final_color * vign * scanline * brightness;
	ALPHA = clamp(max(max(sr, max(sg, sb)), max(ring_line1, ring_line2)) * vign * 0.95, 0.0, 1.0);
}
