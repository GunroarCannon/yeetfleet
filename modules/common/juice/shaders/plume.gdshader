// Engine exhaust: a hot near-white core, a coloured outer cone with heat
// wobble, and length/brightness driven by throttle and boost. Meant for a
// cone or cylinder mesh with V running 0 (nozzle) to 1 (tail) along its length.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 exhaust_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float throttle : hint_range(0.0, 1.0) = 0.0;
uniform float boost : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

void fragment() {
	float along = UV.y;
	float radial = abs(UV.x - 0.5) * 2.0;

	float wobble = sin((along * 18.0) + TIME * 22.0 + time_offset) * 0.05 * (1.0 - along);
	float core_mask = smoothstep(0.5, 0.0, radial + wobble) * smoothstep(1.0, 0.0, along);
	float outer_mask = smoothstep(1.0, 0.15, radial) * smoothstep(1.0, 0.0, along * 0.9);

	vec3 color = mix(exhaust_color.rgb, core_color.rgb, core_mask);
	float alpha = clamp(outer_mask * mix(0.35, 1.0, throttle) + core_mask, 0.0, 1.0);
	alpha *= mix(1.0, 1.6, boost);

	ALBEDO = color;
	ALPHA = alpha;
}
