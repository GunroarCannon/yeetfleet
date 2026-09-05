// Planet atmosphere arc: a view-dependent additive rim, brightest where the
// surface normal turns away from the camera. Meant for a sphere slightly
// larger than the planet it wraps, with its front faces culled so only the
// limb — the edge — ever draws.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float glow_power : hint_range(0.5, 8.0) = 3.0;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float facing = dot(world_normal, view_dir);
	float rim = pow(clamp(1.0 - abs(facing), 0.0, 1.0), glow_power);

	ALBEDO = glow_color.rgb;
	ALPHA = clamp(rim * glow_strength, 0.0, 1.0);
}
