// Safe atmosphere shader: additive rim glow, GL Compatibility friendly.
// Uses cull_back (default) so the sphere renders from outside like any
// normal mesh. The rim glow is calculated from the view angle — center
// is transparent, edges glow — giving the same limb-glow effect without
// the cull_front + depth_draw_never combo that causes black spheres on
// some GL Compatibility drivers.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, shadows_disabled, depth_draw_opaque;

uniform vec4 glow_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float glow_power : hint_range(0.5, 12.0) = 4.0;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.2;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float facing = abs(dot(normalize(v_world_normal), view_dir));
	// Rim: thin at edges (facing near 0), invisible at centre (facing near 1).
	float rim = pow(1.0 - facing, glow_power);
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(rim * glow_strength, 0.0, 1.0);
}
