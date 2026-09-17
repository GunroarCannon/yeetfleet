// Procedural soft gas-cloud billboard: a radial falloff masked by layered
// value noise, so a single quad reads as a wisp of gas rather than a
// hard-edged sprite. No image asset — consistent with this project's
// shader-driven, asset-free visual style (ship_part.gdshader,
// outline.gdshader). See modules/style/scripts/nebula_gas.gd, which arranges
// several of these per cloud cluster.
shader_type spatial;
// depth_test_disabled matters here, not just depth_draw_never: several huge,
// overlapping additive quads at similar world depth otherwise depth-test
// against each other inconsistently per pixel, which reads as a hard-edged
// blocky patchwork instead of a smooth blended cloud.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;

uniform vec4 core_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform vec4 edge_color : source_color = vec4(0.3, 0.2, 0.8, 1.0);
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform float noise_scale : hint_range(0.5, 8.0) = 3.0;
uniform float seed_offset = 0.0;
// Per-puff UV rotation so identical fbm patterns don't all sit at the same
// orientation — a cluster of same-noise quads facing the same way is what
// reads as a tiled, uniform patch rather than a wisp of gas.
uniform float rotation = 0.0;

varying vec2 uv_v;

// Godot 4 dropped the Godot-3-era `render_mode billboard;` keyword for
// spatial shaders — this is the standard replacement: swap the object's
// rotation for the inverse of the camera's, keeping the translation from
// MODEL_MATRIX, so the quad always faces the camera.
void vertex() {
	uv_v = UV;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed_offset) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Each octave rotates before it's sampled, so successive octaves' value-noise
// grids never stack axis-aligned on top of each other. A plain `p *= 2.02`
// fbm keeps every octave's grid lined up with the first, which is exactly
// what reads as a blocky, tiled patch instead of an organic wisp.
const mat2 OCTAVE_ROT = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * value_noise(p);
		p = OCTAVE_ROT * p * 2.02;
		amp *= 0.55;
	}
	return v;
}

void fragment() {
	float rc = cos(rotation);
	float rs = sin(rotation);
	vec2 centred = mat2(vec2(rc, rs), vec2(-rs, rc)) * (uv_v - 0.5);
	float r = length(centred) * 2.0;
	float radial = clamp(1.0 - r, 0.0, 1.0);
	// Domain-warp the sample point through a coarse noise layer so the cloud's
	// wisps curl and drift instead of reading as a stack of round blobs.
	vec2 warp = vec2(
		fbm(centred * noise_scale * 0.5 + seed_offset),
		fbm(centred * noise_scale * 0.5 - seed_offset)
	);
	float n = fbm(centred * noise_scale + warp * 0.7 + seed_offset);
	float alpha = radial * radial * n * density;
	// GL Compatibility's 8-bit backbuffer bands a smooth additive gradient
	// into visible steps once several huge soft quads stack — a per-pixel
	// dither on the alpha breaks the steps up into noise the eye reads as
	// smooth instead of a hard-edged patchwork. Interleaved-gradient-noise
	// form (not the vec2 hash() above): keeps every intermediate value small,
	// which mediump precision on mobile GL Compatibility drivers needs —
	// hash()'s large FRAGCOORD-scaled dot product would overflow mediump range.
	float dither = (fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5) * (1.0 / 48.0);
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp((1.0 - r) * 1.6, 0.0, 1.0) * n);
	// blend_add's own blend factors already scale ALBEDO by ALPHA at the
	// framebuffer stage — multiplying alpha into ALBEDO here too would square
	// an already-small value into near invisibility.
	ALBEDO = col;
	ALPHA = clamp(alpha + dither, 0.0, 1.0);
}
