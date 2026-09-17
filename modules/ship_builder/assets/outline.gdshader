// Ink outline for hulls and rocks, driven by StyleProfile.outline_width/_color.
//
// Classic inverted-hull technique: draw a second, backface-culled-from-the-front
// copy of the same mesh pushed outward along its own normals, flat-coloured and
// unshaded. Chained onto the part shader as `next_pass` (see
// ShipMaterials.apply_outline), so every part that gets a part material gets the
// outline for free with no extra draw call wired up by hand.
//
// LowPoly gives every triangle its own unshared vertices with a true face
// normal (see lowpoly.gd), so pushing along NORMAL opens a small gap at each
// hard edge rather than mitring the corner. That reads fine at the width this
// dial allows (0-0.1m) and is what the art direction's "ink outline" line
// actually asks for -- a soft-cornered break at each panel edge, not a
// mathematically clean offset hull.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always, diffuse_lambert, specular_disabled;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.02;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
