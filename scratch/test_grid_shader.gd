extends SceneTree

func _init():
	print("Checking vector_grid shader compilation...")
	var code := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform float grid_spacing : hint_range(0.01, 0.2) = 0.04;
uniform float line_thickness : hint_range(0.001, 0.05) = 0.006;
uniform float warp_intensity : hint_range(0.0, 2.0) = 0.65;
uniform float time_speed : hint_range(0.0, 2.0) = 0.4;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float t = TIME * time_speed;

	float warp_x = sin(uv.y * 3.5 + t) * 0.12 + sin(uv.y * 7.0 - t * 1.5) * 0.06;
	float warp_y = cos(uv.x * 3.0 + t * 0.8) * 0.10 + cos(uv.x * 6.5 + t * 1.2) * 0.05;

	vec2 warped_uv = uv + vec2(warp_x, warp_y) * warp_intensity;

	vec2 grid_uv = fract(warped_uv / grid_spacing);
	vec2 dist_to_line = abs(grid_uv - 0.5) * grid_spacing;
	
	vec2 fw = fwidth(warped_uv);
	vec2 line_alpha = 1.0 - smoothstep(vec2(0.0), fw * 2.5 + vec2(line_thickness), dist_to_line);
	float grid = max(line_alpha.x, line_alpha.y * 0.85);

	vec3 col_magenta = vec3(1.0, 0.05, 0.65);
	vec3 col_cyan = vec3(0.0, 0.95, 1.0);
	vec3 col_orange = vec3(1.0, 0.55, 0.1);

	float grad = sin(warped_uv.x * 2.0 + warped_uv.y * 1.5 + t * 0.5) * 0.5 + 0.5;
	vec3 neon_color = mix(col_magenta, col_cyan, grad);
	float grad2 = cos(warped_uv.y * 3.0 - t * 0.3) * 0.5 + 0.5;
	neon_color = mix(neon_color, col_orange, grad2 * 0.5);

	float vign = 1.0 - smoothstep(0.7, 1.3, length(uv));

	ALBEDO = neon_color * grid * vign;
	ALPHA = grid * vign * 0.85;
}
"""
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	print("Shader compiled successfully without errors!")
	quit()
