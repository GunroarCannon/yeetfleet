// Glowing chevron arrow for the swipe / slingshot profiles (ChevronArrow3D).
// A flat ribbon: UV.x runs across it, UV.y from the tail (0) to the tip (1).
// The shaft is a stream of scrolling chevrons in a halftone-dot glow, the tip a
// solid arrowhead with a bright rim. Everything is drawn in code — no texture.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.55, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);
// Arrow length over its width (keeps the chevrons in shape at any length).
uniform float length_ratio = 6.0;
// Chevron spacing, in widths.
uniform float spacing = 0.75;
// Chevrons per second toward the tip.
uniform float speed = 2.0;
// Arrowhead length, in widths.
uniform float head = 1.1;
uniform float intensity = 1.0;

void fragment() {
	float u = (UV.x - 0.5) * 2.0;
	float au = abs(u);
	float v = UV.y * length_ratio;
	float shaft_end = max(length_ratio - head, 0.0);

	// Chevrons: stripes of constant (v + |u|·k), so the middle leads the edges.
	float f = fract((v + au * 0.55) / spacing - TIME * speed);
	float band = smoothstep(0.0, 0.07, f) * (1.0 - smoothstep(0.3, 0.42, f));
	float shaft = (1.0 - step(shaft_end, v)) * (1.0 - smoothstep(0.55, 0.72, au));
	float tail = smoothstep(0.0, max(shaft_end * 0.45, 0.01), v);
	float chev = band * shaft * tail;

	// The arrowhead: a filled triangle, brighter at its rim.
	float hv = clamp((v - shaft_end) / max(head, 0.01), 0.0, 1.0);
	float edge_d = (1.0 - hv) - au;
	float in_head = step(shaft_end, v) * smoothstep(-0.04, 0.04, edge_d);
	float rim = in_head * (1.0 - smoothstep(0.0, 0.2, edge_d));

	// Halftone dots under the glow, like a screen print.
	vec2 cell = fract(vec2(u * 5.0, v * 5.0)) - 0.5;
	float dots = 1.0 - smoothstep(0.22, 0.42, length(cell));
	float glow = (shaft * tail * 0.12 + in_head * 0.35) * dots;

	float a = chev + rim + glow;
	float hot = clamp(chev + rim, 0.0, 1.0) * (1.0 - au * 0.6);
	ALBEDO = mix(color.rgb, core_color.rgb, hot);
	ALPHA = clamp(a * intensity, 0.0, 1.0);
}
