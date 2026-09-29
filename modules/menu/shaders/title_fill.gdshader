// Vertical three-stop gradient for the graffiti title's letter fill, with a
// glossy highlight band and a little spray speckle. Drawn over glyphs, so the
// glyph's own coverage (COLOR.a) is kept and only the colour is replaced.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.98, 1.0, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(0.71, 1.0, 0.23, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.1, 0.78, 0.62, 1.0);
// The local y range the gradient spans (the text's top and baseline).
uniform float y_top = 0.0;
uniform float y_bottom = 100.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = clamp((local_pos.y - y_top) / max(y_bottom - y_top, 1.0), 0.0, 1.0);
	vec3 g = t < 0.5 ? mix(top_color.rgb, mid_color.rgb, t * 2.0)
		: mix(mid_color.rgb, bottom_color.rgb, (t - 0.5) * 2.0);
	// Gloss: a soft light band a quarter of the way down.
	g = mix(g, vec3(1.0), smoothstep(0.08, 0.0, abs(t - 0.22)) * 0.55);
	// Spray speckle: a few darker dots, fixed in place.
	float s = hash(floor(local_pos / 3.0));
	g *= 1.0 - step(0.93, s) * 0.18;
	COLOR = vec4(g, COLOR.a);
}
