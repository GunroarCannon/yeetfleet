// Gravitational Lensing Shader for Event Horizon Singularity Cannon & Black Holes.
// Screen-space distortion spatial shader that bends the background starfield,
// nebulae, planets, and nearby ships around the event horizon.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.28;
uniform float event_horizon_radius : hint_range(0.0, 0.5) = 0.16;
uniform float photon_ring_radius : hint_range(0.0, 0.8) = 0.24;
uniform vec4 photon_ring_color : source_color = vec4(0.85, 0.45, 1.0, 1.0);
uniform vec4 accretion_color : source_color = vec4(1.0, 0.65, 0.25, 1.0);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	// Camera-facing billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 center_offset = v_uv - vec2(0.5);
	float dist = length(center_offset);

	if (dist > 0.495) {
		discard;
	}

	// Event horizon: light cannot escape, pure black singularity. Godot's
	// shader compiler rejects an early `return` from fragment(), so the rest
	// of the shader is skipped with an else instead.
	if (dist < event_horizon_radius) {
		ALBEDO = vec3(0.001, 0.0005, 0.002);
		ALPHA = 1.0;
	} else {
		// Einstein deflection: bend rays around the photon sphere
		vec2 bend_dir = normalize(center_offset);
		float deflection = (distortion_strength * 0.06) / max(dist - event_horizon_radius * 0.6, 0.015);
		vec2 warped_screen_uv = SCREEN_UV - bend_dir * deflection;

		vec4 bg_col = texture(screen_texture, warped_screen_uv);

		// Luminous photon ring / Einstein ring
		float ring_dist = abs(dist - photon_ring_radius);
		float ring_glow = exp(-ring_dist * 38.0) * 1.6;

		// Swirling inner accretion disk light
		float angle = atan(center_offset.y, center_offset.x);
		float swirl = 0.5 + 0.5 * sin(angle * 3.0 + TIME * 8.0);
		float accretion = smoothstep(photon_ring_radius * 1.5, event_horizon_radius, dist) * (0.3 + 0.4 * swirl);

		vec3 final_color = bg_col.rgb + photon_ring_color.rgb * ring_glow + accretion_color.rgb * accretion;
		ALBEDO = final_color;
		ALPHA = 1.0;
	}
}
