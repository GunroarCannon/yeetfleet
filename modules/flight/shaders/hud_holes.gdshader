// The tutorial's hand and bands: faded where they pass over a HUD control,
// so the button under a pointing hand still reads. The rects are in screen
// UV (0..1), filled by FlightTutorial from the HUD's controls.
shader_type canvas_item;

uniform vec4 holes[24];
uniform int hole_count = 0;
uniform float hole_alpha : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 p = SCREEN_UV;
	for (int i = 0; i < 24; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 r = holes[i];
		if (p.x > r.x && p.y > r.y && p.x < r.z && p.y < r.w) {
			COLOR.a *= hole_alpha;
			break;
		}
	}
}
