// A see-through blue shield bubble: faint in the middle, bright at the rim
// (fresnel), with slow bands drifting over it. [param flash] brightens it
// for a moment when it takes a hit; [param fade] runs it out. Unshaded and
// no depth write, so it never hides the hull inside it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.72, 1.0, 1.0);
uniform float base_alpha = 0.07;
uniform float rim_alpha = 0.6;
uniform float band_alpha = 0.05;
uniform float flash = 0.0;
uniform float fade = 1.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.6);
	float bands = 0.5 + 0.5 * sin(UV.y * 48.0 - TIME * 2.5);
	ALBEDO = mix(tint.rgb, vec3(1.0), clamp(rim * 0.35 + flash * 0.6, 0.0, 1.0));
	ALPHA = clamp(base_alpha + rim * rim_alpha + bands * band_alpha + flash * 0.25, 0.0, 1.0) * fade;
}
