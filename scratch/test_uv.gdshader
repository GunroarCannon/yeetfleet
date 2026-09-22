shader_type spatial;
render_mode unshaded;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	ALBEDO = vec3(UV.x, UV.y, 0.0);
}
