// Drag preview material.
//
// Shows the silhouette of a part before it is committed to a socket. Edge-lit and
// transparent so it reads as "not yet real" while still communicating shape, and
// tinted from a uniform so the same material serves valid (cyan) and invalid
// (amber) placements -- a colour pair chosen to stay distinguishable for the most
// common forms of colour blindness.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 ghost_color : source_color = vec4(0.22, 0.75, 1.0, 1.0);
uniform float edge_power : hint_range(0.5, 8.0) = 2.2;
uniform float body_strength : hint_range(0.0, 1.0) = 0.10;
uniform float edge_strength : hint_range(0.0, 2.0) = 0.85;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), edge_power);
	ALBEDO = ghost_color.rgb * (body_strength + fresnel * edge_strength);
	ALPHA = 1.0;
}
