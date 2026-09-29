// A black outline round the player's hull, drawn as a per-instance
// material_overlay on its part meshes (see FlightRoot._update_blast_outline):
// the mesh again, back faces only, pushed out along its normals by a fixed
// number of screen pixels, so it frames the ship the same at any zoom. The
// shell is also pushed a little away from the camera (push_m), so on a hull
// built of many small parts one part's shell never shows in front of the
// next part — only round the silhouette. Only attached while a bright blast
// is behind the ship, so it normally costs nothing.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, blend_mix;

uniform float width_px = 3.0;
uniform float push_m = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ink : source_color = vec4(0.02, 0.01, 0.04, 1.0);

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz += normalize(v.xyz) * push_m;
	vec4 clip = PROJECTION_MATRIX * v;
	vec3 n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	float l = length(dir);
	if (l > 0.00001) {
		clip.xy += dir / l * width_px / VIEWPORT_SIZE * 2.0 * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink.rgb;
	ALPHA = ink.a * strength;
}
